import AppKit
import ContextAssistantCore
import Foundation
import ScreenCaptureKit

enum AssistPhase: Equatable {
    case idle
    case capturing
    case recognizing
    case thinking
    case streaming
    case failed
}

@MainActor
final class AppModel: ObservableObject {
    @Published var permissionGranted = false
    @Published var windows: [ShareableWindowInfo] = []
    @Published var isLoadingWindows = false
    @Published var listError: String?
    @Published var selectedWindowID: UInt32? {
        didSet {
            if selectedWindowID != nil {
                pickerFilter = nil
            }
            updateSelectionSummary()
        }
    }
    @Published var selectionSummary = "No window selected"
    @Published var phase: AssistPhase = .idle
    @Published var statusText = "Choose a window, then ask."
    @Published var errorBanner: String?
    @Published var answer = ""
    @Published var answerIsCached = false
    @Published var question: String
    @Published var history: [ConversationTurn] = []
    @Published var selectedHistoryID: UUID?
    @Published var isCompact: Bool
    @Published var opacity: Double
    @Published var hasAPIKey = false
    @Published var showOwnWindows = false
    @Published var baseURL: String
    @Published var modelName: String
    @Published var systemPrompt: String
    @Published var hotKey = HotKeySpec.defaultSpec
    @Published var isRecordingHotkey = false
    @Published var hotKeyError: String?
    @Published var positionPreset: OverlayPreset
    @Published var rateCapacity: Double
    @Published var rateRefillPerSecond: Double
    @Published var keyDraft = ""

    let overlay = OverlayController()

    private let cache = ResponseCache(capacity: 32)
    private let historyStore = HistoryStore()
    private var bucket = TokenBucket(capacity: 4, refillPerSecond: 0.5)
    private var bucketCapacity: Double = -1
    private var bucketRefill: Double = -1
    private let client: LLMClient
    private let hotKeyCenter = HotKeyCenter()
    private var inFlight: Task<Void, Never>?
    private var pickerFilter: SCContentFilter?
    private var pickerSummary: String?
    private var previousOCR: String?
    private var previousQuestion: String?
    private var previousAnswer: String?
    private var hotKeyMonitor: Any?
    private let defaults = UserDefaults.standard

    var isBusy: Bool {
        switch phase {
        case .capturing, .recognizing, .thinking, .streaming:
            return true
        case .idle, .failed:
            return false
        }
    }

    var phaseTitle: String {
        switch phase {
        case .idle: return selectedHistoryID == nil ? "Ready" : "Earlier answer"
        case .capturing: return "Capturing window"
        case .recognizing: return "Reading text"
        case .thinking: return "Asking"
        case .streaming: return "Answer"
        case .failed: return "Needs attention"
        }
    }

    var displayedAnswer: String {
        if let selectedHistoryID, let turn = history.first(where: { $0.id == selectedHistoryID }) {
            return turn.assistantResponse
        }
        return answer
    }

    var visibleWindows: [ShareableWindowInfo] {
        guard !showOwnWindows, let bundleID = Bundle.main.bundleIdentifier else { return windows }
        return windows.filter { $0.bundleIdentifier != bundleID }
    }

    var baseURLWarning: String? {
        guard let url = URL(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme == "http" else {
            return nil
        }
        let host = url.host ?? ""
        if host == "localhost" || host == "127.0.0.1" || host == "::1" {
            return nil
        }
        return "This base URL is not encrypted. Use HTTPS unless the server is one you trust."
    }

    init() {
        let defaults = UserDefaults.standard
        question = defaults.string(forKey: Keys.question) ?? DefaultPrompts.defaultQuestion
        isCompact = defaults.object(forKey: Keys.compact) as? Bool ?? false
        opacity = defaults.object(forKey: Keys.opacity) as? Double ?? 1
        baseURL = defaults.string(forKey: Keys.baseURL) ?? "https://api.openai.com/v1"
        modelName = defaults.string(forKey: Keys.model) ?? "gpt-4o-mini"
        systemPrompt = defaults.string(forKey: Keys.systemPrompt) ?? DefaultPrompts.system
        positionPreset = OverlayPreset(rawValue: defaults.string(forKey: Keys.preset) ?? "") ?? .topTrailing
        rateCapacity = defaults.object(forKey: Keys.rateCapacity) as? Double ?? 4
        rateRefillPerSecond = defaults.object(forKey: Keys.rateRefill) as? Double ?? 0.5
        if let keyCode = defaults.object(forKey: Keys.hotKeyCode) as? Int,
           let modifiers = defaults.object(forKey: Keys.hotKeyModifiers) as? Int {
            hotKey = HotKeySpec(keyCode: UInt32(keyCode), modifiers: UInt32(modifiers))
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 45
        configuration.timeoutIntervalForResource = 180
        client = LLMClient(session: URLSession(configuration: configuration))
        overlay.install(content: OverlayView(model: self))
        overlay.setOpacity(min(1, max(0.55, opacity)))
        history = historyStore.load()
        hotKeyCenter.onPress = { [weak self] in
            self?.ask(bypassCache: false)
        }
        registerHotKey()
        refreshPermission()
        hasAPIKey = (try? KeychainStore.load())?.isEmpty == false
    }

    func refreshPermission() {
        permissionGranted = PermissionCenter.isGranted
    }

    func requestPermission() {
        _ = PermissionCenter.requestAccess()
        refreshPermission()
    }

    func openPermissionSettings() {
        PermissionCenter.openSettings()
    }

    func reloadWindows() {
        guard !isLoadingWindows else { return }
        isLoadingWindows = true
        listError = nil
        Task {
            do {
                let loaded = try await WindowCatalog.windows()
                windows = loaded
                refreshPermission()
                if permissionGranted == false {
                    permissionGranted = true
                }
                updateSelectionSummary()
            } catch {
                listError = error.localizedDescription
                AssistantLog.capture.error("Window list failed: \(error.localizedDescription, privacy: .public)")
                if let failure = error as? CaptureFailure, failure.isTCC {
                    permissionGranted = false
                }
            }
            isLoadingWindows = false
        }
    }

    func useSystemPicker() {
        Task {
            statusText = "Choose one window in the system picker."
            let filter = await SystemWindowPicker.shared.pickSingleWindow()
            guard let filter else {
                statusText = "Picker cancelled."
                return
            }
            pickerFilter = filter
            pickerSummary = "Window chosen in the system picker"
            selectedWindowID = nil
            selectionSummary = pickerSummary ?? selectionSummary
            statusText = "System picker selection is ready."
            AssistantLog.capture.info("User confirmed a window in SCContentSharingPicker")
        }
    }

    func ask(bypassCache: Bool) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorBanner = "Type a question first."
            phase = .failed
            revealOverlay()
            return
        }
        errorBanner = nil
        selectedHistoryID = nil
        inFlight?.cancel()
        revealOverlay()
        inFlight = Task { [weak self] in
            await self?.run(question: trimmed, bypassCache: bypassCache)
        }
    }

    func cancel() {
        inFlight?.cancel()
        if isBusy {
            phase = .idle
            statusText = "Cancelled."
        }
    }

    func cancelOrHide() {
        if isBusy {
            cancel()
        } else {
            hideOverlay()
        }
    }

    func hideOverlay() {
        overlay.hide()
    }

    func setOpacity(_ value: Double) {
        opacity = min(1, max(0.55, value))
        overlay.setOpacity(opacity)
        persist()
    }

    func setCompact(_ compact: Bool) {
        isCompact = compact
        overlay.setCompact(compact)
        persist()
    }

    func applyPreset(_ preset: OverlayPreset) {
        positionPreset = preset
        overlay.place(preset)
        revealOverlay()
        persist()
    }

    func saveAPIKey() {
        let secret = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !secret.isEmpty else { return }
        do {
            try KeychainStore.save(secret)
            keyDraft = ""
            hasAPIKey = true
            errorBanner = nil
            statusText = "API key saved in the Keychain."
        } catch {
            errorBanner = error.localizedDescription
            phase = .failed
        }
    }

    func deleteAPIKey() {
        do {
            try KeychainStore.delete()
            hasAPIKey = false
            keyDraft = ""
            statusText = "API key removed from the Keychain."
        } catch {
            errorBanner = error.localizedDescription
        }
    }

    func resetSystemPrompt() {
        systemPrompt = DefaultPrompts.system
        persist()
    }

    func clearHistory() {
        history = []
        selectedHistoryID = nil
        previousOCR = nil
        previousQuestion = nil
        previousAnswer = nil
        do {
            try historyStore.save([])
        } catch {
            errorBanner = error.localizedDescription
        }
    }

    func showOlderHistory() {
        guard !history.isEmpty else { return }
        if let selectedHistoryID, let index = history.firstIndex(where: { $0.id == selectedHistoryID }) {
            let newerIndex = max(0, index - 1)
            self.selectedHistoryID = history[newerIndex].id
        } else {
            selectedHistoryID = history.last?.id
        }
    }

    func showNewerHistory() {
        guard let selectedHistoryID, let index = history.firstIndex(where: { $0.id == selectedHistoryID }) else {
            return
        }
        let next = index + 1
        if next >= history.count {
            self.selectedHistoryID = nil
        } else {
            self.selectedHistoryID = history[next].id
        }
    }

    func beginHotkeyRecording() {
        isRecordingHotkey = true
        hotKeyCenter.unregister()
        hotKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 {
                self.finishHotkeyRecording(keep: self.hotKey)
                return nil
            }
            let modifiers = HotKeySpec.carbonModifiers(from: event.modifierFlags.intersection(.deviceIndependentFlagsMask))
            if modifiers == 0 || HotKeySpec.isModifierOnly(UInt32(event.keyCode)) {
                return nil
            }
            self.finishHotkeyRecording(keep: HotKeySpec(keyCode: UInt32(event.keyCode), modifiers: modifiers))
            return nil
        }
    }

    func persist() {
        defaults.set(question, forKey: Keys.question)
        defaults.set(isCompact, forKey: Keys.compact)
        defaults.set(opacity, forKey: Keys.opacity)
        defaults.set(baseURL, forKey: Keys.baseURL)
        defaults.set(modelName, forKey: Keys.model)
        defaults.set(systemPrompt, forKey: Keys.systemPrompt)
        defaults.set(positionPreset.rawValue, forKey: Keys.preset)
        defaults.set(rateCapacity, forKey: Keys.rateCapacity)
        defaults.set(rateRefillPerSecond, forKey: Keys.rateRefill)
        defaults.set(Int(hotKey.keyCode), forKey: Keys.hotKeyCode)
        defaults.set(Int(hotKey.modifiers), forKey: Keys.hotKeyModifiers)
    }

    private func finishHotkeyRecording(keep spec: HotKeySpec) {
        if let hotKeyMonitor {
            NSEvent.removeMonitor(hotKeyMonitor)
            self.hotKeyMonitor = nil
        }
        hotKey = spec
        isRecordingHotkey = false
        registerHotKey()
        persist()
    }

    private func registerHotKey() {
        hotKeyCenter.register(hotKey)
        hotKeyError = hotKeyCenter.lastError
    }

    private func revealOverlay() {
        if !overlay.panel.isVisible {
            overlay.place(positionPreset)
        }
        overlay.setOpacity(opacity)
        overlay.show()
    }

    private func updateSelectionSummary() {
        if let selectedWindowID, let window = windows.first(where: { $0.windowID == selectedWindowID }) {
            selectionSummary = "\(window.displayTitle) — \(window.ownerName)"
            return
        }
        if pickerFilter != nil, let pickerSummary {
            selectionSummary = pickerSummary
            return
        }
        selectionSummary = "No window selected"
    }

    private func currentBucket() -> TokenBucket {
        if bucketCapacity != rateCapacity || bucketRefill != rateRefillPerSecond {
            bucket = TokenBucket(capacity: rateCapacity, refillPerSecond: rateRefillPerSecond)
            bucketCapacity = rateCapacity
            bucketRefill = rateRefillPerSecond
        }
        return bucket
    }

    private func run(question: String, bypassCache: Bool) async {
        phase = .capturing
        statusText = "Capturing the selected window."
        answerIsCached = false
        do {
            try Task.checkCancellation()
            let image = try await captureSelectedImage()
            try Task.checkCancellation()
            let verdict = FrameContent.assess(PixelSampler.samples(from: image))
            if case .blankOrUniform(let reason) = verdict {
                AssistantLog.capture.error("Blank frame: \(reason, privacy: .public)")
                throw CaptureFailure.blankFrame(reason: reason)
            }
            phase = .recognizing
            statusText = "Reading text in the window."
            let recognized = try await recognize(image)
            try Task.checkCancellation()
            let trimmedOCR = recognized.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedOCR.isEmpty else {
                phase = .failed
                statusText = "No text was recognized."
                errorBanner = "Vision did not find text in that window. If the window is protected, the frame can also come back blank and the capture stops."
                return
            }
            let key = CacheKey.make(ocrText: trimmedOCR, question: question)
            let cached = await cache.value(for: key)
            let decision = ResponseReusePlanner.decide(
                ocrText: trimmedOCR,
                question: question,
                previousOCR: previousOCR,
                previousQuestion: previousQuestion,
                hasCache: cached != nil,
                bypassCache: bypassCache
            )
            switch decision {
            case .useCache:
                answer = cached?.response ?? ""
                answerIsCached = true
                phase = .idle
                statusText = "Used the saved answer for this text."
                remember(ocr: trimmedOCR, question: question, answer: answer)
            case .usePreviousAnswer:
                answer = previousAnswer ?? ""
                answerIsCached = true
                phase = .idle
                statusText = "The window text looks unchanged, so the previous answer is still here."
            case .requestModel:
                try await streamModel(ocr: trimmedOCR, question: question, cacheKey: key)
            }
        } catch is CancellationError {
            phase = .idle
            statusText = "Cancelled."
        } catch {
            if Task.isCancelled {
                phase = .idle
                statusText = "Cancelled."
                return
            }
            let failure = (error as? CaptureFailure) ?? CaptureFailure.classify(error)
            phase = .failed
            errorBanner = failure.description
            statusText = "Capture stopped."
            AssistantLog.capture.error("Pipeline stopped: \(failure.description, privacy: .public)")
        }
    }

    private func captureSelectedImage() async throws -> CGImage {
        if let selectedWindowID {
            AssistantLog.capture.info("Capturing window id \(selectedWindowID, privacy: .public)")
            return try await ScreenshotCapture.capture(windowID: selectedWindowID)
        }
        if let pickerFilter {
            AssistantLog.capture.info("Capturing the system-picker filter")
            return try await ScreenshotCapture.capture(filter: pickerFilter)
        }
        throw CaptureFailure.underlying("Choose a window in the list or with the system picker first.")
    }

    private func recognize(_ image: CGImage) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            try OCRService.recognize(image)
        }.value
    }

    private func streamModel(ocr: String, question: String, cacheKey: String) async throws {
        let apiKey = try KeychainStore.load() ?? ""
        guard let url = URL(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw CaptureFailure.underlying("The base URL is not valid.")
        }
        let host = url.host ?? ""
        let local = host == "localhost" || host == "127.0.0.1" || host == "::1"
        if apiKey.isEmpty && !local {
            throw CaptureFailure.underlying("Save an API key in the Keychain, or point the base URL at a local server.")
        }
        let decision = await currentBucket().tryConsume()
        guard decision.allowed else {
            let seconds = Int(decision.retryAfter.rounded(.up))
            throw CaptureFailure.underlying("Rate limit reached. Try again in about \(max(seconds, 1)) seconds.")
        }
        phase = .thinking
        statusText = "Asking \(modelName)."
        answer = ""
        let messages = PromptBuilder(systemPrompt: systemPrompt).build(
            history: history,
            windowTitle: selectionSummary,
            ownerName: windows.first(where: { $0.windowID == selectedWindowID })?.ownerName ?? "Selected window",
            ocrText: ocr,
            userQuestion: question
        )
        let configuration = LLMConfiguration(baseURL: url, model: modelName, apiKey: apiKey)
        var streamed = ""
        do {
            for try await chunk in client.stream(configuration: configuration, messages: messages) {
                try Task.checkCancellation()
                if phase != .streaming {
                    phase = .streaming
                    statusText = "Answer is streaming."
                }
                streamed += chunk
                answer = streamed
            }
        } catch let error as LLMClientError {
            AssistantLog.llm.error("Model request failed: \(String(describing: error), privacy: .public)")
            throw CaptureFailure.underlying(Self.describe(error))
        }
        try Task.checkCancellation()
        guard !streamed.isEmpty else {
            throw CaptureFailure.underlying("The model returned an empty answer.")
        }
        await cache.insert(streamed, for: cacheKey)
        remember(ocr: ocr, question: question, answer: streamed)
        let turn = ConversationTurn(
            windowTitle: selectionSummary,
            ownerName: windows.first(where: { $0.windowID == selectedWindowID })?.ownerName ?? "",
            ocrHash: ContentFingerprint.make(ocr).hash,
            ocrExcerpt: HistoryTrimmer.excerpt(ocr, limit: 2_000),
            userQuestion: question,
            assistantResponse: streamed
        )
        history.append(turn)
        history = HistoryTrimmer.trim(history, maxTurns: 30, maxCharacters: 80_000)
        do {
            try historyStore.save(history)
        } catch {
            AssistantLog.store.error("Could not save history: \(error.localizedDescription, privacy: .public)")
        }
        phase = .idle
        statusText = "Answer ready."
        persist()
    }

    private func remember(ocr: String, question: String, answer: String) {
        previousOCR = ocr
        previousQuestion = question
        previousAnswer = answer
    }

    private static func describe(_ error: LLMClientError) -> String {
        switch error {
        case .badURL:
            return "The base URL is not a valid http or https URL."
        case .http(let status, let body):
            let detail = body.isEmpty ? "" : " \(body.prefix(240))"
            return "The model server returned HTTP \(status).\(detail)"
        case .stream(let message):
            return message
        }
    }
}

private enum Keys {
    static let question = "assistant.question"
    static let compact = "assistant.compact"
    static let opacity = "assistant.opacity"
    static let baseURL = "assistant.baseURL"
    static let model = "assistant.model"
    static let systemPrompt = "assistant.systemPrompt"
    static let preset = "assistant.preset"
    static let rateCapacity = "assistant.rateCapacity"
    static let rateRefill = "assistant.rateRefill"
    static let hotKeyCode = "assistant.hotKeyCode"
    static let hotKeyModifiers = "assistant.hotKeyModifiers"
}

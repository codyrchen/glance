import AppKit
import SwiftUI

@main
struct CaptureLabApp: App {
    @StateObject private var model = LabModel()

    var body: some Scene {
        Window("Capture Lab", id: "lab") {
            LabRootView(model: model)
                .frame(minWidth: 720, minHeight: 520)
                .onAppear { model.lockMainWindowSharing() }
        }
        .defaultSize(width: 860, height: 600)
    }
}

@MainActor
final class LabModel: ObservableObject {
    @Published var samples: [LabSample] = []
    private var controllers: [Int: LabWindowController] = [:]
    private var nextIndex = 1

    func addSample() {
        let index = nextIndex
        nextIndex += 1
        let controller = LabWindowController(index: index)
        controller.onUpdate = { [weak self] in
            self?.refresh()
        }
        controllers[index] = controller
        controller.show()
        refresh()
    }

    func close(_ index: Int) {
        controllers[index]?.close()
        controllers[index] = nil
        refresh()
    }

    func setSharing(_ value: LabSharing, index: Int) {
        controllers[index]?.setSharing(value)
        refresh()
    }

    func setLevel(_ value: LabLevel, index: Int) {
        controllers[index]?.setLevel(value)
        refresh()
    }

    func setBehavior(_ behavior: LabBehavior, enabled: Bool, index: Int) {
        controllers[index]?.setBehavior(behavior, enabled: enabled)
        refresh()
    }

    func lockMainWindowSharing() {
        for window in NSApp.windows where !(window is LabSampleWindow) {
            window.sharingType = .readOnly
        }
    }

    private func refresh() {
        samples = controllers.keys.sorted().compactMap { index in
            controllers[index]?.snapshot()
        }
    }
}

enum LabSharing: String, CaseIterable, Identifiable {
    case readOnly
    case none

    var id: String { rawValue }
    var title: String { self == .readOnly ? "readOnly" : "none" }

    var nsValue: NSWindow.SharingType {
        switch self {
        case .readOnly: return .readOnly
        case .none: return .none
        }
    }

    static func from(_ value: NSWindow.SharingType) -> LabSharing {
        value == .none ? .none : .readOnly
    }
}

enum LabLevel: String, CaseIterable, Identifiable {
    case normal
    case floating
    case statusBar

    var id: String { rawValue }
    var title: String {
        switch self {
        case .normal: return "Normal"
        case .floating: return "Floating"
        case .statusBar: return "Status bar"
        }
    }

    var nsValue: NSWindow.Level {
        switch self {
        case .normal: return .normal
        case .floating: return .floating
        case .statusBar: return .statusBar
        }
    }
}

enum LabBehavior: String, CaseIterable, Identifiable {
    case canJoinAllSpaces
    case stationary
    case transient
    case ignoresCycle
    case fullScreenAuxiliary
    case managed

    var id: String { rawValue }
    var title: String {
        switch self {
        case .canJoinAllSpaces: return "Join all spaces"
        case .stationary: return "Stationary"
        case .transient: return "Transient"
        case .ignoresCycle: return "Ignore cycle"
        case .fullScreenAuxiliary: return "Full screen auxiliary"
        case .managed: return "Managed"
        }
    }

    var nsValue: NSWindow.CollectionBehavior {
        switch self {
        case .canJoinAllSpaces: return .canJoinAllSpaces
        case .stationary: return .stationary
        case .transient: return .transient
        case .ignoresCycle: return .ignoresCycle
        case .fullScreenAuxiliary: return .fullScreenAuxiliary
        case .managed: return .managed
        }
    }
}

struct LabSample: Identifiable {
    var index: Int
    var windowID: Int
    var sharing: LabSharing
    var level: LabLevel
    var behaviors: Set<LabBehavior>
    var id: Int { index }
}

final class LabSampleWindow: NSPanel {
    let sampleIndex: Int

    init(index: Int) {
        self.sampleIndex = index
        super.init(
            contentRect: NSRect(x: 80 + CGFloat(index * 24), y: 80 + CGFloat(index * 24), width: 520, height: 320),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        title = "Capture Lab sample \(index)"
        isFloatingPanel = false
        level = .normal
        sharingType = .readOnly
        isReleasedWhenClosed = false
        collectionBehavior = [.managed]
    }
}

@MainActor
final class LabWindowController: NSWindowController {
    let sampleIndex: Int
    var onUpdate: (() -> Void)?
    private var behaviors: Set<LabBehavior> = [.managed]
    private var sharing: LabSharing = .readOnly
    private var levelChoice: LabLevel = .normal

    init(index: Int) {
        self.sampleIndex = index
        let window = LabSampleWindow(index: index)
        super.init(window: window)
        window.contentViewController = NSHostingController(
            rootView: LabSampleView(index: index, windowID: 0, sharingLabel: "sharingType .readOnly")
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func show() {
        guard let window = window as? LabSampleWindow else { return }
        showWindow(nil)
        window.orderFrontRegardless()
        refreshContent()
        onUpdate?()
        Task { @MainActor [weak self] in
            self?.refreshContent()
            self?.onUpdate?()
        }
    }

    func setSharing(_ value: LabSharing) {
        guard Bundle.main.bundleIdentifier == "dev.codychen.CaptureLab" else { return }
        guard let window = window as? LabSampleWindow else { return }
        sharing = value
        window.sharingType = value.nsValue
        refreshContent()
        onUpdate?()
    }

    func setLevel(_ value: LabLevel) {
        guard let window = window as? LabSampleWindow else { return }
        levelChoice = value
        window.level = value.nsValue
        onUpdate?()
    }

    func setBehavior(_ behavior: LabBehavior, enabled: Bool) {
        guard let window = window as? LabSampleWindow else { return }
        if enabled {
            behaviors.insert(behavior)
        } else {
            behaviors.remove(behavior)
        }
        window.collectionBehavior = behaviors.reduce(into: NSWindow.CollectionBehavior()) { partial, item in
            partial.insert(item.nsValue)
        }
        onUpdate?()
    }

    func snapshot() -> LabSample {
        let windowID = window?.windowNumber ?? 0
        return LabSample(
            index: sampleIndex,
            windowID: windowID,
            sharing: sharing,
            level: levelChoice,
            behaviors: behaviors
        )
    }

    private func refreshContent() {
        let windowID = window?.windowNumber ?? 0
        let label = "sharingType .\(sharing.rawValue)"
        window?.contentViewController = NSHostingController(
            rootView: LabSampleView(index: sampleIndex, windowID: windowID, sharingLabel: label)
        )
    }
}

struct LabSampleView: View {
    var index: Int
    var windowID: Int
    var sharingLabel: String

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                Color(red: 0.93, green: 0.42, blue: 0.14)
                Color(red: 0.12, green: 0.45, blue: 0.82)
                Color(red: 0.16, green: 0.65, blue: 0.38)
                Color(red: 0.95, green: 0.82, blue: 0.18)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("CAPTURE LAB SAMPLE \(index)")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text("If you can read this sentence, the frame is not blank.")
                    .font(.title3)
                Text("Window ID \(windowID)")
                    .font(.system(.title3, design: .monospaced))
                Text(sharingLabel)
                    .font(.headline)
            }
            .padding(20)
            .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

struct LabRootView: View {
    @ObservedObject var model: LabModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Capture Lab")
                .font(.title.weight(.semibold))
            Text("These controls call public NSWindow properties on windows this app creates. They do not change other apps. Open Capture Diagnostics, select a sample window, and compare the JSON. A blank result is the measurement. Nothing here tries to recover pixels.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("New test window") { model.addSample() }
                    .buttonStyle(.borderedProminent)
                Text("The main Capture Lab window stays sharingType .readOnly.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if model.samples.isEmpty {
                ContentUnavailableView {
                    Label("No sample windows", systemImage: "macwindow.badge.plus")
                } description: {
                    Text("Create a sample, set its sharing type, then point Capture Diagnostics at its window ID.")
                }
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(model.samples) { sample in
                            sampleCard(sample)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(20)
    }

    private func sampleCard(_ sample: LabSample) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Sample \(sample.index)")
                    .font(.headline)
                Spacer()
                Text("windowNumber \(sample.windowID)")
                    .font(.system(.body, design: .monospaced))
                Button("Close") { model.close(sample.index) }
            }
            Picker("sharingType", selection: Binding(
                get: { sample.sharing },
                set: { model.setSharing($0, index: sample.index) }
            )) {
                ForEach(LabSharing.allCases) { sharing in
                    Text(sharing.title).tag(sharing)
                }
            }
            .pickerStyle(.segmented)
            Picker("Window level", selection: Binding(
                get: { sample.level },
                set: { model.setLevel($0, index: sample.index) }
            )) {
                ForEach(LabLevel.allCases) { level in
                    Text(level.title).tag(level)
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), alignment: .leading)], alignment: .leading) {
                ForEach(LabBehavior.allCases) { behavior in
                    Toggle(behavior.title, isOn: Binding(
                        get: { sample.behaviors.contains(behavior) },
                        set: { model.setBehavior(behavior, enabled: $0, index: sample.index) }
                    ))
                }
            }
            .font(.callout)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }
}

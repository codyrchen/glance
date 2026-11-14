import GlanceCore
import SwiftUI

struct ControlView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HSplitView {
            windowColumn
                .frame(minWidth: 300, idealWidth: 360, maxWidth: 460)
            settingsColumn
                .frame(minWidth: 420)
        }
        .frame(minWidth: 860, minHeight: 640)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            model.refreshPermission()
        }
        .onChange(of: model.baseURL) { _, _ in model.persist() }
        .onChange(of: model.modelName) { _, _ in model.persist() }
        .onChange(of: model.systemPrompt) { _, _ in model.persist() }
        .onChange(of: model.question) { _, _ in model.persist() }
        .onChange(of: model.rateCapacity) { _, _ in model.persist() }
        .onChange(of: model.rateRefillPerSecond) { _, _ in model.persist() }
    }

    private var windowColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Glance")
                    .font(.title2.weight(.semibold))
                Text("Help for one window you choose. The shortcut captures that window only.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            permissionCard
            HStack {
                Button(model.isLoadingWindows ? "Loading…" : "Refresh windows") {
                    model.reloadWindows()
                }
                .disabled(model.isLoadingWindows)
                Button("System picker") {
                    model.useSystemPicker()
                }
                Spacer()
                Toggle("Include this app", isOn: $model.showOwnWindows)
                    .toggleStyle(.checkbox)
                    .font(.caption)
            }
            if model.isLoadingWindows && model.windows.isEmpty {
                ProgressView("Reading the window list…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let listError = model.listError, model.windows.isEmpty {
                ContentUnavailableView {
                    Label("Window list unavailable", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(listError)
                } actions: {
                    Button("Try again") { model.reloadWindows() }
                }
            } else if model.visibleWindows.isEmpty {
                ContentUnavailableView {
                    Label("No shareable windows", systemImage: "macwindow")
                } description: {
                    Text("Grant Screen Recording, then refresh. Only windows macOS exposes are listed.")
                }
            } else {
                List(model.visibleWindows, selection: $model.selectedWindowID) { window in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(window.displayTitle)
                            .lineLimit(1)
                        Text("\(window.ownerName) · \(window.windowID)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .tag(window.windowID)
                    .padding(.vertical, 2)
                }
                .listStyle(.inset)
            }
            Text(model.selectionSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack {
                Button("Ask") { model.ask(bypassCache: false) }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                    .buttonStyle(.borderedProminent)
                Button("Show answer panel") { model.applyPreset(model.positionPreset) }
            }
        }
        .padding(16)
    }

    private var permissionCard: some View {
        Group {
            if model.permissionGranted {
                Label("Screen Recording is on for this app.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Screen Recording is off.", systemImage: "lock.fill")
                        .font(.callout.weight(.semibold))
                    Text("macOS only shares windows after you allow it. System Settings may ask again later; that prompt is the permission check, and this app waits for it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Open Settings") { model.openPermissionSettings() }
                        Button("Request access") { model.requestPermission() }
                        Button("Check again") { model.refreshPermission() }
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var settingsColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                statusBlock
                modelBlock
                shortcutBlock
                appearanceBlock
                memoryBlock
            }
            .padding(18)
            .frame(maxWidth: 640, alignment: .leading)
        }
    }

    private var statusBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(model.phaseTitle, systemImage: model.isBusy ? "viewfinder.circle.fill" : "viewfinder")
                .font(.headline)
            Text(model.statusText)
                .font(.callout)
                .foregroundStyle(.secondary)
            if let error = model.errorBanner {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
            Text("The answer panel uses sharing type readOnly, so it appears in screenshots and screen sharing.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var modelBlock: some View {
        GroupBox("Model") {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Base URL", text: $model.baseURL)
                    .textFieldStyle(.roundedBorder)
                Text("API root, for example https://api.openai.com/v1 or http://127.0.0.1:11434/v1")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let warning = model.baseURLWarning {
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                TextField("Model", text: $model.modelName)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    SecureField(model.hasAPIKey ? "Replace the saved key" : "API key", text: $model.keyDraft)
                        .textFieldStyle(.roundedBorder)
                    Button("Save to Keychain") { model.saveAPIKey() }
                        .disabled(model.keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                HStack {
                    Text(model.hasAPIKey ? "A key is stored in the login Keychain." : "No key saved. A local server can be used without one.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if model.hasAPIKey {
                        Button("Remove key") { model.deleteAPIKey() }
                    }
                }
                DisclosureGroup("System prompt") {
                    TextEditor(text: $model.systemPrompt)
                        .font(.body)
                        .frame(minHeight: 90)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2)))
                    Button("Reset prompt") { model.resetSystemPrompt() }
                }
            }
            .padding(4)
        }
    }

    private var shortcutBlock: some View {
        GroupBox("Shortcut") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(model.hotKey.display)
                        .font(.title3.monospaced())
                    Spacer()
                    Button(model.isRecordingHotkey ? "Press a shortcut…" : "Change shortcut") {
                        model.beginHotkeyRecording()
                    }
                }
                Text("Use at least one modifier. Escape cancels recording. The shortcut works while Glance is running.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let hotKeyError = model.hotKeyError {
                    Text(hotKeyError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                TextField("Question the shortcut sends", text: $model.question, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
            }
            .padding(4)
        }
    }

    private var appearanceBlock: some View {
        GroupBox("Panel") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Opacity")
                    Slider(value: Binding(
                        get: { model.opacity },
                        set: { model.setOpacity($0) }
                    ), in: 0.55...1)
                    Text("\(Int(model.opacity * 100))%")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
                Text("Opacity stays at 55% or more so the panel cannot be faded out of view.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Position", selection: Binding(
                    get: { model.positionPreset },
                    set: { model.applyPreset($0) }
                )) {
                    ForEach(OverlayPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
                Toggle("Start compact", isOn: Binding(
                    get: { model.isCompact },
                    set: { model.setCompact($0) }
                ))
            }
            .padding(4)
        }
    }

    private var memoryBlock: some View {
        GroupBox("Memory and rate") {
            VStack(alignment: .leading, spacing: 8) {
                Stepper(value: $model.rateCapacity, in: 1...20, step: 1) {
                    Text("Burst of \(Int(model.rateCapacity)) model calls")
                }
                HStack {
                    Text("Refill per second")
                    Slider(value: $model.rateRefillPerSecond, in: 0.05...2)
                    Text(String(format: "%.2f", model.rateRefillPerSecond))
                        .monospacedDigit()
                        .frame(width: 44)
                }
                Text("\(model.history.count) saved turns. Identical text is cached. A blank frame never reaches the model.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Clear conversation history", role: .destructive) {
                    model.clearHistory()
                }
            }
            .padding(4)
        }
    }
}

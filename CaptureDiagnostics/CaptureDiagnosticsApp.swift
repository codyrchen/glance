import AppKit
import SwiftUI
import UniformTypeIdentifiers

@main
struct CaptureDiagnosticsApp: App {
    @StateObject private var model = DiagnosticsModel()

    var body: some Scene {
        Window("Capture Diagnostics", id: "diagnostics") {
            DiagnosticsView(model: model)
                .frame(minWidth: 760, minHeight: 560)
        }
        .defaultSize(width: 920, height: 680)
    }
}

@MainActor
final class DiagnosticsModel: ObservableObject {
    @Published var permissionGranted = false
    @Published var windows: [ShareableWindowInfo] = []
    @Published var selectedWindowID: UInt32?
    @Published var isLoading = false
    @Published var isRunning = false
    @Published var listError: String?
    @Published var reportText = "{\n  \"policy\": \"independent-probes-no-fallback\"\n}"

    func refreshPermission() {
        permissionGranted = PermissionCenter.isGranted
    }

    func requestPermission() {
        _ = PermissionCenter.requestAccess()
        refreshPermission()
    }

    func reloadWindows() {
        guard !isLoading else { return }
        isLoading = true
        listError = nil
        Task {
            do {
                windows = try await WindowCatalog.windows()
                refreshPermission()
            } catch {
                listError = error.localizedDescription
            }
            isLoading = false
        }
    }

    func runProbes() {
        guard let selectedWindowID, let window = windows.first(where: { $0.windowID == selectedWindowID }) else {
            listError = "Select one window first."
            return
        }
        guard !isRunning else { return }
        isRunning = true
        listError = nil
        Task {
            let report = await ProbeRunner.run(window: window)
            do {
                reportText = String(decoding: try report.json(), as: UTF8.self)
            } catch {
                reportText = "Could not encode the report: \(error.localizedDescription)"
            }
            isRunning = false
        }
    }

    func copyReport() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(reportText, forType: .string)
    }

    func saveReport() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "capture-diagnostics.json"
        panel.begin { [reportText] response in
            guard response == .OK, let url = panel.url else { return }
            try? Data(reportText.utf8).write(to: url)
        }
    }
}

struct DiagnosticsView: View {
    @ObservedObject var model: DiagnosticsModel

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Capture Diagnostics")
                    .font(.title2.weight(.semibold))
                Text("Pick one window. Each API is called once and judged on its own. The JSON records whether the frame has visible pixels. Frames are not shown or saved, and a result is never used to fill in for another API.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if model.permissionGranted {
                    Label("Screen Recording is on.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.callout)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Screen Recording is required before any probe can run.")
                            .font(.callout)
                        HStack {
                            Button("Open Settings") { PermissionCenter.openSettings() }
                            Button("Request access") { model.requestPermission() }
                            Button("Check again") { model.refreshPermission() }
                        }
                    }
                }
                HStack {
                    Button(model.isLoading ? "Loading…" : "Refresh windows") { model.reloadWindows() }
                        .disabled(model.isLoading)
                }
                if let listError = model.listError {
                    Text(listError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                List(model.windows, selection: $model.selectedWindowID) { window in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(window.displayTitle).lineLimit(1)
                        Text("\(window.ownerName) · \(window.windowID)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(window.windowID)
                }
                Button(model.isRunning ? "Probing…" : "Run independent probes") {
                    model.runProbes()
                }
                .disabled(model.selectedWindowID == nil || model.isRunning)
                .buttonStyle(.borderedProminent)
            }
            .padding(16)
            .frame(minWidth: 320, idealWidth: 380)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("JSON report")
                        .font(.headline)
                    Spacer()
                    Button("Copy") { model.copyReport() }
                    Button("Save…") { model.saveReport() }
                }
                ScrollView {
                    Text(model.reportText)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }
            .padding(16)
        }
        .onAppear { model.refreshPermission() }
    }
}

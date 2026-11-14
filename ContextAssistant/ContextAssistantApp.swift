import AppKit
import SwiftUI

@main
struct ContextAssistantApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("Context Assistant", id: "controls") {
            ControlView(model: model)
        }
        .defaultSize(width: 1020, height: 720)
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Ask about selected window") {
                    model.ask(bypassCache: false)
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                Button("Stop") {
                    model.cancel()
                }
                .keyboardShortcut(".", modifiers: [.command, .shift])
            }
        }

        MenuBarExtra {
            Button("Ask about selected window") {
                model.ask(bypassCache: false)
            }
            Button("Choose with system picker") {
                model.useSystemPicker()
            }
            Divider()
            Text(model.selectionSummary)
            Text(model.isBusy ? "Capture active" : "Idle")
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        } label: {
            Image(systemName: model.isBusy ? "viewfinder.circle.fill" : "viewfinder")
        }
        .menuBarExtraStyle(.menu)
    }
}

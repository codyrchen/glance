import GlanceCore
import SwiftUI

struct OverlayView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.4)
            if model.isCompact {
                compactBody
            } else {
                expandedBody
            }
            Divider().opacity(0.4)
            composer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .background {
            Button("") { model.showOlderHistory() }
                .keyboardShortcut("[", modifiers: .command)
                .hidden()
            Button("") { model.showNewerHistory() }
                .keyboardShortcut("]", modifiers: .command)
                .hidden()
            Button("") { model.cancelOrHide() }
                .keyboardShortcut(.escape, modifiers: [])
                .hidden()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            CaptureDot(active: model.isBusy, failed: model.phase == .failed)
                .help(model.isBusy ? "Capture is running. This panel stays visible to screen sharing." : "Idle. This panel stays visible to screen sharing.")
                .accessibilityLabel(model.isBusy ? "Capture active" : "Capture idle")
            VStack(alignment: .leading, spacing: 1) {
                Text(model.phaseTitle)
                    .font(.headline)
                Text(model.selectionSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if model.answerIsCached {
                Text("Cached")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
            Button(model.isCompact ? "Expand" : "Compact") {
                model.setCompact(!model.isCompact)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(".", modifiers: [.command])
            Button {
                model.hideOverlay()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Hide overlay")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var compactBody: some View {
        ScrollView {
            answerBody
                .padding(14)
        }
        .frame(maxHeight: 120)
    }

    private var expandedBody: some View {
        HStack(alignment: .top, spacing: 0) {
            if !model.history.isEmpty {
                historyColumn
                    .frame(width: 150)
                Divider().opacity(0.4)
            }
            ScrollView {
                answerBody
                    .padding(14)
            }
        }
    }

    private var historyColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                Text("History")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)
                ForEach(model.history) { turn in
                    Button {
                        model.selectedHistoryID = turn.id
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(turn.userQuestion)
                                .lineLimit(2)
                                .font(.caption)
                            Text(turn.windowTitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                        .background(model.selectedHistoryID == turn.id ? Color.accentColor.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
        }
    }

    private var answerBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = model.errorBanner {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            if model.displayedAnswer.isEmpty && model.errorBanner == nil {
                Text(model.statusText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if !model.displayedAnswer.isEmpty {
                MarkdownText(source: model.displayedAnswer)
            }
            if let id = model.selectedHistoryID, model.history.contains(where: { $0.id == id }) {
                Text("Showing an earlier answer. Down arrow returns to the latest one.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Ask about the selected window", text: $model.question, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...3)
                .onSubmit { model.ask(bypassCache: false) }
            if model.isBusy {
                Button("Stop") { model.cancel() }
                    .keyboardShortcut(".", modifiers: [.command, .shift])
            } else {
                Button("Ask") { model.ask(bypassCache: false) }
                    .keyboardShortcut(.return, modifiers: [.command])
            }
            Button("Again") { model.ask(bypassCache: true) }
                .disabled(model.isBusy)
                .help("Ignore the cache and ask the model again")
        }
        .padding(12)
    }
}

struct CaptureDot: View {
    var active: Bool
    var failed: Bool

    var body: some View {
        Circle()
            .fill(failed ? Color.red : (active ? Color.orange : Color.green))
            .frame(width: 10, height: 10)
            .overlay {
                if active {
                    Circle()
                        .stroke(Color.orange.opacity(0.7), lineWidth: 2)
                        .scaleEffect(1.8)
                }
            }
            .accessibilityHidden(true)
    }
}

struct MarkdownText: View {
    var source: String

    var body: some View {
        Group {
            if let attributed = try? AttributedString(
                markdown: source,
                options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
            ) {
                Text(attributed)
            } else {
                Text(source)
            }
        }
        .font(.body)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

import AppKit
import ContextAssistantCore
import SwiftUI

enum OverlayPreset: String, CaseIterable, Identifiable, Codable {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing
    case center

    var id: String { rawValue }

    var title: String {
        switch self {
        case .topLeading: return "Top left"
        case .topTrailing: return "Top right"
        case .bottomLeading: return "Bottom left"
        case .bottomTrailing: return "Bottom right"
        case .center: return "Center"
        }
    }
}

/// Floating answer panel. `sharingType` stays `.readOnly`, which is also the AppKit default.
final class OverlayPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 560),
            styleMask: [.nonactivatingPanel, .titled, .closable, .resizable, .fullSizeContentView, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .utilityWindow
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = false
        applySharingPolicy()
        minSize = NSSize(width: 320, height: 180)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func close() {
        orderOut(nil)
    }

    func applySharingPolicy() {
        switch CapturePolicy.assistantWindowSharing {
        case .readOnly:
            sharingType = .readOnly
        }
    }
}

@MainActor
final class OverlayController {
    let panel = OverlayPanel()
    private var installed = false

    func install<Content: View>(content: Content) {
        guard !installed else { return }
        panel.contentViewController = NSHostingController(rootView: content)
        installed = true
        panel.applySharingPolicy()
    }

    func show() {
        panel.applySharingPolicy()
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    func place(_ preset: OverlayPreset) {
        let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let area = screen.visibleFrame
        let size = panel.frame.size
        let padding: CGFloat = 18
        let origin: NSPoint
        switch preset {
        case .topLeading:
            origin = NSPoint(x: area.minX + padding, y: area.maxY - size.height - padding)
        case .topTrailing:
            origin = NSPoint(x: area.maxX - size.width - padding, y: area.maxY - size.height - padding)
        case .bottomLeading:
            origin = NSPoint(x: area.minX + padding, y: area.minY + padding)
        case .bottomTrailing:
            origin = NSPoint(x: area.maxX - size.width - padding, y: area.minY + padding)
        case .center:
            origin = NSPoint(
                x: area.midX - size.width / 2,
                y: area.midY - size.height / 2
            )
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    func setOpacity(_ value: Double) {
        panel.alphaValue = min(1, max(0.55, value))
    }

    func setCompact(_ compact: Bool) {
        var frame = panel.frame
        frame.size.height = compact ? 240 : 560
        frame.size.width = max(frame.width, compact ? 360 : 440)
        panel.setFrame(frame, display: true, animate: true)
    }

    func hide() {
        panel.orderOut(nil)
    }
}

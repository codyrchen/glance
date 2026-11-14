import Foundation

/// Rules the assistant is built around. The sharing enum has one case so a
/// stealth mode cannot be selected without changing this type.
public enum AssistantWindowSharing: String, Codable, Sendable, Equatable {
    /// `NSWindow.SharingType.readOnly`, which is also the AppKit default.
    case readOnly
}

public enum CapturePolicy {
    public static let assistantWindowSharing = AssistantWindowSharing.readOnly
    public static let allowAPIFallback = false
    public static let stopWhenFrameHasNoVisibleContent = true
    public static let captureRequiresExplicitSelection = true
    public static let diagnosticsAreIndependentProbes = true

    public static let summary = """
    Capture only a window the user selected. A blank or protected frame stops the assistant. \
    The assistant panel stays at sharing type readOnly. Diagnostics record each API separately \
    and never substitute one API's frame for another.
    """
}

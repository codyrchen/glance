import AppKit
import CoreGraphics
import Foundation

enum PermissionCenter {
    static var isGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Shows the system Screen Recording prompt. A denial is not shown again until TCC is reset.
    @discardableResult
    static func requestAccess() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    static func openSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        ]
        for candidate in candidates {
            guard let url = URL(string: candidate) else { continue }
            if NSWorkspace.shared.open(url) {
                return
            }
        }
    }
}

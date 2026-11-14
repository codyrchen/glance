import CoreGraphics
import Foundation
import ScreenCaptureKit

struct ShareableWindowInfo: Identifiable, Hashable, Sendable {
    var windowID: UInt32
    var title: String
    var ownerName: String
    var bundleIdentifier: String
    var width: Double
    var height: Double

    var id: UInt32 { windowID }

    var displayTitle: String {
        title.isEmpty ? "Untitled window" : title
    }
}

enum WindowCatalog {
    static func windows() async throws -> [ShareableWindowInfo] {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            return content.windows.compactMap(makeInfo).sorted { lhs, rhs in
                let owner = lhs.ownerName.localizedCaseInsensitiveCompare(rhs.ownerName)
                if owner == .orderedSame {
                    return lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
                }
                return owner == .orderedAscending
            }
        } catch {
            throw CaptureFailure.classify(error)
        }
    }

    private static func makeInfo(_ window: SCWindow) -> ShareableWindowInfo? {
        let width = Double(window.frame.width)
        let height = Double(window.frame.height)
        guard width >= 40, height >= 40 else { return nil }
        return ShareableWindowInfo(
            windowID: window.windowID,
            title: window.title ?? "",
            ownerName: window.owningApplication?.applicationName ?? "Unknown",
            bundleIdentifier: window.owningApplication?.bundleIdentifier ?? "",
            width: width,
            height: height
        )
    }
}

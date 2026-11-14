import Foundation
import ScreenCaptureKit

enum CaptureFailure: Error, Equatable, CustomStringConvertible {
    case permissionRequired
    case windowUnavailable
    case blankFrame(reason: String)
    case emptyImage
    case timedOut
    case underlying(String)

    var stopsPipeline: Bool { true }

    var isTCC: Bool {
        if case .permissionRequired = self { return true }
        return false
    }

    var description: String {
        switch self {
        case .permissionRequired:
            return "Screen Recording permission is not granted. Enable Glance in System Settings and try again."
        case .windowUnavailable:
            return "That window is no longer available to capture. Choose it again."
        case .blankFrame(let reason):
            return "The window returned a blank frame (\(reason)). Capture stopped. This app does not try another capture API."
        case .emptyImage:
            return "The capture API returned an empty image."
        case .timedOut:
            return "The capture did not produce a frame before the timeout."
        case .underlying(let message):
            return message
        }
    }

    static func classify(_ error: Error) -> CaptureFailure {
        if let failure = error as? CaptureFailure {
            return failure
        }
        if isTCCError(error) {
            return .permissionRequired
        }
        return .underlying(error.localizedDescription)
    }

    static func isTCCError(_ error: Error) -> Bool {
        let nsError = error as NSError
        // SCStreamError.userDeclined is -3801 in SCStreamErrorDomain.
        if nsError.domain == SCStreamErrorDomain && nsError.code == -3801 {
            return true
        }
        if nsError.domain == "com.apple.ScreenCaptureKit.SCStreamErrorDomain" && nsError.code == -3801 {
            return true
        }
        let text = nsError.localizedDescription.lowercased()
        return text.contains("declined")
            || text.contains("not authorized")
            || text.contains("screen recording")
            || text.contains("permission")
            || text.contains("tcc")
    }
}

import Foundation
import ScreenCaptureKit

/// System window picker. The observer only accepts a filter the user confirms.
@MainActor
final class SystemWindowPicker: NSObject, SCContentSharingPickerObserver {
    static let shared = SystemWindowPicker()

    private var continuation: CheckedContinuation<SCContentFilter?, Never>?
    private var isObserving = false

    func pickSingleWindow() async -> SCContentFilter? {
        let picker = SCContentSharingPicker.shared
        if !isObserving {
            picker.add(self)
            isObserving = true
        }
        var configuration = SCContentSharingPickerConfiguration()
        configuration.allowedPickerModes = [.singleWindow]
        configuration.allowsChangingSelectedContent = true
        if let bundleID = Bundle.main.bundleIdentifier {
            configuration.excludedBundleIDs = [bundleID]
        }
        picker.defaultConfiguration = configuration
        picker.isActive = true

        return await withCheckedContinuation { continuation in
            if let existing = self.continuation {
                existing.resume(returning: nil)
            }
            self.continuation = continuation
            picker.present(using: .window)
        }
    }

    private func finish(_ filter: SCContentFilter?) {
        let continuation = self.continuation
        self.continuation = nil
        continuation?.resume(returning: filter)
    }

    nonisolated func contentSharingPicker(
        _ picker: SCContentSharingPicker,
        didUpdateWith filter: SCContentFilter,
        for stream: SCStream?
    ) {
        let selected = filter
        DispatchQueue.main.async {
            SystemWindowPicker.shared.finish(selected)
        }
    }

    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        DispatchQueue.main.async {
            SystemWindowPicker.shared.finish(nil)
        }
    }

    nonisolated func contentSharingPickerStartDidFailWithError(_ error: Error) {
        DispatchQueue.main.async {
            SystemWindowPicker.shared.finish(nil)
        }
    }
}

import AppKit
import ContextAssistantCore
import CoreGraphics
import CoreVideo
import Foundation
import ScreenCaptureKit

/// Still capture of one explicit target through ScreenCaptureKit.
/// This type does not call `CGWindowListCreateImage` and it does not open a stream.
enum ScreenshotCapture {
    static func capture(windowID: UInt32) async throws -> CGImage {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        } catch {
            throw CaptureFailure.classify(error)
        }
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
            throw CaptureFailure.windowUnavailable
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        return try await capture(filter: filter, pointWidth: window.frame.width, pointHeight: window.frame.height, scale: nil)
    }

    static func capture(filter: SCContentFilter) async throws -> CGImage {
        let rect = filter.contentRect
        let scale = filter.pointPixelScale > 0 ? CGFloat(filter.pointPixelScale) : 2
        let width = rect.width >= 2 ? rect.width : 1280
        let height = rect.height >= 2 ? rect.height : 800
        return try await capture(filter: filter, pointWidth: width, pointHeight: height, scale: scale)
    }

    static func configuration(pointWidth: CGFloat, pointHeight: CGFloat, scale: CGFloat) -> SCStreamConfiguration {
        let resolvedScale = scale > 0 ? scale : 2
        let size = CaptureSizing.pixelSize(
            pointWidth: Double(pointWidth),
            pointHeight: Double(pointHeight),
            scale: Double(resolvedScale)
        )
        let configuration = SCStreamConfiguration()
        configuration.width = size.width
        configuration.height = size.height
        configuration.scalesToFit = true
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.queueDepth = 2
        return configuration
    }

    private static func capture(
        filter: SCContentFilter,
        pointWidth: CGFloat,
        pointHeight: CGFloat,
        scale: CGFloat?
    ) async throws -> CGImage {
        let configuration = configuration(
            pointWidth: pointWidth,
            pointHeight: pointHeight,
            scale: scale ?? (NSScreen.main?.backingScaleFactor ?? 2)
        )
        do {
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        } catch {
            throw CaptureFailure.classify(error)
        }
    }
}

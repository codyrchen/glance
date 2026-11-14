import AppKit
import GlanceCore
import CoreGraphics
import CoreImage
import CoreMedia
import CoreVideo
import Darwin
import Foundation
import ScreenCaptureKit

/// Resolves the public `CGWindowListCreateImage` symbol once and calls it a single time.
/// A nil or blank image is the result of this probe. No other option combination is tried.
enum LegacyCaptureProbe {
    private static let listIncludingWindow: UInt32 = 1 << 3
    private static let boundsIgnoreFraming: UInt32 = 1 << 0
    private static let bestResolution: UInt32 = 1 << 3
    private static let library: UnsafeMutableRawPointer? = dlopen(
        "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics",
        RTLD_LAZY
    )

    static func capture(windowID: UInt32) -> Result<CGImage, CaptureFailure> {
        guard let library else {
            return .failure(.underlying("CoreGraphics could not be opened. The legacy probe stops."))
        }
        guard let symbol = dlsym(library, "CGWindowListCreateImage") else {
            return .failure(.underlying("CGWindowListCreateImage is not available in this OS. The legacy probe stops."))
        }
        typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        let function = unsafeBitCast(symbol, to: CreateImage.self)
        let options = boundsIgnoreFraming | bestResolution
        guard let unmanaged = function(.null, listIncludingWindow, windowID, options) else {
            if !PermissionCenter.isGranted {
                return .failure(.permissionRequired)
            }
            return .failure(.emptyImage)
        }
        return .success(unmanaged.takeRetainedValue())
    }
}

enum SampleBufferImage {
    static func make(from sampleBuffer: CMSampleBuffer) -> CGImage? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard image.extent.width > 1, image.extent.height > 1 else { return nil }
        let context = CIContext(options: nil)
        return context.createCGImage(image, from: image.extent)
    }

    static func frameStatus(of sampleBuffer: CMSampleBuffer) -> SCFrameStatus? {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? NSNumber else {
            return nil
        }
        return SCFrameStatus(rawValue: raw.intValue)
    }
}

/// One SCStream, a few frames at most. A blank status ends this probe immediately.
final class StreamFrameProbe: NSObject, SCStreamOutput, SCStreamDelegate {
    private var continuation: CheckedContinuation<CGImage, Error>?
    private var stream: SCStream?
    private var finished = false
    private var delivered = 0
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "dev.codychen.CaptureDiagnostics.stream")

    func capture(filter: SCContentFilter, configuration: SCStreamConfiguration) async throws -> CGImage {
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        self.stream = stream
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            Task {
                do {
                    try await stream.startCapture()
                } catch {
                    self.complete(.failure(error))
                }
            }
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                self.complete(.failure(CaptureFailure.timedOut))
            }
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        delivered += 1
        if SampleBufferImage.frameStatus(of: sampleBuffer) == .blank {
            complete(.failure(CaptureFailure.blankFrame(reason: "SCStream reported a blank frame")))
            return
        }
        if SampleBufferImage.frameStatus(of: sampleBuffer) == .idle {
            if delivered >= 4 {
                complete(.failure(CaptureFailure.timedOut))
            }
            return
        }
        if let image = SampleBufferImage.make(from: sampleBuffer) {
            complete(.success(image))
        } else if delivered >= 4 {
            complete(.failure(CaptureFailure.emptyImage))
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        complete(.failure(error))
    }

    private func complete(_ result: Result<CGImage, Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished, let continuation else { return }
        finished = true
        self.continuation = nil
        let stream = self.stream
        continuation.resume(with: result)
        if let stream {
            Task { try? await stream.stopCapture() }
        }
    }
}

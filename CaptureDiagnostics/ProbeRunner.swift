import AppKit
import GlanceCore
import CoreMedia
import Foundation
import ScreenCaptureKit

enum ProbeRunner {
    static func run(window: ShareableWindowInfo) async -> CaptureDiagnosticsReport {
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        var probes: [CaptureProbeReport] = []
        probes.append(await screenshotProbe(window: window, osVersion: osVersion))
        probes.append(await sampleBufferProbe(window: window, osVersion: osVersion))
        probes.append(await streamProbe(window: window, osVersion: osVersion))
        probes.append(legacyProbe(window: window, osVersion: osVersion))
        return CaptureDiagnosticsReport(
            generatedAt: Date(),
            osVersion: osVersion,
            windowID: window.windowID,
            windowTitle: window.title,
            ownerName: window.ownerName,
            probes: probes
        )
    }

    private static func screenshotProbe(window: ShareableWindowInfo, osVersion: String) async -> CaptureProbeReport {
        await probe(api: "SCScreenshotManager.captureImage", window: window, osVersion: osVersion) {
            try await ScreenshotCapture.capture(windowID: window.windowID)
        }
    }

    private static func sampleBufferProbe(window: ShareableWindowInfo, osVersion: String) async -> CaptureProbeReport {
        await probe(api: "SCScreenshotManager.captureSampleBuffer", window: window, osVersion: osVersion) {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            guard let scWindow = content.windows.first(where: { $0.windowID == window.windowID }) else {
                throw CaptureFailure.windowUnavailable
            }
            let filter = SCContentFilter(desktopIndependentWindow: scWindow)
            let configuration = ScreenshotCapture.configuration(
                pointWidth: scWindow.frame.width,
                pointHeight: scWindow.frame.height,
                scale: NSScreen.main?.backingScaleFactor ?? 2
            )
            let buffer: CMSampleBuffer
            do {
                buffer = try await SCScreenshotManager.captureSampleBuffer(contentFilter: filter, configuration: configuration)
            } catch {
                throw CaptureFailure.classify(error)
            }
            guard let image = SampleBufferImage.make(from: buffer) else {
                throw CaptureFailure.emptyImage
            }
            return image
        }
    }

    private static func streamProbe(window: ShareableWindowInfo, osVersion: String) async -> CaptureProbeReport {
        await probe(api: "SCStream", window: window, osVersion: osVersion) {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            guard let scWindow = content.windows.first(where: { $0.windowID == window.windowID }) else {
                throw CaptureFailure.windowUnavailable
            }
            let filter = SCContentFilter(desktopIndependentWindow: scWindow)
            var configuration = ScreenshotCapture.configuration(
                pointWidth: scWindow.frame.width,
                pointHeight: scWindow.frame.height,
                scale: NSScreen.main?.backingScaleFactor ?? 2
            )
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 8)
            let probe = StreamFrameProbe()
            return try await probe.capture(filter: filter, configuration: configuration)
        }
    }

    private static func legacyProbe(window: ShareableWindowInfo, osVersion: String) -> CaptureProbeReport {
        switch LegacyCaptureProbe.capture(windowID: window.windowID) {
        case .success(let image):
            return report(api: "CGWindowListCreateImage", window: window, osVersion: osVersion, image: image, failure: nil)
        case .failure(let failure):
            return report(api: "CGWindowListCreateImage", window: window, osVersion: osVersion, image: nil, failure: failure)
        }
    }

    private static func probe(
        api: String,
        window: ShareableWindowInfo,
        osVersion: String,
        body: () async throws -> CGImage
    ) async -> CaptureProbeReport {
        do {
            let image = try await body()
            return report(api: api, window: window, osVersion: osVersion, image: image, failure: nil)
        } catch {
            let failure = (error as? CaptureFailure) ?? CaptureFailure.classify(error)
            return report(api: api, window: window, osVersion: osVersion, image: nil, failure: failure)
        }
    }

    /// The image is assessed and then dropped. It is not shown, saved, or passed to another probe.
    private static func report(
        api: String,
        window: ShareableWindowInfo,
        osVersion: String,
        image: CGImage?,
        failure: CaptureFailure?
    ) -> CaptureProbeReport {
        if let image {
            let verdict = FrameContent.assess(PixelSampler.samples(from: image))
            switch verdict {
            case .visible:
                return CaptureProbeReport(
                    api: api,
                    windowID: window.windowID,
                    windowTitle: window.title,
                    ownerName: window.ownerName,
                    osVersion: osVersion,
                    success: true,
                    hasVisibleContent: true,
                    error: nil,
                    tccFailure: false
                )
            case .blankOrUniform(let reason):
                return CaptureProbeReport(
                    api: api,
                    windowID: window.windowID,
                    windowTitle: window.title,
                    ownerName: window.ownerName,
                    osVersion: osVersion,
                    success: true,
                    hasVisibleContent: false,
                    error: reason,
                    tccFailure: false
                )
            }
        }
        let failure = failure ?? .emptyImage
        if case .blankFrame(let reason) = failure {
            return CaptureProbeReport(
                api: api,
                windowID: window.windowID,
                windowTitle: window.title,
                ownerName: window.ownerName,
                osVersion: osVersion,
                success: true,
                hasVisibleContent: false,
                error: reason,
                tccFailure: false
            )
        }
        return CaptureProbeReport(
            api: api,
            windowID: window.windowID,
            windowTitle: window.title,
            ownerName: window.ownerName,
            osVersion: osVersion,
            success: false,
            hasVisibleContent: nil,
            error: failure.description,
            tccFailure: failure.isTCC
        )
    }
}

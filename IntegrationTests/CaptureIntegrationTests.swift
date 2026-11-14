import ContextAssistantCore
import CoreGraphics
import XCTest
@testable import ContextAssistant

final class PixelPipelineTests: XCTestCase {
    func testBlackImageIsReportedBlank() throws {
        let image = try XCTUnwrap(makeImage(red: 0, green: 0, blue: 0))
        let verdict = FrameContent.assess(PixelSampler.samples(from: image))
        guard case .blankOrUniform = verdict else {
            return XCTFail("A black frame must stop the pipeline")
        }
    }

    func testStripedImageIsVisible() throws {
        let image = try XCTUnwrap(makeStripedImage())
        XCTAssertEqual(FrameContent.assess(PixelSampler.samples(from: image)), .visible)
    }

    private func makeImage(red: UInt8, green: UInt8, blue: UInt8) -> CGImage? {
        let width = 32
        let height = 32
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            pixels[index] = red
            pixels[index + 1] = green
            pixels[index + 2] = blue
            pixels[index + 3] = 255
        }
        return pixels.withUnsafeMutableBytes { raw in
            let context = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
            return context?.makeImage()
        }
    }

    private func makeStripedImage() -> CGImage? {
        let width = 32
        let height = 32
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let on = (x / 4).isMultiple(of: 2)
                pixels[offset] = on ? 220 : 20
                pixels[offset + 1] = on ? 40 : 180
                pixels[offset + 2] = 60
                pixels[offset + 3] = 255
            }
        }
        return pixels.withUnsafeMutableBytes { raw in
            let context = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
            return context?.makeImage()
        }
    }
}

final class ScreenRecordingIntegrationTests: XCTestCase {
    func testWindowListWhenPermissionIsGranted() async throws {
        try XCTSkipUnless(
            PermissionCenter.isGranted,
            "Screen Recording permission is not granted to Context Assistant. Grant it in System Settings, then rerun this test."
        )
        _ = try await WindowCatalog.windows()
    }

    func testExplicitWindowWhenConfigured() async throws {
        try XCTSkipUnless(
            PermissionCenter.isGranted,
            "Screen Recording permission is not granted to Context Assistant."
        )
        guard let raw = ProcessInfo.processInfo.environment["CONTEXT_ASSISTANT_TEST_WINDOW_ID"],
              let windowID = UInt32(raw) else {
            throw XCTSkip("Set CONTEXT_ASSISTANT_TEST_WINDOW_ID to a window you selected.")
        }
        do {
            let image = try await ScreenshotCapture.capture(windowID: windowID)
            _ = FrameContent.assess(PixelSampler.samples(from: image))
        } catch let error as CaptureFailure {
            XCTAssertTrue(error.stopsPipeline)
        }
    }
}

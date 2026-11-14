import XCTest
@testable import GlanceCore

final class FrameContentTests: XCTestCase {
    func testEmptyAndTinyFramesAreBlank() {
        XCTAssertEqual(FrameContent.assess([]), .blankOrUniform(reason: "too few pixels"))
        let few = Array(repeating: PixelSample(red: 255, green: 255, blue: 255), count: 8)
        XCTAssertEqual(FrameContent.assess(few), .blankOrUniform(reason: "too few pixels"))
    }

    func testBlackFrameIsBlank() {
        let samples = Array(repeating: PixelSample(red: 0, green: 0, blue: 0), count: 64)
        XCTAssertEqual(FrameContent.assess(samples), .blankOrUniform(reason: "near-black frame"))
    }

    func testDarkGrayIsBlank() {
        let samples = Array(repeating: PixelSample(red: 3, green: 3, blue: 3), count: 64)
        if case .blankOrUniform = FrameContent.assess(samples) {
            return
        }
        XCTFail("expected a dark frame to stop the pipeline")
    }

    func testWhitePageIsVisible() {
        let samples = Array(repeating: PixelSample(red: 250, green: 250, blue: 250), count: 64)
        XCTAssertEqual(FrameContent.assess(samples), .visible)
    }

    func testSingleBrightPixelIsVisible() {
        var samples = Array(repeating: PixelSample(red: 0, green: 0, blue: 0), count: 64)
        samples[10] = PixelSample(red: 240, green: 240, blue: 240)
        XCTAssertEqual(FrameContent.assess(samples), .visible)
    }

    func testNoiseIsVisible() {
        var samples: [PixelSample] = []
        samples.reserveCapacity(64)
        for index in 0..<64 {
            let red = UInt8((index * 37) % 255)
            let green = UInt8((index * 13) % 255)
            let blue = UInt8((index * 7) % 200)
            samples.append(PixelSample(red: red, green: green, blue: blue))
        }
        XCTAssertEqual(FrameContent.assess(samples), .visible)
    }
}

final class CaptureSizingTests: XCTestCase {
    func testScaleWithoutCap() {
        let size = CaptureSizing.pixelSize(pointWidth: 400, pointHeight: 300, scale: 2)
        XCTAssertEqual(size.width, 800)
        XCTAssertEqual(size.height, 600)
    }

    func testLongEdgeIsCapped() {
        let size = CaptureSizing.pixelSize(pointWidth: 2000, pointHeight: 1000, scale: 2, maxEdge: 1600)
        XCTAssertEqual(max(size.width, size.height), 1600)
        XCTAssertEqual(size.width, 1600)
        XCTAssertEqual(size.height, 800)
    }

    func testZeroBecomesOnePixel() {
        let size = CaptureSizing.pixelSize(pointWidth: 0, pointHeight: 0, scale: 0)
        XCTAssertEqual(size.width, 1)
        XCTAssertEqual(size.height, 1)
    }
}

final class CapturePolicyTests: XCTestCase {
    func testAssistantCannotSelectStealthOrFallback() {
        XCTAssertEqual(CapturePolicy.assistantWindowSharing, .readOnly)
        XCTAssertFalse(CapturePolicy.allowAPIFallback)
        XCTAssertTrue(CapturePolicy.stopWhenFrameHasNoVisibleContent)
        XCTAssertTrue(CapturePolicy.captureRequiresExplicitSelection)
    }
}

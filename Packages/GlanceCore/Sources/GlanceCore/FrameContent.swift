import Foundation

public struct PixelSample: Equatable, Sendable {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public var luminance: Double {
        (0.2126 * Double(red)) + (0.7152 * Double(green)) + (0.0722 * Double(blue))
    }
}

public enum FrameContentVerdict: Equatable, Sendable {
    case visible
    /// Near-black or empty. Callers stop. This is not a signal to try another capture API.
    case blankOrUniform(reason: String)
}

public enum FrameContent {
    /// Flags frames that are empty or near-black with almost no variation.
    /// A bright uniform window (an empty document) stays `.visible` so OCR can report that it has no text.
    public static func assess(_ samples: [PixelSample]) -> FrameContentVerdict {
        guard samples.count >= 16 else {
            return .blankOrUniform(reason: "too few pixels")
        }
        let luminances = samples.map(\.luminance)
        let count = Double(luminances.count)
        let mean = luminances.reduce(0, +) / count
        let variance = luminances.reduce(0) { partial, value in
            let delta = value - mean
            return partial + (delta * delta)
        } / count
        let maxLuminance = luminances.max() ?? 0

        if maxLuminance < 12 && variance < 16 {
            return .blankOrUniform(reason: "near-black frame")
        }
        if variance < 1 && mean < 18 {
            return .blankOrUniform(reason: "uniform dark frame")
        }
        return .visible
    }
}

public enum CaptureSizing {
    public static func pixelSize(
        pointWidth: Double,
        pointHeight: Double,
        scale: Double,
        maxEdge: Double = 1600
    ) -> (width: Int, height: Int) {
        let safeScale = max(scale, 1)
        var width = max(pointWidth, 1) * safeScale
        var height = max(pointHeight, 1) * safeScale
        let edge = max(width, height)
        if edge > maxEdge && edge > 0 {
            let ratio = maxEdge / edge
            width *= ratio
            height *= ratio
        }
        return (max(1, Int(width.rounded())), max(1, Int(height.rounded())))
    }
}

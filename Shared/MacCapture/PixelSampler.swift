import ContextAssistantCore
import CoreGraphics
import Foundation

enum PixelSampler {
    /// Downscales into a known RGBA buffer and returns one sample per pixel of that buffer.
    static func samples(from image: CGImage, grid: Int = 32) -> [PixelSample] {
        let sourceWidth = image.width
        let sourceHeight = image.height
        guard sourceWidth > 0, sourceHeight > 0, grid > 0 else { return [] }
        let columns = min(grid, sourceWidth)
        let rows = min(grid, sourceHeight)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixels = [UInt8](repeating: 0, count: columns * rows * 4)
        let drew = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: columns,
                height: rows,
                bitsPerComponent: 8,
                bytesPerRow: columns * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: columns, height: rows))
            return true
        }
        guard drew else { return [] }
        var samples: [PixelSample] = []
        samples.reserveCapacity(columns * rows)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            samples.append(PixelSample(red: pixels[index], green: pixels[index + 1], blue: pixels[index + 2]))
        }
        return samples
    }
}

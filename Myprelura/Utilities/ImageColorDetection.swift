import UIKit

/// Detects a dominant colour from an image and maps it to the app's colour vocabulary.
/// Used by the feed search bar when the user attaches an image for "search by colour".
enum ImageColorDetection {

    private static let sampleSize = CGSize(width: 64, height: 64)
    private static let bucketBits = 4

    /// Returns dominant (r,g,b) in 0...1, or nil if detection fails.
    static func dominantColor(from image: UIImage) -> (r: Double, g: Double, b: Double)? {
        // Prefer CGImage path
        if let result = dominantFromCGImage(image) { return result }
        // Fallback: draw into small bitmap and bucket
        return dominantFromRenderedImage(image)
    }

    private static func dominantFromCGImage(_ image: UIImage) -> (r: Double, g: Double, b: Double)? {
        guard let cg = image.cgImage else { return nil }
        let w = cg.width
        let h = cg.height
        guard w > 0, h > 0 else { return nil }

        let scale = min(sampleSize.width / CGFloat(w), sampleSize.height / CGFloat(h), 1)
        let sw = Int(CGFloat(w) * scale)
        let sh = Int(CGFloat(h) * scale)
        guard sw > 0, sh > 0 else { return nil }

        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * sw
        let bufferSize = bytesPerRow * sh

        guard let space = cg.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: sw,
                height: sh,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
              ),
              let data = context.data else { return nil }

        context.draw(cg, in: CGRect(x: 0, y: 0, width: sw, height: sh))

        let ptr = data.bindMemory(to: UInt8.self, capacity: bufferSize)
        var buckets = [Int: Int]()
        let mask = (1 << bucketBits) - 1

        for y in 0..<sh {
            for x in 0..<sw {
                let offset = (y * sw + x) * bytesPerPixel
                let r = Int(ptr[offset])
                let g = Int(ptr[offset + 1])
                let b = Int(ptr[offset + 2])
                let key = (r >> (8 - bucketBits)) << (bucketBits * 2) | (g >> (8 - bucketBits)) << bucketBits | (b >> (8 - bucketBits))
                buckets[key, default: 0] += 1
            }
        }

        guard let (dominantKey, _) = buckets.max(by: { $0.value < $1.value }) else { return nil }

        let r = ((dominantKey >> (bucketBits * 2)) & mask) << (8 - bucketBits)
        let g = ((dominantKey >> bucketBits) & mask) << (8 - bucketBits)
        let b = (dominantKey & mask) << (8 - bucketBits)
        return (Double(r) / 255, Double(g) / 255, Double(b) / 255)
    }

    /// Fallback: render into small image and sample pixels.
    private static func dominantFromRenderedImage(_ image: UIImage) -> (r: Double, g: Double, b: Double)? {
        let size = CGSize(width: 32, height: 32)
        let renderer = UIGraphicsImageRenderer(size: size)
        let small = renderer.image { ctx in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let cg = small.cgImage else { return nil }
        return dominantFromCGImage(UIImage(cgImage: cg))
    }

    /// Maps image dominant colour to the nearest app colour name.
    static func nearestAppColour(from image: UIImage) -> String? {
        guard let (r, g, b) = dominantColor(from: image) else { return nil }
        return AISearchService.nearestColourName(r: r, g: g, b: b)
    }
}

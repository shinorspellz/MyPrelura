import UIKit
import CoreImage

/// Detects dominant colour from image using CoreImage CIAreaAverage and maps to a supported colour name.
enum ColourDetectionService {
    private static let supportedColourNames = [
        "Black", "White", "Grey", "Red", "Blue", "Green", "Yellow", "Pink", "Purple",
        "Brown", "Beige", "Navy", "Olive"
    ]

    private static let colourRGB: [(name: String, r: Float, g: Float, b: Float)] = [
        ("Black", 0.0, 0.0, 0.0),
        ("White", 1.0, 1.0, 1.0),
        ("Grey", 0.5, 0.5, 0.5),
        ("Red", 0.9, 0.2, 0.2),
        ("Blue", 0.2, 0.4, 0.9),
        ("Green", 0.2, 0.7, 0.3),
        ("Yellow", 0.95, 0.9, 0.2),
        ("Pink", 1.0, 0.6, 0.75),
        ("Purple", 0.5, 0.2, 0.7),
        ("Brown", 0.45, 0.3, 0.2),
        ("Beige", 0.96, 0.96, 0.86),
        ("Navy", 0.0, 0.0, 0.5),
        ("Olive", 0.5, 0.5, 0.0)
    ]

    /// Returns the closest supported colour name for the image's dominant colour.
    static func detectDominantColour(from image: UIImage) -> String? {
        guard let ciImage = CIImage(image: image) else { return nil }
        let extent = ciImage.extent
        guard extent.width > 0, extent.height > 0 else { return nil }

        guard let filter = CIFilter(name: "CIAreaAverage"),
              let filterImage = CIFilter(name: "CIAffineClamp") else { return nil }
        filterImage.setValue(ciImage, forKey: kCIInputImageKey)
        filterImage.setValue(CGAffineTransform.identity, forKey: kCIInputTransformKey)
        guard let clamped = filterImage.outputImage else { return nil }

        filter.setValue(clamped, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: extent), forKey: kCIInputExtentKey)
        guard let output = filter.outputImage else { return nil }

        let context = CIContext()
        var pixel: [UInt8] = [0, 0, 0, 0]
        context.render(output, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        let r = Float(pixel[0]) / 255.0
        let g = Float(pixel[1]) / 255.0
        let b = Float(pixel[2]) / 255.0

        var bestName: String?
        var bestDist: Float = .infinity
        for entry in colourRGB {
            let dr = r - entry.r
            let dg = g - entry.g
            let db = b - entry.b
            let dist = dr * dr + dg * dg + db * db
            if dist < bestDist {
                bestDist = dist
                bestName = entry.name
            }
        }
        return bestName
    }
}

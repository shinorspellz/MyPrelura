import Foundation
import Vision
import UIKit

/// Detects garment category from image using Vision VNClassifyImageRequest. Maps labels to: Dress, Hoodie, Shirt, Jacket, Coat, Trousers, Skirt, Shoes, Bag, Scarf, Hat.
enum CategoryDetectionService {
    private static let categoryLabels: [(category: String, keywords: [String])] = [
        ("Dress", ["dress", "gown", "frock"]),
        ("Hoodie", ["hoodie", "hoody", "sweatshirt", "sweater", "jumper", "pullover"]),
        ("Shirt", ["shirt", "blouse", "top", "tee", "t-shirt", "t shirt"]),
        ("Jacket", ["jacket", "blazer", "cardigan"]),
        ("Coat", ["coat", "overcoat", "parka"]),
        ("Trousers", ["trousers", "pants", "jeans", "tights", "leggings"]),
        ("Skirt", ["skirt"]),
        ("Shoes", ["shoes", "sneakers", "boots", "sandals", "heels", "footwear"]),
        ("Bag", ["bag", "handbag", "purse", "backpack"]),
        ("Scarf", ["scarf", "shawl"]),
        ("Hat", ["hat", "cap", "beanie"])
    ]

    private static let minConfidence: Float = 0.70

    /// Runs Vision image classification and returns the first category that matches with confidence >= 0.70.
    static func detectCategory(image: UIImage) async -> String? {
        guard let cgImage = image.cgImage else { return nil }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)

        return await withCheckedContinuation { continuation in
            let request = VNClassifyImageRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
            do {
                try handler.perform([request])
                let observations = request.results ?? []
                for obs in observations {
                    guard obs.confidence >= minConfidence else { continue }
                    let id = obs.identifier.lowercased()
                    for entry in categoryLabels {
                        if entry.keywords.contains(where: { id.contains($0) }) {
                            continuation.resume(returning: entry.category)
                            return
                        }
                    }
                }
                continuation.resume(returning: nil)
            } catch {
                #if DEBUG
                print("[CategoryDetection] error: \(error)")
                #endif
                continuation.resume(returning: nil)
            }
        }
    }
}

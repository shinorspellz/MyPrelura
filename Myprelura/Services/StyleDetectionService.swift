import Foundation
import Vision
import UIKit

/// Detects style from image using Vision VNClassifyImageRequest. Maps to: Casual, Streetwear, Sport, Formal, Vintage, Minimal.
enum StyleDetectionService {
    private static let styleLabels: [(style: String, keywords: [String])] = [
        ("Casual", ["casual", "everyday", "relaxed"]),
        ("Streetwear", ["streetwear", "street", "urban"]),
        ("Sport", ["sport", "sportswear", "athletic", "activewear", "gym"]),
        ("Formal", ["formal", "suit", "business", "elegant"]),
        ("Vintage", ["vintage", "retro", "classic"]),
        ("Minimal", ["minimal", "minimalist", "simple", "plain"])
    ]

    private static let minConfidence: Float = 0.60

    /// Returns the first matching style with confidence >= 0.60, or nil.
    static func detectStyle(image: UIImage) async -> String? {
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
                    for entry in styleLabels {
                        if entry.keywords.contains(where: { id.contains($0) }) {
                            continuation.resume(returning: entry.style)
                            return
                        }
                    }
                }
                continuation.resume(returning: nil)
            } catch {
                #if DEBUG
                print("[StyleDetection] error: \(error)")
                #endif
                continuation.resume(returning: nil)
            }
        }
    }
}

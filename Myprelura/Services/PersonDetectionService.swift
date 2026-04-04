import Foundation
import Vision
import UIKit

/// Detects a human in the image using Vision. Returns the first detected person's bounding box.
enum PersonDetectionService {
    /// Detects humans; returns the first observation or nil if none.
    /// Uses synchronous perform + single resume to avoid double-resume crash (Vision can invoke the completion handler and perform can throw on some images).
    static func detectPerson(in image: UIImage) async -> VNHumanObservation? {
        guard let cgImage = image.cgImage else { return nil }
        return await withCheckedContinuation { continuation in
            let request = VNDetectHumanRectanglesRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
                let observations = (request.results as? [VNHumanObservation]) ?? []
                continuation.resume(returning: observations.first)
            } catch {
                #if DEBUG
                print("[PersonDetection] perform error: \(error)")
                #endif
                continuation.resume(returning: nil)
            }
        }
    }
}

import UIKit
import Vision

/// Crops the torso region from a detected human bounding box (approx. 60% of height for clothing area).
enum ClothingCropper {
    /// Crop image to the torso region of the human observation. Bounding box is in normalized Vision coordinates (origin bottom-left).
    static func cropTorso(from image: UIImage, humanObservation: VNHumanObservation) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let orientation = image.imageOrientation
        let boundingBox = humanObservation.boundingBox

        // Vision boundingBox is normalized (0-1), origin bottom-left. Convert to image coords (top-left origin).
        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)
        let x = boundingBox.minX * imageWidth
        let y = (1.0 - boundingBox.maxY) * imageHeight
        let w = boundingBox.width * imageWidth
        var h = boundingBox.height * imageHeight
        let torsoHeight = h * 0.6
        let torsoY = y + (h - torsoHeight)
        h = torsoHeight
        let cropRect = CGRect(
            x: max(0, min(x, imageWidth - 1)),
            y: max(0, min(torsoY, imageHeight - 1)),
            width: max(1, min(w, imageWidth)),
            height: max(1, min(h, imageHeight))
        )

        guard let cropped = cgImage.cropping(to: cropRect) else { return nil }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: orientation)
    }
}

import UIKit

/// On-device AI Listing Assistant pipeline. Detects person → crops torso → colour/category/style → generates title/description/tags. No external APIs.
final class GarmentAnalysisService {
    private static let detectionSize: CGFloat = 640

    /// Creates a copy of the image resized so the longest side is detectionSize. Does not modify the original.
    private static func detectionCopy(of image: UIImage) -> UIImage? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(detectionSize / size.width, detectionSize / size.height)
        guard scale < 1.0 else { return image }
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    /// Runs the full pipeline on a background queue. Call from main and update UI on main with the result.
    static func analyze(image: UIImage) async -> GarmentAnalysisResult {
        let work = await Task.detached(priority: .userInitiated) {
            guard let detectionImage = detectionCopy(of: image) else {
                return GarmentAnalysisResult()
            }
            var result = GarmentAnalysisResult()

            // 1. Detect person
            guard let human = await PersonDetectionService.detectPerson(in: detectionImage) else {
                return result
            }

            // 2. Crop torso
            guard let cropped = ClothingCropper.cropTorso(from: detectionImage, humanObservation: human) else {
                return result
            }

            // 3. Dominant colour
            result.colour = ColourDetectionService.detectDominantColour(from: cropped)

            // 4. Category
            result.category = await CategoryDetectionService.detectCategory(image: cropped)

            // 5. Style
            result.style = await StyleDetectionService.detectStyle(image: cropped)

            // 6. Generate title, description, tags
            result.title = ListingContentGenerator.title(colour: result.colour, style: result.style, category: result.category)
            result.description = ListingContentGenerator.description(colour: result.colour, category: result.category, style: result.style)
            result.tags = ListingContentGenerator.tags(colour: result.colour, style: result.style, category: result.category)

            return result
        }.value
        return work
    }
}

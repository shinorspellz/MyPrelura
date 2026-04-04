import UIKit

extension UIImage {

    /// Returns a copy of the image with EXIF orientation applied so it displays correctly.
    /// Photos from the camera often have orientation metadata; `UIImage(data:)` ignores it,
    /// which causes rotated thumbnails. This redraws the image so orientation is baked in.
    func normalizedForDisplay() -> UIImage {
        if imageOrientation == .up { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(at: .zero)
        }
    }
}

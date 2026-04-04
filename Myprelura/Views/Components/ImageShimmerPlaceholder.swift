import SwiftUI
import Shimmer

/// Shimmer placeholder for image thumbnails while loading. Uses SwiftUI-Shimmer.
struct ImageShimmerPlaceholder: View {
    var cornerRadius: CGFloat = 8

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Theme.Colors.secondaryBackground)
            .shimmering()
    }
}

/// Shimmer placeholder that fills the given size (for use in GeometryReader or fixed frame).
struct ImageShimmerPlaceholderFilled: View {
    var cornerRadius: CGFloat = 8

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Theme.Colors.secondaryBackground)
            .shimmering()
    }
}

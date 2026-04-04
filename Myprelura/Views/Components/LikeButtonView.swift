import SwiftUI

/// Shared like button: heart + count. Use on product cards and detail for consistent design.
/// Tap area is 56×56 pt for easier tapping; the visible pill stays the same size.
struct LikeButtonView: View {
    let isLiked: Bool
    let likeCount: Int
    let action: () -> Void
    /// When true, show on dark overlay (white icon when unliked). When false, use for light backgrounds (red when liked, primaryText when not).
    var onDarkOverlay: Bool = true

    private static let minTapSize: CGFloat = 56

    var body: some View {
        Button(action: action) {
            ZStack {
                Color.clear
                    .frame(width: Self.minTapSize, height: Self.minTapSize)
                    .contentShape(Rectangle())
                likePillContent
                    .allowsHitTesting(false)
            }
            .frame(width: Self.minTapSize, height: Self.minTapSize)
        }
        .buttonStyle(HapticTapButtonStyle(haptic: { HapticManager.like() }))
    }

    private var likePillContent: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: isLiked ? "heart.fill" : "heart")
                .font(.system(size: 14, weight: .medium))
            Text("\(likeCount)")
                .font(Theme.Typography.caption)
        }
        .foregroundColor(isLiked ? .red : (onDarkOverlay ? .white : Theme.Colors.primaryText))
        .shadow(color: onDarkOverlay ? .black.opacity(0.4) : .clear, radius: 1, x: 0, y: 1)
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, 6)
        .background(
            Group {
                if onDarkOverlay {
                    Capsule().fill(Color.black.opacity(0.6))
                } else {
                    Color.clear
                }
            }
        )
    }
}

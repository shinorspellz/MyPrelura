import SwiftUI

/// Lightweight loading placeholder (aligned with consumer “shimmer” feel without extra dependencies).
struct AdminShimmer: View {
    @State private var animate = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            LinearGradient(
                colors: [
                    Theme.Colors.glassBackground,
                    Theme.Colors.glassBackground.opacity(0.45),
                    Theme.Colors.glassBackground,
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: w * 1.8)
            .offset(x: animate ? w * 0.35 : -w * 0.55)
        }
        .clipped()
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
    }
}

struct AdminShimmerCapsule: View {
    var height: CGFloat = 14

    var body: some View {
        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
            .fill(Theme.Colors.glassBackground)
            .frame(height: height)
            .overlay { AdminShimmer() }
            .clipShape(RoundedRectangle(cornerRadius: height / 2, style: .continuous))
    }
}

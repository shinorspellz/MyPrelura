import SwiftUI

extension View {
    /// Applies a glassmorphism effect with customizable parameters
    func glassStyle(
        cornerRadius: CGFloat = Theme.Glass.cornerRadius,
        opacity: Double = Theme.Glass.opacity
    ) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)
                    .opacity(opacity)
            )
            .shadow(
                color: Color.black.opacity(Theme.Glass.shadowOpacity),
                radius: Theme.Glass.shadowRadius,
                x: 0,
                y: 4
            )
    }
}

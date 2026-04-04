import SwiftUI

struct GlassEffect: ViewModifier {
    let cornerRadius: CGFloat
    let opacity: Double
    let blurRadius: CGFloat
    
    init(
        cornerRadius: CGFloat = Theme.Glass.cornerRadius,
        opacity: Double = Theme.Glass.opacity,
        blurRadius: CGFloat = Theme.Glass.blurRadius
    ) {
        self.cornerRadius = cornerRadius
        self.opacity = opacity
        self.blurRadius = blurRadius
    }
    
    func body(content: Content) -> some View {
        content
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

extension View {
    func glassEffect(
        cornerRadius: CGFloat = Theme.Glass.cornerRadius,
        opacity: Double = Theme.Glass.opacity,
        blurRadius: CGFloat = Theme.Glass.blurRadius
    ) -> some View {
        modifier(GlassEffect(cornerRadius: cornerRadius, opacity: opacity, blurRadius: blurRadius))
    }
}

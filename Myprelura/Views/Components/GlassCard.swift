import SwiftUI

struct GlassCard<Content: View>: View {
    let content: Content
    let cornerRadius: CGFloat
    let padding: CGFloat
    
    init(
        cornerRadius: CGFloat = Theme.Glass.cornerRadius,
        padding: CGFloat = Theme.Spacing.md,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.content = content()
    }
    
    var body: some View {
        content
            .padding(padding)
            .glassEffect(cornerRadius: cornerRadius)
    }
}

// Convenience initializer for simple content
extension GlassCard where Content == AnyView {
    init(
        cornerRadius: CGFloat = Theme.Glass.cornerRadius,
        padding: CGFloat = Theme.Spacing.md
    ) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.content = AnyView(EmptyView())
    }
}

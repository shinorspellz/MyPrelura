import SwiftUI

struct GlassNavigationBar: ViewModifier {
    let title: String
    let leadingButton: AnyView?
    let trailingButton: AnyView?
    
    init(
        title: String,
        leadingButton: AnyView? = nil,
        trailingButton: AnyView? = nil
    ) {
        self.title = title
        self.leadingButton = leadingButton
        self.trailingButton = trailingButton
    }
    
    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            HStack {
                if let leading = leadingButton {
                    leading
                } else {
                    Spacer()
                        .frame(width: 44)
                }
                
                Spacer()
                
                Text(title)
                    .font(Theme.Typography.title3)
                    .foregroundColor(Theme.Colors.primaryText)
                
                Spacer()
                
                if let trailing = trailingButton {
                    trailing
                } else {
                    Spacer()
                        .frame(width: 44)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(0.9)
            )
            .overlay(ContentDivider(), alignment: .bottom)
            
            content
        }
    }
}

extension View {
    func glassNavigationBar(
        title: String,
        leadingButton: AnyView? = nil,
        trailingButton: AnyView? = nil
    ) -> some View {
        modifier(GlassNavigationBar(
            title: title,
            leadingButton: leadingButton,
            trailingButton: trailingButton
        ))
    }
}

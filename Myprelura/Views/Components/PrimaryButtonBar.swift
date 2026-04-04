import SwiftUI

/// Static bottom bar that holds the main primary (filled) CTA. Use with ZStack(alignment: .bottom) so content scrolls above it.
/// Same height everywhere: more space above the button, minimal space beneath (top sm, bottom xs).
struct PrimaryButtonBar<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.sm)
            .padding(.bottom, 0)
            .frame(maxWidth: .infinity)
            .background(Theme.Colors.background)
            .overlay(ContentDivider(), alignment: .top)
            .ignoresSafeArea(edges: .bottom)
    }
}

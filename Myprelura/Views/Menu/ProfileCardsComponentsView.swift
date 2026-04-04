import SwiftUI

/// Debug screen: single primary button (glass material + tap) for design reference.
struct ProfileCardsComponentsView: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()
            Button(action: {}) {
                Text("Primary")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.primaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.md)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .background(Capsule().fill(.ultraThinMaterial))
            }
            .buttonStyle(GlassMaterialButtonStyle())
            .frame(maxWidth: 280)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.background)
        .navigationTitle("Profile cards, and components")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }
}

/// System tap animation for glass material buttons (scale on press, like Apple's iPhone UI).
private struct GlassMaterialButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

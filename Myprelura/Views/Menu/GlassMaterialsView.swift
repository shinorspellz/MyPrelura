import SwiftUI

/// Debug screen: Liquid Glass buttons per [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views).
/// Shows glass-effect buttons over a vibrant background so the frosted effect is visible, plus a solid button for comparison.
struct GlassMaterialsView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.xl) {
                glassButtonsSection
                labelsSection
                borderButtonsSection
                borderLabelsSection
            }
            .padding(Theme.Spacing.lg)
        }
        .background(glassDemoBackground)
        .navigationTitle("Glass materials")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }

    /// Vertical stack of full-width buttons: two with Liquid Glass, one solid.
    private var glassButtonsSection: some View {
        GlassEffectContainer(spacing: Theme.Spacing.md) {
            VStack(spacing: Theme.Spacing.md) {
                // Liquid Glass (regular)
                Button(action: {}) {
                    Text("Hello, World!")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, Theme.Spacing.lg)
                        .padding(.vertical, Theme.Spacing.md)
                }
                .buttonStyle(PlainTappableButtonStyle())
                .glassEffect(.regular, in: .rect(cornerRadius: 12))

                // Glass clear button (fully glassy — used for Discover category buttons)
                Button(action: {}) {
                    Text("Hello, World!")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, Theme.Spacing.lg)
                        .padding(.vertical, Theme.Spacing.md)
                }
                .buttonStyle(PlainTappableButtonStyle())
                .glassEffect(.clear, in: .rect(cornerRadius: 30))

                // Liquid Glass (clear + primary colour tint)
                Button(action: {}) {
                    Text("Hello, World!")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, Theme.Spacing.lg)
                        .padding(.vertical, Theme.Spacing.md)
                }
                .buttonStyle(PlainTappableButtonStyle())
                .glassEffect(.clear.tint(Theme.primaryColor), in: .rect(cornerRadius: 12))

                // Liquid Glass (clear + primary tint, corner radius 30) — PrimaryGlassButton component
                PrimaryGlassButton("Hello, World!", action: {})

                // Solid (no glass) for comparison
                Button(action: {}) {
                    Text("Hello, World!")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, Theme.Spacing.lg)
                        .padding(.vertical, Theme.Spacing.md)
                        .background(Color.orange, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(PlainTappableButtonStyle())
            }
        }
    }

    /// Border versions: outline only (no fill), stroke only. Radius-30 row uses BorderGlassButton.
    private var borderButtonsSection: some View {
        VStack(spacing: Theme.Spacing.md) {
            outlineButton(cornerRadius: 12, strokeColor: .white)
            outlineButton(cornerRadius: 12, strokeColor: .white)
            outlineButton(cornerRadius: 12, strokeColor: Theme.primaryColor)
            BorderGlassButton("Hello, World!", action: {})
            outlineButton(cornerRadius: 12, strokeColor: .orange)
        }
    }

    private func outlineButton(cornerRadius: CGFloat, strokeColor: Color) -> some View {
        Button(action: {}) {
            Text("Hello, World!")
                .font(Theme.Typography.headline)
                .foregroundStyle(strokeColor)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.md)
        }
        .buttonStyle(PlainTappableButtonStyle())
        .background(Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(strokeColor, lineWidth: 2)
        )
    }

    private var labelsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Glass (regular)")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.secondaryText)
            Text("Glass clear button (pill)")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.secondaryText)
            Text("Glass (clear + primary tint)")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.secondaryText)
            Text("Glass (clear + primary tint, radius 30)")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.secondaryText)
            Text("Solid (no glass)")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var borderLabelsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Border — Glass (regular)")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.secondaryText)
            Text("Border — Glass (clear)")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.secondaryText)
            Text("Border — Glass (clear + primary tint)")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.secondaryText)
            Text("Border — Glass (clear + primary tint, radius 30)")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.secondaryText)
            Text("Border — Solid (no glass)")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Gradient background so the liquid glass effect is visible (pink → green → blue, like Apple's reference).
    private var glassDemoBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.95, green: 0.4, blue: 0.5),
                Color(red: 0.3, green: 0.7, blue: 0.35),
                Color(red: 0.25, green: 0.5, blue: 0.95)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .overlay(
            LinearGradient(
                colors: [.black.opacity(0.2), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .ignoresSafeArea()
    }
}

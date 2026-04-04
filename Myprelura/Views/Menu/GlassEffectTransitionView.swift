import SwiftUI

/// Debug page demonstrating [GlassEffectTransition](https://developer.apple.com/documentation/swiftui/glasseffecttransition):
/// how Liquid Glass views animate when content appears, disappears, or changes.
/// Shows all three transition types: identity, materialize, matchedGeometry.
struct GlassEffectTransitionView: View {
    @State private var showIdentity = false
    @State private var showMaterialize = false
    @Namespace private var glassNamespace

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                introSection
                identitySection
                materializeSection
                matchedGeometrySection
            }
            .padding(Theme.Spacing.lg)
        }
        .background(glassDemoBackground)
        .navigationTitle("Glass effect transition")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }

    private var glassDemoBackground: some View {
        LinearGradient(
            colors: [
                Theme.primaryColor.opacity(0.4),
                Color.purple.opacity(0.3),
                Color.blue.opacity(0.2)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var introSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("GlassEffectTransition")
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.primaryText)
            Text("Controls how Liquid Glass materials animate when views are inserted, removed, or change layout. Tap each toggle to see the transition.")
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.secondaryText)
        }
    }

    // MARK: - Identity
    /// No animation: glass appears/disappears immediately. Useful for debugging or static UI.
    private var identitySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("1. identity")
                .font(Theme.Typography.headline)
                .foregroundColor(Theme.Colors.primaryText)
            Text("Glass appears immediately with no fade or shape animation.")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.secondaryText)
            Toggle("Show glass", isOn: $showIdentity)
                .tint(Theme.primaryColor)
            GlassEffectContainer(spacing: Theme.Spacing.md) {
                if showIdentity {
                    Text("Identity transition")
                        .font(Theme.Typography.body)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(Theme.Spacing.md)
                        .glassEffect(.regular, in: .rect(cornerRadius: 12))
                        .glassEffectTransition(.identity)
                }
            }
            .frame(minHeight: 56)
            .animation(.default, value: showIdentity)
        }
    }

    // MARK: - Materialize
    /// Content fades in/out smoothly without matching geometry to other glass shapes.
    private var materializeSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("2. materialize")
                .font(Theme.Typography.headline)
                .foregroundColor(Theme.Colors.primaryText)
            Text("Smooth fade in/out; no morphing between shapes. Good for menus and buttons.")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.secondaryText)
            Toggle("Show glass", isOn: $showMaterialize)
                .tint(Theme.primaryColor)
            GlassEffectContainer(spacing: Theme.Spacing.md) {
                if showMaterialize {
                    Text("Materialize transition")
                        .font(Theme.Typography.body)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(Theme.Spacing.md)
                        .glassEffect(.clear.tint(Theme.primaryColor), in: .rect(cornerRadius: 12))
                        .glassEffectTransition(.materialize)
                }
            }
            .frame(minHeight: 56)
            .animation(.easeInOut(duration: 0.35), value: showMaterialize)
        }
    }

    // MARK: - Matched geometry
    /// Fluid morphing between glass shapes that share the same glassEffectID and namespace.
    private var matchedGeometrySection: some View {
        MatchedGeometryDemo(namespace: glassNamespace)
    }
}

/// Demo: two glass views with the same glassEffectID swap visibility — glass shape morphs between them.
private struct MatchedGeometryDemo: View {
    let namespace: Namespace.ID
    @State private var showA = true

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("3. matchedGeometry")
                .font(Theme.Typography.headline)
                .foregroundColor(Theme.Colors.primaryText)
            Text("Glass morphs between views that share the same glassEffectID. Requires GlassEffectContainer and a shared namespace.")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.secondaryText)
            Button {
                withAnimation(.easeInOut(duration: 0.4)) {
                    showA.toggle()
                }
            } label: {
                Text(showA ? "Switch to B" : "Switch to A")
                    .font(Theme.Typography.headline)
                    .foregroundColor(Theme.primaryColor)
            }
            .buttonStyle(PlainTappableButtonStyle())
            GlassEffectContainer(spacing: Theme.Spacing.md) {
                if showA {
                    Text("View A")
                        .font(Theme.Typography.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(Theme.Spacing.lg)
                        .glassEffect(.regular, in: .rect(cornerRadius: 16))
                        .glassEffectID("morph", in: namespace)
                        .glassEffectTransition(.matchedGeometry)
                } else {
                    Text("View B")
                        .font(Theme.Typography.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(Theme.Spacing.lg)
                        .glassEffect(.clear.tint(Theme.primaryColor), in: .rect(cornerRadius: 16))
                        .glassEffectID("morph", in: namespace)
                        .glassEffectTransition(.matchedGeometry)
                }
            }
            .frame(minHeight: 80)
        }
    }
}

#Preview {
    NavigationStack {
        GlassEffectTransitionView()
    }
}

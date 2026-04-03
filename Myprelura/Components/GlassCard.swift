import SwiftUI

struct GlassCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Colors.glassBackground)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Glass.menuContainerCornerRadius, style: .continuous)
                    .stroke(Theme.Colors.glassBorder, lineWidth: Theme.Glass.borderWidth)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Glass.menuContainerCornerRadius, style: .continuous))
    }
}

struct PrimaryButton: View {
    let title: String
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: {
            HapticManager.primaryAction()
            action()
        }) {
            HStack(spacing: Theme.Spacing.sm) {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                }
                Text(title)
                    .font(Theme.Typography.headline)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
            .contentShape(RoundedRectangle(cornerRadius: 30))
        }
        .buttonStyle(PlainTappableButtonStyle())
        .background(Theme.primaryColor)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .opacity(isLoading ? 0.6 : 1)
        .disabled(isLoading)
    }
}

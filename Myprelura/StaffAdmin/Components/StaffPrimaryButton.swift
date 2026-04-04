import SwiftUI

/// Staff login / forms — matches legacy admin primary CTA.
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

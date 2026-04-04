import SwiftUI

/// Outline-only (no fill) button: primary-color stroke, corner radius 30.
/// Use for secondary actions that should match the primary glass style as an outline.
struct BorderGlassButton: View {
    let title: String
    var icon: String? = nil
    var isEnabled: Bool = true
    let action: () -> Void

    private let cornerRadius: CGFloat = 30
    private let strokeLineWidth: CGFloat = 1

    init(
        _ title: String,
        icon: String? = nil,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.isEnabled = isEnabled
        self.action = action
    }

    var body: some View {
        Button(action: {
            HapticManager.secondaryAction()
            action()
        }) {
            HStack(spacing: Theme.Spacing.sm) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                }
                Text(title)
                    .font(Theme.Typography.headline)
            }
            .foregroundStyle(Theme.primaryColor)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
        .buttonStyle(PlainTappableButtonStyle())
        .background(Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(Theme.primaryColor, lineWidth: strokeLineWidth)
        )
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
        .opacity(isEnabled ? 1 : 0.6)
        .disabled(!isEnabled)
    }
}

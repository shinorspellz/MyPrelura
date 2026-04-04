import SwiftUI

/// Primary CTA button using Liquid Glass: clear + primary tint, corner radius 30.
/// Use this for all primary actions across the app.
struct PrimaryGlassButton: View {
    let title: String
    var icon: String? = nil
    /// Asset catalog name; when set, shown instead of SF Symbol `icon`.
    var assetIcon: String? = nil
    var isEnabled: Bool = true
    var isLoading: Bool = false
    let action: () -> Void

    init(
        _ title: String,
        icon: String? = nil,
        assetIcon: String? = nil,
        isEnabled: Bool = true,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.assetIcon = assetIcon
        self.isEnabled = isEnabled
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        Button(action: {
            HapticManager.primaryAction()
            action()
        }) {
            HStack(spacing: Theme.Spacing.sm) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    if let assetIcon {
                        Image(assetIcon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 22, height: 22)
                    } else if let icon {
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .semibold))
                    }
                    Text(title)
                        .font(Theme.Typography.headline)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
            // Full control bounds tappable (not only glyph bounds of Text/Image).
            .contentShape(RoundedRectangle(cornerRadius: 30))
        }
        .buttonStyle(PlainTappableButtonStyle())
        .glassEffect(.clear.tint(Theme.primaryColor), in: .rect(cornerRadius: 30))
        .contentShape(RoundedRectangle(cornerRadius: 30))
        .opacity(isEnabled && !isLoading ? 1 : 0.6)
        .disabled(!isEnabled || isLoading)
    }
}

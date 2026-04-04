import SwiftUI

/// Single component for all filter/category/brand pills. Inactive state uses material card style (3D elevation).
struct PillTag: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let isSelected: Bool
    /// When true, unselected state shows icon (e.g. for brand row). Text colour: unselected = grey, selected = white.
    var accentWhenUnselected: Bool = false
    /// Optional leading icon (e.g. "message.fill" for brand row).
    var icon: String? = nil
    let action: () -> Void

    private let shape = RoundedRectangle(cornerRadius: Theme.Glass.tagCornerRadius)

    /// In light mode, skip shadow to avoid muddy low-contrast look on white; in dark mode use elevation shadow.
    private var inactiveShadowColor: Color {
        colorScheme == .light ? .clear : Color.black.opacity(0.22)
    }
    private let inactiveShadowRadius: CGFloat = 6
    private let inactiveShadowY: CGFloat = 3

    var body: some View {
        Button(action: {
            HapticManager.selection()
            action()
        }) {
            HStack(spacing: Theme.Spacing.xs) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(foregroundColor)
                }
                Text(title)
                    .font(Theme.Typography.subheadline)
                    .foregroundColor(foregroundColor)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(backgroundView)
            .clipShape(shape)
            .overlay(overlayView)
            .shadow(
                color: isSelected ? .clear : inactiveShadowColor,
                radius: isSelected ? 0 : inactiveShadowRadius,
                x: 0,
                y: isSelected ? 0 : inactiveShadowY
            )
        }
        .buttonStyle(PlainTappableButtonStyle())
    }

    private var foregroundColor: Color {
        if isSelected { return .white }
        return colorScheme == .light ? Theme.Colors.primaryText : Theme.Colors.secondaryText
    }

    @ViewBuilder
    private var backgroundView: some View {
        if isSelected {
            shape.fill(Theme.primaryColor)
        } else if colorScheme == .light {
            shape.fill(Theme.Colors.background)
        } else {
            shape.fill(Theme.Colors.secondaryBackground)
        }
    }

    /// Inactive: subtle stroke for card edge. Selected: no border.
    @ViewBuilder
    private var overlayView: some View {
        if isSelected {
            EmptyView()
        } else {
            shape
                .strokeBorder(inactiveBorderColor, lineWidth: 0.5)
        }
    }

    private var inactiveBorderColor: Color {
        colorScheme == .light
            ? Color.black.opacity(0.18)
            : Theme.Colors.glassBorder.opacity(0.5)
    }
}

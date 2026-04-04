import SwiftUI

struct GlassButton: View {
    let title: String
    let icon: String?
    let action: () -> Void
    let style: GlassButtonStyle

    enum GlassButtonStyle {
        case primary
        case secondary
        case outline
    }

    init(
        _ title: String,
        icon: String? = nil,
        style: GlassButtonStyle = .primary,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.style = style
        self.action = action
    }
    
    var body: some View {
        Group {
            if style == .primary {
                PrimaryGlassButton(title, icon: icon, action: action)
            } else {
                BorderGlassButton(title, icon: icon, action: action)
            }
        }
    }
}

// MARK: - Toolbar/nav icons: Liquid Glass circle (system .regular material in circle).

/// Liquid Glass circle behind toolbar icons — system glass material for consistent look.
private struct GlassIconCircleStyle: ViewModifier {
    let size: CGFloat

    func body(content: Content) -> some View {
        content
            .frame(width: size, height: size)
            .glassEffect(.regular, in: .ellipse)
    }
}

/// Icon-only glassy circle button for toolbars (bell, heart, gear, xmark). One component = consistent look.
struct GlassIconButton: View {
    let icon: String
    let action: () -> Void
    let size: CGFloat
    var iconColor: Color = Theme.primaryColor
    var iconSize: CGFloat = 18

    init(
        icon: String,
        size: CGFloat = 44,
        iconColor: Color = Theme.primaryColor,
        iconSize: CGFloat = 18,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.size = size
        self.iconColor = iconColor
        self.iconSize = iconSize
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundColor(iconColor)
                .modifier(GlassIconCircleStyle(size: size))
        }
        .buttonStyle(HapticTapButtonStyle())
    }
}

/// Same glassy circle + icon, no button (e.g. for NavigationLink label in toolbar).
struct GlassIconView: View {
    let icon: String
    var size: CGFloat = 44
    var iconColor: Color = Theme.primaryColor
    var iconSize: CGFloat = 18

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: iconSize, weight: .semibold))
            .foregroundColor(iconColor)
            .modifier(GlassIconCircleStyle(size: size))
    }
}

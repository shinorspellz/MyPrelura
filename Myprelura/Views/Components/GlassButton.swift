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

/// Glass circle + neutral bell; only a small dot shows state (shopper: red unread; Console: primary when monitor on).
struct NotificationToolbarBellVisual: View {
    private enum Kind {
        case shopperUnread(Bool)
        case consoleMonitorOn(Bool)
    }

    private let kind: Kind

    init(emphasized: Bool) {
        self.kind = .consoleMonitorOn(emphasized)
    }

    init(hasUnread: Bool) {
        self.kind = .shopperUnread(hasUnread)
    }

    private var showDot: Bool {
        switch kind {
        case .shopperUnread(let u): return u
        case .consoleMonitorOn(let on): return on
        }
    }

    private var dotColor: Color {
        switch kind {
        case .shopperUnread: return Color.red
        case .consoleMonitorOn: return Theme.primaryColor
        }
    }

    var body: some View {
        Image(systemName: "bell")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(Theme.Colors.primaryText)
            .modifier(GlassIconCircleStyle(size: 44))
            .overlay(alignment: .topTrailing) {
                if showDot {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 10, height: 10)
                        .offset(x: 4, y: -4)
                        .allowsHitTesting(false)
                }
            }
    }
}

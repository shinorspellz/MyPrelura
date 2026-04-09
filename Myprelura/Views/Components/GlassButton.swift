import SwiftUI
import UIKit

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

/// Glass circle + neutral bell; shopper: red **count** badge; Console: primary dot when monitor on.
struct NotificationToolbarBellVisual: View {
    private enum Kind {
        case shopper(unreadCount: Int)
        case consoleMonitorOn(Bool)
    }

    private let kind: Kind

    init(emphasized: Bool) {
        self.kind = .consoleMonitorOn(emphasized)
    }

    init(unreadCount: Int) {
        self.kind = .shopper(unreadCount: max(0, unreadCount))
    }

    private static let toolbarCanvasWidth: CGFloat = 56
    private static let toolbarCanvasHeight: CGFloat = 52
    private static let bellBadgeRimNudgeX: CGFloat = -3
    private static let bellBadgeRimNudgeY: CGFloat = 3

    var body: some View {
        ZStack {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.Colors.primaryText)
                    .modifier(GlassIconCircleStyle(size: 44))
                badgeLayer
                    .offset(x: Self.bellBadgeRimNudgeX, y: Self.bellBadgeRimNudgeY)
            }
            .frame(width: 44, height: 44)
        }
        .frame(width: Self.toolbarCanvasWidth, height: Self.toolbarCanvasHeight)
    }

    @ViewBuilder
    private var badgeLayer: some View {
        switch kind {
        case .shopper(let count):
            if count > 0 {
                shopperUnreadBadge(count: count)
            }
        case .consoleMonitorOn(let on):
            if on {
                Circle()
                    .fill(Theme.primaryColor)
                    .frame(width: 10, height: 10)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white.opacity(0.35), lineWidth: 0.75)
                    )
                    .allowsHitTesting(false)
            }
        }
    }

    private static let opaqueBadgeRed = Color(UIColor(red: 0.96, green: 0.26, blue: 0.21, alpha: 1))

    private func shopperUnreadBadge(count: Int) -> some View {
        let label = count > 99 ? "99+" : "\(count)"
        return Text(label)
            .font(.system(size: label.count >= 3 ? 9 : 10, weight: .bold))
            .foregroundStyle(.white)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, count >= 10 ? 5 : 4)
            .frame(minWidth: 18, minHeight: 18)
            .background(Capsule().fill(Self.opaqueBadgeRed))
            .compositingGroup()
            .allowsHitTesting(false)
    }
}

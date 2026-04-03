import SwiftUI

/// Aligned with `PreluraSwift` `Theme` (primary, dark background #0C0C0C, glass tokens, typography scale).
struct Theme {
    static let primaryColor = Color(hex: "AB28B2")

    /// Staff app is dark-first; mirrors consumer `Theme.effectiveColorScheme` usage.
    static var effectiveColorScheme: ColorScheme = .dark

    struct Colors {
        static var background: Color {
            effectiveColorScheme == .dark ? Color(hex: "0C0C0C") : Color(uiColor: .systemBackground)
        }

        /// Navigation bar / tab bar surface (same as main app screen background in dark mode).
        static var navigationBarBackground: Color {
            effectiveColorScheme == .dark ? Color(hex: "0C0C0C") : Color(uiColor: .systemBackground)
        }

        static var modalSheetBackground: Color {
            effectiveColorScheme == .dark ? Color(hex: "1C1C1C") : Color(uiColor: .systemBackground)
        }

        static var secondaryBackground: Color { Color(uiColor: .secondarySystemBackground) }
        static var tertiaryBackground: Color { Color(uiColor: .tertiarySystemBackground) }

        static var primaryText: Color { Color(uiColor: .label) }
        static var secondaryText: Color { Color(uiColor: .secondaryLabel) }
        static var tertiaryText: Color { Color(uiColor: .tertiaryLabel) }

        static var authOverVideoText: Color { Color.white.opacity(0.95) }

        static var error: Color { Color(uiColor: .systemRed) }

        static var glassBackground: Color {
            effectiveColorScheme == .dark
                ? Color.white.opacity(0.1)
                : Color.black.opacity(0.06)
        }

        static var glassBorder: Color {
            effectiveColorScheme == .dark
                ? Color.white.opacity(0.2)
                : Color.black.opacity(0.12)
        }

        static var profileRingBorder: Color {
            effectiveColorScheme == .dark
                ? Color.white.opacity(0.35)
                : Color.black.opacity(0.2)
        }
    }

    struct Glass {
        static let blurRadius: CGFloat = 20
        static let opacity: Double = 0.8
        static let borderWidth: CGFloat = 1
        static let cornerRadius: CGFloat = 10.8
        static let menuContainerCornerRadius: CGFloat = 12
        static let tagCornerRadius: CGFloat = 20
        static let shadowRadius: CGFloat = 10
        static let shadowOpacity: Double = 0.1
    }

    struct Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    struct AppBar {
        static let horizontalPadding: CGFloat = Spacing.md
        static let verticalPadding: CGFloat = Spacing.sm
        static let buttonSize: CGFloat = 44
    }

    /// Small accents for dashboard metric tiles (adds colour without fighting dark/light semantics).
    struct MetricAccents {
        static let users = Color(hex: "5AC8FA")
        static let newToday = Color(hex: "34C759")
        static let listingViews = Color(hex: "FF9500")
        static let viewsToday = Color(hex: "FF2D55")
        static let health = Color(hex: "AB28B2")
    }

    struct Typography {
        static let largeTitle = Font.system(size: 34, weight: .bold, design: .default)
        static let title = Font.system(size: 28, weight: .bold, design: .default)
        static let title2 = Font.system(size: 22, weight: .bold, design: .default)
        static let title3 = Font.system(size: 20, weight: .semibold, design: .default)
        static let headline = Font.system(size: 17, weight: .semibold, design: .default)
        static let body = Font.system(size: 17, weight: .regular, design: .default)
        static let callout = Font.system(size: 16, weight: .regular, design: .default)
        static let subheadline = Font.system(size: 15, weight: .regular, design: .default)
        static let footnote = Font.system(size: 13, weight: .regular, design: .default)
        static let caption = Font.system(size: 12, weight: .regular, design: .default)
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

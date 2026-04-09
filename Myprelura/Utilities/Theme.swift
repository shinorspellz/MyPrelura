import SwiftUI

struct Theme {
    // Primary Color (same in light and dark)
    static let primaryColor = Color(hex: "AB28B2")

    /// Resolved scheme for the app (set from AppearanceRoot; used for glass colors).
    static var effectiveColorScheme: ColorScheme = .dark

    // Adaptive Colors (UIKit semantic colors follow system; glass colors use effectiveColorScheme)
    struct Colors {
        // Background colors (dark mode uses #0C0C0C for normal screens)
        static var background: Color {
            effectiveColorScheme == .dark ? Color(hex: "0C0C0C") : Color(uiColor: UIColor.systemBackground)
        }

        /// Tab bar / navigation bar surface (staff chrome).
        static var navigationBarBackground: Color {
            effectiveColorScheme == .dark ? Color(hex: "0C0C0C") : Color(uiColor: UIColor.systemBackground)
        }

        /// Dedicated modal sheet surface in dark mode.
        static var modalSheetBackground: Color {
            effectiveColorScheme == .dark ? Color(hex: "1C1C1E") : Color(uiColor: UIColor.systemBackground)
        }

        static var secondaryBackground: Color {
            Color(uiColor: UIColor.secondarySystemBackground)
        }

        static var tertiaryBackground: Color {
            Color(uiColor: UIColor.tertiarySystemBackground)
        }

        // Text colors
        static var primaryText: Color {
            Color(uiColor: UIColor.label)
        }

        static var secondaryText: Color {
            Color(uiColor: UIColor.secondaryLabel)
        }

        static var tertiaryText: Color {
            Color(uiColor: UIColor.tertiaryLabel)
        }

        /// Text over video on auth screens (login/signup): always light for readability in both light and dark mode.
        static var authOverVideoText: Color {
            Color.white.opacity(0.95)
        }

        /// Error/destructive text and controls
        static var error: Color {
            Color(uiColor: .systemRed)
        }

        // Glass effect colors (light mode: dark tint; dark mode: light tint)
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

        /// Ring border around profile image (visible in light and dark mode).
        static var profileRingBorder: Color {
            effectiveColorScheme == .dark
                ? Color.white.opacity(0.35)
                : Color.black.opacity(0.2)
        }
    }
    
    // Glassmorphism Constants (menu container corner radius reduced by 40% from 18)
    struct Glass {
        static let blurRadius: CGFloat = 20
        static let opacity: Double = 0.8
        static let borderWidth: CGFloat = 1
        static let cornerRadius: CGFloat = 10.8
        /// Corner radius for menu-style containers and cards (e.g. Help with Order, profile menu popover)
        static let menuContainerCornerRadius: CGFloat = 12
        /// Corner radius for category/tag pills (unchanged by menu container reduction; keep pill-shaped)
        static let tagCornerRadius: CGFloat = 20
        static let shadowRadius: CGFloat = 10
        static let shadowOpacity: Double = 0.1
    }
    
    // Spacing
    struct Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    /// Staff dashboard metric tile accents (Myprelura home).
    struct MetricAccents {
        static let users = Color(hex: "5AC8FA")
        static let newToday = Color(hex: "34C759")
        static let listingViews = Color(hex: "FF9500")
        static let viewsToday = Color(hex: "FF2D55")
        static let health = Color(hex: "AB28B2")
        static let console = Color(hex: "5E5CE6")
    }

    /// Standard app bar / custom header layout so top-level icons and back buttons stay in the same position.
    struct AppBar {
        static let horizontalPadding: CGFloat = Spacing.md
        static let verticalPadding: CGFloat = Spacing.sm
        static let buttonSize: CGFloat = 44
    }
    
    // Typography
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
        static let caption = Font.system(size: 13, weight: .regular, design: .default)
    }

    /// Product colour names to SwiftUI Color (matches Flutter colorsProvider for detail colour integration).
    static func productColor(for name: String) -> Color? {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines)
        switch key.lowercased() {
        case "black": return .black
        case "brown": return .brown
        case "grey", "gray": return .gray
        case "white": return .white
        case "beige": return Color(hex: "F5F5DC")
        case "pink": return .pink
        case "purple": return .purple
        case "red": return .red
        case "yellow": return .yellow
        case "blue": return .blue
        case "green": return .green
        case "orange": return .orange
        case "tan": return Color(hex: "D2B48C")
        case "silver": return Color(hex: "C0C0C0")
        case "gold": return Color(hex: "D4AF37")
        case "navy": return Color(hex: "000080")
        default: return nil
        }
    }
}

// Color extension for hex support
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
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

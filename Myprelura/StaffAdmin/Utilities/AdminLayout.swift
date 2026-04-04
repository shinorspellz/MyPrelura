import SwiftUI
import UIKit

/// iPad and Mac (Catalyst / Designed for iPad) use a desktop-style sidebar; iPhone keeps the tab bar.
enum AdminLayout {
    /// Synced with `Theme.effectiveColorScheme` from the main Prelura app pattern.
    static var prefersDesktopNavigation: Bool {
        #if targetEnvironment(macCatalyst)
        return true
        #else
        return UIDevice.current.userInterfaceIdiom == .pad
        #endif
    }

    /// Max readable width for detail column (desktop-style centred content).
    static let desktopReadableMaxWidth: CGFloat = 960

    /// Apply global `UINavigationBar` / `UITabBar` appearances. Call whenever `Theme.effectiveColorScheme` changes.
    static func applyGlobalUIKitChrome(isDark: Bool) {
        let accent = UIColor(red: 171 / 255, green: 40 / 255, blue: 178 / 255, alpha: 1)

        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        if isDark {
            let bg = UIColor(red: 12 / 255, green: 12 / 255, blue: 12 / 255, alpha: 1)
            nav.backgroundColor = bg
            nav.titleTextAttributes = [.foregroundColor: UIColor.white]
            nav.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        } else {
            nav.backgroundColor = UIColor.systemBackground
            nav.titleTextAttributes = [.foregroundColor: UIColor.label]
            nav.largeTitleTextAttributes = [.foregroundColor: UIColor.label]
        }

        let navObj = UINavigationBar.appearance()
        navObj.standardAppearance = nav
        navObj.compactAppearance = nav
        navObj.scrollEdgeAppearance = nav
        navObj.compactScrollEdgeAppearance = nav
        navObj.tintColor = accent

        let tab = UITabBarAppearance()
        if isDark {
            tab.configureWithOpaqueBackground()
            tab.backgroundColor = UIColor(red: 12 / 255, green: 12 / 255, blue: 12 / 255, alpha: 1)
            tab.stackedLayoutAppearance.normal.iconColor = .lightGray
            tab.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.lightGray]
        } else {
            tab.configureWithDefaultBackground()
            tab.backgroundColor = UIColor.systemBackground
            tab.stackedLayoutAppearance.normal.iconColor = UIColor.secondaryLabel
            tab.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.secondaryLabel]
        }
        tab.stackedLayoutAppearance.selected.iconColor = accent
        tab.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: accent]

        let tabObj = UITabBar.appearance()
        tabObj.standardAppearance = tab
        tabObj.scrollEdgeAppearance = tab
        tabObj.tintColor = accent
        tabObj.unselectedItemTintColor = isDark ? .lightGray : .secondaryLabel
    }
}

struct AdminDesktopReadableWidthModifier: ViewModifier {
    func body(content: Content) -> some View {
        Group {
            if AdminLayout.prefersDesktopNavigation {
                content
                    .frame(maxWidth: AdminLayout.desktopReadableMaxWidth)
                    .frame(maxWidth: .infinity)
            } else {
                content
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

extension View {
    func adminDesktopReadableWidth() -> some View {
        modifier(AdminDesktopReadableWidthModifier())
    }
}

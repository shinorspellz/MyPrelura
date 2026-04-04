import SwiftUI

/// Navigation bar that follows the active color scheme (consumer Prelura uses semantic nav + system chrome in light mode).
private struct AdminNavigationChromeModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .toolbarBackground(Theme.Colors.navigationBarBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(colorScheme == .dark ? .dark : .light, for: .navigationBar)
    }
}

extension View {
    func adminNavigationChrome() -> some View {
        modifier(AdminNavigationChromeModifier())
    }
}

/// Tab bar chrome driven by the resolved scheme (not forced dark).
struct AdminTabBarChromeModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .toolbarBackground(Theme.Colors.navigationBarBackground, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
            .toolbarColorScheme(colorScheme == .dark ? .dark : .light, for: .tabBar)
    }
}

extension View {
    func adminTabBarChrome() -> some View {
        modifier(AdminTabBarChromeModifier())
    }
}

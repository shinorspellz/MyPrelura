import SwiftUI

/// Mirrors consumer `AppearanceRootView`: `UserDefaults` key `appearance_mode`, `preferredColorScheme`, Theme + UIKit chrome sync.
struct AdminRootShellView: View {
    @AppStorage(Constants.appearanceModeStorageKey) private var appearanceMode = "system"
    @Environment(\.colorScheme) private var colorScheme

    private var resolvedScheme: ColorScheme? {
        switch appearanceMode {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    private var effectiveScheme: ColorScheme {
        resolvedScheme ?? colorScheme
    }

    var body: some View {
        RootView()
            .id(appearanceMode)
            .preferredColorScheme(resolvedScheme)
            .tint(Theme.primaryColor)
            .onAppear { syncChrome() }
            .onChange(of: appearanceMode) { _, _ in syncChrome() }
            .onChange(of: colorScheme) { _, _ in syncChrome() }
    }

    private func syncChrome() {
        Theme.effectiveColorScheme = effectiveScheme
        AdminLayout.applyGlobalUIKitChrome(isDark: effectiveScheme == .dark)
    }
}

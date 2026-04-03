import SwiftUI

@main
struct MypreluraApp: App {
    @State private var session = AdminSession()
    @State private var showSplash = true

    init() {
        Theme.effectiveColorScheme = .dark
        AdminLayout.applyGlobalUIKitChrome(isDark: true)
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if showSplash {
                    SplashView {
                        showSplash = false
                    }
                } else {
                    AdminRootShellView()
                }
            }
            .environment(session)
        }
    }
}

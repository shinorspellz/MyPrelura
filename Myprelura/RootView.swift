import SwiftUI

struct RootView: View {
    @Environment(AdminSession.self) private var session

    var body: some View {
        Group {
            if session.isSignedIn {
                if AdminLayout.prefersDesktopNavigation {
                    AdminDesktopShell()
                } else {
                    MainTabView()
                }
            } else {
                LoginView()
            }
        }
        .task {
            await session.bootstrapIfNeeded()
        }
    }
}

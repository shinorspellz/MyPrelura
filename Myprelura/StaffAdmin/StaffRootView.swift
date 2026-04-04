import SwiftUI

struct StaffRootView: View {
    @Environment(AdminSession.self) private var session
    @EnvironmentObject private var authService: AuthService

    var body: some View {
        Group {
            if session.isSignedIn {
                if AdminLayout.prefersDesktopNavigation {
                    AdminDesktopShell()
                } else {
                    StaffMainTabView()
                }
            } else {
                StaffAdminLoginView()
            }
        }
        .task {
            await session.bootstrapIfNeeded()
            authService.reloadTokensFromStorage()
        }
        .onChange(of: session.accessToken) { _, _ in
            authService.reloadTokensFromStorage()
        }
        .onChange(of: session.refreshToken) { _, _ in
            authService.reloadTokensFromStorage()
        }
        .onChange(of: session.username) { _, _ in
            authService.reloadTokensFromStorage()
        }
    }
}

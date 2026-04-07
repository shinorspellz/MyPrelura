import SwiftUI

struct StaffRootView: View {
    @Environment(AdminSession.self) private var session
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var appRouter: AppRouter

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
            if session.isSignedIn {
                ConsoleHealthBackgroundMonitor.shared.attach(session: session)
            }
        }
        .onChange(of: session.isSignedIn) { _, signedIn in
            if signedIn {
                ConsoleHealthBackgroundMonitor.shared.attach(session: session)
            } else {
                ConsoleHealthBackgroundMonitor.shared.detachOnSignOut()
            }
        }
        .onChange(of: session.accessLevel) { _, _ in
            if session.isSignedIn {
                ConsoleHealthBackgroundMonitor.shared.attach(session: session)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            ConsoleHealthBackgroundMonitor.shared.onAppBecameActive()
        }
        .fullScreenCover(isPresented: Binding(
            get: { appRouter.pendingStaffConsoleOpen },
            set: { new in
                if !new { appRouter.clearPendingStaffConsole() }
            }
        )) {
            NavigationStack {
                ConsoleView()
                    .environment(session)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { appRouter.clearPendingStaffConsole() }
                        }
                    }
            }
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

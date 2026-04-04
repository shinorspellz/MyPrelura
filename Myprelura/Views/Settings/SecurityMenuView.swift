import SwiftUI

/// Security & Privacy (from Flutter security_menu.dart). Menu list: Blocklist, Reset Password, Delete Account, Pause Account.
struct SecurityMenuView: View {
    var body: some View {
        List {
            NavigationLink(destination: MyReportsView()) {
                securityRow("My reports", icon: "flag")
            }
            NavigationLink(destination: BlocklistView()) {
                securityRow("Blocklist", icon: "person.slash")
            }
            NavigationLink(destination: ResetPasswordView()) {
                securityRow("Reset Password", icon: "key")
            }
            NavigationLink(destination: DeleteAccountView()) {
                securityRow("Delete Account", icon: "trash")
            }
            NavigationLink(destination: PauseAccountView()) {
                securityRow("Pause Account", icon: "pause.circle")
            }
        }
        .listStyle(.insetGrouped)
        .background(Theme.Colors.background)
        .navigationTitle(L10n.string("Security & Privacy"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }

    private func securityRow(_ title: String, icon: String) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(Theme.Colors.secondaryText)
            Text(title)
                .foregroundColor(Theme.Colors.primaryText)
        }
    }
}

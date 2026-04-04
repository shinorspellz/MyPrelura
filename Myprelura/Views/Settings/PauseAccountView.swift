import SwiftUI

/// Pause (archive) account: password. Matches Flutter PauseAccount; backend archiveAccount.
struct PauseAccountView: View {
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showConfirm = false
    @State private var showSuccess = false

    private let userService = UserService()

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    Text(L10n.string("Pausing your account will hide your profile and listings. You can reactivate later by logging in."))
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.secondaryText)
                    if let err = errorMessage {
                        Text(err)
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.error)
                    }
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text(L10n.string("Password"))
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.secondaryText)
                        SettingsTextField(
                            placeholder: "Enter password",
                            text: $password,
                            isSecure: true
                        )
                    }
                }
                .padding(Theme.Spacing.md)
                .padding(.bottom, 100)
            }
            .background(Theme.Colors.background)

            PrimaryButtonBar {
                PrimaryGlassButton(
                    "Pause Account",
                    isEnabled: !password.isEmpty,
                    isLoading: isLoading,
                    action: { showConfirm = true }
                )
            }
        }
        .navigationTitle(L10n.string("Pause Account"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .confirmationDialog("Pause account?", isPresented: $showConfirm, titleVisibility: .visible) {
            Button("Pause Account") {
                Task { await pauseAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(L10n.string("Your profile and listings will be hidden until you log in again."))
        }
        .alert("Account paused", isPresented: $showSuccess) {
            Button("OK") {
                Task { await authService.logout() }
            }
        } message: {
            Text(L10n.string("Your account has been paused. You will be signed out."))
        }
    }

    private func pauseAccount() async {
        guard !password.isEmpty else { return }
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            try await userService.archiveAccount(password: password)
            showSuccess = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

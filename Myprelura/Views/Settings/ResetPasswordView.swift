import SwiftUI

/// Reset password: current, new, confirm. Matches Flutter ResetPasswordScreen.
struct ResetPasswordView: View {
    @EnvironmentObject var authService: AuthService

    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showSuccess = false

    private let userService = UserService()

    private var canSubmit: Bool {
        !currentPassword.isEmpty && !newPassword.isEmpty && !confirmPassword.isEmpty && newPassword == confirmPassword
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    if let err = errorMessage {
                        Text(err)
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.error)
                    }
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text(L10n.string("Current Password"))
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.secondaryText)
                        SettingsTextField(
                            placeholder: "Enter current password",
                            text: $currentPassword,
                            isSecure: true
                        )
                    }
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text(L10n.string("New Password"))
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.secondaryText)
                        SettingsTextField(
                            placeholder: "Enter new password",
                            text: $newPassword,
                            isSecure: true
                        )
                    }
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text(L10n.string("Confirm New Password"))
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.secondaryText)
                        SettingsTextField(
                            placeholder: "Confirm new password",
                            text: $confirmPassword,
                            isSecure: true
                        )
                        if !confirmPassword.isEmpty && newPassword != confirmPassword {
                            Text(L10n.string("Passwords do not match"))
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.error)
                        }
                    }
                }
                .padding(Theme.Spacing.md)
                .padding(.bottom, 100)
            }
            .background(Theme.Colors.background)

            PrimaryButtonBar {
                PrimaryGlassButton(
                    "Reset Password",
                    isEnabled: canSubmit,
                    isLoading: isLoading,
                    action: { Task { await resetPassword() } }
                )
            }
        }
        .navigationTitle(L10n.string("Reset Password"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .alert("Password updated", isPresented: $showSuccess) {
            Button("OK") {
                currentPassword = ""
                newPassword = ""
                confirmPassword = ""
                errorMessage = nil
            }
        } message: {
            Text(L10n.string("Your password has been changed successfully."))
        }
    }

    private func resetPassword() async {
        guard canSubmit else { return }
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            try await userService.passwordChange(currentPassword: currentPassword, newPassword: newPassword)
            showSuccess = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

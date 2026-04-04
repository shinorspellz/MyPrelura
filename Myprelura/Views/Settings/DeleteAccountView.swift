import SwiftUI

/// Delete account: password + confirm. Matches Flutter DeleteAccount.
struct DeleteAccountView: View {
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showConfirm = false

    private let userService = UserService()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                Text(L10n.string("Deleting your account is permanent. You will lose access to your listings, messages, and data."))
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
                Spacer(minLength: Theme.Spacing.xl)
                Button {
                    showConfirm = true
                } label: {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text(L10n.string("Delete Account"))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.md)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.Colors.error)
                .disabled(password.isEmpty || isLoading)
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.Colors.background)
        .navigationTitle(L10n.string("Delete Account"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .confirmationDialog("Delete account?", isPresented: $showConfirm, titleVisibility: .visible) {
            Button("Delete Account", role: .destructive) {
                Task { await deleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(L10n.string("This action cannot be undone. All your data will be permanently removed."))
        }
    }

    private func deleteAccount() async {
        guard !password.isEmpty else { return }
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            try await userService.deleteAccount(password: password)
            await authService.logout()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

import SwiftUI

/// Forgot password: enter email, send reset link (Flutter ForgotPasswordScreen).
struct ForgotPasswordView: View {
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) private var dismiss
    @State private var email: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showEmailSent = false

    var body: some View {
        Group {
            if showEmailSent {
                emailSentContent
            } else {
                ZStack(alignment: .bottom) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                            Text(L10n.string("Enter the email address associated with your account and we'll send you a link to reset your password."))
                                .font(Theme.Typography.body)
                                .foregroundColor(Theme.Colors.secondaryText)
                            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                Text("Email")
                                    .font(Theme.Typography.subheadline)
                                    .foregroundColor(Theme.Colors.secondaryText)
                                TextField(L10n.string("Enter your email"), text: $email)
                                    .textContentType(.emailAddress)
                                    .keyboardType(.emailAddress)
                                    .textInputAutocapitalization(.never)
                                    .textFieldStyle(PlainTextFieldStyle())
                                    .padding(Theme.Spacing.md)
                                    .background(Theme.Colors.secondaryBackground)
                                    .cornerRadius(30)
                                    .foregroundColor(Theme.Colors.primaryText)
                            }
                            if let err = errorMessage {
                                Text(err)
                                    .font(Theme.Typography.caption)
                                    .foregroundColor(Theme.Colors.error)
                            }
                        }
                        .padding(Theme.Spacing.lg)
                        .padding(.bottom, 100)
                    }
                    PrimaryButtonBar {
                        PrimaryGlassButton("Send reset link", isLoading: isLoading, action: submit)
                            .disabled(!isValidEmail(email))
                    }
                }
            }
        }
        .background(Theme.Colors.background)
        .navigationTitle(L10n.string("Forgot Password"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .foregroundColor(Theme.primaryColor)
                    .buttonStyle(HapticTapButtonStyle())
            }
        }
    }

    private var emailSentContent: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: "envelope.badge")
                .font(.system(size: 64))
                .foregroundColor(Theme.primaryColor)
            Text(L10n.string("Check your email"))
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.primaryText)
            Text("We've sent a 6-digit code to \(email). Enter it on the next screen to set a new password.")
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            NavigationLink(destination: NewPasswordView(email: email.trimmingCharacters(in: .whitespacesAndNewlines)).environmentObject(authService)) {
                Text(L10n.string("Enter code"))
                    .font(Theme.Typography.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.md)
            }
            .buttonStyle(HapticTapButtonStyle(haptic: { HapticManager.primaryAction() }))
            .glassEffect(.clear.tint(Theme.primaryColor), in: .rect(cornerRadius: 30))
            Button("Back to login") { dismiss() }
                .font(Theme.Typography.body)
                .foregroundColor(Theme.primaryColor)
                .buttonStyle(HapticTapButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Spacing.lg)
    }

    private func isValidEmail(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#
        return t.range(of: pattern, options: .regularExpression) != nil
    }

    private func submit() {
        let e = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidEmail(e) else {
            errorMessage = "Please enter a valid email address"
            return
        }
        errorMessage = nil
        isLoading = true
        Task {
            do {
                try await authService.requestPasswordReset(email: e)
                await MainActor.run { showEmailSent = true }
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
            await MainActor.run { isLoading = false }
        }
    }
}

#Preview {
    NavigationStack {
        ForgotPasswordView()
            .environmentObject(AuthService())
    }
}

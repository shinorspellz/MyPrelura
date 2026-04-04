import SwiftUI

/// Email/link verification (Flutter VerifyUserRoute /verify/:token). Verifies token and shows success or error.
struct VerifyUserView: View {
    let token: String

    @EnvironmentObject var authService: AuthService
    @State private var status: Status = .verifying
    @State private var errorMessage: String?

    enum Status {
        case verifying
        case success
        case failure
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            switch status {
            case .verifying:
                ProgressView()
                    .scaleEffect(1.2)
                    .tint(Theme.primaryColor)
                Text("Verifying your email...")
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.secondaryText)
            case .success:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundColor(Theme.primaryColor)
                Text("Email verified")
                    .font(Theme.Typography.title2)
                    .foregroundColor(Theme.Colors.primaryText)
                Text("You can now log in to your account.")
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.secondaryText)
            case .failure:
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundColor(Theme.Colors.error)
                Text("Verification failed")
                    .font(Theme.Typography.title2)
                    .foregroundColor(Theme.Colors.primaryText)
                if let err = errorMessage {
                    Text(err)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.secondaryText)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.background)
        .onAppear {
            verify()
        }
    }

    private func verify() {
        Task {
            do {
                let success = try await authService.verifyAccount(code: token)
                await MainActor.run {
                    status = success ? .success : .failure
                    if !success { errorMessage = "Verification failed." }
                }
            } catch {
                await MainActor.run {
                    status = .failure
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

#Preview {
    VerifyUserView(token: "abc123")
        .environmentObject(AuthService())
}

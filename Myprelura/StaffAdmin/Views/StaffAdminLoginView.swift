import SwiftUI

/// Staff login only — visual language matches `PreluraSwift` login (logo, rounded fields, primary CTA) without consumer signup / video.
struct StaffAdminLoginView: View {
    @Environment(AdminSession.self) private var session
    @EnvironmentObject private var authService: AuthService
    @State private var username = Constants.prefilledStaffUsername
    @State private var password = Constants.prefilledStaffPassword
    @State private var showPassword = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.background
                    .ignoresSafeArea()
                ScrollView {
                    VStack(spacing: Theme.Spacing.lg) {
                        VStack(spacing: Theme.Spacing.sm) {
                            Image("PreluraLogo")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: 44)
                            Text("Myprelura")
                                .font(Theme.Typography.title2)
                                .foregroundStyle(Theme.Colors.primaryText)
                            Text("Staff & admin sign-in")
                                .font(Theme.Typography.subheadline)
                                .foregroundStyle(Theme.Colors.secondaryText)
                        }
                        .padding(.top, Theme.Spacing.xl)
                        .adminDesktopReadableWidth()

                        VStack(spacing: Theme.Spacing.md) {
                            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                Text("Username")
                                    .font(Theme.Typography.subheadline)
                                    .foregroundStyle(Theme.Colors.secondaryText)
                                TextField("Enter your username", text: $username)
                                    .textFieldStyle(.plain)
                                    .padding(Theme.Spacing.md)
                                    .background(Theme.Colors.secondaryBackground)
                                    .clipShape(RoundedRectangle(cornerRadius: 30))
                                    .foregroundStyle(Theme.Colors.primaryText)
                                    .textContentType(.username)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                            }
                            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                Text("Password")
                                    .font(Theme.Typography.subheadline)
                                    .foregroundStyle(Theme.Colors.secondaryText)
                                HStack(spacing: Theme.Spacing.sm) {
                                    Group {
                                        if showPassword {
                                            TextField("Enter your password", text: $password)
                                        } else {
                                            SecureField("Enter your password", text: $password)
                                        }
                                    }
                                    .textFieldStyle(.plain)
                                    .foregroundStyle(Theme.Colors.primaryText)
                                    Button(action: { showPassword.toggle() }) {
                                        Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                                            .font(.system(size: 18))
                                            .foregroundStyle(Theme.Colors.secondaryText)
                                    }
                                    .buttonStyle(PlainTappableButtonStyle())
                                }
                                .padding(Theme.Spacing.md)
                                .background(Theme.Colors.secondaryBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 30))
                            }
                            if let errorMessage {
                                Text(errorMessage)
                                    .font(Theme.Typography.caption)
                                    .foregroundStyle(Theme.Colors.error)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            PrimaryButton(title: "Sign in", isLoading: isLoading) {
                                Task { await signIn() }
                            }
                            Text("No public registration. Use `adminLogin` credentials from Django.")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.tertiaryText)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, Theme.Spacing.lg)
                        .adminDesktopReadableWidth()

                        Spacer(minLength: Theme.Spacing.xxl)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .adminNavigationChrome()
        }
    }

    private func signIn() async {
        errorMessage = nil
        let u = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !u.isEmpty, !password.isEmpty else {
            errorMessage = "Enter username and password."
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            try await session.signIn(username: u, password: password)
            authService.reloadTokensFromStorage()
        } catch let e as GraphQLError {
            errorMessage = e.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authService: AuthService
    /// Demo credentials for testing; pre-filled so you don't have to type each time.
    @State private var username: String = "Testuser"
    @State private var password: String = "Password123!!!"
    @State private var showPassword: Bool = false
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var showSignup: Bool = false
    @State private var showForgotPassword: Bool = false
    @State private var showEmailVerificationCode: Bool = false
    @State private var loginVideoURL: URL?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                VideoBackgroundView(videoURL: loginVideoURL, overlayOpacity: 0.45)
                ScrollView {
                    VStack(spacing: Theme.Spacing.lg) {
                        // Header
                        VStack(spacing: Theme.Spacing.sm) {
                            Image("PreluraLogo")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: 44)
                            Text(L10n.string("Welcome back"))
                                .font(Theme.Typography.title2)
                                .foregroundColor(Theme.Colors.authOverVideoText)
                        }
                        .padding(.top, Theme.Spacing.xl)

                        // Form
                        VStack(spacing: Theme.Spacing.md) {
                            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                Text(L10n.string("Username"))
                                    .font(Theme.Typography.subheadline)
                                    .foregroundColor(Theme.Colors.authOverVideoText)
                                TextField(L10n.string("Enter your username"), text: $username)
                                    .textFieldStyle(PlainTextFieldStyle())
                                    .padding(Theme.Spacing.md)
                                    .background(Theme.Colors.secondaryBackground)
                                    .cornerRadius(30)
                                    .foregroundColor(Theme.Colors.primaryText)
                            }
                            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                Text(L10n.string("Password"))
                                    .font(Theme.Typography.subheadline)
                                    .foregroundColor(Theme.Colors.authOverVideoText)
                                HStack(spacing: Theme.Spacing.sm) {
                                    Group {
                                        if showPassword {
                                            TextField(L10n.string("Enter your password"), text: $password)
                                        } else {
                                            SecureField(L10n.string("Enter your password"), text: $password)
                                        }
                                    }
                                    .textFieldStyle(PlainTextFieldStyle())
                                    .foregroundColor(Theme.Colors.primaryText)
                                    Button(action: { showPassword.toggle() }) {
                                        Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                                            .font(.system(size: 18))
                                            .foregroundColor(Theme.Colors.authOverVideoText)
                                    }
                                    .buttonStyle(PlainTappableButtonStyle())
                                }
                                .padding(Theme.Spacing.md)
                                .background(Theme.Colors.secondaryBackground)
                                .cornerRadius(30)
                            }
                            if let error = errorMessage {
                                Text(error)
                                    .font(Theme.Typography.caption)
                                    .foregroundColor(.red)
                                    .padding(.horizontal, Theme.Spacing.md)
                                if error.localizedCaseInsensitiveContains("verify") && error.localizedCaseInsensitiveContains("email") {
                                    Button("Enter verification code") {
                                        showEmailVerificationCode = true
                                    }
                                    .font(Theme.Typography.caption)
                                    .foregroundColor(Theme.primaryColor)
                                    .padding(.top, Theme.Spacing.xs)
                                }
                            }
                            Button(L10n.string("Forgot password?")) {
                                showForgotPassword = true
                            }
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.primaryColor)
                            .buttonStyle(HapticTapButtonStyle())
                        }
                        .padding(.horizontal, Theme.Spacing.lg)

                        HStack {
                            Text(L10n.string("Don't have an account?"))
                                .font(Theme.Typography.body)
                                .foregroundColor(Theme.Colors.authOverVideoText)
                            Button(action: { showSignup = true }) {
                                Text(L10n.string("Sign up"))
                                    .font(Theme.Typography.body)
                                    .foregroundColor(Theme.primaryColor)
                            }
                            .buttonStyle(HapticTapButtonStyle())
                        }
                        .padding(.bottom, 100)
                    }
                }

                VStack(spacing: Theme.Spacing.md) {
                    BorderGlassButton(L10n.string("Continue as guest"), action: { authService.continueAsGuest() })
                        .padding(.horizontal, Theme.Spacing.md)

                    PrimaryGlassButton(
                        L10n.string("Login"),
                        isEnabled: !username.isEmpty && !password.isEmpty,
                        isLoading: isLoading,
                        action: handleLogin
                    )
                    .padding(.horizontal, Theme.Spacing.md)
                }
                .padding(.top, Theme.Spacing.sm)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity)
            }
            .navigationBarHidden(true)
            .onAppear {
                if loginVideoURL == nil {
                    loginVideoURL = AuthVideo.randomLoginVideoURL()
                }
            }
            .navigationDestination(isPresented: $showSignup) {
                SignupView()
            }
            .sheet(isPresented: $showForgotPassword) {
                NavigationStack {
                    ForgotPasswordView()
                        .environmentObject(authService)
                }
                .scrollContentBackground(.hidden)
            }
            .fullScreenCover(isPresented: $showEmailVerificationCode) {
                NavigationStack {
                    EmailVerificationCodeView(
                        username: username,
                        password: password,
                        onDismiss: { showEmailVerificationCode = false },
                        onVerifiedAndLoggedIn: {
                            showEmailVerificationCode = false
                            authService.shouldShowOnboardingAfterLogin = true
                        }
                    )
                    .environmentObject(authService)
                }
            }
        }
    }
    
    private func handleLogin() {
        guard !username.isEmpty, !password.isEmpty else { return }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                _ = try await authService.login(username: username, password: password)
                // Login successful - navigation will be handled by app state
                isLoading = false
            } catch {
                isLoading = false
                let msg = error.localizedDescription
                errorMessage = msg
                // Do not auto-open verify screen: user stays on login and can tap "Enter verification code" if needed
            }
        }
    }
}

#Preview {
    LoginView()
        .preferredColorScheme(.dark)
}

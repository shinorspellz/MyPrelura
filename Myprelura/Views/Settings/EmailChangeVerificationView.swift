import SwiftUI

/// Shown after user requests an email change: enter the 4-digit code sent to the new email to complete verification.
/// On success calls onVerified (no login; user is already logged in).
struct EmailChangeVerificationView: View {
    let newEmail: String
    var onDismiss: () -> Void
    var onVerified: () -> Void

    @EnvironmentObject var authService: AuthService
    @State private var codeString: String = ""
    @State private var isVerifying: Bool = false
    @State private var isResending: Bool = false
    @State private var resendMessage: String?
    @State private var errorMessage: String?
    @FocusState private var focusedIndex: Int?

    private let codeLength = 4
    private let boxSize: CGFloat = 56
    private let boxCornerRadius: CGFloat = 16

    private var codeTrimmed: String {
        String(codeString.prefix(codeLength)).uppercased()
    }
    private var canSubmit: Bool {
        codeTrimmed.count == codeLength
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // Single full-bleed background (matches login EmailVerificationCodeView) to avoid two-tone split
                Theme.Colors.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Theme.Spacing.xl) {
                        Text(L10n.string("Verify your new email"))
                            .font(Theme.Typography.title2)
                            .foregroundColor(Theme.Colors.primaryText)
                        Text("Enter the 4-digit code we sent to \(newEmail).")
                            .font(Theme.Typography.body)
                            .foregroundColor(Theme.Colors.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        HStack(spacing: Theme.Spacing.sm) {
                            ForEach(0..<codeLength, id: \.self) { index in
                                digitField(index: index)
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.lg)
                        .padding(.top, Theme.Spacing.md)

                        if let err = errorMessage {
                            Text(err)
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.error)
                                .padding(.horizontal)
                        }
                        if let msg = resendMessage {
                            Text(msg)
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.primaryText)
                                .padding(.horizontal)
                        }

                        Button(L10n.string("Didn't get the code?")) {
                            resendCode()
                        }
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.primaryColor)
                        .padding(.top, Theme.Spacing.sm)
                        .disabled(isResending)
                    }
                    .padding(.top, Theme.Spacing.xl)
                    .padding(.bottom, 120)
                }
                .scrollContentBackground(.hidden)

                PrimaryButtonBar {
                    PrimaryGlassButton(L10n.string("Verify"), isLoading: isVerifying, action: verify)
                        .disabled(!canSubmit)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.Colors.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("Cancel")) {
                        onDismiss()
                    }
                    .foregroundColor(Theme.primaryColor)
                }
            }
            .toolbarBackground(Theme.Colors.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .onAppear {
                focusedIndex = 0
            }
        }
    }

    private static func normalizedCodeCharacter(_ c: Character) -> Character? {
        if c.isNumber { return c }
        if c.isLetter { return Character(c.uppercased()) }
        return nil
    }

    private func digitField(index: Int) -> some View {
        TextField("", text: Binding(
            get: {
                guard index < codeString.count else { return "" }
                let i = codeString.index(codeString.startIndex, offsetBy: index)
                return String(codeString[i])
            },
            set: { newValue in
                let uppercased = newValue.uppercased()
                let allowed = uppercased.compactMap { Self.normalizedCodeCharacter($0) }
                var newCode = codeString
                if allowed.count > 1 {
                    newCode = String(allowed.prefix(codeLength)).uppercased()
                    codeString = newCode
                    DispatchQueue.main.async {
                        focusedIndex = newCode.count >= codeLength ? nil : min(newCode.count, codeLength - 1)
                    }
                    return
                }
                if let ch = allowed.first {
                    if index < newCode.count {
                        let i = newCode.index(newCode.startIndex, offsetBy: index)
                        newCode.replaceSubrange(i...i, with: String(ch))
                    } else {
                        newCode.append(ch)
                    }
                    newCode = String(newCode.prefix(codeLength))
                    codeString = newCode
                    DispatchQueue.main.async {
                        if index < codeLength - 1 && newCode.count > index + 1 {
                            focusedIndex = index + 1
                        } else if newCode.count >= codeLength {
                            focusedIndex = nil
                        }
                    }
                } else {
                    if index < newCode.count {
                        let i = newCode.index(newCode.startIndex, offsetBy: index)
                        newCode.remove(at: i)
                        codeString = newCode
                        DispatchQueue.main.async {
                            focusedIndex = min(index, newCode.count)
                        }
                    }
                }
            }
        ))
        .keyboardType(.numberPad)
        .textInputAutocapitalization(.characters)
        .autocorrectionDisabled()
        .font(.system(size: 24, weight: .semibold, design: .rounded))
        .multilineTextAlignment(.center)
        .foregroundColor(Theme.Colors.primaryText)
        .focused($focusedIndex, equals: index)
        .frame(width: boxSize, height: boxSize)
        .background(Theme.Colors.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: boxCornerRadius))
    }

    private func verify() {
        guard canSubmit else { return }
        errorMessage = nil
        resendMessage = nil
        isVerifying = true
        Task {
            do {
                let success = try await authService.verifyAccount(code: codeTrimmed)
                await MainActor.run {
                    isVerifying = false
                    if success {
                        onVerified()
                    } else {
                        errorMessage = L10n.string("Invalid or expired code.")
                    }
                }
            } catch {
                await MainActor.run {
                    isVerifying = false
                    errorMessage = verificationErrorMessage(from: error)
                }
            }
        }
    }

    private func verificationErrorMessage(from error: Error) -> String {
        let msg = error.localizedDescription
        if msg.localizedCaseInsensitiveContains("expired") {
            return L10n.string("This code has expired. Tap \"Didn't get the code?\" to request a new one.")
        }
        if msg.localizedCaseInsensitiveContains("invalid") && (msg.localizedCaseInsensitiveContains("code") || msg.localizedCaseInsensitiveContains("verification")) {
            return L10n.string("Invalid verification code. Please check and try again.")
        }
        return msg
    }

    private func resendCode() {
        errorMessage = nil
        resendMessage = nil
        isResending = true
        Task {
            do {
                _ = try await authService.resendActivationEmail(email: newEmail)
                await MainActor.run {
                    isResending = false
                    resendMessage = L10n.string("Verification code sent. Check your email.")
                }
            } catch {
                await MainActor.run {
                    isResending = false
                    resendMessage = error.localizedDescription
                }
            }
        }
    }
}

import SwiftUI

/// Account Settings (from Flutter account_setting_view). Form: first name, last name, email, phone, DOB, gender (no profile-only fields).
/// Uses same API as Flutter: ViewMe for load, updateProfile + changeEmail for save. Bio/username/location are in Profile settings.
struct AccountSettingsView: View {
    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var email: String = ""
    @State private var phone: String = ""
    @State private var dateOfBirth: Date?
    @State private var dateOfBirthText: String = ""
    @State private var gender: String = ""

    @State private var isLoading = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showDatePicker = false
    @State private var showGenderPicker = false
    @State private var showSuccess = false
    @State private var pendingPhoneVerification: PendingPhoneVerification?
    @State private var phoneOtpCode: String = ""
    @State private var phoneOtpError: String?
    @State private var isSendingPhoneOtp = false
    @State private var isVerifyingPhoneOtp = false
    @FocusState private var focusedField: Field?
    @State private var loadedUser: User?
    /// When non-nil, we've requested an email change; show verification sheet so user enters the new code.
    @State private var pendingEmailVerification: PendingEmail?
    @EnvironmentObject private var authService: AuthService

    private let userService = UserService()

    private enum Field { case firstName, lastName, email, phone }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    SettingsTextField(
                        placeholder: L10n.string("First name"),
                        text: $firstName,
                        textContentType: .givenName
                    )
                    .focused($focusedField, equals: .firstName)

                    SettingsTextField(
                        placeholder: L10n.string("Last name"),
                        text: $lastName,
                        textContentType: .familyName
                    )
                    .focused($focusedField, equals: .lastName)

                    SettingsTextField(
                        placeholder: "Email",
                        text: $email,
                        keyboardType: .emailAddress,
                        textContentType: .emailAddress
                    )
                    .focused($focusedField, equals: .email)

                    VStack(alignment: .leading, spacing: 6) {
                        phoneField
                        Text("UK number only (without +44)")
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.secondaryText)
                            .padding(.horizontal, Theme.Spacing.sm)
                    }

                    SettingsTextField(
                        placeholder: "Date of birth",
                        text: $dateOfBirthText,
                        isEnabled: false,
                        onTap: { showDatePicker = true }
                    )

                    SettingsTextField(
                        placeholder: L10n.string("Gender"),
                        text: $gender,
                        isEnabled: false,
                        onTap: { showGenderPicker = true }
                    )

                    if let err = errorMessage {
                        Text(err)
                            .font(Theme.Typography.caption)
                            .foregroundColor(.red)
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.lg)
                .padding(.bottom, 100)
            }
            .background(Theme.Colors.background)

            PrimaryButtonBar {
                PrimaryGlassButton("Save", isLoading: isSaving, action: save)
            }
        }
        .navigationTitle(L10n.string("Account"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .onAppear(perform: loadUser)
        .sheet(isPresented: $showDatePicker) { datePickerSheet }
        .sheet(isPresented: $showGenderPicker) { genderPickerSheet }
        .sheet(item: $pendingEmailVerification) { wrapper in
            EmailChangeVerificationView(
                newEmail: wrapper.email,
                onDismiss: { pendingEmailVerification = nil },
                onVerified: {
                    pendingEmailVerification = nil
                    showSuccess = true
                    loadUser()
                }
            )
            .environmentObject(authService)
        }
        .sheet(item: $pendingPhoneVerification) { wrapper in
            phoneVerificationSheet(for: wrapper)
        }
        .alert(L10n.string("Saved"), isPresented: $showSuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(L10n.string("Your account settings have been updated."))
        }
    }

    private var datePickerSheet: some View {
        NavigationStack {
            DatePicker("Date of birth", selection: Binding(
                get: { dateOfBirth ?? Date() },
                set: { dateOfBirth = $0; dateOfBirthText = formatDOB($0) }
            ), displayedComponents: .date)
            .datePickerStyle(.graphical)
            .padding()
            .navigationTitle(L10n.string("Date of birth"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showDatePicker = false }
                        .foregroundColor(Theme.primaryColor)
                }
            }
        }
    }

    private var genderPickerSheet: some View {
        NavigationStack {
            List(["Male", "Female"], id: \.self) { option in
                Button(option) {
                    gender = option
                    showGenderPicker = false
                }
            }
            .navigationTitle(L10n.string("Gender"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func formatDOB(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "dd-MM-yyyy"
        return f.string(from: date)
    }

    private func loadUser() {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let user = try await userService.getUser()
                await MainActor.run {
                    loadedUser = user
                    let (first, last) = Self.splitDisplayName(user.displayName)
                    firstName = first
                    lastName = last
                    email = user.email ?? ""
                    phone = nationalPhoneSuffix(from: user.phoneDisplay)
                    dateOfBirth = user.dateOfBirth
                    dateOfBirthText = user.dateOfBirth.map { formatDOB($0) } ?? ""
                    gender = user.gender ?? ""
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

    /// Split "First Last" into (first, last); single word becomes (word, "").
    private static func splitDisplayName(_ displayName: String) -> (String, String) {
        let parts = displayName.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        if parts.count >= 2 {
            return (String(parts[0]), String(parts[1]))
        }
        if parts.count == 1 {
            return (String(parts[0]), "")
        }
        return ("", "")
    }

    @ViewBuilder
    private func phoneVerificationSheet(for pending: PendingPhoneVerification) -> some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text("Enter the 6-digit code sent to \(pending.displayPhone)")
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.secondaryText)
                TextField("OTP code", text: $phoneOtpCode)
                    .keyboardType(.numberPad)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .padding(.horizontal, Theme.Spacing.md)
                    .frame(height: 56)
                    .background(Theme.Colors.secondaryBackground)
                    .clipShape(Capsule())
                    .onChange(of: phoneOtpCode) { _, newValue in
                        phoneOtpCode = String(newValue.filter(\.isNumber).prefix(6))
                        phoneOtpError = nil
                    }
                if let phoneOtpError {
                    Text(phoneOtpError)
                        .font(Theme.Typography.caption)
                        .foregroundColor(.red)
                }
                Spacer()
                PrimaryGlassButton(
                    "Verify and save",
                    isLoading: isVerifyingPhoneOtp,
                    action: verifyPhoneOtpAndSave
                )
                .disabled(phoneOtpCode.count != 6 || isVerifyingPhoneOtp)
                Button(isSendingPhoneOtp ? "Sending..." : "Resend code") {
                    resendPhoneOtp(pending)
                }
                .font(Theme.Typography.body)
                .foregroundColor(Theme.primaryColor)
                .disabled(isSendingPhoneOtp || isVerifyingPhoneOtp)
            }
            .padding(Theme.Spacing.md)
            .navigationTitle("Verify phone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        pendingPhoneVerification = nil
                        phoneOtpCode = ""
                        phoneOtpError = nil
                    }
                }
            }
        }
    }

    private func save() {
        guard let user = loadedUser else { return }
        isSaving = true
        errorMessage = nil
        let emailTrimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let emailChanged = emailTrimmed != (user.email ?? "")
        Task {
            do {
                if emailChanged {
                    try await userService.changeEmail(emailTrimmed)
                    await MainActor.run {
                        isSaving = false
                        pendingEmailVerification = PendingEmail(email: emailTrimmed)
                    }
                    return
                }
                let phoneParsed = parsePhone(phone.trimmingCharacters(in: .whitespacesAndNewlines))
                if hasPhoneChanged(phoneParsed, existing: user.phoneDisplay), let phoneParsed {
                    try await userService.sendPhoneOtp(phoneNumber: "+\(phoneParsed.countryCode)\(phoneParsed.number)")
                    await MainActor.run {
                        isSaving = false
                        phoneOtpCode = ""
                        phoneOtpError = nil
                        pendingPhoneVerification = PendingPhoneVerification(
                            countryCode: phoneParsed.countryCode,
                            number: phoneParsed.number
                        )
                    }
                    return
                }
                try await performProfileUpdate(user: user, verifiedPhone: nil, otp: nil)
                await MainActor.run {
                    isSaving = false
                    showSuccess = true
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSaving = false
                }
            }
        }
    }

    private func resendPhoneOtp(_ pending: PendingPhoneVerification) {
        phoneOtpError = nil
        isSendingPhoneOtp = true
        Task {
            do {
                try await userService.sendPhoneOtp(phoneNumber: pending.e164)
                await MainActor.run {
                    isSendingPhoneOtp = false
                }
            } catch {
                await MainActor.run {
                    isSendingPhoneOtp = false
                    phoneOtpError = error.localizedDescription
                }
            }
        }
    }

    private func verifyPhoneOtpAndSave() {
        guard let user = loadedUser, let pending = pendingPhoneVerification else { return }
        guard phoneOtpCode.count == 6 else {
            phoneOtpError = "Please enter the 6-digit OTP code."
            return
        }
        phoneOtpError = nil
        isVerifyingPhoneOtp = true
        Task {
            do {
                try await performProfileUpdate(
                    user: user,
                    verifiedPhone: (countryCode: pending.countryCode, number: pending.number),
                    otp: phoneOtpCode
                )
                await MainActor.run {
                    isVerifyingPhoneOtp = false
                    pendingPhoneVerification = nil
                    phoneOtpCode = ""
                    showSuccess = true
                    loadUser()
                }
            } catch {
                await MainActor.run {
                    isVerifyingPhoneOtp = false
                    phoneOtpError = error.localizedDescription
                }
            }
        }
    }

    private func performProfileUpdate(
        user: User,
        verifiedPhone: (countryCode: String, number: String)?,
        otp: String?
    ) async throws {
        let firstTrimmed = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let lastTrimmed = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        let genderToSend = gender.isEmpty ? nil : gender
        let parsedFromForm = parsePhone(phone.trimmingCharacters(in: .whitespacesAndNewlines))
        let phoneToSend: (countryCode: String, number: String)? = verifiedPhone ?? {
            guard hasPhoneChanged(parsedFromForm, existing: user.phoneDisplay) else { return nil }
            return parsedFromForm
        }()
        let displayNameToSend: String? = {
            if firstTrimmed.isEmpty && lastTrimmed.isEmpty { return nil }
            if lastTrimmed.isEmpty { return firstTrimmed }
            return "\(firstTrimmed) \(lastTrimmed)"
        }()
        try await userService.updateProfile(
            displayName: displayNameToSend,
            firstName: firstTrimmed.isEmpty ? nil : firstTrimmed,
            lastName: lastTrimmed.isEmpty ? nil : lastTrimmed,
            gender: genderToSend,
            dob: dateOfBirth,
            phoneNumber: phoneToSend,
            otp: otp
        )
    }

    private var phoneField: some View {
        HStack(spacing: Theme.Spacing.sm) {
            HStack(spacing: 6) {
                Text("🇬🇧")
                Text("+44")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.Colors.primaryText)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .frame(height: 56)
            .background(Theme.Colors.secondaryBackground)
            .clipShape(Capsule())

            TextField("Phone", text: $phone)
                .keyboardType(.numberPad)
                .textContentType(.telephoneNumber)
                .focused($focusedField, equals: .phone)
                .onChange(of: phone) { _, newValue in
                    phone = newValue.filter(\.isNumber)
                }
                .padding(.horizontal, Theme.Spacing.md)
                .frame(height: 56)
                .background(Theme.Colors.secondaryBackground)
                .clipShape(Capsule())
        }
    }

    private func hasPhoneChanged(
        _ parsed: (countryCode: String, number: String)?,
        existing: String?
    ) -> Bool {
        let existingDigits = normalizedExistingPhone(existing)
        guard let parsed else {
            return !existingDigits.isEmpty
        }
        return parsed.number != existingDigits
    }

    /// Parse UK national suffix into (countryCode, number). Country code is fixed at +44.
    private func parsePhone(_ raw: String) -> (countryCode: String, number: String)? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var digits = trimmed.filter { $0.isNumber }
        guard !digits.isEmpty else { return nil }
        if digits.hasPrefix("44") {
            digits = String(digits.dropFirst(2))
        } else if digits.hasPrefix("0") {
            digits = String(digits.dropFirst())
        }
        return ("44", digits)
    }

    private func nationalPhoneSuffix(from display: String?) -> String {
        let digits = (display ?? "").filter(\.isNumber)
        guard !digits.isEmpty else { return "" }
        if digits.hasPrefix("44") {
            return String(digits.dropFirst(2))
        }
        return digits
    }

    private func normalizedExistingPhone(_ existing: String?) -> String {
        let suffix = nationalPhoneSuffix(from: existing)
        if suffix.hasPrefix("0") { return String(suffix.dropFirst()) }
        return suffix
    }
}

/// Identifiable wrapper for presenting email-change verification sheet.
private struct PendingEmail: Identifiable {
    let id = UUID()
    let email: String
}

private struct PendingPhoneVerification: Identifiable {
    let id = UUID()
    let countryCode: String
    let number: String

    var e164: String { "+\(countryCode)\(number)" }
    var displayPhone: String { "+\(countryCode) \(number)" }
}

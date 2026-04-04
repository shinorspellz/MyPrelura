import SwiftUI

/// UK withdrawal flow: amount → bank details (sort code, account number, name) → review → submit → success.
struct WithdrawalFlowView: View {
    let availableBalance: Double
    var onDismiss: () -> Void

    @EnvironmentObject private var authService: AuthService
    @State private var payoutBank: PayoutBankAccountDisplay?
    @State private var step: Step = .amount
    @State private var amountText: String = ""
    @State private var sortCode: String = ""
    @State private var accountNumber: String = ""
    @State private var accountHolderName: String = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var didSucceed = false
    @FocusState private var focusedField: Field?
    @Environment(\.dismiss) private var dismiss

    private enum Step {
        case amount
        case bankDetails
        case review
        case success
    }

    private enum Field {
        case amount, sortCode, accountNumber, accountHolderName
    }

    private var amountValue: Double? {
        guard !amountText.isEmpty else { return nil }
        let cleaned = amountText.replacingOccurrences(of: ",", with: ".")
        return Double(cleaned)
    }

    private var isValidAmount: Bool {
        guard let a = amountValue, a > 0 else { return false }
        return a <= availableBalance
    }

    private var canSubmitBank: Bool {
        sortCode.filter { $0.isNumber }.count == 6
            && accountNumber.count == 8
            && !accountHolderName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Last digits shown on saved payout account (e.g. "6096"), from `****6096`.
    private var savedPayoutAccountEnding: String? {
        guard let m = payoutBank?.maskedAccountNumber, m.hasPrefix("****"), m.count > 4 else { return nil }
        return String(m.dropFirst(4))
    }

    private var userService: UserService {
        let s = UserService()
        if let token = authService.authToken { s.updateAuthToken(token) }
        return s
    }

    var body: some View {
        Group {
            if didSucceed {
                successView
            } else {
                NavigationStack {
                    ZStack(alignment: .bottom) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                                switch step {
                                case .amount:
                                    amountStepContent
                                case .bankDetails:
                                    bankDetailsStepContent
                                case .review:
                                    reviewStepContent
                                case .success:
                                    EmptyView()
                                }
                            }
                            .padding(Theme.Spacing.md)
                            .padding(.bottom, 120)
                        }
                        .background(Theme.Colors.background)

                        if step != .success {
                            PrimaryButtonBar {
                                primaryButton
                            }
                        }
                    }
                    .navigationTitle(navigationTitle)
                    .navigationBarTitleDisplayMode(.inline)
                    .task {
                        await loadSavedPayoutBank()
                    }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            if step == .amount || didSucceed {
                                Button(L10n.string("Cancel")) {
                                    onDismiss()
                                    dismiss()
                                }
                                .foregroundColor(Theme.primaryColor)
                            } else {
                                Button(L10n.string("Back")) {
                                    switch step {
                                    case .bankDetails: step = .amount
                                    case .review: step = .bankDetails
                                    default: break
                                    }
                                }
                                .foregroundColor(Theme.primaryColor)
                            }
                        }
                    }
                }
            }
        }
    }

    private func loadSavedPayoutBank() async {
        do {
            let user = try await userService.getUser()
            await MainActor.run { payoutBank = user.payoutBankAccount }
        } catch {
            await MainActor.run { payoutBank = nil }
        }
    }

    private var navigationTitle: String {
        switch step {
        case .amount: return L10n.string("Withdraw")
        case .bankDetails: return L10n.string("Bank details")
        case .review: return L10n.string("Review withdrawal")
        case .success: return L10n.string("Withdraw")
        }
    }

    private var amountStepContent: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text(L10n.string("How much would you like to withdraw?"))
                .font(Theme.Typography.headline)
                .foregroundColor(Theme.Colors.primaryText)

            Text(L10n.string("Available balance"))
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.secondaryText)
            Text(formatCurrency(availableBalance))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.primaryText)

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text(L10n.string("Amount"))
                    .font(Theme.Typography.subheadline)
                    .foregroundColor(Theme.Colors.secondaryText)
                HStack(spacing: Theme.Spacing.sm) {
                    Text("£")
                        .font(Theme.Typography.title2)
                        .foregroundColor(Theme.Colors.secondaryText)
                    SettingsTextField(
                        placeholder: "0.00",
                        text: $amountText,
                        keyboardType: .decimalPad
                    )
                    .focused($focusedField, equals: .amount)
                    .onChange(of: amountText) { _, newValue in
                        let sanitized = PriceFieldFilter.sanitizePriceInput(newValue)
                        if sanitized != newValue { amountText = sanitized }
                    }
                }
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                if let ending = savedPayoutAccountEnding {
                    Text(String(format: L10n.string("Withdrawing to account ending in %@"), ending))
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.secondaryText)
                } else {
                    Text(L10n.string("You'll add your bank details on the next step."))
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.secondaryText)
                }
                Text(L10n.string("Withdrawals usually reach your bank within 30 minutes."))
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.secondaryText)
            }
            .padding(.top, Theme.Spacing.xs)

            if let err = errorMessage {
                Text(err)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.error)
            }
        }
    }

    private var bankDetailsStepContent: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text(L10n.string("Enter your UK bank details. Withdrawals usually reach your bank within 30 minutes."))
                .font(Theme.Typography.subheadline)
                .foregroundColor(Theme.Colors.secondaryText)

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text(L10n.string("Sort code"))
                    .font(Theme.Typography.subheadline)
                    .foregroundColor(Theme.Colors.secondaryText)
                SettingsTextField(
                    placeholder: "00-00-00",
                    text: $sortCode,
                    keyboardType: .numberPad
                )
                .focused($focusedField, equals: .sortCode)
                .onChange(of: sortCode) { _, newValue in
                    sortCode = formatSortCode(newValue)
                }
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text(L10n.string("Account number"))
                    .font(Theme.Typography.subheadline)
                    .foregroundColor(Theme.Colors.secondaryText)
                SettingsTextField(
                    placeholder: "12345678",
                    text: $accountNumber,
                    keyboardType: .numberPad
                )
                .focused($focusedField, equals: .accountNumber)
                .onChange(of: accountNumber) { _, newValue in
                    let filtered = newValue.filter { $0.isNumber }.prefix(8)
                    accountNumber = String(filtered)
                }
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text(L10n.string("Account holder name"))
                    .font(Theme.Typography.subheadline)
                    .foregroundColor(Theme.Colors.secondaryText)
                SettingsTextField(
                    placeholder: "As shown on your bank account",
                    text: $accountHolderName,
                    textContentType: .name
                )
                .focused($focusedField, equals: .accountHolderName)
            }

            if let err = errorMessage {
                Text(err)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.error)
            }
        }
    }

    private var reviewStepContent: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text(L10n.string("Confirm your withdrawal"))
                .font(Theme.Typography.headline)
                .foregroundColor(Theme.Colors.primaryText)

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                reviewRow(L10n.string("Amount"), formatCurrency(amountValue ?? 0))
                reviewRow(L10n.string("Sort code"), sortCode)
                reviewRow(L10n.string("Account number"), accountNumber)
                reviewRow(L10n.string("Account holder"), accountHolderName)
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Colors.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Glass.cornerRadius))

            if let err = errorMessage {
                Text(err)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.error)
            }
        }
    }

    private func reviewRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.secondaryText)
            Spacer()
            Text(value)
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.primaryText)
        }
    }

    private var successView: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(Theme.primaryColor)
            Text(L10n.string("Withdrawal requested"))
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.primaryText)
            Text(L10n.string("Your withdrawal of %@ will usually reach your bank within 30 minutes.").replacingOccurrences(of: "%@", with: formatCurrency(amountValue ?? 0)))
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Spacer()
            PrimaryButtonBar {
                PrimaryGlassButton(L10n.string("Done"), action: {
                    onDismiss()
                    dismiss()
                })
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.bottom, Theme.Spacing.lg)
        }
        .background(Theme.Colors.background)
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch step {
        case .amount:
            PrimaryGlassButton(L10n.string("Continue"), isEnabled: isValidAmount, action: {
                errorMessage = nil
                if amountValue ?? 0 > availableBalance {
                    errorMessage = L10n.string("Amount cannot exceed available balance.")
                } else {
                    step = .bankDetails
                }
            })
        case .bankDetails:
            PrimaryGlassButton(L10n.string("Continue"), isEnabled: canSubmitBank, action: {
                errorMessage = nil
                step = .review
            })
        case .review:
            PrimaryGlassButton(
                L10n.string("Withdraw"),
                isEnabled: true,
                isLoading: isSubmitting,
                action: submitWithdrawal
            )
        case .success:
            EmptyView()
        }
    }

    private func submitWithdrawal() {
        errorMessage = nil
        isSubmitting = true
        // Placeholder: wire to withdrawal API when backend supports it (client-only; no backend change).
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            isSubmitting = false
            didSucceed = true
        }
    }

    private func formatCurrency(_ value: Double) -> String {
        CurrencyFormatter.gbp(value)
    }

    private func formatSortCode(_ raw: String) -> String {
        let digits = raw.filter { $0.isNumber }.prefix(6)
        let s = String(digits)
        if s.count <= 2 { return s }
        if s.count <= 4 { return s.prefix(2) + "-" + s.dropFirst(2) }
        return s.prefix(2) + "-" + s.dropFirst(2).prefix(2) + "-" + s.dropFirst(4)
    }
}

#Preview {
    WithdrawalFlowView(availableBalance: 87, onDismiss: {})
        .environmentObject(AuthService())
}

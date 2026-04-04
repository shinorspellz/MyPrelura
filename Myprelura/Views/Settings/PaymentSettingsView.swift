import SwiftUI

/// Payment settings: fetch active payment method and payout bank account, show card/bank or empty state, Add Card / Add Bank, Delete.
struct PaymentSettingsView: View {
    @State private var paymentMethod: PaymentMethod?
    @State private var payoutBankAccount: PayoutBankAccountDisplay?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isDeleting = false
    @State private var isDeletingBank = false
    @State private var showDeleteConfirm = false
    @State private var showDeleteBankConfirm = false

    @EnvironmentObject private var authService: AuthService
    private let userService = UserService()

    var body: some View {
        List {
            if isLoading && paymentMethod == nil && errorMessage == nil {
                Section {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }
            } else {
                    Section(header: Text(L10n.string("Active Payment method"))) {
                        if let method = paymentMethod {
                            HStack(spacing: Theme.Spacing.md) {
                                Image(systemName: "creditcard.fill")
                                    .font(.system(size: 22))
                                    .foregroundColor(Theme.primaryColor)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(method.cardBrand) •••• \(method.last4Digits)")
                                        .font(Theme.Typography.headline)
                                        .foregroundColor(Theme.Colors.primaryText)
                                    Text(String(format: L10n.string("Card ending in %@"), method.last4Digits))
                                        .font(Theme.Typography.caption)
                                        .foregroundColor(Theme.Colors.secondaryText)
                                }
                                Spacer()
                            }
                            .padding(.vertical, Theme.Spacing.xs)
                            Button(role: .destructive) {
                                showDeleteConfirm = true
                            } label: {
                                HStack {
                                    if isDeleting {
                                        ProgressView()
                                            .scaleEffect(0.9)
                                            .tint(Theme.Colors.error)
                                    } else {
                                        Text(L10n.string("Delete"))
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .disabled(isDeleting || isDeletingBank)
                        } else {
                            Text(L10n.string("No payment method added"))
                                .foregroundColor(Theme.Colors.secondaryText)
                        }
                    }
                    Section(header: Text(L10n.string("Active bank account"))) {
                        if let bank = payoutBankAccount {
                            HStack(spacing: Theme.Spacing.md) {
                                Image(systemName: "building.columns.fill")
                                    .font(.system(size: 22))
                                    .foregroundColor(Theme.primaryColor)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(bank.maskedSortCode)  \(bank.maskedAccountNumber)")
                                        .font(Theme.Typography.headline)
                                        .foregroundColor(Theme.Colors.primaryText)
                                    HStack(alignment: .center, spacing: Theme.Spacing.sm) {
                                        Text(bank.accountHolderName)
                                            .font(Theme.Typography.caption)
                                            .foregroundColor(Theme.Colors.secondaryText)
                                        Spacer(minLength: 0)
                                        if let label = bank.accountLabel, !label.isEmpty {
                                            Text(label)
                                                .font(Theme.Typography.caption)
                                                .foregroundColor(Theme.Colors.secondaryText)
                                                .multilineTextAlignment(.trailing)
                                        }
                                    }
                                }
                                Spacer()
                            }
                            .padding(.vertical, Theme.Spacing.xs)
                            Text(L10n.string("Payouts are sent here when delivery is complete."))
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.secondaryText)
                            Button(role: .destructive) {
                                showDeleteBankConfirm = true
                            } label: {
                                HStack {
                                    if isDeletingBank {
                                        ProgressView()
                                            .scaleEffect(0.9)
                                            .tint(Theme.Colors.error)
                                    } else {
                                        Text(L10n.string("Delete"))
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .disabled(isDeleting || isDeletingBank)
                        } else {
                            Text(L10n.string("No bank account added"))
                                .foregroundColor(Theme.Colors.secondaryText)
                        }
                    }
                    Section {
                        NavigationLink(destination: AddBankAccountView(onSaved: { Task { await load() } })) {
                            Label("Add Bank Account", systemImage: "building.columns")
                                .foregroundColor(Theme.Colors.primaryText)
                        }
                    }
                    if let err = errorMessage {
                        Section {
                            Text(err)
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.error)
                        }
                    }
            }
        }
        .listStyle(.insetGrouped)
        .background(Theme.Colors.background)
        .navigationTitle(L10n.string("Payments"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .refreshable { await load() }
        .task { await load() }
        .confirmationDialog("Remove payment method?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let method = paymentMethod {
                    Task { await deletePaymentMethod(method.paymentMethodId) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(L10n.string("This card will be removed from your account."))
        }
        .confirmationDialog(L10n.string("Remove bank account?"), isPresented: $showDeleteBankConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task { await deletePayoutBankAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(L10n.string("Payouts will not be sent until you add a bank account again."))
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        userService.updateAuthToken(authService.authToken)
        do {
            let method = try await userService.getUserPaymentMethod()
            let user = try await userService.getUser(username: nil)
            await MainActor.run {
                paymentMethod = method
                payoutBankAccount = user.payoutBankAccount
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func deletePaymentMethod(_ id: String) async {
        isDeleting = true
        errorMessage = nil
        defer { isDeleting = false }
        do {
            try await userService.deletePaymentMethod(paymentMethodId: id)
            paymentMethod = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deletePayoutBankAccount() async {
        isDeletingBank = true
        errorMessage = nil
        defer { isDeletingBank = false }
        userService.updateAuthToken(authService.authToken)
        do {
            try await userService.clearPayoutBankAccount()
            payoutBankAccount = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

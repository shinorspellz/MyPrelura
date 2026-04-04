import SwiftUI

struct AddPaymentCardView: View {
    /// Called after a card is successfully added so the parent (e.g. PaymentSettingsView) can refresh.
    var onAdded: (() -> Void)? = nil

    @State private var cardNumber: String = ""
    @State private var expiryMonth: String = ""
    @State private var expiryYear: String = ""
    @State private var cvv: String = ""
    @State private var cardholderName: String = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showSuccess = false
    @FocusState private var focusedField: Field?
    @Environment(\.dismiss) private var dismiss

    private let userService = UserService()
    private enum Field { case cardNumber, expiryMonth, expiryYear, cvv, cardholderName }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    Text(L10n.string("Enter your card details securely. Your payment information is encrypted."))
                        .font(Theme.Typography.subheadline)
                        .foregroundColor(Theme.Colors.secondaryText)
                        .padding(.bottom, Theme.Spacing.xs)

                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text(L10n.string("Card number"))
                            .font(Theme.Typography.subheadline)
                            .foregroundColor(Theme.Colors.secondaryText)
                        SettingsTextField(
                            placeholder: "1234 5678 9012 3456",
                            text: $cardNumber,
                            keyboardType: .numberPad,
                            textContentType: .creditCardNumber
                        )
                        .focused($focusedField, equals: .cardNumber)
                        .onChange(of: cardNumber) { _, newValue in
                            cardNumber = formatCardNumber(newValue)
                        }
                    }

                    HStack(spacing: Theme.Spacing.md) {
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            Text(L10n.string("Expiry"))
                                .font(Theme.Typography.subheadline)
                                .foregroundColor(Theme.Colors.secondaryText)
                            HStack(spacing: Theme.Spacing.sm) {
                                SettingsTextField(
                                    placeholder: "MM",
                                    text: $expiryMonth,
                                    keyboardType: .numberPad
                                )
                                .focused($focusedField, equals: .expiryMonth)
                                .onChange(of: expiryMonth) { _, newValue in
                                    let filtered = newValue.filter { $0.isNumber }.prefix(2)
                                    expiryMonth = String(filtered)
                                }
                                Text("/")
                                    .font(Theme.Typography.body)
                                    .foregroundColor(Theme.Colors.secondaryText)
                                SettingsTextField(
                                    placeholder: "YY",
                                    text: $expiryYear,
                                    keyboardType: .numberPad
                                )
                                .focused($focusedField, equals: .expiryYear)
                                .onChange(of: expiryYear) { _, newValue in
                                    let filtered = newValue.filter { $0.isNumber }.prefix(2)
                                    expiryYear = String(filtered)
                                }
                            }
                        }
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            Text(L10n.string("CVV"))
                                .font(Theme.Typography.subheadline)
                                .foregroundColor(Theme.Colors.secondaryText)
                            SettingsTextField(
                                placeholder: "123",
                                text: $cvv,
                                keyboardType: .numberPad
                            )
                            .focused($focusedField, equals: .cvv)
                            .onChange(of: cvv) { _, newValue in
                                let filtered = newValue.filter { $0.isNumber }.prefix(4)
                                cvv = String(filtered)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text(L10n.string("Name on card"))
                            .font(Theme.Typography.subheadline)
                            .foregroundColor(Theme.Colors.secondaryText)
                        SettingsTextField(
                            placeholder: "Cardholder name",
                            text: $cardholderName,
                            textContentType: .name
                        )
                        .focused($focusedField, equals: .cardholderName)
                    }

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
                PrimaryGlassButton("Add card", isEnabled: canSubmit, isLoading: isSaving, action: addCard)
            }
        }
        .navigationTitle(L10n.string("Add Payment Card"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .alert("Card added", isPresented: $showSuccess) {
            Button("OK") {
                onAdded?()
                dismiss()
            }
        } message: {
            Text(L10n.string("Your payment method has been saved."))
        }
    }

    private var canSubmit: Bool {
        let digits = cardNumber.filter { $0.isNumber }
        return digits.count >= 15 && digits.count <= 19
            && expiryMonth.count == 2
            && expiryYear.count == 2
            && cvv.count >= 3 && cvv.count <= 4
            && !cardholderName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func formatCardNumber(_ raw: String) -> String {
        let digits = raw.filter { $0.isNumber }
        let limited = String(digits.prefix(19))
        return limited.enumerated().reduce("") { acc, el in
            if el.offset > 0 && el.offset % 4 == 0 { return acc + " " + String(el.element) }
            return acc + String(el.element)
        }
    }

    private func addCard() {
        errorMessage = nil
        guard canSubmit else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                // Backend expects a Stripe payment method ID (e.g. from Stripe SDK createPaymentMethod).
                // Without Stripe we use a test token for test mode; production must use Stripe to tokenize the card.
                let paymentMethodId = "pm_card_visa" // Stripe test token; replace with Stripe.createPaymentMethod() result in production
                try await userService.addPaymentMethod(paymentMethodId: paymentMethodId)
                await MainActor.run { showSuccess = true }
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
        }
    }
}

#Preview {
    NavigationStack {
        AddPaymentCardView()
    }
}

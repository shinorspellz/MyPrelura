import SwiftUI

/// Currency setting screen (Flutter CurrencySettingRoute).
struct CurrencySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCurrency: String = "British Pound (GBP)"
    @State private var saved = false

    private let currencies = [
        "British Pound (GBP)",
        "Euro (EUR)",
    ]

    var body: some View {
        List {
            ForEach(currencies, id: \.self) { currency in
                Button {
                    selectedCurrency = currency
                } label: {
                    HStack {
                        Text(currency)
                            .font(Theme.Typography.body)
                            .foregroundColor(Theme.Colors.primaryText)
                        Spacer()
                        if selectedCurrency == currency {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(Theme.primaryColor)
                        }
                    }
                }
                .buttonStyle(PlainTappableButtonStyle())
            }
            if saved {
                Text(L10n.string("Saved"))
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.primaryColor)
            }
        }
        .listStyle(.insetGrouped)
        .background(Theme.Colors.background)
        .navigationTitle(L10n.string("Currency"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    // TODO: Persist currency preference
                    saved = true
                }
                .foregroundColor(Theme.primaryColor)
            }
        }
        .toolbar(.hidden, for: .tabBar)
    }
}

#Preview {
    NavigationStack {
        CurrencySettingsView()
    }
}

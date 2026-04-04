import SwiftUI

/// Shipping Address (from Flutter shipping_address_view). Loads from ViewMe, saves via updateProfile(shippingAddress:).
struct ShippingAddressView: View {
    @State private var addressLine1: String = ""
    @State private var addressLine2: String = ""
    @State private var city: String = ""
    @State private var state: String = ""
    @State private var country: String = "United Kingdom"
    @State private var postcode: String = ""

    @State private var isLoading = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showSuccess = false
    @Environment(\.dismiss) private var dismiss

    private let userService = UserService()

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    Text(L10n.string("Address"))
                        .font(Theme.Typography.headline)
                        .foregroundColor(Theme.Colors.primaryText)

                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text(L10n.string("Address line 1"))
                            .font(Theme.Typography.subheadline)
                            .foregroundColor(Theme.Colors.secondaryText)
                        SettingsTextField(placeholder: "Street address", text: $addressLine1, textContentType: .streetAddressLine1)
                    }
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text(L10n.string("Address line 2 (optional)"))
                            .font(Theme.Typography.subheadline)
                            .foregroundColor(Theme.Colors.secondaryText)
                        SettingsTextField(placeholder: "Apartment, suite, etc.", text: $addressLine2, textContentType: .streetAddressLine2)
                    }
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text(L10n.string("City"))
                            .font(Theme.Typography.subheadline)
                            .foregroundColor(Theme.Colors.secondaryText)
                        SettingsTextField(placeholder: "City", text: $city, textContentType: .addressCity)
                    }
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text(L10n.string("State / County"))
                            .font(Theme.Typography.subheadline)
                            .foregroundColor(Theme.Colors.secondaryText)
                        SettingsTextField(placeholder: "State or county", text: $state, textContentType: .addressState)
                    }
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text(L10n.string("Country"))
                            .font(Theme.Typography.subheadline)
                            .foregroundColor(Theme.Colors.secondaryText)
                        Text(country)
                            .font(Theme.Typography.body)
                            .foregroundColor(Theme.Colors.primaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, Theme.Spacing.md)
                            .background(Theme.Colors.secondaryBackground)
                            .cornerRadius(30)
                    }
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text(L10n.string("Postcode"))
                            .font(Theme.Typography.subheadline)
                            .foregroundColor(Theme.Colors.secondaryText)
                        SettingsTextField(placeholder: "XXX XXX", text: $postcode, textContentType: .postalCode)
                            .onChange(of: postcode) { _, newValue in
                                postcode = formatPostcode(newValue)
                            }
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
                PrimaryGlassButton("Save", isEnabled: canSave, isLoading: isSaving, action: save)
            }
        }
        .navigationTitle(L10n.string("Shipping Address"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .onAppear(perform: loadUser)
        .alert("Saved", isPresented: $showSuccess) {
            Button("OK", role: .cancel) { dismiss() }
        } message: {
            Text(L10n.string("Your shipping address has been updated."))
        }
    }

    /// Required: address line 1, city, postcode (format XXX XXX). Optional: address line 2, state.
    private var canSave: Bool {
        let a = addressLine1.trimmingCharacters(in: .whitespaces)
        let c = city.trimmingCharacters(in: .whitespaces)
        return !a.isEmpty && !c.isEmpty && isPostcodeValid(postcode)
    }

    /// UK postcode format: exactly XXX XXX (3 alphanumeric, space, 3 alphanumeric).
    private func isPostcodeValid(_ value: String) -> Bool {
        let s = value.trimmingCharacters(in: .whitespaces)
        guard s.count == 7 else { return false }
        let parts = s.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].count == 3, parts[1].count == 3 else { return false }
        let allowed = CharacterSet.alphanumerics
        return parts[0].unicodeScalars.allSatisfy { allowed.contains($0) }
            && parts[1].unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    /// Format postcode as XXX XXX: only alphanumeric, auto-insert space after 3rd character, max 7 chars.
    private func formatPostcode(_ raw: String) -> String {
        let filtered = raw.uppercased().filter { $0.isLetter || $0.isNumber }
        let withoutSpace = String(filtered.prefix(6))
        if withoutSpace.count <= 3 {
            return withoutSpace
        }
        return withoutSpace.prefix(3) + " " + withoutSpace.dropFirst(3)
    }

    private func loadUser() {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let user = try await userService.getUser()
                await MainActor.run {
                    if let addr = user.shippingAddress {
                        addressLine1 = addr.address
                        addressLine2 = addr.state ?? ""
                        city = addr.city
                        state = addr.state ?? ""
                        country = addr.country == "GB" ? "United Kingdom" : addr.country
                        postcode = formatPostcode(addr.postcode)
                    } else {
                        country = "United Kingdom"
                    }
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

    private func save() {
        guard canSave else { return }
        let address = addressLine1.trimmingCharacters(in: .whitespaces)
        let cityVal = city.trimmingCharacters(in: .whitespaces)
        let postcodeVal = postcode.trimmingCharacters(in: .whitespaces)
        guard !address.isEmpty, !cityVal.isEmpty, !postcodeVal.isEmpty else { return }
        errorMessage = nil
        isSaving = true
        let shipping = ShippingAddress(
            address: address,
            city: cityVal,
            state: state.isEmpty ? nil : state,
            country: "GB",
            postcode: postcodeVal
        )
        Task {
            do {
                try await userService.updateProfile(shippingAddress: shipping)
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
}

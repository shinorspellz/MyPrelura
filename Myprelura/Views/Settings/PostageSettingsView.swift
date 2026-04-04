import SwiftUI

/// Postage settings (from Flutter postage_settings). Royal Mail (with First Class option), DPD; toggles and price fields.
/// Loads/saves via viewMe meta and updateProfile(meta:). Buyers see these options at checkout.
struct PostageSettingsView: View {
    @State private var royalMailEnabled: Bool = false
    @State private var royalMailStandardPrice: String = ""
    @State private var royalMailStandardDays: String = ""
    @State private var royalMailFirstClassPrice: String = ""
    @State private var royalMailFirstClassDays: String = ""
    @State private var dpdEnabled: Bool = false
    @State private var dpdPrice: String = ""
    @State private var dpdDays: String = ""
    @State private var evriEnabled: Bool = false
    @State private var evriPrice: String = ""
    @State private var evriDays: String = ""
    @State private var customOptions: [CustomDeliveryOption] = []
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showSuccess = false
    @EnvironmentObject private var authService: AuthService

    @FocusState private var focusedField: Field?
    private enum Field {
        case royalMailStandard, royalMailStandardDays
        case royalMailFirstClass, royalMailFirstClassDays
        case dpdPrice, dpdDays
        case evriPrice, evriDays
    }
    private let userService = UserService()

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    // Royal Mail
                    sectionHeader(L10n.string("Royal Mail"))
                Toggle(L10n.string("Enable Royal Mail"), isOn: $royalMailEnabled)
                    .tint(Theme.primaryColor)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(Theme.Colors.secondaryBackground)
                    .cornerRadius(Theme.Glass.menuContainerCornerRadius)

                if royalMailEnabled {
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Text(L10n.string("Standard Shipping"))
                                .font(Theme.Typography.subheadline)
                                .foregroundColor(Theme.Colors.secondaryText)
                            priceAndDaysRow(price: $royalMailStandardPrice, days: $royalMailStandardDays, priceField: .royalMailStandard, daysField: .royalMailStandardDays)
                        }
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Text(L10n.string("First Class (Next day)"))
                                .font(Theme.Typography.subheadline)
                                .foregroundColor(Theme.Colors.secondaryText)
                            priceAndDaysRow(price: $royalMailFirstClassPrice, days: $royalMailFirstClassDays, priceField: .royalMailFirstClass, daysField: .royalMailFirstClassDays)
                        }
                    }
                }

                // DPD
                sectionHeader(L10n.string("DPD"))
                Toggle(L10n.string("Enable DPD"), isOn: $dpdEnabled)
                    .tint(Theme.primaryColor)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(Theme.Colors.secondaryBackground)
                    .cornerRadius(Theme.Glass.menuContainerCornerRadius)

                if dpdEnabled {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(L10n.string("Standard Shipping"))
                            .font(Theme.Typography.subheadline)
                            .foregroundColor(Theme.Colors.secondaryText)
                        priceAndDaysRow(price: $dpdPrice, days: $dpdDays, priceField: .dpdPrice, daysField: .dpdDays)
                    }
                }

                // EVRI
                sectionHeader("Evri")
                Toggle("Enable Evri", isOn: $evriEnabled)
                    .tint(Theme.primaryColor)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(Theme.Colors.secondaryBackground)
                    .cornerRadius(Theme.Glass.menuContainerCornerRadius)

                if evriEnabled {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("Standard Shipping")
                            .font(Theme.Typography.subheadline)
                            .foregroundColor(Theme.Colors.secondaryText)
                        priceAndDaysRow(price: $evriPrice, days: $evriDays, priceField: .evriPrice, daysField: .evriDays)
                    }
                }

                sectionHeader("Custom delivery options")
                ForEach(customOptions) { option in
                    customOptionEditor(optionID: option.id)
                }
                Button {
                    customOptions.append(CustomDeliveryOption(id: UUID().uuidString, name: "", enabled: true, price: nil, deliveryDays: nil))
                } label: {
                    Label("Add custom option", systemImage: "plus.circle")
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.primaryColor)
                }

                    if let msg = errorMessage {
                        Text(msg)
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.error)
                            .padding(.top, Theme.Spacing.sm)
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.lg)
                .padding(.bottom, 100)
            }
            .background(Theme.Colors.background)

            PrimaryButtonBar {
                PrimaryGlassButton(L10n.string("Save"), isLoading: isSaving, action: savePostage)
            }
        }
        .navigationTitle(L10n.string("Postage"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task { await loadPostage() }
        .alert(L10n.string("Saved"), isPresented: $showSuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(L10n.string("Your postage settings have been saved."))
        }
    }

    private func loadPostage() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        userService.updateAuthToken(authService.authToken)
        do {
            let user = try await userService.getUser(username: nil)
            await MainActor.run {
                if let opts = user.postageOptions {
                    royalMailEnabled = opts.royalMailEnabled
                    royalMailStandardPrice = opts.royalMailStandardPrice.map { String(format: "%.2f", $0) } ?? ""
                    royalMailStandardDays = opts.royalMailStandardDays.map(String.init) ?? ""
                    royalMailFirstClassPrice = opts.royalMailFirstClassPrice.map { String(format: "%.2f", $0) } ?? ""
                    royalMailFirstClassDays = opts.royalMailFirstClassDays.map(String.init) ?? ""
                    dpdEnabled = opts.dpdEnabled
                    dpdPrice = opts.dpdPrice.map { String(format: "%.2f", $0) } ?? ""
                    dpdDays = opts.dpdDays.map(String.init) ?? ""
                    evriEnabled = opts.evriEnabled
                    evriPrice = opts.evriPrice.map { String(format: "%.2f", $0) } ?? ""
                    evriDays = opts.evriDays.map(String.init) ?? ""
                    customOptions = opts.customOptions
                }
            }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }

    private func savePostage() {
        focusedField = nil
        isSaving = true
        errorMessage = nil
        let opts = SellerPostageOptions(
            royalMailEnabled: royalMailEnabled,
            royalMailStandardPrice: Double(royalMailStandardPrice.trimmingCharacters(in: .whitespaces)),
            royalMailStandardDays: Int(royalMailStandardDays.trimmingCharacters(in: .whitespaces)),
            royalMailFirstClassPrice: Double(royalMailFirstClassPrice.trimmingCharacters(in: .whitespaces)),
            royalMailFirstClassDays: Int(royalMailFirstClassDays.trimmingCharacters(in: .whitespaces)),
            dpdEnabled: dpdEnabled,
            dpdPrice: Double(dpdPrice.trimmingCharacters(in: .whitespaces)),
            dpdDays: Int(dpdDays.trimmingCharacters(in: .whitespaces)),
            evriEnabled: evriEnabled,
            evriPrice: Double(evriPrice.trimmingCharacters(in: .whitespaces)),
            evriDays: Int(evriDays.trimmingCharacters(in: .whitespaces)),
            customOptions: customOptions
        )
        let fullMeta: [String: Any] = ["postage": opts.toMetaPostage()]
        Task {
            defer { Task { @MainActor in isSaving = false } }
            userService.updateAuthToken(authService.authToken)
            do {
                try await userService.updateProfile(meta: fullMeta)
                await MainActor.run {
                    errorMessage = nil
                    showSuccess = true
                }
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(Theme.Typography.headline)
            .foregroundColor(Theme.Colors.primaryText)
    }

    private func priceAndDaysRow(
        price: Binding<String>,
        days: Binding<String>,
        priceField: Field,
        daysField: Field
    ) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Text("£")
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.primaryText)
                TextField("0", text: price)
                    .onChange(of: price.wrappedValue) { _, newValue in
                        let s = PriceFieldFilter.sanitizePriceInput(newValue)
                        if s != newValue { price.wrappedValue = s }
                    }
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.primaryText)
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: priceField)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.md)
            .background(Theme.Colors.secondaryBackground)
            .cornerRadius(30)

            HStack(spacing: Theme.Spacing.xs) {
                TextField("Days", text: days)
                    .onChange(of: days.wrappedValue) { _, newValue in
                        let digits = newValue.filter(\.isNumber)
                        if digits != newValue { days.wrappedValue = digits }
                    }
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.primaryText)
                    .keyboardType(.numberPad)
                    .focused($focusedField, equals: daysField)
                Text("days")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.secondaryText)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.md)
            .background(Theme.Colors.secondaryBackground)
            .cornerRadius(30)
            .frame(width: 120)
        }
    }

    private func customOptionEditor(optionID: String) -> some View {
        guard let index = customOptions.firstIndex(where: { $0.id == optionID }) else {
            return AnyView(EmptyView())
        }
        let option = customOptions[index]
        return AnyView(
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                TextField("Carrier name (e.g. UPS Express)", text: Binding(
                    get: { option.name },
                    set: { newValue in
                        if let liveIndex = customOptions.firstIndex(where: { $0.id == optionID }) {
                            customOptions[liveIndex].name = newValue
                        }
                    }
                ))
                .font(Theme.Typography.body)
                Toggle("", isOn: Binding(
                    get: { option.enabled },
                    set: { newValue in
                        if let liveIndex = customOptions.firstIndex(where: { $0.id == optionID }) {
                            customOptions[liveIndex].enabled = newValue
                        }
                    }
                ))
                .labelsHidden()
                .tint(Theme.primaryColor)
                Button(role: .destructive) {
                    if let liveIndex = customOptions.firstIndex(where: { $0.id == optionID }) {
                        customOptions.remove(at: liveIndex)
                    }
                } label: {
                    Image(systemName: "trash")
                }
            }
            priceAndDaysRow(
                price: Binding(
                    get: { option.price.map { String(format: "%.2f", $0) } ?? "" },
                    set: { newValue in
                        if let liveIndex = customOptions.firstIndex(where: { $0.id == optionID }) {
                            customOptions[liveIndex].price = Double(newValue.trimmingCharacters(in: .whitespaces))
                        }
                    }
                ),
                days: Binding(
                    get: { option.deliveryDays.map(String.init) ?? "" },
                    set: { newValue in
                        if let liveIndex = customOptions.firstIndex(where: { $0.id == optionID }) {
                            customOptions[liveIndex].deliveryDays = Int(newValue.trimmingCharacters(in: .whitespaces))
                        }
                    }
                ),
                priceField: .dpdPrice,
                daysField: .dpdDays
            )
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.secondaryBackground)
        .cornerRadius(Theme.Glass.menuContainerCornerRadius)
        )
    }
}

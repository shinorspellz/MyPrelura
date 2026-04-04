import SwiftUI

/// Multi-buy discounts: fetch/save tiers via UserService. Matches Flutter multi_buy_discount.dart.
struct MultiBuyDiscountView: View {
    @State private var isEnabled: Bool = false
    @State private var tier2Percent: String = "0"
    @State private var tier5Percent: String = "0"
    @State private var tier10Percent: String = "0"
    @State private var discounts: [MultibuyDiscount] = []
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    private let userService = UserService()
    private let tierMinItems = [2, 5, 10]

    var body: some View {
        ZStack(alignment: .bottom) {
            List {
                Section {
                    Toggle(isOn: Binding(
                        get: { isEnabled },
                        set: { newValue in
                            if newValue {
                                isEnabled = true
                            } else {
                                Task { await turnOff() }
                            }
                        }
                    )) {
                        Text("Multi-buy discounts")
                            .font(Theme.Typography.body)
                            .foregroundColor(Theme.Colors.primaryText)
                    }
                    .tint(Theme.primaryColor)
                    .disabled(isSaving)
                }
                if isEnabled {
                    Section(header: Text("Discount tiers").font(Theme.Typography.caption).foregroundColor(Theme.Colors.secondaryText)) {
                        tierRow(label: "2+ items", value: $tier2Percent)
                        tierRow(label: "5+ items", value: $tier5Percent)
                        tierRow(label: "10+ items", value: $tier10Percent)
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
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if isEnabled {
                    PrimaryButtonBar {
                        PrimaryGlassButton("Save", isLoading: isSaving, action: { Task { await save() } })
                    }
                }
            }
        }
        .navigationTitle("Multi-buy discounts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .refreshable { await load() }
        .task { await load() }
        .alert("Saved", isPresented: .init(get: { successMessage != nil }, set: { if !$0 { successMessage = nil } })) {
            Button("OK", role: .cancel) { successMessage = nil }
        } message: {
            if let msg = successMessage { Text(msg) }
        }
    }

    private func tierRow(label: String, value: Binding<String>) -> some View {
        HStack {
            Text(label)
                .foregroundColor(Theme.Colors.primaryText)
            Spacer()
            TextField("0", text: PriceFieldFilter.binding(get: { value.wrappedValue }, set: { value.wrappedValue = $0 }))
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 50)
            Text("%")
                .foregroundColor(Theme.Colors.secondaryText)
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let userTask = userService.getUser()
            async let discountsTask = userService.getMultibuyDiscounts(userId: nil)
            let (user, fetchedDiscounts) = try await (userTask, discountsTask)
            await MainActor.run {
                isEnabled = user.isMultibuyEnabled
                discounts = fetchedDiscounts
                tier2Percent = percentFor(minItems: 2)
                tier5Percent = percentFor(minItems: 5)
                tier10Percent = percentFor(minItems: 10)
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func percentFor(minItems: Int) -> String {
        let d = discounts.first { $0.minItems == minItems }
        guard let d = d else { return "0" }
        // Backend may return "10" or "10.00" for 10%; parse as Double to avoid showing 1000% when value is "10.00"
        let pct = Double(d.discountValue) ?? 0
        return String(Int(pct))
    }

    private func turnOff() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await userService.deactivateMultibuyDiscounts()
            await MainActor.run {
                isEnabled = false
                discounts = []
                NotificationCenter.default.post(name: .preluraUserProfileDidUpdate, object: nil)
            }
            await load()
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func save() async {
        errorMessage = nil
        let p2 = Int(tier2Percent) ?? 0
        let p5 = Int(tier5Percent) ?? 0
        let p10 = Int(tier10Percent) ?? 0
        if p2 < 5 || p5 < 5 || p10 < 5 {
            errorMessage = "Minimum of 5% discount required"
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            let inputs: [MultibuyDiscountInput] = [
                inputFor(minItems: 2, percent: p2),
                inputFor(minItems: 5, percent: p5),
                inputFor(minItems: 10, percent: p10),
            ]
            try await userService.createOrUpdateMultibuyDiscount(inputs: inputs)
            await MainActor.run {
                successMessage = "Saved"
                NotificationCenter.default.post(name: .preluraUserProfileDidUpdate, object: nil)
            }
            await load()
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func inputFor(minItems: Int, percent: Int) -> MultibuyDiscountInput {
        let existing = discounts.first { $0.minItems == minItems }
        return MultibuyDiscountInput(
            id: existing?.id,
            minItems: minItems,
            discountPercentage: String(percent),
            isActive: true
        )
    }
}

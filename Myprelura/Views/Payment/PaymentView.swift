import SwiftUI

/// Delivery type for checkout (matches Flutter Enum$DeliveryTypeEnum: HOME_DELIVERY, COLLECTION_POINT).
enum DeliveryType: String, CaseIterable {
    case homeDelivery = "Home delivery"
    case collectionPoint = "Collection point"

    var shippingFee: Double {
        switch self {
        case .homeDelivery: return 2.29
        case .collectionPoint: return 2.99
        }
    }

    var iconName: String {
        switch self {
        case .homeDelivery: return "house"
        case .collectionPoint: return "mappin.circle"
        }
    }
}

/// Full payment/checkout screen (Flutter PaymentRoute). Products, address, delivery, buyer protection, total, Pay by card.
struct PaymentView: View {
    let products: [Item]
    let totalPrice: Double
    var customOffer: Bool = false
    var respondToCustomOffer: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authService: AuthService
    @Environment(\.optionalTabCoordinator) private var tabCoordinator
    @State private var currentUser: User?
    @State private var selectedDelivery: DeliveryType = .homeDelivery
    /// Chosen seller postage option per seller (one parcel per seller).
    @State private var selectedSellerOptionBySellerID: [UUID: SellerDeliveryOption] = [:]
    @State private var buyerProtectionEnabled: Bool = false
    @State private var paymentMethod: PaymentMethod?
    @State private var isLoadingPaymentMethod = true
    @State private var isSubmitting = false
    @State private var showPaymentSuccess = false
    @State private var errorMessage: String?
    @State private var discountTiers: [MultibuyDiscount] = []
    /// Set after refetching products that lacked `seller.meta` (e.g. added from Shop All before queries requested postage).
    @State private var enrichedLineItems: [Item]?

    /// Line items used for totals, postage UI, and payment (enriched when possible).
    private var lineItems: [Item] { enrichedLineItems ?? products }

    private let userService = UserService()
    private let productService = ProductService()
    private let chatService = ChatService()

    /// Sum used as the base "Price" for totals.
    /// When opened from an accepted offer, `totalPrice` is the accepted offer amount, and we must use it
    /// instead of the products' listing price so the checkout matches the agreed offer.
    private var orderSubtotal: Double {
        customOffer ? totalPrice : lineItems.reduce(0) { $0 + $1.price }
    }
    /// Multi-buy discount % from seller's tiers (when all items from same seller and count qualifies).
    private func discountPercent(for count: Int) -> Int {
        let sorted = discountTiers.filter { $0.isActive && $0.minItems <= count }.sorted { $0.minItems > $1.minItems }
        guard let tier = sorted.first else { return 0 }
        return Int(Double(tier.discountValue) ?? 0)
    }
    private var multiBuyDiscountPercent: Int {
        // When paying from a custom offer, the offer amount should be treated as the negotiated subtotal.
        // Applying multibuy discounts again would double-adjust the price.
        customOffer ? 0 : discountPercent(for: lineItems.count)
    }
    private var multiBuyDiscountAmount: Double { orderSubtotal * Double(multiBuyDiscountPercent) / 100 }
    private var afterDiscount: Double { orderSubtotal - multiBuyDiscountAmount }
    private var buyerProtectionFee: Double {
        let p = afterDiscount
        if p <= 10 { return (10 * p) / 100 }
        if p <= 50 { return (8 * p) / 100 }
        if p <= 200 { return (6 * p) / 100 }
        return (5 * p) / 100
    }
    /// Distinct sellers in the cart (one shipping charge per seller).
    private var sellerGroups: [(seller: User, items: [Item])] {
        let g = Dictionary(grouping: lineItems, by: { $0.seller.id })
        return g.values.compactMap { arr -> (User, [Item])? in
            guard let s = arr.first?.seller else { return nil }
            return (s, arr)
        }
        .sorted { $0.seller.username.localizedCaseInsensitiveCompare($1.seller.username) == .orderedAscending }
    }

    private func deliveryOptions(for seller: User) -> [SellerDeliveryOption] {
        seller.postageOptions?.toDeliveryOptions() ?? []
    }

    private func selectedOption(for seller: User) -> SellerDeliveryOption? {
        let opts = deliveryOptions(for: seller)
        guard !opts.isEmpty else { return nil }
        if let picked = selectedSellerOptionBySellerID[seller.id], opts.contains(picked) {
            return picked
        }
        return opts.first
    }

    private func setSelectedOption(_ option: SellerDeliveryOption, for seller: User) {
        selectedSellerOptionBySellerID[seller.id] = option
    }

    /// Shipping for one seller’s parcel: their chosen rate, or the global standard rate.
    private func postageFee(for seller: User) -> Double {
        if let opt = selectedOption(for: seller) {
            return opt.shippingFee
        }
        return selectedDelivery.shippingFee
    }

    private var effectiveShippingFee: Double {
        sellerGroups.reduce(0) { $0 + postageFee(for: $1.seller) }
    }
    private var total: Double {
        afterDiscount + effectiveShippingFee + (buyerProtectionEnabled ? buyerProtectionFee : 0)
    }

    /// When all products share the same seller, returns that seller's userId for multibuy fetch.
    private var commonSellerUserId: Int? {
        guard let first = lineItems.first?.seller.userId else { return nil }
        let allSame = lineItems.allSatisfy { $0.seller.userId == first }
        return allSame ? first : nil
    }

    /// More than one seller group (must match `sellerGroups`, which keys on `seller.id`).
    private var isMultiSellerCheckout: Bool {
        sellerGroups.count > 1
    }

    private func formatAddress(_ addr: ShippingAddress?) -> String {
        guard let addr else { return "No address set" }
        var parts: [String] = []
        if !addr.address.isEmpty { parts.append(addr.address) }
        if !addr.city.isEmpty { parts.append(addr.city) }
        if !addr.postcode.isEmpty { parts.append(addr.postcode) }
        return parts.isEmpty ? "No address set" : parts.joined(separator: ", ")
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    sectionHeader("Address")
                    NavigationLink(destination: ShippingAddressView()) {
                        paymentRow(title: currentUser?.shippingAddress.map { formatAddress($0) } ?? currentUser?.location ?? "No address set", trailing: "chevron.right")
                    }
                    .buttonStyle(PlainTappableButtonStyle())

                    sectionHeader("Delivery Option")
                    deliveryOptionsSection

                    sectionHeader("Your Contact details")
                    paymentRow(title: currentUser?.phoneDisplay ?? "+44 ••••••••••", trailing: "chevron.right")

                    Toggle(isOn: $buyerProtectionEnabled) {
                        HStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: "shield")
                                .font(.system(size: 16))
                                .foregroundColor(Theme.Colors.primaryText)
                            Text(L10n.string("Buyer protection fee"))
                                .font(Theme.Typography.body)
                                .foregroundColor(Theme.Colors.primaryText)
                            Text(CurrencyFormatter.gbp(buyerProtectionFee))
                                .font(Theme.Typography.body)
                                .foregroundColor(Theme.Colors.secondaryText)
                        }
                    }
                    .tint(Theme.primaryColor)

                    sectionHeader("\(lineItems.count) \(lineItems.count == 1 ? "Item" : "Items")")
                    VStack(spacing: 0) {
                        ForEach(lineItems) { item in
                            let perItemOfferPrice: Double? = {
                                guard customOffer, lineItems.count > 0 else { return nil }
                                return totalPrice / Double(lineItems.count)
                            }()
                            HStack(alignment: .top) {
                                Text(item.title)
                                    .font(Theme.Typography.body)
                                    .foregroundColor(Theme.Colors.primaryText)
                                    .lineLimit(2)
                                Spacer()
                                if let offerPrice = perItemOfferPrice {
                                    Text(CurrencyFormatter.gbp(offerPrice))
                                        .font(Theme.Typography.body)
                                        .foregroundColor(Theme.Colors.secondaryText)
                                } else {
                                    Text(item.formattedPrice)
                                        .font(Theme.Typography.body)
                                        .foregroundColor(Theme.Colors.secondaryText)
                                }
                            }
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, Theme.Spacing.sm)
                            .overlay(ContentDivider(), alignment: .bottom)
                        }
                        infoRow(L10n.string("Price"), CurrencyFormatter.gbp(orderSubtotal))
                        if lineItems.count > 1 && multiBuyDiscountPercent > 0 {
                            infoRow(String(format: L10n.string("Multi-buy discount (%d%%)"), multiBuyDiscountPercent), CurrencyFormatter.gbp(-multiBuyDiscountAmount), valueColor: Theme.primaryColor)
                        }
                        postageSummaryRows
                        if buyerProtectionEnabled {
                            infoRow(L10n.string("Buyer protection fee"), CurrencyFormatter.gbp(buyerProtectionFee))
                        }
                        infoRow(L10n.string("Total"), CurrencyFormatter.gbp(total), isBold: true)
                    }
                    .background(Theme.Colors.background)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Theme.Colors.glassBorder, lineWidth: 0.5)
                    )

                    sectionHeader("Active Payment Method")
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
                        .padding(Theme.Spacing.md)
                        .background(Theme.Colors.secondaryBackground)
                        .cornerRadius(Theme.Glass.cornerRadius)
                    } else if !isLoadingPaymentMethod {
                        Text(L10n.string("No payment method added"))
                            .font(Theme.Typography.body)
                            .foregroundColor(Theme.Colors.secondaryText)
                            .padding(Theme.Spacing.md)
                        NavigationLink(destination: AddPaymentCardView(onAdded: { Task { await loadPaymentMethod() } })) {
                            Text(L10n.string("Add payment method"))
                                .font(Theme.Typography.headline)
                                .foregroundColor(Theme.primaryColor)
                        }
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding()
                    }

                    if let err = errorMessage {
                        Text(err)
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.error)
                            .padding(.horizontal)
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.bottom, 200)
            }
            .background(Theme.Colors.background)

            bottomBar
        }
        .navigationTitle(L10n.string("Payment"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.Colors.background, for: .navigationBar)
        .fullScreenCover(isPresented: $showPaymentSuccess) {
            PaymentSuccessfulView(productId: lineItems.first?.productId) {
                showPaymentSuccess = false
                dismiss()
            }
        }
        .onAppear {
            seedDefaultSellerShippingSelections()
            Task {
                await loadUser()
                await loadPaymentMethod()
            }
        }
        .task(id: products.map(\.id.uuidString).joined(separator: "|")) {
            await enrichLineItemsWithSellerPostageIfNeeded()
        }
        .task(id: "multibuy-\(lineItems.count)-\(commonSellerUserId ?? -1)") {
            guard lineItems.count > 1, let sellerId = commonSellerUserId else {
                discountTiers = []
                return
            }
            userService.updateAuthToken(authService.authToken)
            do {
                discountTiers = try await userService.getMultibuyDiscounts(userId: sellerId)
            } catch {
                discountTiers = []
            }
        }
        .toolbar(.hidden, for: .tabBar)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(Theme.Typography.body)
            .fontWeight(.light)
            .foregroundColor(Theme.Colors.secondaryText)
            .padding(.top, Theme.Spacing.xs)
    }

    private func paymentRow(title: String, trailing: String) -> some View {
        HStack {
            Text(title)
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.primaryText)
            Spacer()
            Image(systemName: trailing)
                .font(.system(size: 14))
                .foregroundColor(Theme.Colors.secondaryText)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.secondaryBackground)
        .cornerRadius(Theme.Glass.cornerRadius)
    }

    @ViewBuilder
    private var deliveryOptionsSection: some View {
        let withCustom = sellerGroups.filter { !deliveryOptions(for: $0.seller).isEmpty }
        let withDefault = sellerGroups.filter { deliveryOptions(for: $0.seller).isEmpty }

        if !withCustom.isEmpty {
            ForEach(withCustom, id: \.seller.id) { group in
                if sellerGroups.count > 1 {
                    Text(group.seller.username.isEmpty ? L10n.string("Seller") : "@\(group.seller.username)")
                        .font(Theme.Typography.subheadline)
                        .foregroundColor(Theme.Colors.secondaryText)
                        .padding(.top, Theme.Spacing.xs)
                }
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(Array(deliveryOptions(for: group.seller).enumerated()), id: \.offset) { _, option in
                        sellerDeliveryOptionCard(option, seller: group.seller)
                    }
                }
            }
        }
        if !withDefault.isEmpty {
            if !withCustom.isEmpty {
                sectionHeader("Standard shipping")
            }
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(DeliveryType.allCases, id: \.self) { option in
                    deliveryOptionCard(option)
                }
            }
        }
    }

    @ViewBuilder
    private var postageSummaryRows: some View {
        if sellerGroups.count <= 1 {
            infoRow(L10n.string("Postage"), CurrencyFormatter.gbp(effectiveShippingFee))
        } else {
            ForEach(sellerGroups, id: \.seller.id) { group in
                let name = group.seller.username.isEmpty ? L10n.string("Seller") : group.seller.username
                infoRow("\(L10n.string("Postage")) · \(name)", CurrencyFormatter.gbp(postageFee(for: group.seller)))
            }
        }
    }

    private func deliveryOptionCard(_ option: DeliveryType) -> some View {
        let isSelected = selectedDelivery == option
        return Button {
            selectedDelivery = option
        } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: option.iconName)
                        .font(.system(size: 20))
                        .foregroundColor(isSelected ? Theme.primaryColor : Theme.Colors.secondaryText)
                    Text(option.rawValue)
                        .font(Theme.Typography.body)
                        .fontWeight(.semibold)
                        .foregroundColor(isSelected ? Theme.primaryColor : Theme.Colors.primaryText)
                }
                Text(CurrencyFormatter.gbp(option.shippingFee))
                    .font(Theme.Typography.caption)
                    .foregroundColor(isSelected ? Theme.primaryColor : Theme.Colors.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.md)
            .background(isSelected ? Theme.primaryColor.opacity(0.1) : Theme.Colors.secondaryBackground)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Theme.primaryColor : Theme.Colors.glassBorder, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(HapticTapButtonStyle(haptic: { HapticManager.selection() }))
    }

    private func sellerDeliveryOptionCard(_ option: SellerDeliveryOption, seller: User) -> some View {
        let picked = selectedOption(for: seller)
        let isSelected = picked?.name == option.name && picked?.shippingFee == option.shippingFee
        return Button {
            setSelectedOption(option, for: seller)
        } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "shippingbox")
                        .font(.system(size: 20))
                        .foregroundColor(isSelected ? Theme.primaryColor : Theme.Colors.secondaryText)
                    Text(option.name)
                        .font(Theme.Typography.body)
                        .fontWeight(.semibold)
                        .foregroundColor(isSelected ? Theme.primaryColor : Theme.Colors.primaryText)
                }
                Text(CurrencyFormatter.gbp(option.shippingFee))
                    .font(Theme.Typography.caption)
                    .foregroundColor(isSelected ? Theme.primaryColor : Theme.Colors.secondaryText)
                if let days = option.estimatedDays, days > 0 {
                    Text(days == 1 ? "1 day delivery" : "\(days) days delivery")
                        .font(Theme.Typography.caption)
                        .foregroundColor(isSelected ? Theme.primaryColor : Theme.Colors.secondaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.md)
            .background(isSelected ? Theme.primaryColor.opacity(0.1) : Theme.Colors.secondaryBackground)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Theme.primaryColor : Theme.Colors.glassBorder, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(HapticTapButtonStyle(haptic: { HapticManager.selection() }))
    }

    private func infoRow(_ label: String, _ value: String, valueColor: Color? = nil, isBold: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(isBold ? Theme.Typography.body : Theme.Typography.body)
                .fontWeight(isBold ? .medium : .regular)
                .foregroundColor(Theme.Colors.primaryText)
            Spacer()
            Text(value)
                .font(Theme.Typography.body)
                .foregroundColor(valueColor ?? Theme.Colors.secondaryText)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .overlay(ContentDivider(), alignment: .bottom)
    }

    private var bottomBar: some View {
        PrimaryButtonBar {
            VStack(spacing: Theme.Spacing.sm) {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "lock")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.Colors.secondaryText)
                    Text(L10n.string("This is a secure encryption payment"))
                        .font(Theme.Typography.caption)
                        .fontWeight(.light)
                        .foregroundColor(Theme.Colors.secondaryText)
                }
                PrimaryGlassButton("Pay by card", icon: "creditcard", isLoading: isSubmitting, action: payByCard)
            }
        }
    }

    /// When `seller.meta` was missing on cart lines, default postage cards show; after refetch, fill real seller options.
    private func enrichLineItemsWithSellerPostageIfNeeded() async {
        guard enrichedLineItems == nil else { return }
        let baseline = products
        let needsFetch = baseline.indices.filter { deliveryOptions(for: baseline[$0].seller).isEmpty }
        if needsFetch.isEmpty { return }
        productService.updateAuthToken(authService.authToken)
        var merged = baseline
        for idx in needsFetch {
            guard let pid = merged[idx].productId.flatMap({ Int($0) }), pid > 0 else { continue }
            if let fresh = try? await productService.getProduct(id: pid) {
                merged[idx] = fresh
            }
        }
        await MainActor.run {
            enrichedLineItems = merged
            Self.seedDefaultSellerShippingSelections(
                items: merged,
                selectedSellerOptionBySellerID: &selectedSellerOptionBySellerID
            )
        }
    }

    private func seedDefaultSellerShippingSelections() {
        Self.seedDefaultSellerShippingSelections(
            items: lineItems,
            selectedSellerOptionBySellerID: &selectedSellerOptionBySellerID
        )
    }

    private static func seedDefaultSellerShippingSelections(
        items: [Item],
        selectedSellerOptionBySellerID: inout [UUID: SellerDeliveryOption]
    ) {
        let groups = Dictionary(grouping: items, by: { $0.seller.id })
        for (_, arr) in groups {
            guard let seller = arr.first?.seller else { continue }
            let opts = seller.postageOptions?.toDeliveryOptions() ?? []
            if !opts.isEmpty, selectedSellerOptionBySellerID[seller.id] == nil {
                selectedSellerOptionBySellerID[seller.id] = opts.first
            }
        }
    }

    private func loadUser() async {
        do {
            currentUser = try await userService.getUser(username: nil)
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }

    private func loadPaymentMethod() async {
        isLoadingPaymentMethod = true
        defer { isLoadingPaymentMethod = false }
        do {
            let method = try await userService.getUserPaymentMethod()
            await MainActor.run {
                paymentMethod = method
                errorMessage = nil
            }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }

    private func payByCard() {
        errorMessage = nil
        if currentUser?.shippingAddress == nil {
            errorMessage = "Please add a complete shipping address before payment. Go to Settings > Shipping."
            return
        }
        guard let method = paymentMethod else {
            errorMessage = "Add a payment method"
            return
        }
        guard let addr = currentUser?.shippingAddress else { return }
        isSubmitting = true
        Task {
            defer { Task { @MainActor in isSubmitting = false } }
            userService.updateAuthToken(authService.authToken)
            productService.updateAuthToken(authService.authToken)
            do {
                let phone = currentUser?.phoneDisplay ?? "0000000000"
                let fee = Float(effectiveShippingFee)
                let primarySeller = lineItems.first?.seller
                let primaryOpts = primarySeller.map { deliveryOptions(for: $0) } ?? []
                let primaryChosen = primarySeller.flatMap { selectedOption(for: $0) }
                let (provider, deliveryType): (String, String) = if let s = primarySeller, let opt = primaryChosen, !primaryOpts.isEmpty {
                    (opt.deliveryProvider, opt.deliveryType)
                } else {
                    ("EVRI", selectedDelivery == .collectionPoint ? "LOCAL_PICKUP" : "HOME_DELIVERY")
                }
                let selectedShippingName: String? = if let opt = primaryChosen, !primaryOpts.isEmpty {
                    opt.name
                } else {
                    selectedDelivery.rawValue
                }
                let deliveryDetails = CreateOrderDeliveryDetails(
                    address: addr.address,
                    city: addr.city,
                    state: addr.state ?? "",
                    country: addr.country,
                    postalCode: addr.postcode,
                    phoneNumber: phone,
                    deliveryProvider: provider,
                    deliveryType: deliveryType,
                    shippingOptionName: selectedShippingName
                )
                let productIds = lineItems.compactMap { $0.productId }.compactMap { Int($0) }
                guard !productIds.isEmpty else {
                    await MainActor.run { errorMessage = "Invalid product" }
                    return
                }
                NSLog("[PAY_DEBUG] payByCard start products=%d", productIds.count)
                let orderResult: CreateOrderResult
                if productIds.count == 1 {
                    NSLog("[PAY_DEBUG] createOrder single product")
                    orderResult = try await productService.createOrder(
                        productId: productIds[0],
                        productIds: nil,
                        buyerProtection: buyerProtectionEnabled,
                        shippingFee: fee,
                        deliveryDetails: deliveryDetails
                    )
                } else {
                    NSLog("[PAY_DEBUG] createOrder multi product")
                    let sellerFeeRows: [(sellerId: Int, shippingFee: Float)]? = {
                        guard isMultiSellerCheckout else { return nil }
                        let rows: [(Int, Float)] = sellerGroups.compactMap { group in
                            guard let sid = group.seller.userId else { return nil }
                            return (sid, Float(postageFee(for: group.seller)))
                        }
                        guard rows.count == sellerGroups.count, rows.count > 1 else { return nil }
                        return rows.map { (sellerId: $0.0, shippingFee: $0.1) }
                    }()
                    if isMultiSellerCheckout, sellerFeeRows == nil {
                        await MainActor.run {
                            errorMessage = "Cannot complete checkout: missing seller id for one or more items. Try again from the product page."
                        }
                        return
                    }
                    orderResult = try await productService.createOrder(
                        productId: nil,
                        productIds: productIds,
                        buyerProtection: buyerProtectionEnabled,
                        shippingFee: fee,
                        sellerShippingFees: sellerFeeRows,
                        deliveryDetails: deliveryDetails
                    )
                }
                guard let orderIdInt = Int(orderResult.orderId) else {
                    await MainActor.run { errorMessage = "Invalid order id" }
                    return
                }
                NSLog("[PAY_DEBUG] createPaymentIntent orderId=%d", orderIdInt)
                let (_, paymentRef) = try await userService.createPaymentIntent(orderId: orderIdInt, paymentMethodId: method.paymentMethodId)
                NSLog("[PAY_DEBUG] createPaymentIntent done paymentRef=%@", paymentRef)
                var (paymentStatus, orderConfirmed, backendMessage) = try await userService.confirmPayment(paymentRef: paymentRef)
                NSLog("[PAY_DEBUG] confirmPayment done orderConfirmed=%@", String(describing: orderConfirmed))
                // Retry confirmPayment when Stripe is still "processing" (often transitions to succeeded within a few seconds)
                let maxRetries = 2
                var attempt = 0
                while orderConfirmed != true, attempt < maxRetries,
                      let msg = backendMessage, msg.lowercased().contains("still processing") {
                    attempt += 1
                    NSLog("[PAY_DEBUG] confirmPayment retry %d after 3s (still processing)", attempt)
                    try await Task.sleep(nanoseconds: 3_000_000_000)
                    (paymentStatus, orderConfirmed, backendMessage) = try await userService.confirmPayment(paymentRef: paymentRef)
                    NSLog("[PAY_DEBUG] confirmPayment retry %d orderConfirmed=%@", attempt, String(describing: orderConfirmed))
                }
                let confirmed = orderConfirmed == true
                if !confirmed {
                    await MainActor.run {
                        errorMessage = backendMessage ?? "Payment not confirmed yet. Check Messages in a moment or try again."
                        NSLog("[PAY_DEBUG] NOT confirmed: showing error (no success screen)")
                    }
                    return
                }
                // Match Flutter: ensure conversation and sold-confirmation message exist by calling the mutation (backend handle_payment_success may have already done it; mutation is idempotent).
                chatService.updateAuthToken(authService.authToken)
                var soldConversationId: Int?
                do {
                    let (success, conversationId) = try await chatService.createSoldConfirmationMessage(orderId: orderIdInt)
                    soldConversationId = conversationId
                    NSLog("[PAY_DEBUG] createSoldConfirmationMessage orderId=%d success=%@", orderIdInt, String(success))
                } catch {
                    NSLog("[PAY_DEBUG] createSoldConfirmationMessage failed: %@", error.localizedDescription)
                    // Continue anyway: conversation might already exist from handle_payment_success
                }
                // Refetch so we open the conversation that has the order.
                var conversationToOpen: Conversation?
                if let seller = lineItems.first?.seller, !seller.username.isEmpty {
                    chatService.updateAuthToken(authService.authToken)
                    func fetchByOrderId() async throws -> Conversation? {
                        let list = try await chatService.getConversations()
                        let withSeller = list.filter { $0.recipient.username == seller.username }
                        let withOrder = withSeller.first { $0.order?.id == orderResult.orderId }
                        return withOrder
                    }
                    do {
                        if let convoId = soldConversationId {
                            conversationToOpen = try await chatService.getConversationById(
                                conversationId: String(convoId),
                                currentUsername: authService.username
                            )
                            NSLog("[PAY_DEBUG] getConversationById from sold_confirmation: conv=%@", conversationToOpen?.id ?? "nil")
                        }
                        if conversationToOpen == nil {
                            NSLog("[PAY_DEBUG] waiting 1.5s then fetch conversations by order id")
                            try await Task.sleep(nanoseconds: 1_500_000_000)
                            conversationToOpen = try await fetchByOrderId()
                            NSLog("[PAY_DEBUG] fetchByOrderId first try: conv=%@", conversationToOpen?.id ?? "nil")
                            if conversationToOpen == nil {
                                try await Task.sleep(nanoseconds: 1_500_000_000)
                                conversationToOpen = try await fetchByOrderId()
                                NSLog("[PAY_DEBUG] fetchByOrderId retry: conv=%@", conversationToOpen?.id ?? "nil")
                            }
                        }
                    } catch {
                        NSLog("[PAY_DEBUG] conversation fetch/create failed: %@", error.localizedDescription)
                    }
                }
                await MainActor.run {
                    if isMultiSellerCheckout {
                        tabCoordinator?.openInboxListOnly = true
                        tabCoordinator?.selectTab(3)
                        NSLog("[PAY_DEBUG] multi-seller: inbox list only")
                    } else if let conv = conversationToOpen {
                        tabCoordinator?.selectTab(3)
                        tabCoordinator?.pendingOpenConversation = conv
                        NSLog("[PAY_DEBUG] opening conversation id=%@", conv.id)
                    }
                    showPaymentSuccess = true
                    NSLog("[PAY_DEBUG] showPaymentSuccess=true")
                }
            } catch {
                NSLog("[PAY_DEBUG] payByCard error: %@", error.localizedDescription)
                await MainActor.run { errorMessage = error.localizedDescription }
            }
        }
    }
}

#Preview {
    PaymentView(products: Item.sampleItems.prefix(1).map { $0 }, totalPrice: Item.sampleItems[0].price)
        .environmentObject(AuthService())
}

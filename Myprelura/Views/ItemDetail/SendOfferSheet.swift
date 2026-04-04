import SwiftUI

// MARK: - Reusable offer modal content (marketplace + chat)

/// Shared offer form: optional product row + chips when item provided, £ input, Clear + Send offer. Use inside OptionsSheet for same look in marketplace and chat.
struct OfferModalContent: View {
    /// When non-nil, show product row and -5/-10/-15% chips. When nil, show compact form (title + input + buttons).
    var item: Item?
    /// For compact form (item == nil): used for 60% min validation. When nil, only value > 0 is required.
    var listingPrice: Double? = nil
    var onSubmit: (Double) -> Void
    var onDismiss: () -> Void
    @Binding var isSubmitting: Bool
    /// Optional: caller can set to show API/validation errors (e.g. marketplace createOffer failure).
    @Binding var errorMessage: String?
    /// When showing the compact "item send offer" variant, controls whether the offer text field is
    /// prefilled with the item's listing price.
    var prefillOfferAmountFromItem: Bool = true
    @State private var offerAmount: String = ""
    @State private var selectedSuggestionPrice: Double? = nil
    @FocusState private var offerFieldFocused: Bool

    private var maxPrice: Double {
        if let item = item { return item.price }
        return listingPrice ?? .infinity
    }
    private var fivePercent: Double { maxPrice * 0.95 }
    private var tenPercent: Double { maxPrice * 0.90 }
    private var fifteenPercent: Double { maxPrice * 0.85 }

    private var offerValue: Double? {
        let cleaned = offerAmount.replacingOccurrences(of: "£", with: "").trimmingCharacters(in: .whitespaces)
        return Double(cleaned)
    }

    private var canSubmit: Bool {
        guard let value = offerValue, value > 0 else { return false }
        if maxPrice != .infinity, value < maxPrice * 0.6 { return false }
        return true
    }

    private var optionDivider: some View {
        // Intentionally no separator/divider: design wants a clean modal.
        EmptyView()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top: product (optional) + chips (optional) + price field — tightened spacing
            if let item = item {
                HStack(alignment: .top, spacing: Theme.Spacing.md) {
                    if let url = item.imageURLs.first, let imageURL = URL(string: url) {
                        AsyncImage(url: imageURL) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            default:
                                Rectangle()
                                    .fill(Theme.Colors.secondaryBackground)
                            }
                        }
                        .frame(width: 80, height: 100)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.title)
                            .font(Theme.Typography.headline)
                            .foregroundColor(Theme.Colors.primaryText)
                            .lineLimit(2)
                        if let brand = item.brand, !brand.isEmpty {
                            Text(brand)
                                .font(Theme.Typography.subheadline)
                                .foregroundColor(Theme.Colors.secondaryText)
                        }
                        if let size = item.size, !size.isEmpty {
                            let displaySize = size.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("size ")
                                ? String(size.trimmingCharacters(in: .whitespaces).dropFirst(5)).trimmingCharacters(in: .whitespaces)
                                : size
                            Text(displaySize)
                                .font(Theme.Typography.subheadline)
                                .foregroundColor(Theme.Colors.secondaryText)
                        }
                        priceRow(item: item)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                optionDivider

                HStack(spacing: 8) {
                    suggestionChip(price: fivePercent, discount: "-5%")
                    suggestionChip(price: tenPercent, discount: "-10%")
                    suggestionChip(price: fifteenPercent, discount: "-15%")
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.xs)
                optionDivider
            }

            // Your offer input — minimal top padding for slicker look
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(L10n.string("Your offer"))
                    .font(Theme.Typography.subheadline)
                    .foregroundColor(Theme.Colors.secondaryText)
                HStack(spacing: Theme.Spacing.sm) {
                    Text("£")
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.primaryText)
                    TextField("0", text: $offerAmount)
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.primaryText)
                        .keyboardType(.decimalPad)
                        .focused($offerFieldFocused)
                        .onChange(of: offerAmount) { _, newValue in
                            let sanitized = PriceFieldFilter.sanitizePriceInput(newValue)
                            if sanitized != newValue { offerAmount = sanitized }
                        }
                        .onChange(of: offerAmount) { _, _ in
                            errorMessage = nil
                            if let v = offerValue, v != selectedSuggestionPrice { selectedSuggestionPrice = nil }
                        }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.md)
                .background(Theme.Colors.secondaryBackground)
                .cornerRadius(30)
                .overlay(
                    RoundedRectangle(cornerRadius: 30)
                        .strokeBorder(Theme.Colors.glassBorder, lineWidth: 1)
                )
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, item == nil ? Theme.Spacing.xs : Theme.Spacing.sm)
            .padding(.bottom, Theme.Spacing.xs)
            if let err = errorMessage, !err.isEmpty {
                Text(err)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.error)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.bottom, Theme.Spacing.xs)
            }
            optionDivider

            // Clear + Send Offer — tight spacing below the input divider
            VStack(spacing: Theme.Spacing.sm) {
                BorderGlassButton(L10n.string("Clear")) {
                    offerAmount = ""
                    selectedSuggestionPrice = nil
                    errorMessage = nil
                }
                PrimaryGlassButton(L10n.string("Send offer"), icon: "paperplane.fill", isLoading: isSubmitting, action: submitOffer)
                    .disabled(!canSubmit)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.sm)
            .padding(.bottom, Theme.Spacing.sm)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Colors.background)
        .onAppear {
            if let item = item {
                if prefillOfferAmountFromItem {
                    offerAmount = item.price == floor(item.price) ? "\(Int(item.price))" : String(format: "%.2f", item.price)
                } else {
                    offerAmount = ""
                }
            } else if let p = listingPrice {
                offerAmount = p == floor(p) ? "\(Int(p))" : String(format: "%.2f", p)
            }
            offerFieldFocused = true
        }
    }

    private func submitOffer() {
        guard let value = offerValue, value > 0 else { return }
        if maxPrice != .infinity, value < maxPrice * 0.6 {
            errorMessage = "Offer too low. Try again."
            return
        }
        errorMessage = nil
        onSubmit(value)
    }

    private func priceRow(item: Item) -> some View {
        HStack(spacing: 4) {
            if item.originalPrice != nil, item.originalPrice! > item.price {
                Text(item.formattedOriginalPrice)
                    .font(Theme.Typography.subheadline)
                    .foregroundColor(Theme.Colors.secondaryText)
                    .strikethrough()
                Text(item.formattedPrice)
                    .font(Theme.Typography.subheadline)
                    .foregroundColor(Theme.Colors.primaryText)
            } else {
                Text(item.formattedPrice)
                    .font(Theme.Typography.subheadline)
                    .foregroundColor(Theme.primaryColor)
            }
        }
    }

    private func suggestionChip(price: Double, discount: String) -> some View {
        let isSelected = selectedSuggestionPrice == price
        let priceStr = price == floor(price) ? "\(Int(price))" : String(format: "%.2f", price)
        return Button(action: {
            HapticManager.selection()
            offerAmount = price == floor(price) ? "\(Int(price))" : String(format: "%.2f", price)
            selectedSuggestionPrice = price
            errorMessage = nil
        }) {
            HStack(spacing: 6) {
                Text("£\(priceStr)")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(discount)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundColor(isSelected ? .white : Theme.Colors.primaryText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(isSelected ? Theme.primaryColor : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(isSelected ? Theme.primaryColor : Theme.Colors.glassBorder, lineWidth: isSelected ? 1.5 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(PlainTappableButtonStyle())
    }
}

// MARK: - Marketplace wrapper (OptionsSheet content: createOffer + navigate to chat)

/// Send-offer content for OptionsSheet on item detail. Uses OfferModalContent and wires createOffer + navigate to Inbox.
struct SendOfferSheetContent: View {
    let item: Item
    var onDismiss: () -> Void

    @EnvironmentObject var authService: AuthService
    @Environment(\.optionalTabCoordinator) private var tabCoordinator
    private let productService = ProductService()
    private let chatService = ChatService()
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        OfferModalContent(
            item: item,
            listingPrice: nil,
            onSubmit: { value in submitOffer(value: value) },
            onDismiss: onDismiss,
            isSubmitting: $isSubmitting,
            errorMessage: $errorMessage,
            prefillOfferAmountFromItem: false
        )
    }

    private func submitOffer(value: Double) {
        guard let productIdStr = item.productId, let productId = Int(productIdStr) else { return }
        isSubmitting = true
        errorMessage = nil
        Task {
            defer { Task { @MainActor in isSubmitting = false } }
            productService.updateAuthToken(authService.authToken)
            chatService.updateAuthToken(authService.authToken)
            do {
                // Reuse existing conversation for the same product so we don't create duplicate chats.
                let convs = try await chatService.getConversations()
                let existing = convs.first { conv in
                    conv.offer?.products?.contains(where: { $0.id == productIdStr }) == true
                }
                if let conv = existing, let tc = tabCoordinator {
                    await MainActor.run {
                        onDismiss()
                        tc.selectTab(3)
                        tc.pendingOpenConversation = conv
                    }
                    return
                }
                let (_, conversation) = try await productService.createOffer(offerPrice: value, productIds: [productId], message: nil)
                await MainActor.run {
                    onDismiss()
                    if let conv = conversation, let tc = tabCoordinator {
                        tc.selectTab(3)
                        tc.pendingOfferJustSent = true
                        tc.pendingOfferConversationId = conv.id
                        tc.pendingOfferPrice = value
                        DispatchQueue.main.async {
                            tc.pendingOpenConversation = conv
                        }
                    }
                }
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
        }
    }
}

import SwiftUI

/// Cart-like list of items selected for multi-buy. Applies seller's discount tiers (2+, 5+, 10+). Checkout disabled when only 1 item.
struct MultiBuyCartView: View {
    @Binding var selectedIds: Set<String>
    let allItems: [Item]
    /// Seller's user id for fetching multibuy discount tiers; nil = current user.
    var sellerUserId: Int? = nil

    @EnvironmentObject private var authService: AuthService
    @State private var discountTiers: [MultibuyDiscount] = []
    @State private var showPayment: Bool = false
    private let userService = UserService()

    private var items: [Item] {
        allItems.filter { selectedIds.contains($0.id.uuidString) }
    }

    private var subtotal: Double {
        items.reduce(0) { $0 + $1.price }
    }

    /// Discount % for item count from seller's tiers (largest minItems <= count). 2–4 → tier 2, 5–9 → tier 5, 10+ → tier 10.
    private func discountPercent(for count: Int) -> Int {
        let sorted = discountTiers.filter { $0.isActive && $0.minItems <= count }.sorted { $0.minItems > $1.minItems }
        guard let tier = sorted.first else { return 0 }
        return Int(Double(tier.discountValue) ?? 0)
    }

    private var discountPercent: Int { discountPercent(for: items.count) }
    private var discountAmount: Double { subtotal * Double(discountPercent) / 100 }
    private var totalPrice: Double { subtotal - discountAmount }
    private var canCheckout: Bool { items.count >= 2 }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(items) { item in
                        cartRow(item: item)
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.sm)
                .padding(.bottom, Theme.Spacing.xl)
            }
            .background(Theme.Colors.background)

            VStack(spacing: Theme.Spacing.sm) {
                HStack {
                    Text(L10n.string("Price"))
                        .font(Theme.Typography.subheadline)
                        .foregroundColor(Theme.Colors.secondaryText)
                    Spacer()
                    Text(CurrencyFormatter.gbp(subtotal))
                        .font(Theme.Typography.subheadline)
                        .foregroundColor(Theme.Colors.primaryText)
                }
                .padding(.horizontal, Theme.Spacing.md)
                if discountPercent > 0 {
                    HStack {
                        Text(String(format: "Multi-buy discount (%d%%)", discountPercent))
                            .font(Theme.Typography.subheadline)
                            .foregroundColor(Theme.primaryColor)
                        Spacer()
                        Text(CurrencyFormatter.gbp(-discountAmount))
                            .font(Theme.Typography.subheadline)
                            .foregroundColor(Theme.primaryColor)
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                }
                HStack {
                    Text(L10n.string("Total"))
                        .font(Theme.Typography.headline)
                        .foregroundColor(Theme.Colors.primaryText)
                    Spacer()
                    Text(CurrencyFormatter.gbp(totalPrice))
                        .font(Theme.Typography.headline)
                        .foregroundColor(Theme.Colors.primaryText)
                }
                .padding(.horizontal, Theme.Spacing.md)

                Button(action: { showPayment = true }) {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "creditcard")
                            .font(.system(size: 16, weight: .semibold))
                        Text(L10n.string("Checkout"))
                            .font(Theme.Typography.headline)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.vertical, Theme.Spacing.md)
                    .glassEffect(.clear.tint(Theme.primaryColor), in: .rect(cornerRadius: 30))
                    .glassEffectTransition(.materialize)
                }
                .buttonStyle(HapticTapButtonStyle(haptic: { HapticManager.selection() }))
                .padding(.horizontal, Theme.Spacing.md)
                .disabled(!canCheckout)
                .opacity(canCheckout ? 1 : 0.6)
            }
            .padding(.vertical, Theme.Spacing.md)
            .background(Theme.Colors.background)
        }
        .navigationTitle(L10n.string("Shopping bag"))
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showPayment) {
            NavigationStack {
                PaymentView(products: items, totalPrice: totalPrice)
                    .environmentObject(authService)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(action: { showPayment = false }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 28))
                                    .foregroundStyle(Theme.Colors.secondaryText)
                            }
                        }
                    }
            }
        }
        .task {
            userService.updateAuthToken(authService.authToken)
            // Use seller's id so their multi-buy settings apply for any buyer (not just when seller views own bag).
            let effectiveSellerId = sellerUserId ?? items.first?.seller.userId
            do {
                discountTiers = try await userService.getMultibuyDiscounts(userId: effectiveSellerId)
            } catch {
                discountTiers = []
            }
        }
    }

    private func cartRow(item: Item) -> some View {
        HStack(alignment: .center, spacing: Theme.Spacing.md) {
            // Thumbnail
            Group {
                if let first = item.imageURLs.first, let url = URL(string: first) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        case .failure, .empty:
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Theme.primaryColor.opacity(0.2))
                                .overlay(
                                    Image(systemName: "photo")
                                        .font(.system(size: 24))
                                        .foregroundColor(Theme.primaryColor.opacity(0.5))
                                )
                        @unknown default:
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Theme.primaryColor.opacity(0.2))
                        }
                    }
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Theme.primaryColor.opacity(0.2))
                        .overlay(
                            Image(systemName: "photo")
                                .font(.system(size: 24))
                                .foregroundColor(Theme.primaryColor.opacity(0.5))
                        )
                }
            }
            .frame(width: 72, height: 72 * 1.3)
            .clipped()
            .cornerRadius(8)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                if let brand = item.brand {
                    Text(brand)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.primaryColor)
                }
                Text(item.title)
                    .font(Theme.Typography.subheadline)
                    .foregroundColor(Theme.Colors.primaryText)
                    .lineLimit(2)
                Text(item.formattedPrice)
                    .font(Theme.Typography.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(Theme.Colors.primaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: {
                HapticManager.selection()
                selectedIds.remove(item.id.uuidString)
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(Theme.Colors.secondaryText)
            }
            .buttonStyle(HapticTapButtonStyle(haptic: { HapticManager.selection() }))
        }
        .padding(.vertical, Theme.Spacing.sm)
        .padding(.horizontal, Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.Glass.cornerRadius)
                .fill(Theme.Colors.secondaryBackground)
        )
        .padding(.vertical, Theme.Spacing.xs)
    }
}

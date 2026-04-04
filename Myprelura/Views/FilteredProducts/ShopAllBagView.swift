import SwiftUI

/// Bag view for Shop All: list of items + total + Checkout. Uses ShopAllBagStore.
struct ShopAllBagView: View {
    @ObservedObject var store: ShopAllBagStore
    @EnvironmentObject var authService: AuthService
    @State private var showPayment: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            if store.items.isEmpty {
                VStack(spacing: Theme.Spacing.md) {
                    Spacer()
                    Image(systemName: "bag")
                        .font(.system(size: 50))
                        .foregroundColor(Theme.Colors.secondaryText)
                    Text(L10n.string("Your bag is empty"))
                        .font(Theme.Typography.title3)
                        .foregroundColor(Theme.Colors.secondaryText)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: Theme.Spacing.sm) {
                        ForEach(store.items) { item in
                            shopAllBagRow(item: item) {
                                store.remove(item)
                            }
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.md)
                }
                VStack(spacing: Theme.Spacing.sm) {
                    HStack {
                        Text(L10n.string("Total"))
                            .font(Theme.Typography.headline)
                        Spacer()
                        Text(store.formattedTotal)
                            .font(Theme.Typography.headline)
                            .foregroundColor(Theme.primaryColor)
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
                }
                .padding(.vertical, Theme.Spacing.md)
                .background(Theme.Colors.background)
                .overlay(ContentDivider(), alignment: .top)
            }
        }
        .background(Theme.Colors.background)
        .navigationTitle(L10n.string("Shopping bag"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .fullScreenCover(isPresented: $showPayment) {
            NavigationStack {
                PaymentView(products: store.items, totalPrice: store.totalPrice)
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
    }

    private func shopAllBagRow(item: Item, onRemove: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: Theme.Spacing.md) {
            Group {
                if let first = item.imageURLs.first, let url = URL(string: first) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fill)
                        default:
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Theme.primaryColor.opacity(0.2))
                                .overlay(Image(systemName: "photo").font(.system(size: 24)).foregroundColor(Theme.primaryColor.opacity(0.5)))
                        }
                    }
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Theme.primaryColor.opacity(0.2))
                        .overlay(Image(systemName: "photo").font(.system(size: 24)).foregroundColor(Theme.primaryColor.opacity(0.5)))
                }
            }
            .frame(width: 72, height: 72 * 1.3)
            .clipped()
            .cornerRadius(8)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                if let brand = item.brand {
                    Text(brand).font(Theme.Typography.caption).foregroundColor(Theme.primaryColor)
                }
                Text(item.title).font(Theme.Typography.subheadline).foregroundColor(Theme.Colors.primaryText).lineLimit(2)
                Text(item.formattedPrice).font(Theme.Typography.subheadline).fontWeight(.semibold).foregroundColor(Theme.Colors.primaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: { HapticManager.selection(); onRemove() }) {
                Image(systemName: "xmark.circle.fill").font(.system(size: 22)).foregroundColor(Theme.Colors.secondaryText)
            }
            .buttonStyle(HapticTapButtonStyle(haptic: { HapticManager.selection() }))
        }
        .padding(Theme.Spacing.sm)
        .background(RoundedRectangle(cornerRadius: Theme.Glass.cornerRadius).fill(Theme.Colors.secondaryBackground))
    }
}

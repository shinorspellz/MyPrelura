import SwiftUI

/// Favourites: fetch liked products, grid, search, empty state. Matches Flutter MyFavouriteScreen.
struct MyFavouritesView: View {
    @EnvironmentObject var authService: AuthService
    /// Shared with Shop All and item detail (injected from `MainTabView`).
    @EnvironmentObject private var shopAllBag: ShopAllBagStore
    /// When true, opened from Shop All (e.g. Try Cart rules already apply from that flow).
    var fromShopAll: Bool = false
    /// User turns this on to pass the shared bag into item detail (toolbar bag on Favourites).
    @State private var shopAllBagToolbarActive = false
    @State private var searchText: String = ""
    @State private var items: [Item] = []
    @State private var totalNumber: Int = 0
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var currentPage = 1
    @State private var isLoadingMore = false

    private let productService = ProductService()
    private let pageCount = 20
    /// Same grid as feed: column and row spacing so products don’t bleed together.
    private let columns = [
        GridItem(.flexible(), spacing: Theme.Spacing.md),
        GridItem(.flexible(), spacing: Theme.Spacing.md)
    ]

    private var filteredItems: [Item] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return items }
        return items.filter { $0.title.lowercased().contains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            DiscoverSearchField(
                text: $searchText,
                placeholder: L10n.string("Search favourites"),
                topPadding: Theme.Spacing.xs
            )

            if let err = errorMessage {
                Text(err)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.error)
                    .padding(.horizontal)
            }

            if isLoading && items.isEmpty {
                Spacer()
                ProgressView()
                Spacer()
            } else if items.isEmpty {
                Spacer()
                VStack(spacing: Theme.Spacing.md) {
                    Text(L10n.string("No favourites yet"))
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.primaryText)
                    Text(L10n.string("Items you save as favourites will appear here."))
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .padding(Theme.Spacing.xl)
                Spacer()
            } else if filteredItems.isEmpty {
                Spacer()
                Text(String(format: L10n.string("No results for \"%@\""), searchText))
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.secondaryText)
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: columns,
                        alignment: .leading,
                        spacing: Theme.Spacing.md,
                        pinnedViews: []
                    ) {
                        ForEach(filteredItems) { item in
                            let inBag = shopAllBag.items.contains(where: { $0.id == item.id })
                            NavigationLink(destination: ItemDetailView(
                                item: item,
                                authService: authService,
                                offersAllowed: !(fromShopAll || shopAllBagToolbarActive),
                                shopAllBag: shopAllBagToolbarActive ? shopAllBag : nil,
                                activateShopBagActionsInitially: shopAllBagToolbarActive
                            )) {
                                HomeItemCard(
                                    item: item,
                                    onLikeTap: { unfavourite(item) },
                                    showAddToBag: shopAllBagToolbarActive,
                                    onAddToBag: shopAllBagToolbarActive
                                        ? {
                                            if !shopAllBag.items.contains(where: { $0.id == item.id }) {
                                                shopAllBag.add(item)
                                            }
                                        }
                                        : nil,
                                    isInBag: inBag,
                                    onRemove: shopAllBagToolbarActive
                                        ? { shopAllBag.remove(item) }
                                        : nil
                                )
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                            }
                            .buttonStyle(PlainTappableButtonStyle())
                            .onAppear {
                                if item.id == filteredItems.last?.id {
                                    loadMoreIfNeeded()
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.md)
                    .padding(.bottom, shopAllBagToolbarActive ? 88 : Theme.Spacing.lg)

                    if isLoadingMore {
                        ProgressView()
                            .padding()
                    }
                }
            }
        }
        .background(Theme.Colors.background)
        .toolbar(.hidden, for: .tabBar)
        .navigationTitle(L10n.string("Favourites"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    shopAllBagToolbarActive.toggle()
                } label: {
                    Image(systemName: shopAllBagToolbarActive ? "bag.fill" : "bag")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(shopAllBagToolbarActive ? Theme.primaryColor : Theme.Colors.primaryText)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainTappableButtonStyle())
                .accessibilityLabel("Toggle shopping bag mode")
            }
        }
        .overlay(alignment: .bottom) {
            if shopAllBagToolbarActive {
                favouritesTryCartFloatingBar
            }
        }
        .refreshable { await load(resetPage: true) }
        .task { await load(resetPage: true) }
    }

    /// Same as Shop All Try Cart: tap opens `ShopAllBagView` → Checkout → `PaymentView`.
    private var favouritesTryCartFloatingBar: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                GlassEffectContainer(spacing: 0) {
                    NavigationLink(destination: ShopAllBagView(store: shopAllBag).environmentObject(authService)) {
                        HStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: "cart.fill")
                                .font(.system(size: 16, weight: .semibold))
                            Text(L10n.string("Shopping bag"))
                                .font(Theme.Typography.headline)
                            Spacer(minLength: 0)
                            Text(shopAllBag.formattedTotal)
                                .font(Theme.Typography.headline)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, Theme.Spacing.lg)
                        .padding(.vertical, Theme.Spacing.md)
                        .glassEffect(.clear.tint(Theme.primaryColor), in: .rect(cornerRadius: 30))
                        .glassEffectTransition(.materialize)
                    }
                    .buttonStyle(PlainTappableButtonStyle())
                }
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                Spacer()
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.bottom, 15)
        }
        .allowsHitTesting(true)
    }

    private func load(resetPage: Bool) async {
        productService.updateAuthToken(authService.authToken)
        if resetPage {
            currentPage = 1
            items = []
        }
        if currentPage == 1 { isLoading = true }
        errorMessage = nil
        defer {
            if currentPage == 1 { isLoading = false }
        }
        do {
            let (newItems, total) = try await productService.getLikedProducts(pageNumber: currentPage, pageCount: pageCount)
            if currentPage == 1 {
                items = newItems
            } else {
                let ids = Set(items.map { $0.id })
                items += newItems.filter { !ids.contains($0.id) }
            }
            totalNumber = total
        } catch {
            errorMessage = L10n.userFacingError(error)
        }
    }

    private func loadMoreIfNeeded() {
        guard !isLoadingMore, items.count < totalNumber else { return }
        Task {
            isLoadingMore = true
            currentPage += 1
            await load(resetPage: false)
            isLoadingMore = false
        }
    }

    /// Unfavourite (toggle like off) and remove from list.
    private func unfavourite(_ item: Item) {
        guard let productId = item.productId, !productId.isEmpty else { return }
        items.removeAll { $0.id == item.id }
        Task {
            do {
                _ = try await productService.toggleLike(productId: productId, isLiked: false)
            } catch {
                await MainActor.run {
                    items.append(item)
                }
            }
        }
    }
}


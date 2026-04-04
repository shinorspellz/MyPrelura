import SwiftUI
import Shimmer

struct DiscoverView: View {
    @EnvironmentObject var authService: AuthService
    @ObservedObject var tabCoordinator: TabCoordinator
    @ObservedObject var viewModel: DiscoverViewModel
    @State private var searchText: String = ""
    @State private var showSearchMembersResults: Bool = false
    @State private var scrollPosition: String? = "discover_top"
    /// When true, pill tag rows stop their drift animation (set on scroll or tap).
    @State private var pillAnimationStopped: Bool = false
    @State private var showGuestSignInPrompt: Bool = false
    /// Try Cart banner: typewriter phase (0..<3) and visible character count (0...8).
    @State private var tryCartPhase: Int = 0
    @State private var tryCartVisibleCount: Int = 0
    @State private var tryCartHoldTicks: Int = 0
    @State private var tryCartTimer: Timer?

    private static let categories = ["Women", "Men"]
    private static let tryCartText = "Try Cart"
    /// 3 font styles for Try Cart cycle: bold default, rounded, serif.
    private static let tryCartFonts: [Font] = [
        .system(size: 28, weight: .bold, design: .default),
        .system(size: 26, weight: .bold, design: .rounded),
        .system(size: 24, weight: .semibold, design: .serif)
    ]

    init(tabCoordinator: TabCoordinator, viewModel: DiscoverViewModel) {
        self.tabCoordinator = tabCoordinator
        self.viewModel = viewModel
    }
    
    let brands = ["New Look", "Nike", "Next", "adidas", "Bo", "Ralph Lauren", "Prettylittlething", "River Island", "Zara", "H&M", "ASOS", "Topshop", "Mango", "Bershka", "Pull & Bear", "Stradivarius", "Massimo Dutti", "COS", "Arket", "Weekday"]
    
    private let topId = "discover_top"

    var body: some View {
        GeometryReader { geometry in
            discoverScrollContent(geometry: geometry)
        }
        .onChange(of: scrollPosition) { _, new in
            tabCoordinator.reportAtTop(tab: 1, isAtTop: new == topId)
        }
        .background(Theme.Colors.background)
        .navigationTitle(L10n.string("Discover"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHidden(viewModel.isLoading && viewModel.discoverItems.isEmpty)
        .toolbar { discoverToolbar }
        .refreshable { await viewModel.refreshAsync() }
        .onAppear {
            if authService.isAuthenticated {
                viewModel.updateAuthToken(authService.authToken)
                if viewModel.discoverItems.isEmpty {
                    viewModel.refresh()
                } else {
                    // Returning to Discover (e.g. from product detail): refresh only recently viewed so the slider updates
                    viewModel.refreshRecentlyViewedSection()
                }
            }
            startTryCartTypewriterTimer()
        }
        .onDisappear {
            tryCartTimer?.invalidate()
            tryCartTimer = nil
        }
        .onChange(of: authService.isAuthenticated) { _, isAuthenticated in
            if isAuthenticated {
                viewModel.updateAuthToken(authService.authToken)
                viewModel.refresh()
            }
        }
        .onChange(of: authService.authToken) { _, newToken in
            if authService.isAuthenticated {
                viewModel.updateAuthToken(newToken)
                viewModel.refresh()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .preluraRecentlyViewedDidUpdate)) { _ in
            viewModel.refreshRecentlyViewedSection()
        }
        .fullScreenCover(isPresented: $showSearchMembersResults) {
            SearchMembersView(query: searchText)
        }
        .fullScreenCover(isPresented: $showGuestSignInPrompt) {
            GuestSignInPromptView()
        }
    }

    @ViewBuilder
    private func discoverScrollContent(geometry: GeometryProxy) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                if viewModel.isLoading && viewModel.discoverItems.isEmpty {
                    DiscoverShimmerView()
                        .frame(width: geometry.size.width)
                        .frame(minHeight: geometry.size.height)
                } else {
                    discoverMainStack
                }
            }
            .scrollPosition(id: $scrollPosition, anchor: .top)
            .onAppear {
                tabCoordinator.reportAtTop(tab: 1, isAtTop: true)
                tabCoordinator.registerScrollToTop(tab: 1) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(topId, anchor: .top)
                    }
                }
                tabCoordinator.registerRefresh(tab: 1) {
                    Task { await viewModel.refreshAsync() }
                }
            }
        }
    }

    private var discoverMainStack: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 1).id(topId)
            DiscoverSearchField(
                text: $searchText,
                placeholder: L10n.string("Search members"),
                animatedPlaceholders: [
                    L10n.string("Search by name"),
                    L10n.string("Find members"),
                    L10n.string("Search username"),
                    L10n.string("Discover people"),
                    L10n.string("Find sellers"),
                ],
                onSubmit: { showSearchMembersResults = true },
                topPadding: Theme.Spacing.xs
            )
            .padding(.trailing, Theme.Spacing.sm)
            .padding(.bottom, 2)
            brandFiltersSection
            tryCartBanner
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.primaryColor)
                    Text(L10n.string("Shop Categories"))
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.primaryColor)
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, 14)
                .padding(.bottom, Theme.Spacing.sm)
                ContentDivider()
                categoryCirclesSection
                shopByStyleAndLookbooksBanners
                    .padding(.top, max(0, Theme.Spacing.md - 10))
                    .padding(.bottom, Theme.Spacing.lg)
                recentlyViewedSection
                ContentDivider()
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.lg)
                brandsYouLoveSection
                ContentDivider()
                    .padding(.vertical, Theme.Spacing.lg)
                topShopsSection
                ContentDivider()
                    .padding(.vertical, Theme.Spacing.lg)
                shopBargainsSection
                ContentDivider()
                    .padding(.vertical, Theme.Spacing.lg)
                onSaleSection
            }
            .padding(.top, 5)
            .padding(.bottom, Theme.Spacing.lg)
        }
        .frame(maxWidth: .infinity)
    }

    @ToolbarContentBuilder
    private var discoverToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            HStack(spacing: Theme.Spacing.sm) {
                NavigationLink(destination: MyFavouritesView()) {
                    Image(systemName: "heart")
                        .foregroundColor(Theme.Colors.primaryText)
                        .frame(width: Theme.AppBar.buttonSize, height: Theme.AppBar.buttonSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(HapticTapButtonStyle(haptic: { HapticManager.like() }))
            }
        }
    }
    
    // MARK: - Try Cart banner (below pill tags; Rectangle 11 2 image + overlay + typewriter text → Shop All page; height 150pt)
    private var tryCartBanner: some View {
        NavigationLink(destination: FilteredProductsView(
            title: "Shop All",
            filterType: .tryCartSearch,
            authService: authService,
            offersAllowed: false
        )) {
            ZStack {
                Image("Rectangle 11 2")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 150)
                    .frame(maxWidth: .infinity)
                    .clipped()
                Color.black.opacity(0.4)
                    .frame(height: 150)
                    .frame(maxWidth: .infinity)
                let visiblePrefix = String(Self.tryCartText.prefix(tryCartVisibleCount))
                let font = Self.tryCartFonts[tryCartPhase]
                HStack(spacing: 2) {
                    Text(visiblePrefix)
                        .font(font)
                        .foregroundColor(.white)
                    TimelineView(.animation(minimumInterval: 0.05)) { context in
                        let blink = 0.5 + 0.5 * sin(context.date.timeIntervalSinceReferenceDate * .pi * 2)
                        Text("|")
                            .font(font)
                            .foregroundColor(.white)
                            .opacity(blink)
                    }
                }
                .animation(.easeOut(duration: 0.12), value: tryCartVisibleCount)
                .animation(.easeInOut(duration: 0.35), value: tryCartPhase)
                Text("BETA")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.black.opacity(0.6)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, 10)
                    .padding(.trailing, 10)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainTappableButtonStyle())
        .padding(.vertical, Theme.Spacing.sm)
    }

    private func startTryCartTypewriterTimer() {
        tryCartTimer?.invalidate()
        let fullCount = Self.tryCartText.count
        let holdTicksNeeded = 14 // ~2.1s at 0.15s per tick
        tryCartTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { _ in
            DispatchQueue.main.async {
                if tryCartVisibleCount < fullCount {
                    tryCartVisibleCount += 1
                    tryCartHoldTicks = 0
                } else {
                    tryCartHoldTicks += 1
                    if tryCartHoldTicks >= holdTicksNeeded {
                        tryCartPhase = (tryCartPhase + 1) % 3
                        tryCartVisibleCount = 0
                        tryCartHoldTicks = 0
                    }
                }
            }
        }
        RunLoop.main.add(tryCartTimer!, forMode: .common)
    }

    // MARK: - Brand Filters (2 rows, slow drift; tap or scroll stops animation)
    private var brandFiltersSection: some View {
        let brandsToShow = Array(brands.prefix(20))
        let firstRow = Array(brandsToShow.prefix(10))
        let secondRow = Array(brandsToShow.suffix(from: min(10, brandsToShow.count)))
        
        return VStack(spacing: 0) {
            AnimatedBrandRow(brands: firstRow, maxOffset: 30, authService: authService, animationStopped: $pillAnimationStopped)
            if !secondRow.isEmpty {
                AnimatedBrandRow(brands: secondRow, maxOffset: 17, authService: authService, animationStopped: $pillAnimationStopped)
                    .padding(.top, 4)
            }
        }
        .padding(.top, 2)
        .padding(.bottom, 2)
    }
    
    // MARK: - Category List (simple list like brands on sell page; navigate to filtered category)
    private var categoryCirclesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(Self.categories.enumerated()), id: \.offset) { index, category in
                NavigationLink(destination: FilteredProductsView(
                    title: L10n.string(category),
                    filterType: .byParentCategory(categoryName: category),
                    authService: authService
                )) {
                    HStack {
                        Text(L10n.string(category))
                            .font(Theme.Typography.body)
                            .foregroundColor(Theme.Colors.primaryText)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Theme.Colors.secondaryText)
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.md)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainTappableButtonStyle())
                if index < Self.categories.count - 1 {
                    ContentDivider()
                }
            }
        }
    }

    // MARK: - Shop by style & Lookbooks (portrait banners side by side; image + overlay + text)
    @State private var shopByStyleImageIndex: Int = 0

    private static let bannerHeight: CGFloat = 215

    private var shopByStyleAndLookbooksBanners: some View {
        GeometryReader { geo in
            let totalPadding = Theme.Spacing.md * 2
            let gap = Theme.Spacing.sm
            let bannerWidth = (geo.size.width - totalPadding - gap) / 2
            HStack(spacing: gap) {
                shopByStyleBanner(containerWidth: bannerWidth)
                lookbooksBanner(containerWidth: bannerWidth)
            }
            .padding(.horizontal, Theme.Spacing.md)
        }
        .frame(height: Self.bannerHeight)
    }

    private func shopByStyleBanner(containerWidth: CGFloat) -> some View {
        NavigationLink(destination: FilteredProductsView(
            title: L10n.string("Shop by style"),
            filterType: .shopByStyle,
            authService: authService,
            offersAllowed: false,
            showAddToBag: false
        )) {
            ZStack {
                Image(shopByStyleImageIndex == 0 ? "ShopByStyle1" : "ShopByStyle2")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: containerWidth, height: Self.bannerHeight)
                    .clipped()
                    .animation(.easeInOut(duration: 1.2), value: shopByStyleImageIndex)
                Color.black.opacity(0.45)
                    .frame(width: containerWidth, height: Self.bannerHeight)
                Text(L10n.string("Shop by style"))
                    .font(Theme.Typography.title3)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(Theme.Spacing.md)
            }
            .frame(width: containerWidth, height: Self.bannerHeight)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Glass.cornerRadius))
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainTappableButtonStyle())
        .frame(width: containerWidth, height: Self.bannerHeight)
        .onAppear {
            startShopByStyleImageTimer()
        }
        .onDisappear {
            shopByStyleImageTimer?.invalidate()
            shopByStyleImageTimer = nil
        }
    }

    @State private var shopByStyleImageTimer: Timer?

    private func startShopByStyleImageTimer() {
        shopByStyleImageTimer?.invalidate()
        shopByStyleImageTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 1.2)) {
                    shopByStyleImageIndex = 1 - shopByStyleImageIndex
                }
            }
        }
        RunLoop.main.add(shopByStyleImageTimer!, forMode: .common)
    }

    private func lookbooksBanner(containerWidth: CGFloat) -> some View {
        NavigationLink(destination: LookbookView()) {
            ZStack {
                Image("LookbookBanner")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: containerWidth, height: Self.bannerHeight)
                    .clipped()
                Color.black.opacity(0.45)
                    .frame(width: containerWidth, height: Self.bannerHeight)
                Text(L10n.string("Lookbooks"))
                    .font(Theme.Typography.title3)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(Theme.Spacing.md)
            }
            .frame(width: containerWidth, height: Self.bannerHeight)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Glass.cornerRadius))
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainTappableButtonStyle())
        .frame(width: containerWidth, height: Self.bannerHeight)
    }
    
    // MARK: - Recently Viewed Section (Products)
    private var recentlyViewedSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text(L10n.string("Recently viewed"))
                    .font(Theme.Typography.headline)
                    .foregroundColor(Theme.Colors.primaryText)
                
                Spacer()
                
                NavigationLink(destination: FilteredProductsView(title: L10n.string("Recently viewed"), filterType: .recentlyViewed, authService: authService)) {
                    Text(L10n.string("See All"))
                        .font(Theme.Typography.subheadline)
                        .foregroundColor(Theme.primaryColor)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: Theme.Spacing.sm) {
                    ForEach(viewModel.recentlyViewedItems) { item in
                        NavigationLink(value: AppRoute.itemDetail(item)) {
                            DiscoverItemCard(item: item, onLikeTap: {
                                if authService.isGuestMode { showGuestSignInPrompt = true }
                                else { viewModel.toggleLike(productId: item.productId ?? "") }
                            })
                                .frame(width: 160)
                        }
                        .buttonStyle(PlainTappableButtonStyle())
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
            }
        }
    }
    
    // MARK: - Brands You Love Section
    private var brandsYouLoveSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(L10n.string("Brands You Love"))
                        .font(Theme.Typography.headline)
                        .foregroundColor(Theme.Colors.primaryText)
                    
                    Text(L10n.string("Recommended from your favorite brands"))
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.secondaryText)
                }
                
                Spacer()
                
                NavigationLink(destination: FilteredProductsView(title: L10n.string("Brands You Love"), filterType: .brandsYouLove, authService: authService)) {
                    Text(L10n.string("See All"))
                        .font(Theme.Typography.subheadline)
                        .foregroundColor(Theme.primaryColor)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: Theme.Spacing.sm) {
                    ForEach(viewModel.brandsYouLoveItems) { item in
                        NavigationLink(value: AppRoute.itemDetail(item)) {
                            DiscoverItemCard(item: item, onLikeTap: {
                                if authService.isGuestMode { showGuestSignInPrompt = true }
                                else { viewModel.toggleLike(productId: item.productId ?? "") }
                            })
                                .frame(width: 160)
                        }
                        .buttonStyle(PlainTappableButtonStyle())
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
            }
        }
    }
    
    // MARK: - Top Shops Section
    private var topShopsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(L10n.string("Top Shops"))
                    .font(Theme.Typography.headline)
                    .foregroundColor(Theme.Colors.primaryText)
                
                Text(L10n.string("Buy from trusted and popular vendors"))
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.secondaryText)
            }
            .padding(.horizontal, Theme.Spacing.md)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.md) {
                    ForEach(viewModel.topShops) { shop in
                        NavigationLink(destination: UserProfileView(
                            seller: User(username: shop.username, displayName: shop.username, avatarURL: shop.avatarURL),
                            authService: authService
                        )) {
                            VStack(spacing: Theme.Spacing.xs) {
                                // Shop avatar
                                if let avatarURL = shop.avatarURL, !avatarURL.isEmpty, let url = URL(string: avatarURL) {
                                    AsyncImage(url: url) { phase in
                                        switch phase {
                                        case .empty:
                                            Circle()
                                                .fill(Theme.Colors.secondaryBackground)
                                                .frame(width: 100, height: 100)
                                                .shimmering()
                                        case .success(let image):
                                            image
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(width: 100, height: 100)
                                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                        case .failure:
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Theme.primaryColor)
                                                .frame(width: 100, height: 100)
                                                .overlay(
                                                    Text(String(shop.username.prefix(1)).uppercased())
                                                        .font(.system(size: 32, weight: .bold))
                                                        .foregroundColor(.white)
                                                )
                                        @unknown default:
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Theme.primaryColor)
                                                .frame(width: 100, height: 100)
                                                .overlay(
                                                    Text(String(shop.username.prefix(1)).uppercased())
                                                        .font(.system(size: 32, weight: .bold))
                                                        .foregroundColor(.white)
                                                )
                                        }
                                    }
                                } else {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Theme.primaryColor)
                                        .frame(width: 100, height: 100)
                                        .overlay(
                                            Text(String(shop.username.prefix(1)).uppercased())
                                                .font(.system(size: 32, weight: .bold))
                                                .foregroundColor(.white)
                                        )
                                }
                                
                                Text(shop.username)
                                    .font(Theme.Typography.caption)
                                    .foregroundColor(Theme.Colors.primaryText)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(PlainTappableButtonStyle())
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
            }
        }
    }
    
    // MARK: - Shop Bargains Section
    private var shopBargainsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(L10n.string("Shop Bargains"))
                        .font(Theme.Typography.headline)
                        .foregroundColor(Theme.Colors.primaryText)
                    
                    Text(L10n.string("Steals under £15"))
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.secondaryText)
                }
                
                Spacer()
                
                NavigationLink(destination: FilteredProductsView(title: L10n.string("Shop Bargains"), filterType: .shopBargains, authService: authService)) {
                    Text(L10n.string("See All"))
                        .font(Theme.Typography.subheadline)
                        .foregroundColor(Theme.primaryColor)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: Theme.Spacing.sm) {
                    ForEach(viewModel.shopBargainsItems) { item in
                        NavigationLink(value: AppRoute.itemDetail(item)) {
                            DiscoverItemCard(item: item)
                                .frame(width: 160)
                        }
                        .buttonStyle(PlainTappableButtonStyle())
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
            }
        }
    }
    
    // MARK: - On Sale Section
    private var onSaleSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(L10n.string("On Sale"))
                        .font(Theme.Typography.headline)
                        .foregroundColor(Theme.Colors.primaryText)
                    
                    Text(L10n.string("Discounted items"))
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.secondaryText)
                }
                
                Spacer()
                
                NavigationLink(destination: FilteredProductsView(title: L10n.string("On Sale"), filterType: .onSale, authService: authService)) {
                    Text(L10n.string("See All"))
                        .font(Theme.Typography.subheadline)
                        .foregroundColor(Theme.primaryColor)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: Theme.Spacing.sm) {
                    ForEach(viewModel.onSaleItems) { item in
                        NavigationLink(value: AppRoute.itemDetail(item)) {
                            DiscoverItemCard(item: item, onLikeTap: {
                                if authService.isGuestMode { showGuestSignInPrompt = true }
                                else { viewModel.toggleLike(productId: item.productId ?? "") }
                            })
                                .frame(width: 160)
                        }
                        .buttonStyle(PlainTappableButtonStyle())
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
            }
        }
    }
    
}

// MARK: - Supporting Views

/// One row of brand pills: slow drift (30px top row, 17px second row) then loop back. Stops when user scrolls or taps.
private struct AnimatedBrandRow: View {
    let brands: [String]
    let maxOffset: CGFloat
    let authService: AuthService
    @Binding var animationStopped: Bool
    @Environment(\.colorScheme) private var colorScheme

    @State private var offset: CGFloat = 0
    @State private var driftTimer: Timer?

    private let shape = RoundedRectangle(cornerRadius: Theme.Glass.tagCornerRadius)
    private var pillBackground: Color {
        colorScheme == .light ? Theme.Colors.background : Theme.Colors.secondaryBackground
    }
    private var pillBorderColor: Color {
        colorScheme == .light ? Color.black.opacity(0.18) : Theme.Colors.glassBorder.opacity(0.5)
    }

    private let pillRowId = "pill_row_start"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) {
                    Color.clear
                        .frame(width: 0)
                        .id(pillRowId)
                    ForEach(brands, id: \.self) { brand in
                        NavigationLink(destination: FilteredProductsView(
                            title: brand,
                            filterType: .byBrand(brandName: brand),
                            authService: authService
                        )) {
                            Text(brand)
                                .font(Theme.Typography.subheadline)
                                .foregroundColor(colorScheme == .light ? Theme.Colors.primaryText : Theme.Colors.secondaryText)
                                .padding(.horizontal, Theme.Spacing.md)
                                .padding(.vertical, Theme.Spacing.sm)
                                .background(shape.fill(pillBackground))
                                .overlay(
                                    shape
                                        .strokeBorder(pillBorderColor, lineWidth: 0.5)
                                )
                        }
                        .buttonStyle(PlainTappableButtonStyle())
                        .simultaneousGesture(TapGesture().onEnded { _ in
                            animationStopped = true
                        })
                    }
                }
                .padding(.leading, Theme.Spacing.md)
                .padding(.trailing, Theme.Spacing.md)
                .offset(x: offset)
            }
            .frame(height: 44)
            .simultaneousGesture(
                DragGesture(minimumDistance: 1).onEnded { _ in
                    animationStopped = true
                }
            )
            .onAppear {
                offset = 0
                proxy.scrollTo(pillRowId, anchor: .leading)
                startDriftIfNeeded()
            }
            .onChange(of: animationStopped) { _, stopped in
                if stopped {
                    driftTimer?.invalidate()
                    driftTimer = nil
                    withAnimation(.easeOut(duration: 0.25)) {
                        offset = 0
                    }
                    proxy.scrollTo(pillRowId, anchor: .leading)
                } else {
                    offset = 0
                    proxy.scrollTo(pillRowId, anchor: .leading)
                    startDriftIfNeeded()
                }
            }
            .onDisappear {
                driftTimer?.invalidate()
                driftTimer = nil
            }
        }
    }
    
    private func startDriftIfNeeded() {
        guard !animationStopped else { return }
        driftTimer?.invalidate()
        offset = 0
        driftTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            Task { @MainActor in
                guard !animationStopped else { return }
                withAnimation(.easeInOut(duration: 3)) {
                    offset = offset == 0 ? maxOffset : 0
                }
            }
        }
        driftTimer?.tolerance = 0.2
        RunLoop.main.add(driftTimer!, forMode: .common)
        withAnimation(.easeInOut(duration: 3)) {
            offset = maxOffset
        }
    }
}

struct BrandFilterPill: View {
    let brand: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        PillTag(title: brand, isSelected: isSelected, accentWhenUnselected: true, action: action)
    }
}

struct DiscoverItemCard: View {
    let item: Item
    var onLikeTap: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            // Seller info (avatar + username) above image
            HStack(spacing: Theme.Spacing.xs) {
                // Avatar
                if let avatarURL = item.seller.avatarURL, !avatarURL.isEmpty, let url = URL(string: avatarURL) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            Circle()
                                .fill(Theme.Colors.secondaryBackground)
                                .shimmering()
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        case .failure:
                            Circle()
                                .fill(Theme.primaryColor)
                                .overlay(
                                    Text(String((item.seller.username.isEmpty ? "U" : item.seller.username).prefix(1)).uppercased())
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.white)
                                )
                        @unknown default:
                            Circle()
                                .fill(Theme.Colors.secondaryBackground)
                                .shimmering()
                        }
                    }
                    .frame(width: 20, height: 20)
                    .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Theme.primaryColor)
                        .frame(width: 20, height: 20)
                        .overlay(
                            Text(String((item.seller.username.isEmpty ? "U" : item.seller.username).prefix(1)).uppercased())
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                        )
                }
                
                // Username
                Text(item.seller.username.isEmpty ? "User" : item.seller.username)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.secondaryText)
                    .lineLimit(1)
            }
            .padding(.horizontal, Theme.Spacing.xs)
            .padding(.bottom, Theme.Spacing.xs * 1.5)
            
            // Image with like count overlay - matching feed/profile design
            GeometryReader { geometry in
                let imageWidth = geometry.size.width
                let imageHeight = imageWidth * 1.43 // 1:1.43 (10% taller than 1.3) for thumbnail
                
                ZStack(alignment: .bottomTrailing) {
                    // Background container - fixed size
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Theme.primaryColor.opacity(0.3),
                                    Theme.primaryColor.opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: imageWidth, height: imageHeight)
                    
                    // Product Image - fixed size; retries once on failure to avoid stuck placeholders
                    RetryAsyncImage(
                        url: item.imageURLs.first.flatMap { URL(string: $0) },
                        width: imageWidth,
                        height: imageHeight,
                        cornerRadius: 8,
                        placeholder: {
                            ImageShimmerPlaceholderFilled(cornerRadius: 8)
                                .frame(width: imageWidth, height: imageHeight)
                        },
                        failurePlaceholder: {
                            Image(systemName: "photo")
                                .font(.system(size: 40))
                                .foregroundColor(Theme.primaryColor.opacity(0.5))
                                .frame(width: imageWidth, height: imageHeight)
                        }
                    )
                    
                    // Like count overlay - tappable
                    LikeButtonView(isLiked: item.isLiked, likeCount: item.likeCount, action: { onLikeTap?() })
                    .padding(Theme.Spacing.xs)
                }
            }
            .aspectRatio(1.0 / 1.43, contentMode: .fit)
            .clipped()
            
            // Product details section with consistent spacing (kept below image, no overlap)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                // Brand (purple)
                if let brand = item.brand {
                    Text(brand)
                        .font(Theme.Typography.subheadline)
                        .foregroundColor(Theme.primaryColor)
                        .padding(.top, Theme.Spacing.sm)
                }
                
                // Title
                Text(item.title)
                    .font(Theme.Typography.subheadline)
                    .foregroundColor(Theme.Colors.primaryText)
                    .lineLimit(1)
                
                // Condition
                Text(item.formattedCondition)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.secondaryText)
                
                // Price
                HStack(spacing: Theme.Spacing.xs) {
                    if let originalPrice = item.originalPrice {
                        Text(item.formattedOriginalPrice)
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.secondaryText)
                            .strikethrough()
                    }
                    
                    Text(item.formattedPrice)
                        .font(Theme.Typography.subheadline)
                        .foregroundColor(Theme.Colors.primaryText)
                    
                    if let discount = item.discountPercentage {
                        Text("\(discount)%")
                            .font(Theme.Typography.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, Theme.Spacing.xs)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.red)
                            )
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.xs)
            .padding(.bottom, Theme.Spacing.sm)
        }
    }
}

// MARK: - Category primary-style button (filled when selected, outline when not)
private struct CategoryPrimaryButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    private let cornerRadius: CGFloat = 30

    var body: some View {
        Button(action: {
            HapticManager.selection()
            action()
        }) {
            Text(title)
                .font(Theme.Typography.headline)
                .foregroundStyle(isSelected ? .white : Theme.primaryColor)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.md)
        }
        .buttonStyle(PlainTappableButtonStyle())
        .background(
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(isSelected ? Theme.primaryColor : Color.clear)
        )
        .overlay {
            if !isSelected {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Theme.primaryColor, lineWidth: 2)
            }
        }
    }
}

#Preview {
    DiscoverView(tabCoordinator: TabCoordinator(), viewModel: DiscoverViewModel(authService: nil))
        .preferredColorScheme(.dark)
}

import SwiftUI

enum ProductFilterType: Equatable {
    case onSale
    case shopBargains
    case recentlyViewed
    case brandsYouLove
    case byBrand(brandName: String)
    case bySize(sizeName: String)
    /// Discover category: Men, Women, Boys, Girls (parent category filter).
    case byParentCategory(categoryName: String)
    /// Try Cart: free search, add to bag only (offers disabled).
    case tryCartSearch
    /// Shop by style: style filter via toolbar "Styles" modal (no category pills).
    case shopByStyle
}

/// One active modal (sort / filter / styles). Avoids stacking multiple `.sheet` presentations.
enum FilteredProductsActiveSheet: Identifiable, Equatable {
    case sort
    case filter
    case styles
    var id: Self { self }
}

struct FilteredProductsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authService: AuthService
    @StateObject private var viewModel: FilteredProductsViewModel
    @State private var activeSheet: FilteredProductsActiveSheet?
    @State private var tryCartSearchTask: Task<Void, Never>?
    @EnvironmentObject private var shopAllBag: ShopAllBagStore
    @State private var showGuestSignInPrompt: Bool = false
    @State private var showTryCartOnboarding: Bool = false
    /// Avoid re-presenting Try Cart intro when `onAppear` runs again (e.g. back from item detail).
    @State private var didScheduleTryCartOnboardingThisVisit: Bool = false
    /// Try Cart: when on, grid + detail use the shared bag (toolbar bag on Shop All). Defaults on for Shop All so Add to bag is visible immediately.
    @State private var shopAllBagToolbarActive: Bool

    let title: String
    let filterType: ProductFilterType
    /// When false, item detail shows only Buy now (no Send an offer). Used for Try Cart.
    let offersAllowed: Bool
    /// When false, hide floating Shopping bag bar (e.g. Shop by style). When nil, use (filterType == .tryCartSearch). Grid uses the same bag controls as Favourites when bag mode is on.
    var showAddToBag: Bool? = nil

    /// Try Cart (or explicit flag): floating bag + pass `shopAllBag` into item detail for optional toolbar cart mode.
    private var tryCartShoppingEnabled: Bool {
        showAddToBag ?? (filterType == .tryCartSearch)
    }

    init(title: String, filterType: ProductFilterType, authService: AuthService? = nil, offersAllowed: Bool = true, showAddToBag: Bool? = nil) {
        self.title = title
        self.filterType = filterType
        self.offersAllowed = offersAllowed
        self.showAddToBag = showAddToBag
        _viewModel = StateObject(wrappedValue: FilteredProductsViewModel(filterType: filterType, authService: authService))
        let bagModeDefault = showAddToBag ?? (filterType == .tryCartSearch)
        _shopAllBagToolbarActive = State(initialValue: bagModeDefault)
    }

    private func likeAction(for item: Item) -> () -> Void {
        return { [self] in
            if authService.isGuestMode { showGuestSignInPrompt = true }
            else { viewModel.toggleLike(productId: item.productId ?? "") }
        }
    }

    @ViewBuilder
    private var productGridContent: some View {
        if viewModel.isLoading && viewModel.items.isEmpty {
            FeedShimmerView()
        } else if viewModel.items.isEmpty {
            VStack(spacing: Theme.Spacing.md) {
                Spacer()
                Image(systemName: "bag")
                    .font(.system(size: 60))
                    .foregroundColor(Theme.Colors.secondaryText)
                Text(L10n.string("No products found"))
                    .font(Theme.Typography.title3)
                    .foregroundColor(Theme.Colors.secondaryText)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: Theme.Spacing.sm),
                        GridItem(.flexible(), spacing: Theme.Spacing.sm)
                    ],
                    spacing: Theme.Spacing.md
                ) {
                    ForEach(viewModel.filteredItems) { item in
                        let bagMode = tryCartShoppingEnabled && shopAllBagToolbarActive
                        let inBag = shopAllBag.items.contains(where: { $0.id == item.id })
                        NavigationLink(destination: ItemDetailView(
                            item: item,
                            authService: authService,
                            offersAllowed: offersAllowed,
                            shopAllBag: bagMode ? shopAllBag : nil,
                            activateShopBagActionsInitially: bagMode
                        )) {
                            HomeItemCard(
                                item: item,
                                onLikeTap: likeAction(for: item),
                                showAddToBag: bagMode,
                                onAddToBag: bagMode
                                    ? {
                                        if !shopAllBag.items.contains(where: { $0.id == item.id }) {
                                            shopAllBag.add(item)
                                        }
                                    }
                                    : nil,
                                isInBag: inBag,
                                onRemove: bagMode ? { shopAllBag.remove(item) } : nil
                            )
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                        .buttonStyle(PlainTappableButtonStyle())
                        .onAppear {
                            if item.id == viewModel.filteredItems.suffix(4).first?.id {
                                viewModel.loadMore()
                            }
                        }
                    }
                    if viewModel.isLoadingMore {
                        HStack {
                            Spacer()
                            ProgressView()
                                .padding()
                            Spacer()
                        }
                        .gridCellColumns(2)
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.md)
                .padding(.bottom, (tryCartShoppingEnabled && shopAllBagToolbarActive) ? 88 : 0)
            }
            .refreshable {
                await viewModel.refreshAsync()
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search Bar (same position as feed / discover / inbox)
            DiscoverSearchField(
                text: Binding(get: { viewModel.searchText }, set: { viewModel.searchText = $0 }),
                placeholder: tryCartShoppingEnabled ? "Search anything to add to bag" : L10n.string("Search items, brands or styles"),
                showClearButton: true,
                onClear: { viewModel.searchText = "" },
                topPadding: Theme.Spacing.xs
            )
            .padding(.trailing, Theme.Spacing.sm)

            // Shop by style: pill tags under search bar for style filters
            if case .shopByStyle = filterType {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.sm) {
                        PillTag(
                            title: L10n.string("All"),
                            isSelected: viewModel.selectedStyle == nil,
                            accentWhenUnselected: true,
                            action: {
                                viewModel.selectedStyle = nil
                                viewModel.loadData()
                            }
                        )
                        ForEach(Self.styleFilterOptions, id: \.self) { raw in
                            let displayName = StyleSelectionView.displayName(for: raw)
                            PillTag(
                                title: displayName,
                                isSelected: viewModel.selectedStyle == raw,
                                accentWhenUnselected: true,
                                action: {
                                    viewModel.selectedStyle = raw
                                    viewModel.loadData()
                                }
                            )
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                }
                .padding(.vertical, Theme.Spacing.sm)
            }

            // Shop All only: Row 1 = All + main categories (Women, Men, Boys, Girls, Toddlers).
            if case .tryCartSearch = filterType {
                VStack(alignment: .leading, spacing: 0) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Theme.Spacing.sm) {
                            PillTag(
                                title: L10n.string("All"),
                                isSelected: viewModel.selectedParentCategory == nil,
                                accentWhenUnselected: true,
                                action: {
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        viewModel.selectShopAllAll()
                                    }
                                }
                            )
                            ForEach(["Women", "Men", "Boys", "Girls", "Toddlers"], id: \.self) { category in
                                PillTag(
                                    title: L10n.string(category),
                                    isSelected: viewModel.selectedParentCategory == category,
                                    accentWhenUnselected: true,
                                    action: {
                                        withAnimation(.easeInOut(duration: 0.25)) {
                                            viewModel.selectShopAllMain(category)
                                        }
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.md)
                    }
                    .padding(.vertical, Theme.Spacing.sm)

                    // Row 2: subcategories (slide in/out when a main is selected)
                    if viewModel.selectedParentCategory != nil {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: Theme.Spacing.sm) {
                                ForEach(viewModel.shopAllSubCategories, id: \.id) { sub in
                                    PillTag(
                                        title: sub.name,
                                        isSelected: viewModel.selectedSubCategory?.id == sub.id,
                                        accentWhenUnselected: true,
                                        action: {
                                            withAnimation(.easeInOut(duration: 0.25)) {
                                                viewModel.selectShopAllSub(sub)
                                            }
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal, Theme.Spacing.md)
                        }
                        .padding(.vertical, Theme.Spacing.sm)
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .move(edge: .top).combined(with: .opacity)
                        ))
                    }

                    // Row 3: sub-subcategories (slide in/out when a sub with children is selected)
                    if viewModel.selectedSubCategory != nil && !viewModel.shopAllSubSubCategories.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: Theme.Spacing.sm) {
                                ForEach(viewModel.shopAllSubSubCategories, id: \.id) { subSub in
                                    PillTag(
                                        title: subSub.name,
                                        isSelected: viewModel.selectedCategoryId == Int(subSub.id),
                                        accentWhenUnselected: true,
                                        action: {
                                            withAnimation(.easeInOut(duration: 0.25)) {
                                                viewModel.selectShopAllSubSub(subSub)
                                            }
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal, Theme.Spacing.md)
                        }
                        .padding(.vertical, Theme.Spacing.sm)
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .move(edge: .top).combined(with: .opacity)
                        ))
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: viewModel.selectedParentCategory)
                .animation(.easeInOut(duration: 0.25), value: viewModel.selectedSubCategory?.id)
                .animation(.easeInOut(duration: 0.25), value: viewModel.shopAllSubSubCategories.count)
            }

            // Pill tags for main categories (Women, Men, Boys, Girls): Condition, Style, Colour, Price
            if case .byParentCategory = filterType {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.sm) {
                        PillTag(
                            title: L10n.string("Condition"),
                            isSelected: viewModel.filterCondition != nil,
                            accentWhenUnselected: true,
                            action: { activeSheet = .filter }
                        )
                        PillTag(
                            title: L10n.string("Style"),
                            isSelected: false,
                            accentWhenUnselected: true,
                            action: { activeSheet = .filter }
                        )
                        PillTag(
                            title: L10n.string("Colour"),
                            isSelected: false,
                            accentWhenUnselected: true,
                            action: { activeSheet = .filter }
                        )
                        PillTag(
                            title: L10n.string("Price"),
                            isSelected: !viewModel.filterMinPrice.isEmpty || !viewModel.filterMaxPrice.isEmpty,
                            accentWhenUnselected: true,
                            action: { activeSheet = .filter }
                        )
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                }
                .padding(.vertical, Theme.Spacing.sm)
            }

            // Filter / Sort row (grey pills, no shadow)
            HStack {
                Button(action: { activeSheet = .filter }) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: "line.3.horizontal.decrease")
                            .font(.system(size: 14))
                        Text(L10n.string("Filter"))
                            .font(Theme.Typography.subheadline)
                    }
                    .foregroundColor(Theme.Colors.secondaryText)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Glass.cornerRadius)
                            .fill(Theme.Colors.secondaryBackground)
                    )
                }
                .buttonStyle(HapticTapButtonStyle(haptic: { HapticManager.selection() }))

                Spacer()

                Button(action: { activeSheet = .sort }) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text(L10n.string(viewModel.sortOption.rawValue))
                            .font(Theme.Typography.subheadline)
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 12))
                    }
                    .foregroundColor(Theme.Colors.secondaryText)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Glass.cornerRadius)
                            .fill(Theme.Colors.secondaryBackground)
                    )
                }
                .buttonStyle(HapticTapButtonStyle(haptic: { HapticManager.selection() }))
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(Theme.Colors.background)

            // Product Grid
            productGridContent
        }
        .background(Theme.Colors.background)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHidden(false)
        .toolbarBackground(Theme.Colors.background, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            if authService.isAuthenticated {
                viewModel.updateAuthToken(authService.authToken)
            }
            viewModel.loadData()
            scheduleTryCartOnboardingIfNeeded()
        }
        .onChange(of: viewModel.searchText) { _, _ in
            if case .tryCartSearch = filterType {
                tryCartSearchTask?.cancel()
                tryCartSearchTask = Task {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        viewModel.loadData()
                    }
                }
            }
            if case .shopByStyle = filterType {
                tryCartSearchTask?.cancel()
                tryCartSearchTask = Task {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        viewModel.loadData()
                    }
                }
            }
        }
        .onChange(of: authService.authToken) { oldToken, newToken in
            if authService.isAuthenticated {
                viewModel.updateAuthToken(newToken)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .preluraRecentlyViewedDidUpdate)) { _ in
            if case .recentlyViewed = filterType {
                viewModel.loadData()
            }
        }
        .onChange(of: viewModel.selectedParentCategory) { _, _ in
            if case .tryCartSearch = filterType {
                viewModel.loadData()
            }
        }
        .toolbar {
            if case .shopByStyle = filterType {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L10n.string("Styles")) {
                        activeSheet = .styles
                    }
                    .foregroundColor(Theme.Colors.primaryText)
                }
            }
            if tryCartShoppingEnabled {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
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

                    NavigationLink(destination: MyFavouritesView(fromShopAll: true)) {
                        Image(systemName: "heart")
                            .foregroundColor(Theme.Colors.primaryText)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainTappableButtonStyle())
                }
            }
        }
        .overlay(alignment: .bottom) {
            if tryCartShoppingEnabled {
                shopAllFloatingBar
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .sort:
                filteredProductsSortSheet
            case .filter:
                filteredProductsFilterSheet
            case .styles:
                stylesSheetContent
            }
        }
        .fullScreenCover(isPresented: $showGuestSignInPrompt) { GuestSignInPromptView() }
        .overlay {
            if showTryCartOnboarding {
                TryCartOnboardingPopupOverlay(onComplete: finishTryCartOnboarding)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .zIndex(900)
            }
        }
    }

    private func scheduleTryCartOnboardingIfNeeded() {
        guard case .tryCartSearch = filterType else { return }
        guard !didScheduleTryCartOnboardingThisVisit else { return }
        guard AppBannerPolicy.shouldPresent(.tryCartShopAllIntro) else { return }
        didScheduleTryCartOnboardingThisVisit = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 420_000_000)
            withAnimation(.easeOut(duration: 0.22)) {
                showTryCartOnboarding = true
            }
        }
    }

    private func finishTryCartOnboarding() {
        if !AppBannerPolicy.forceShowTryCartShopAllIntroEveryTime {
            AppBannerPolicy.markSeen(.tryCartShopAllIntro)
        }
        withAnimation(.easeOut(duration: 0.2)) {
            showTryCartOnboarding = false
        }
    }

    /// Multi-buy style: floating primary-colour glassy pill (bag icon + "Shopping bag" + total).
    private var shopAllFloatingBar: some View {
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

    private var optionDivider: some View {
        Rectangle()
            .fill(Theme.Colors.glassBorder)
            .frame(height: 0.5)
            .padding(.horizontal, Theme.Spacing.md)
    }

    private var filteredProductsSortSheet: some View {
        OptionsSheet(title: L10n.string("Sort"), onDismiss: { activeSheet = nil }, useCustomCornerRadius: false) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(FilteredProductsSortOption.allCases.enumerated()), id: \.offset) { index, option in
                    Button(action: { viewModel.sortOption = option }) {
                        HStack {
                            Text(L10n.string(option.rawValue))
                                .font(Theme.Typography.body)
                                .foregroundColor(Theme.Colors.primaryText)
                            Spacer()
                            if viewModel.sortOption == option {
                                Image(systemName: "checkmark")
                                    .foregroundColor(Theme.primaryColor)
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, Theme.Spacing.md)
                    }
                    .buttonStyle(HapticTapButtonStyle())
                    if index < FilteredProductsSortOption.allCases.count - 1 { optionDivider }
                }
                optionDivider
                VStack(spacing: Theme.Spacing.sm) {
                    BorderGlassButton(L10n.string("Clear")) {
                        viewModel.sortOption = .relevance
                    }
                    PrimaryGlassButton(L10n.string("Apply")) {
                        activeSheet = nil
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.md)
            }
            .padding(.vertical, Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Style filter options (StyleEnum raw values; same set as StyleSelectionView in SellView).
    private static let styleFilterOptions: [String] = [
        "WORKWEAR", "WORKOUT", "CASUAL", "PARTY_DRESS", "PARTY_OUTFIT", "FORMAL_WEAR", "EVENING_WEAR",
        "WEDDING_GUEST", "LOUNGEWEAR", "VACATION_RESORT_WEAR", "FESTIVAL_WEAR", "ACTIVEWEAR", "NIGHTWEAR",
        "VINTAGE", "Y2K", "BOHO", "MINIMALIST", "GRUNGE", "CHIC", "STREETWEAR", "PREPPY", "RETRO",
        "COTTAGECORE", "GLAM", "SUMMER_STYLES", "WINTER_ESSENTIALS", "SPRING_FLORALS", "AUTUMN_LAYERS",
        "RAINY_DAY_WEAR", "DENIM_JEANS", "DRESSES_GOWNS", "JACKETS_COATS", "KNITWEAR_SWEATERS",
        "SKIRTS_SHORTS", "SUITS_BLAZERS", "TOPS_BLOUSES", "SHOES_FOOTWEAR", "TRAVEL_FRIENDLY",
        "MATERNITY_WEAR", "ATHLEISURE", "ECO_FRIENDLY", "FESTIVAL_READY", "DATE_NIGHT", "ETHNIC_WEAR",
        "OFFICE_PARTY_OUTFIT", "COCKTAIL_ATTIRE", "PROM_DRESSES", "MUSIC_CONCERT_WEAR", "OVERSIZED",
        "SLIM_FIT", "RELAXED_FIT", "CHRISTMAS", "SCHOOL_UNIFORMS"
    ]

    private var stylesSheetContent: some View {
        OptionsSheet(title: L10n.string("Styles"), onDismiss: { activeSheet = nil }, useCustomCornerRadius: false) {
            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Self.styleFilterOptions, id: \.self) { raw in
                            Button(action: {
                                viewModel.selectedStyle = viewModel.selectedStyle == raw ? nil : raw
                            }) {
                                HStack {
                                    Text(StyleSelectionView.displayName(for: raw))
                                        .font(Theme.Typography.body)
                                        .foregroundColor(Theme.Colors.primaryText)
                                    Spacer()
                                    if viewModel.selectedStyle == raw {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(Theme.primaryColor)
                                    }
                                }
                                .padding(.horizontal, Theme.Spacing.md)
                                .padding(.vertical, Theme.Spacing.md)
                            }
                            .buttonStyle(HapticTapButtonStyle())
                            if raw != Self.styleFilterOptions.last {
                                optionDivider
                            }
                        }
                    }
                }
                .frame(maxHeight: .infinity)
                optionDivider
                VStack(spacing: Theme.Spacing.sm) {
                    BorderGlassButton(L10n.string("Clear")) {
                        viewModel.selectedStyle = nil
                        viewModel.loadData()
                        activeSheet = nil
                    }
                    PrimaryGlassButton(L10n.string("Apply")) {
                        viewModel.loadData()
                        activeSheet = nil
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.md)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.vertical, Theme.Spacing.md)
        }
    }

    private var filteredProductsFilterSheet: some View {
        OptionsSheet(title: L10n.string("Filter"), onDismiss: { activeSheet = nil }, useCustomCornerRadius: false) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                Text(L10n.string("Condition"))
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.secondaryText)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.top, Theme.Spacing.xs)
                ForEach(profileConditionOptions, id: \.raw) { option in
                    Button(action: {
                        viewModel.filterCondition = viewModel.filterCondition == option.raw ? nil : option.raw
                    }) {
                        HStack {
                            Text(L10n.string(option.display))
                                .font(Theme.Typography.body)
                                .foregroundColor(Theme.Colors.primaryText)
                            Spacer()
                            if viewModel.filterCondition == option.raw {
                                Image(systemName: "checkmark")
                                    .foregroundColor(Theme.primaryColor)
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, Theme.Spacing.md)
                    }
                    .buttonStyle(HapticTapButtonStyle())
                    optionDivider
                }
                Text(L10n.string("Price range"))
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.secondaryText)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.top, Theme.Spacing.sm)
                HStack(spacing: Theme.Spacing.sm) {
                    SettingsTextField(
                        placeholder: L10n.string("Min. Price"),
                        text: PriceFieldFilter.binding(get: { viewModel.filterMinPrice }, set: { viewModel.filterMinPrice = $0 }),
                        keyboardType: .decimalPad,
                        bordered: true
                    )
                    .onChange(of: viewModel.filterMinPrice) { _, newValue in
                        let sanitized = PriceFieldFilter.sanitizePriceInput(newValue)
                        if sanitized != newValue { viewModel.filterMinPrice = sanitized }
                    }
                    SettingsTextField(
                        placeholder: L10n.string("Max. Price"),
                        text: PriceFieldFilter.binding(get: { viewModel.filterMaxPrice }, set: { viewModel.filterMaxPrice = $0 }),
                        keyboardType: .decimalPad,
                        bordered: true
                    )
                    .onChange(of: viewModel.filterMaxPrice) { _, newValue in
                        let sanitized = PriceFieldFilter.sanitizePriceInput(newValue)
                        if sanitized != newValue { viewModel.filterMaxPrice = sanitized }
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.md)
                optionDivider
                VStack(spacing: Theme.Spacing.sm) {
                    BorderGlassButton(L10n.string("Clear")) {
                        viewModel.filterCondition = nil
                        viewModel.filterMinPrice = ""
                        viewModel.filterMaxPrice = ""
                    }
                    PrimaryGlassButton(L10n.string("Apply")) {
                        activeSheet = nil
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.md)
                }
                .padding(.vertical, Theme.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

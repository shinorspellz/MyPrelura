import SwiftUI
import PhotosUI
import Shimmer

// MARK: - Profile sort
enum ProfileSortOption: String, CaseIterable {
    case relevance = "Relevance"
    case newestFirst = "Newest First"
    case priceAsc = "Price Ascending"
    case priceDesc = "Price Descending"
}

// MARK: - Condition filter options. Shared with UserProfileView.
let profileConditionOptions: [(raw: String, display: String)] = [
    ("EXCELLENT_CONDITION", "Excellent Condition"),
    ("GOOD_CONDITION", "Good Condition"),
    ("BRAND_NEW_WITH_TAGS", "Brand New With Tags"),
    ("BRAND_NEW_WITHOUT_TAGS", "Brand new Without Tags"),
    ("HEAVILY_USED", "Heavily Used")
]

/// One active modal for profile listings. Chaining multiple `.sheet(isPresented:)` on the same view stacks sheets when two bindings are true (e.g. sort + filter).
enum ProfileListingsSheet: Identifiable, Equatable {
    case sort
    case filter
    case shopSearch
    var id: Self { self }
}

struct ProfileView: View {
    @EnvironmentObject var authService: AuthService
    @ObservedObject var tabCoordinator: TabCoordinator
    @StateObject private var viewModel: ProfileViewModel
    @State private var scrollPosition: String? = "profile_top"
    @State private var isMultiBuyEnabled: Bool = false
    @State private var selectedBrands: Set<String> = []
    @State private var expandedCategories: Bool = false
    @State private var selectedCategory: String? = nil
    @State private var selectedPhoto: PhotosPickerItem? = nil
    @State private var profileImage: UIImage? = nil
    @State private var isVacationMode: Bool = false
    @State private var profileSort: ProfileSortOption = .newestFirst
    @State private var filterCondition: String? = nil
    @State private var filterMinPrice: String = ""
    @State private var filterMaxPrice: String = ""
    @State private var activeListingsSheet: ProfileListingsSheet?
    /// Tracks horizontal scroll position in Top brands so it doesn't reset when selection changes.
    @State private var topBrandsScrollId: String? = nil
    @State private var showFullBioSheet: Bool = false
    @State private var filterMultiBuyOnly: Bool = false
    @State private var shopSearchQuery: String = ""
    /// When true, Multi-buy button has entered selection mode: show "Select" pill on each item; tapping toggles selection; floating button shows cart.
    @State private var isMultiBuySelectionMode: Bool = false
    /// Item ids (uuidString) selected for multi-buy. Used when isMultiBuySelectionMode is true.
    @State private var selectedMultiBuyItemIds: Set<String> = []

    private let topId = "profile_top"

    init(tabCoordinator: TabCoordinator) {
        self.tabCoordinator = tabCoordinator
        _viewModel = StateObject(wrappedValue: ProfileViewModel(authService: nil))
    }
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            ScrollViewReader { proxy in
                ScrollView {
                    if authService.isGuestMode {
                        Color.clear.frame(height: 1).id(topId)
                        GuestSignInPromptView()
                    } else if viewModel.isLoading {
                        ProfileShimmerView()
                            .frame(minHeight: UIScreen.main.bounds.height)
                    } else {
                        VStack(spacing: 0) {
                            Color.clear.frame(height: 1).id(topId)
                            profileSection
                            
                            // Bio/Welcome Message
                            if let bio = viewModel.user?.bio {
                                bioSection(bio)
                            }
                            // Location (below bio, with grey icon)
                            if let location = viewModel.user?.location, !location.isEmpty {
                                profileLocationRow(location)
                            }
                            // Verification status (so user can see if account is verified)
                            if let isVerified = viewModel.user?.isVerified {
                                profileVerificationRow(isVerified: isVerified)
                            }
                            // When vacation mode is on, hide products and show holiday message (matches Flutter)
                            if viewModel.user?.isVacationMode == true {
                                vacationModeSection
                            } else {
                                // Categories, Multi-buy, Top Brands, Filter/Sort — only when user has products
                                if !viewModel.userItems.isEmpty {
                                    filtersSection
                                }
                                // Items Grid
                                itemsGridSection
                            }
                        }
                    }
                }
                .scrollPosition(id: $scrollPosition, anchor: .top)
                .onAppear {
                    tabCoordinator.reportAtTop(tab: 4, isAtTop: true)
                    tabCoordinator.registerScrollToTop(tab: 4) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(topId, anchor: .top)
                        }
                    }
                    tabCoordinator.registerRefresh(tab: 4) {
                        Task { await viewModel.refreshAsync() }
                    }
                }
            }
            .onChange(of: scrollPosition) { _, new in
                tabCoordinator.reportAtTop(tab: 4, isAtTop: new == topId)
            }
            .background(Theme.Colors.background)
            .refreshable {
                await viewModel.refreshAsync()
            }

            // Shopping bag button: visible from 1st selection (grey, disabled); tappable from 2nd (materialize entrance).
            if !selectedMultiBuyItemIds.isEmpty && isMultiBuySelectionMode {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        GlassEffectContainer(spacing: 0) {
                            Group {
                                if selectedMultiBuyItemIds.count >= 2 {
                                    NavigationLink(destination: MultiBuyCartView(
                                        selectedIds: $selectedMultiBuyItemIds,
                                        allItems: viewModel.userItems,
                                        sellerUserId: viewModel.user?.userId
                                    )) {
                                        shoppingBagButtonLabel
                                    }
                                    .buttonStyle(PlainTappableButtonStyle())
                                } else {
                                    shoppingBagButtonLabel
                                        .opacity(0.6)
                                        .allowsHitTesting(false)
                                }
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, Theme.Spacing.lg)
                            .padding(.vertical, Theme.Spacing.md)
                            .glassEffect(.clear.tint(Theme.primaryColor), in: .rect(cornerRadius: 30))
                            .glassEffectTransition(.materialize)
                        }
                        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                        .animation(.easeInOut(duration: 0.35), value: selectedMultiBuyItemIds.count)
                        Spacer()
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.bottom, 15)
                }
                .allowsHitTesting(true)
            }
        }
        .navigationTitle(viewModel.user?.username ?? L10n.string("Profile"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHidden(viewModel.isLoading || authService.isGuestMode)
        .toolbar {
            if !authService.isGuestMode {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(value: AppRoute.menu(MenuContext(
                        listingCount: viewModel.user?.listingsCount ?? 0,
                        isMultiBuyEnabled: viewModel.user?.isMultibuyEnabled ?? isMultiBuyEnabled,
                        isVacationMode: viewModel.user?.isVacationMode ?? isVacationMode,
                        username: viewModel.user?.username
                    ))) {
                        Image(systemName: "line.3.horizontal")
                            .foregroundColor(Theme.Colors.primaryText)
                            .frame(width: Theme.AppBar.buttonSize, height: Theme.AppBar.buttonSize)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(HapticTapButtonStyle())
                }
            }
        }
        .onAppear {
            if authService.isGuestMode { return }
            if authService.isAuthenticated {
                viewModel.updateAuthToken(authService.authToken)
                // Only load when we have no data (first visit); otherwise persist like Home/Discover
                if viewModel.user == nil {
                    viewModel.refresh()
                }
            }
        }
        .onChange(of: authService.isGuestMode) { _, isGuest in
            if isGuest { return }
            if authService.isAuthenticated {
                viewModel.updateAuthToken(authService.authToken)
                viewModel.refresh()
            }
        }
        .onChange(of: authService.authToken) { oldToken, newToken in
            // Update token and refresh when token changes
            if authService.isAuthenticated && !authService.isGuestMode {
                viewModel.updateAuthToken(newToken)
                viewModel.refresh()
            }
        }
        .onChange(of: viewModel.user?.username) { _, _ in
            if let u = viewModel.user {
                isMultiBuyEnabled = u.isMultibuyEnabled
                isVacationMode = u.isVacationMode
            }
        }
        .onChange(of: viewModel.user?.isVacationMode) { _, new in
            if let v = new { isVacationMode = v }
        }
        .onChange(of: viewModel.user?.isMultibuyEnabled) { _, new in
            if let v = new { isMultiBuyEnabled = v }
        }
        .onReceive(NotificationCenter.default.publisher(for: .preluraUserProfileDidUpdate)) { _ in
            viewModel.refresh()
        }
    }

    private var shoppingBagButtonLabel: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "cart.fill")
                .font(.system(size: 16, weight: .semibold))
            Text(L10n.string("Shopping bag"))
                .font(Theme.Typography.headline)
        }
    }

    private static let profilePhotoSize: CGFloat = 88

    /// Placeholder when no photo or load failed (circle + person icon).
    private var profilePhotoPlaceholder: some View {
        Circle()
            .fill(Theme.primaryColor)
            .frame(width: Self.profilePhotoSize, height: Self.profilePhotoSize)
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.white)
            )
    }

    // MARK: - Profile Section
    private var profileSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            // Row 1: Profile photo and stats centered in remaining space
            HStack(alignment: .center, spacing: 0) {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Group {
                        if let profileImage = profileImage {
                            Image(uiImage: profileImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: Self.profilePhotoSize, height: Self.profilePhotoSize)
                                .clipShape(Circle())
                        } else if let user = viewModel.user, let avatarURL = user.avatarURL, !avatarURL.isEmpty, let url = URL(string: avatarURL) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .empty:
                                    Circle()
                                        .fill(Theme.Colors.secondaryBackground)
                                        .frame(width: Self.profilePhotoSize, height: Self.profilePhotoSize)
                                        .shimmering()
                                case .success(let image):
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: Self.profilePhotoSize, height: Self.profilePhotoSize)
                                        .clipShape(Circle())
                                case .failure:
                                    profilePhotoPlaceholder
                                @unknown default:
                                    profilePhotoPlaceholder
                                }
                            }
                            .frame(width: Self.profilePhotoSize, height: Self.profilePhotoSize)
                            .clipShape(Circle())
                        } else {
                            profilePhotoPlaceholder
                        }
                    }
                }
                .onChange(of: selectedPhoto) { oldValue, newItem in
                    Task {
                        if let newItem = newItem,
                           let data = try? await newItem.loadTransferable(type: Data.self),
                           let image = UIImage(data: data) {
                            await MainActor.run {
                                profileImage = image
                                viewModel.uploadProfileImage(image, authToken: authService.authToken)
                            }
                        }
                    }
                }
                .overlay {
                    if viewModel.isUploadingProfilePhoto {
                        ProgressView()
                            .tint(.white)
                            .frame(width: Self.profilePhotoSize, height: Self.profilePhotoSize)
                            .background(Color.black.opacity(0.4))
                            .clipShape(Circle())
                    }
                }
                .overlay(
                    Circle()
                        .stroke(Theme.Colors.profileRingBorder, lineWidth: 2.5)
                        .frame(width: Self.profilePhotoSize, height: Self.profilePhotoSize)
                )
                .alert("Profile photo", isPresented: Binding(
                    get: { viewModel.profilePhotoUploadError != nil },
                    set: { if !$0 { viewModel.profilePhotoUploadError = nil } }
                )) {
                    Button("OK") { viewModel.profilePhotoUploadError = nil }
                } message: {
                    if let err = viewModel.profilePhotoUploadError {
                        Text(err)
                    }
                }

                Spacer(minLength: Theme.Spacing.xl)
                // Listings, Following, Followers on the same row as the profile photo
                profileStatsRowCompact
                Spacer(minLength: Theme.Spacing.xl)
            }

            // Row 2: Stars (tappable → Reviews) only; sale icon decorative only (not tappable)
            VStack(alignment: .leading, spacing: 2) {
                let hasSaleItems = viewModel.userItems.contains { $0.discountPercentage != nil }
                let showSaleIcon = hasSaleItems && (viewModel.user?.isVacationMode != true)
                if let u = viewModel.user {
                    HStack(alignment: .center, spacing: 4) {
                        NavigationLink(value: AppRoute.reviews(username: u.username, rating: u.rating)) {
                            HStack(alignment: .center, spacing: 4) {
                                ForEach(0..<5, id: \.self) { _ in
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 13))
                                        .foregroundColor(.yellow)
                                }
                                Text("(\(u.reviewCount))")
                                    .font(Theme.Typography.subheadline)
                                    .foregroundColor(Theme.Colors.secondaryText)
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: true)
                            }
                        }
                        .buttonStyle(HapticTapButtonStyle())
                        if showSaleIcon {
                            Spacer(minLength: 4)
                            Image("SaleIcon")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: 16)
                                .allowsHitTesting(false)
                        }
                    }
                } else {
                    HStack(alignment: .center, spacing: 4) {
                        ForEach(0..<5, id: \.self) { _ in
                            Image(systemName: "star.fill")
                                .font(.system(size: 13))
                                .foregroundColor(.yellow)
                        }
                        Text("(\(viewModel.user?.reviewCount ?? 0))")
                            .font(Theme.Typography.subheadline)
                            .foregroundColor(Theme.Colors.secondaryText)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: true)
                        if showSaleIcon {
                            Spacer(minLength: 4)
                            Image("SaleIcon")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: 16)
                                .allowsHitTesting(false)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.top, Theme.Spacing.md)
        .padding(.bottom, Theme.Spacing.xs)
    }

    /// Stats row next to avatar — compact fonts so we don't increase effective screen width.
    private var profileStatsRowCompact: some View {
        HStack(spacing: Theme.Spacing.md) {
            StatColumn(value: "\(viewModel.user?.listingsCount ?? 0)", label: (viewModel.user?.listingsCount ?? 0) == 1 ? L10n.string("Listing") : L10n.string("Listings"), compact: true)
            if let u = viewModel.user {
                NavigationLink(destination: FollowingListView(username: u.username)) {
                    StatColumn(value: "\(u.followingsCount)", label: L10n.string("Following"), compact: true)
                }
                .buttonStyle(PlainTappableButtonStyle())
                NavigationLink(destination: FollowersListView(username: u.username)) {
                    StatColumn(value: "\(u.followersCount)", label: (u.followersCount == 1 ? L10n.string("Follower") : L10n.string("Followers")), compact: true)
                }
                .buttonStyle(PlainTappableButtonStyle())
            } else {
                StatColumn(value: "\(viewModel.user?.followingsCount ?? 0)", label: L10n.string("Following"), compact: true)
                StatColumn(value: "\(viewModel.user?.followersCount ?? 0)", label: L10n.string("Followers"), compact: true)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
    
    // MARK: - Bio Section
    private func bioSection(_ bio: String) -> some View {
        let limit = 100
        let truncated = bio.count > limit
        let displayText = truncated ? String(bio.prefix(limit)) + "..." : bio
        return         Group {
            if truncated {
                Button(action: { showFullBioSheet = true }) {
                    Text(displayText)
                        .font(Theme.Typography.subheadline)
                        .foregroundColor(Theme.Colors.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.top, Theme.Spacing.xs)
                        .padding(.bottom, Theme.Spacing.sm)
                }
                .buttonStyle(PlainTappableButtonStyle())
            } else {
                Text(displayText)
                    .font(Theme.Typography.subheadline)
                    .foregroundColor(Theme.Colors.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.top, Theme.Spacing.xs)
                    .padding(.bottom, Theme.Spacing.sm)
            }
        }
        .sheet(isPresented: $showFullBioSheet) {
            OptionsSheet(title: L10n.string("Bio"), onDismiss: { showFullBioSheet = false }, detents: [.medium, .large], useCustomCornerRadius: false) {
                ScrollView {
                    Text(bio)
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Theme.Spacing.md)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    /// Location row: grey location icon + text, shown below bio.
    private func profileLocationRow(_ location: String) -> some View {
        HStack(alignment: .center, spacing: 6) {
            Image(systemName: "location.fill")
                .font(.system(size: 12))
                .foregroundColor(Theme.Colors.secondaryText)
            Text(location)
                .font(Theme.Typography.subheadline)
                .foregroundColor(Theme.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.bottom, Theme.Spacing.sm)
    }

    /// Shows whether the account email is verified (so user can tell at a glance).
    private func profileVerificationRow(isVerified: Bool) -> some View {
        HStack(alignment: .center, spacing: 6) {
            Image(systemName: isVerified ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 12))
                .foregroundColor(isVerified ? Color.green : Theme.Colors.secondaryText)
            Text(isVerified ? "Email verified" : "Email not verified")
                .font(Theme.Typography.subheadline)
                .foregroundColor(Theme.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.bottom, Theme.Spacing.sm)
    }

    /// Shown when vacation mode is on: products and filters are hidden (matches Flutter HolidayModeWidget).
    private var vacationModeSection: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer(minLength: 40)
            Image(systemName: "umbrella.fill")
                .font(.system(size: 64))
                .foregroundColor(Theme.Colors.secondaryText)
            Text(L10n.string("Vacation mode turned on"))
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.secondaryText)
                .multilineTextAlignment(.center)
            Spacer(minLength: 40)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xl)
    }
    
    // MARK: - Filters Section
    private var filtersSection: some View {
        VStack(spacing: 0) {
            // Categories (Expandable)
            VStack(spacing: 0) {
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        expandedCategories.toggle()
                    }
                }) {
                    HStack {
                        Text(L10n.string("Categories"))
                            .font(Theme.Typography.subheadline)
                            .foregroundColor(Theme.Colors.secondaryText)
                        Spacer()
                        Image(systemName: expandedCategories ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.Colors.secondaryText)
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.md)
                }
                .buttonStyle(HapticTapButtonStyle(haptic: { HapticManager.toggle() }))
                
                // Expanded categories list (standard spacing: Theme.Spacing)
                if expandedCategories {
                    VStack(spacing: 0) {
                        ForEach(viewModel.categoriesWithCounts, id: \.name) { category in
                            Button(action: {
                                selectedCategory = selectedCategory == category.name ? nil : category.name
                                // TODO: Filter items by category
                            }) {
                                HStack(spacing: Theme.Spacing.sm) {
                                    Image(systemName: "minus")
                                        .font(.system(size: 13))
                                        .foregroundColor(Theme.Colors.secondaryText)
                                    
                                    Text(category.name)
                                        .font(Theme.Typography.subheadline)
                                        .foregroundColor(Theme.Colors.primaryText)
                                    
                                    Text("(\(category.count) \(category.count == 1 ? L10n.string("item") : L10n.string("items"))")
                                        .font(Theme.Typography.caption)
                                        .foregroundColor(Theme.Colors.secondaryText)
                                    
                                    Spacer(minLength: Theme.Spacing.md)
                                    
                                    Image(systemName: selectedCategory == category.name ? "checkmark.square" : "square")
                                        .font(.system(size: 16))
                                        .foregroundColor(selectedCategory == category.name ? Theme.primaryColor : Theme.Colors.secondaryText)
                                }
                                .padding(.horizontal, Theme.Spacing.md)
                                .padding(.vertical, Theme.Spacing.md)
                            }
                            .buttonStyle(HapticTapButtonStyle(haptic: { HapticManager.selection() }))
                            
                            if category.name != viewModel.categoriesWithCounts.last?.name {
                                ContentDivider()
                                    .padding(.leading, Theme.Spacing.md)
                            }
                        }
                    }
                }
            }
            .overlay(ContentDivider(), alignment: .bottom)
            
            // Top Brands (same component and placement as Home filter tags)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: Theme.Spacing.sm) {
                    Button(action: {
                        HapticManager.selection()
                        activeListingsSheet = .shopSearch
                    }) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 16))
                            .foregroundColor(Theme.Colors.secondaryText)
                    }
                    .buttonStyle(HapticTapButtonStyle())
                    Button(action: {
                        HapticManager.selection()
                        activeListingsSheet = .shopSearch
                    }) {
                        Text(L10n.string("Top brands"))
                            .font(Theme.Typography.subheadline)
                            .foregroundColor(Theme.Colors.secondaryText)
                    }
                    .buttonStyle(PlainTappableButtonStyle())
                    Spacer()
                    if viewModel.user?.isMultibuyEnabled ?? isMultiBuyEnabled {
                        Button(action: {
                            HapticManager.selection()
                            if isMultiBuySelectionMode {
                                isMultiBuySelectionMode = false
                                selectedMultiBuyItemIds = []
                            } else {
                                isMultiBuySelectionMode = true
                            }
                        }) {
                            Text(L10n.string("Multi-buy"))
                                .font(Theme.Typography.subheadline)
                                .foregroundColor(isMultiBuySelectionMode ? .white : Theme.primaryColor)
                                .padding(.horizontal, Theme.Spacing.md)
                                .padding(.vertical, Theme.Spacing.sm)
                                .background(
                                    RoundedRectangle(cornerRadius: Theme.Glass.tagCornerRadius)
                                        .fill(isMultiBuySelectionMode ? Theme.primaryColor : Theme.primaryColor.opacity(0.2))
                                )
                        }
                        .buttonStyle(PlainTappableButtonStyle())
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.sm)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.sm) {
                        ForEach(viewModel.topBrands, id: \.self) { brand in
                            BrandFilterPill(
                                brand: brand,
                                isSelected: selectedBrands.contains(brand),
                                action: {
                                    HapticManager.selection()
                                    if selectedBrands.contains(brand) {
                                        selectedBrands.remove(brand)
                                    } else if selectedBrands.count < 2 {
                                        selectedBrands.insert(brand)
                                    }
                                }
                            )
                            .id(brand)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                }
                .scrollPosition(id: $topBrandsScrollId, anchor: .leading)
                .id("profile_top_brands_pills")
                .padding(.vertical, Theme.Spacing.sm)
            }
            .animation(.none, value: selectedBrands)
            
            // Filter and Sort (matches Flutter FilterAndSort: bottom sheets + Clear)
            HStack {
                Button(action: {
                    activeListingsSheet = .filter
                }) {
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
                
                Button(action: {
                    activeListingsSheet = .sort
                }) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text(L10n.string(profileSort.rawValue))
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
        }
        .sheet(item: $activeListingsSheet) { sheet in
            switch sheet {
            case .sort:
                profileSortSheet
            case .filter:
                profileFilterSheet
            case .shopSearch:
                shopSearchSheetContent
            }
        }
    }
    
    private var optionDivider: some View {
        Rectangle()
            .fill(Theme.Colors.glassBorder)
            .frame(height: 0.5)
            .padding(.horizontal, Theme.Spacing.md)
    }

    // MARK: - Sort sheet (same presentation as product Options sheet)
    private var profileSortSheet: some View {
        OptionsSheet(title: L10n.string("Sort"), onDismiss: { activeListingsSheet = nil }, useCustomCornerRadius: false) {
            SortSheetContent(selectedSort: $profileSort, onApply: { activeListingsSheet = nil })
        }
    }

    // MARK: - Filter sheet (same presentation as product Options sheet)
    private var profileFilterSheet: some View {
        OptionsSheet(title: L10n.string("Filter"), onDismiss: { activeListingsSheet = nil }, useCustomCornerRadius: false) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                Text(L10n.string("Condition"))
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.secondaryText)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.top, Theme.Spacing.xs)
                ForEach(profileConditionOptions, id: \.raw) { option in
                    Button(action: {
                        filterCondition = filterCondition == option.raw ? nil : option.raw
                    }) {
                        HStack {
                            Text(L10n.string(option.display))
                                .font(Theme.Typography.body)
                                .foregroundColor(Theme.Colors.primaryText)
                            Spacer()
                            if filterCondition == option.raw {
                                Image(systemName: "checkmark")
                                    .foregroundColor(Theme.primaryColor)
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, Theme.Spacing.md)
                    }
                    .buttonStyle(HapticTapButtonStyle(haptic: { HapticManager.selection() }))
                    optionDivider
                }
                Text(L10n.string("Price range"))
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.secondaryText)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.top, Theme.Spacing.sm)
                HStack(spacing: Theme.Spacing.sm) {
                    SettingsTextField(placeholder: L10n.string("Min. Price"), text: PriceFieldFilter.binding(get: { filterMinPrice }, set: { filterMinPrice = $0 }), keyboardType: .decimalPad, bordered: true)
                        .onChange(of: filterMinPrice) { _, newValue in
                            let s = PriceFieldFilter.sanitizePriceInput(newValue)
                            if s != newValue { filterMinPrice = s }
                        }
                    SettingsTextField(placeholder: L10n.string("Max. Price"), text: PriceFieldFilter.binding(get: { filterMaxPrice }, set: { filterMaxPrice = $0 }), keyboardType: .decimalPad, bordered: true)
                        .onChange(of: filterMaxPrice) { _, newValue in
                            let s = PriceFieldFilter.sanitizePriceInput(newValue)
                            if s != newValue { filterMaxPrice = s }
                        }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.md)
                optionDivider
                VStack(spacing: Theme.Spacing.sm) {
                    BorderGlassButton(L10n.string("Clear")) {
                        filterCondition = nil
                        filterMinPrice = ""
                        filterMaxPrice = ""
                    }
                    PrimaryGlassButton(L10n.string("Apply")) {
                        activeListingsSheet = nil
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
    
    // MARK: - Shop search sheet (tap on Top brands search field)
    private var shopSearchSheetContent: some View {
        let query = shopSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filteredItems = query.isEmpty
            ? viewModel.userItems
            : viewModel.userItems.filter { item in
                item.title.lowercased().contains(query)
                || (item.brand?.lowercased().contains(query) ?? false)
                || (item.categoryName?.lowercased().contains(query) ?? false)
                || item.category.name.lowercased().contains(query)
                || item.description.lowercased().contains(query)
            }
        return OptionsSheet(
            title: L10n.string("Search"),
            onDismiss: {
                activeListingsSheet = nil
                shopSearchQuery = ""
            },
            detents: [.large],
            useCustomCornerRadius: false
        ) {
            VStack(spacing: 0) {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16))
                        .foregroundColor(Theme.Colors.secondaryText)
                    TextField(L10n.string("Search your shop"), text: $shopSearchQuery)
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.primaryText)
                        .autocorrectionDisabled()
                }
                .padding(Theme.Spacing.sm)
                .background(Theme.Colors.secondaryBackground)
                .cornerRadius(10)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.sm)
                .padding(.bottom, Theme.Spacing.xs)

                NavigationStack {
                    ScrollView {
                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: Theme.Spacing.sm),
                                GridItem(.flexible(), spacing: Theme.Spacing.sm)
                            ],
                            spacing: Theme.Spacing.md
                        ) {
                            ForEach(filteredItems) { item in
                                NavigationLink(value: AppRoute.itemDetail(item)) {
                                    WardrobeItemCard(item: item, onLikeTap: { viewModel.toggleLike(productId: item.productId ?? "") })
                                }
                                .buttonStyle(PlainTappableButtonStyle())
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, Theme.Spacing.md)
                    }
                    .navigationDestination(for: AppRoute.self) { route in
                        switch route {
                        case .itemDetail(let item):
                            ItemDetailView(item: item, authService: authService)
                        case .conversation(_, _), .menu:
                            EmptyView()
                        case .reviews(let username, let rating):
                            ReviewsView(username: username, rating: rating)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
    
    // MARK: - Items Grid Section
    private var itemsGridSection: some View {
        var items = viewModel.userItems
        
        if !selectedBrands.isEmpty {
            items = items.filter { item in
                guard let b = item.brand else { return false }
                return selectedBrands.contains(b)
            }
        }
        if let selectedCategory = selectedCategory {
            items = items.filter {
                ($0.categoryName ?? $0.category.name) == selectedCategory
            }
        }
        if let cond = filterCondition {
            items = items.filter { $0.condition.uppercased() == cond.uppercased() }
        }
        let minP = Double(filterMinPrice.replacingOccurrences(of: ",", with: "."))
        let maxP = Double(filterMaxPrice.replacingOccurrences(of: ",", with: "."))
        if let min = minP, min > 0 {
            items = items.filter { $0.price >= min }
        }
        if let max = maxP, max > 0 {
            items = items.filter { $0.price <= max }
        }
        switch profileSort {
        case .relevance:
            break
        case .newestFirst:
            items = items.sorted { $0.createdAt > $1.createdAt }
        case .priceAsc:
            items = items.sorted { $0.price < $1.price }
        case .priceDesc:
            items = items.sorted { $0.price > $1.price }
        }

        return Group {
            if items.isEmpty {
                profileListingsEmptyState(hasAnyListings: !viewModel.userItems.isEmpty)
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: Theme.Spacing.sm),
                        GridItem(.flexible(), spacing: Theme.Spacing.sm)
                    ],
                    spacing: Theme.Spacing.md
                ) {
                    ForEach(items) { item in
                        if isMultiBuySelectionMode {
                            Button(action: {
                                HapticManager.selection()
                                let id = item.id.uuidString
                                if selectedMultiBuyItemIds.contains(id) {
                                    selectedMultiBuyItemIds.remove(id)
                                } else {
                                    selectedMultiBuyItemIds.insert(id)
                                }
                            }) {
                                WardrobeItemCard(
                                    item: item,
                                    onLikeTap: { viewModel.toggleLike(productId: item.productId ?? "") },
                                    multiBuySelectionMode: true,
                                    isSelectedForMultiBuy: selectedMultiBuyItemIds.contains(item.id.uuidString),
                                    onMultiBuySelectTap: {
                                        HapticManager.selection()
                                        let id = item.id.uuidString
                                        if selectedMultiBuyItemIds.contains(id) {
                                            selectedMultiBuyItemIds.remove(id)
                                        } else {
                                            selectedMultiBuyItemIds.insert(id)
                                        }
                                    }
                                )
                            }
                            .buttonStyle(PlainTappableButtonStyle())
                        } else {
                            NavigationLink(value: AppRoute.itemDetail(item)) {
                                WardrobeItemCard(item: item, onLikeTap: { viewModel.toggleLike(productId: item.productId ?? "") })
                            }
                            .buttonStyle(PlainTappableButtonStyle())
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.md)
            }
        }
    }

    private func profileListingsEmptyState(hasAnyListings: Bool) -> some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer(minLength: 40)
            Image(systemName: "tshirt")
                .font(.system(size: 56))
                .foregroundColor(Theme.Colors.secondaryText.opacity(0.7))
            Text(hasAnyListings ? L10n.string("No items match your filters") : L10n.string("No listings yet"))
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.xl)
            if hasAnyListings {
                Text(L10n.string("Try adjusting your filters"))
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.secondaryText)
            }
            Spacer(minLength: 40)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xl)
    }
}

// MARK: - Supporting Views

struct StatColumn: View {
    let value: String
    let label: String
    /// When true, uses smaller fonts and minWidth for use next to profile avatar (avoids zoomed layout).
    var compact: Bool = false
    
    var body: some View {
        VStack(spacing: compact ? 2 : Theme.Spacing.xs) {
            Text(value)
                .font(compact ? .system(size: 20, weight: .semibold) : Theme.Typography.title2)
                .foregroundColor(Theme.Colors.primaryText)
            
            Text(label)
                .font(compact ? .system(size: 14, weight: .regular) : Theme.Typography.subheadline)
                .foregroundColor(Theme.Colors.secondaryText)
        }
        .frame(minWidth: compact ? 50 : 80)
    }
}

struct BrandButton: View {
    let brand: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        PillTag(
            title: brand,
            isSelected: isSelected,
            accentWhenUnselected: true,
            icon: "message.fill",
            action: action
        )
    }
}

struct WardrobeItemCard: View {
    let item: Item
    var onLikeTap: (() -> Void)? = nil
    /// When true, show a "Select" pill on the image (top right) for multi-buy selection.
    var multiBuySelectionMode: Bool = false
    var isSelectedForMultiBuy: Bool = false
    var onMultiBuySelectTap: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            // Image with like count overlay - fixed size container
            GeometryReader { geometry in
                let imageWidth = geometry.size.width
                let imageHeight = imageWidth * 1.3 // 1:1.3 width:height ratio
                
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
                        cornerRadius: Theme.Glass.cornerRadius,
                        placeholder: {
                            ImageShimmerPlaceholderFilled(cornerRadius: Theme.Glass.cornerRadius)
                                .frame(width: imageWidth, height: imageHeight)
                        },
                        failurePlaceholder: {
                            Image(systemName: "photo")
                                .font(.system(size: 40))
                                .foregroundColor(Theme.primaryColor.opacity(0.5))
                                .frame(width: imageWidth, height: imageHeight)
                        }
                    )
                    
                    // Like count overlay - shared component (56pt tap area, same visual)
                    LikeButtonView(isLiked: item.isLiked, likeCount: item.likeCount, action: { onLikeTap?() })
                    .padding(Theme.Spacing.xs)
                }
                .overlay(alignment: .topTrailing) {
                    if multiBuySelectionMode {
                        Button(action: { onMultiBuySelectTap?() }) {
                            Text(L10n.string(isSelectedForMultiBuy ? "Selected" : "Select"))
                                .font(Theme.Typography.caption)
                                .fontWeight(.medium)
                                .foregroundColor(Theme.primaryColor)
                                .padding(.horizontal, Theme.Spacing.sm)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(Theme.primaryColor.opacity(0.2))
                                )
                        }
                        .buttonStyle(HapticTapButtonStyle(haptic: { HapticManager.selection() }))
                        .padding(Theme.Spacing.xs)
                    }
                }
            }
            .aspectRatio(1.0/1.3, contentMode: .fit)
            
            // Product details section with consistent spacing
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
                        Text("\(discount)% Off")
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
        }
    }
}

#Preview {
    ProfileView(tabCoordinator: TabCoordinator())
        .preferredColorScheme(.dark)
}

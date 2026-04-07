import SwiftUI
import Shimmer

/// Other user's profile – same layout as ProfileView (read-only: no menu, no photo edit).
struct UserProfileView: View {
    let seller: User
    @EnvironmentObject var authService: AuthService
    @Environment(\.staffAdminSession) private var staffAdminSession
    @StateObject private var viewModel: UserProfileViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedBrand: String? = nil
    @State private var expandedCategories: Bool = false
    @State private var selectedCategory: String? = nil
    @State private var profileSort: ProfileSortOption = .newestFirst
    @State private var filterCondition: String? = nil
    @State private var filterMinPrice: String = ""
    @State private var filterMaxPrice: String = ""
    @State private var activeListingsSheet: ProfileListingsSheet?
    @State private var topBrandsScrollId: String? = nil
    @State private var showProfilePhotoFullScreen: Bool = false
    @State private var showFullBioSheet: Bool = false
    @State private var filterMultiBuyOnly: Bool = false
    @State private var isMultiBuySelectionMode: Bool = false
    @State private var selectedMultiBuyItemIds: Set<String> = []
    @State private var shopSearchQuery: String = ""
    @State private var showProfileModerationMenu = false

    init(seller: User, authService: AuthService?) {
        self.seller = seller
        _viewModel = StateObject(wrappedValue: UserProfileViewModel(seller: seller, authService: authService))
    }

    private var isPreluraSupportProfile: Bool {
        PreluraSupportBranding.isSupportRecipient(username: viewModel.user.username)
    }

    private var profileNavigationTitle: String {
        PreluraSupportBranding.displayTitle(forRecipientUsername: viewModel.user.username)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
        ScrollView {
                if viewModel.isLoading && viewModel.items.isEmpty && viewModel.errorMessage == nil {
                    ProfileShimmerView()
                } else {
                    VStack(spacing: 0) {
                        profileHeaderSection
                        if let bio = viewModel.user.bio, !bio.isEmpty {
                            bioSection(bio)
                        }
                        if let location = viewModel.user.location, !location.isEmpty {
                            profileLocationRow(location)
                        }
                        // Email verified badge: visible to others only when verified (hidden when not)
                        if viewModel.user.isVerified {
                            profileVerificationRow()
                        }
                        if viewModel.user.isVacationMode {
                            vacationModeSection(isLoggedInUser: false)
                        } else {
                            followRow
                            if !viewModel.items.isEmpty {
                                filtersSection
                            }
                            itemsGridSection
                        }
                    }
                }
                if let message = viewModel.errorMessage, !viewModel.items.isEmpty {
                    Text(message)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.secondaryText)
                        .padding()
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.background)
        .navigationTitle(profileNavigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHidden(false)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: Theme.Spacing.sm) {
                    Button(action: {
                        HapticManager.selection()
                        activeListingsSheet = .shopSearch
                    }) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(Theme.Colors.primaryText)
                            .frame(width: Theme.AppBar.buttonSize, height: Theme.AppBar.buttonSize)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainTappableButtonStyle())
                    Button(action: {
                        HapticManager.selection()
                        showProfileModerationMenu = true
                    }) {
                        Image(systemName: "flag")
                            .foregroundColor(Theme.Colors.primaryText)
                            .frame(width: Theme.AppBar.buttonSize, height: Theme.AppBar.buttonSize)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainTappableButtonStyle())
                }
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .refreshable { await viewModel.refreshAsync() }
        .onAppear {
            viewModel.load()
        }
        .sheet(isPresented: $showProfileModerationMenu) {
            NavigationStack {
                StaffProfileModerationMenuView(
                    username: viewModel.user.username,
                    userId: viewModel.user.userId,
                    staffGraphQL: staffAdminSession?.graphQL
                )
            }
        }
        .overlay {
            if showProfilePhotoFullScreen, let urlString = viewModel.user.avatarURL, !urlString.isEmpty, let url = URL(string: urlString) {
                profilePhotoExpandedOverlay(url: url)
            }
        }

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
                                        allItems: viewModel.items,
                                        sellerUserId: viewModel.user.userId
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
    private static let profilePhotoExpandedSize: CGFloat = 240

    /// Overlay: dimmed background (tap to dismiss) + expanded circular profile image with ring, subtle animation.
    private func profilePhotoExpandedOverlay(url: URL) -> some View {
        ProfilePhotoExpandedOverlay(
            url: url,
            expandedSize: Self.profilePhotoExpandedSize,
            ringBorderColor: Theme.Colors.profileRingBorder,
            onDismiss: {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showProfilePhotoFullScreen = false
                }
            }
        )
    }

    private var profileHeaderSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .center, spacing: 0) {
                Group {
                    if isPreluraSupportProfile {
                        PreluraSupportBranding.supportAvatar(size: Self.profilePhotoSize)
                            .overlay(
                                Circle()
                                    .stroke(Theme.Colors.profileRingBorder, lineWidth: 2.5)
                                    .frame(width: Self.profilePhotoSize, height: Self.profilePhotoSize)
                            )
                    } else if let urlString = viewModel.user.avatarURL, !urlString.isEmpty, let url = URL(string: urlString) {
                        Button(action: { showProfilePhotoFullScreen = true }) {
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
                        }
                        .buttonStyle(PlainTappableButtonStyle())
                        .overlay(
                            Circle()
                                .stroke(Theme.Colors.profileRingBorder, lineWidth: 2.5)
                                .frame(width: Self.profilePhotoSize, height: Self.profilePhotoSize)
                        )
                    } else {
                        profilePhotoPlaceholder
                            .overlay(
                                Circle()
                                    .stroke(Theme.Colors.profileRingBorder, lineWidth: 2.5)
                                    .frame(width: Self.profilePhotoSize, height: Self.profilePhotoSize)
                            )
                    }
                }

                Spacer(minLength: Theme.Spacing.xl)

                HStack(spacing: Theme.Spacing.md) {
                    StatColumn(value: "\(viewModel.items.count)", label: viewModel.items.count == 1 ? L10n.string("Listing") : L10n.string("Listings"), compact: true)
                    NavigationLink(destination: FollowingListView(username: viewModel.user.username)) {
                        StatColumn(value: "\(viewModel.user.followingsCount)", label: L10n.string("Following"), compact: true)
                    }
                    .buttonStyle(PlainTappableButtonStyle())
                    NavigationLink(destination: FollowersListView(username: viewModel.user.username)) {
                        StatColumn(value: "\(viewModel.displayedFollowersCount)", label: viewModel.displayedFollowersCount == 1 ? L10n.string("Follower") : L10n.string("Followers"), compact: true)
                    }
                    .buttonStyle(PlainTappableButtonStyle())
                }
                .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: Theme.Spacing.xl)
            }

            VStack(alignment: .leading, spacing: 2) {
                let hasSaleItems = viewModel.items.contains { $0.discountPercentage != nil }
                HStack(alignment: .center, spacing: 4) {
                    NavigationLink(value: AppRoute.reviews(username: viewModel.user.username, rating: viewModel.user.rating)) {
                        HStack(alignment: .center, spacing: 4) {
                            HStack(spacing: 2) {
                                ForEach(0..<5, id: \.self) { _ in
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 13))
                                        .foregroundColor(.yellow)
                                }
                            }
                            Text("(\(viewModel.user.reviewCount))")
                                .font(Theme.Typography.subheadline)
                                .foregroundColor(Theme.Colors.secondaryText)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: true)
                        }
                    }
                    .buttonStyle(HapticTapButtonStyle())
                    if hasSaleItems {
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.md)
    }

    /// Placeholder when no photo or load failed (matches profile placeholder: circle + initial).
    private var profilePhotoPlaceholder: some View {
        Circle()
            .fill(Theme.primaryColor)
            .frame(width: Self.profilePhotoSize, height: Self.profilePhotoSize)
            .overlay(
                Text(String(viewModel.user.username.prefix(1)).uppercased())
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.white)
            )
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

    /// Email verified badge (only shown for other users when verified).
    private func profileVerificationRow() -> some View {
        HStack(alignment: .center, spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundColor(Color.green)
            Text("Email verified")
                .font(Theme.Typography.subheadline)
                .foregroundColor(Theme.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.bottom, Theme.Spacing.sm)
    }

    private func bioSection(_ bio: String) -> some View {
        let limit = 100
        let truncated = bio.count > limit
        let displayText = truncated ? String(bio.prefix(limit)) + "..." : bio
        return Group {
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

    /// Placeholder when no photo or load failed (matches profile placeholder: circle + initial).
    private func vacationModeSection(isLoggedInUser: Bool) -> some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer(minLength: 40)
            Image(systemName: "umbrella.fill")
                .font(.system(size: 64))
                .foregroundColor(Theme.Colors.secondaryText)
            Text(isLoggedInUser ? L10n.string("Vacation mode turned on") : L10n.string("This member is on vacation"))
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.secondaryText)
                .multilineTextAlignment(.center)
            Spacer(minLength: 40)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xl)
    }

    /// Follow / Following row with switch, above Categories. Only meaningful when viewing another user (we have userId).
    private var followRow: some View {
        HStack {
            Text(viewModel.isFollowing ? L10n.string("Following") : L10n.string("Follow"))
                .font(Theme.Typography.subheadline)
                .foregroundColor(Theme.Colors.secondaryText)
            Spacer()
            if viewModel.user.userId != nil {
                if viewModel.isTogglingFollow {
                    ProgressView()
                        .scaleEffect(0.9)
                } else {
                    Toggle("", isOn: Binding(
                        get: { viewModel.isFollowing },
                        set: { _ in
                            Task {
                                await viewModel.toggleFollow(authToken: authService.authToken)
                            }
                        }
                    ))
                    .labelsHidden()
                    .tint(Theme.primaryColor)
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.md)
        .overlay(ContentDivider(), alignment: .bottom)
    }

    // MARK: - Filters Section (Categories, Multi-buy read-only, Top brands, Filter/Sort)
    private var filtersSection: some View {
        VStack(spacing: 0) {
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
                .buttonStyle(PlainTappableButtonStyle())

                if expandedCategories {
                    VStack(spacing: 0) {
                        ForEach(viewModel.categoriesWithCounts, id: \.name) { category in
                            Button(action: {
                                selectedCategory = selectedCategory == category.name ? nil : category.name
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
                            .buttonStyle(PlainTappableButtonStyle())
                            if category.name != viewModel.categoriesWithCounts.last?.name {
                                ContentDivider()
                                    .padding(.leading, Theme.Spacing.md)
                            }
                        }
                    }
                }
            }
            .overlay(ContentDivider(), alignment: .bottom)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: Theme.Spacing.sm) {
                    Text(L10n.string("Top brands"))
                        .font(Theme.Typography.subheadline)
                        .foregroundColor(Theme.Colors.secondaryText)
                    Spacer()
                    if viewModel.user.isMultibuyEnabled {
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
                                isSelected: selectedBrand == brand,
                                action: { selectedBrand = selectedBrand == brand ? nil : brand }
                            )
                            .id(brand)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                }
                .scrollPosition(id: $topBrandsScrollId, anchor: .leading)
                .id("user_profile_top_brands_pills")
                .padding(.vertical, Theme.Spacing.sm)
            }

            // Filter and Sort (grey pills, no shadow)
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
                userProfileSortSheet
            case .filter:
                userProfileFilterSheet
            case .shopSearch:
                userProfileShopSearchSheetContent
            }
        }
    }

    private var optionDivider: some View {
        Rectangle()
            .fill(Theme.Colors.glassBorder)
            .frame(height: 0.5)
            .padding(.horizontal, Theme.Spacing.md)
    }

    private var userProfileSortSheet: some View {
        OptionsSheet(title: L10n.string("Sort"), onDismiss: { activeListingsSheet = nil }, useCustomCornerRadius: false) {
            SortSheetContent(selectedSort: $profileSort, onApply: { activeListingsSheet = nil })
        }
    }

    private var userProfileFilterSheet: some View {
        OptionsSheet(title: L10n.string("Filter"), onDismiss: { activeListingsSheet = nil }, useCustomCornerRadius: false) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                Text(L10n.string("Condition"))
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.secondaryText)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.top, Theme.Spacing.xs)
                ForEach(profileConditionOptions, id: \.raw) { option in
                    Button(action: { filterCondition = filterCondition == option.raw ? nil : option.raw }) {
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
                    .buttonStyle(PlainTappableButtonStyle())
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

    // MARK: - Shop search sheet (opened from toolbar search button)
    private var userProfileShopSearchSheetContent: some View {
        let query = shopSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filteredItems = query.isEmpty
            ? viewModel.items
            : viewModel.items.filter { item in
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
                    TextField(L10n.string("Search shop"), text: $shopSearchQuery)
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
                                NavigationLink(destination: ItemDetailView(item: item, authService: authService)) {
                                    WardrobeItemCard(
                                        item: item,
                                        onLikeTap: { viewModel.toggleLike(productId: item.productId ?? "") }
                                    )
                                }
                                .buttonStyle(PlainTappableButtonStyle())
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, Theme.Spacing.md)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    // MARK: - Items Grid
    private var itemsGridSection: some View {
        var items = viewModel.items
        if let selectedBrand = selectedBrand { items = items.filter { $0.brand == selectedBrand } }
        if let selectedCategory = selectedCategory {
            items = items.filter { ($0.categoryName ?? $0.category.name) == selectedCategory }
        }
        if let cond = filterCondition { items = items.filter { $0.condition.uppercased() == cond.uppercased() } }
        let minP = Double(filterMinPrice.replacingOccurrences(of: ",", with: "."))
        let maxP = Double(filterMaxPrice.replacingOccurrences(of: ",", with: "."))
        if let min = minP, min > 0 { items = items.filter { $0.price >= min } }
        if let max = maxP, max > 0 { items = items.filter { $0.price <= max } }
        switch profileSort {
        case .relevance: break
        case .newestFirst: items = items.sorted { $0.createdAt > $1.createdAt }
        case .priceAsc: items = items.sorted { $0.price < $1.price }
        case .priceDesc: items = items.sorted { $0.price > $1.price }
        }
        return Group {
            if items.isEmpty {
                profileListingsEmptyState(hasAnyListings: !viewModel.items.isEmpty)
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
                            NavigationLink(destination: ItemDetailView(item: item, authService: authService)) {
                                WardrobeItemCard(
                                    item: item,
                                    onLikeTap: { viewModel.toggleLike(productId: item.productId ?? "") }
                                )
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

    /// Shown when the profile listings grid is empty: no listings yet, or no items match filters.
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

// MARK: - Expanded profile photo overlay (circular + ring, tap overlay to dismiss)
private struct ProfilePhotoExpandedOverlay: View {
    let url: URL
    let expandedSize: CGFloat
    let ringBorderColor: Color
    let onDismiss: () -> Void

    @State private var appeared: Bool = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .opacity(appeared ? 1 : 0)
                .ignoresSafeArea()
                .onTapGesture {
                    closeWithAnimation()
                }

            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: expandedSize, height: expandedSize)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(ringBorderColor, lineWidth: 3)
                                .frame(width: expandedSize, height: expandedSize)
                        )
                case .empty, .failure:
                    Circle()
                        .fill(Theme.Colors.secondaryBackground)
                        .frame(width: expandedSize, height: expandedSize)
                        .overlay(
                            Circle()
                                .stroke(ringBorderColor, lineWidth: 3)
                                .frame(width: expandedSize, height: expandedSize)
                        )
                @unknown default:
                    EmptyView()
                }
            }
            .frame(width: expandedSize, height: expandedSize)
            .contentShape(Circle())
            .onTapGesture { closeWithAnimation() }
            .scaleEffect(appeared ? 1 : 0.4)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.28)) {
                appeared = true
            }
        }
    }

    private func closeWithAnimation() {
        withAnimation(.easeIn(duration: 0.22)) {
            appeared = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            onDismiss()
        }
    }
}

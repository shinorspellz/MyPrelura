import SwiftUI
import Shimmer
import UIKit

struct ItemDetailView: View {
    let item: Item
    /// When false, only Buy now is shown (no Send an offer). Used for Try Cart.
    var offersAllowed: Bool = true
    /// When set (e.g. from Shop All), show "Add to bag" and add to this store instead of Buy now/Offer.
    var shopAllBag: ShopAllBagStore? = nil
    @StateObject private var viewModel: ItemDetailViewModel
    @State private var displayedItem: Item? = nil
    @State private var selectedImageIndex: Int = 0
    @State private var selectedTab: Int = 0
    @State private var showFullScreenImages: Bool = false
    @State private var showSendOfferSheet: Bool = false
    @State private var offerSheetSortOption: ProfileSortOption = .relevance
    @State private var showPaymentSheet: Bool = false
    @State private var showProductOptionsSheet: Bool = false
    @State private var showReportSheet: Bool = false
    @State private var showEditListingSheet: Bool = false
    @State private var showDeleteConfirm: Bool = false
    @State private var showMarkSoldConfirm: Bool = false
    @State private var showDeleteError: Bool = false
    @State private var showMarkSoldError: Bool = false
    @State private var deleteErrorMessage: String?
    @State private var markSoldErrorMessage: String?
    @State private var showGuestSignInPrompt: Bool = false
    /// When `shopAllBag` is provided (e.g. Shop All), user must enable this via the toolbar bag button before "Add to bag" appears.
    @State private var isTryCartToolbarActive: Bool = false
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authService: AuthService
    @Environment(\.optionalTabCoordinator) private var tabCoordinator

    /// Bag used for bottom actions only after the user toggles the cart control on.
    private var activeShopAllBag: ShopAllBagStore? {
        guard let bag = shopAllBag, isTryCartToolbarActive else { return nil }
        return bag
    }
    
    /// When `shopAllBag` is set and this is true (e.g. user enabled bag mode on Shop All / Favourites), bottom bar shows Add to bag without an extra tap on the detail bag icon.
    init(
        item: Item,
        authService: AuthService? = nil,
        offersAllowed: Bool = true,
        shopAllBag: ShopAllBagStore? = nil,
        activateShopBagActionsInitially: Bool = false
    ) {
        self.item = item
        self.offersAllowed = offersAllowed
        self.shopAllBag = shopAllBag
        _viewModel = StateObject(wrappedValue: ItemDetailViewModel(authService: authService))
        _isTryCartToolbarActive = State(initialValue: shopAllBag != nil && activateShopBagActionsInitially)
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 0) {
                    // Image Carousel (extends under status bar)
                    imageCarousel
                    
                    // Product Top Details
                    productTopDetails
                    
                    // Description Section
                    descriptionSection
                    
                    // Product Attributes
                    productAttributes
                    
                    // Tabs
                    tabsSection
                    
                    // Tab Content
                    tabContent
                }
                .padding(.bottom, isCurrentUser || effectiveItem.isSold ? 0 : 100)
            }
            .background(Theme.Colors.background)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if shopAllBag != nil {
                        Button {
                            isTryCartToolbarActive.toggle()
                        } label: {
                            Image(systemName: isTryCartToolbarActive ? "bag.fill" : "bag")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainTappableButtonStyle())
                        .accessibilityLabel("Toggle shopping bag mode")
                    }
                    Button(action: { showProductOptionsSheet = true }) {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainTappableButtonStyle())
                }
            }

            // Bottom Action Buttons
            if !isCurrentUser, !effectiveItem.isSold {
                bottomActionButtons
            }
        }
        .ignoresSafeArea(edges: .top)
        .onAppear {
            if displayedItem == nil { displayedItem = item }
            viewModel.syncLikeState(isLiked: effectiveItem.isLiked, likeCount: effectiveItem.likeCount)
        }
        .task(id: item.productId ?? item.id.uuidString) {
            if displayedItem == nil { displayedItem = item }
            // Run when detail view appears (and when product changes): auth, record view, load related content
            if authService.isAuthenticated {
                viewModel.updateAuthToken(authService.authToken)
            }
            if let productId = item.productId {
                viewModel.loadSimilarProducts(productId: productId, categoryId: nil)
                if authService.isAuthenticated {
                    viewModel.recordRecentlyViewed(productId: productId)
                }
                // Refetch to get latest status (e.g. sold, like) in case list had stale data
                if let updated = await viewModel.loadProduct(productId: productId) {
                    displayedItem = updated
                    viewModel.syncLikeState(isLiked: updated.isLiked, likeCount: updated.likeCount)
                }
            }
            viewModel.loadMemberItems(username: item.seller.username, excludeProductId: item.id, includeInListIfEmpty: isCurrentUser ? effectiveItem : nil)
            if isCurrentUser, item.seller.avatarURL == nil || item.seller.avatarURL?.isEmpty == true {
                await viewModel.loadCurrentUserAvatar()
            }
        }
        .onChange(of: authService.authToken) { oldToken, newToken in
            if authService.isAuthenticated {
                viewModel.updateAuthToken(newToken)
            }
        }
        .fullScreenCover(isPresented: $showFullScreenImages) {
            FullScreenImageViewer(
                imageURLs: effectiveItem.imageURLs,
                selectedIndex: $selectedImageIndex,
                onDismiss: { showFullScreenImages = false }
            )
        }
        .fullScreenCover(isPresented: $showGuestSignInPrompt) {
            GuestSignInPromptView()
        }
        .sheet(isPresented: $showSendOfferSheet) {
            OptionsSheet(title: L10n.string("Send an offer"), onDismiss: { showSendOfferSheet = false }, useCustomCornerRadius: false) {
                SendOfferSheetContent(item: effectiveItem, onDismiss: { showSendOfferSheet = false })
                    .environmentObject(authService)
            }
        }
        .navigationDestination(isPresented: $showPaymentSheet) {
            PaymentView(products: [effectiveItem], totalPrice: effectiveItem.price)
                .environmentObject(authService)
        }
        .sheet(isPresented: $showProductOptionsSheet) {
            productOptionsSheet
        }
        .sheet(isPresented: $showReportSheet) {
            NavigationStack {
                ReportUserView(
                    username: effectiveItem.seller.username,
                    isProduct: true,
                    productId: Int(effectiveItem.productId ?? "")
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L10n.string("Done")) { showReportSheet = false }
                            .foregroundColor(Theme.primaryColor)
                    }
                }
            }
            .environmentObject(authService)
        }
        .sheet(isPresented: $showEditListingSheet) {
            NavigationStack {
                SellView(
                    selectedTab: .constant(2),
                    editProductId: effectiveItem.productId.flatMap { Int($0) },
                    onEditComplete: {
                        showEditListingSheet = false
                        Task {
                            if let pid = displayedItem?.productId ?? item.productId,
                               let updated = await viewModel.loadProduct(productId: pid) {
                                await MainActor.run { displayedItem = updated }
                            }
                        }
                    }
                )
                .environmentObject(authService)
            }
        }
        .alert(L10n.string("Delete listing?"), isPresented: $showDeleteConfirm) {
            Button(L10n.string("Cancel"), role: .cancel) { showDeleteConfirm = false }
            Button(L10n.string("Delete listing"), role: .destructive) {
                guard let productId = item.productId else { return }
                Task {
                    do {
                        try await viewModel.deleteProduct(productId: productId)
                        await MainActor.run { dismiss() }
                    } catch {
                        await MainActor.run { deleteErrorMessage = error.localizedDescription; showDeleteError = true }
                    }
                }
            }
        } message: {
            Text("This cannot be undone.")
        }
        .alert(L10n.string("Mark as sold?"), isPresented: $showMarkSoldConfirm) {
            Button(L10n.string("Cancel"), role: .cancel) { showMarkSoldConfirm = false }
            Button(L10n.string("Mark as sold")) {
                guard let productId = item.productId else { return }
                Task {
                    do {
                        try await viewModel.markAsSold(productId: productId)
                        if let updated = await viewModel.loadProduct(productId: productId) {
                            await MainActor.run { displayedItem = updated }
                        }
                        await MainActor.run { showMarkSoldConfirm = false }
                    } catch {
                        await MainActor.run { markSoldErrorMessage = error.localizedDescription; showMarkSoldError = true }
                    }
                }
            }
        } message: {
            Text("This will mark the listing as sold.")
        }
        .alert(L10n.string("Error"), isPresented: $showDeleteError) {
            Button(L10n.string("OK")) { showDeleteError = false; deleteErrorMessage = nil }
        } message: {
            if let msg = deleteErrorMessage { Text(msg) }
        }
        .alert(L10n.string("Error"), isPresented: $showMarkSoldError) {
            Button(L10n.string("OK")) { showMarkSoldError = false; markSoldErrorMessage = nil }
        } message: {
            if let msg = markSoldErrorMessage { Text(msg) }
        }
        .toolbar(.hidden, for: .tabBar)
    }
    
    private var isCurrentUser: Bool {
        guard let currentUsername = authService.username else { return false }
        return currentUsername.lowercased() == item.seller.username.lowercased()
    }

    /// Displayed item (refetched after mark-as-sold); falls back to initial item.
    private var effectiveItem: Item {
        displayedItem ?? item
    }

    // MARK: - Product options sheet (3-dot menu; modal list design like ProfileMenuView)
    private var productOptionsSheet: some View {
        ProductOptionsSheet(
            item: effectiveItem,
            isCurrentUser: isCurrentUser,
            onDismiss: { showProductOptionsSheet = false },
            onShare: { shareProduct(); showProductOptionsSheet = false },
            onReport: { showProductOptionsSheet = false; showReportSheet = true },
            onEdit: { showProductOptionsSheet = false; showEditListingSheet = true },
            onCopyToNewListing: {
                showProductOptionsSheet = false
                tabCoordinator?.pendingSellPrefill = SellFormPrefill.from(item: effectiveItem)
                tabCoordinator?.selectTab(2)
            },
            onDelete: { showProductOptionsSheet = false; showDeleteConfirm = true },
            onMarkAsSold: { showProductOptionsSheet = false; showMarkSoldConfirm = true },
            onCopyLink: { copyProductLink(); showProductOptionsSheet = false }
        )
    }

    private func shareProduct() {
        let slug = item.publicWebItemSlug
        guard !slug.isEmpty else { return }
        let encoded = slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? slug
        guard let url = URL(string: "\(Constants.publicWebItemLinkBaseURL)/item/\(encoded)") else { return }
        let av = UIActivityViewController(activityItems: [effectiveItem.title, url], applicationActivities: nil)
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = windowScene.windows.first?.rootViewController else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        top.present(av, animated: true)
    }

    private func copyProductLink() {
        let slug = item.publicWebItemSlug
        guard !slug.isEmpty else { return }
        let encoded = slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? slug
        UIPasteboard.general.string = "\(Constants.publicWebItemLinkBaseURL)/item/\(encoded)"
    }

    /// Avatar URL for seller: use item's seller avatar if set, else for own product use current user's profile picture.
    private var effectiveSellerAvatarURL: String {
        if let url = effectiveItem.seller.avatarURL, !url.isEmpty { return url }
        if isCurrentUser, let url = viewModel.currentUserAvatarURL, !url.isEmpty { return url }
        return ""
    }

    /// Profile photo placeholder: circle with first letter of username (no shimmer).
    private var sellerAvatarPlaceholder: some View {
        Circle()
            .fill(Theme.primaryColor.opacity(0.3))
            .frame(width: 50, height: 50)
            .overlay(
                Text(String(effectiveItem.seller.username.prefix(1)).uppercased())
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(Theme.primaryColor)
            )
    }

    /// Seller avatar: placeholder when no photo; otherwise AsyncImage (shimmer only while loading URL, failure → placeholder).
    @ViewBuilder
    private var sellerAvatarView: some View {
        if effectiveSellerAvatarURL.isEmpty {
            sellerAvatarPlaceholder
        } else {
            AsyncImage(url: URL(string: effectiveSellerAvatarURL)) { phase in
                switch phase {
                case .empty:
                    Circle()
                        .fill(Theme.Colors.secondaryBackground)
                        .frame(width: 50, height: 50)
                        .shimmering()
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 50, height: 50)
                        .clipShape(Circle())
                case .failure:
                    sellerAvatarPlaceholder
                @unknown default:
                    EmptyView()
                }
            }
        }
    }

    // MARK: - Image Carousel (aspect 585:826; extends under status bar, no black bar)
    private static let imageAspectWidth: CGFloat = 585
    private static let imageAspectHeight: CGFloat = 826
    /// Max fraction of screen height the image area can use (60–65%).
    private static let maxImageHeightFraction: CGFloat = 0.65
    
    private var imageCarousel: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let screenH = UIScreen.main.bounds.height
            let aspectH = w * (Self.imageAspectHeight / Self.imageAspectWidth)
            let h = min(aspectH, screenH * Self.maxImageHeightFraction)
            
            ZStack(alignment: .top) {
                TabView(selection: $selectedImageIndex) {
                ForEach(0..<effectiveItem.imageURLs.count, id: \.self) { index in
                    AsyncImage(url: URL(string: effectiveItem.imageURLs[index])) { phase in
                        switch phase {
                        case .empty:
                            Rectangle()
                                .fill(Theme.Colors.secondaryBackground)
                                .shimmering()
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        case .failure:
                            Rectangle()
                                .fill(Theme.Colors.secondaryBackground)
                                .overlay(
                                    Image(systemName: "photo")
                                        .font(.system(size: 40))
                                        .foregroundColor(Theme.Colors.secondaryText)
                                )
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(width: w, height: h)
            .ignoresSafeArea(edges: .top)
            .onTapGesture { showFullScreenImages = true }
            
            // Heart Icon Overlay (bottom right) — on top so it always receives touch
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    LikeButtonView(
                        isLiked: viewModel.isLiked,
                        likeCount: viewModel.likeCount,
                        action: {
                            if authService.isGuestMode { showGuestSignInPrompt = true }
                            else if let productId = effectiveItem.productId, !productId.isEmpty { viewModel.toggleLike(productId: productId) }
                        }
                    )
                    .padding(.trailing, 15)
                    .padding(.bottom, 15)
                }
            }
            .allowsHitTesting(true)
            .zIndex(2)
            
            // Page Indicator (centered at bottom)
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    HStack(spacing: 5) {
                        ForEach(0..<effectiveItem.imageURLs.count, id: \.self) { index in
                            Circle()
                                .fill(selectedImageIndex == index ? Theme.primaryColor : Color.black)
                                .frame(width: selectedImageIndex == index ? 7 : 5,
                                       height: selectedImageIndex == index ? 7 : 5)
                        }
                    }
                    Spacer()
                }
                .padding(.bottom, 15)
            }
            }
            .frame(width: w, height: h)
        }
        .frame(height: min(
            UIScreen.main.bounds.width * Self.imageAspectHeight / Self.imageAspectWidth,
            UIScreen.main.bounds.height * Self.maxImageHeightFraction
        ))
    }
    
    /// Removes a leading "Size " so we never show "Size One Size" (backend or our label can already add it).
    private func sizeDisplayValue(_ size: String) -> String {
        let t = size.trimmingCharacters(in: .whitespaces)
        if t.count > 5, t[...t.index(t.startIndex, offsetBy: 4)].lowercased() == "size " {
            return String(t[t.index(t.startIndex, offsetBy: 5)...]).trimmingCharacters(in: .whitespaces)
        }
        return t
    }

    // MARK: - Product Top Details
    private var productTopDetails: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            // Title (smaller than before; Flutter uses bodyLarge-style)
            Text(effectiveItem.title)
                .font(Theme.Typography.headline)
                .foregroundColor(Theme.Colors.primaryText)
                .lineLimit(4)
            
            // Brand and Size Row (tappable → filter by brand / size; same behaviour as Flutter)
            HStack {
                if let brand = effectiveItem.brand {
                    NavigationLink(destination: FilteredProductsView(title: brand, filterType: .byBrand(brandName: brand), authService: authService)) {
                        Text(brand)
                            .font(Theme.Typography.body)
                            .foregroundColor(Theme.primaryColor)
                    }
                    .buttonStyle(HapticTapButtonStyle())
                }
                Spacer()
                if let size = effectiveItem.size {
                    let displaySize = sizeDisplayValue(size)
                    NavigationLink(destination: FilteredProductsView(title: displaySize, filterType: .bySize(sizeName: size), authService: authService)) {
                        Text(displaySize)
                            .font(Theme.Typography.body)
                            .foregroundColor(Theme.primaryColor)
                    }
                    .buttonStyle(HapticTapButtonStyle())
                }
            }
            
            // Condition and Price Row
            HStack {
                HStack(spacing: Theme.Spacing.sm) {
                    Text(effectiveItem.formattedCondition)
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.secondaryText)
                    if effectiveItem.isSold {
                        Text(L10n.string("Sold"))
                            .font(Theme.Typography.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Theme.primaryColor)
                            .cornerRadius(8)
                    }
                }
                Spacer()
                
                // Price with discount handling
                if let originalPrice = effectiveItem.originalPrice {
                    Text(effectiveItem.formattedOriginalPrice)
                        .font(Theme.Typography.headline)
                        .foregroundColor(Theme.Colors.secondaryText)
                        .strikethrough()
                    Text(effectiveItem.formattedPrice)
                        .font(Theme.Typography.headline)
                        .foregroundColor(Theme.Colors.primaryText)
                    if let discount = effectiveItem.discountPercentage {
                        Text("\(discount)%")
                            .font(Theme.Typography.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color(hex: "8d100f"))
                    }
                } else {
                    Text(effectiveItem.formattedPrice)
                        .font(Theme.Typography.headline)
                        .foregroundColor(Theme.Colors.primaryText)
                }
            }
            
            // Colour field: round swatch then text (e.g. 🔵 Blue), always shown just above seller
            HStack(spacing: Theme.Spacing.sm) {
                if effectiveItem.colors.isEmpty {
                    Text("—")
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.secondaryText)
                } else {
                    ForEach(effectiveItem.colors, id: \.self) { colorName in
                        HStack(spacing: 6) {
                            if let swatch = Theme.productColor(for: colorName) {
                                Circle()
                                    .fill(swatch)
                                    .frame(width: 18, height: 18)
                                    .overlay(Circle().stroke(Theme.Colors.secondaryText.opacity(0.3), lineWidth: 1))
                            }
                            Text(colorName)
                                .font(Theme.Typography.body)
                                .foregroundColor(Theme.Colors.primaryText)
                        }
                        .padding(.trailing, Theme.Spacing.sm)
                    }
                }
            }
            
            // Seller Info (avatar + username tappable → seller profile)
            HStack(spacing: Theme.Spacing.sm) {
                NavigationLink(destination: UserProfileView(seller: effectiveItem.seller, authService: authService)) {
                    HStack(spacing: Theme.Spacing.sm) {
                        sellerAvatarView
                        VStack(alignment: .leading, spacing: 4) {
                            Text(effectiveItem.seller.username)
                                .font(Theme.Typography.body)
                                .fontWeight(.bold)
                                .foregroundColor(Theme.Colors.primaryText)
                            HStack(spacing: 4) {
                                ForEach(0..<5, id: \.self) { _ in
                                    Image(systemName: "star")
                                        .font(.system(size: 12))
                                        .foregroundColor(Theme.Colors.secondaryText)
                                }
                                Text("(\(effectiveItem.seller.reviewCount))")
                                    .font(Theme.Typography.caption)
                                    .foregroundColor(Theme.Colors.secondaryText)
                            }
                        }
                    }
                }
                .buttonStyle(PlainTappableButtonStyle())

                Spacer()

                if !isCurrentUser {
                    NavigationLink(destination: ChatWithSellerView(seller: effectiveItem.seller, item: effectiveItem, authService: authService)) {
                        Image(systemName: "message.fill")
                            .font(.system(size: 20))
                            .foregroundColor(Theme.primaryColor)
                    }
                    .buttonStyle(PlainTappableButtonStyle())
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.top, Theme.Spacing.lg)
        .padding(.bottom, Theme.Spacing.lg / 2)
        .background(Theme.Colors.background)
    }
    
    // MARK: - Description Section (content only, no title or bullet)
    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                descriptionBody
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.top, Theme.Spacing.lg / 2)
                hashtagChipsIfNeeded
            }
            .padding(.bottom, Theme.Spacing.lg)
            .overlay(ContentDivider(), alignment: .bottom)
        }
        .background(Theme.Colors.background)
    }

    @ViewBuilder
    private var hashtagChipsIfNeeded: some View {
        let tags = HashtagTextSupport.uniqueHashtags(in: effectiveItem.description)
        if !tags.isEmpty {
            hashtagChipsRow(tags: tags)
                .padding(.horizontal, Theme.Spacing.md)
        }
    }
    
    private var descriptionBody: some View {
        let lines = effectiveItem.description.isEmpty ? ["—"] : effectiveItem.description.components(separatedBy: "\n").filter { !$0.isEmpty }
        return VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            ForEach(lines, id: \.self) { line in
                textWithHashtags(line.trimmingCharacters(in: .whitespaces))
                    .font(Theme.Typography.body)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Renders a string with hashtags (#word) in primary colour.
    private func textWithHashtags(_ string: String) -> Text {
        let segments = HashtagTextSupport.parseHashtagSegments(string)
        return segments.reduce(Text(verbatim: "")) { acc, seg in
            acc + Text(seg.text)
                .font(Theme.Typography.body)
                .foregroundColor(seg.isHashtag ? Theme.primaryColor : Theme.Colors.primaryText)
        }
    }

    @ViewBuilder
    private func hashtagChipsRow(tags: [String]) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 72), spacing: 8)],
            alignment: .leading,
            spacing: 8
        ) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(Theme.Typography.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(Theme.primaryColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.primaryColor.opacity(0.18))
                    .clipShape(Capsule())
            }
        }
    }
    
    // MARK: - Product Attributes
    private var productAttributes: some View {
        VStack(spacing: 0) {
            attributeRow(label: "Category", value: effectiveItem.categoryName ?? effectiveItem.category.name)
            if let brandName = effectiveItem.brand {
                NavigationLink(destination: FilteredProductsView(title: brandName, filterType: .byBrand(brandName: brandName), authService: authService)) {
                    attributeRow(label: "Material", value: brandName, valueColor: Theme.primaryColor)
                }
                .buttonStyle(PlainTappableButtonStyle())
            }
            if let size = effectiveItem.size {
                let displaySize = sizeDisplayValue(size)
                NavigationLink(destination: FilteredProductsView(title: displaySize, filterType: .bySize(sizeName: size), authService: authService)) {
                    attributeRow(label: "Size", value: displaySize, valueColor: Theme.primaryColor)
                }
                .buttonStyle(PlainTappableButtonStyle())
            }
            attributeRow(label: "Condition", value: effectiveItem.formattedCondition)
            attributeRow(label: "Views", value: "\(effectiveItem.views)")
            attributeRow(label: "Uploaded", value: formatDate(effectiveItem.createdAt))
            attributeRow(label: "Postage", value: "Postage: From £1.99", valueColor: Theme.primaryColor)
        }
        .background(Theme.Colors.background)
    }
    
    private func attributeRow(label: String, value: String, valueColor: Color? = nil) -> some View {
        HStack {
            Text(label)
                .font(Theme.Typography.headline)
                .foregroundColor(Theme.Colors.primaryText)
            Spacer()
            Text(value)
                .font(Theme.Typography.body)
                .foregroundColor(valueColor ?? Theme.Colors.primaryText)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.lg)
        .overlay(ContentDivider(), alignment: .bottom)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    // MARK: - Tabs Section
    private var tabsSection: some View {
        HStack(spacing: 0) {
            TabButton(title: L10n.string("Member's items"), isSelected: selectedTab == 0) {
                selectedTab = 0
            }
            TabButton(title: L10n.string("Similar items"), isSelected: selectedTab == 1) {
                selectedTab = 1
            }
        }
        .background(Theme.Colors.background)
    }
    
    // MARK: - Tab Content
    private var tabContent: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            if selectedTab == 0 {
                // Member's Items Tab
                membersItemsTab
            } else {
                // Similar Items Tab
                similarItemsTab
            }
        }
        .frame(minHeight: 300)
        .background(Theme.Colors.background)
    }
    
    private var membersItemsTab: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            // Shop Bundles Section
            HStack {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(L10n.string("Shop bundles"))
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.primaryText)
                    Text(L10n.string("Save on postage"))
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.secondaryText)
                }
                Spacer()
                PrimaryGlassButton("Create Bundle", action: {
                    // Create bundle
                })
                .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.md)
            
            // Product Grid
            if viewModel.isLoadingMember {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if viewModel.memberItems.isEmpty {
                VStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "bag")
                        .font(.system(size: 40))
                        .foregroundColor(Theme.Colors.secondaryText)
                    Text(L10n.string("No member items available yet"))
                        .font(Theme.Typography.body)
                        .fontWeight(.bold)
                        .foregroundColor(Theme.Colors.primaryText)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.xl)
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: Theme.Spacing.sm),
                        GridItem(.flexible(), spacing: Theme.Spacing.sm)
                    ],
                    spacing: Theme.Spacing.md
                ) {
                    ForEach(viewModel.memberItems) { memberItem in
                        NavigationLink(destination: ItemDetailView(item: memberItem, authService: authService)) {
                            HomeItemCard(item: memberItem)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                        .buttonStyle(PlainTappableButtonStyle())
                    }
                }
                .padding(.horizontal, Theme.Spacing.sm)
            }
        }
    }
    
    private var similarItemsTab: some View {
        Group {
            if viewModel.isLoadingSimilar {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if viewModel.similarItems.isEmpty {
                VStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "bag")
                        .font(.system(size: 40))
                        .foregroundColor(Theme.Colors.secondaryText)
                    Text(L10n.string("No similar items available yet"))
                        .font(Theme.Typography.body)
                        .fontWeight(.bold)
                        .foregroundColor(Theme.Colors.primaryText)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.xl)
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: Theme.Spacing.sm),
                        GridItem(.flexible(), spacing: Theme.Spacing.sm)
                    ],
                    spacing: Theme.Spacing.md
                ) {
                    ForEach(viewModel.similarItems) { similarItem in
                        NavigationLink(destination: ItemDetailView(item: similarItem, authService: authService)) {
                            HomeItemCard(item: similarItem)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                        .buttonStyle(PlainTappableButtonStyle())
                    }
                }
                .padding(.horizontal, Theme.Spacing.sm)
            }
        }
    }
    
    // MARK: - Bottom Action Buttons
    private var bottomActionButtons: some View {
        PrimaryButtonBar {
            if let bag = activeShopAllBag {
                let isInBag = bag.items.contains(where: { $0.id == effectiveItem.id })
                if isInBag {
                    BorderGlassButton(L10n.string("Remove"), icon: "minus.circle", action: {
                        bag.remove(effectiveItem)
                        dismiss()
                    })
                    .frame(maxWidth: .infinity)
                } else {
                    BorderGlassButton(L10n.string("Add to bag"), icon: "bag.badge.plus", action: {
                        bag.add(effectiveItem)
                        dismiss()
                    })
                    .frame(maxWidth: .infinity)
                }
            } else {
                HStack(spacing: Theme.Spacing.sm) {
                    if offersAllowed {
                        BorderGlassButton("Send an Offer", action: {
                            showSendOfferSheet = true
                        })
                        .frame(maxWidth: .infinity)
                    }
                    PrimaryGlassButton("Buy now", action: {
                        showPaymentSheet = true
                    })
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

// MARK: - Full Screen Image Viewer (slider)
struct FullScreenImageViewer: View {
    let imageURLs: [String]
    @Binding var selectedIndex: Int
    var onDismiss: () -> Void
    
    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()
            
            TabView(selection: $selectedIndex) {
                ForEach(0..<imageURLs.count, id: \.self) { index in
                    AsyncImage(url: URL(string: imageURLs[index])) { phase in
                        switch phase {
                        case .empty:
                            Rectangle()
                                .fill(Theme.Colors.secondaryBackground)
                                .shimmering()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        case .failure:
                            Image(systemName: "photo")
                                .font(.system(size: 48))
                                .foregroundColor(.white.opacity(0.5))
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
            
            // Close button — visible in both light and dark mode
            VStack {
                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(Theme.Colors.primaryText)
                            .symbolRenderingMode(.hierarchical)
                            .background(Circle().fill(.ultraThinMaterial))
                    }
                    .buttonStyle(HapticTapButtonStyle())
                    .padding(.trailing, Theme.Spacing.md)
                    .padding(.top, Theme.Spacing.lg)
                }
                Spacer()
                // Page indicator
                HStack(spacing: 6) {
                    ForEach(0..<imageURLs.count, id: \.self) { index in
                        Circle()
                            .fill(selectedIndex == index ? Theme.primaryColor : Color.white.opacity(0.4))
                            .frame(width: selectedIndex == index ? 8 : 6, height: selectedIndex == index ? 8 : 6)
                    }
                }
                .padding(.bottom, 40)
            }
        }
    }
}

// MARK: - Product options sheet (uses OptionsSheet component)
struct ProductOptionsSheet: View {
    let item: Item
    let isCurrentUser: Bool
    let onDismiss: () -> Void
    var onShare: () -> Void = {}
    var onReport: () -> Void = {}
    var onEdit: () -> Void = {}
    var onCopyToNewListing: () -> Void = {}
    var onDelete: () -> Void = {}
    var onMarkAsSold: () -> Void = {}
    var onCopyLink: () -> Void = {}

    private var optionDivider: some View {
        Rectangle()
            .fill(Theme.Colors.glassBorder)
            .frame(height: 0.5)
            .padding(.horizontal, Theme.Spacing.md)
    }

    private var sheetHeightDetent: CGFloat {
        let header: CGFloat = 108
        let row: CGFloat = 54
        let contentVerticalPadding: CGFloat = 32
        let rows = isCurrentUser ? 5 : 3
        let dividers: CGFloat = CGFloat(max(0, rows - 1)) * 0.5
        return header + contentVerticalPadding + CGFloat(rows) * row + dividers + 12
    }

    var body: some View {
        OptionsSheet(
            title: L10n.string("Options"),
            onDismiss: onDismiss,
            detents: [.height(sheetHeightDetent)],
            useCustomCornerRadius: false,
            fillsAvailableVerticalSpace: false
        ) {
            VStack(alignment: .leading, spacing: 0) {
                if isCurrentUser {
                    MenuItemRow(title: L10n.string("Edit listing"), icon: "square.and.pencil", action: { onEdit() }, iconAndSubtitleColor: Theme.Colors.secondaryText)
                    optionDivider
                    MenuItemRow(title: L10n.string("Copy to a new listing"), icon: "doc.on.doc", action: { onCopyToNewListing() }, iconAndSubtitleColor: Theme.Colors.secondaryText)
                    optionDivider
                    MenuItemRow(title: L10n.string("Share"), icon: "square.and.arrow.up", action: { onShare() }, iconAndSubtitleColor: Theme.Colors.secondaryText)
                    optionDivider
                    MenuItemRow(title: L10n.string("Mark as sold"), icon: "checkmark.circle", action: { onMarkAsSold() }, iconAndSubtitleColor: Theme.Colors.secondaryText)
                    optionDivider
                    MenuItemRow(title: L10n.string("Delete listing"), icon: "trash", action: { onDelete() }, isDestructive: true)
                } else {
                    MenuItemRow(title: L10n.string("Share"), icon: "square.and.arrow.up", action: { onShare() }, iconAndSubtitleColor: Theme.Colors.secondaryText)
                    optionDivider
                    MenuItemRow(title: L10n.string("Report listing"), icon: "flag", action: { onReport() }, iconAndSubtitleColor: Theme.Colors.secondaryText)
                    optionDivider
                    MenuItemRow(title: L10n.string("Copy link"), icon: "link", action: { onCopyLink() }, iconAndSubtitleColor: Theme.Colors.secondaryText)
                }
            }
            .padding(.vertical, Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct TabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Text(title)
                    .font(Theme.Typography.headline)
                    .foregroundColor(isSelected ? Theme.Colors.primaryText : Theme.Colors.secondaryText)
                    .fontWeight(isSelected ? .bold : .regular)
                    .padding(.vertical, Theme.Spacing.md)
                
                Rectangle()
                    .fill(isSelected ? Theme.primaryColor : Color.clear)
                    .frame(height: 2)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(HapticTapButtonStyle(haptic: { HapticManager.selection() }))
    }
}

#Preview {
    NavigationView {
        ItemDetailView(item: Item.sampleItems[0])
            .environmentObject(AuthService())
    }
    .preferredColorScheme(.dark)
}

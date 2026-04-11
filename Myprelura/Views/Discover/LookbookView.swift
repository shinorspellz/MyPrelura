//
//  LookbookView.swift
//  Prelura-swift
//
//  Instagram-style feed: full-width images, scrollable, poster, likes/comments (tappable), style filters.
//

import SwiftUI
import Shimmer
import UIKit

/// One lookbook post: image(s), poster, comments, styles for filtering. Remote URLs in `imageUrls` (carousel), or legacy document/asset.
/// Optional tags + productSnapshots come from local LookbookFeedStore (merged when post id / URL matches).
struct LookbookEntry: Identifiable {
    let id: UUID
    let imageNames: [String]
    /// When set, first image is loaded from Documents (legacy local).
    let documentImagePath: String?
    /// Remote slide URLs (single or multiple for in-post carousel). Empty when using document/assets only.
    let imageUrls: [String]
    /// First remote URL, if any.
    var imageUrl: String? { imageUrls.first }
    let posterUsername: String
    let caption: String?
    var commentsCount: Int
    let styles: [String]
    /// Tag positions (0–1) and productIds; from local store when available.
    let tags: [LookbookTagData]?
    /// productId -> snapshot for thumbnails; from local store when available.
    let productSnapshots: [String: LookbookProductSnapshot]?

    init(id: UUID? = nil, imageNames: [String], documentImagePath: String? = nil, imageUrl: String? = nil, posterUsername: String, caption: String? = nil, commentsCount: Int, styles: [String], tags: [LookbookTagData]? = nil, productSnapshots: [String: LookbookProductSnapshot]? = nil) {
        self.id = id ?? UUID()
        self.imageNames = imageNames
        self.documentImagePath = documentImagePath
        if let u = imageUrl, !u.isEmpty {
            self.imageUrls = [u]
        } else {
            self.imageUrls = []
        }
        self.posterUsername = posterUsername
        self.caption = caption
        self.commentsCount = commentsCount
        self.styles = styles
        self.tags = tags
        self.productSnapshots = productSnapshots
    }

    /// Entry from server (feed). Merges local multi-image URLs and tags when record matches.
    init(from serverPost: ServerLookbookPost, localRecord: LookbookUploadRecord? = nil) {
        self.id = UUID(uuidString: serverPost.id) ?? UUID()
        self.imageNames = []
        self.documentImagePath = nil
        let serverTrim = serverPost.imageUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        let fromServer: [String] = serverTrim.isEmpty ? [] : [serverTrim]
        if let local = localRecord {
            let localUrls = dedupeOrderedValidLookbookURLs(local.allImageUrls)
            if localUrls.count > 1 {
                self.imageUrls = localUrls
            } else {
                self.imageUrls = fromServer.isEmpty ? localUrls : fromServer
            }
        } else {
            self.imageUrls = fromServer
        }
        self.posterUsername = serverPost.username
        self.caption = serverPost.caption
        self.commentsCount = serverPost.commentsCount ?? 0
        self.styles = localRecord?.styles ?? []
        self.tags = localRecord?.tags
        self.productSnapshots = localRecord?.productSnapshots
    }
}

private let lookbookSpacing: CGFloat = 12
private let lookbookTopId = "lookbook_top"

/// Ordered de-duplication so accidental duplicate URLs do not spawn a multi-page `TabView` with collapsed height.
private func dedupeOrderedValidLookbookURLs(_ urls: [String]) -> [String] {
    var seen = Set<String>()
    var out: [String] = []
    for u in urls {
        let t = u.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, URL(string: t) != nil else { continue }
        if seen.insert(t).inserted { out.append(t) }
    }
    return out
}

// MARK: - Canonical media frames (1080×1350, 1080×1080, 1920×1080)

/// Width ÷ height for each canonical lookbook crop; closest bucket is chosen from the loaded image’s pixel aspect ratio.
private enum LookbookCanonicalAspect: CGFloat, CaseIterable {
    case portrait1080x1350 = 0.8 // 1080/1350
    case square1080 = 1
    case landscape1920x1080 = 1.7777777777777777 // 1920/1080

    static func bucket(for imageWidthOverHeight: CGFloat) -> Self {
        allCases.min(by: { abs($0.rawValue - imageWidthOverHeight) < abs($1.rawValue - imageWidthOverHeight) })!
    }
}

// MARK: - One feed row per post

private struct LookbookFeedRowModel: Identifiable {
    let id: String
    let entry: LookbookEntry
}

private func buildLookbookFeedRows(from list: [LookbookEntry]) -> [LookbookFeedRowModel] {
    list.enumerated().map { i, entry in
        LookbookFeedRowModel(id: "\(i)-\(entry.id.uuidString)", entry: entry)
    }
}

/// Style raw values for filter pills — same as StyleSelectionView (uploads). Subset used for display.
private let lookbookStylePillValues: [String] = [
    "CASUAL", "VINTAGE", "STREETWEAR", "MINIMALIST", "BOHO", "CHIC", "FORMAL_WEAR",
    "PARTY_DRESS", "LOUNGEWEAR", "ACTIVEWEAR", "Y2K", "DRESSES_GOWNS", "DENIM_JEANS",
    "SUMMER_STYLES", "WINTER_ESSENTIALS", "ATHLEISURE", "DATE_NIGHT", "VACATION_RESORT_WEAR"
]

private struct ProductIdNavigator: Identifiable, Hashable {
    let id: String
}

struct LookbookView: View {
    @EnvironmentObject private var authService: AuthService
    @State private var entries: [LookbookEntry] = []
    @State private var feedLoading = false
    @State private var feedError: String?
    @State private var scrollPosition: String? = lookbookTopId
    @State private var showSearchSheet: Bool = false
    @State private var searchText: String = ""
    @State private var commentsEntry: LookbookEntry?
    @State private var fullScreenEntry: LookbookEntry?
    @State private var selectedProductId: ProductIdNavigator?
    private let productService = ProductService()

    var body: some View {
        ZStack {
            GeometryReader { geometry in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        Color.clear.frame(height: 1).id(lookbookTopId)

                        LookbookTopBanner()

                        LookbookStyleThumbnailStrip()

                        LookbookHorizontalPortraitSection(
                            title: L10n.string("Explore communities"),
                            showSeeAll: true,
                            cards: LookbookFeedAssets.exploreCommunityCards,
                            visibleThumbCount: 2.8,
                            containerWidth: geometry.size.width
                        )

                        LookbookHorizontalPortraitSection(
                            title: L10n.string("Get inspired"),
                            showSeeAll: false,
                            cards: LookbookFeedAssets.getInspiredCards,
                            visibleThumbCount: 2,
                            containerWidth: geometry.size.width
                        )

                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            Text(L10n.string("Feed"))
                                .font(Theme.Typography.headline)
                                .foregroundColor(Theme.Colors.primaryText)
                                .padding(.horizontal, Theme.Spacing.md)
                                .padding(.top, Theme.Spacing.sm)
                        }

                        if feedLoading && entries.isEmpty {
                            LookbookShimmerView()
                        } else if entries.isEmpty {
                            emptyPlaceholder(minHeight: geometry.size.height - 120)
                        } else {
                            ForEach(buildLookbookFeedRows(from: entries)) { row in
                                lookbookFeedRow(model: row)
                            }
                        }
                    }
                    .padding(.bottom, Theme.Spacing.xl)
                }
            }
            .scrollPosition(id: $scrollPosition, anchor: .top)
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.background)

            if let entry = fullScreenEntry {
                LookbookTransparentFullscreenOverlay(entry: entry) {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                        fullScreenEntry = nil
                    }
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.94, anchor: .center)),
                    removal: .opacity
                ))
                .zIndex(2)
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: fullScreenEntry?.id)
        .navigationTitle(L10n.string("Lookbooks"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: Theme.Spacing.sm) {
                    NavigationLink(destination: LookbooksUploadView()) {
                        Image(systemName: "plus.circle")
                            .foregroundColor(Theme.Colors.primaryText)
                            .frame(width: Theme.AppBar.buttonSize, height: Theme.AppBar.buttonSize)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(HapticTapButtonStyle())
                    Button(action: { showSearchSheet = true }) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(Theme.Colors.primaryText)
                            .frame(width: Theme.AppBar.buttonSize, height: Theme.AppBar.buttonSize)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(HapticTapButtonStyle())
                }
            }
        }
        .sheet(item: $commentsEntry) { entry in
            LookbookCommentsSheet(entry: entry) { newCount in
                if let idx = entries.firstIndex(where: { $0.id == entry.id }) {
                    var updated = entries[idx]
                    updated.commentsCount = newCount
                    entries[idx] = updated
                }
            }
            .lookbookCommentsPresentationChrome()
        }
        .sheet(isPresented: $showSearchSheet) {
            LookbookSearchSheet(searchText: $searchText, entries: entries)
        }
        .navigationDestination(item: $selectedProductId) { nav in
            LookbookProductDetailLoader(productId: nav.id, productService: productService, authService: authService)
        }
        .onAppear { loadFeedFromServer() }
        .refreshable { await loadFeedFromServerAsync() }
    }

    private func loadFeedFromServer() {
        Task { await loadFeedFromServerAsync() }
    }

    private func loadFeedFromServerAsync() async {
        guard authService.isAuthenticated else {
            await MainActor.run {
                entries = []
                feedLoading = false
                feedError = nil
            }
            return
        }
        await MainActor.run { feedLoading = true; feedError = nil }
        let client = GraphQLClient()
        client.setAuthToken(authService.authToken)
        let service = LookbookService(client: client)
        service.setAuthToken(authService.authToken)
        do {
            let posts = try await service.fetchLookbooks()
            let localRecords = LookbookFeedStore.load()
            await MainActor.run {
                entries = posts.map { post in
                    LookbookEntry(from: post, localRecord: localRecords.first { r in r.id == post.id || r.imagePath == post.imageUrl })
                }
                feedLoading = false
                feedError = nil
            }
        } catch {
            await MainActor.run {
                feedLoading = false
                let isCancelled = (error as? CancellationError) != nil
                    || (error as? URLError)?.code == .cancelled
                    || error.localizedDescription.lowercased().contains("cancelled")
                feedError = isCancelled ? nil : error.localizedDescription
                // Keep existing feed on refresh failure so the list doesn’t go blank.
            }
        }
    }

    private func emptyPlaceholder(minHeight: CGFloat) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundColor(Theme.Colors.secondaryText)
            Text("No lookbooks yet")
                .font(Theme.Typography.title3)
                .foregroundColor(Theme.Colors.primaryText)
            Text("Upload from the menu to add your first look.")
                .font(Theme.Typography.subheadline)
                .foregroundColor(Theme.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.xl)
            if let err = feedError, !err.isEmpty {
                Text(err)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.xl)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minHeight: max(minHeight, 200))
    }

    private func lookbookFeedRow(model: LookbookFeedRowModel) -> some View {
        LookbookFeedRowView(
            entry: model.entry,
            onCommentsTap: { entry in commentsEntry = entry },
            onImageTap: { entry in
                withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                    fullScreenEntry = entry
                }
            },
            onProductTap: { productId in selectedProductId = ProductIdNavigator(id: productId) }
        )
        .id(model.id)
        .padding(.bottom, lookbookSpacing)
    }
}

// MARK: - Topic / style lookbook feed (pushed from thumbnails)

private struct LookbookTopicFeedView: View {
    @EnvironmentObject private var authService: AuthService
    let screenTitle: String
    let styleFilter: Set<String>

    @State private var entries: [LookbookEntry] = []
    @State private var feedLoading = false
    @State private var feedError: String?
    @State private var commentsEntry: LookbookEntry?
    @State private var fullScreenEntry: LookbookEntry?
    @State private var selectedProductId: ProductIdNavigator?
    private let productService = ProductService()

    private var filteredEntries: [LookbookEntry] {
        if styleFilter.isEmpty { return entries }
        return entries.filter { entry in
            !Set(entry.styles).isDisjoint(with: styleFilter)
        }
    }

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()

            ScrollView {
                LazyVStack(spacing: 0) {
                    if feedLoading && entries.isEmpty {
                        LookbookShimmerView()
                    } else if entries.isEmpty {
                        topicEmptyPlaceholder(allLoadedEmpty: true)
                    } else if filteredEntries.isEmpty {
                        topicEmptyPlaceholder(allLoadedEmpty: false)
                    } else {
                        ForEach(buildLookbookFeedRows(from: filteredEntries)) { row in
                            topicFeedRow(model: row)
                        }
                    }
                }
                .padding(.bottom, Theme.Spacing.xl)
            }
            .scrollContentBackground(.hidden)

            if let entry = fullScreenEntry {
                LookbookTransparentFullscreenOverlay(entry: entry) {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                        fullScreenEntry = nil
                    }
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.94, anchor: .center)),
                    removal: .opacity
                ))
                .zIndex(2)
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: fullScreenEntry?.id)
        .navigationTitle(screenTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar(.visible, for: .navigationBar)
        .sheet(item: $commentsEntry) { entry in
            LookbookCommentsSheet(entry: entry) { newCount in
                if let idx = entries.firstIndex(where: { $0.id == entry.id }) {
                    var updated = entries[idx]
                    updated.commentsCount = newCount
                    entries[idx] = updated
                }
            }
            .lookbookCommentsPresentationChrome()
        }
        .navigationDestination(item: $selectedProductId) { nav in
            LookbookProductDetailLoader(productId: nav.id, productService: productService, authService: authService)
        }
        .onAppear { loadFeedFromServer() }
        .refreshable { await loadFeedFromServerAsync() }
    }

    private func topicEmptyPlaceholder(allLoadedEmpty: Bool) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundColor(Theme.Colors.secondaryText)
            if allLoadedEmpty {
                Text("No lookbooks yet")
                    .font(Theme.Typography.title3)
                    .foregroundColor(Theme.Colors.primaryText)
                Text("Upload from the menu to add your first look.")
                    .font(Theme.Typography.subheadline)
                    .foregroundColor(Theme.Colors.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.xl)
            } else {
                Text("No lookbooks here yet")
                    .font(Theme.Typography.title3)
                    .foregroundColor(Theme.Colors.primaryText)
                Text("Nothing matches this topic right now. Check back soon.")
                    .font(Theme.Typography.subheadline)
                    .foregroundColor(Theme.Colors.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.xl)
            }
            if let err = feedError, !err.isEmpty {
                Text(err)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.xl)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Spacing.xl)
    }

    private func topicFeedRow(model: LookbookFeedRowModel) -> some View {
        LookbookFeedRowView(
            entry: model.entry,
            onCommentsTap: { entry in commentsEntry = entry },
            onImageTap: { entry in
                withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                    fullScreenEntry = entry
                }
            },
            onProductTap: { productId in selectedProductId = ProductIdNavigator(id: productId) }
        )
        .id(model.id)
        .padding(.bottom, lookbookSpacing)
    }

    private func loadFeedFromServer() {
        Task { await loadFeedFromServerAsync() }
    }

    private func loadFeedFromServerAsync() async {
        guard authService.isAuthenticated else {
            await MainActor.run {
                entries = []
                feedLoading = false
                feedError = nil
            }
            return
        }
        await MainActor.run { feedLoading = true; feedError = nil }
        let client = GraphQLClient()
        client.setAuthToken(authService.authToken)
        let service = LookbookService(client: client)
        service.setAuthToken(authService.authToken)
        do {
            let posts = try await service.fetchLookbooks()
            let localRecords = LookbookFeedStore.load()
            await MainActor.run {
                entries = posts.map { post in
                    LookbookEntry(from: post, localRecord: localRecords.first { r in r.id == post.id || r.imagePath == post.imageUrl })
                }
                feedLoading = false
                feedError = nil
            }
        } catch {
            await MainActor.run {
                feedLoading = false
                let isCancelled = (error as? CancellationError) != nil
                    || (error as? URLError)?.code == .cancelled
                    || error.localizedDescription.lowercased().contains("cancelled")
                feedError = isCancelled ? nil : error.localizedDescription
            }
        }
    }
}

// MARK: - Lookbooks header & discovery rows (bundled `LookbookFeed` assets)

private struct LookbookBundledPortraitTile: View {
    let resourceName: String
    let width: CGFloat
    var cornerRadius: CGFloat = 12

    private var tileHeight: CGFloat {
        width / LookbookCanonicalAspect.portrait1080x1350.rawValue
    }

    var body: some View {
        Group {
            if let ui = LookbookFeedAssets.uiImage(named: resourceName) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
            } else {
                Theme.Colors.secondaryBackground
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(Theme.Colors.secondaryText)
                    }
            }
        }
        .frame(width: width, height: tileHeight)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Discover-style portrait tile: image + dim overlay + title on top (same stacking as `DiscoverView` banners).
private struct LookbookHorizontalPortraitTile: View {
    let card: LookbookHorizontalCard
    let width: CGFloat

    private var tileHeight: CGFloat {
        width / LookbookCanonicalAspect.portrait1080x1350.rawValue
    }

    var body: some View {
        ZStack {
            Group {
                if let ui = LookbookFeedAssets.uiImage(named: card.resourceName) {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()
                } else {
                    Theme.Colors.secondaryBackground
                }
            }
            .frame(width: width, height: tileHeight)
            .clipped()

            Color.black.opacity(0.45)
                .frame(width: width, height: tileHeight)

            Text(card.overlayTitle)
                .font(Theme.Typography.title3)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.75)
                .lineLimit(2)
                .padding(Theme.Spacing.sm)
        }
        .frame(width: width, height: tileHeight)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct LookbookTopBanner: View {
    private let bannerHeight: CGFloat = 196

    var body: some View {
        Group {
            if let ui = LookbookFeedAssets.uiImage(named: LookbookFeedAssets.bannerResourceName) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [
                        Theme.primaryColor.opacity(0.55),
                        Theme.Colors.secondaryBackground
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .frame(height: bannerHeight)
        .frame(maxWidth: .infinity)
        .clipped()
        .clipShape(
            UnevenRoundedRectangle(
                cornerRadii: RectangleCornerRadii(
                    topLeading: 0,
                    bottomLeading: 22,
                    bottomTrailing: 22,
                    topTrailing: 0
                ),
                style: .continuous
            )
        )
        .padding(.bottom, Theme.Spacing.sm)
        .ignoresSafeArea(edges: .top)
    }
}

private struct LookbookStyleThumbnailStrip: View {
    private let thumbWidth: CGFloat = 76

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(L10n.string("Explore by style"))
                .font(Theme.Typography.headline)
                .foregroundColor(Theme.Colors.primaryText)
                .padding(.horizontal, Theme.Spacing.md)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(Array(lookbookStylePillValues.enumerated()), id: \.offset) { index, raw in
                        let resource = LookbookFeedAssets.styleThumbnailResource(styleIndex: index)
                        NavigationLink {
                            LookbookTopicFeedView(
                                screenTitle: StyleSelectionView.displayName(for: raw),
                                styleFilter: [raw]
                            )
                        } label: {
                            VStack(spacing: Theme.Spacing.sm) {
                                LookbookBundledPortraitTile(resourceName: resource, width: thumbWidth, cornerRadius: 10)
                                Text(StyleSelectionView.displayName(for: raw))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(Theme.Colors.secondaryText)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                    .minimumScaleFactor(0.85)
                                    .frame(width: thumbWidth)
                            }
                            .padding(Theme.Spacing.sm)
                            .background(Theme.Colors.secondaryBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Theme.Colors.glassBorder.opacity(0.4), lineWidth: 0.5)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.xs)
            }
        }
        .padding(.top, Theme.Spacing.sm)
        .background(Theme.Colors.background)
    }
}

private struct LookbookHorizontalPortraitSection: View {
    let title: String
    var showSeeAll: Bool = false
    var onSeeAll: (() -> Void)?
    let cards: [LookbookHorizontalCard]
    /// Visible thumbnails across the content width (e.g. 2.8 shows two full + a peek of the third).
    let visibleThumbCount: CGFloat
    let containerWidth: CGFloat

    private var contentWidth: CGFloat {
        containerWidth - Theme.Spacing.md * 2
    }

    private var thumbWidth: CGFloat {
        let gap = Theme.Spacing.sm
        if visibleThumbCount <= 2.01 {
            return (contentWidth - gap) / visibleThumbCount
        }
        let fullGaps = 2
        return (contentWidth - CGFloat(fullGaps) * gap) / visibleThumbCount
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(Theme.Typography.headline)
                    .foregroundColor(Theme.Colors.primaryText)
                Spacer(minLength: Theme.Spacing.sm)
                if showSeeAll {
                    Button {
                        onSeeAll?()
                    } label: {
                        Text(L10n.string("See all"))
                            .font(Theme.Typography.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(Theme.primaryColor)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(cards) { card in
                        NavigationLink {
                            LookbookTopicFeedView(screenTitle: card.overlayTitle, styleFilter: card.styleFilter)
                        } label: {
                            LookbookHorizontalPortraitTile(card: card, width: thumbWidth)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
            }
        }
        .padding(.bottom, Theme.Spacing.md)
    }
}

/// Full-bleed dimmed overlay so the feed stays visible; image scales in with a light spring.
private struct LookbookTransparentFullscreenOverlay: View {
    let entry: LookbookEntry
    var onDismiss: () -> Void

    @State private var index: Int = 0

    var body: some View {
        ZStack {
            Color.black.opacity(0.48)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }

            VStack(spacing: 0) {
                TabView(selection: $index) {
                    ForEach(Array(entry.imageUrls.enumerated()), id: \.offset) { idx, url in
                        LookbookFullscreenImage(
                            documentImagePath: idx == 0 ? entry.documentImagePath : nil,
                            imageName: entry.imageNames.first ?? "",
                            imageUrl: url
                        )
                        .padding(.horizontal, Theme.Spacing.md)
                        .tag(idx)
                    }
                    if entry.imageUrls.isEmpty {
                        LookbookFullscreenImage(
                            documentImagePath: entry.documentImagePath,
                            imageName: entry.imageNames.first ?? "",
                            imageUrl: nil
                        )
                        .padding(.horizontal, Theme.Spacing.md)
                        .tag(0)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: entry.imageUrls.count > 1 ? .automatic : .never))
                .frame(maxHeight: UIScreen.main.bounds.height * 0.78)
            }
            .allowsHitTesting(true)

            VStack {
                HStack {
                    Spacer()
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.35), radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                    .padding(.trailing, 14)
                }
                Spacer()
            }
        }
    }
}

// MARK: - Feed image: canonical aspect bucket, fill frame, optional double-tap, pinch zoom, bag for tagged products.
private struct LookbookFeedImage: View {
    let imageName: String
    let documentImagePath: String?
    let imageUrl: String?
    let tags: [LookbookTagData]?
    let productSnapshots: [String: LookbookProductSnapshot]?
    /// When false, tagged pins are hidden (e.g. secondary carousel slides).
    let showTagOverlay: Bool
    let onDoubleTapLike: (() -> Void)?
    let onTap: () -> Void
    let onProductTap: (String) -> Void

    @State private var scale: CGFloat = 1
    @State private var anchorScale: CGFloat = 1
    @State private var dragOffset: CGSize = .zero
    @State private var anchorDragOffset: CGSize = .zero
    @State private var showTaggedProducts = false
    @State private var bucket: LookbookCanonicalAspect = .square1080
    @State private var remoteImage: UIImage?
    @State private var remoteLoading = false

    private let minScale: CGFloat = 1
    private let maxScale: CGFloat = 4
    private let bagSize: CGFloat = 44
    private let thumbSize: CGFloat = 56

    private var hasTaggedProducts: Bool {
        guard showTagOverlay, let tags = tags, let snapshots = productSnapshots, !tags.isEmpty else { return false }
        return tags.contains { snapshots[$0.productId] != nil }
    }

    private var pinchZoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in scale = anchorScale * value }
            .onEnded { _ in
                scale = min(max(scale, minScale), maxScale)
                anchorScale = scale
                if scale <= 1.01 {
                    dragOffset = .zero
                    anchorDragOffset = .zero
                }
            }
    }

    /// Only attached when zoomed — a `DragGesture(minimumDistance: 0)` on the feed image otherwise steals scroll drags from the parent `ScrollView`.
    private var panWhenZoomedGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                dragOffset = CGSize(
                    width: anchorDragOffset.width + value.translation.width,
                    height: anchorDragOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                anchorDragOffset = dragOffset
            }
    }

    private var localUIImage: UIImage? {
        if let path = documentImagePath,
           let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appending(path: path),
           let data = try? Data(contentsOf: url),
           let ui = UIImage(data: data) { return ui }
        if !imageName.isEmpty, let ui = UIImage(named: imageName) { return ui }
        return nil
    }

    private var filledImageLayer: some View {
        Group {
            if let ui = localUIImage {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
            } else if let ui = remoteImage {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
            } else if imageUrl != nil, let _ = URL(string: imageUrl!) {
                if remoteLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.Colors.secondaryBackground.opacity(0.5))
                } else {
                    Image(systemName: "photo")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(Theme.Colors.secondaryText)
                        .padding(48)
                }
            } else if !imageName.isEmpty {
                Image(imageName)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .padding(48)
            }
        }
    }

    @ViewBuilder
    private func applyTapGestures(to base: some View) -> some View {
        if let dbl = onDoubleTapLike {
            base
                .onTapGesture(count: 2, perform: dbl)
                .onTapGesture(perform: onTap)
        } else {
            base.onTapGesture(perform: onTap)
        }
    }

    var body: some View {
        let framed = filledImageLayer
            .scaleEffect(scale)
            .offset(dragOffset)
            .frame(maxWidth: .infinity)
            .aspectRatio(bucket.rawValue, contentMode: .fit)
            .clipped()
            .overlay(alignment: .topTrailing) {
                if hasTaggedProducts {
                    Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showTaggedProducts.toggle() } }) {
                        Image(systemName: "bag.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.white)
                            .frame(width: bagSize, height: bagSize)
                            .background(Theme.primaryColor.opacity(0.9))
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(PlainTappableButtonStyle())
                    .padding(Theme.Spacing.sm)
                }
            }
            .overlay {
                if showTaggedProducts, showTagOverlay, let tags = tags, let snapshots = productSnapshots {
                    GeometryReader { g in
                        ForEach(tags.filter { snapshots[$0.productId] != nil }) { tag in
                            if let snapshot = snapshots[tag.productId] {
                                let x = g.size.width * tag.x
                                let y = g.size.height * tag.y
                                productThumbnail(snapshot: snapshot, onTap: { onProductTap(tag.productId) })
                                    .position(x: x, y: y)
                            }
                        }
                    }
                    .allowsHitTesting(true)
                }
            }
            .contentShape(Rectangle())
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        let core = applyTapGestures(to: framed)
            // `highPriorityGesture` steals drags from the parent ScrollView; pinch still works with `simultaneousGesture`.
            .simultaneousGesture(pinchZoomGesture)

        Group {
            if scale > 1.01 {
                core.simultaneousGesture(panWhenZoomedGesture)
            } else {
                core
            }
        }
        .onAppear(perform: syncBucketFromLocalIfPossible)
        .task(id: imageUrl) { await loadRemoteIfNeeded() }
    }

    private func syncBucketFromLocalIfPossible() {
        if let ui = localUIImage {
            bucket = LookbookCanonicalAspect.bucket(for: ui.size.width / max(ui.size.height, 1))
        }
    }

    private func loadRemoteIfNeeded() async {
        guard let urlString = imageUrl, let url = URL(string: urlString) else {
            await MainActor.run {
                remoteImage = nil
                remoteLoading = false
            }
            return
        }
        if localUIImage != nil { return }
        await MainActor.run { remoteLoading = true }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let ui = UIImage(data: data) else { throw URLError(.cannotDecodeContentData) }
            let b = LookbookCanonicalAspect.bucket(for: ui.size.width / max(ui.size.height, 1))
            await MainActor.run {
                remoteImage = ui
                bucket = b
                remoteLoading = false
            }
        } catch {
            await MainActor.run {
                remoteImage = nil
                remoteLoading = false
            }
        }
    }

    private func productThumbnail(snapshot: LookbookProductSnapshot, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                Group {
                    if let urlString = snapshot.imageUrl, let url = URL(string: urlString) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img): img.resizable().scaledToFill()
                            default: Color.gray.opacity(0.3)
                            }
                        }
                    } else {
                        Color.gray.opacity(0.3)
                    }
                }
                .frame(width: thumbSize, height: thumbSize)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                Text(snapshot.title)
                    .font(.caption2)
                    .foregroundColor(Theme.Colors.primaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: thumbSize + 16)
            }
            .padding(6)
            .background(Theme.Colors.background.opacity(0.95))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.Colors.glassBorder, lineWidth: 1))
            .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(PlainTappableButtonStyle())
    }
}

// MARK: - Loading shimmer for Lookbooks feed (pills + post card placeholders)
private struct LookbookShimmerView: View {
    var body: some View {
        VStack(spacing: 0) {
            stylePillsShimmer
            ForEach(0..<3, id: \.self) { _ in
                LookbookPostCardShimmer()
            }
        }
        .padding(.bottom, Theme.Spacing.xl)
        .shimmering()
    }

    private var stylePillsShimmer: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(0..<6, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Theme.Glass.tagCornerRadius)
                        .fill(Theme.Colors.secondaryBackground)
                        .frame(width: 72, height: 36)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
        }
        .background(Theme.Colors.background)
    }
}

private struct LookbookPostCardShimmer: View {
    private let mediaAspect = LookbookCanonicalAspect.portrait1080x1350.rawValue
    private let avatarSize: CGFloat = 36

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Circle()
                    .fill(Theme.Colors.secondaryBackground)
                    .frame(width: avatarSize, height: avatarSize)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Theme.Colors.secondaryBackground)
                    .frame(width: 100, height: 14)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.sm)

            RoundedRectangle(cornerRadius: 4)
                .fill(Theme.Colors.secondaryBackground)
                .frame(width: 180, height: 13)
                .padding(.horizontal, Theme.Spacing.md)

            RoundedRectangle(cornerRadius: 4)
                .fill(Theme.Colors.secondaryBackground)
                .frame(height: 14)
                .padding(.horizontal, Theme.Spacing.md)

            Color.clear
                .aspectRatio(mediaAspect, contentMode: .fit)
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Theme.Colors.secondaryBackground)
                }
                .frame(maxWidth: .infinity)
                .background(Theme.Colors.secondaryBackground.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, Theme.Spacing.md)

            HStack(spacing: Theme.Spacing.lg) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Theme.Colors.secondaryBackground)
                    .frame(width: 140, height: 16)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.xs)
            .padding(.bottom, Theme.Spacing.sm)

            Rectangle()
                .fill(Theme.Colors.glassBorder.opacity(0.45))
                .frame(height: 0.5)
                .padding(.leading, Theme.Spacing.md)
        }
        .padding(.bottom, lookbookSpacing)
    }
}

// MARK: - Feed row: one post; multiple images in a page TabView (carousel).
private struct LookbookFeedRowView: View {
    let entry: LookbookEntry
    let onCommentsTap: (LookbookEntry) -> Void
    let onImageTap: (LookbookEntry) -> Void
    let onProductTap: (String) -> Void

    @State private var carouselIndex: Int = 0

    private let iconSize: CGFloat = 18

    private func detailLine(for entry: LookbookEntry) -> String {
        if let first = entry.styles.first, !first.isEmpty {
            return "\(StyleSelectionView.displayName(for: first)) fit"
        }
        return "New fit"
    }

    /// Stable height for the media slot: `TabView` + async image load otherwise collapsed to a few points in `LazyVStack`.
    private var mediaBlock: some View {
        let urls = entry.imageUrls
        return Color.clear
            .aspectRatio(LookbookCanonicalAspect.portrait1080x1350.rawValue, contentMode: .fit)
            .overlay {
                mediaOverlayInner(urls: urls)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func mediaOverlayInner(urls: [String]) -> some View {
        if urls.count > 1 {
            TabView(selection: $carouselIndex) {
                ForEach(Array(urls.enumerated()), id: \.offset) { idx, url in
                    LookbookFeedImage(
                        imageName: entry.imageNames.first ?? "",
                        documentImagePath: idx == 0 ? entry.documentImagePath : nil,
                        imageUrl: url,
                        tags: entry.tags,
                        productSnapshots: entry.productSnapshots,
                        showTagOverlay: idx == 0,
                        onDoubleTapLike: nil,
                        onTap: { onImageTap(entry) },
                        onProductTap: onProductTap
                    )
                    .tag(idx)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
        } else {
            LookbookFeedImage(
                imageName: entry.imageNames.first ?? "",
                documentImagePath: entry.documentImagePath,
                imageUrl: urls.first,
                tags: entry.tags,
                productSnapshots: entry.productSnapshots,
                showTagOverlay: true,
                onDoubleTapLike: nil,
                onTap: { onImageTap(entry) },
                onProductTap: onProductTap
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Circle()
                    .fill(Theme.Colors.secondaryBackground)
                    .frame(width: 36, height: 36)
                    .overlay(
                        Text(String(entry.posterUsername.prefix(1)).uppercased())
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Theme.Colors.secondaryText)
                    )
                Text(entry.posterUsername)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.Colors.primaryText)
                Spacer()
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.sm)

            Text("📍 \(detailLine(for: entry))")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.Colors.primaryText)
                .padding(.horizontal, Theme.Spacing.md)

            if let caption = entry.caption, !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                HashtagColoredText(text: caption)
                    .padding(.horizontal, Theme.Spacing.md)
            }

            mediaBlock
                .frame(maxWidth: .infinity)
                .background(Theme.Colors.secondaryBackground.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, Theme.Spacing.md)

            HStack(spacing: Theme.Spacing.lg) {
                Button(action: { onCommentsTap(entry) }) {
                    HStack(spacing: 4) {
                        Image(systemName: "bubble.right")
                            .font(.system(size: iconSize))
                            .foregroundColor(Theme.Colors.primaryText)
                        Text("\(entry.commentsCount)")
                            .font(.system(size: 14))
                            .foregroundColor(Theme.Colors.primaryText)
                        Text("Comments")
                            .font(.system(size: 14))
                            .foregroundColor(Theme.Colors.secondaryText)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainTappableButtonStyle())
                Spacer()
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.xs)
            .padding(.bottom, Theme.Spacing.sm)

            Rectangle()
                .fill(Theme.Colors.glassBorder.opacity(0.45))
                .frame(height: 0.5)
                .padding(.leading, Theme.Spacing.md)
        }
        .onChange(of: entry.imageUrls.count) { _, newCount in
            if carouselIndex >= newCount { carouselIndex = max(0, newCount - 1) }
        }
    }
}

// MARK: - Loads product by id and presents ItemDetailView (for tagged product tap from lookbook feed)
private struct LookbookProductDetailLoader: View {
    let productId: String
    let productService: ProductService
    let authService: AuthService
    @State private var item: Item?
    @State private var failed = false

    var body: some View {
        Group {
            if let item = item {
                ItemDetailView(item: item, authService: authService)
            } else if failed {
                ContentUnavailableView("Product unavailable", systemImage: "bag", description: Text("This item may have been removed."))
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            guard let id = Int(productId) else { failed = true; return }
            do {
                let loaded = try await productService.getProduct(id: id)
                await MainActor.run { item = loaded; if loaded == nil { failed = true } }
            } catch {
                await MainActor.run { failed = true }
            }
        }
    }
}

// MARK: - Comments sheet presentation (match OptionsSheet / sort–filter modal surface)
private extension View {
    func lookbookCommentsPresentationChrome() -> some View {
        presentationDetents([.fraction(0.44), .medium, .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(22)
            .presentationBackground(Theme.Colors.modalSheetBackground)
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
    }
}

// MARK: - Comments sheet
struct LookbookCommentsSheet: View {
    let entry: LookbookEntry
    var onCountChanged: ((Int) -> Void)? = nil
    @EnvironmentObject private var authService: AuthService
    @Environment(\.dismiss) private var dismiss
    @State private var comments: [ServerLookbookComment] = []
    @State private var draft: String = ""
    @State private var loading = false
    @State private var sending = false

    private let sheetBg = Theme.Colors.modalSheetBackground

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if loading {
                    ProgressView().padding(.top, Theme.Spacing.lg)
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        ForEach(comments) { c in
                            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                                Circle()
                                    .fill(Theme.Colors.secondaryBackground)
                                    .frame(width: 32, height: 32)
                                    .overlay(Text(String(c.username.prefix(1)).uppercased())
                                        .font(.caption)
                                        .foregroundColor(Theme.Colors.secondaryText))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(c.username)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(Theme.Colors.primaryText)
                                    HashtagColoredText(text: c.text)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, Theme.Spacing.md)
                        }
                    }
                    .padding(.vertical, Theme.Spacing.md)
                }
                HStack(spacing: Theme.Spacing.sm) {
                    TextField("Add a comment", text: $draft, axis: .vertical)
                        .lineLimit(1...4)
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(Theme.Colors.secondaryBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                    Button(sending ? "..." : "Send") {
                        sendComment()
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
                    .foregroundColor(Theme.primaryColor)
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .background(sheetBg)
            }
            .background(sheetBg)
            .navigationTitle(L10n.string("Comments"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(sheetBg, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("Done")) { dismiss() }
                        .foregroundColor(Theme.primaryColor)
                }
            }
            .task { await loadComments() }
        }
    }

    private func loadComments() async {
        loading = true
        defer { loading = false }
        let client = GraphQLClient()
        client.setAuthToken(authService.authToken)
        let service = LookbookService(client: client)
        if let loaded = try? await service.fetchComments(postId: entry.id.uuidString) {
            comments = loaded
            onCountChanged?(loaded.count)
        }
    }

    private func sendComment() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        sending = true
        let client = GraphQLClient()
        client.setAuthToken(authService.authToken)
        let service = LookbookService(client: client)
        Task {
            do {
                let result = try await service.addComment(postId: entry.id.uuidString, text: text)
                await MainActor.run {
                    draft = ""
                    comments.append(result.comment)
                    onCountChanged?(result.commentsCount)
                    sending = false
                }
            } catch {
                await MainActor.run { sending = false }
            }
        }
    }
}

// MARK: - Thumbnail for search / list (server URL, document image, or asset)
private struct LookbookEntryThumbnail: View {
    let entry: LookbookEntry
    var body: some View {
        Group {
            if let urlString = entry.imageUrls.first, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    case .failure: Image(systemName: "photo").resizable().scaledToFit().foregroundStyle(Theme.Colors.secondaryText)
                    default: ProgressView()
                    }
                }
            } else if let path = entry.documentImagePath,
               let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appending(path: path),
               let data = try? Data(contentsOf: url),
               let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else if let first = entry.imageNames.first {
                Image(first)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
        }
    }
}

private struct HashtagColoredText: View {
    let text: String
    @EnvironmentObject private var appRouter: AppRouter

    private var attributed: AttributedString {
        var result = AttributedString(text)
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)

        if let regex = try? NSRegularExpression(pattern: "#\\w+") {
            for match in regex.matches(in: text, range: full) {
                guard let range = Range(match.range, in: result) else { continue }
                result[range].foregroundColor = Theme.primaryColor
                result[range].font = Theme.Typography.subheadline.weight(.semibold)
            }
        }

        if let regex = try? NSRegularExpression(pattern: "@[A-Za-z0-9_]+") {
            for match in regex.matches(in: text, range: full) {
                guard let range = Range(match.range, in: result) else { continue }
                let token = ns.substring(with: match.range)
                let username = String(token.dropFirst())
                if !username.isEmpty {
                    let enc = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
                    if let url = URL(string: "prelura://user/\(enc)") {
                        result[range].link = url
                    }
                }
                result[range].foregroundColor = Theme.primaryColor
                result[range].font = Theme.Typography.subheadline.weight(.semibold)
            }
        }

        return result
    }

    var body: some View {
        Text(attributed)
            .font(Theme.Typography.subheadline)
            .foregroundColor(Theme.Colors.primaryText)
            .lineLimit(nil)
            .environment(\.openURL, OpenURLAction { url in
                if url.scheme?.lowercased() == "prelura",
                   let host = url.host?.lowercased(),
                   host == "user" || host == "profile" {
                    appRouter.handle(url: url)
                    return .handled
                }
                return .systemAction
            })
    }
}

private struct LookbookFullscreenImage: View {
    let documentImagePath: String?
    let imageName: String
    let imageUrl: String?

    @State private var scale: CGFloat = 1
    @State private var anchorScale: CGFloat = 1
    @State private var dragOffset: CGSize = .zero
    @State private var anchorDragOffset: CGSize = .zero

    private var localUIImage: UIImage? {
        if let path = documentImagePath,
           let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appending(path: path),
           let data = try? Data(contentsOf: url),
           let ui = UIImage(data: data) { return ui }
        if !imageName.isEmpty, let ui = UIImage(named: imageName) { return ui }
        return nil
    }

    var body: some View {
        GeometryReader { geo in
            Group {
                if let ui = localUIImage {
                    Image(uiImage: ui).resizable().scaledToFit()
                } else if let s = imageUrl, let url = URL(string: s) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image): image.resizable().scaledToFit()
                        case .empty: ProgressView().tint(.white)
                        default:
                            Image(systemName: "photo")
                                .resizable()
                                .scaledToFit()
                                .foregroundColor(.white.opacity(0.7))
                                .padding(80)
                        }
                    }
                } else {
                    Image(systemName: "photo")
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(.white.opacity(0.7))
                        .padding(80)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .scaleEffect(scale)
            .offset(dragOffset)
            .contentShape(Rectangle())
            .highPriorityGesture(
                MagnificationGesture()
                    .onChanged { value in
                        scale = max(1, anchorScale * value)
                    }
                    .onEnded { _ in
                        scale = min(max(scale, 1), 6)
                        anchorScale = scale
                        if scale <= 1.01 {
                            dragOffset = .zero
                            anchorDragOffset = .zero
                        }
                    }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard scale > 1.01 else { return }
                        dragOffset = CGSize(
                            width: anchorDragOffset.width + value.translation.width,
                            height: anchorDragOffset.height + value.translation.height
                        )
                    }
                    .onEnded { _ in
                        guard scale > 1.01 else { return }
                        anchorDragOffset = dragOffset
                    }
            )
        }
    }
}

// MARK: - Search sheet (filter by search text in username/caption)
struct LookbookSearchSheet: View {
    @Binding var searchText: String
    let entries: [LookbookEntry]
    @Environment(\.dismiss) private var dismiss

    private var filteredBySearch: [LookbookEntry] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return entries }
        return entries.filter { $0.posterUsername.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(Theme.Colors.secondaryText)
                    TextField(L10n.string("Search lookbooks"), text: $searchText)
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.primaryText)
                        .autocorrectionDisabled()
                }
                .padding(Theme.Spacing.sm)
                .background(Theme.Colors.secondaryBackground)
                .cornerRadius(10)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)

                ScrollView {
                    LazyVStack(spacing: Theme.Spacing.sm) {
                        ForEach(filteredBySearch) { entry in
                            HStack(spacing: Theme.Spacing.sm) {
                                LookbookEntryThumbnail(entry: entry)
                                    .frame(width: 50, height: 50)
                                    .clipped()
                                    .cornerRadius(8)
                                Text(entry.posterUsername)
                                    .font(Theme.Typography.body)
                                    .foregroundColor(Theme.Colors.primaryText)
                                Spacer()
                            }
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, Theme.Spacing.xs)
                        }
                    }
                }
            }
            .background(Theme.Colors.background)
            .navigationTitle(L10n.string("Search"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("Done")) { dismiss() }
                        .foregroundColor(Theme.primaryColor)
                }
            }
        }
    }
}

extension LookbookEntry: Equatable {
    static func == (lhs: LookbookEntry, rhs: LookbookEntry) -> Bool { lhs.id == rhs.id }
}

extension LookbookEntry: Hashable {
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

#if DEBUG
struct LookbookView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            LookbookView()
                .environmentObject(AuthService())
        }
    }
}
#endif

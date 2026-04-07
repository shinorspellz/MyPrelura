import SwiftUI

private enum ListingStatusChip: String, CaseIterable {
    case active = "ACTIVE"
    case sold = "SOLD"

    var title: String {
        switch self {
        case .active: return "Active"
        case .sold: return "Sold"
        }
    }
}

private enum StaffListingSort: String, CaseIterable, Identifiable {
    case newest = "NEWEST"
    case priceAsc = "PRICE_ASC"
    case priceDesc = "PRICE_DESC"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newest: return "Newest first"
        case .priceAsc: return "Price: low to high"
        case .priceDesc: return "Price: high to low"
        }
    }
}

struct ListingsModerationView: View {
    var wrapsInNavigationStack: Bool = true

    @Environment(AdminSession.self) private var session
    @State private var rows: [ProductBrowseRow] = []
    @State private var hasMore = false
    @State private var page = 1
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var flagProduct: ProductBrowseRow?
    @State private var statusChip: ListingStatusChip = .active
    @State private var sortOption: StaffListingSort = .newest
    @State private var searchText = ""
    @State private var appliedMinPrice: Double?
    @State private var appliedMaxPrice: Double?
    @State private var showFilterSheet = false
    @State private var draftMinPrice = ""
    @State private var draftMaxPrice = ""
    private let pageSize = 25

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var listingsLoadSignature: String {
        [
            statusChip.rawValue,
            sortOption.rawValue,
            trimmedSearch,
            appliedMinPrice.map { String($0) } ?? "",
            appliedMaxPrice.map { String($0) } ?? "",
        ].joined(separator: "\u{1e}")
    }

    private var hasActiveListingFilters: Bool {
        appliedMinPrice != nil || appliedMaxPrice != nil
    }

    var body: some View {
        Group {
            if wrapsInNavigationStack {
                NavigationStack { listingsRoot }
            } else {
                listingsRoot
            }
        }
    }

    private var listingsRoot: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                ForEach(ListingStatusChip.allCases, id: \.self) { chip in
                    listingStatusChipButton(chip)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 10)

            List {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(Theme.Colors.error)
                }

                if isLoading && rows.isEmpty {
                    Section {
                        ForEach(0 ..< 6, id: \.self) { _ in
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Theme.Colors.glassBackground)
                                    .frame(width: 56, height: 56)
                                    .overlay { AdminShimmer() }
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                VStack(alignment: .leading, spacing: 8) {
                                    AdminShimmerCapsule(height: 16)
                                        .frame(width: 180)
                                    AdminShimmerCapsule(height: 12)
                                        .frame(width: 120)
                                }
                            }
                            .listRowBackground(Color.clear)
                        }
                    }
                }

                ForEach(rows) { p in
                    NavigationLink(value: p) {
                        HStack(alignment: .center, spacing: 12) {
                            listingThumbnail(p)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(p.name ?? "Listing \(p.id)")
                                    .font(Theme.Typography.headline)
                                    .foregroundStyle(Theme.Colors.primaryText)
                                Text(listingRowMetaLine(p))
                                    .font(Theme.Typography.footnote)
                                    .foregroundStyle(Theme.Colors.secondaryText)
                            }
                        }
                    }
                    .contextMenu {
                        Button("Flag listing…") {
                            flagProduct = p
                        }
                    }
                }

                if hasMore {
                    Button("Load more") {
                        Task { await loadMore() }
                    }
                    .disabled(isLoading)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .refreshable { await refresh() }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.Colors.background)
        .navigationTitle("Listings")
        .navigationBarTitleDisplayMode(.inline)
        .adminNavigationChrome()
        .searchable(text: $searchText, prompt: "Search title or brand")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Section("Sort") {
                        ForEach(StaffListingSort.allCases) { opt in
                            Button {
                                sortOption = opt
                            } label: {
                                HStack {
                                    Text(opt.title)
                                    if sortOption == opt {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .foregroundStyle(Theme.Colors.primaryText)
                }
                .accessibilityLabel("Sort listings")

                Button {
                    draftMinPrice = appliedMinPrice.map { priceDraftString($0) } ?? ""
                    draftMaxPrice = appliedMaxPrice.map { priceDraftString($0) } ?? ""
                    showFilterSheet = true
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .foregroundStyle(hasActiveListingFilters ? Theme.primaryColor : Theme.Colors.primaryText)
                }
                .accessibilityLabel("Filter listings")
            }
        }
        .sheet(isPresented: $showFilterSheet) {
            listingFilterSheet
        }
        .task(id: listingsLoadSignature) { await refresh() }
        .navigationDestination(for: ProductBrowseRow.self) { p in
            StaffListingDetailView(product: p) {
                flagProduct = p
            }
        }
        .sheet(item: $flagProduct) { p in
            ListingFlagSheet(product: p)
                .environment(session)
        }
    }

    @ViewBuilder
    private func listingThumbnail(_ p: ProductBrowseRow) -> some View {
        Group {
            if let u = p.primaryImageURL {
                AsyncImage(url: u) { phase in
                    switch phase {
                    case .empty:
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Theme.Colors.glassBackground)
                            ProgressView()
                        }
                    case let .success(img):
                        img
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        thumbPlaceholder
                    @unknown default:
                        thumbPlaceholder
                    }
                }
            } else {
                thumbPlaceholder
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Theme.Colors.glassBorder, lineWidth: 1)
        )
    }

    private var thumbPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.Colors.glassBackground)
            Image(systemName: "photo")
                .foregroundStyle(Theme.Colors.secondaryText)
        }
    }

    private func priceText(_ p: Double?) -> String {
        guard let p else { return "—" }
        return String(format: "£%.2f", p)
    }

    private func listingRowMetaLine(_ p: ProductBrowseRow) -> String {
        let user = "@\(p.seller?.username ?? "—")"
        let st = p.status ?? ""
        let price = priceText(p.price)
        if let rel = Self.relativeListingAgeShort(iso: p.createdAt), !rel.isEmpty {
            return "\(user) · \(st) · \(price) · \(rel)"
        }
        return "\(user) · \(st) · \(price)"
    }

    /// Short relative age for list rows (e.g. "2 min", "5 hr") — matches shopper-style footers.
    private static func relativeListingAgeShort(iso: String?) -> String? {
        guard let iso, !iso.isEmpty else { return nil }
        let parsers: [ISO8601DateFormatter] = {
            let f1 = ISO8601DateFormatter()
            f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let f2 = ISO8601DateFormatter()
            f2.formatOptions = [.withInternetDateTime]
            return [f1, f2]
        }()
        guard let date = parsers.compactMap({ $0.date(from: iso) }).first else { return nil }
        let now = Date()
        if now.timeIntervalSince(date) < 60 { return "now" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        let s = f.localizedString(for: date, relativeTo: now)
        if s.lowercased().hasPrefix("in ") { return nil }
        return s
    }

    private func listingStatusChipButton(_ chip: ListingStatusChip) -> some View {
        let selected = chip == statusChip
        return Button {
            statusChip = chip
        } label: {
            Text(chip.title)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(selected ? Theme.primaryColor.opacity(0.35) : Theme.Colors.glassBackground)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(selected ? Theme.primaryColor : Theme.Colors.glassBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .controlSize(.small)
    }

    private func statusFilterParam() -> String? {
        switch statusChip {
        case .active: return nil
        case .sold: return "SOLD"
        }
    }

    private var listingFilterSheet: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Price uses the listing’s GBP price. Use the navigation search field for title or brand.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
                Section("Price (£)") {
                    TextField("Minimum", text: $draftMinPrice)
                        .keyboardType(.decimalPad)
                    TextField("Maximum", text: $draftMaxPrice)
                        .keyboardType(.decimalPad)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.modalSheetBackground)
            .navigationTitle("Filter listings")
            .navigationBarTitleDisplayMode(.inline)
            .adminNavigationChrome()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { showFilterSheet = false }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Apply") {
                        appliedMinPrice = parsePriceDraft(draftMinPrice)
                        appliedMaxPrice = parsePriceDraft(draftMaxPrice)
                        showFilterSheet = false
                    }
                    .fontWeight(.semibold)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button("Clear all filters") {
                    searchText = ""
                    draftMinPrice = ""
                    draftMaxPrice = ""
                    appliedMinPrice = nil
                    appliedMaxPrice = nil
                    showFilterSheet = false
                }
                .font(Theme.Typography.subheadline)
                .foregroundStyle(Theme.Colors.secondaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
        }
    }

    private func priceDraftString(_ value: Double) -> String {
        if value.rounded() == value {
            return String(format: "%.0f", value)
        }
        return String(value)
    }

    private func parsePriceDraft(_ raw: String) -> Double? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        let normalized = s.replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }

    private func refresh() async {
        page = 1
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let result = try await PreluraAdminAPI.allProductsPage(
                client: session.graphQL,
                page: 1,
                pageSize: pageSize,
                statusFilter: statusFilterParam(),
                sort: sortOption.rawValue,
                search: trimmedSearch.isEmpty ? nil : trimmedSearch,
                minPrice: appliedMinPrice,
                maxPrice: appliedMaxPrice
            )
            rows = result.rows
            hasMore = result.hasMore
            page = 2
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadMore() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await PreluraAdminAPI.allProductsPage(
                client: session.graphQL,
                page: page,
                pageSize: pageSize,
                statusFilter: statusFilterParam(),
                sort: sortOption.rawValue,
                search: trimmedSearch.isEmpty ? nil : trimmedSearch,
                minPrice: appliedMinPrice,
                maxPrice: appliedMaxPrice
            )
            rows.append(contentsOf: result.rows)
            hasMore = result.hasMore
            page += 1
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ListingFlagSheet: View {
    @Environment(AdminSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    let product: ProductBrowseRow

    @State private var notes = ""
    @State private var reason = "SPAM"
    @State private var flagType = "HIDDEN"
    @State private var message: String?
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(product.name ?? "Product \(product.id)")
                    Text("@\(product.seller?.username ?? "—")")
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
                Section("Reason") {
                    Picker("Reason", selection: $reason) {
                        Text("Spam").tag("SPAM")
                        Text("Inappropriate").tag("INAPPROPRIATE_CONTENT")
                        Text("Copyright").tag("COPYRIGHT_INFRINGEMENT")
                        Text("Community").tag("COMMUNITY_GUIDELINES")
                        Text("Other").tag("OTHER")
                    }
                    Picker("Action", selection: $flagType) {
                        Text("Hide").tag("HIDDEN")
                        Text("Remove").tag("REMOVED")
                        Text("Flag").tag("FLAGGED")
                    }
                }
                Section("Notes") {
                    TextField("Optional notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
                if let message {
                    Section {
                        Text(message)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.modalSheetBackground)
            .navigationTitle("Flag listing")
            .navigationBarTitleDisplayMode(.inline)
            .adminNavigationChrome()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
                        Task { await submit() }
                    }
                    .disabled(isWorking)
                }
            }
        }
    }

    private func submit() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let r = try await PreluraAdminAPI.flagProduct(
                client: session.graphQL,
                productId: String(product.id),
                reason: reason,
                flagType: flagType,
                notes: notes.isEmpty ? nil : notes
            )
            message = r.message ?? (r.success == true ? "Queued" : "Failed")
            if r.success == true {
                dismiss()
            }
        } catch {
            message = error.localizedDescription
        }
    }
}

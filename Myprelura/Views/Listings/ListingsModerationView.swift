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
    private let pageSize = 25

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
        List {
            Section {
                Text("Choose Active (live marketplace) or Sold for moderation. Tap a row for the public listing on prelura.uk. Sold URLs may not render if the site hides completed sales. Flag from the toolbar or row menu.")
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }

            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(ListingStatusChip.allCases, id: \.self) { chip in
                            listingStatusChipButton(chip)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .listRowBackground(Color.clear)
            }

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
                            Text("@\(p.seller?.username ?? "—") · \(p.status ?? "") · \(priceText(p.price))")
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
        .navigationTitle("Listings")
        .navigationBarTitleDisplayMode(.inline)
        .adminNavigationChrome()
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.background)
        .refreshable { await refresh() }
        .task { await refresh() }
        .onChange(of: statusChip) { _, _ in
            Task { await refresh() }
        }
        .navigationDestination(for: ProductBrowseRow.self) { p in
            ListingWebDetailView(product: p) {
                flagProduct = p
            }
        }
        .sheet(item: $flagProduct) { p in
            ListingFlagSheet(product: p)
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

    private func listingStatusChipButton(_ chip: ListingStatusChip) -> some View {
        let selected = chip == statusChip
        return Button {
            statusChip = chip
        } label: {
            Text(chip.title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(selected ? Theme.primaryColor.opacity(0.35) : Theme.Colors.glassBackground)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(selected ? Theme.primaryColor : Theme.Colors.glassBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func statusFilterParam() -> String? {
        switch statusChip {
        case .active: return nil
        case .sold: return "SOLD"
        }
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
                statusFilter: statusFilterParam()
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
                statusFilter: statusFilterParam()
            )
            rows.append(contentsOf: result.rows)
            hasMore = result.hasMore
            page += 1
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ListingWebDetailView: View {
    let product: ProductBrowseRow
    let onFlag: () -> Void

    var body: some View {
        Group {
            if let url = Constants.publicProductURL(productId: product.id, listingCode: product.listingCode) {
                AdminWebViewRepresentable(url: url)
                    .ignoresSafeArea(edges: .bottom)
                    .background(Theme.Colors.background)
                    .navigationTitle(product.name ?? "Listing")
                    .navigationBarTitleDisplayMode(.inline)
                    .adminNavigationChrome()
                    .toolbar {
                        ToolbarItemGroup(placement: .primaryAction) {
                            ShareLink(item: url) {
                                Image(systemName: "square.and.arrow.up")
                            }
                            Button("Flag") {
                                onFlag()
                            }
                        }
                    }
            } else {
                ContentUnavailableView("Invalid listing", systemImage: "bag", description: Text("Could not build a prelura.uk URL."))
                    .background(Theme.Colors.background)
            }
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

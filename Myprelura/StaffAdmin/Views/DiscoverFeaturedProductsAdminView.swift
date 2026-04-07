import SwiftUI

/// Staff: choose up to 20 products to feature at the front of Discover → “Recently viewed” on the shopper app.
struct DiscoverFeaturedProductsAdminView: View {
    var wrapsInNavigationStack: Bool = true

    @Environment(AdminSession.self) private var session

    @State private var featured: [ProductBrowseRow] = []
    @State private var searchText = ""
    @State private var searchResults: [ProductBrowseRow] = []
    @State private var isLoadingFeatured = false
    @State private var isSearching = false
    @State private var isSaving = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var flagProduct: ProductBrowseRow?

    private let maxFeatured = 20

    var body: some View {
        Group {
            if wrapsInNavigationStack {
                NavigationStack { root }
            } else {
                root
            }
        }
    }

    private var root: some View {
        List {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(Theme.Colors.error)
            }
            if let statusMessage, errorMessage == nil {
                Text(statusMessage).font(.caption).foregroundStyle(.secondary)
            }

            Section("Featured on Discover (max \(maxFeatured))") {
                if isLoadingFeatured && featured.isEmpty {
                    ProgressView()
                } else if featured.isEmpty {
                    Text("None yet. Search below and tap a listing to add.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(featured) { row in
                        NavigationLink(value: row) {
                            HStack(spacing: 12) {
                                listingThumbnail(row)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(row.name ?? "—")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Theme.Colors.primaryText)
                                    Text(metaLine(row))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .onMove(perform: move)
                    .onDelete(perform: delete)
                }
            }

            Section("Add from catalogue") {
                TextField("Search active listings…", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if isSearching { ProgressView() }
                ForEach(searchResults) { row in
                    let already = featured.contains(where: { $0.id == row.id })
                    Button {
                        add(row)
                    } label: {
                        HStack(spacing: 12) {
                            listingThumbnail(row)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.name ?? "—")
                                    .font(.subheadline.weight(.semibold))
                                Text(row.listingCode ?? "")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            if already {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(already || (!already && featured.count >= maxFeatured))
                }
            }
        }
        .navigationTitle("Discover featured")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task { await save() }
                }
                .disabled(isSaving)
            }
        }
        .onAppear {
            Task { await loadFeatured() }
        }
        .onChange(of: searchText) { _, new in
            searchTask?.cancel()
            let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
            searchTask = Task {
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard !Task.isCancelled else { return }
                await runSearch(query: trimmed)
            }
        }
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

    private func metaLine(_ p: ProductBrowseRow) -> String {
        let code = p.listingCode ?? "—"
        let price = priceText(p.price)
        return "\(code) · \(price)"
    }

    private func priceText(_ p: Double?) -> String {
        guard let p else { return "—" }
        return String(format: "£%.2f", p)
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

    private func loadFeatured() async {
        isLoadingFeatured = true
        errorMessage = nil
        defer { isLoadingFeatured = false }
        do {
            featured = try await PreluraAdminAPI.discoverFeaturedProductRows(client: session.graphQL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func runSearch(query: String) async {
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        isSearching = true
        defer { isSearching = false }
        do {
            let (rows, _) = try await PreluraAdminAPI.allProductsPage(
                client: session.graphQL,
                page: 1,
                pageSize: 25,
                search: query
            )
            searchResults = rows
        } catch {
            searchResults = []
        }
    }

    private func add(_ row: ProductBrowseRow) {
        guard featured.count < maxFeatured else { return }
        guard !featured.contains(where: { $0.id == row.id }) else { return }
        featured.append(row)
        statusMessage = nil
    }

    private func delete(at offsets: IndexSet) {
        featured.remove(atOffsets: offsets)
    }

    private func move(from source: IndexSet, to destination: Int) {
        featured.move(fromOffsets: source, toOffset: destination)
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        statusMessage = nil
        defer { isSaving = false }
        do {
            try await PreluraAdminAPI.setDiscoverFeaturedProducts(
                client: session.graphQL,
                productIds: featured.map(\.id)
            )
            statusMessage = "Saved. Shoppers will see these first under Discover → Recently viewed."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

import SwiftUI

private enum PeopleListFilter: String, CaseIterable, Identifiable {
    case all
    case staffOnly
    case superuserOnly
    case verifiedOnly
    case hasActiveListings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "Everyone"
        case .staffOnly: return "Staff only"
        case .superuserOnly: return "Superuser only"
        case .verifiedOnly: return "Verified email"
        case .hasActiveListings: return "Has active listings"
        }
    }
}

struct UserManagementView: View {
    var wrapsInNavigationStack: Bool = true

    @Environment(AdminSession.self) private var session
    @EnvironmentObject private var authService: AuthService
    @State private var searchText = ""
    @State private var rows: [UserAdminRow] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var page = 1
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var listFilter: PeopleListFilter = .all
    @State private var showFilterSheet = false
    private let pageSize = 30

    private var displayedRows: [UserAdminRow] {
        switch listFilter {
        case .all:
            return rows
        case .staffOnly:
            return rows.filter { $0.isStaff == true }
        case .superuserOnly:
            return rows.filter { $0.isSuperuser == true }
        case .verifiedOnly:
            return rows.filter { $0.isVerified == true }
        case .hasActiveListings:
            return rows.filter { ($0.activeListings ?? 0) > 0 }
        }
    }

    var body: some View {
        Group {
            if wrapsInNavigationStack {
                NavigationStack { userListRoot }
            } else {
                userListRoot
            }
        }
    }

    private var userListRoot: some View {
        listContent
            .navigationDestination(for: AppRoute.self) { route in
                switch route {
                case .itemDetail(let item):
                    ItemDetailView(item: item, authService: authService)
                case .conversation, .menu:
                    EmptyView()
                case let .reviews(username, rating):
                    ReviewsView(username: username, rating: rating)
                }
            }
    }

    private var listContent: some View {
        List {
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(Theme.Colors.error)
                    .font(Theme.Typography.footnote)
            }
            if isLoading && rows.isEmpty {
                Section {
                    ForEach(0 ..< 8, id: \.self) { _ in
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Theme.Colors.glassBackground)
                                .frame(width: 52, height: 52)
                                .overlay { AdminShimmer() }
                                .clipShape(Circle())
                            VStack(alignment: .leading, spacing: 8) {
                                AdminShimmerCapsule(height: 18)
                                    .frame(width: 160)
                                AdminShimmerCapsule(height: 12)
                                    .frame(width: 220)
                            }
                        }
                        .listRowBackground(Color.clear)
                    }
                }
            }
            if listFilter != .all, !rows.isEmpty, displayedRows.isEmpty {
                Section {
                    Text("No people match this filter in the loaded results. Load more or choose “Everyone”.")
                        .font(Theme.Typography.footnote)
                        .foregroundStyle(Theme.Colors.secondaryText)
                        .listRowBackground(Color.clear)
                }
            }
            ForEach(displayedRows) { u in
                NavigationLink {
                    UserDetailView(username: u.username ?? "", summary: u)
                } label: {
                    HStack(alignment: .center, spacing: 12) {
                        AdminAvatar(
                            urlString: u.profilePictureUrl ?? u.thumbnailUrl,
                            size: 52
                        )
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(u.displayName ?? u.username ?? "User \(u.id)")
                                    .font(Theme.Typography.headline)
                                if u.isSuperuser == true {
                                    Text("SUPER")
                                        .font(.caption2.weight(.bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.3))
                                        .clipShape(Capsule())
                                } else if u.isStaff == true {
                                    Text("STAFF")
                                        .font(.caption2.weight(.bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Theme.primaryColor.opacity(0.25))
                                        .clipShape(Capsule())
                                }
                            }
                            Text("@\(u.username ?? "—") · \(u.email ?? "no email")")
                                .font(Theme.Typography.footnote)
                                .foregroundStyle(Theme.Colors.secondaryText)
                            if let joined = u.dateJoined, !joined.isEmpty {
                                Text("Joined \(joined.prefix(10))")
                                    .font(Theme.Typography.caption)
                                    .foregroundStyle(Theme.Colors.tertiaryText)
                            }
                            HStack(spacing: 12) {
                                Label("\(u.activeListings ?? 0) active", systemImage: "bag")
                                Label(u.totalSales?.display ?? "£0", systemImage: "chart.line.uptrend.xyaxis")
                            }
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.tertiaryText)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            if !rows.isEmpty {
                Button("Load more") {
                    Task { await load(next: true) }
                }
                .disabled(isLoading)
            }
        }
        .navigationTitle("People")
        .navigationBarTitleDisplayMode(.inline)
        .adminNavigationChrome()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    HapticManager.selection()
                    showFilterSheet = true
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .foregroundStyle(listFilter == .all ? Theme.Colors.primaryText : Theme.primaryColor)
                }
                .accessibilityLabel("Filter people")
            }
        }
        .sheet(isPresented: $showFilterSheet) {
            NavigationStack {
                List {
                    Section {
                        Text("Applies to people already loaded. Use search and “Load more” to widen the list.")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.secondaryText)
                            .listRowBackground(Color.clear)
                    }
                    Section("Show") {
                        ForEach(PeopleListFilter.allCases) { option in
                            Button {
                                listFilter = option
                                showFilterSheet = false
                            } label: {
                                HStack {
                                    Text(option.title)
                                        .foregroundStyle(Theme.Colors.primaryText)
                                    Spacer()
                                    if listFilter == option {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Theme.primaryColor)
                                            .fontWeight(.semibold)
                                    }
                                }
                            }
                        }
                    }
                }
                .navigationTitle("Filter")
                .navigationBarTitleDisplayMode(.inline)
                .adminNavigationChrome()
                .scrollContentBackground(.hidden)
                .background(Theme.Colors.background)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { showFilterSheet = false }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search username or profile")
        .onChange(of: searchText) { _, _ in
            searchDebounceTask?.cancel()
            searchDebounceTask = Task {
                try? await Task.sleep(nanoseconds: 400_000_000)
                guard !Task.isCancelled else { return }
                await load(next: false)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.background)
        .refreshable { await load(next: false) }
        .task { await load(next: false) }
    }

    private func load(next: Bool) async {
        if !next {
            page = 1
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let searchParam = q.isEmpty ? nil : q
        do {
            let batch = try await PreluraAdminAPI.userAdminStats(
                client: session.graphQL,
                search: searchParam,
                page: page,
                pageSize: pageSize
            )
            if next {
                rows.append(contentsOf: batch)
                page += 1
            } else {
                rows = batch
                page = 2
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

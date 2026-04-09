import SwiftUI

// MARK: - Home

struct HomeNavigation: View {
    @EnvironmentObject var authService: AuthService
    @ObservedObject var tabCoordinator: TabCoordinator

    var body: some View {
        NavigationStack {
            HomeView(tabCoordinator: tabCoordinator)
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
    }
}

// MARK: - Discover

struct DiscoverNavigation: View {
    @EnvironmentObject var authService: AuthService
    @ObservedObject var tabCoordinator: TabCoordinator
    @ObservedObject var discoverViewModel: DiscoverViewModel

    var body: some View {
        NavigationStack {
            DiscoverView(tabCoordinator: tabCoordinator, viewModel: discoverViewModel)
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
    }
}

// MARK: - Sell

struct SellNavigation: View {
    @Binding var selectedTab: Int

    var body: some View {
        NavigationStack {
            SellView(selectedTab: $selectedTab)
        }
    }
}

// MARK: - Inbox

struct InboxNavigation: View {
    @ObservedObject var tabCoordinator: TabCoordinator
    @ObservedObject var inboxViewModel: InboxViewModel
    @State private var path: [AppRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            ChatListView(tabCoordinator: tabCoordinator, path: $path, inboxViewModel: inboxViewModel)
                .navigationDestination(for: AppRoute.self) { route in
                    switch route {
                    case .conversation(let conversation, let isArchived):
                        ChatDetailView(conversation: conversation, isOpenedFromArchive: isArchived)
                    case .itemDetail, .menu:
                        EmptyView()
                    case .reviews(let username, let rating):
                        ReviewsView(username: username, rating: rating)
                    }
                }
        }
    }
}

// MARK: - Profile

struct ProfileNavigation: View {
    @EnvironmentObject var authService: AuthService
    @ObservedObject var tabCoordinator: TabCoordinator

    var body: some View {
        NavigationStack {
            ProfileView(tabCoordinator: tabCoordinator)
                .navigationDestination(for: AppRoute.self) { route in
                    switch route {
                    case .itemDetail(let item):
                        ItemDetailView(item: item, authService: authService)
                    case .menu(let context):
                        MenuView(
                            listingCount: context.listingCount,
                            isMultiBuyEnabled: context.isMultiBuyEnabled,
                            isVacationMode: context.isVacationMode,
                            username: context.username
                        )
                    case .reviews(let username, let rating):
                        ReviewsView(username: username, rating: rating)
                    case .conversation:
                        EmptyView()
                    }
                }
        }
    }
}

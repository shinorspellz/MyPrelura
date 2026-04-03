import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            NavigationStack {
                ListingsModerationView(wrapsInNavigationStack: false)
            }
            .tabItem { Label("Listings", systemImage: "bag") }

            NavigationStack {
                UserManagementView(wrapsInNavigationStack: false)
            }
            .tabItem { Label("People", systemImage: "person.3") }

            NavigationStack {
                MessagesRootView(wrapsInNavigationStack: false)
            }
            .tabItem { Label("Messages", systemImage: "message") }

            NavigationStack {
                ReportsQueueView(wrapsInNavigationStack: false)
            }
            .tabItem { Label("Reports", systemImage: "exclamationmark.triangle") }

            NavigationStack {
                DashboardView(wrapsInNavigationStack: false)
            }
            .tabItem { Label("Home", systemImage: "house.fill") }
        }
        .tint(Theme.primaryColor)
        .adminTabBarChrome()
    }
}

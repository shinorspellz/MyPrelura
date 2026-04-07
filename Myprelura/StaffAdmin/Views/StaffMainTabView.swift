import SwiftUI

struct StaffMainTabView: View {
    var body: some View {
        TabView {
            NavigationStack {
                StaffDashboardView(wrapsInNavigationStack: false)
            }
            .tabItem { Label("Home", systemImage: "house.fill") }

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
        }
        .tint(Theme.primaryColor)
        .adminTabBarChrome()
    }
}

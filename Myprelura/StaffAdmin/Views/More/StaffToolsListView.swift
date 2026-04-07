import SwiftUI

/// Staff utilities list for pushing onto the home `NavigationStack` (full screen on iPad; avoids sheet popovers).
struct StaffToolsListView: View {
    var body: some View {
        List {
            Section("Operations") {
                NavigationLink {
                    ConsoleView()
                } label: {
                    Label("Console", systemImage: "slider.horizontal.3")
                }
                NavigationLink {
                    AnalyticsDetailView()
                } label: {
                    Label("Analytics", systemImage: "chart.xyaxis.line")
                }
                NavigationLink {
                    TransactionsView(wrapsInNavigationStack: false)
                } label: {
                    Label("Orders", systemImage: "sterlingsign.circle")
                }
                NavigationLink {
                    BannersAnnouncementsView()
                } label: {
                    Label("Home banners", systemImage: "photo.on.rectangle.angled")
                }
                NavigationLink {
                    DiscoverFeaturedProductsAdminView(wrapsInNavigationStack: false)
                } label: {
                    Label("Discover featured", systemImage: "star.fill")
                }
            }
        }
        .navigationTitle("Tools")
        .navigationBarTitleDisplayMode(.inline)
        .adminNavigationChrome()
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.background)
    }
}

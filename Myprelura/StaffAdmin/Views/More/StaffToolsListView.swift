import SwiftUI

/// Entries mirrored on the iPad sidebar under Tools and in this list from Home.
enum AdminToolsMenuItem: String, CaseIterable, Identifiable, Hashable {
    case adminDashboard
    case console
    case analytics
    case orders
    case homeBanners
    case discoverFeatured

    var id: String { rawValue }

    var title: String {
        switch self {
        case .adminDashboard: return L10n.string("Admin Dashboard")
        case .console: return "Console"
        case .analytics: return "Analytics"
        case .orders: return "Orders"
        case .homeBanners: return "Home banners"
        case .discoverFeatured: return "Discover featured"
        }
    }

    var systemImage: String {
        switch self {
        case .adminDashboard: return "rectangle.3.group.bubble.left"
        case .console: return "slider.horizontal.3"
        case .analytics: return "chart.xyaxis.line"
        case .orders: return "sterlingsign.circle"
        case .homeBanners: return "photo.on.rectangle.angled"
        case .discoverFeatured: return "star.fill"
        }
    }

    @ViewBuilder
    func destinationView() -> some View {
        switch self {
        case .adminDashboard:
            AdminDashboardView()
        case .console:
            ConsoleView()
        case .analytics:
            AnalyticsDetailView()
        case .orders:
            TransactionsView(wrapsInNavigationStack: false)
        case .homeBanners:
            BannersAnnouncementsView()
        case .discoverFeatured:
            DiscoverFeaturedProductsAdminView(wrapsInNavigationStack: false)
        }
    }
}

/// Staff utilities list for pushing onto the home `NavigationStack` (full screen on iPad; avoids sheet popovers).
struct StaffToolsListView: View {
    @EnvironmentObject private var authService: AuthService

    var body: some View {
        List {
            Section("Operations") {
                ForEach(AdminToolsMenuItem.allCases) { item in
                    NavigationLink {
                        item.destinationView()
                    } label: {
                        Label(item.title, systemImage: item.systemImage)
                    }
                }
            }
            Section("Roadmap") {
                NavigationLink {
                    StaffRoadmapView()
                } label: {
                    Label("Planned modules (phase 2+)", systemImage: "map")
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

import SwiftUI

enum AdminSidebarSection: String, CaseIterable, Identifiable, Hashable {
    case home
    case users
    case listings
    case reports
    case messages
    case messaging
    case payments
    case growth
    case notifications
    case ai
    case internalTools
    case shadowView

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .users: return "User management"
        case .listings: return "Listings"
        case .reports: return "Reports"
        case .messages: return "Messages"
        case .messaging: return "Messaging & offers"
        case .payments: return "Payments & disputes"
        case .growth: return "Growth & monetisation"
        case .notifications: return "Notifications"
        case .ai: return "AI control"
        case .internalTools: return "Internal tools"
        case .shadowView: return "Shadow marketplace"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house.fill"
        case .users: return "person.3"
        case .listings: return "bag"
        case .reports: return "exclamationmark.triangle"
        case .messages: return "message"
        case .messaging: return "bubble.left.and.bubble.right"
        case .payments: return "creditcard"
        case .growth: return "chart.line.uptrend.xyaxis"
        case .notifications: return "bell.badge"
        case .ai: return "cpu"
        case .internalTools: return "list.clipboard"
        case .shadowView: return "eye.circle"
        }
    }

    static var liveOps: [AdminSidebarSection] {
        [.listings, .users, .messages, .reports, .home]
    }

    static var roadmap: [AdminSidebarSection] {
        [.messaging, .payments, .growth, .notifications, .ai, .internalTools, .shadowView]
    }
}

struct AdminDesktopShell: View {
    @State private var selection: AdminSidebarSection = .listings
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List {
                Section("Live operations") {
                    ForEach(AdminSidebarSection.liveOps) { item in
                        sidebarRow(item)
                    }
                }
                Section("Roadmap (phase 2+)") {
                    ForEach(AdminSidebarSection.roadmap) { item in
                        sidebarRow(item)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Myprelura")
            .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 360)
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.navigationBarBackground)
        } detail: {
            NavigationStack {
                detailView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.Colors.background)
            }
        }
        .tint(Theme.primaryColor)
    }

    private func sidebarRow(_ item: AdminSidebarSection) -> some View {
        Button {
            HapticManager.selection()
            selection = item
        } label: {
            Label(item.title, systemImage: item.systemImage)
                .foregroundStyle(selection == item ? Theme.primaryColor : Theme.Colors.primaryText)
        }
        .listRowBackground(selection == item ? Theme.primaryColor.opacity(0.12) : Color.clear)
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .home:
            DashboardView(wrapsInNavigationStack: false)
        case .users:
            UserManagementView(wrapsInNavigationStack: false)
        case .listings:
            ListingsModerationView(wrapsInNavigationStack: false)
        case .reports:
            ReportsQueueView(wrapsInNavigationStack: false)
        case .messages:
            MessagesRootView(wrapsInNavigationStack: false)
        case .messaging:
            AdminPlaceholderView(
                title: "Messaging & offer monitoring",
                detail: "Read-only threads, offer debugger, and moderation alerts need dedicated GraphQL fields and staff policies. No backend changes were made in this pass.",
                systemImage: "bubble.left.and.bubble.right"
            )
        case .payments:
            AdminPlaceholderView(
                title: "Payments & transactions",
                detail: "Refunds UI, dispute queues, commission breakdowns, and stuck-transaction detection can extend `adminAllOrders` / payments queries when exposed for staff.",
                systemImage: "creditcard"
            )
        case .growth:
            AdminPlaceholderView(
                title: "Growth & monetisation",
                detail: "Boosted listings, A/B pricing, and seller analytics require productised admin APIs.",
                systemImage: "chart.line.uptrend.xyaxis"
            )
        case .notifications:
            AdminPlaceholderView(
                title: "Notifications & announcements",
                detail: "Segmented push and in-app campaigns are not exposed on GraphQL yet; banners are available under Tools today.",
                systemImage: "bell.badge"
            )
        case .ai:
            AdminPlaceholderView(
                title: "AI control panel",
                detail: "Auto-moderation toggles and model suggestions need a backend surface before this tab can ship.",
                systemImage: "cpu"
            )
        case .internalTools:
            AdminPlaceholderView(
                title: "Internal tools",
                detail: "Shift mode, audit logs, and Discord workflow hooks are planned once APIs exist.",
                systemImage: "list.clipboard"
            )
        case .shadowView:
            AdminPlaceholderView(
                title: "Shadow marketplace view",
                detail: "Impersonation / user simulation requires secure server-side support.",
                systemImage: "eye.circle"
            )
        }
    }
}

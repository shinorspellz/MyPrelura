import SwiftUI

enum AdminSidebarSection: String, CaseIterable, Identifiable, Hashable {
    case home
    case users
    case listings
    case reports
    case orderIssues
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
        case .orderIssues: return "Order issues"
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
        case .orderIssues: return "cart.fill.badge.minus"
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
        [.home, .listings, .users, .messages, .reports, .orderIssues]
    }

    /// Tool-style entries first (quick access on iPad sidebar); planned product modules follow.
    static var roadmap: [AdminSidebarSection] {
        [.internalTools, .shadowView, .messaging, .payments, .growth, .notifications, .ai]
    }
}

private enum AdminShellSidebarSelection: Hashable {
    case live(AdminSidebarSection)
    case tool(AdminToolsMenuItem)
}

struct AdminDesktopShell: View {
    @State private var selection: AdminShellSidebarSelection = .live(.home)
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List {
                Section("Live operations") {
                    ForEach(AdminSidebarSection.liveOps) { item in
                        sidebarRowLive(item)
                    }
                }
                Section("Tools") {
                    ForEach(AdminToolsMenuItem.allCases) { item in
                        sidebarRowTool(item)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("WEARHOUSE Pro")
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

    private func isSelectedLive(_ item: AdminSidebarSection) -> Bool {
        if case let .live(s) = selection { return s == item }
        return false
    }

    private func isSelectedTool(_ item: AdminToolsMenuItem) -> Bool {
        if case let .tool(t) = selection { return t == item }
        return false
    }

    private func sidebarRowLive(_ item: AdminSidebarSection) -> some View {
        let isOn = isSelectedLive(item)
        return Button {
            HapticManager.selection()
            selection = .live(item)
        } label: {
            Label(item.title, systemImage: item.systemImage)
                .foregroundStyle(isOn ? Theme.primaryColor : Theme.Colors.primaryText)
        }
        .listRowBackground(isOn ? Theme.primaryColor.opacity(0.12) : Color.clear)
    }

    private func sidebarRowTool(_ item: AdminToolsMenuItem) -> some View {
        let isOn = isSelectedTool(item)
        return Button {
            HapticManager.selection()
            selection = .tool(item)
        } label: {
            Label(item.title, systemImage: item.systemImage)
                .foregroundStyle(isOn ? Theme.primaryColor : Theme.Colors.primaryText)
        }
        .listRowBackground(isOn ? Theme.primaryColor.opacity(0.12) : Color.clear)
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case let .tool(tool):
            tool.destinationView()
        case let .live(section):
            liveSectionDetail(section)
        }
    }

    @ViewBuilder
    private func liveSectionDetail(_ section: AdminSidebarSection) -> some View {
        switch section {
        case .home:
            StaffDashboardView(wrapsInNavigationStack: false)
        case .users:
            UserManagementView(wrapsInNavigationStack: false)
        case .listings:
            ListingsModerationView(wrapsInNavigationStack: false)
        case .reports:
            ReportsQueueView(wrapsInNavigationStack: false)
        case .orderIssues:
            StaffOrderIssuesView(wrapsInNavigationStack: false)
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

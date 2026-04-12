import SwiftUI

/// **Roadmap (phase 2+)** destinations (Tools → Roadmap, and Settings on iPhone).
struct StaffRoadmapView: View {
    var body: some View {
        List {
            Section {
                Text("Planned modules (no dedicated backend in this pass). Open from Tools → Roadmap on iPad, or Admin settings on iPhone.")
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .listRowBackground(Color.clear)
            }
            ForEach(AdminSidebarSection.roadmap) { item in
                NavigationLink {
                    roadmapDetail(item)
                } label: {
                    Label(item.title, systemImage: item.systemImage)
                }
            }
        }
        .navigationTitle("Roadmap")
        .navigationBarTitleDisplayMode(.inline)
        .adminNavigationChrome()
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.background)
    }

    @ViewBuilder
    private func roadmapDetail(_ item: AdminSidebarSection) -> some View {
        switch item {
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
        default:
            AdminPlaceholderView(title: item.title, detail: "Open from iPad sidebar for this section.", systemImage: item.systemImage)
        }
    }
}

import SwiftUI

/// Dedicated analytics surface (same `analyticsOverview` as Home, expanded layout).
struct AnalyticsDetailView: View {
    @Environment(AdminSession.self) private var session
    @State private var analytics: AnalyticsOverviewDTO?
    @State private var errorMessage: String?
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                if let errorMessage {
                    Text(errorMessage)
                        .font(Theme.Typography.footnote)
                        .foregroundStyle(Theme.Colors.error)
                        .padding(.horizontal)
                }
                if let a = analytics {
                    metricBlock(title: "Audience", a: a)
                    metricBlock(title: "Listing traffic", a: a)
                    Text("Figures mirror the production `analyticsOverview` field. Add seller-level and conversion funnels when those admin fields ship.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.tertiaryText)
                        .padding(.horizontal)
                } else if !isLoading {
                    ContentUnavailableView("No data", systemImage: "chart.bar.xaxis")
                }
            }
            .padding(.vertical)
            .adminDesktopReadableWidth()
        }
        .background(Theme.Colors.background)
        .navigationTitle("Analytics")
        .navigationBarTitleDisplayMode(.inline)
        .adminNavigationChrome()
        .refreshable { await load() }
        .task { await load() }
    }

    private func metricBlock(title: String, a: AnalyticsOverviewDTO) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(Theme.Typography.title3)
                    .foregroundStyle(Theme.Colors.primaryText)
                Grid(horizontalSpacing: 16, verticalSpacing: 12) {
                    GridRow {
                        statCell("Total users", "\(a.totalUsers ?? 0)", delta(a.totalUsersPercentageChange))
                        statCell("New today", "\(a.totalNewUsersToday ?? 0)", delta(a.newUsersPercentageChange))
                    }
                    GridRow {
                        statCell("Listing views", "\(a.totalProductViews ?? 0)", delta(a.totalProductViewsPercentageChange))
                        statCell("Views today", "\(a.totalProductViewsToday ?? 0)", "Intraday")
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    private func statCell(_ title: String, _ value: String, _ foot: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.secondaryText)
            Text(value)
                .font(Theme.Typography.title2)
                .foregroundStyle(Theme.Colors.primaryText)
            Text(foot)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.tertiaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func delta(_ pct: Double?) -> String {
        guard let pct else { return "—" }
        let sign = pct >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", pct))% vs prior day"
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            analytics = try await PreluraAdminAPI.analyticsOverview(client: session.graphQL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

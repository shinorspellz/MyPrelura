import SwiftUI

private enum HomeNav: Hashable {
    case analytics
    case report(StaffAdminReportRow)
}

struct StaffDashboardView: View {
    /// When `false`, embed inside `AdminDesktopShell`’s shared `NavigationStack` (iPad / Mac).
    var wrapsInNavigationStack: Bool = true

    @Environment(AdminSession.self) private var session
    @State private var analytics: AnalyticsOverviewDTO?
    @State private var reports: [StaffAdminReportRow] = []
    @State private var loadError: String?
    @State private var isLoading = true
    @State private var showTools = false

    var body: some View {
        Group {
            if wrapsInNavigationStack {
                NavigationStack { dashboardRoot }
            } else {
                dashboardRoot
            }
        }
    }

    private var dashboardRoot: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                if let loadError {
                    Text(loadError)
                        .font(Theme.Typography.footnote)
                        .foregroundStyle(Theme.Colors.error)
                        .padding(.horizontal)
                }

                if isLoading && analytics == nil {
                    dashboardShimmerBlock
                        .padding(.horizontal)
                }

                if let a = analytics {
                    metricsGrid(a)
                    healthCard(a)
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Live activity")
                            .font(Theme.Typography.title3)
                            .foregroundStyle(Theme.Colors.primaryText)
                        Text("Latest combined account & listing reports.")
                            .font(Theme.Typography.footnote)
                            .foregroundStyle(Theme.Colors.secondaryText)
                    }
                }
                .padding(.horizontal)

                ForEach(reports.prefix(15)) { r in
                    activityRow(r)
                        .padding(.horizontal)
                }

                if reports.isEmpty && !isLoading {
                    Text("No recent reports, or your token cannot read the admin dashboard.")
                        .font(Theme.Typography.footnote)
                        .foregroundStyle(Theme.Colors.secondaryText)
                        .padding(.horizontal)
                }
            }
            .padding(.vertical)
            .adminDesktopReadableWidth()
        }
        .background(Theme.Colors.background)
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.inline)
        .adminNavigationChrome()
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showTools = true
                } label: {
                    Image(systemName: "wrench.and.screwdriver")
                }
                .accessibilityLabel("Tools")

                NavigationLink {
                    SettingsHubView()
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
            }
        }
        .sheet(isPresented: $showTools) {
            AdminToolsMenuSheet()
        }
        .refreshable { await load() }
        .task { await load() }
        .navigationDestination(for: HomeNav.self) { dest in
            switch dest {
            case .analytics:
                AnalyticsDetailView()
            case let .report(r):
                AdminReportDetailView(report: r)
            }
        }
    }

    private var dashboardShimmerBlock: some View {
        LazyVGrid(columns: metricColumns, spacing: Theme.Spacing.md) {
            ForEach(0 ..< 4, id: \.self) { _ in
                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        AdminShimmerCapsule(height: 12)
                            .frame(width: 80)
                        AdminShimmerCapsule(height: 28)
                            .frame(maxWidth: .infinity)
                        AdminShimmerCapsule(height: 14)
                            .frame(width: 140)
                    }
                }
            }
        }
    }

    private var metricColumns: [GridItem] {
        if AdminLayout.prefersDesktopNavigation {
            return [
                GridItem(.flexible(), spacing: Theme.Spacing.md),
                GridItem(.flexible(), spacing: Theme.Spacing.md),
                GridItem(.flexible(), spacing: Theme.Spacing.md),
                GridItem(.flexible(), spacing: Theme.Spacing.md),
            ]
        }
        return [
            GridItem(.flexible(), spacing: Theme.Spacing.md),
            GridItem(.flexible(), spacing: Theme.Spacing.md),
        ]
    }

    private func metricsGrid(_ a: AnalyticsOverviewDTO) -> some View {
        LazyVGrid(columns: metricColumns, spacing: Theme.Spacing.md) {
            metricTile(
                title: "Total users",
                value: "\(a.totalUsers ?? 0)",
                detail: todayDelta(a.totalUsersPercentageChange),
                systemImage: "person.3.fill",
                accent: Theme.MetricAccents.users
            )
            metricTile(
                title: "New today",
                value: "\(a.totalNewUsersToday ?? 0)",
                detail: todayDelta(a.newUsersPercentageChange),
                systemImage: "sparkles",
                accent: Theme.MetricAccents.newToday
            )
            metricTile(
                title: "Listing views",
                value: "\(a.totalProductViews ?? 0)",
                detail: todayDelta(a.totalProductViewsPercentageChange),
                systemImage: "eye.fill",
                accent: Theme.MetricAccents.listingViews
            )
            metricTile(
                title: "Views today",
                value: "\(a.totalProductViewsToday ?? 0)",
                detail: "Intraday traffic",
                systemImage: "chart.line.uptrend.xyaxis",
                accent: Theme.MetricAccents.viewsToday
            )
        }
        .padding(.horizontal)
    }

    private func metricTile(title: String, value: String, detail: String, systemImage: String, accent: Color) -> some View {
        NavigationLink(value: HomeNav.analytics) {
            GlassCard {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: systemImage)
                        .font(.title2)
                        .foregroundStyle(accent)
                        .frame(width: 36, height: 36)
                        .background(accent.opacity(0.22))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title)
                            .font(Theme.Typography.footnote)
                            .foregroundStyle(Theme.Colors.secondaryText)
                        Text(value)
                            .font(Theme.Typography.title2)
                            .foregroundStyle(Theme.Colors.primaryText)
                        Text(detail)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.tertiaryText)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func todayDelta(_ pct: Double?) -> String {
        guard let pct else { return "—" }
        let sign = pct >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", pct))% vs prior day"
    }

    private func healthCard(_ a: AnalyticsOverviewDTO) -> some View {
        let score = MarketplaceHealthScore.compute(from: a)
        return NavigationLink(value: HomeNav.analytics) {
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "heart.text.square.fill")
                            .foregroundStyle(Theme.MetricAccents.health)
                        Text("Marketplace health score")
                            .font(Theme.Typography.title3)
                            .foregroundStyle(Theme.Colors.primaryText)
                        Spacer()
                        Text("\(score.value)")
                            .font(Theme.Typography.largeTitle)
                            .foregroundStyle(Theme.MetricAccents.health)
                    }
                    Text(score.subtitle)
                        .font(Theme.Typography.footnote)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }

    private func activityRow(_ r: StaffAdminReportRow) -> some View {
        NavigationLink(value: HomeNav.report(r)) {
            GlassCard {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(r.reportType ?? "REPORT")
                            .font(Theme.Typography.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Theme.primaryColor.opacity(0.2))
                            .clipShape(Capsule())
                        Spacer()
                        Text(r.status ?? "")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.secondaryText)
                    }
                    if let reason = r.reason {
                        Text(reason)
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Colors.primaryText)
                    }
                    let who: String = {
                        if r.reportType == "PRODUCT", let name = r.productName {
                            return "Listing: \(name)"
                        }
                        if let u = r.accountReportedUsername {
                            return "Account: @\(u)"
                        }
                        return "Report #\(r.id)"
                    }()
                    Text(who)
                        .font(Theme.Typography.subheadline)
                        .foregroundStyle(Theme.Colors.secondaryText)
                    if let by = r.reportedByUsername {
                        Text("Reported by @\(by)")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.tertiaryText)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        let c = session.graphQL
        do {
            async let a = PreluraAdminAPI.analyticsOverview(client: c)
            async let r = PreluraAdminAPI.allReports(client: c)
            analytics = try await a
            reports = try await r
        } catch {
            loadError = error.localizedDescription
        }
    }
}

private enum MarketplaceHealthScore {
    static func compute(from a: AnalyticsOverviewDTO) -> (value: Int, subtitle: String) {
        let nu = a.newUsersPercentageChange ?? 0
        let pv = a.totalProductViewsPercentageChange ?? 0
        let blend = (nu + pv) / 2
        let base = 72
        let swing = min(25, max(-25, Int(blend * 2)))
        let v = min(98, max(38, base + swing))
        let subtitle =
            "Heuristic from user-growth and listing-view momentum. Wire disputes and delivery KPIs when those admin metrics are exposed."
        return (v, subtitle)
    }
}

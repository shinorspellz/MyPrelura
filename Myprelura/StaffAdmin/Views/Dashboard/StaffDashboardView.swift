import SwiftUI

// MARK: - Dashboard layout (phone: ½-width grid + full-width rows; consistent icon boxes)

private enum DashboardChrome {
    static let iconBox: CGFloat = 36
    static let iconFont = Font.system(size: 17, weight: .semibold)
    /// Keeps 2×2 metric rows aligned even when footnotes wrap differently.
    static let metricTileMinHeight: CGFloat = 120
}

private enum HomeNav: Hashable {
    case analytics
    case console
    case tools
    case report(StaffAdminReportRow)
}

struct StaffDashboardView: View {
    /// When `false`, embed inside `AdminDesktopShell`’s shared `NavigationStack` (iPad / Mac).
    var wrapsInNavigationStack: Bool = true

    @Environment(AdminSession.self) private var session
    @EnvironmentObject private var authService: AuthService
    @State private var analytics: AnalyticsOverviewDTO?
    @State private var reports: [StaffAdminReportRow] = []
    @State private var loadError: String?
    @State private var isLoading = true

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
                }

                if isLoading && analytics == nil {
                    dashboardShimmerBlock
                }

                if let a = analytics {
                    metricsGrid(a)
                        .frame(maxWidth: .infinity)
                    healthCard(a)
                        .frame(maxWidth: .infinity)
                }

                consoleCard
                    .frame(maxWidth: .infinity)
                liveActivitySectionCard
                    .frame(maxWidth: .infinity)

                ForEach(reports.prefix(15)) { r in
                    activityRow(r)
                        .frame(maxWidth: .infinity)
                }

                if reports.isEmpty && !isLoading {
                    Text("No recent reports, or your token cannot read the admin dashboard.")
                        .font(Theme.Typography.footnote)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical)
            .frame(maxWidth: .infinity, alignment: .leading)
            .adminDesktopReadableWidth()
        }
        .background(Theme.Colors.background)
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.inline)
        .adminNavigationChrome()
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                NavigationLink(value: HomeNav.tools) {
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
        .refreshable { await load() }
        .task { await load() }
        .navigationDestination(for: HomeNav.self) { dest in
            switch dest {
            case .analytics:
                AnalyticsDetailView()
            case .console:
                ConsoleView()
                    .environment(session)
            case .tools:
                StaffToolsListView()
                    .environment(session)
            case let .report(r):
                AdminReportDetailView(report: r)
                    .environmentObject(authService)
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
                    .frame(maxWidth: .infinity, minHeight: DashboardChrome.metricTileMinHeight, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func dashboardIconBox(systemImage: String, accent: Color) -> some View {
        Image(systemName: systemImage)
            .font(DashboardChrome.iconFont)
            .imageScale(.medium)
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(accent)
            .frame(width: DashboardChrome.iconBox, height: DashboardChrome.iconBox)
            .background(accent.opacity(0.22))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                detail: metricIntradayFooter,
                systemImage: "chart.line.uptrend.xyaxis",
                accent: Theme.MetricAccents.viewsToday
            )
        }
    }

    private func metricTile(title: String, value: String, detail: String, systemImage: String, accent: Color) -> some View {
        NavigationLink(value: HomeNav.analytics) {
            GlassCard {
                HStack(alignment: .top, spacing: 10) {
                    dashboardIconBox(systemImage: systemImage, accent: accent)
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
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, minHeight: DashboardChrome.metricTileMinHeight, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    /// Same typography slot as `% vs prior day`; we do not expose intraday Δ yet.
    private var metricIntradayFooter: String {
        "Intraday count · no prior-day compare"
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
                HStack(alignment: .top, spacing: 10) {
                    dashboardIconBox(systemImage: "heart.text.square.fill", accent: Theme.MetricAccents.health)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Marketplace health score")
                            .font(Theme.Typography.footnote)
                            .foregroundStyle(Theme.Colors.secondaryText)
                        Text("\(score.value)")
                            .font(Theme.Typography.title2)
                            .foregroundStyle(Theme.MetricAccents.health)
                        Text(score.subtitle)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.tertiaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private var consoleCard: some View {
        NavigationLink(value: HomeNav.console) {
            GlassCard {
                HStack(alignment: .top, spacing: 10) {
                    dashboardIconBox(systemImage: "slider.horizontal.3", accent: Theme.MetricAccents.console)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Console")
                            .font(Theme.Typography.footnote)
                            .foregroundStyle(Theme.Colors.secondaryText)
                        Text("Health & probes")
                            .font(Theme.Typography.title2)
                            .foregroundStyle(Theme.Colors.primaryText)
                        Text("Health probes, outage simulation, and optional alert webhooks.")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.tertiaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    /// Same chrome as metric / console rows (icon + three-line stack).
    private var liveActivitySectionCard: some View {
        GlassCard {
            HStack(alignment: .top, spacing: 10) {
                dashboardIconBox(systemImage: "dot.radiowaves.left.and.right", accent: Theme.primaryColor)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Live activity")
                        .font(Theme.Typography.footnote)
                        .foregroundStyle(Theme.Colors.secondaryText)
                    Text("Recent reports")
                        .font(Theme.Typography.title2)
                        .foregroundStyle(Theme.Colors.primaryText)
                    Text("Latest combined account, listing, and order-issue rows.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity)
    }

    private func activityRow(_ r: StaffAdminReportRow) -> some View {
        NavigationLink(value: HomeNav.report(r)) {
            GlassCard {
                HStack(alignment: .top, spacing: 12) {
                    reportActivityThumbnail(r)
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
                            return "\(r.reportType ?? "Report") #\(r.backendRowId)"
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    /// Same 56×56 rounded rect + border as listing moderation rows so live activity thumbnails look consistent.
    private func reportActivityThumbnail(_ r: StaffAdminReportRow) -> some View {
        let url = r.imagesUrl?.compactMap { MediaURL.resolvedURL(from: $0) }.first
        return Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Theme.Colors.glassBackground)
                            ProgressView()
                        }
                    case let .success(img):
                        img
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        reportThumbPlaceholder(r)
                    @unknown default:
                        reportThumbPlaceholder(r)
                    }
                }
            } else {
                reportThumbPlaceholder(r)
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Theme.Colors.glassBorder, lineWidth: 1)
        )
    }

    private func reportThumbPlaceholder(_ r: StaffAdminReportRow) -> some View {
        let accent = reportTypeAccent(r)
        return ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(accent.opacity(0.22))
            Image(systemName: reportPlaceholderSystemImage(r))
                .font(DashboardChrome.iconFont)
                .foregroundStyle(accent)
        }
    }

    /// Matches metric-tile icon tints so placeholders align with the KPI row language.
    private func reportTypeAccent(_ r: StaffAdminReportRow) -> Color {
        switch r.reportType {
        case "PRODUCT": return Theme.MetricAccents.listingViews
        case "ACCOUNT": return Theme.MetricAccents.users
        case "ORDER_ISSUE": return Theme.MetricAccents.console
        default: return Theme.primaryColor
        }
    }

    private func reportPlaceholderSystemImage(_ r: StaffAdminReportRow) -> String {
        switch r.reportType {
        case "ACCOUNT": return "person.fill"
        case "PRODUCT": return "bag.fill"
        case "ORDER_ISSUE": return "shippingbox.fill"
        default: return "doc.text.fill"
        }
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

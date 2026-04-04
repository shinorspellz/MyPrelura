import SwiftUI
import UIKit

/// Dashboard screen — seller metrics, KPIs, and charts. Fetches UserEarnings from API; some metrics use derived/placeholder values until backend supports them.
struct ShopValueView: View {
    @EnvironmentObject var authService: AuthService
    var listingCount: Int = 0

    @State private var earnings: UserEarnings?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showWithdrawalFlow = false

    private var userService: UserService {
        let s = UserService()
        if let token = authService.authToken { s.updateAuthToken(token) }
        return s
    }

    // MARK: - Data (API + derived/placeholder)
    private var currentShopValue: Double { earnings?.networth ?? 0 }
    /// Cleared for payout: delivered/completed orders only (`userEarnings.completedPayments`).
    private var balance: Double { earnings?.completedPayments.value ?? 0 }
    private var thisMonth: Double { earnings?.earningsInMonth.value ?? 0 }
    private var totalEarnings: Double { earnings?.totalEarnings.value ?? 0 }
    /// Total earned since account creation (same as totalEarnings from API).
    private var lifetimeEarnings: Double { totalEarnings }
    private var transactionsCompleted: Int { earnings?.totalEarnings.quantity ?? 0 }
    private var pendingValue: Double { earnings?.pendingPayments.value ?? 0 }
    private var pendingOrdersCount: Int { earnings?.pendingPayments.quantity ?? 0 }
    /// Shown under Balance: sum from `pendingPayments.value` (in-flight / uncaptured payments).
    private var balancePendingSubtitle: String? {
        guard pendingOrdersCount > 0 || pendingValue > 0 else { return nil }
        return String(format: L10n.string("Pending %@"), formatCurrency(pendingValue))
    }

    private var viewsThisMonth: Int { 1240 }
    private var itemsSold: Int { transactionsCompleted }
    private var conversionRate: Double { viewsThisMonth > 0 ? Double(itemsSold) / Double(viewsThisMonth) * 100 : 4.8 }
    private var averageItemPrice: Double { itemsSold > 0 ? totalEarnings / Double(itemsSold) : 32 }
    private var sellerRating: Double { 4.9 }
    private var projectedMonthlyEarnings: Double { 720 }

    /// Placeholder % change vs previous period (until backend provides). Used for Views this month, This month, Total earnings, Lifetime, Projected earnings.
    private var viewsThisMonthPercentChange: Double { 8.0 }
    private var thisMonthPercentChange: Double { 12.0 }
    private var totalEarningsPercentChange: Double { 5.0 }
    private var lifetimePercentChange: Double { 5.0 }
    private var projectedEarningsPercentChange: Double { 10.0 }

    /// Mock weekly earnings for chart (last 6 weeks). Flat zeros when month-to-date is zero so UI matches data.
    private var earningsTrendPoints: [Double] {
        let m = thisMonth
        if m <= 0 { return [0, 0, 0, 0, 0, 0] }
        return [m * 0.15, m * 0.35, m * 0.55, m * 0.75, m * 0.88, m]
    }

    var body: some View {
        Group {
            if isLoading && earnings == nil {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ZStack(alignment: .bottom) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                            heroSection
                            kpiGrid
                            earningsChartSection
                            secondaryKpiGrid
                            performanceSection
                            helpLink
                        }
                        .padding(Theme.Spacing.md)
                        .padding(.bottom, 100)
                    }
                    PrimaryButtonBar {
                        PrimaryGlassButton(L10n.string("Withdraw"), action: { showWithdrawalFlow = true })
                    }
                }
            }
        }
        .background(Theme.Colors.background)
        .navigationTitle(L10n.string("Seller dashboard"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .refreshable { await loadEarnings() }
        .onAppear { Task { await loadEarnings() } }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task { await loadEarnings() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .preluraSellerEarningsShouldRefresh)) { _ in
            // Avoid showing pre-wipe KPIs if the next fetch fails or is slow.
            earnings = nil
            Task { await loadEarnings() }
        }
        .sheet(isPresented: $showWithdrawalFlow) {
            NavigationStack {
                WithdrawalFlowView(availableBalance: balance, onDismiss: { showWithdrawalFlow = false })
                    .environmentObject(authService)
            }
        }
    }

    private func loadEarnings() async {
        isLoading = true
        errorMessage = nil
        do {
            let e = try await userService.getUserEarnings()
            await MainActor.run {
                self.earnings = e
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                // Do not keep stale numbers from a previous successful response.
                self.earnings = nil
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    // MARK: - Hero: Shop Value + Listings
    private var heroSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(L10n.string("Current shop value"))
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.secondaryText)
                .textCase(.uppercase)
                .tracking(0.5)
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                Text(formatCurrency(currentShopValue))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.primaryText)
            }
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "tag")
                    .font(.caption)
                    .foregroundColor(Theme.Colors.secondaryText)
                Text("\(listingCount) \(L10n.string("active listings"))")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.lg)
        .background(Theme.Colors.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Glass.cornerRadius))
    }

    // MARK: - KPI grid (6 thumbnails: Balance, Pending orders, This month, Total earnings, Transactions, Lifetime)
    private var kpiGrid: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(L10n.string("Earnings & balance"))
                .font(Theme.Typography.headline)
                .foregroundColor(Theme.Colors.primaryText)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.sm) {
                DashboardKPICard(
                    title: L10n.string("Balance"),
                    value: formatCurrency(balance),
                    subtitle: balancePendingSubtitle,
                    pinSubtitleToBottom: true
                )
                DashboardKPICard(title: L10n.string("Pending orders"), value: "\(pendingOrdersCount)")
                DashboardKPICard(title: L10n.string("This month"), value: formatCurrency(thisMonth), percentChange: thisMonth > 0 ? thisMonthPercentChange : nil)
                DashboardKPICard(title: L10n.string("Total earnings"), value: formatCurrency(totalEarnings), percentChange: totalEarnings > 0 ? totalEarningsPercentChange : nil)
                DashboardKPICard(title: L10n.string("Transactions completed"), value: "\(transactionsCompleted)")
                DashboardKPICard(title: L10n.string("Lifetime"), value: formatCurrency(lifetimeEarnings), percentChange: lifetimeEarnings > 0 ? lifetimePercentChange : nil)
            }
        }
    }

    // MARK: - Earnings trend chart
    private var earningsChartSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(L10n.string("Earnings this month"))
                .font(Theme.Typography.headline)
                .foregroundColor(Theme.Colors.primaryText)
            DashboardAreaChart(points: earningsTrendPoints, fillColor: Theme.primaryColor.opacity(0.25), lineColor: Theme.primaryColor)
                .frame(height: 140)
                .padding(.vertical, Theme.Spacing.sm)
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Glass.cornerRadius))
    }

    // MARK: - Performance (Views, Items sold, Conversion, Avg price — Pending orders moved to top section)
    private var secondaryKpiGrid: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(L10n.string("Performance"))
                .font(Theme.Typography.headline)
                .foregroundColor(Theme.Colors.primaryText)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.sm) {
                DashboardKPICard(title: L10n.string("Views this month"), value: formatNumber(viewsThisMonth), percentChange: viewsThisMonthPercentChange)
                DashboardKPICard(title: L10n.string("Items sold"), value: "\(itemsSold)")
                DashboardKPICard(title: L10n.string("Conversion rate"), value: String(format: "%.1f%%", conversionRate))
                DashboardKPICard(title: L10n.string("Average item price"), value: formatCurrency(averageItemPrice))
            }
        }
    }

    // MARK: - Seller rating + Projected earnings (gauge-style)
    private var performanceSection: some View {
        HStack(spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(L10n.string("Seller rating"))
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.secondaryText)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.1f", sellerRating))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.primaryText)
                    Image(systemName: "star.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.yellow)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.lg)
            .background(Theme.Colors.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Glass.cornerRadius))

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(L10n.string("Projected monthly earnings"))
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.secondaryText)
                Text(formatCurrency(projectedMonthlyEarnings))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.Colors.primaryText)
                HStack(spacing: 2) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .semibold))
                    Text(String(format: "+%.1f%%", projectedEarningsPercentChange))
                        .font(.caption2)
                }
                .foregroundColor(Theme.primaryColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.lg)
            .background(Theme.Colors.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Glass.cornerRadius))
        }
    }

    private var helpLink: some View {
        Button(action: {}) {
            Text(L10n.string("Help"))
                .font(Theme.Typography.body)
                .foregroundColor(Theme.primaryColor)
        }
        .buttonStyle(HapticTapButtonStyle())
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.sm)
    }

    private func formatCurrency(_ value: Double) -> String {
        CurrencyFormatter.gbp(value)
    }

    private func formatNumber(_ n: Int) -> String {
        if n >= 1000 {
            return String(format: "%.1fk", Double(n) / 1000)
        }
        return "\(n)"
    }
}

// MARK: - Dashboard KPI card (fixed height so all cards align)
private struct DashboardKPICard: View {
    let title: String
    let value: String
    var subtitle: String? = nil
    /// When true, subtitle is pinned to the bottom of the card (gap under the main value).
    var pinSubtitleToBottom: Bool = false
    /// Percent change vs previous period; positive = increase, negative = decrease. Shown with arrow and colour (e.g. +8%, -2%).
    var percentChange: Double? = nil

    private var cardMinHeight: CGFloat {
        if let sub = subtitle, !sub.isEmpty { return 108 }
        return 92
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.secondaryText)
                .lineLimit(2)
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.Colors.primaryText)
            if pinSubtitleToBottom {
                Spacer(minLength: 0)
                if let sub = subtitle, !sub.isEmpty {
                    Text(sub)
                        .font(.caption2)
                        .foregroundColor(Theme.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                if let sub = subtitle, !sub.isEmpty {
                    Text(sub)
                        .font(.caption2)
                        .foregroundColor(Theme.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            if let pct = percentChange {
                HStack(spacing: 2) {
                    Image(systemName: pct >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 10, weight: .semibold))
                    Text(String(format: "%@%.1f%%", pct >= 0 ? "+" : "", pct))
                        .font(.caption2)
                }
                .foregroundColor(pct >= 0 ? Theme.primaryColor : Theme.Colors.error)
            }
        }
        .frame(maxWidth: .infinity, minHeight: cardMinHeight, alignment: .topLeading)
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Area chart for dashboard
private struct DashboardAreaChart: View {
    let points: [Double]
    let fillColor: Color
    let lineColor: Color

    var body: some View {
        GeometryReader { _ in
            DashboardAreaChartShape(points: points)
                .fill(fillColor)
            DashboardAreaChartShape(points: points)
                .stroke(lineColor, lineWidth: 2)
        }
    }
}

private struct DashboardAreaChartShape: Shape {
    let points: [Double]
    func path(in rect: CGRect) -> Path {
        guard !points.isEmpty else { return Path() }
        let maxP = points.max() ?? 1
        let minP = points.min() ?? 0
        let range = maxP - minP
        let stepX = rect.width / CGFloat(max(points.count - 1, 1))
        var areaPath = Path()
        for (i, v) in points.enumerated() {
            let x = CGFloat(i) * stepX
            let y = range > 0 ? rect.height * (1 - CGFloat((v - minP) / range)) : rect.height / 2
            if i == 0 {
                areaPath.move(to: CGPoint(x: x, y: rect.height))
                areaPath.addLine(to: CGPoint(x: x, y: y))
            } else {
                areaPath.addLine(to: CGPoint(x: x, y: y))
            }
        }
        areaPath.addLine(to: CGPoint(x: CGFloat(points.count - 1) * stepX, y: rect.height))
        areaPath.closeSubpath()
        return areaPath
    }
}

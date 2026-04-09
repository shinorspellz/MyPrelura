import SwiftUI

private let orderIssueReportType = "ORDER_ISSUE"
private let profanityReportType = "PROFANITY"

struct ReportsQueueView: View {
    var wrapsInNavigationStack: Bool = true

    @Environment(AdminSession.self) private var session
    @EnvironmentObject private var authService: AuthService
    @State private var reports: [StaffAdminReportRow] = []
    @State private var errorMessage: String?
    @State private var filterText = ""
    @State private var selectedTypeTag: String?

    private var typeTagsFromData: [String] {
        let types = Set(reports.compactMap(\.reportType).filter { !$0.isEmpty })
        return types.filter { $0 != orderIssueReportType && $0 != profanityReportType }.sorted()
    }

    private func chipTitle(for tag: String) -> String {
        if tag == profanityReportType { return "Profanity" }
        return tag
    }

    private var filtered: [StaffAdminReportRow] {
        var base = reports
        if let tag = selectedTypeTag {
            base = base.filter { ($0.reportType ?? "") == tag }
        }
        let q = filterText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return base }
        return base.filter {
            ($0.reason ?? "").lowercased().contains(q)
                || ($0.reportType ?? "").lowercased().contains(q)
                || ($0.reportedByUsername ?? "").lowercased().contains(q)
                || ($0.accountReportedUsername ?? "").lowercased().contains(q)
                || ($0.productName ?? "").lowercased().contains(q)
        }
    }

    var body: some View {
        Group {
            if wrapsInNavigationStack {
                NavigationStack { reportsRoot }
            } else {
                reportsRoot
            }
        }
    }

    private var reportsRoot: some View {
        VStack(alignment: .leading, spacing: 0) {
            chipScrollRow
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 6)

            List {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(Theme.Colors.error)
                }
                ForEach(filtered) { r in
                    NavigationLink(value: r) {
                        HStack(alignment: .center, spacing: 10) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text((r.reportType ?? "REPORT").uppercased())
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .background(Theme.primaryColor.opacity(0.2))
                                        .clipShape(Capsule())
                                    Spacer()
                                    Text(r.status ?? "")
                                        .font(Theme.Typography.caption)
                                        .foregroundStyle(Theme.Colors.secondaryText)
                                }
                                Text(r.reason ?? "No reason")
                                    .font(Theme.Typography.headline)
                                    .foregroundStyle(Theme.Colors.primaryText)
                                if let ctx = r.context, !ctx.isEmpty {
                                    Text(ctx)
                                        .font(Theme.Typography.footnote)
                                        .foregroundStyle(Theme.Colors.secondaryText)
                                        .lineLimit(4)
                                }
                                if r.reportType == "PRODUCT" {
                                    Text("Listing #\(r.productId ?? 0) · \(r.productName ?? "")")
                                        .font(Theme.Typography.caption)
                                        .foregroundStyle(Theme.Colors.secondaryText)
                                } else if r.reportType == orderIssueReportType, let oid = r.orderId {
                                    Text("Order #\(oid)")
                                        .font(Theme.Typography.caption)
                                        .foregroundStyle(Theme.Colors.secondaryText)
                                } else if let u = r.accountReportedUsername {
                                    Text("@\(u)")
                                        .font(Theme.Typography.caption)
                                        .foregroundStyle(Theme.Colors.secondaryText)
                                }
                                if let by = r.reportedByUsername {
                                    Text("Reporter: @\(by)")
                                        .font(Theme.Typography.caption)
                                        .foregroundStyle(Theme.Colors.tertiaryText)
                                }
                            }
                            if r.hasLinkedChat {
                                Image(systemName: "bubble.left.and.bubble.right.fill")
                                    .font(.body)
                                    .foregroundStyle(Theme.primaryColor)
                                    .accessibilityLabel("Has linked chat")
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .listStyle(.plain)
        }
        .navigationTitle("Reports")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    StaffOrderIssuesView(wrapsInNavigationStack: false)
                } label: {
                    Label("Order issues", systemImage: "cart.fill.badge.minus")
                }
            }
        }
        .adminNavigationChrome()
        .searchable(text: $filterText, prompt: "Filter queue")
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.background)
        .refreshable { await load() }
        .task { await load() }
        .navigationDestination(for: StaffAdminReportRow.self) { r in
            AdminReportDetailView(report: r)
                .environmentObject(authService)
        }
    }

    private var chipScrollRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                typeChip(title: "All", tag: nil)
                typeChip(title: "Order issue", tag: orderIssueReportType)
                typeChip(title: "Profanity", tag: profanityReportType)
                ForEach(typeTagsFromData, id: \.self) { tag in
                    typeChip(title: chipTitle(for: tag), tag: tag)
                }
            }
        }
    }

    private func load() async {
        errorMessage = nil
        do {
            reports = try await PreluraAdminAPI.allReports(client: session.graphQL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func typeChip(title: String, tag: String?) -> some View {
        let selected = (tag == nil && selectedTypeTag == nil) || (tag != nil && tag == selectedTypeTag)
        return Button {
            selectedTypeTag = tag
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(selected ? Theme.primaryColor.opacity(0.35) : Theme.Colors.glassBackground)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(selected ? Theme.primaryColor : Theme.Colors.glassBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

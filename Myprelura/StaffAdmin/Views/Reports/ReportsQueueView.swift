import SwiftUI

struct ReportsQueueView: View {
    var wrapsInNavigationStack: Bool = true

    @Environment(AdminSession.self) private var session
    @State private var reports: [StaffAdminReportRow] = []
    @State private var errorMessage: String?
    @State private var filterText = ""
    @State private var selectedTypeTag: String?

    private var typeTags: [String] {
        let types = Set(reports.compactMap(\.reportType).filter { !$0.isEmpty })
        return types.sorted()
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
        List {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(Theme.Colors.error)
            }
            if !typeTags.isEmpty {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            typeChip(title: "All", tag: nil)
                            ForEach(typeTags, id: \.self) { tag in
                                typeChip(title: tag, tag: tag)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowBackground(Color.clear)
                }
            }
            ForEach(filtered) { r in
                NavigationLink(value: r) {
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
                    .padding(.vertical, 6)
                }
            }
        }
        .navigationTitle("Reports")
        .navigationBarTitleDisplayMode(.inline)
        .adminNavigationChrome()
        .searchable(text: $filterText, prompt: "Filter queue")
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.background)
        .refreshable { await load() }
        .task { await load() }
        .navigationDestination(for: StaffAdminReportRow.self) { r in
            AdminReportDetailView(report: r)
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

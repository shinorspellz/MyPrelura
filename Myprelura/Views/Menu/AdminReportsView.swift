import SwiftUI

struct AdminReportsView: View {
    @EnvironmentObject var authService: AuthService
    @StateObject private var adminService = AdminService(client: GraphQLClient())

    @State private var reports: [AdminReportRow] = []
    @State private var selectedType: ReportTypeFilter = .all
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var expandedIds: Set<String> = []

    private enum ReportTypeFilter: String, CaseIterable {
        case all = "All"
        case product = "Product reports"
        case account = "User reports"
    }

    private var filteredReports: [AdminReportRow] {
        switch selectedType {
        case .all:
            return reports
        case .product:
            return reports.filter { ($0.reportType ?? "").uppercased() == "PRODUCT" }
        case .account:
            return reports.filter { ($0.reportType ?? "").uppercased() == "ACCOUNT" }
        }
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            if !(isLoading && reports.isEmpty) && !(errorMessage != nil && reports.isEmpty) {
                filterPills
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.top, Theme.Spacing.xs)
            }
            Group {
            if isLoading && reports.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage, reports.isEmpty {
                Text(errorMessage)
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.error)
                    .multilineTextAlignment(.center)
                    .padding()
            } else {
                List {
                    ForEach(filteredReports) { report in
                        DisclosureGroup(
                            isExpanded: Binding(
                                get: { expandedIds.contains(report.id) },
                                set: { on in
                                    if on { expandedIds.insert(report.id) } else { expandedIds.remove(report.id) }
                                }
                            ),
                            content: { detail(report) },
                            label: {
                                HStack(alignment: .center, spacing: Theme.Spacing.sm) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(report.publicId ?? "Report #\(report.rawId)")
                                            .font(Theme.Typography.headline)
                                        Text((report.reportType ?? "REPORT") + " • " + (report.status ?? "PENDING"))
                                            .font(Theme.Typography.caption)
                                            .foregroundColor(Theme.Colors.secondaryText)
                                        if let by = report.reportedByUsername, !by.isEmpty {
                                            Text("Raised by \(by)")
                                                .font(Theme.Typography.caption)
                                                .foregroundColor(Theme.Colors.secondaryText)
                                        }
                                        if let created = report.dateCreated, !created.isEmpty {
                                            Text(Self.formatAdminRelativeDate(iso: created))
                                                .font(Theme.Typography.caption)
                                                .foregroundColor(Theme.Colors.secondaryText)
                                        }
                                    }
                                    Spacer()
                                    if let cid = report.conversationId {
                                        NavigationLink {
                                            AdminReportOrderChatLoaderView(conversationId: String(cid))
                                        } label: {
                                            Image(systemName: "bubble.right.fill")
                                                .foregroundColor(Theme.primaryColor)
                                                .imageScale(.medium)
                                        }
                                        .buttonStyle(PlainTappableButtonStyle())
                                    } else {
                                        Text("No chat")
                                            .font(Theme.Typography.caption)
                                            .foregroundColor(Theme.Colors.secondaryText)
                                    }
                                }
                            }
                        )
                    }
                }
                .listStyle(.plain)
            }
        }
        }
        .background(Theme.Colors.background)
        .navigationTitle("Reports")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .refreshable { await load() }
        .task {
            if let token = authService.authToken { adminService.updateAuthToken(token) }
            await load()
        }
    }

    private var filterPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.xs) {
                ForEach(ReportTypeFilter.allCases, id: \.rawValue) { filter in
                    Button {
                        selectedType = filter
                    } label: {
                        Text(filter.rawValue)
                            .font(Theme.Typography.caption.weight(.semibold))
                            .foregroundColor(selectedType == filter ? Theme.Colors.primaryText : Theme.Colors.secondaryText)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(selectedType == filter ? Theme.Colors.secondaryBackground : Theme.Colors.background)
                            )
                            .overlay(
                                Capsule()
                                    .stroke(Theme.Colors.glassBorder, lineWidth: 1)
                            )
                    }
                    .buttonStyle(PlainTappableButtonStyle())
                }
            }
        }
    }

    @ViewBuilder
    private func detail(_ report: AdminReportRow) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            labeled("Reason", report.reason ?? "—")
            labeled("Details", report.context ?? "—")
            if let target = report.accountReportedUsername, !target.isEmpty {
                labeled("Reported account", target)
            }
            if let productName = report.productName, !productName.isEmpty {
                if let productId = report.productId {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Reported product")
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.secondaryText)
                        NavigationLink {
                            AdminReportProductLoaderView(productId: productId)
                                .environmentObject(authService)
                        } label: {
                            Text(productName)
                                .font(Theme.Typography.body.weight(.semibold))
                                .foregroundColor(Theme.primaryColor)
                        }
                        .buttonStyle(PlainTappableButtonStyle())
                    }
                } else {
                    labeled("Reported product", productName)
                }
            }
            if let urls = report.imagesUrl, !urls.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.xs) {
                        ForEach(urls, id: \.self) { urlString in
                            if let url = URL(string: urlString) {
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .success(let image): image.resizable().scaledToFill()
                                    default: Rectangle().fill(Theme.Colors.tertiaryBackground)
                                    }
                                }
                                .frame(width: 72, height: 72)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }
            }
            if let cid = report.conversationId {
                NavigationLink {
                    AdminReportOrderChatLoaderView(conversationId: String(cid))
                } label: {
                    Text("View conversation")
                        .font(Theme.Typography.body.weight(.semibold))
                        .foregroundColor(Theme.primaryColor)
                }
                .buttonStyle(PlainTappableButtonStyle())
            } else {
                Text("No conversation linked for this report.")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.secondaryText)
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(Theme.Typography.caption).foregroundColor(Theme.Colors.secondaryText)
            Text(value).font(Theme.Typography.body).foregroundColor(Theme.Colors.primaryText)
        }
    }

    private func load() async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        do {
            let list = try await adminService.fetchAllReports()
            await MainActor.run {
                reports = list
                isLoading = false
            }
        } catch {
            await MainActor.run {
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private static func formatAdminRelativeDate(iso: String) -> String {
        let parsers: [ISO8601DateFormatter] = {
            let f1 = ISO8601DateFormatter()
            f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let f2 = ISO8601DateFormatter()
            f2.formatOptions = [.withInternetDateTime]
            return [f1, f2]
        }()
        guard let date = parsers.compactMap({ $0.date(from: iso) }).first else { return iso }
        let now = Date()
        if now.timeIntervalSince(date) < 60 { return "Just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        let value = formatter.localizedString(for: date, relativeTo: now)
        if value.lowercased().hasPrefix("in ") { return iso }
        return value
    }

}

private struct AdminReportOrderChatLoaderView: View {
    let conversationId: String
    @EnvironmentObject var authService: AuthService
    @StateObject private var chatService = ChatService()
    @State private var conversation: Conversation?
    @State private var errorMessage: String?
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading chat...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let conversation {
                ChatDetailView(conversation: conversation)
            } else {
                Text(errorMessage ?? "Could not open this conversation.")
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            chatService.updateAuthToken(authService.authToken)
            do {
                let loaded = try await chatService.getConversationById(
                    conversationId: conversationId,
                    currentUsername: authService.username
                )
                await MainActor.run {
                    conversation = loaded
                    isLoading = false
                    if loaded == nil {
                        errorMessage = "Not found or no permission for this order chat."
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}

private struct AdminReportProductLoaderView: View {
    let productId: Int
    @EnvironmentObject var authService: AuthService
    private let productService = ProductService()
    @State private var item: Item?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading product...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let item {
                ItemDetailView(item: item, authService: authService)
            } else {
                Text(errorMessage ?? "Could not load product.")
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                if let loaded = try await productService.getProduct(id: productId) {
                    await MainActor.run {
                        item = loaded
                        isLoading = false
                    }
                } else {
                    await MainActor.run {
                        errorMessage = "Product not found."
                        isLoading = false
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}

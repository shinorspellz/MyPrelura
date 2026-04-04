import SwiftUI

/// Staff drill-down for a queue row: evidence, deep links, and GraphQL `conversation` messages (same API as consumer; real-time would use WebSockets like the shopper app).
struct AdminReportDetailView: View {
    @Environment(AdminSession.self) private var session
    let report: StaffAdminReportRow

    @State private var messages: [ChatMessageDTO] = []
    @State private var messagesError: String?

    private var orderedMessages: [ChatMessageDTO] {
        messages.sorted { $0.id < $1.id }
    }

    private var threadId: Int? {
        report.supportConversationId ?? report.conversationId
    }

    var body: some View {
        List {
            Section("Summary") {
                LabeledContent("Type", value: report.reportType ?? "—")
                LabeledContent("Status", value: report.status ?? "—")
                if let pid = report.publicId, !pid.isEmpty {
                    LabeledContent("Public id", value: pid)
                }
            }

            Section("Details") {
                Text(report.reason ?? "No reason")
                if let ctx = report.context, !ctx.isEmpty {
                    Text(ctx)
                        .font(Theme.Typography.footnote)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
            }

            if let imgs = report.imagesUrl, !imgs.isEmpty {
                Section("Attachments") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Array(imgs.enumerated()), id: \.offset) { _, urlStr in
                                if let u = URL(string: urlStr) {
                                    AsyncImage(url: u) { phase in
                                        switch phase {
                                        case .empty:
                                            ProgressView()
                                        case let .success(img):
                                            img.resizable().scaledToFill()
                                        default:
                                            Image(systemName: "photo")
                                        }
                                    }
                                    .frame(width: 120, height: 120)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        }
                    }
                }
            }

            Section("People") {
                if let by = report.reportedByUsername {
                    LabeledContent("Reporter", value: "@\(by)")
                }
                if let acc = report.accountReportedUsername {
                    if let url = Constants.publicProfileURL(username: acc) {
                        NavigationLink {
                            ConsumerWebPageView(url: url, title: "@\(acc)")
                        } label: {
                            Text("Open reported account (web)")
                        }
                    }
                }
            }

            if report.reportType == "PRODUCT", let pid = report.productId {
                Section("Listing") {
                    LabeledContent("Product id", value: "\(pid)")
                    if let name = report.productName {
                        Text(name)
                    }
                    if let url = Constants.publicProductURL(productId: pid, listingCode: nil) {
                        NavigationLink {
                            ConsumerWebPageView(url: url, title: "Listing")
                        } label: {
                            Text("Open listing on prelura.uk")
                        }
                    }
                }
            }

            Section {
                if let tid = threadId {
                    LabeledContent("Thread id", value: "\(tid)")
                    Text("Messages load via the same `conversation` GraphQL query as the shopper inbox. Staff access follows server rules (system/order threads). Live typing and push use WebSockets in the consumer app; this screen refreshes on open and pull-to-refresh.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.tertiaryText)
                } else {
                    Text("No linked conversation id on this report.")
                        .font(Theme.Typography.footnote)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
            } header: {
                Text("Conversation")
            }

            if let messagesError {
                Section {
                    Text(messagesError)
                        .foregroundStyle(Theme.Colors.error)
                        .font(Theme.Typography.footnote)
                }
            }

            if !messages.isEmpty {
                Section("Messages (oldest → newest)") {
                    ForEach(orderedMessages) { m in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(m.sender?.username.map { "@\($0)" } ?? "—")
                                    .font(Theme.Typography.caption)
                                    .foregroundStyle(Theme.primaryColor)
                                Spacer()
                                Text(m.createdAt ?? "")
                                    .font(Theme.Typography.caption)
                                    .foregroundStyle(Theme.Colors.tertiaryText)
                            }
                            Text(m.text ?? "")
                                .font(Theme.Typography.subheadline)
                                .foregroundStyle(Theme.Colors.primaryText)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("Report #\(report.id)")
        .navigationBarTitleDisplayMode(.inline)
        .adminNavigationChrome()
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.background)
        .refreshable { await loadMessages() }
        .task { await loadMessages() }
    }

    private func loadMessages() async {
        guard let tid = threadId else { return }
        messagesError = nil
        do {
            let rows = try await PreluraAdminAPI.conversationMessages(
                client: session.graphQL,
                conversationId: tid,
                page: 1,
                pageSize: 200
            )
            messages = rows
        } catch {
            messagesError = error.localizedDescription
            messages = []
        }
    }
}

import SwiftUI

struct SupportIssueDraft {
    let selectedOptions: [String]
    let description: String
    let imageDatas: [Data]
    let imageUrls: [String]
    let issueTypeCode: String?
    let issueId: Int?
    let issuePublicId: String?

    init(
        selectedOptions: [String],
        description: String,
        imageDatas: [Data],
        imageUrls: [String] = [],
        issueTypeCode: String?,
        issueId: Int?,
        issuePublicId: String?
    ) {
        self.selectedOptions = selectedOptions
        self.description = description
        self.imageDatas = imageDatas
        self.imageUrls = imageUrls
        self.issueTypeCode = issueTypeCode
        self.issueId = issueId
        self.issuePublicId = issuePublicId
    }
}

private struct SupportChatMessage: Identifiable {
    let id: String
    let text: String
    let isFromUser: Bool
    let createdAt: Date
}

private struct PersistedIssueSummary {
    let issueTypeText: String?
    let description: String?
    let imageUrls: [String]
}

private enum SupportIssueImageSource {
    case local(UIImage)
    case remote(String)
}

private struct SupportIssueImageFullscreenView: View {
    let images: [SupportIssueImageSource]
    let initialIndex: Int
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIndex: Int = 0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            TabView(selection: $selectedIndex) {
                ForEach(Array(images.enumerated()), id: \.offset) { index, source in
                    Group {
                        switch source {
                        case .local(let image):
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color.black)
                        case .remote(let urlString):
                            if let url = URL(string: urlString) {
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .scaledToFit()
                                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                                            .background(Color.black)
                                    case .empty:
                                        ProgressView()
                                            .tint(.white)
                                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    case .failure:
                                        Image(systemName: "photo")
                                            .foregroundColor(.white.opacity(0.7))
                                            .font(.system(size: 42))
                                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    @unknown default:
                                        EmptyView()
                                    }
                                }
                            } else {
                                Image(systemName: "photo")
                                    .foregroundColor(.white.opacity(0.7))
                                    .font(.system(size: 42))
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        }
                    }
                    .tag(index)
                    .padding(.horizontal, Theme.Spacing.sm)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))

            Button("Done") { dismiss() }
                .font(Theme.Typography.body.weight(.semibold))
                .foregroundColor(.white)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .background(Color.black.opacity(0.45))
                .clipShape(Capsule())
                .padding(.top, Theme.Spacing.lg)
                .padding(.trailing, Theme.Spacing.md)
        }
        .onAppear {
            selectedIndex = min(max(initialIndex, 0), max(images.count - 1, 0))
        }
    }
}

private struct SupportOrderProductHeader: View {
    let item: Item
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                Group {
                    if let firstUrl = item.imageURLs.first, let url = URL(string: firstUrl) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().aspectRatio(contentMode: .fill)
                            case .failure, .empty:
                                Rectangle()
                                    .fill(Theme.Colors.secondaryBackground)
                                    .overlay(Image(systemName: "photo").foregroundColor(Theme.Colors.secondaryText))
                            @unknown default:
                                EmptyView()
                            }
                        }
                    } else {
                        Rectangle()
                            .fill(Theme.Colors.secondaryBackground)
                            .overlay(Image(systemName: "photo").foregroundColor(Theme.Colors.secondaryText))
                    }
                }
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 4))

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(Theme.Typography.body)
                        .fontWeight(.semibold)
                        .foregroundColor(Theme.Colors.primaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(item.formattedPrice)
                        .font(Theme.Typography.body)
                        .fontWeight(.semibold)
                        .foregroundColor(Theme.primaryColor)
                    Text("Related order item")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.Colors.secondaryText)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(Theme.Colors.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Glass.cornerRadius))
        }
        .buttonStyle(PlainTappableButtonStyle())
    }
}

/// Help Chat View (from Flutter help_chat_view). Chat-like support conversation with order issue context.
struct HelpChatView: View {
    var orderId: String? = nil
    /// When set, messages load from GraphQL/WebSocket-backed conversation (buyer ↔ support / staff).
    var conversationId: String? = nil
    var issueDraft: SupportIssueDraft? = nil
    /// Admin opened thread from Order issues list.
    var isAdminSupportThread: Bool = false
    var customerUsername: String? = nil
    /// When true, chat is read-only (e.g. after submitting "Item not as described" — user already sent context).
    var hidesMessageComposer: Bool = false

    @EnvironmentObject var authService: AuthService
    @StateObject private var chatService = ChatService()
    @State private var newMessage = ""
    @State private var chatMessages: [SupportChatMessage] = []
    @State private var relatedItem: Item?
    @State private var relatedProductId: Int?
    @State private var isLoadingHeaderProduct = false
    @State private var productHeaderError: String?
    @State private var isLoadingMessages = false
    @State private var loadMessagesError: String?
    @State private var persistedIssueImageUrls: [String] = []
    @State private var persistedIssueTypeText: String?
    @State private var persistedIssueDescription: String?
    @State private var showIssueImageViewer = false
    @State private var selectedIssueImageIndex = 0
    private let userService = UserService()
    private let productService = ProductService()

    private var usePersistedThread: Bool {
        guard let cid = conversationId, !cid.isEmpty, Int(cid) != nil else { return false }
        return true
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            if let item = relatedItem {
                NavigationLink(destination: ItemDetailView(item: item)) {
                    SupportOrderProductHeader(item: item) { }
                }
                .buttonStyle(PlainTappableButtonStyle())
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.xs)
            } else if isLoadingHeaderProduct {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.top, Theme.Spacing.xs)
            } else if let err = productHeaderError, !err.isEmpty {
                Text(err)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.top, Theme.Spacing.xs)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: Theme.Spacing.sm) {
                        issueSummaryCard

                        if isLoadingMessages {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.top, Theme.Spacing.sm)
                        } else if let err = loadMessagesError, !err.isEmpty {
                            Text(err)
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.error)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        ForEach(chatMessages) { message in
                            HStack {
                                if message.isFromUser { Spacer(minLength: Theme.Spacing.lg) }
                                Text(message.text)
                                    .font(Theme.Typography.body)
                                    .foregroundColor(message.isFromUser ? .white : Theme.Colors.primaryText)
                                    .padding(.horizontal, Theme.Spacing.md)
                                    .padding(.vertical, Theme.Spacing.sm)
                                    .background(message.isFromUser ? Theme.primaryColor : Theme.Colors.secondaryBackground)
                                    .clipShape(RoundedRectangle(cornerRadius: 18))
                                if !message.isFromUser { Spacer(minLength: Theme.Spacing.lg) }
                            }
                            .id(message.id)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.top, Theme.Spacing.xs)
                    .padding(.bottom, Theme.Spacing.sm)
                }
                .onChange(of: chatMessages.count) { _, _ in
                    if let lastId = chatMessages.last?.id {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
            }

            if !hidesMessageComposer {
                messageComposer
            }
        }
        .background(Theme.Colors.background)
        .navigationTitle(navigationTitleText)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .fullScreenCover(isPresented: $showIssueImageViewer) {
            SupportIssueImageFullscreenView(
                images: issueGallerySources,
                initialIndex: selectedIssueImageIndex
            )
        }
        .task {
            chatService.updateAuthToken(authService.authToken)
            if usePersistedThread {
                await loadPersistedMessages()
            } else {
                await bootstrapSupportChat()
            }
            await loadRelatedOrderProduct()
        }
    }

    private var navigationTitleText: String {
        if isAdminSupportThread {
            if let u = customerUsername, !u.isEmpty { return "Support · \(u)" }
            return "Support chat"
        }
        return "Help Chat"
    }

    @ViewBuilder
    private var issueSummaryCard: some View {
        if issueDraft != nil || !persistedIssueImageUrls.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Issue details shared with support")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.secondaryText)

                if let issueDraft, !issueDraft.selectedOptions.isEmpty {
                    Text(issueDraft.selectedOptions.joined(separator: ", "))
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.primaryText)
                } else if let typeText = persistedIssueTypeText, !typeText.isEmpty {
                    Text(typeText)
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.primaryText)
                }

                if let issueDraft, !issueDraft.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(issueDraft.description)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.primaryText)
                } else if let description = persistedIssueDescription, !description.isEmpty {
                    Text(description)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.primaryText)
                }

                if !issueGallerySources.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Theme.Spacing.xs) {
                            ForEach(Array(issueGallerySources.enumerated()), id: \.offset) { index, source in
                                Button {
                                    selectedIssueImageIndex = index
                                    showIssueImageViewer = true
                                } label: {
                                    Group {
                                        switch source {
                                        case .local(let uiImage):
                                            Image(uiImage: uiImage)
                                                .resizable()
                                                .scaledToFill()
                                        case .remote(let urlString):
                                            if let url = URL(string: urlString) {
                                                AsyncImage(url: url) { phase in
                                                    switch phase {
                                                    case .success(let image):
                                                        image.resizable().scaledToFill()
                                                    case .failure, .empty:
                                                        Rectangle()
                                                            .fill(Theme.Colors.secondaryBackground)
                                                            .overlay(Image(systemName: "photo").foregroundColor(Theme.Colors.secondaryText))
                                                    @unknown default:
                                                        EmptyView()
                                                    }
                                                }
                                            } else {
                                                Rectangle()
                                                    .fill(Theme.Colors.secondaryBackground)
                                                    .overlay(Image(systemName: "photo").foregroundColor(Theme.Colors.secondaryText))
                                            }
                                        }
                                    }
                                    .frame(width: 120, height: 120)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Glass.cornerRadius))
        }
    }

    private var issueGallerySources: [SupportIssueImageSource] {
        var list: [SupportIssueImageSource] = []
        if let issueDraft {
            for data in issueDraft.imageDatas {
                if let image = UIImage(data: data) {
                    list.append(.local(image))
                }
            }
            for url in issueDraft.imageUrls where !url.isEmpty {
                list.append(.remote(url))
            }
        }
        for url in persistedIssueImageUrls where !url.isEmpty {
            list.append(.remote(url))
        }
        return list
    }

    private var messageComposer: some View {
        HStack(spacing: Theme.Spacing.sm) {
            TextField("Type a message...", text: $newMessage)
                .textFieldStyle(.plain)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, 12)
                .background(Theme.Colors.secondaryBackground)
                .clipShape(Capsule())

            Button(action: sendMessage) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 42, height: 42)
                    .background(Theme.primaryColor)
                    .clipShape(Circle())
            }
            .disabled(newMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.bottom, Theme.Spacing.sm)
    }

    private func bootstrapSupportChat() async {
        if chatMessages.isEmpty {
            let starter = issueDraft?.selectedOptions.first ?? "Order support request"
            await MainActor.run {
                chatMessages = [
                    SupportChatMessage(
                        id: UUID().uuidString,
                        text: "Support: Thanks for reaching out. We received your \(starter.lowercased()) details. We'll respond within 24-72 hrs.",
                        isFromUser: false,
                        createdAt: Date()
                    )
                ]
            }
        }
    }

    private func loadPersistedMessages() async {
        guard let cid = conversationId, let _ = Int(cid) else { return }
        await MainActor.run {
            isLoadingMessages = true
            loadMessagesError = nil
        }
        chatService.updateAuthToken(authService.authToken)
        do {
            let msgs = try await chatService.getMessages(conversationId: cid, pageNumber: 1, pageCount: 100)
            let me = (authService.username ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            // Hide structured system-context payloads from bubbles:
            // - order_issue (already summarized at the top)
            // - account_report / product_report (reports context)
            let rendered = msgs.filter { m in
                // Suppress any structured system payloads that should be summarized, not bubbled
                let trimmed = m.content.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("{"),
                   let data = trimmed.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let t = ((json["type"] as? String) ?? (json["message_type"] as? String) ?? (json["kind"] as? String))?.lowercased() ?? ""
                    if t == "order_issue" || t == "account_report" || t == "product_report" {
                        return false
                    }
                    // If common report keys exist, assume it's a report context blob and hide
                    if json["public_id"] != nil && (json["reported_username"] != nil || json["reason"] != nil) {
                        return false
                    }
                }
                // Legacy flag
                if m.isOrderIssue { return false }
                return true
            }
            let mapped: [SupportChatMessage] = rendered.map { m in
                let sender = m.senderUsername.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let fromUser = !me.isEmpty && sender == me
                let mid = m.backendId.map { "b-\($0)" } ?? m.id.uuidString
                return SupportChatMessage(id: mid, text: m.content, isFromUser: fromUser, createdAt: m.timestamp)
            }
            await MainActor.run {
                chatMessages = mapped
                let persisted = extractPersistedIssueSummary(from: msgs)
                persistedIssueImageUrls = persisted.imageUrls
                persistedIssueTypeText = persisted.issueTypeText
                persistedIssueDescription = persisted.description
                isLoadingMessages = false
            }
        } catch {
            await MainActor.run {
                isLoadingMessages = false
                loadMessagesError = error.localizedDescription
            }
        }
    }

    private func extractPersistedIssueSummary(from messages: [Message]) -> PersistedIssueSummary {
        var orderedUrls: [String] = []
        var seen = Set<String>()
        var issueTypeText: String?
        var description: String?
        for message in messages {
            let trimmed = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("{"),
                  let data = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            let kind = ((json["type"] as? String) ?? (json["message_type"] as? String) ?? (json["kind"] as? String))?.lowercased()
            guard kind == "order_issue" || kind == "account_report" || kind == "product_report" else { continue }

            if issueTypeText == nil {
                issueTypeText = (json["issue_type"] as? String)
                    ?? (json["issueType"] as? String)
                    ?? (json["title"] as? String)
                    ?? (json["subject"] as? String)
                    ?? (json["reason"] as? String)
            }
            if description == nil {
                let rawDescription = (json["description"] as? String)
                    ?? (json["details"] as? String)
                    ?? (json["notes"] as? String)
                if let rawDescription {
                    let normalized = rawDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !normalized.isEmpty { description = normalized }
                }
            }

            let candidates: [String] = [
                "imagesUrl", "images_url", "issueImages", "issue_images", "images"
            ]
            for key in candidates {
                guard let raw = json[key] else { continue }
                let urls = decodeImageUrlList(raw)
                for url in urls where !url.isEmpty && !seen.contains(url) {
                    seen.insert(url)
                    orderedUrls.append(url)
                }
            }
        }
        return PersistedIssueSummary(
            issueTypeText: issueTypeText,
            description: description,
            imageUrls: orderedUrls
        )
    }

    private func decodeImageUrlList(_ raw: Any) -> [String] {
        if let urls = raw as? [String] {
            return urls.compactMap { normalizePossibleImageUrl($0) }
        }
        if let objects = raw as? [[String: Any]] {
            return objects.compactMap { dict in
                (dict["url"] as? String).flatMap { normalizePossibleImageUrl($0) }
            }
        }
        if let single = raw as? String {
            if let normalized = normalizePossibleImageUrl(single) { return [normalized] }
            return []
        }
        return []
    }

    private func normalizePossibleImageUrl(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("{"),
           let data = trimmed.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let url = json["url"] as? String {
            return url.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    private func sendMessage() {
        let text = newMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if usePersistedThread, let cid = conversationId, Int(cid) != nil {
            let optimistic = SupportChatMessage(id: UUID().uuidString, text: text, isFromUser: true, createdAt: Date())
            newMessage = ""
            chatMessages.append(optimistic)
            Task {
                chatService.updateAuthToken(authService.authToken)
                let uuid = UUID().uuidString
                do {
                    let ok = try await chatService.sendMessage(conversationId: cid, message: text, messageUuid: uuid)
                    if !ok {
                        await MainActor.run {
                            chatMessages.removeAll { $0.id == optimistic.id }
                            loadMessagesError = "Message failed to send"
                        }
                    }
                } catch {
                    await MainActor.run {
                        chatMessages.removeAll { $0.id == optimistic.id }
                        loadMessagesError = error.localizedDescription
                    }
                }
            }
            return
        }
        chatMessages.append(SupportChatMessage(id: UUID().uuidString, text: text, isFromUser: true, createdAt: Date()))
        newMessage = ""
    }

    private func loadRelatedOrderProduct() async {
        guard let orderId, !orderId.isEmpty else { return }
        await MainActor.run {
            isLoadingHeaderProduct = true
            productHeaderError = nil
        }

        userService.updateAuthToken(authService.authToken)
        productService.updateAuthToken(authService.authToken)

        do {
            async let sellerOrdersTask = userService.getUserOrders(isSeller: true)
            async let buyerOrdersTask = userService.getUserOrders(isSeller: false)
            let (sellerOrders, buyerOrders) = try await (sellerOrdersTask, buyerOrdersTask)
            let allOrders = sellerOrders.orders + buyerOrders.orders
            guard let matchedOrder = allOrders.first(where: { $0.id == orderId }),
                  let firstOrderProduct = matchedOrder.products.first else {
                await MainActor.run {
                    isLoadingHeaderProduct = false
                    productHeaderError = "Related product unavailable"
                }
                return
            }
            guard let pid = Int(firstOrderProduct.id) else {
                await MainActor.run {
                    isLoadingHeaderProduct = false
                    productHeaderError = "Related product unavailable"
                }
                return
            }
            let product = try await productService.getProduct(id: pid)
            await MainActor.run {
                relatedProductId = pid
                relatedItem = product
                isLoadingHeaderProduct = false
                if relatedItem == nil {
                    productHeaderError = "Related product unavailable"
                }
            }
        } catch {
            await MainActor.run {
                isLoadingHeaderProduct = false
                productHeaderError = "Could not load related product"
            }
        }
    }
}

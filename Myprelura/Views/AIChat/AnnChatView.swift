import SwiftUI

/// Support chat with Ann: customer support and order issues. Loads user's orders (placed + sold), injects context for Ann, shows order slider when relevant; tap order for details and "what issue?" sheet.
struct AnnChatView: View {
    @EnvironmentObject var authService: AuthService
    @StateObject private var viewModel = HomeViewModel()

    @State private var messages: [ChatMessage] = []
    @State private var inputText: String = ""
    @FocusState private var isInputFocused: Bool
    @State private var isBotThinking: Bool = false

    @State private var soldOrders: [Order] = []
    @State private var boughtOrders: [Order] = []
    @State private var ordersLoaded: Bool = false
    @State private var selectedOrderForHelp: OrderContext?

    private let openAI = OpenAIService.shared
    private let userService = UserService()

    private static let conversationStarters: [String] = [
        "I need help with an order.",
        "When will I get my refund?",
        "How do I cancel my order?",
        "My item says delivered but I don't have it.",
        "I'd like to check my order status."
    ]

    var body: some View {
        VStack(spacing: 0) {
            messageList
            inputBar
        }
        .background(Theme.Colors.background)
        .navigationTitle("Ann")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task { await loadOrdersIfNeeded() }
        .sheet(item: $selectedOrderForHelp) { ctx in
            AnnOrderHelpSheet(
                order: ctx.order,
                isSeller: ctx.isSeller,
                onSend: { issueText in
                    selectedOrderForHelp = nil
                    submitOrderIssue(orderContext: ctx, issueText: issueText)
                },
                onViewFullOrder: {
                    selectedOrderForHelp = nil
                }
            )
        }
    }

    private var messageList: some View {
        Group {
            if messages.isEmpty {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    VStack(spacing: Theme.Spacing.lg) {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(Theme.primaryColor.opacity(0.6))
                        Text("Welcome to support — I'm Ann. Ask about orders, refunds, or anything else. How can I help?")
                            .font(Theme.Typography.body)
                            .foregroundColor(Theme.Colors.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, Theme.Spacing.xl)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                                ChatBubbleView(
                                    message: message,
                                    isLastMessage: index == messages.count - 1,
                                    viewModel: viewModel,
                                    onOrderTapped: { order, isSeller in
                                        selectedOrderForHelp = OrderContext(order: order, isSeller: isSeller)
                                    }
                                )
                            }
                            if isBotThinking {
                                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                                    TypingIndicatorView()
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, Theme.Spacing.md)
                                .padding(.vertical, Theme.Spacing.sm)
                                .id("typing")
                            }
                        }
                        .padding(.vertical, Theme.Spacing.md)
                    }
                    .onChange(of: messages.count) { _, _ in
                        withAnimation(.easeOut(duration: 0.2)) {
                            if isBotThinking {
                                proxy.scrollTo("typing", anchor: .bottom)
                            } else if let last = messages.last?.id {
                                proxy.scrollTo(last, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: isBotThinking) { _, thinking in
                        if thinking {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo("typing", anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var inputBar: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.sm) {
            ZStack(alignment: .leading) {
                TextField(placeholderForInputBar, text: $inputText, axis: .vertical)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.primaryText)
                    .focused($isInputFocused)
                    .lineLimit(1...6)
                    .padding(Theme.Spacing.md)
                    .background(Theme.Colors.secondaryBackground)
                    .cornerRadius(30)
                    .overlay(
                        RoundedRectangle(cornerRadius: 30)
                            .stroke(isInputFocused ? Theme.primaryColor : Color.clear, lineWidth: 2)
                    )
                if messages.isEmpty && inputText.isEmpty {
                    ConversationStarterOverlay(
                        starters: Self.conversationStarters,
                        onTap: { isInputFocused = true }
                    )
                }
            }
            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(canSend ? Theme.primaryColor : Theme.Colors.secondaryText)
            }
            .disabled(!canSend || isBotThinking)
            .buttonStyle(HapticTapButtonStyle(haptic: { HapticManager.primaryAction() }))
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.background)
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Theme.Colors.glassBorder),
            alignment: .top
        )
    }

    private var placeholderForInputBar: String {
        (messages.isEmpty && inputText.isEmpty) ? "" : L10n.string("Type a message...")
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendMessage() {
        let raw = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, !isBotThinking else { return }

        let userMessage = ChatMessage(isFromUser: true, text: raw)
        messages.append(userMessage)
        inputText = ""
        isBotThinking = true

        Task {
            await respondToUserMessage(raw)
            await MainActor.run { isBotThinking = false }
        }
    }

    private func respondToUserMessage(_ raw: String) async {
        let thinkingStart = Date()
        let minThinkingSeconds = Double.random(in: 1.0...2.5)
        let conversationHistory = buildConversationHistory()
        let orderContextString = buildOrderContextForAnn()

        let openAIReply = openAI.isConfigured
            ? await openAI.reply(userMessage: raw, conversationHistory: conversationHistory, assistant: .ann, orderContext: orderContextString)
            : nil
        let replyText = openAIReply ?? "I'm Ann, here to help with orders and support. What would you like to know?"

        await ensureMinThinkingTime(since: thinkingStart, minSeconds: minThinkingSeconds)
        let showOrderSlider = isOrderRelatedMessage(raw) && !allOrderContexts.isEmpty
        await MainActor.run {
            messages.append(ChatMessage(
                isFromUser: false,
                text: replyText,
                items: nil,
                orders: showOrderSlider ? allOrderContexts : nil
            ))
        }
    }

    private var allOrderContexts: [OrderContext] {
        let sold = soldOrders.map { OrderContext(order: $0, isSeller: true) }
        let bought = boughtOrders.map { OrderContext(order: $0, isSeller: false) }
        return sold + bought
    }

    private func loadOrdersIfNeeded() async {
        guard !authService.isGuestMode, !ordersLoaded else { return }
        userService.updateAuthToken(authService.authToken)
        do {
            async let soldTask = userService.getUserOrders(isSeller: true)
            async let boughtTask = userService.getUserOrders(isSeller: false)
            let (soldResult, boughtResult) = try await (soldTask, boughtTask)
            await MainActor.run {
                soldOrders = soldResult.orders
                boughtOrders = boughtResult.orders
                ordersLoaded = true
            }
        } catch {
            await MainActor.run { ordersLoaded = true }
        }
    }

    private func buildOrderContextForAnn() -> String? {
        guard ordersLoaded else { return nil }
        if soldOrders.isEmpty && boughtOrders.isEmpty { return "The user has no orders yet." }
        var lines: [String] = ["The user's orders (the app may show them below). Do not invent order IDs or details."]
        if !boughtOrders.isEmpty {
            lines.append("Orders they placed (as buyer): " + boughtOrders.prefix(15).map { " \($0.displayOrderId) \($0.status) £\($0.priceTotal)" }.joined(separator: "; "))
        }
        if !soldOrders.isEmpty {
            lines.append("Orders they sold (as seller): " + soldOrders.prefix(15).map { " \($0.displayOrderId) \($0.status) £\($0.priceTotal)" }.joined(separator: "; "))
        }
        return lines.joined(separator: "\n")
    }

    private func isOrderRelatedMessage(_ text: String) -> Bool {
        let lower = text.lowercased()
        let tokens = ["order", "orders", "refund", "cancel", "delivery", "shipped", "issue", "problem", "help", "status", "tracking", "bought", "sold"]
        return tokens.contains { lower.contains($0) }
    }

    private func submitOrderIssue(orderContext: OrderContext, issueText: String) {
        let trimmed = issueText.trimmingCharacters(in: .whitespacesAndNewlines)
        let userMessageText = trimmed.isEmpty
            ? "I need help with order \(orderContext.order.displayOrderId)."
            : "\(orderContext.order.displayOrderId): \(trimmed)"
        let userMessage = ChatMessage(isFromUser: true, text: userMessageText)
        messages.append(userMessage)
        isBotThinking = true
        Task {
            await respondToUserMessage(userMessageText)
            await MainActor.run { isBotThinking = false }
        }
    }

    private func ensureMinThinkingTime(since: Date, minSeconds: Double) async {
        let elapsed = Date().timeIntervalSince(since)
        if elapsed < minSeconds {
            try? await Task.sleep(nanoseconds: UInt64((minSeconds - elapsed) * 1_000_000_000))
        }
    }

    private func buildConversationHistory() -> [(user: String, assistant: String)] {
        var pairs: [(user: String, assistant: String)] = []
        var i = 0
        while i < messages.count {
            guard messages[i].isFromUser else { i += 1; continue }
            let userText = messages[i].text
            i += 1
            if i < messages.count, !messages[i].isFromUser {
                pairs.append((userText, messages[i].text))
                i += 1
            }
        }
        let maxPairs = 5
        if pairs.count <= maxPairs { return pairs }
        return Array(pairs.suffix(maxPairs))
    }
}

// MARK: - Order help sheet (tap order in Ann chat: show date, ask what issue, send to Ann)
private struct AnnOrderHelpSheet: View {
    let order: Order
    let isSeller: Bool
    var onSend: (String) -> Void
    var onViewFullOrder: () -> Void

    @EnvironmentObject private var authService: AuthService
    @State private var issueText: String = ""
    @Environment(\.dismiss) private var dismiss

    private var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }

    private var statusDisplay: String {
        switch order.status {
        case "CONFIRMED": return "Confirmed"
        case "SHIPPED": return "Shipped"
        case "DELIVERED": return "Completed"
        case "CANCELLED": return "Cancelled"
        case "REFUNDED": return "Refunded"
        default: return order.status
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    Text("Order \(order.displayOrderId)")
                        .font(Theme.Typography.headline)
                        .foregroundColor(Theme.Colors.primaryText)
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("Placed \(dateFormatter.string(from: order.createdAt))")
                            .font(Theme.Typography.body)
                            .foregroundColor(Theme.Colors.secondaryText)
                        Text("Status: \(statusDisplay)")
                            .font(Theme.Typography.body)
                            .foregroundColor(Theme.Colors.primaryText)
                        Text("£\(order.priceTotal)")
                            .font(Theme.Typography.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(Theme.Colors.primaryText)
                    }
                    .padding(Theme.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.Colors.secondaryBackground)
                    .cornerRadius(Theme.Glass.cornerRadius)

                    Text("What issue are you having?")
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.primaryText)
                    TextField("Describe the issue (optional)", text: $issueText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...6)

                    Button {
                        dismiss()
                        onSend(issueText)
                    } label: {
                        Text("Send to Ann")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.Spacing.sm)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.primaryColor)

                    NavigationLink(destination: OrderDetailView(order: order, isSeller: isSeller)) {
                        HStack {
                            Image(systemName: "doc.text")
                            Text("View full order details")
                        }
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.primaryColor)
                    }
                    .padding(.top, Theme.Spacing.sm)
                }
                .padding(Theme.Spacing.md)
            }
            .background(Theme.Colors.background)
            .navigationTitle("Order help")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        onViewFullOrder()
                        dismiss()
                    }
                }
            }
        }
    }
}

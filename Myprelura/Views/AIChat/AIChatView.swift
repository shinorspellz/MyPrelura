import SwiftUI
import PhotosUI

// MARK: - Chat message model

/// Pairs an order with role so Ann can show "placed" vs "sold" and open OrderDetailView with correct isSeller.
struct OrderContext: Identifiable {
    let order: Order
    let isSeller: Bool
    var id: String { order.id }
}

struct ChatMessage: Identifiable {
    let id: UUID
    let isFromUser: Bool
    let text: String
    var items: [Item]?
    var orders: [OrderContext]?
    init(id: UUID = UUID(), isFromUser: Bool, text: String, items: [Item]? = nil, orders: [OrderContext]? = nil) {
        self.id = id
        self.isFromUser = isFromUser
        self.text = text
        self.items = items
        self.orders = orders
    }
}


// MARK: - AI Chat View (conversational chatbot)

/// Dedicated AI chat: standard pushed page with Lenny welcome placeholder, then Messages-style bubbles and input.
struct AIChatView: View {
    @EnvironmentObject var authService: AuthService
    @ObservedObject var viewModel: HomeViewModel

    @State private var messages: [ChatMessage] = []
    @State private var inputText: String = ""
    @FocusState private var isInputFocused: Bool
    @State private var isBotThinking: Bool = false
    /// Full-sentence prompts so users are encouraged to type naturally, not just keywords.
    private static let conversationStarters: [String] = [
        "I'm looking for a navy blazer.",
        "Do you have a floral dress under £30?",
        "I need a pink skirt for a wedding.",
        "Have you got a black jacket?",
        "I'm after a green hoodie.",
        "Looking for white trainers.",
        "Any denim jeans in size 10?",
        "Do you have a leather bag?",
        "I want a striped top.",
        "I need a wool coat for winter."
    ]

    private let aiSearch = AISearchService()
    private let productService = ProductService()
    private let openAI = OpenAIService.shared
    private let pageSize = 20

    var body: some View {
        VStack(spacing: 0) {
            messageList
            inputBar
        }
        .background(Theme.Colors.background)
        .navigationTitle("Lenny")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            productService.updateAuthToken(authService.authToken)
        }
    }

    private var messageList: some View {
        Group {
            if messages.isEmpty {
                // Placeholder centered in the middle of the page (above input bar).
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    VStack(spacing: Theme.Spacing.lg) {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(Theme.primaryColor.opacity(0.6))
                        Text(L10n.string("Welcome to the chat, I'm Lenny, and I'm here to assist you. Send a message to get started."))
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
                                    viewModel: viewModel
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

    /// Messages-style input: same padding and style as ChatDetailView (taller field). Before first message, shows animated conversation starters in the field.
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

    /// When the overlay is showing (empty chat, no text), use no placeholder so only the animated prompt is visible.
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
        let minThinkingSeconds = Double.random(in: 1.0...3.0)
        let conversationHistory = buildConversationHistory()

        if aiSearch.isGreetingOnly(raw) {
            let openAIReply = openAI.isConfigured ? await openAI.reply(userMessage: raw, conversationHistory: conversationHistory) : nil
            await ensureMinThinkingTime(since: thinkingStart, minSeconds: minThinkingSeconds)
            await MainActor.run {
                let text = openAIReply ?? L10n.string(aiSearch.randomGreetingReply())
                messages.append(ChatMessage(isFromUser: false, text: text, items: []))
            }
            return
        }

        // When OpenAI is not configured, fall back to parser-based search (original behavior).
        if !openAI.isConfigured {
            await respondWithParserOnly(raw: raw, thinkingStart: thinkingStart, minThinkingSeconds: minThinkingSeconds)
            return
        }

        // OpenAI decides when to show products: only when the reply contains [SEARCH: query].
        let openAIReply = await openAI.reply(userMessage: raw, conversationHistory: conversationHistory)
        let (displayText, searchQuery) = Self.parseSearchDirective(from: openAIReply ?? "")

        if let query = searchQuery, !query.trimmingCharacters(in: .whitespaces).isEmpty {
            // Run product search only when OpenAI asked for it via [SEARCH: ...].
            let parsed = aiSearch.parse(query: query)
            do {
                let visible = try await fetchProductsForParsed(parsed)
                await ensureMinThinkingTime(since: thinkingStart, minSeconds: minThinkingSeconds)
                await MainActor.run {
                    messages.append(ChatMessage(isFromUser: false, text: displayText, items: visible))
                }
            } catch {
                await ensureMinThinkingTime(since: thinkingStart, minSeconds: minThinkingSeconds)
                await MainActor.run {
                    let text = displayText.isEmpty ? L10n.string("Something went wrong. Please try again.") : displayText
                    messages.append(ChatMessage(isFromUser: false, text: text))
                }
            }
        } else {
            // No [SEARCH: ...]: show only the reply, no products.
            await ensureMinThinkingTime(since: thinkingStart, minSeconds: minThinkingSeconds)
            await MainActor.run {
                let text = displayText.isEmpty ? L10n.string(AISearchService.randomOutOfScopeReply()) : displayText
                messages.append(ChatMessage(isFromUser: false, text: text, items: []))
            }
        }
    }

    /// Fallback when OpenAI is not configured: use parser to decide when to search (original behavior).
    private func respondWithParserOnly(raw: String, thinkingStart: Date, minThinkingSeconds: Double) async {
        let parsed = aiSearch.parse(query: raw)
        let inScope = isParsedInScope(parsed)
        let shouldRunSearch = hasProductIntent(parsed)
        if inScope && shouldRunSearch {
            do {
                let visible = try await fetchProductsForParsed(parsed)
                let ruleBasedReply = visible.isEmpty ? aiSearch.replyForNoResults() : aiSearch.replyForResults(parsed: parsed, hasItems: true, query: raw)
                await ensureMinThinkingTime(since: thinkingStart, minSeconds: minThinkingSeconds)
                await MainActor.run {
                    messages.append(ChatMessage(isFromUser: false, text: ruleBasedReply, items: visible))
                }
            } catch {
                await ensureMinThinkingTime(since: thinkingStart, minSeconds: minThinkingSeconds)
                await MainActor.run {
                    messages.append(ChatMessage(isFromUser: false, text: L10n.string("Something went wrong. Please try again."), items: nil))
                }
            }
        } else if inScope && !shouldRunSearch {
            await ensureMinThinkingTime(since: thinkingStart, minSeconds: minThinkingSeconds)
            await MainActor.run {
                messages.append(ChatMessage(isFromUser: false, text: L10n.string(AISearchService.replyWhenNeedMoreDetail()), items: []))
            }
        } else {
            await ensureMinThinkingTime(since: thinkingStart, minSeconds: minThinkingSeconds)
            await MainActor.run {
                messages.append(ChatMessage(isFromUser: false, text: L10n.string(AISearchService.randomOutOfScopeReply()), items: []))
            }
        }
    }

    /// Parses OpenAI reply for [SEARCH: query]. Returns (displayText, searchQuery). Display text has the [SEARCH: ...] line removed.
    private static func parseSearchDirective(from reply: String) -> (displayText: String, searchQuery: String?) {
        let pattern = #"\[SEARCH:\s*([^\]]*)\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: reply, range: NSRange(reply.startIndex..., in: reply)) else {
            return (reply.trimmingCharacters(in: .whitespacesAndNewlines), nil)
        }
        let fullRange = Range(match.range, in: reply)!
        let captureRange = Range(match.range(at: 1), in: reply)!
        let query = String(reply[captureRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        var display = reply
        display.removeSubrange(fullRange)
        display = display.trimmingCharacters(in: .whitespacesAndNewlines)
        if display.hasSuffix("\n") { display = String(display.dropLast()) }
        display = display.trimmingCharacters(in: .whitespacesAndNewlines)
        return (display, query.isEmpty ? nil : query)
    }

    /// Fetches and filters products for the given parsed query (same logic as before, returns items or empty).
    private func fetchProductsForParsed(_ parsed: ParsedSearch) async throws -> [Item] {
        let categoryFilter = (parsed.categoryOverride == nil || parsed.categoryOverride == "All") ? nil : parsed.categoryOverride
        let colourSet = Set(parsed.appliedColourNames.map { $0.lowercased() })
        let useBroadSearch = !parsed.appliedColourNames.isEmpty
        let useSizeFilter = parsed.sizeTerm != nil
        let fetchCount: Int
        if useBroadSearch { fetchCount = 50 }
        else if useSizeFilter { fetchCount = 80 }
        else { fetchCount = pageSize }

        let candidates = parsed.searchQueryCandidates.isEmpty
            ? (parsed.searchText.isEmpty ? [""] : [parsed.searchText])
            : parsed.searchQueryCandidates
        var visible: [Item] = []
        for (index, candidate) in candidates.enumerated() {
            let searchForApi: String?
            if useBroadSearch {
                let withoutColour = candidate
                    .split(separator: " ")
                    .map(String.init)
                    .filter { !colourSet.contains($0.lowercased()) }
                    .joined(separator: " ")
                searchForApi = withoutColour.isEmpty ? nil : withoutColour
            } else {
                searchForApi = candidate.isEmpty ? nil : candidate
            }
            let products = try await productService.getAllProducts(
                pageNumber: 1,
                pageCount: fetchCount,
                search: searchForApi,
                parentCategory: categoryFilter,
                maxPrice: parsed.priceMax
            )
            var filtered = products.excludingVacationModeSellers()
            if useBroadSearch && !parsed.appliedColourNames.isEmpty {
                filtered = filtered.filter { item in
                    item.colors.contains { c in
                        parsed.appliedColourNames.contains { $0.caseInsensitiveCompare(c) == .orderedSame }
                    }
                }
                if filtered.isEmpty && index == 0 {
                    let fullQueryProducts = try await productService.getAllProducts(
                        pageNumber: 1,
                        pageCount: pageSize,
                        search: parsed.searchText.isEmpty ? nil : parsed.searchText,
                        parentCategory: categoryFilter,
                        maxPrice: parsed.priceMax
                    )
                    filtered = fullQueryProducts.excludingVacationModeSellers()
                }
            }
            if let sizeTerm = parsed.sizeTerm, !filtered.isEmpty {
                let term = sizeTerm.lowercased()
                let sizeFiltered = filtered.filter { item in
                    guard let s = item.size?.lowercased().trimmingCharacters(in: .whitespaces), !s.isEmpty else { return false }
                    if s == term { return true }
                    let normalized = s.replacingOccurrences(of: " ", with: "")
                    if normalized == term { return true }
                    let parts = s.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
                    if parts.contains(term) { return true }
                    return s.contains(term) && (s.hasPrefix(term + " ") || s.hasSuffix(" " + term) || s.contains(" " + term + " "))
                }
                if !sizeFiltered.isEmpty { filtered = sizeFiltered }
            }
            if !filtered.isEmpty {
                visible = filtered
                break
            }
        }
        return visible
    }

    /// True when we have enough to run product search: a category or a product-type term (not just colours).
    private func hasProductIntent(_ parsed: ParsedSearch) -> Bool {
        if let cat = parsed.categoryOverride, !cat.isEmpty, cat != "All" { return true }
        let trimmed = parsed.searchText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        let words = trimmed.split(separator: " ").map(String.init)
        let colourSet = Set(parsed.appliedColourNames.map { $0.lowercased() })
        return words.contains { !colourSet.contains($0.lowercased()) }
    }

    /// Last few user/assistant pairs for OpenAI context (max 5 pairs).
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

    /// Ensures at least minSeconds have passed since `since` before returning (shows "thinking" for a natural 1–3 seconds).
    private func ensureMinThinkingTime(since: Date, minSeconds: Double) async {
        let elapsed = Date().timeIntervalSince(since)
        if elapsed < minSeconds {
            try? await Task.sleep(nanoseconds: UInt64((minSeconds - elapsed) * 1_000_000_000))
        }
    }

    private func isParsedInScope(_ parsed: ParsedSearch) -> Bool {
        if !parsed.searchText.trimmingCharacters(in: .whitespaces).isEmpty { return true }
        if let cat = parsed.categoryOverride, !cat.isEmpty, cat != "All" { return true }
        if !parsed.appliedColourNames.isEmpty { return true }
        if parsed.priceMax != nil { return true }
        return false
    }
}

// MARK: - Chat bubble (user vs bot, optional product grid)

struct ChatBubbleView: View {
    let message: ChatMessage
    let isLastMessage: Bool
    @ObservedObject var viewModel: HomeViewModel
    /// When set (e.g. Ann), tapping an order calls this instead of navigating; use to show help sheet.
    var onOrderTapped: ((Order, Bool) -> Void)? = nil
    @EnvironmentObject private var authService: AuthService
    @State private var showGuestSignInPrompt: Bool = false

    /// Typewriter effect for bot messages: only animates when this message is the last (newly added).
    @State private var visibleCharCount: Int = 0
    private let typewriterIntervalNs: UInt64 = 28_000_000 // 28ms per character

    private func runTypewriter() {
        let fullCount = message.text.count
        guard fullCount > 0 else { return }
        Task { @MainActor in
            for i in 1...fullCount {
                try? await Task.sleep(nanoseconds: typewriterIntervalNs)
                visibleCharCount = i
            }
        }
    }

    private var displayedText: String {
        if message.isFromUser { return message.text }
        if isLastMessage { return String(message.text.prefix(visibleCharCount)) }
        return message.text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                if message.isFromUser { Spacer(minLength: 60) }
                Text(displayedText)
                    .font(Theme.Typography.body)
                    .foregroundColor(message.isFromUser ? .white : Theme.Colors.primaryText)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(message.isFromUser ? Theme.primaryColor : Theme.Colors.secondaryBackground)
                    )
                    .frame(maxWidth: 280, alignment: message.isFromUser ? .trailing : .leading)
                if !message.isFromUser { Spacer(minLength: 60) }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .onAppear {
                if !message.isFromUser && isLastMessage && visibleCharCount < message.text.count {
                    runTypewriter()
                } else if !message.isFromUser && !isLastMessage {
                    visibleCharCount = message.text.count
                }
            }
            .onChange(of: isLastMessage) { _, new in
                if !new { visibleCharCount = message.text.count }
            }

            if let items = message.items, !items.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Rectangle()
                        .fill(Theme.Colors.glassBorder)
                        .frame(height: 0.5)
                        .padding(.horizontal, Theme.Spacing.md)
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: Theme.Spacing.sm) {
                                ForEach(Array(items.prefix(20))) { item in
                                    NavigationLink(destination: ItemDetailView(item: item, authService: authService)) {
                                        HomeItemCard(item: item, onLikeTap: {
                                if authService.isGuestMode { showGuestSignInPrompt = true }
                                else { viewModel.toggleLike(productId: item.productId ?? "") }
                            })
                                            .frame(width: 140, alignment: .topLeading)
                                    }
                                    .buttonStyle(PlainTappableButtonStyle())
                                }
                            }
                            .padding(.horizontal, Theme.Spacing.md)
                        }
                        .frame(maxWidth: .infinity)
                        if items.count >= 3 {
                            NavigationLink(destination: AIResultsView(items: items, viewModel: viewModel)) {
                                Text(L10n.string("See All"))
                                    .font(Theme.Typography.subheadline)
                                    .foregroundColor(Theme.primaryColor)
                            }
                            .buttonStyle(HapticTapButtonStyle())
                            .padding(.leading, Theme.Spacing.md)
                            .padding(.top, Theme.Spacing.xs)
                        }
                    }
                    .padding(.vertical, Theme.Spacing.md)
                    Rectangle()
                        .fill(Theme.Colors.glassBorder)
                        .frame(height: 0.5)
                        .padding(.horizontal, Theme.Spacing.md)
                }
                .padding(.top, Theme.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let orders = message.orders, !orders.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Rectangle()
                        .fill(Theme.Colors.glassBorder)
                        .frame(height: 0.5)
                        .padding(.horizontal, Theme.Spacing.md)
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: Theme.Spacing.sm) {
                                ForEach(Array(orders.prefix(20))) { ctx in
                                    if let onTap = onOrderTapped {
                                        Button {
                                            onTap(ctx.order, ctx.isSeller)
                                        } label: {
                                            OrderSliderCard(order: ctx.order, isSeller: ctx.isSeller)
                                                .frame(width: 160, alignment: .topLeading)
                                        }
                                        .buttonStyle(PlainTappableButtonStyle())
                                    } else {
                                        NavigationLink(destination: OrderDetailView(order: ctx.order, isSeller: ctx.isSeller)) {
                                            OrderSliderCard(order: ctx.order, isSeller: ctx.isSeller)
                                                .frame(width: 160, alignment: .topLeading)
                                        }
                                        .buttonStyle(PlainTappableButtonStyle())
                                    }
                                }
                            }
                            .padding(.horizontal, Theme.Spacing.md)
                        }
                        .frame(maxWidth: .infinity)
                        if orders.count >= 3 {
                            NavigationLink(destination: MyOrdersView()) {
                                Text(L10n.string("See All"))
                                    .font(Theme.Typography.subheadline)
                                    .foregroundColor(Theme.primaryColor)
                            }
                            .buttonStyle(HapticTapButtonStyle())
                            .padding(.leading, Theme.Spacing.md)
                            .padding(.top, Theme.Spacing.xs)
                        }
                    }
                    .padding(.vertical, Theme.Spacing.md)
                    Rectangle()
                        .fill(Theme.Colors.glassBorder)
                        .frame(height: 0.5)
                        .padding(.horizontal, Theme.Spacing.md)
                }
                .padding(.top, Theme.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .id(message.id)
        .fullScreenCover(isPresented: $showGuestSignInPrompt) {
            GuestSignInPromptView()
        }
    }
}

// MARK: - Order slider card (compact order card for Ann support chat)
private struct OrderSliderCard: View {
    let order: Order
    /// When set, show "Sold" or "Bought" badge so user knows context.
    var isSeller: Bool? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            orderImage
            if isSeller != nil {
                Text(isSeller == true ? "Sold" : "Bought")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.Colors.secondaryText)
            }
            Text(order.products.first?.name ?? "Order")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.primaryText)
                .lineLimit(1)
            Text("£\(order.priceTotal)")
                .font(Theme.Typography.subheadline)
                .fontWeight(.medium)
                .foregroundColor(Theme.Colors.primaryText)
            Text(orderStatusDisplay(order.status))
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.secondaryText)
        }
        .padding(Theme.Spacing.sm)
        .background(Theme.Colors.secondaryBackground)
        .cornerRadius(Theme.Glass.cornerRadius)
    }

    private var orderImage: some View {
        Group {
            if let url = order.products.first?.imageUrl, !url.isEmpty {
                AsyncImage(url: URL(string: url)) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    default: Rectangle().fill(Theme.Colors.tertiaryBackground)
                    }
                }
            } else {
                Rectangle()
                    .fill(Theme.Colors.tertiaryBackground)
                    .overlay(Image(systemName: "bag").foregroundColor(Theme.Colors.secondaryText))
            }
        }
        .frame(width: 140, height: 100)
        .clipped()
        .cornerRadius(8)
    }

    private func orderStatusDisplay(_ status: String) -> String {
        switch status {
        case "CONFIRMED": return "Confirmed"
        case "SHIPPED": return "Shipped"
        case "DELIVERED": return "Completed"
        case "CANCELLED": return "Cancelled"
        case "REFUNDED": return "Refunded"
        default: return status
        }
    }
}

// MARK: - AI Results (full-page results from AI, no search)

struct AIResultsView: View {
    let items: [Item]
    @ObservedObject var viewModel: HomeViewModel
    @EnvironmentObject private var authService: AuthService
    @State private var showGuestSignInPrompt: Bool = false

    private let columns = [
        GridItem(.flexible(), spacing: Theme.Spacing.sm),
        GridItem(.flexible(), spacing: Theme.Spacing.sm)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.Spacing.md) {
                ForEach(items) { item in
                    NavigationLink(destination: ItemDetailView(item: item, authService: authService)) {
                        HomeItemCard(item: item, onLikeTap: {
                                if authService.isGuestMode { showGuestSignInPrompt = true }
                                else { viewModel.toggleLike(productId: item.productId ?? "") }
                            })
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .buttonStyle(PlainTappableButtonStyle())
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.md)
        }
        .background(Theme.Colors.background)
        .navigationTitle(L10n.string("Results"))
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showGuestSignInPrompt) {
            GuestSignInPromptView()
        }
    }
}

// MARK: - Conversation starter overlay (animated cycling suggestions before first message)

struct ConversationStarterOverlay: View {
    let starters: [String]
    var onTap: () -> Void

    @State private var currentIndex: Int = 0
    @State private var opacity: Double = 1
    private let cycleInterval: Double = 2.8
    private let fadeDuration: Double = 0.35

    var body: some View {
        let starter = starters.isEmpty ? "Type a message..." : starters[currentIndex % starters.count]
        Text(starter)
            .font(Theme.Typography.body)
            .foregroundColor(Theme.Colors.secondaryText.opacity(0.9))
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .opacity(opacity)
            .task {
                guard !starters.isEmpty else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: UInt64(cycleInterval * 1_000_000_000))
                    if Task.isCancelled { break }
                    await MainActor.run {
                        withAnimation(.easeInOut(duration: fadeDuration)) { opacity = 0 }
                    }
                    try? await Task.sleep(nanoseconds: UInt64(fadeDuration * 1_000_000_000))
                    if Task.isCancelled { break }
                    await MainActor.run {
                        currentIndex = (currentIndex + 1) % starters.count
                        withAnimation(.easeInOut(duration: fadeDuration)) { opacity = 1 }
                    }
                }
            }
    }
}

// MARK: - Typing indicator (animated bouncing dots)

struct TypingIndicatorView: View {
    private let dotCount = 3
    private let dotSize: CGFloat = 8
    private let period: Double = 1.2

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.05, paused: false)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack(spacing: 6) {
                    ForEach(0..<dotCount, id: \.self) { i in
                        let phase = (t / period + Double(i) * 0.22).truncatingRemainder(dividingBy: 1)
                        let scale = 0.65 + 0.5 * sin(phase * .pi * 2)
                        Circle()
                            .fill(Theme.primaryColor.opacity(0.9))
                            .frame(width: dotSize, height: dotSize)
                            .scaleEffect(scale)
                    }
                }
                Text(L10n.string("Thinking..."))
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.secondaryText)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Theme.Colors.secondaryBackground)
        )
    }
}
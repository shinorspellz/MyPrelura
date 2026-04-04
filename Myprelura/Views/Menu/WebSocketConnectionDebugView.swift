import SwiftUI

/// Dedicated socket test view: manually connect to a conversation socket and inspect connection/errors/events.
struct WebSocketConnectionDebugView: View {
    @EnvironmentObject private var authService: AuthService
    @StateObject private var chatService = ChatService()
    @State private var conversations: [Conversation] = []
    @State private var selectedConversationId: String?
    @State private var loadingConversations = false
    @State private var conversationId: String = ""
    @State private var outboundText: String = ""
    @State private var connected = false
    @State private var lastError: String?
    @State private var events: [String] = []
    @State private var socket: ChatWebSocketService?
    @State private var typingFeedbackStatus: String = "Idle"
    @State private var typingFeedbackIsError = false
    @State private var typingFeedbackTask: Task<Void, Never>?

    var body: some View {
        List {
            Section {
                Button(loadingConversations ? "Refreshing…" : "Refresh conversations") {
                    Task { await loadConversations() }
                }
                .disabled(loadingConversations || socketAuthToken == nil)
                if conversations.isEmpty {
                    Text("No conversations loaded yet.")
                        .font(.caption)
                        .foregroundColor(Theme.Colors.secondaryText)
                } else {
                    ForEach(conversations, id: \.id) { c in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(PreluraSupportBranding.displayTitle(forRecipientUsername: c.recipient.username))
                                    .font(.subheadline.weight(.semibold))
                                Text("conv id: \(c.id)")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.Colors.secondaryText)
                            }
                            Spacer()
                            if selectedConversationId == c.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.green)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedConversationId = c.id
                            conversationId = c.id
                        }
                    }
                }
                TextField("Conversation ID", text: $conversationId)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                HStack(spacing: Theme.Spacing.sm) {
                    Button("Connect") { connect(conversationId) }
                        .disabled(conversationId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || socketAuthToken == nil)
                    Button("Connect selected") {
                        guard let selectedConversationId else { return }
                        connect(selectedConversationId)
                    }
                        .disabled((selectedConversationId ?? "").isEmpty || socketAuthToken == nil)
                    Button("Disconnect", role: .destructive) {
                        socket?.disconnect()
                        socket = nil
                    }
                }
                LabeledContent("State") {
                    Text(connected ? "Connected" : "Disconnected")
                        .foregroundColor(connected ? .green : Theme.Colors.secondaryText)
                }
                if let lastError, !lastError.isEmpty {
                    Text(lastError)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            } header: {
                Text("Connection")
            } footer: {
                Text("Pick a real conversation and connect. If this still says disconnected after selecting a conversation, it is a real socket failure.")
            }

            Section {
                TextField("Send message text", text: $outboundText)
                    .textInputAutocapitalization(.sentences)
                    .onChange(of: outboundText) { _, newValue in
                        handleTypingChange(newValue)
                    }
                HStack {
                    Text("WebSocket")
                        .foregroundColor(Theme.Colors.secondaryText)
                    Spacer()
                    Text(connected ? "Connected" : "Disconnected")
                        .foregroundColor(connected ? .green : .red)
                        .font(.caption)
                }
                HStack {
                    Text("Typing feedback")
                        .foregroundColor(Theme.Colors.secondaryText)
                    Spacer()
                    Text(typingFeedbackStatus)
                        .foregroundColor(typingFeedbackIsError ? .red : .green)
                        .font(.caption)
                }
                Button("Send over socket") { sendProbeMessage() }
                    .disabled(!connected || outboundText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } header: {
                Text("Send test")
            } footer: {
                Text("As you type, this sends typing events. If no socket typing feedback arrives quickly, this view marks it as an error.")
            }

            Section {
                if events.isEmpty {
                    Text("No socket events yet.")
                        .font(.caption)
                        .foregroundColor(Theme.Colors.secondaryText)
                } else {
                    ForEach(Array(events.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.caption)
                            .textSelection(.enabled)
                    }
                }
                Button("Clear log", role: .destructive) {
                    events.removeAll()
                }
            } header: {
                Text("Event log")
            }
        }
        .listStyle(.insetGrouped)
        .background(Theme.Colors.background)
        .navigationTitle("WebSocket test")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            chatService.updateAuthToken(authService.authToken)
            await loadConversations()
        }
        .onChange(of: authService.authToken) { _, newValue in
            chatService.updateAuthToken(newValue)
        }
        .onDisappear {
            typingFeedbackTask?.cancel()
            socket?.disconnect()
            socket = nil
        }
    }

    private func connect(_ rawConversationId: String) {
        let conv = rawConversationId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let token = socketAuthToken, !conv.isEmpty else {
            lastError = "Missing socket auth token (refresh token not available)"
            return
        }
        socket?.disconnect()
        lastError = nil
        append("Connecting to conv=\(conv)")
        let ws = ChatWebSocketService(conversationId: conv, token: token)
        ws.onConnectionStateChanged = { isConnected in
            connected = isConnected
            if !isConnected {
                typingFeedbackStatus = "Socket disconnected"
                typingFeedbackIsError = true
            }
            append(isConnected ? "CONNECTED" : "DISCONNECTED")
        }
        ws.onDisconnectReason = { reason in
            lastError = reason
            append("DISCONNECT_REASON: \(reason)")
        }
        ws.onTypingEvent = { event in
            typingFeedbackTask?.cancel()
            typingFeedbackStatus = "Feedback received (\(event.isTyping ? "typing" : "not typing"))"
            typingFeedbackIsError = false
            append("TYPING conv=\(event.conversationId ?? "-") user=\(event.senderUsername ?? "-") isTyping=\(event.isTyping)")
        }
        ws.onOfferEvent = { event in
            append("OFFER type=\(event.type) conv=\(event.conversationId ?? "-") status=\(event.status ?? "-")")
        }
        ws.onOrderEvent = { event in
            append("ORDER type=\(event.type) conv=\(event.conversationId ?? "-")")
        }
        ws.onNewMessage = { message, echoUuid in
            append("MESSAGE from=\(message.senderUsername) text=\(message.content.prefix(80)) echo=\(echoUuid ?? "-")")
        }
        socket = ws
        ws.connect()
    }

    private func loadConversations() async {
        loadingConversations = true
        defer { loadingConversations = false }
        do {
            let list = try await chatService.getConversations()
            await MainActor.run {
                conversations = list
                if selectedConversationId == nil {
                    selectedConversationId = list.first?.id
                    conversationId = list.first?.id ?? ""
                }
                append("Loaded \(list.count) conversations")
            }
        } catch {
            await MainActor.run {
                lastError = "Failed loading conversations: \(error.localizedDescription)"
                append("LOAD_CONVERSATIONS_FAILED: \(error.localizedDescription)")
            }
        }
    }

    private func sendProbeMessage() {
        guard let ws = socket else { return }
        let text = outboundText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let ok = ws.send(message: text, messageUUID: UUID().uuidString)
        append(ok ? "SENT: \(text)" : "SEND FAILED: socket not connected")
    }

    private func append(_ value: String) {
        let stamp = Date().formatted(date: .omitted, time: .standard)
        events.insert("[\(stamp)] \(value)", at: 0)
    }

    private func handleTypingChange(_ newValue: String) {
        guard connected, let ws = socket else {
            typingFeedbackStatus = "Socket disconnected"
            typingFeedbackIsError = true
            return
        }
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let isTyping = !trimmed.isEmpty
        ws.sendTyping(isTyping: isTyping)
        append("LOCAL_TYPING sent isTyping=\(isTyping)")
        typingFeedbackTask?.cancel()
        typingFeedbackStatus = "Waiting for feedback..."
        typingFeedbackIsError = false

        typingFeedbackTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                typingFeedbackStatus = "No typing feedback received"
                typingFeedbackIsError = true
                append("TYPING_FEEDBACK_TIMEOUT")
            }
        }
    }

    /// Backend WebSocket middleware authenticates against refresh tokens.
    /// Fall back to access token only if refresh is unavailable.
    private var socketAuthToken: String? {
        let token = (authService.refreshToken ?? authService.authToken)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let token, !token.isEmpty else { return nil }
        return token
    }
}

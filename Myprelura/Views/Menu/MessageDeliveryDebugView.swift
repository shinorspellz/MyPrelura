import SwiftUI

/// End-to-end DM test helper: send a probe message and verify it is persisted in the thread.
struct MessageDeliveryDebugView: View {
    @EnvironmentObject private var authService: AuthService
    @StateObject private var chatService = ChatService()

    @State private var conversations: [Conversation] = []
    @State private var selectedConversationId: String?
    @State private var isLoading = false
    @State private var isSending = false
    @State private var statusLine = "Idle"
    @State private var probeText = ""

    var body: some View {
        List {
            Section {
                Text("Use this to test real DM persistence. Select a conversation, send a probe, then verify it appears in fetched thread messages.")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)
            } header: {
                Text("What this tests")
            }

            Section {
                Button(isLoading ? "Refreshing…" : "Refresh conversations") {
                    Task { await loadConversations() }
                }
                .disabled(isLoading)

                if conversations.isEmpty {
                    Text("No conversations loaded")
                        .foregroundStyle(Theme.Colors.secondaryText)
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
                        .onTapGesture { selectedConversationId = c.id }
                    }
                }
            } header: {
                Text("Conversation picker")
            }

            Section {
                TextField("Probe message text", text: $probeText)
                    .autocorrectionDisabled()
                Button(isSending ? "Sending…" : "Send probe + verify") {
                    Task { await sendProbeAndVerify() }
                }
                .disabled(isSending || (selectedConversationId ?? "").isEmpty)

                Text(statusLine)
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .textSelection(.enabled)
            } header: {
                Text("Probe")
            } footer: {
                Text("This validates send + persistence. For remote push arrival, use two devices/accounts and check Push diagnostics + Message push trace.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Message delivery test")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            chatService.updateAuthToken(authService.authToken)
            await loadConversations()
        }
        .onChange(of: authService.authToken) { _, newValue in
            chatService.updateAuthToken(newValue)
        }
    }

    private func loadConversations() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let list = try await chatService.getConversations()
            await MainActor.run {
                conversations = list
                if selectedConversationId == nil {
                    selectedConversationId = list.first?.id
                }
                statusLine = "Loaded \(list.count) conversations"
            }
        } catch {
            await MainActor.run {
                statusLine = "Failed loading conversations: \(error.localizedDescription)"
            }
        }
    }

    private func sendProbeAndVerify() async {
        guard let convId = selectedConversationId, !convId.isEmpty else { return }
        isSending = true
        defer { isSending = false }

        let message = probeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "DM PROBE \(Date().formatted(date: .omitted, time: .standard))"
            : probeText.trimmingCharacters(in: .whitespacesAndNewlines)
        let uuid = UUID().uuidString
        await MainActor.run { statusLine = "Sending to conv \(convId)…" }
        do {
            _ = try await chatService.sendMessage(conversationId: convId, message: message, messageUuid: uuid)
            await MainActor.run { statusLine = "Sent. Verifying in thread…" }
            let msgs = try await chatService.getMessages(conversationId: convId, pageNumber: 1, pageCount: 30)
            let found = msgs.contains { $0.content.trimmingCharacters(in: .whitespacesAndNewlines) == message }
            await MainActor.run {
                if found {
                    statusLine = "OK: persisted and fetched in conversation."
                } else {
                    statusLine = "Sent but not found in latest page yet (may be delayed)."
                }
            }
        } catch {
            await MainActor.run {
                statusLine = "Send failed: \(error.localizedDescription)"
            }
        }
    }
}


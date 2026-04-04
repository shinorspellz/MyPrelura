import SwiftUI

/// Admin Actions (from Flutter admin_menu.dart). Shown only when user is staff. Menu list with Delete All Conversations etc.
struct AdminMenuView: View {
    @EnvironmentObject var authService: AuthService
    @StateObject private var chatService = ChatService()
    @State private var showDeleteAllConfirmation = false
    @State private var showResultAlert = false
    @State private var deleteAllResult: String?
    @State private var isDeletingAll = false

    var body: some View {
        List {
            Button(role: .destructive, action: { showDeleteAllConfirmation = true }) {
                HStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "trash")
                        .font(.body)
                        .foregroundColor(.red)
                    Text(L10n.string("Delete All Conversations"))
                        .foregroundColor(.red)
                }
            }
            .disabled(isDeletingAll)
        }
        .listStyle(.insetGrouped)
        .background(Theme.Colors.background)
        .navigationTitle(L10n.string("Admin Actions"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            if let token = authService.authToken {
                chatService.updateAuthToken(token)
            }
        }
        .alert(L10n.string("Delete All Conversations"), isPresented: $showDeleteAllConfirmation) {
            Button(L10n.string("Cancel"), role: .cancel) {}
            Button(L10n.string("Delete"), role: .destructive) {
                performDeleteAllConversations()
            }
        } message: {
            Text("This will permanently delete all your conversations and cannot be undone.")
        }
        .alert("Result", isPresented: $showResultAlert) {
            Button("OK") { deleteAllResult = nil }
        } message: {
            Text(deleteAllResult ?? "")
        }
    }

    private func performDeleteAllConversations() {
        isDeletingAll = true
        Task {
            do {
                let (success, message, convCount, orderCount) = try await chatService.deleteAllConversations()
                await MainActor.run {
                    isDeletingAll = false
                    if success {
                        let details = [convCount.map { "\($0) conversations" }, orderCount.map { "\($0) orders" }].compactMap { $0 }.joined(separator: ", ")
                        deleteAllResult = "Done. " + (details.isEmpty ? (message ?? "Deleted.") : details)
                    } else {
                        deleteAllResult = message ?? "Delete failed."
                    }
                    showResultAlert = true
                }
            } catch {
                await MainActor.run {
                    isDeletingAll = false
                    deleteAllResult = error.localizedDescription
                    showResultAlert = true
                }
            }
        }
    }
}

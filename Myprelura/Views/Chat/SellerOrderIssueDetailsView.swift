import SwiftUI

/// Seller-side order issue details (Flutter SellerOrderIssueDetailsRoute). Shows issue and actions for seller.
struct SellerOrderIssueDetailsView: View {
    var issueId: Int
    var orderId: Int
    var publicId: String?

    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) private var dismiss
    @State private var supportConversationId: String?
    @State private var isOpeningSupport = false
    @State private var supportError: String?
    @State private var navigateToHelpChat = false

    private let userService = UserService()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                Text("Order issue #\(issueId)")
                    .font(Theme.Typography.title2)
                    .foregroundColor(Theme.Colors.primaryText)
                Text("A buyer has raised an issue for this order. Review the details and respond.")
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.secondaryText)
                if let supportError, !supportError.isEmpty {
                    Text(supportError)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.error)
                }
                Button {
                    Task { await openPersistedSupportChat() }
                } label: {
                    HStack {
                        if isOpeningSupport {
                            ProgressView()
                                .padding(.trailing, 8)
                        }
                        Text("Contact support")
                            .font(Theme.Typography.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundColor(Theme.primaryColor)
                }
                .disabled(isOpeningSupport)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.md)
        }
        .background(Theme.Colors.background)
        .navigationTitle("Order Issue")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .background(
            NavigationLink(
                destination: HelpChatView(
                    orderId: String(orderId),
                    conversationId: supportConversationId,
                    issueDraft: nil,
                    isAdminSupportThread: false,
                    customerUsername: nil
                ),
                isActive: $navigateToHelpChat
            ) { EmptyView() }
            .hidden()
        )
    }

    private func openPersistedSupportChat() async {
        await MainActor.run {
            isOpeningSupport = true
            supportError = nil
        }
        userService.updateAuthToken(authService.authToken)
        do {
            let cid = try await userService.ensureSellerOrderIssueSupportThread(issueId: issueId)
            await MainActor.run {
                supportConversationId = String(cid)
                isOpeningSupport = false
                navigateToHelpChat = true
            }
        } catch {
            await MainActor.run {
                isOpeningSupport = false
                supportError = error.localizedDescription
            }
        }
    }
}

#Preview {
    NavigationStack {
        SellerOrderIssueDetailsView(issueId: 1, orderId: 100, publicId: nil)
    }
    .environmentObject(AuthService())
}

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
    @State private var orderIssue: OrderIssueDetails?
    @State private var isLoadingIssue = true
    @State private var supportEntryUsedOptimistic = false

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
                if isLoadingIssue {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, Theme.Spacing.sm)
                }
                if let supportError, !supportError.isEmpty {
                    Text(supportError)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.error)
                }
                if !isLoadingIssue {
                    if sellerSupportEntryAvailable {
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
                    } else {
                        Text("You've already contacted support for this issue. Continue the conversation in Messages.")
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.md)
        }
        .background(Theme.Colors.background)
        .navigationTitle("Order Issue")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task { await loadOrderIssue() }
        .onChange(of: navigateToHelpChat) { _, isActive in
            if !isActive {
                Task { await loadOrderIssue() }
            }
        }
        .background(
            NavigationLink(
                destination: HelpChatView(
                    orderId: String(orderId),
                    conversationId: supportConversationId,
                    issueDraft: nil,
                    isAdminSupportThread: false,
                    customerUsername: nil,
                    sellerOrderIssueSupportSingleUserMessage: true
                ),
                isActive: $navigateToHelpChat
            ) { EmptyView() }
            .hidden()
        )
    }

    private var sellerSupportEntryAvailable: Bool {
        if supportEntryUsedOptimistic { return false }
        return orderIssue?.sellerSupportConversationId == nil
    }

    private func loadOrderIssue() async {
        await MainActor.run {
            isLoadingIssue = true
            supportError = nil
        }
        userService.updateAuthToken(authService.authToken)
        do {
            let result = try await userService.getOrderIssue(issueId: issueId, publicId: publicId)
            await MainActor.run {
                orderIssue = result
                isLoadingIssue = false
                if result?.sellerSupportConversationId != nil {
                    supportEntryUsedOptimistic = true
                }
            }
        } catch {
            await MainActor.run {
                orderIssue = nil
                isLoadingIssue = false
                supportError = error.localizedDescription
            }
        }
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
                supportEntryUsedOptimistic = true
                isOpeningSupport = false
                navigateToHelpChat = true
            }
            await loadOrderIssue()
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

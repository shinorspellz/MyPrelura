import SwiftUI

/// Presents a single deep-link destination (product, user profile, or chat) in a full-screen cover. Resolves product by ID or user by username.
struct DeepLinkOverlayView: View {
    let item: DeepLinkDestinationItem
    let onDismiss: () -> Void
    private var destination: DeepLinkDestination { item.destination }
    @EnvironmentObject var authService: AuthService
    @State private var resolvedItem: Item?
    @State private var resolvedUser: User?
    @State private var resolvedConversation: Conversation?
    @State private var isLoading = true
    @State private var loadError: String?

    private let productService = ProductService()
    private let userService = UserService()
    private let chatService = ChatService()

    private var dismissBackButton: some View {
        Button(action: onDismiss) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.headline)
                Text(L10n.string("Back"))
                    .font(Theme.Typography.subheadline)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.Colors.background.opacity(0.85))
            .clipShape(Capsule())
        }
        .padding()
    }

    var body: some View {
        Group {
            if isLoading && !skipsAsyncResolve {
                VStack(spacing: Theme.Spacing.md) {
                    ProgressView()
                    if let err = loadError {
                        Text(err)
                            .font(Theme.Typography.body)
                            .foregroundColor(Theme.Colors.secondaryText)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.Colors.background)
            } else {
                destinationView
            }
        }
        .onAppear {
            if let token = authService.authToken {
                productService.updateAuthToken(token)
                userService.updateAuthToken(token)
                chatService.updateAuthToken(token)
            }
            Task { await resolve() }
        }
    }

    /// Order / issue deep links render immediately with local placeholders; no GraphQL prefetch here.
    private var skipsAsyncResolve: Bool {
        switch destination {
        case .orderDetail, .orderIssueSupport: return true
        default: return false
        }
    }

    private func stubOrderForDeepLink(orderId: Int) -> Order {
        Order(
            id: String(orderId),
            publicId: "PR",
            priceTotal: "0",
            discountPrice: nil,
            status: "",
            createdAt: Date(),
            otherParty: nil,
            products: [],
            shippingAddress: nil,
            shipmentService: nil,
            deliveryDate: nil,
            trackingNumber: nil,
            trackingUrl: nil,
            buyerOrderCountWithSeller: nil,
            cancellation: nil
        )
    }

    @ViewBuilder
    private var destinationView: some View {
        switch destination {
        case .product(let publicSlug):
            if let item = resolvedItem {
                ItemDetailView(item: item, authService: authService)
                    .overlay(alignment: .topLeading) {
                        dismissBackButton
                    }
            } else {
                deepLinkErrorView(message: "Product not found")
            }
        case .user:
            if let user = resolvedUser {
                UserProfileView(seller: user, authService: authService)
                    .overlay(alignment: .topLeading) {
                        dismissBackButton
                    }
            } else {
                deepLinkErrorView(message: "User not found")
            }
        case .conversation(let conversationId, let username, _, _):
            if let conv = resolvedConversation {
                NavigationStack {
                    ChatDetailView(conversation: conv)
                }
                .overlay(alignment: .topLeading) {
                    dismissBackButton
                }
            } else {
                deepLinkErrorView(message: "Conversation not found")
            }

        case .orderDetail(let orderId):
            NavigationStack {
                OrderDetailView(order: stubOrderForDeepLink(orderId: orderId), isSeller: nil)
            }
            .environmentObject(authService)
            .overlay(alignment: .topLeading) {
                dismissBackButton
            }

        case .orderIssueSupport(let conversationId, let orderId, _):
            NavigationStack {
                HelpChatView(
                    orderId: orderId,
                    conversationId: conversationId,
                    issueDraft: nil,
                    hidesMessageComposer: false
                )
            }
            .environmentObject(authService)
            .overlay(alignment: .topLeading) {
                dismissBackButton
            }
        }
    }

    private func deepLinkErrorView(message: String) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            Text(message)
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.secondaryText)
            Button("Close", action: onDismiss)
                .foregroundColor(Theme.primaryColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.background)
    }

    private func resolve() async {
        switch destination {
        case .orderDetail, .orderIssueSupport:
            await MainActor.run { isLoading = false }

        case .product(let publicSlug):
            do {
                let item = try await productService.getProduct(publicSlug: publicSlug)
                await MainActor.run {
                    resolvedItem = item
                    loadError = item == nil ? "Product not found" : nil
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    loadError = error.localizedDescription
                    isLoading = false
                }
            }
        case .user(let username):
            do {
                let user = try await userService.getUser(username: username)
                await MainActor.run {
                    resolvedUser = user
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    loadError = error.localizedDescription
                    isLoading = false
                }
            }
        case .conversation(let conversationId, let username, _, _):
            let conv = await chatService.resolveConversationForOpening(
                conversationId: conversationId,
                fallbackUsername: username,
                currentUsername: authService.username
            )
            await MainActor.run {
                resolvedConversation = conv
                isLoading = false
            }
        }
    }
}

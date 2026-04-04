import SwiftUI

/// Debug: mock chat screen – clone of messages chat with order header bar, order confirmation card, mock messages, offer card, and sold confirmation banner (each labeled).
struct OrderChatMockDebugView: View {
    /// Mock "current user" (seller) for bubble alignment.
    private static let currentUsername = "seller1"
    private static let recipientUsername = "buyer1"
    /// Mock avatar URL for the other user (buyer) in title and chat bubbles.
    private static let mockRecipientAvatarURL = "https://picsum.photos/seed/buyer1/100/100"

    private static let mockOrder = ConversationOrder(
        id: "mock-order-1",
        publicId: "PRMOCK1",
        status: "CONFIRMED",
        total: 42.50,
        firstProductName: "Vintage Jacket",
        firstProductImageUrl: nil,
        firstProductId: nil,
        createdAt: Date(),
        lineItems: []
    )

    private static let mockOfferPending = OfferInfo(
        id: "mock-offer-pending",
        status: "PENDING",
        offerPrice: 38.00,
        buyer: OfferInfo.OfferUser(username: "buyer1", profilePictureUrl: nil),
        products: [OfferInfo.OfferProduct(id: "1", name: "Vintage Jacket", seller: nil)],
        createdAt: Date(),
        sentByCurrentUser: false
    )
    private static let mockOfferAccepted = OfferInfo(
        id: "mock-offer-accepted",
        status: "ACCEPTED",
        offerPrice: 38.00,
        buyer: OfferInfo.OfferUser(username: "buyer1", profilePictureUrl: nil),
        products: [OfferInfo.OfferProduct(id: "1", name: "Vintage Jacket", seller: nil)],
        createdAt: Date(),
        sentByCurrentUser: false
    )
    private static let mockOfferDeclined = OfferInfo(
        id: "mock-offer-declined",
        status: "REJECTED",
        offerPrice: 38.00,
        buyer: OfferInfo.OfferUser(username: "buyer1", profilePictureUrl: nil),
        products: [OfferInfo.OfferProduct(id: "1", name: "Vintage Jacket", seller: nil)],
        createdAt: Date(),
        sentByCurrentUser: false
    )

    private static let mockMessages: [Message] = [
        Message(
            senderUsername: "buyer1",
            content: "Hi, is this still available?",
            timestamp: Date().addingTimeInterval(-7200)
        ),
        Message(
            senderUsername: "seller1",
            content: "Yes!",
            timestamp: Date().addingTimeInterval(-5400)
        ),
        Message(
            senderUsername: "buyer1",
            content: "I'll take it",
            timestamp: Date().addingTimeInterval(-3300)
        ),
        Message(
            senderUsername: "seller1",
            content: "Thanks!",
            timestamp: Date().addingTimeInterval(-3000)
        ),
    ]

    /// Timeline: message ids and offer in chat order (order confirmation at top, then this list).
    private static var timelineOrder: [ChatItem] {
        [
            .message(mockMessages[0].id),
            .message(mockMessages[1].id),
            .offer(mockOfferPending.id),
            .message(mockMessages[2].id),
            .message(mockMessages[3].id),
        ]
    }

    private var messageInputBar: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.sm) {
            TextField("Type a message...", text: .constant(""))
                .textFieldStyle(.plain)
                .padding(.horizontal, Theme.Spacing.md)
                .frame(minHeight: 44)
                .background(Theme.Colors.secondaryBackground)
                .cornerRadius(22)
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(Theme.Colors.glassBorder, lineWidth: 1)
                )
                .foregroundColor(Theme.Colors.secondaryText)
                .disabled(true)
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 32))
                .foregroundColor(Theme.Colors.secondaryText)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Colors.background)
    }

    var body: some View {
        VStack(spacing: 0) {
            orderHeaderBarMock
            Rectangle()
                .fill(Theme.Colors.glassBorder)
                .frame(height: 0.5)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    OrderConfirmationCardView(order: Self.mockOrder, isSeller: true)
                        .overlay(alignment: .topLeading) { debugLabel("OrderConfirmationCardView") }
                        .padding(.bottom, Theme.Spacing.sm)
                    ForEach(Array(Self.timelineOrder.enumerated()), id: \.offset) { timelineIndex, entry in
                        timelineRow(timelineIndex: timelineIndex, entry: entry)
                    }
                    offerCardShowcaseSection
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                messageInputBar
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: Theme.Spacing.sm) {
                    mockTitleAvatar(url: Self.mockRecipientAvatarURL, username: Self.recipientUsername)
                    Text(Self.recipientUsername)
                        .font(.headline)
                        .foregroundColor(Theme.Colors.primaryText)
                        .lineLimit(1)
                }
            }
        }
        .toolbar(.hidden, for: .tabBar)
    }

    private static let titleAvatarSize: CGFloat = 32

    private func mockTitleAvatar(url: String?, username: String) -> some View {
        Group {
            if let u = url, !u.isEmpty, let parsed = URL(string: u) {
                AsyncImage(url: parsed) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    case .failure:
                        mockAvatarPlaceholder(username: username)
                    case .empty:
                        mockAvatarPlaceholder(username: username)
                    @unknown default:
                        mockAvatarPlaceholder(username: username)
                    }
                }
            } else {
                mockAvatarPlaceholder(username: username)
            }
        }
        .frame(width: Self.titleAvatarSize, height: Self.titleAvatarSize)
        .clipShape(Circle())
    }

    private func mockAvatarPlaceholder(username: String) -> some View {
        Circle()
            .fill(Theme.Colors.secondaryBackground)
            .overlay(
                Text(String((username.isEmpty ? "?" : username).prefix(1)).uppercased())
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.Colors.secondaryText)
            )
    }

    private func debugLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(Theme.Colors.secondaryText.opacity(0.8))
            .padding(4)
    }

    @ViewBuilder
    private func timelineRow(timelineIndex: Int, entry: ChatItem) -> some View {
        switch entry {
        case .message(let messageId):
            if let message = Self.mockMessages.first(where: { $0.id == messageId }) {
                let topPadding: CGFloat = timelineIndex == 0 ? 0 : Theme.Spacing.md
                MessageBubbleView(
                    message: message,
                    isCurrentUser: message.senderUsername == Self.currentUsername,
                    showAvatar: showAvatarForMessage(message),
                    showTimestamp: true,
                    avatarURL: showAvatarForMessage(message) ? Self.mockRecipientAvatarURL : nil,
                    recipientUsername: Self.recipientUsername
                )
                .id(message.id)
                .padding(.top, topPadding)
            }
        case .offer:
            let prevIsOffer = timelineIndex > 0 && Self.timelineOrder[timelineIndex - 1].isOffer
            let topPadding: CGFloat = timelineIndex == 0 ? 0 : (prevIsOffer ? 0 : Theme.Spacing.md)
            OfferCardView(
                offer: Self.mockOfferPending,
                currentUsername: Self.currentUsername,
                isSeller: true,
                isResponding: false,
                errorMessage: nil,
                onAccept: {},
                onDecline: {},
                onSendNewOffer: {},
                onPayNow: {},
                forceGreyedOut: false
            )
            .overlay(alignment: .topLeading) { debugLabel("OfferCardView (seller, in timeline)") }
            .padding(.horizontal, 0)
            .padding(.vertical, Theme.Spacing.sm)
            .background(Theme.Colors.background)
            .padding(.top, topPadding)
        case .sold:
            EmptyView()
        case .soldBanner:
            EmptyView()
        }
    }

    private var offerCardShowcaseSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text("Offer card – both sides & states")
                .font(Theme.Typography.caption)
                .fontWeight(.semibold)
                .foregroundColor(Theme.Colors.secondaryText)
                .padding(.top, Theme.Spacing.md)
            offerCardRow(label: "Seller, Pending", offer: Self.mockOfferPending, currentUsername: Self.currentUsername, isSeller: true, forceGreyedOut: false)
            offerCardRow(label: "Buyer, Pending", offer: Self.mockOfferPending, currentUsername: Self.recipientUsername, isSeller: false, forceGreyedOut: false)
            offerCardRow(label: "Seller, Accepted", offer: Self.mockOfferAccepted, currentUsername: Self.currentUsername, isSeller: true, forceGreyedOut: false)
            offerCardRow(label: "Buyer, Accepted", offer: Self.mockOfferAccepted, currentUsername: Self.recipientUsername, isSeller: false, forceGreyedOut: false)
            offerCardRow(label: "Seller, Declined", offer: Self.mockOfferDeclined, currentUsername: Self.currentUsername, isSeller: true, forceGreyedOut: false)
            offerCardRow(label: "Buyer, Declined", offer: Self.mockOfferDeclined, currentUsername: Self.recipientUsername, isSeller: false, forceGreyedOut: false)
            offerCardRow(label: "Overwritten (grey, not clickable)", offer: Self.mockOfferPending, currentUsername: Self.currentUsername, isSeller: true, forceGreyedOut: true)
        }
    }

    private func offerCardRow(label: String, offer: OfferInfo, currentUsername: String, isSeller: Bool, forceGreyedOut: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            debugLabel(label)
            OfferCardView(
                offer: offer,
                currentUsername: currentUsername,
                isSeller: isSeller,
                isResponding: false,
                errorMessage: nil,
                onAccept: {},
                onDecline: {},
                onSendNewOffer: {},
                onPayNow: {},
                forceGreyedOut: forceGreyedOut
            )
        }
    }

    private func showAvatarForMessage(_ message: Message) -> Bool {
        guard message.senderUsername != Self.currentUsername else { return false }
        guard let idx = Self.mockMessages.firstIndex(where: { $0.id == message.id }) else { return true }
        if idx == 0 { return true }
        let prev = Self.mockMessages[idx - 1]
        return prev.senderUsername != message.senderUsername
    }

    private var orderHeaderBarMock: some View {
        let order = Self.mockOrder
        let priceStr = CurrencyFormatter.gbp(order.total)
        return HStack(spacing: Theme.Spacing.md) {
            Rectangle()
                .fill(Theme.Colors.secondaryBackground)
                .overlay(Image(systemName: "bag.fill").font(.body).foregroundColor(Theme.Colors.secondaryText))
                .aspectRatio(1, contentMode: .fill)
                .frame(width: 56, height: 56)
                .clipped()
                .cornerRadius(8)
            VStack(alignment: .leading, spacing: 2) {
                Text(order.firstProductName ?? "Order")
                    .font(Theme.Typography.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(Theme.Colors.primaryText)
                    .lineLimit(1)
                Text(priceStr)
                    .font(Theme.Typography.body)
                    .fontWeight(.semibold)
                    .foregroundColor(Theme.primaryColor)
                Text(order.status)
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
        .background(Theme.Colors.background)
    }
}

#Preview {
    NavigationStack {
        OrderChatMockDebugView()
    }
}

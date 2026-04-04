import SwiftUI
import PhotosUI

/// "Item not as described" help flow (Flutter ItemNotAsDescribedHelpScreen). User submits issue details, then lands on read-only help chat.
struct ItemNotAsDescribedHelpView: View {
    var orderId: String?
    var conversationId: String?
    /// When set (multibuy), load this product instead of the first line on the order.
    var relatedProductId: String? = nil

    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) private var dismiss
    @State private var description: String = ""
    @State private var selectedIssueType: String? = nil
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var selectedImageDataList: [Data] = []
    @State private var selectedPreviewImages: [UIImage] = []
    @State private var isSubmittingIssue = false
    @State private var submitError: String?
    @State private var createdIssueId: Int?
    @State private var createdIssuePublicId: String?
    /// GraphQL support thread id returned from createOrderCase (persisted Help Chat).
    @State private var supportConversationId: String?
    @State private var showSupportChat = false
    @State private var relatedItem: Item?
    @State private var isLoadingRelatedProduct = false
    @State private var relatedProductError: String?
    private let userService = UserService()
    private let productService = ProductService()
    private let fileUploadService = FileUploadService()
    private let chatService = ChatService()
    private let descriptionFieldCornerRadius: CGFloat = 30

    private let issueTypes: [(id: String, label: String)] = [
        ("NOT_AS_DESCRIBED", "Item not as described"),
        ("TOO_SMALL", "Item is too small"),
        ("COUNTERFEIT", "Item is counterfeit"),
        ("DAMAGED", "Item is damaged or broken"),
        ("WRONG_COLOR", "Item is wrong colour"),
        ("WRONG_SIZE", "Item is wrong size"),
        ("DEFECTIVE", "Item doesn't work / defective"),
        ("OTHER", "Other")
    ]

    var body: some View {
        VStack(spacing: 0) {
            relatedProductTopBar
            Rectangle()
                .fill(Theme.Colors.glassBorder)
                .frame(height: 0.5)

            List {
                Section {
                    Text("If the item you received doesn't match the description, you can raise an issue within 3 days of delivery.")
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.secondaryText)
                        .listRowInsets(EdgeInsets(top: Theme.Spacing.sm, leading: Theme.Spacing.md, bottom: Theme.Spacing.sm, trailing: Theme.Spacing.md))
                        .listRowBackground(Theme.Colors.background)
                }

                Section(header: Text("What's the issue?").font(Theme.Typography.headline).foregroundColor(Theme.Colors.primaryText)) {
                    ForEach(issueTypes, id: \.id) { type in
                        Button {
                            selectedIssueType = type.id
                        } label: {
                            HStack {
                                Text(type.label)
                                    .font(Theme.Typography.body)
                                    .foregroundColor(Theme.Colors.primaryText)
                                Spacer()
                                if selectedIssueType == type.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(Theme.primaryColor)
                                }
                            }
                        }
                        .buttonStyle(PlainTappableButtonStyle())
                    }
                }

                Section(header: Text("Additional details (optional)").font(Theme.Typography.body).fontWeight(.medium).foregroundColor(Theme.Colors.secondaryText)) {
                    ZStack(alignment: .topLeading) {
                        if description.isEmpty {
                            Text("Describe the issue...")
                                .font(Theme.Typography.body)
                                .foregroundColor(Theme.Colors.secondaryText)
                                .padding(.horizontal, Theme.Spacing.md)
                                .padding(.vertical, Theme.Spacing.md)
                                .padding(.top, selectedPreviewImages.isEmpty ? 28 : 112)
                        }
                        TextEditor(text: $description)
                            .font(Theme.Typography.body)
                            .foregroundColor(Theme.Colors.primaryText)
                            .scrollContentBackground(.hidden)
                            .padding(Theme.Spacing.sm)
                            .padding(.top, selectedPreviewImages.isEmpty ? 24 : 108)
                            .frame(minHeight: selectedPreviewImages.isEmpty ? 170 : 240)
                            .clipShape(RoundedRectangle(cornerRadius: descriptionFieldCornerRadius))

                        PhotosPicker(selection: $selectedPhotoItems, maxSelectionCount: 6, matching: .images) {
                            HStack(spacing: Theme.Spacing.xs) {
                                Image(systemName: "photo")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(Theme.Colors.secondaryText)
                                if !selectedImageDataList.isEmpty {
                                    Text("\(selectedImageDataList.count) image\(selectedImageDataList.count == 1 ? "" : "s") selected")
                                        .font(Theme.Typography.caption)
                                        .foregroundColor(Theme.Colors.secondaryText)
                                }
                            }
                        }
                        .padding(.top, Theme.Spacing.sm)
                        .padding(.leading, Theme.Spacing.md)

                        if !selectedImageDataList.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: Theme.Spacing.xs) {
                                    ForEach(Array(selectedPreviewImages.enumerated()), id: \.offset) { _, image in
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 74, height: 74)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                }
                                .padding(.horizontal, Theme.Spacing.md)
                            }
                            .padding(.top, 40)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.Colors.secondaryBackground)
                    .clipShape(RoundedRectangle(cornerRadius: descriptionFieldCornerRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: descriptionFieldCornerRadius)
                            .stroke(Theme.Colors.glassBorder.opacity(0.6), lineWidth: 0.5)
                    )
                    .padding(.horizontal, Theme.Spacing.md)
                    .listRowInsets(EdgeInsets(top: Theme.Spacing.sm, leading: 0, bottom: Theme.Spacing.sm, trailing: 0))
                    .listRowBackground(Theme.Colors.background)
                    .listRowSeparator(.hidden)
                }
                if let submitError, !submitError.isEmpty {
                    Section {
                        Text(submitError)
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.error)
                    }
                    .listRowBackground(Theme.Colors.background)
                }
            }
            .listStyle(.insetGrouped)
            .background(Theme.Colors.background)
        }
        .background(Theme.Colors.background)
        .navigationTitle("Item Not as Described")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button(action: { Task { await startSupportConversation() } }) {
                HStack(spacing: Theme.Spacing.sm) {
                    if isSubmittingIssue {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(isSubmittingIssue ? "Submitting..." : "Submit")
                        .font(Theme.Typography.headline)
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.md)
                .background(Theme.primaryColor)
                .clipShape(RoundedRectangle(cornerRadius: 26))
            }
            .disabled(selectedIssueType == nil || isSubmittingIssue)
            .opacity((selectedIssueType == nil || isSubmittingIssue) ? 0.55 : 1.0)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(Theme.Colors.background)
        }
        .overlay {
            if isSubmittingIssue {
                ZStack {
                    Color.black.opacity(0.25).ignoresSafeArea()
                    VStack(spacing: Theme.Spacing.sm) {
                        ProgressView()
                        Text("Submitting...")
                            .font(Theme.Typography.subheadline)
                            .foregroundColor(Theme.Colors.primaryText)
                    }
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.vertical, Theme.Spacing.md)
                    .background(Theme.Colors.background)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
        }
        .background(
            NavigationLink(
                destination: HelpChatView(
                    orderId: orderId,
                    conversationId: supportConversationId ?? conversationId,
                    issueDraft: SupportIssueDraft(
                        selectedOptions: selectedIssueLabels,
                        description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                        imageDatas: selectedImageDataList,
                        issueTypeCode: selectedIssueType,
                        issueId: createdIssueId,
                        issuePublicId: createdIssuePublicId
                    ),
                    hidesMessageComposer: true
                ),
                isActive: $showSupportChat
            ) { EmptyView() }
            .hidden()
        )
        .task { await loadRelatedOrderProduct() }
        .onChange(of: selectedPhotoItems) { _, newItems in
            Task {
                var loaded: [Data] = []
                for item in newItems {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        loaded.append(data)
                    }
                }
                let previews = loaded.compactMap { UIImage(data: $0) }
                await MainActor.run {
                    selectedImageDataList = loaded
                    selectedPreviewImages = previews
                }
            }
        }
    }

    private func startSupportConversation() async {
        guard let selectedIssueType,
              let orderId,
              let oid = Int(orderId) else {
            await MainActor.run { submitError = "Missing issue type or order." }
            return
        }
        await MainActor.run {
            isSubmittingIssue = true
            submitError = nil
        }
        userService.updateAuthToken(authService.authToken)
        fileUploadService.setAuthToken(authService.authToken)
        do {
            let uploadedUrls: [String]
            if selectedImageDataList.isEmpty {
                uploadedUrls = []
            } else {
                let uploads = try await fileUploadService.uploadProductImages(selectedImageDataList)
                uploadedUrls = uploads.map(\.url)
            }
            let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
            let desc = trimmed.isEmpty ? (selectedIssueLabels.first ?? "Item not as described") : trimmed
            let result = try await userService.raiseOrderIssue(
                orderId: oid,
                issueType: selectedIssueType,
                description: desc,
                imagesUrl: uploadedUrls,
                otherIssueDescription: selectedIssueType == "OTHER" ? desc : nil
            )
            if let scid = result.supportConversationId {
                await sendSupportIssueContextMessage(
                    conversationId: String(scid),
                    orderId: oid,
                    issueType: selectedIssueType,
                    description: desc,
                    imageUrls: uploadedUrls,
                    issueId: result.issueId,
                    publicId: result.publicId
                )
            }
            await MainActor.run {
                createdIssueId = result.issueId
                createdIssuePublicId = result.publicId
                if let scid = result.supportConversationId {
                    supportConversationId = String(scid)
                }
                isSubmittingIssue = false
                showSupportChat = true
            }
        } catch {
            await MainActor.run {
                isSubmittingIssue = false
                submitError = error.localizedDescription
            }
        }
    }

    private func sendSupportIssueContextMessage(
        conversationId: String,
        orderId: Int,
        issueType: String,
        description: String,
        imageUrls: [String],
        issueId: Int?,
        publicId: String?
    ) async {
        chatService.updateAuthToken(authService.authToken)
        var payload: [String: Any] = [
            "type": "order_issue",
            "order_id": orderId,
            "issue_type": issueType,
            "description": description,
            "imagesUrl": imageUrls
        ]
        if let issueId { payload["issue_id"] = issueId }
        if let publicId, !publicId.isEmpty { payload["public_id"] = publicId }
        if let pid = relatedItem?.productId.flatMap({ Int($0) }) {
            payload["product_id"] = pid
        } else if let rid = relatedProductId.flatMap({ Int($0) }) {
            payload["product_id"] = rid
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else { return }
        _ = try? await chatService.sendMessage(
            conversationId: conversationId,
            message: text,
            messageUuid: UUID().uuidString
        )
    }

    @ViewBuilder
    private var relatedProductTopBar: some View {
        if let item = relatedItem {
            NavigationLink(destination: ItemDetailView(item: item)) {
                HStack(spacing: Theme.Spacing.md) {
                    Group {
                        if let urlString = item.imageURLs.first, let url = URL(string: urlString) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let img): img.resizable().scaledToFill()
                                default: ImageShimmerPlaceholderFilled(cornerRadius: 8)
                                }
                            }
                        } else {
                            ImageShimmerPlaceholderFilled(cornerRadius: 8)
                        }
                    }
                    .aspectRatio(1, contentMode: .fill)
                    .frame(width: 56, height: 56)
                    .clipped()
                    .cornerRadius(8)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(Theme.Typography.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(Theme.Colors.primaryText)
                            .lineLimit(1)
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
                .background(Theme.Colors.background)
            }
            .buttonStyle(PlainTappableButtonStyle())
        } else if isLoadingRelatedProduct {
            HStack {
                ProgressView()
                Spacer()
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(Theme.Colors.background)
        } else if let relatedProductError, !relatedProductError.isEmpty {
            HStack {
                Text(relatedProductError)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.secondaryText)
                Spacer()
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(Theme.Colors.background)
        } else {
            EmptyView()
        }
    }

    private func loadRelatedOrderProduct() async {
        guard let orderId, !orderId.isEmpty else { return }
        await MainActor.run {
            isLoadingRelatedProduct = true
            relatedProductError = nil
        }
        userService.updateAuthToken(authService.authToken)
        productService.updateAuthToken(authService.authToken)
        do {
            let pid: Int? = {
                if let rid = relatedProductId?.trimmingCharacters(in: .whitespacesAndNewlines), !rid.isEmpty, let i = Int(rid) {
                    return i
                }
                return nil
            }()
            if let pid {
                let product = try await productService.getProduct(id: pid)
                await MainActor.run {
                    relatedItem = product
                    isLoadingRelatedProduct = false
                    if relatedItem == nil { relatedProductError = "Related product unavailable" }
                }
                return
            }
            async let sellerOrdersTask = userService.getUserOrders(isSeller: true)
            async let buyerOrdersTask = userService.getUserOrders(isSeller: false)
            let (sellerOrders, buyerOrders) = try await (sellerOrdersTask, buyerOrdersTask)
            let allOrders = sellerOrders.orders + buyerOrders.orders
            guard let matchedOrder = allOrders.first(where: { $0.id == orderId }),
                  let firstOrderProduct = matchedOrder.products.first,
                  let fallbackPid = Int(firstOrderProduct.id) else {
                await MainActor.run {
                    isLoadingRelatedProduct = false
                    relatedProductError = "Related product unavailable"
                }
                return
            }
            let product = try await productService.getProduct(id: fallbackPid)
            await MainActor.run {
                relatedItem = product
                isLoadingRelatedProduct = false
                if relatedItem == nil { relatedProductError = "Related product unavailable" }
            }
        } catch {
            await MainActor.run {
                isLoadingRelatedProduct = false
                relatedProductError = "Could not load related product"
            }
        }
    }

    private var selectedIssueLabels: [String] {
        guard let selectedIssueType else { return [] }
        if let match = issueTypes.first(where: { $0.id == selectedIssueType }) {
            return [match.label]
        }
        return []
    }
}

#Preview {
    NavigationStack {
        ItemNotAsDescribedHelpView(orderId: nil, conversationId: nil)
    }
}

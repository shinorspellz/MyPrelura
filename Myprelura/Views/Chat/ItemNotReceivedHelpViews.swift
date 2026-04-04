import SwiftUI
import PhotosUI
import UIKit

/// Educational step before escalating “item not received” to support (matches intended Flutter-style flow).
struct ItemNotReceivedGuidanceHelpView: View {
    var orderId: String?
    var conversationId: String?
    var relatedProductId: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                Text("We know waiting for a parcel can be frustrating. Here is what usually happens, and when it makes sense to get in touch.")
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                guidanceCard(
                    icon: "clock.fill",
                    title: "Allow a few extra days",
                    body: "Most UK orders arrive within the estimated window shown on your order. Carriers often deliver Monday–Saturday during daytime hours. Weekends, bank holidays, and busy sale periods can add one to three working days that are outside anyone’s control."
                )

                guidanceCard(
                    icon: "shippingbox.fill",
                    title: "Tracking can move slowly",
                    body: "Sometimes a label is created before the parcel is scanned. You might see “label created” or no updates for 24–48 hours. That does not always mean the parcel is lost—sorting hubs batch-scan thousands of items. If tracking shows movement but delivery is delayed, the carrier is usually still processing it."
                )

                guidanceCard(
                    icon: "exclamationmark.triangle.fill",
                    title: "Delays outside our control",
                    body: "Severe weather, customs checks (on international routes), industrial action, incorrect or incomplete addresses, access issues (buzzer, gate, safe place), and high-volume events can all delay delivery. Sellers ship through third-party carriers; Prelura does not operate the courier network, but we can help investigate once a reasonable time has passed."
                )

                guidanceCard(
                    icon: "person.2.fill",
                    title: "Before you escalate",
                    body: "Check your order’s tracking link, confirm your shipping address on the order detail screen, ask housemates or reception if they accepted the parcel, and look for a “missed delivery” card. Messaging the seller in your order chat is often the fastest way to clarify dispatch timing."
                )

                NavigationLink {
                    ItemNotReceivedReportHelpView(
                        orderId: orderId,
                        conversationId: conversationId,
                        relatedProductId: relatedProductId
                    )
                } label: {
                    Text("I still need help")
                        .font(Theme.Typography.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.md)
                        .background(Theme.primaryColor)
                        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.top, Theme.Spacing.sm)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.md)
        }
        .background(Theme.Colors.background)
        .navigationTitle("Item Not Received")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }

    private func guidanceCard(icon: String, title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.primaryColor)
                Text(title)
                    .font(Theme.Typography.headline)
                    .foregroundColor(Theme.Colors.primaryText)
            }
            Text(body)
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Glass.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Glass.cornerRadius, style: .continuous)
                .stroke(Theme.Colors.glassBorder.opacity(0.45), lineWidth: 0.5)
        )
    }
}

/// Collects details then opens the same locked support thread flow as “Item not as described”.
struct ItemNotReceivedReportHelpView: View {
    var orderId: String?
    var conversationId: String?
    var relatedProductId: String?

    @EnvironmentObject var authService: AuthService
    @State private var description: String = ""
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var selectedImageDataList: [Data] = []
    @State private var selectedPreviewImages: [UIImage] = []
    @State private var isSubmittingIssue = false
    @State private var submitError: String?
    @State private var createdIssueId: Int?
    @State private var createdIssuePublicId: String?
    @State private var supportConversationId: String?
    @State private var showSupportChat = false

    private let userService = UserService()
    private let fileUploadService = FileUploadService()
    private let chatService = ChatService()
    private let descriptionFieldCornerRadius: CGFloat = 30

    private let issueTypeCode = "NOT_RECEIVED"

    var body: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    Text("Describe what has happened: when you expected delivery, what tracking shows (if anything), and any steps you have already taken. The more detail you give, the faster we can help.")
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.secondaryText)
                        .listRowInsets(EdgeInsets(top: Theme.Spacing.sm, leading: Theme.Spacing.md, bottom: Theme.Spacing.sm, trailing: Theme.Spacing.md))
                        .listRowBackground(Theme.Colors.background)
                }

                Section(header: Text("Your situation").font(Theme.Typography.headline).foregroundColor(Theme.Colors.primaryText)) {
                    ZStack(alignment: .topLeading) {
                        if description.isEmpty {
                            Text("E.g. estimated delivery was last Tuesday, tracking has not updated for five days, I have messaged the seller…")
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
        .navigationTitle("Report not received")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button(action: { Task { await submitReport() } }) {
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
            .disabled(descriptionTrimmed.isEmpty || isSubmittingIssue)
            .opacity((descriptionTrimmed.isEmpty || isSubmittingIssue) ? 0.55 : 1.0)
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
                        selectedOptions: ["Item not received"],
                        description: descriptionTrimmed,
                        imageDatas: selectedImageDataList,
                        issueTypeCode: issueTypeCode,
                        issueId: createdIssueId,
                        issuePublicId: createdIssuePublicId
                    ),
                    hidesMessageComposer: true
                ),
                isActive: $showSupportChat
            ) { EmptyView() }
            .hidden()
        )
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

    private var descriptionTrimmed: String {
        description.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submitReport() async {
        guard let orderId, let oid = Int(orderId) else {
            await MainActor.run { submitError = "Missing order." }
            return
        }
        guard !descriptionTrimmed.isEmpty else {
            await MainActor.run { submitError = "Please describe what happened." }
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
            let result = try await userService.raiseOrderIssue(
                orderId: oid,
                issueType: issueTypeCode,
                description: descriptionTrimmed,
                imagesUrl: uploadedUrls,
                otherIssueDescription: nil
            )
            if let scid = result.supportConversationId {
                await sendSupportIssueContextMessage(
                    conversationId: String(scid),
                    orderId: oid,
                    issueType: issueTypeCode,
                    description: descriptionTrimmed,
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
        if let rid = relatedProductId.flatMap({ Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }) {
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
}

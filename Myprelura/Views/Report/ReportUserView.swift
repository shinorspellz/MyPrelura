import SwiftUI
import PhotosUI

/// Report user/account options (Flutter ReportAccountOptionsRoute).
struct ReportUserView: View {
    let username: String
    var isProduct: Bool = false
    var productId: Int?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authService: AuthService
    @State private var selectedOption: String?
    @State private var showDetailsScreen = false

    private let userService = UserService()
    private let productService = ProductService()

    private let userOptions = [
        "This user has engaged in inappropriate or offensive behaviour towards others",
        "This user has engaged in harassing or abusive behavior towards others on the platform.",
        "The user has violated our community guidelines and terms of service.",
        "The user has posted inappropriate or explicit content.",
        "This user has been involved in fraudulent or deceptive activities.",
        "The user has been consistently unprofessional in their conduct.",
        "The user has been impersonating someone else on the platform.",
        "Other",
    ]
    private let productOptions = [
        "The product has violated our community guidelines and terms of service.",
        "The product has posted inappropriate or explicit content.",
        "This product has been involved in fraudulent or deceptive activities.",
        "The product has been consistently unprofessional in their description.",
        "Other",
    ]

    private var options: [String] { isProduct ? productOptions : userOptions }

    var body: some View {
        List {
            ForEach(options, id: \.self) { option in
                Button {
                    selectedOption = option
                    showDetailsScreen = true
                } label: {
                    HStack {
                        Text(option)
                            .font(Theme.Typography.body)
                            .foregroundColor(Theme.Colors.primaryText)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        if selectedOption == option {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(Theme.primaryColor)
                        }
                    }
                    .padding(.vertical, Theme.Spacing.sm)
                }
                .buttonStyle(PlainTappableButtonStyle())
            }
        }
        .listStyle(.insetGrouped)
        .background(Theme.Colors.background)
        .navigationTitle("Report")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showDetailsScreen) {
            if let selectedOption {
                ReportUserDetailsView(
                    username: username,
                    isProduct: isProduct,
                    productId: productId,
                    reason: selectedOption
                )
            }
        }
        .toolbar(.hidden, for: .tabBar)
    }
}

private struct ReportUserDetailsView: View {
    let username: String
    let isProduct: Bool
    let productId: Int?
    let reason: String

    @State private var description: String = ""
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var selectedImageDataList: [Data] = []
    @State private var selectedPreviewImages: [UIImage] = []
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var isSubmitting = false

    private let userService = UserService()
    private let productService = ProductService()
    private let fileUploadService = FileUploadService()

    var body: some View {
        List {
            Section {
                Text(reason)
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.primaryText)
            } header: {
                Text("Reason")
            }

            Section {
                TextEditor(text: $description)
                    .font(Theme.Typography.body)
                    .frame(minHeight: 120)
            } header: {
                Text("Details")
            }

            Section {
                PhotosPicker(selection: $selectedPhotoItems, maxSelectionCount: 6, matching: .images) {
                    HStack {
                        Image(systemName: "photo.on.rectangle")
                        Text("Upload photos (optional)")
                    }
                    .foregroundColor(Theme.primaryColor)
                }
                if !selectedPreviewImages.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Theme.Spacing.xs) {
                            ForEach(Array(selectedPreviewImages.enumerated()), id: \.offset) { _, image in
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 72, height: 72)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }
            }

            if let successMessage {
                Section {
                    Text(successMessage)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.primaryColor)
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.error)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Report details")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PrimaryGlassButton(isSubmitting ? "Submitting..." : "Submit report", isLoading: isSubmitting) {
                Task { await submit() }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(Theme.Colors.background)
            .disabled(isSubmitting)
        }
        .onChange(of: selectedPhotoItems) { _, newItems in
            Task {
                var loaded: [Data] = []
                for item in newItems {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        loaded.append(data)
                    }
                }
                await MainActor.run {
                    selectedImageDataList = loaded
                    selectedPreviewImages = loaded.compactMap { UIImage(data: $0) }
                }
            }
        }
    }

    private func submit() async {
        await MainActor.run {
            isSubmitting = true
            errorMessage = nil
            successMessage = nil
        }
        do {
            fileUploadService.setAuthToken(UserDefaults.standard.string(forKey: "AUTH_TOKEN"))
            let uploaded: [(url: String, thumbnail: String)] = selectedImageDataList.isEmpty ? [] : (try await fileUploadService.uploadProductImages(selectedImageDataList))
            let imageUrls = uploaded.map { $0.url }
            let submittedRef: SubmittedReportRef?
            if isProduct, let pid = productId {
                submittedRef = try await productService.reportProduct(
                    productId: String(pid),
                    reason: reason,
                    content: description.trimmingCharacters(in: .whitespacesAndNewlines),
                    imagesUrl: imageUrls
                )
            } else {
                submittedRef = try await userService.reportAccount(
                    username: username,
                    reason: reason,
                    content: description.trimmingCharacters(in: .whitespacesAndNewlines),
                    imagesUrl: imageUrls
                )
            }
            await MainActor.run {
                isSubmitting = false
                let ref = submittedRef?.publicId ?? "submitted"
                successMessage = "Report submitted. Reference: \(ref)"
            }
        } catch {
            await MainActor.run {
                isSubmitting = false
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    NavigationStack {
        ReportUserView(username: "testuser")
            .environmentObject(AuthService())
    }
}

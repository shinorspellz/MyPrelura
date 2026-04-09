//
//  LookbooksUploadView.swift
//  Prelura-swift
//
//  Debug: upload banner, zoom/pan cropper, Upload + Tag (active when image selected).
//

import SwiftUI
import PhotosUI
import CoreImage
import UIKit

private func lookbookCaptionKeyboardAccessory(target: Any?, action: Selector) -> UIToolbar {
    let bar = UIToolbar()
    bar.sizeToFit()
    let flex = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
    let done = UIBarButtonItem(barButtonSystemItem: .done, target: target, action: action)
    bar.items = [flex, done]
    return bar
}

// MARK: - Hashtag-aware caption field (hashtags shown in primary colour)

/// Text field that displays #hashtag segments in primary colour. Used for lookbook caption and any hashtag field.
struct HashtagCaptionField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var minLines: Int = 1
    var maxLines: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(Theme.Typography.body)
                .fontWeight(.medium)
                .foregroundColor(Theme.Colors.secondaryText)

            if minLines > 1 || (maxLines ?? 1) > 1 {
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(placeholder)
                            .font(Theme.Typography.body)
                            .foregroundColor(Theme.Colors.secondaryText)
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, Theme.Spacing.md)
                    }
                    HashtagTextEditorRepresentable(text: $text, primaryColor: UIColor(Theme.primaryColor))
                        .frame(minHeight: minLines > 1 ? CGFloat(minLines) * 24 : 44)
                        .padding(Theme.Spacing.sm)
                }
                .background(Theme.Colors.secondaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: 30))
            } else {
                HashtagTextFieldRepresentable(text: $text, placeholder: placeholder, primaryColor: UIColor(Theme.primaryColor))
                    .frame(height: 44)
                    .padding(.horizontal, Theme.Spacing.md)
                    .background(Theme.Colors.secondaryBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 30))
            }
        }
    }
}

/// Single-line text field with hashtags in primary colour.
private struct HashtagTextFieldRepresentable: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let primaryColor: UIColor

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged), for: .editingChanged)
        field.font = UIFont.preferredFont(forTextStyle: .body)
        field.textColor = UIColor.label
        field.attributedPlaceholder = NSAttributedString(string: placeholder, attributes: [.foregroundColor: UIColor.secondaryLabel])
        field.backgroundColor = .clear
        field.inputAccessoryView = lookbookCaptionKeyboardAccessory(target: context.coordinator, action: #selector(Coordinator.dismissKeyboard))
        return field
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text {
            uiView.attributedText = Self.attributedString(for: text, primaryColor: primaryColor)
        }
    }

    static func attributedString(for string: String, primaryColor: UIColor) -> NSAttributedString {
        let font = UIFont.preferredFont(forTextStyle: .body)
        let normalAttrs: [NSAttributedString.Key: Any] = [.foregroundColor: UIColor.label, .font: font]
        let hashtagAttrs: [NSAttributedString.Key: Any] = [.foregroundColor: primaryColor, .font: font]
        let result = NSMutableAttributedString()
        let normalColor = UIColor.label
        let regex = try? NSRegularExpression(pattern: "#\\w+", options: [])
        var lastEnd = string.startIndex
        let nsRange = NSRange(string.startIndex..., in: string)
        regex?.enumerateMatches(in: string, options: [], range: nsRange) { match, _, _ in
            guard let range = match?.range, let swiftRange = Range(range, in: string) else { return }
            if swiftRange.lowerBound > lastEnd {
                result.append(NSAttributedString(string: String(string[lastEnd..<swiftRange.lowerBound]), attributes: normalAttrs))
            }
            result.append(NSAttributedString(string: String(string[swiftRange]), attributes: hashtagAttrs))
            lastEnd = swiftRange.upperBound
        }
        if lastEnd < string.endIndex {
            result.append(NSAttributedString(string: String(string[lastEnd...]), attributes: normalAttrs))
        }
        return result.length > 0 ? result : NSAttributedString(string: string, attributes: normalAttrs)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UITextFieldDelegate {
        var parent: HashtagTextFieldRepresentable
        init(_ parent: HashtagTextFieldRepresentable) { self.parent = parent }

        @objc func editingChanged(_ field: UITextField) {
            parent.text = field.text ?? ""
        }

        @objc func dismissKeyboard() {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }
}

/// Multi-line text editor with hashtags in primary colour.
private struct HashtagTextEditorRepresentable: UIViewRepresentable {
    @Binding var text: String
    let primaryColor: UIColor

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate = context.coordinator
        tv.font = UIFont.preferredFont(forTextStyle: .body)
        tv.textColor = UIColor.label
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.inputAccessoryView = lookbookCaptionKeyboardAccessory(
            target: context.coordinator,
            action: #selector(Coordinator.dismissKeyboard)
        )
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            let sel = uiView.selectedTextRange
            uiView.attributedText = HashtagTextFieldRepresentable.attributedString(for: text, primaryColor: primaryColor)
            uiView.selectedTextRange = sel
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: HashtagTextEditorRepresentable
        init(_ parent: HashtagTextEditorRepresentable) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text ?? ""
        }

        @objc func dismissKeyboard() {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }
}

// MARK: - Models

struct LookbookTagData: Codable, Identifiable, Equatable {
    var id: String { "\(productId)_\(x)_\(y)" }
    let productId: String
    let x: Double
    let y: Double
}

/// Minimal product info for showing tagged thumbnails on lookbook feed (stored with upload).
struct LookbookProductSnapshot: Codable, Equatable {
    let productId: String
    let title: String
    let imageUrl: String?
}

struct LookbookUploadRecord: Codable {
    let id: String
    /// Primary image URL (first slide); matches server `imageUrl`.
    let imagePath: String
    /// When the user posts multiple photos in one upload, all URLs (carousel). First matches `imagePath`.
    var imageUrls: [String]?
    var tags: [LookbookTagData]
    var caption: String?
    /// Style tags (e.g. CASUAL, VINTAGE); max 3. Optional for backward compat.
    var styles: [String]?
    /// productId -> snapshot for thumbnails at pin positions (optional for backward compat).
    var productSnapshots: [String: LookbookProductSnapshot]?

    /// URLs to render in the feed (single- or multi-image).
    var allImageUrls: [String] {
        if let u = imageUrls, !u.isEmpty { return u }
        return [imagePath]
    }
}

// MARK: - Store

private enum LookbookUploadStore {
    static let defaults = UserDefaults.standard
    static let currentKey = "lookbook_upload_current"
    static let tagsPrefix = "lookbook_tags_"

    static func saveCurrent(record: LookbookUploadRecord) {
        if let data = try? JSONEncoder().encode(record) {
            defaults.set(data, forKey: currentKey)
        }
    }

    static func loadCurrent() -> LookbookUploadRecord? {
        guard let data = defaults.data(forKey: currentKey),
              let record = try? JSONDecoder().decode(LookbookUploadRecord.self, from: data) else { return nil }
        return record
    }

    static func saveTags(imageId: String, tags: [LookbookTagData]) {
        if let data = try? JSONEncoder().encode(tags) {
            defaults.set(data, forKey: tagsPrefix + imageId)
        }
    }

    static func loadTags(imageId: String) -> [LookbookTagData] {
        guard let data = defaults.data(forKey: tagsPrefix + imageId),
              let tags = try? JSONDecoder().decode([LookbookTagData].self, from: data) else { return [] }
        return tags
    }
}

// MARK: - First page: Upload banner + two bottom buttons (active only when image selected)

/// Style pill raw values for lookbook (subset of StyleSelectionView; same as LookbookView filter pills).
private let lookbookUploadStylePills: [String] = [
    "CASUAL", "VINTAGE", "STREETWEAR", "MINIMALIST", "BOHO", "CHIC", "FORMAL_WEAR",
    "PARTY_DRESS", "LOUNGEWEAR", "ACTIVEWEAR", "Y2K", "DRESSES_GOWNS", "DENIM_JEANS",
    "SUMMER_STYLES", "WINTER_ESSENTIALS", "ATHLEISURE", "DATE_NIGHT", "VACATION_RESORT_WEAR"
]

/// Fixed export sizes for lookbook uploads (crop + resize before upload). Aspect = width ÷ height.
enum LookbookUploadCropPreset: Int, CaseIterable, Identifiable, Equatable {
    case square1080
    case portrait1080x1350
    case portrait1080x1600
    case landscape1920x1080
    case landscape1350x1080

    var id: Int { rawValue }

    var exportWidth: Int {
        switch self {
        case .square1080, .portrait1080x1350, .portrait1080x1600: return 1080
        case .landscape1920x1080: return 1920
        case .landscape1350x1080: return 1350
        }
    }

    var exportHeight: Int {
        switch self {
        case .square1080: return 1080
        case .portrait1080x1350: return 1350
        case .portrait1080x1600: return 1600
        case .landscape1920x1080: return 1080
        case .landscape1350x1080: return 1080
        }
    }

    var aspectRatio: CGFloat {
        CGFloat(exportWidth) / CGFloat(exportHeight)
    }

    var menuTitle: String {
        switch self {
        case .square1080: return "1 : 1"
        case .portrait1080x1350: return "4 : 5"
        case .portrait1080x1600: return "Tall"
        case .landscape1920x1080: return "16 : 9"
        case .landscape1350x1080: return "5 : 4"
        }
    }

    var menuSubtitle: String {
        "\(exportWidth)×\(exportHeight)"
    }
}

struct LookbooksUploadView: View {
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) private var dismiss
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var selectedImages: [UIImage] = []
    @State private var rawPickerImages: [UIImage] = []
    @State private var showCropFlow = false
    @State private var cropQueueIndex = 0
    @State private var cropAccumulated: [UIImage] = []
    @State private var cropPreset: LookbookUploadCropPreset = .portrait1080x1350
    @State private var caption: String = ""
    @State private var selectedStylePills: Set<String> = []
    @State private var uploadState: UploadState = .idle
    @State private var showTagScreen = false
    @State private var uploadedRecord: LookbookUploadRecord?
    @State private var tagSessionId: String = UUID().uuidString
    @State private var taggedTags: [LookbookTagData] = []
    @State private var taggedProductItems: [Item] = []
    @State private var showSuccessBanner = false
    /// Picker sheet is presented from this level so it is not nested under `.fullScreenCover` (nested sheets often fail to appear).
    @State private var showLookbookTagProductPicker = false
    @State private var lookbookTagPickedProduct: Item?

    private static let maxStylePills = 3
    private static let maxPhotosPerPost = 10

    enum UploadState {
        case idle
        case uploading
        case uploaded
        case failed(String)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    // Upload banner: full width, placeholder or selected image
                    PhotosPicker(
                        selection: $selectedItems,
                        maxSelectionCount: Self.maxPhotosPerPost,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Group {
                            if selectedImages.count == 1, let image = selectedImages.first {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: .infinity)
                            } else if selectedImages.count > 1 {
                                TabView {
                                    ForEach(Array(selectedImages.enumerated()), id: \.offset) { _, image in
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(maxWidth: .infinity)
                                    }
                                }
                                .tabViewStyle(.page(indexDisplayMode: .automatic))
                                .frame(minHeight: 220)
                            } else {
                                VStack(spacing: Theme.Spacing.md) {
                                    Image(systemName: "photo.badge.plus")
                                        .font(.system(size: 44))
                                        .foregroundStyle(Theme.Colors.secondaryText)
                                    Text("Tap to choose photos")
                                        .font(Theme.Typography.body)
                                        .foregroundColor(Theme.Colors.secondaryText)
                                    Text("Up to \(Self.maxPhotosPerPost) — shows as one carousel post")
                                        .font(Theme.Typography.caption)
                                        .foregroundColor(Theme.Colors.secondaryText)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: 200)
                                .background(Theme.Colors.secondaryBackground)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 200)
                        .contentShape(Rectangle())
                    }
                    .onChange(of: selectedItems) { _, newValue in
                        Task { await loadImages(from: newValue) }
                    }

                    if !selectedImages.isEmpty {
                        // Tagged products (shown after returning from Tag screen)
                        if !taggedProductItems.isEmpty {
                            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                                Text("Tagged products")
                                    .font(Theme.Typography.body)
                                    .fontWeight(.medium)
                                    .foregroundColor(Theme.Colors.primaryText)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: Theme.Spacing.sm) {
                                        ForEach(taggedProductItems, id: \.id) { item in
                                            taggedProductChip(item)
                                        }
                                    }
                                    .padding(.vertical, Theme.Spacing.xs)
                                }
                            }
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.top, Theme.Spacing.md)
                        }

                        // Style pills: select up to 3
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Text("Style tags")
                                .font(Theme.Typography.body)
                                .fontWeight(.medium)
                                .foregroundColor(Theme.Colors.secondaryText)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: Theme.Spacing.sm) {
                                    ForEach(lookbookUploadStylePills, id: \.self) { raw in
                                        let isSelected = selectedStylePills.contains(raw)
                                        let canSelect = selectedStylePills.count < Self.maxStylePills || isSelected
                                        Button(action: {
                                            if isSelected {
                                                selectedStylePills.remove(raw)
                                            } else if canSelect {
                                                selectedStylePills.insert(raw)
                                            }
                                        }) {
                                            Text(StyleSelectionView.displayName(for: raw))
                                                .font(Theme.Typography.subheadline)
                                                .foregroundColor(isSelected ? .white : Theme.Colors.primaryText)
                                                .padding(.horizontal, Theme.Spacing.sm)
                                                .padding(.vertical, Theme.Spacing.xs)
                                                .background(isSelected ? Theme.primaryColor : Theme.Colors.secondaryBackground)
                                                .cornerRadius(20)
                                        }
                                        .buttonStyle(PlainTappableButtonStyle())
                                        .disabled(!canSelect && !isSelected)
                                    }
                                }
                                .padding(.vertical, Theme.Spacing.xs)
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.top, Theme.Spacing.md)

                        HashtagCaptionField(
                            label: "Caption",
                            placeholder: "Add a caption (optional)",
                            text: $caption,
                            minLines: 3,
                            maxLines: 6
                        )
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.top, Theme.Spacing.md)
                    }

                    Color.clear.frame(height: 24)
                }
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)

            if case .failed(let msg) = uploadState {
                Text(msg)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal, Theme.Spacing.md)
            }

            PrimaryButtonBar {
                VStack(spacing: Theme.Spacing.sm) {
                    PrimaryGlassButton(
                        "Upload",
                        isEnabled: !selectedImages.isEmpty && !uploadState.uploading,
                        isLoading: uploadState.uploading,
                        action: uploadImage
                    )
                    BorderGlassButton("Tag", isEnabled: !selectedImages.isEmpty, action: { showTagScreen = true })
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.background)
        .overlay {
            if uploadState.uploading {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .overlay {
                        VStack(spacing: Theme.Spacing.lg) {
                            ProgressView()
                                .scaleEffect(1.4)
                                .tint(Theme.Colors.primaryText)
                        }
                        .padding(Theme.Spacing.xl)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Glass.cornerRadius)
                                .fill(Theme.Colors.background)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Glass.cornerRadius)
                                .strokeBorder(Theme.Colors.glassBorder, lineWidth: 1)
                        )
                    }
                    .transition(.opacity)
                    .allowsHitTesting(true)
            }
        }
        .overlay(alignment: .top) {
            if showSuccessBanner {
                successBanner
            }
        }
        .animation(.easeInOut(duration: 0.2), value: uploadState.uploading)
        .animation(.easeInOut(duration: 0.3), value: showSuccessBanner)
        .navigationTitle("Lookbooks Upload")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .fullScreenCover(isPresented: $showCropFlow) {
            if cropQueueIndex < rawPickerImages.count {
                LookbookUploadCropShellView(
                    image: rawPickerImages[cropQueueIndex],
                    imageIndex: cropQueueIndex + 1,
                    totalImages: rawPickerImages.count,
                    preset: $cropPreset,
                    onCancel: cancelCropFlow,
                    onApplyCropped: { cropped in
                        cropAccumulated.append(cropped)
                        if cropQueueIndex + 1 < rawPickerImages.count {
                            cropQueueIndex += 1
                        } else {
                            selectedImages = cropAccumulated
                            cropAccumulated = []
                            cropQueueIndex = 0
                            rawPickerImages = []
                            showCropFlow = false
                            tagSessionId = UUID().uuidString
                            taggedTags = []
                            taggedProductItems = []
                        }
                    }
                )
                .id(cropQueueIndex)
            }
        }
        .fullScreenCover(isPresented: $showTagScreen) {
            if let image = selectedImages.first {
                LookbookTagProductsView(
                    image: image,
                    imageURL: uploadedRecord.flatMap { lookbookImageURL($0.imagePath) },
                    imageId: tagSessionId,
                    initialTags: taggedTags,
                    showProductPicker: $showLookbookTagProductPicker,
                    pickedProduct: $lookbookTagPickedProduct,
                    onDismiss: {
                        showTagScreen = false
                        showLookbookTagProductPicker = false
                        lookbookTagPickedProduct = nil
                    },
                    onConfirm: { newTags, resolved in
                        taggedTags = newTags
                        taggedProductItems = Array(resolved.values)
                    }
                )
                .environmentObject(authService)
            }
        }
    }

    private func taggedProductChip(_ item: Item) -> some View {
        VStack(spacing: 4) {
            Group {
                if let urlString = item.imageURLs.first, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFill()
                        default: Rectangle().fill(Theme.Colors.secondaryBackground).overlay(Image(systemName: "photo").foregroundStyle(Theme.Colors.secondaryText))
                        }
                    }
                } else {
                    Rectangle()
                        .fill(Theme.Colors.secondaryBackground)
                        .overlay(Image(systemName: "photo").foregroundStyle(Theme.Colors.secondaryText))
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(item.title)
                .font(.caption2)
                .foregroundColor(Theme.Colors.primaryText)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 64)
        }
    }

    private func lookbookImageURL(_ path: String) -> URL? {
        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        return dir.appending(path: "lookbooks").appending(path: path)
    }

    private var successBanner: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(Theme.primaryColor)
            Text("Uploaded successfully")
                .font(Theme.Typography.headline)
                .foregroundColor(Theme.Colors.primaryText)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .background(Theme.Colors.background)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Glass.cornerRadius)
                .strokeBorder(Theme.Colors.glassBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Glass.cornerRadius))
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.top, Theme.Spacing.sm)
        .opacity(showSuccessBanner ? 1 : 0)
        .offset(y: showSuccessBanner ? 0 : -30)
    }

    private func cancelCropFlow() {
        showCropFlow = false
        rawPickerImages = []
        cropAccumulated = []
        cropQueueIndex = 0
        selectedItems = []
    }

    private func loadImages(from items: [PhotosPickerItem]) async {
        guard !items.isEmpty else {
            await MainActor.run {
                selectedImages = []
                rawPickerImages = []
                showCropFlow = false
            }
            return
        }
        var images: [UIImage] = []
        images.reserveCapacity(items.count)
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { continue }
            images.append(image)
        }
        await MainActor.run {
            guard !images.isEmpty else {
                selectedImages = []
                rawPickerImages = []
                showCropFlow = false
                return
            }
            rawPickerImages = images
            cropQueueIndex = 0
            cropAccumulated = []
            showCropFlow = true
        }
    }

    private func buildProductSnapshots() -> [String: LookbookProductSnapshot] {
        return Dictionary(uniqueKeysWithValues: taggedProductItems.compactMap { item -> (String, LookbookProductSnapshot)? in
            guard let productId = item.productId, !productId.isEmpty else { return nil }
            return (productId, LookbookProductSnapshot(
                productId: productId,
                title: item.title,
                imageUrl: item.imageURLs.first
            ))
        })
    }

    private func uploadImage() {
        let toUpload = selectedImages
        guard !toUpload.isEmpty else {
            uploadState = .failed("No photos selected")
            return
        }
        uploadState = .uploading
        let client = GraphQLClient()
        client.setAuthToken(authService.authToken)
        let service = LookbookService(client: client)
        service.setAuthToken(authService.authToken)
        let cap = caption
        let styles = selectedStylePills
        let tags = taggedTags
        let snapshots = buildProductSnapshots()
        Task {
            do {
                var urls: [String] = []
                urls.reserveCapacity(toUpload.count)
                for image in toUpload {
                    guard let imageData = image.jpegData(compressionQuality: 0.85) else { continue }
                    let imageUrl = try await service.uploadLookbookImage(imageData)
                    urls.append(imageUrl)
                }
                guard let firstUrl = urls.first else {
                    throw NSError(domain: "LookbooksUpload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not upload images"])
                }
                let post = try await service.createLookbook(imageUrl: firstUrl, caption: cap.isEmpty ? nil : cap)
                let record = LookbookUploadRecord(
                    id: post.id,
                    imagePath: post.imageUrl,
                    imageUrls: urls.count > 1 ? urls : nil,
                    tags: tags,
                    caption: cap.isEmpty ? nil : cap,
                    styles: styles.isEmpty ? nil : Array(styles),
                    productSnapshots: snapshots.isEmpty ? nil : snapshots
                )
                LookbookFeedStore.append(record)
                await MainActor.run {
                    uploadState = .idle
                    selectedImages = []
                    caption = ""
                    selectedStylePills = []
                    selectedItems = []
                    uploadedRecord = nil
                    taggedTags = []
                    taggedProductItems = []
                    HapticManager.success()
                    showSuccessBanner = true
                    Task {
                        try? await Task.sleep(nanoseconds: 2_500_000_000)
                        await MainActor.run {
                            showSuccessBanner = false
                            dismiss()
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    uploadState = .failed(error.localizedDescription)
                }
            }
        }
    }
}

extension LookbooksUploadView.UploadState {
    var uploading: Bool {
        if case .uploading = self { return true }
        return false
    }
}

// MARK: - Lookbook upload crop (fixed aspect + export size)

extension Notification.Name {
    static let lookbookAspectCropExportRequested = Notification.Name("lookbookAspectCropExportRequested")
}

/// Full-screen crop UI: pick one of several export frames, pinch to zoom and drag to reframe.
private struct LookbookUploadCropShellView: View {
    let image: UIImage
    let imageIndex: Int
    let totalImages: Int
    @Binding var preset: LookbookUploadCropPreset
    let onCancel: () -> Void
    let onApplyCropped: (UIImage) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel", action: onCancel)
                    .foregroundStyle(Theme.Colors.primaryText)
                Spacer()
                Text(totalImages > 1 ? "Photo \(imageIndex) of \(totalImages)" : "Frame your photo")
                    .font(Theme.Typography.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Colors.primaryText)
                Spacer()
                Color.clear.frame(width: 56)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(Theme.Colors.background)

            VStack(alignment: .leading, spacing: 6) {
                Text("Export size")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .padding(.horizontal, Theme.Spacing.md)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.sm) {
                        ForEach(LookbookUploadCropPreset.allCases) { p in
                            let on = p == preset
                            Button {
                                preset = p
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.menuTitle)
                                        .font(.subheadline.weight(.semibold))
                                    Text(p.menuSubtitle)
                                        .font(.caption2)
                                        .opacity(0.85)
                                }
                                .foregroundStyle(on ? .white : Theme.Colors.primaryText)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(on ? Theme.primaryColor : Theme.Colors.secondaryBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                }
            }
            .padding(.vertical, Theme.Spacing.sm)
            .background(Theme.Colors.background)

            LookbookAspectCropRepresentable(image: image, preset: preset, onCropped: onApplyCropped)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)

            PrimaryGlassButton(totalImages > 1 && imageIndex < totalImages ? "Next" : "Use photo") {
                NotificationCenter.default.post(name: .lookbookAspectCropExportRequested, object: nil)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
            .background(Theme.Colors.background)
        }
        .background(Theme.Colors.background)
    }
}

private struct LookbookAspectCropRepresentable: UIViewControllerRepresentable {
    let image: UIImage
    let preset: LookbookUploadCropPreset
    let onCropped: (UIImage) -> Void

    func makeUIViewController(context: Context) -> LookbookAspectCropViewController {
        let vc = LookbookAspectCropViewController(image: image, preset: preset)
        vc.onCropped = onCropped
        return vc
    }

    func updateUIViewController(_ uiViewController: LookbookAspectCropViewController, context: Context) {
        uiViewController.setPreset(preset)
    }
}

private final class LookbookAspectCropViewController: UIViewController, UIScrollViewDelegate {
    var onCropped: ((UIImage) -> Void)?
    private let originalImage: UIImage
    private(set) var preset: LookbookUploadCropPreset
    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private var normalizedImage: UIImage?
    private var baseCoverScale: CGFloat = 1

    init(image: UIImage, preset: LookbookUploadCropPreset) {
        self.originalImage = image
        self.preset = preset
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func setPreset(_ newPreset: LookbookUploadCropPreset) {
        guard newPreset != preset else { return }
        preset = newPreset
        scrollView.zoomScale = 1
        view.setNeedsLayout()
        view.layoutIfNeeded()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        normalizedImage = Self.normalizeOrientation(originalImage)
        scrollView.delegate = self
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 5
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.clipsToBounds = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        imageView.contentMode = .scaleToFill
        imageView.isUserInteractionEnabled = false
        scrollView.addSubview(imageView)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(exportRequested),
            name: .lookbookAspectCropExportRequested,
            object: nil
        )
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutCropArea()
    }

    private func layoutCropArea() {
        guard let img = normalizedImage else { return }
        let iw = img.size.width
        let ih = img.size.height
        guard iw > 0, ih > 0, view.bounds.width > 0, view.bounds.height > 0 else { return }

        let aspect = preset.aspectRatio
        let margin: CGFloat = 12
        let inner = view.bounds.insetBy(dx: margin, dy: margin)
        var cw = inner.width
        var ch = cw / aspect
        if ch > inner.height {
            ch = inner.height
            cw = ch * aspect
        }
        let cx = (view.bounds.width - cw) * 0.5
        let cy = (view.bounds.height - ch) * 0.5
        scrollView.frame = CGRect(x: cx, y: cy, width: cw, height: ch)

        baseCoverScale = max(cw / iw, ch / ih)
        let w = iw * baseCoverScale
        let h = ih * baseCoverScale
        imageView.image = img
        imageView.frame = CGRect(x: 0, y: 0, width: w, height: h)
        scrollView.contentSize = CGSize(width: w, height: h)
        scrollView.zoomScale = 1
        let offsetX = max(0, (w - cw) * 0.5)
        let offsetY = max(0, (h - ch) * 0.5)
        scrollView.contentOffset = CGPoint(x: offsetX, y: offsetY)
    }

    @objc private func exportRequested() {
        guard let img = normalizedImage else { return }
        let iw = img.size.width
        let ih = img.size.height
        let W = iw * baseCoverScale
        let H = ih * baseCoverScale
        guard W > 0, H > 0 else { return }

        let z = scrollView.zoomScale
        let ox = scrollView.contentOffset.x / z
        let oy = scrollView.contentOffset.y / z
        let vw = scrollView.bounds.width / z
        let vh = scrollView.bounds.height / z

        let imgX = (ox / W) * iw
        let imgY = (oy / H) * ih
        let imgW = (vw / W) * iw
        let imgH = (vh / H) * ih
        var crop = CGRect(x: imgX, y: imgY, width: imgW, height: imgH)
            .intersection(CGRect(x: 0, y: 0, width: iw, height: ih))
        guard crop.width > 1, crop.height > 1 else { return }

        guard let cgFull = img.cgImage else { return }
        let pxW = CGFloat(cgFull.width)
        let pxH = CGFloat(cgFull.height)
        let sx = pxW / iw
        let sy = pxH / ih
        let pxCrop = CGRect(
            x: crop.minX * sx,
            y: crop.minY * sy,
            width: crop.width * sx,
            height: crop.height * sy
        ).integral
        let boundsPx = CGRect(x: 0, y: 0, width: pxW, height: pxH)
        let clipped = pxCrop.intersection(boundsPx)
        guard clipped.width > 1, clipped.height > 1,
              let croppedCg = cgFull.cropping(to: clipped) else { return }

        let cropped = UIImage(cgImage: croppedCg, scale: 1, orientation: .up)
        let ew = preset.exportWidth
        let eh = preset.exportHeight
        guard let out = Self.resizePreservingAspect(cropped, targetWidth: ew, targetHeight: eh) else { return }
        onCropped?(out)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    private static func normalizeOrientation(_ image: UIImage) -> UIImage {
        if image.imageOrientation == .up { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        let r = UIGraphicsImageRenderer(size: image.size, format: format)
        return r.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    private static func resizePreservingAspect(_ image: UIImage, targetWidth: Int, targetHeight: Int) -> UIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: targetWidth, height: targetHeight)
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

private struct ImageFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let n = nextValue()
        if n != .zero { value = n }
    }
}

// MARK: - Tag products (full-screen): draggable dot + Tag product button

struct LookbookTagProductsView: View {
    var image: UIImage?
    var imageURL: URL?
    let imageId: String
    let initialTags: [LookbookTagData]
    @Binding var showProductPicker: Bool
    @Binding var pickedProduct: Item?
    let onDismiss: () -> Void
    /// Called when user taps Confirm; passes current tags and resolved items so the upload page can show them.
    var onConfirm: (([LookbookTagData], [String: Item]) -> Void)?

    @EnvironmentObject var authService: AuthService
    @State private var tags: [LookbookTagData] = []
    @State private var resolvedItems: [String: Item] = [:]
    @State private var dotPosition: CGPoint = CGPoint(x: 0.5, y: 0.5)
    @State private var selectedItemForDetail: Item?
    @State private var imageFrame: CGRect = .zero

    private let productService = ProductService()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                GeometryReader { geo in
                    ZStack(alignment: .topLeading) {
                        imageContent(geo: geo)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .contentShape(Rectangle())
                            .onTapGesture { showProductPicker = true }
                            .coordinateSpace(name: "lookbookContainer")
                            .onPreferenceChange(ImageFramePreferenceKey.self) { imageFrame = $0 }

                        if imageFrame != .zero {
                            // Dot first so product badges are hit-tested on top (otherwise only the placement dot could be dragged).
                            draggableDot(geo: geo)
                            ForEach(tags) { tag in
                                if let item = resolvedItems[tag.productId] {
                                    lookbookTagBadge(tag: tag, item: item, imageFrame: imageFrame) { newX, newY in
                                        updateTagPosition(tag: tag, newX: newX, newY: newY)
                                    }
                                }
                            }
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                }
                .ignoresSafeArea()

                VStack {
                    HStack {
                        Spacer()
                        Button(action: onDismiss) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.5), radius: 2)
                        }
                        .padding()
                    }
                    Spacer()
                    VStack(spacing: Theme.Spacing.sm) {
                        Button(action: { showProductPicker = true }) {
                            Text("Choose product")
                                .font(Theme.Typography.body.weight(.semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.white.opacity(0.18))
                                .clipShape(RoundedRectangle(cornerRadius: Theme.Glass.cornerRadius, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: Theme.Glass.cornerRadius, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        PrimaryGlassButton(L10n.string("Confirm"), action: {
                            onConfirm?(tags, resolvedItems)
                            onDismiss()
                        })
                    }
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.bottom, Theme.Spacing.xl)
                    .frame(maxWidth: .infinity)
                    .background(Color.black.opacity(0.6))
                }
            }
            .navigationDestination(item: $selectedItemForDetail) { item in
                ItemDetailView(item: item, authService: authService)
            }
        }
        // Sheet must attach here (inside fullScreenCover), not on LookbooksUploadView — otherwise
        // iOS never presents it above the tag UI and "Choose product" appears to do nothing.
        .sheet(isPresented: $showProductPicker) {
            ProductSearchSheet(
                productService: productService,
                authService: authService,
                onSelect: { item in
                    pickedProduct = item
                    showProductPicker = false
                },
                onCancel: {
                    showProductPicker = false
                }
            )
            .environmentObject(authService)
        }
        .onAppear {
            tags = initialTags
            persistTags()
            loadResolvedItems()
        }
        .onChange(of: tags) { _, _ in persistTags() }
        .onChange(of: pickedProduct) { _, new in
            guard let item = new, let pid = item.productId, !pid.isEmpty else { return }
            let tag = LookbookTagData(productId: pid, x: Double(dotPosition.x), y: Double(dotPosition.y))
            tags.append(tag)
            resolvedItems[pid] = item
            pickedProduct = nil
        }
    }

    @ViewBuilder
    private func imageContent(geo: GeometryProxy) -> some View {
        if let img = image {
            Image(uiImage: img)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .background(
                    GeometryReader { inner in
                        Color.clear.preference(
                            key: ImageFramePreferenceKey.self,
                            value: inner.frame(in: .named("lookbookContainer"))
                        )
                    }
                )
        } else if let url = imageURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .background(
                            GeometryReader { inner in
                                Color.clear.preference(
                                    key: ImageFramePreferenceKey.self,
                                    value: inner.frame(in: .named("lookbookContainer"))
                                )
                            }
                        )
                case .failure:
                    Text("Failed to load image").foregroundColor(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
                @unknown default:
                    EmptyView()
                }
            }
        } else {
            Color.gray
        }
    }

    private func lookbookTagBadge(tag: LookbookTagData, item: Item, imageFrame: CGRect, onMove: @escaping (Double, Double) -> Void) -> some View {
        let pointerSize: CGFloat = 24
        let thumbSize: CGFloat = 32
        let cardWidth: CGFloat = 100
        let spacing: CGFloat = 6
        let totalWidth = pointerSize + spacing + cardWidth
        return HStack(alignment: .center, spacing: spacing) {
            Circle()
                .fill(Color.orange.opacity(0.9))
                .frame(width: pointerSize, height: pointerSize)
                .overlay(Circle().stroke(Color.white, lineWidth: 2))
            HStack(spacing: 6) {
                Group {
                    if let urlString = item.imageURLs.first, let url = URL(string: urlString) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img): img.resizable().scaledToFill()
                            case .failure, .empty:
                                Rectangle()
                                    .fill(Theme.Colors.secondaryBackground)
                                    .overlay(Image(systemName: "photo").font(.caption2).foregroundColor(Theme.Colors.secondaryText))
                            @unknown default: EmptyView()
                            }
                        }
                    } else {
                        Rectangle()
                            .fill(Theme.Colors.secondaryBackground)
                            .overlay(Image(systemName: "photo").font(.caption2).foregroundColor(Theme.Colors.secondaryText))
                    }
                }
                .frame(width: thumbSize, height: thumbSize)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                Text(item.brand ?? item.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.75))
            .cornerRadius(8)
            .frame(width: cardWidth, alignment: .leading)
        }
        .frame(width: totalWidth, alignment: .leading)
        .contentShape(Rectangle())
        .highPriorityGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named("lookbookContainer"))
                .onChanged { value in
                    let nx = (value.location.x - imageFrame.minX) / imageFrame.width
                    let ny = (value.location.y - imageFrame.minY) / imageFrame.height
                    let clampedX = min(1, max(0, nx))
                    let clampedY = min(1, max(0, ny))
                    onMove(clampedX, clampedY)
                }
        )
        .onTapGesture {
            selectedItemForDetail = item
        }
        .position(x: imageFrame.minX + imageFrame.width * tag.x - pointerSize / 2 + totalWidth / 2, y: imageFrame.minY + imageFrame.height * tag.y)
        .contextMenu {
            Button(role: .destructive) {
                removeTag(tag)
            } label: {
                Label("Remove tag", systemImage: "trash")
            }
        }
    }

    private func removeTag(_ tag: LookbookTagData) {
        tags.removeAll { $0.id == tag.id }
        if !tags.contains(where: { $0.productId == tag.productId }) {
            resolvedItems.removeValue(forKey: tag.productId)
        }
        persistTags()
    }

    private func updateTagPosition(tag: LookbookTagData, newX: Double, newY: Double) {
        guard let idx = tags.firstIndex(where: { $0.id == tag.id }) else { return }
        tags[idx] = LookbookTagData(productId: tag.productId, x: newX, y: newY)
    }

    private func draggableDot(geo: GeometryProxy) -> some View {
        let px = imageFrame.minX + imageFrame.width * dotPosition.x
        let py = imageFrame.minY + imageFrame.height * dotPosition.y
        return Circle()
            .fill(Color.orange)
            .frame(width: 32, height: 32)
            .overlay(Circle().stroke(Color.white, lineWidth: 3))
            .position(x: px, y: py)
            .gesture(
                DragGesture(coordinateSpace: .named("lookbookContainer"))
                    .onChanged { value in
                        let nx = (value.location.x - imageFrame.minX) / imageFrame.width
                        let ny = (value.location.y - imageFrame.minY) / imageFrame.height
                        dotPosition.x = min(1, max(0, nx))
                        dotPosition.y = min(1, max(0, ny))
                    }
            )
    }

    private func persistTags() {
        LookbookUploadStore.saveTags(imageId: imageId, tags: tags)
        if var record = LookbookUploadStore.loadCurrent(), record.id == imageId {
            record.tags = tags
            LookbookUploadStore.saveCurrent(record: record)
        }
    }

    @MainActor
    private func loadResolvedItems() {
        Task {
            for tag in tags {
                guard let id = Int(tag.productId), resolvedItems[tag.productId] == nil else { continue }
                if let item = try? await productService.getProduct(id: id) {
                    resolvedItems[tag.productId] = item
                }
            }
        }
    }
}

// MARK: - Product search sheet

struct ProductSearchSheet: View {
    let productService: ProductService
    let authService: AuthService
    let onSelect: (Item) -> Void
    let onCancel: () -> Void

    @StateObject private var userService = UserService()
    @State private var query: String = ""
    @State private var myProducts: [Item] = []
    @State private var searchResults: [Item] = []
    @State private var loadingMyProducts = true
    @State private var searching = false

    private var isSearchMode: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }
    private var displayedItems: [Item] { isSearchMode ? searchResults : myProducts }
    private var showEmptyState: Bool {
        if isSearchMode { return !searching && searchResults.isEmpty }
        return !loadingMyProducts && myProducts.isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DiscoverSearchField(
                    text: $query,
                    placeholder: "Search products",
                    showClearButton: true,
                    outerPadding: true
                )
                .onSubmit { if isSearchMode { runSearch() } }

                if showEmptyState {
                    emptyStatePlaceholder
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if loadingMyProducts && !isSearchMode && displayedItems.isEmpty {
                    VStack(spacing: Theme.Spacing.md) {
                        ProgressView()
                        Text("Loading your products…")
                            .font(.subheadline)
                            .foregroundColor(Theme.Colors.secondaryText)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            if searching {
                                HStack(spacing: Theme.Spacing.sm) {
                                    ProgressView()
                                    Text("Searching…")
                                        .font(.subheadline)
                                        .foregroundColor(Theme.Colors.secondaryText)
                                }
                                .padding(.horizontal, Theme.Spacing.md)
                                .padding(.top, Theme.Spacing.sm)
                            }
                            LazyVGrid(
                                columns: [
                                    GridItem(.flexible(), spacing: Theme.Spacing.sm),
                                    GridItem(.flexible(), spacing: Theme.Spacing.sm)
                                ],
                                spacing: Theme.Spacing.md
                            ) {
                                ForEach(displayedItems) { item in
                                    Button {
                                        onSelect(item)
                                    } label: {
                                        WardrobeItemCard(item: item)
                                    }
                                    .buttonStyle(PlainTappableButtonStyle())
                                }
                            }
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, Theme.Spacing.md)
                        }
                    }
                }
            }
            .navigationTitle("Tag product")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
            .onAppear {
                userService.updateAuthToken(authService.authToken)
                loadMyProducts()
            }
            .onChange(of: query) { _, newQuery in
                if newQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                    searchResults = []
                } else {
                    runSearch()
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var emptyStatePlaceholder: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(spacing: Theme.Spacing.md) {
                Image(systemName: isSearchMode ? "magnifyingglass" : "tag")
                    .font(.system(size: 44))
                    .foregroundColor(Theme.Colors.secondaryText)
                Text(isSearchMode ? "No products found" : "You have no products listed yet")
                    .font(.subheadline)
                    .foregroundColor(Theme.Colors.secondaryText)
                    .multilineTextAlignment(.center)
                if isSearchMode {
                    Text("Try a different search term or tag from your list above")
                        .font(.caption)
                        .foregroundColor(Theme.Colors.secondaryText.opacity(0.8))
                        .multilineTextAlignment(.center)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadMyProducts() {
        loadingMyProducts = true
        Task {
            do {
                let username = authService.username
                let items = try await userService.getUserProducts(username: username)
                await MainActor.run {
                    myProducts = items
                    loadingMyProducts = false
                }
            } catch {
                await MainActor.run {
                    myProducts = []
                    loadingMyProducts = false
                }
            }
        }
    }

    private func runSearch() {
        guard isSearchMode else { return }
        searching = true
        Task {
            do {
                let items = try await productService.searchProducts(query: query.trimmingCharacters(in: .whitespaces), pageCount: 20)
                await MainActor.run {
                    searchResults = items
                    searching = false
                }
            } catch {
                await MainActor.run {
                    searchResults = []
                    searching = false
                }
            }
        }
    }
}

#if DEBUG
struct LookbooksUploadView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            LookbooksUploadView()
                .environmentObject(AuthService())
        }
    }
}
#endif

//
//  BackgroundReplacerView.swift
//  Prelura-swift
//
//  Shop tool: remove background (Vision) and place subject on a theme background.
//  Themes are app-provided only; no custom upload.
//

import SwiftUI
import PhotosUI

struct BackgroundReplacerView: View {
    @State private var selectedItem: PhotosPickerItem?
    @State private var sourceImage: UIImage?
    @State private var resultImage: UIImage?
    @State private var selectedTheme: ThemeBackground?
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var showSaveConfirmation = false
    @State private var step: Step = .pickPhoto

    private let service = BackgroundRemovalService()

    enum Step {
        case pickPhoto
        case chooseTheme
        case preview
    }

    var body: some View {
        VStack(spacing: 0) {
            stepIndicator
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.background)
        .navigationTitle("Background replacer")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .onChange(of: selectedItem) { _, new in
            Task { await loadImage(new) }
        }
        .alert("Saved", isPresented: $showSaveConfirmation) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Image saved to Photos.")
        }
    }

    private var stepIndicator: some View {
        HStack(spacing: Theme.Spacing.xs) {
            stepDot(1, active: step != .preview)
            stepLine(active: step == .chooseTheme || step == .preview)
            stepDot(2, active: step == .chooseTheme || step == .preview)
            stepLine(active: step == .preview)
            stepDot(3, active: step == .preview)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .background(Theme.Colors.secondaryBackground.opacity(0.5))
    }

    private func stepDot(_ n: Int, active: Bool) -> some View {
        Circle()
            .fill(active ? Theme.primaryColor : Theme.Colors.tertiaryBackground)
            .frame(width: 10, height: 10)
    }

    private func stepLine(active: Bool) -> some View {
        Rectangle()
            .fill(active ? Theme.primaryColor.opacity(0.6) : Theme.Colors.tertiaryBackground)
            .frame(height: 2)
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .pickPhoto:
            pickPhotoSection
        case .chooseTheme:
            chooseThemeSection
        case .preview:
            previewSection
        }
    }

    private var pickPhotoSection: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                Text("Choose a photo with a person or subject. We'll remove the background and let you pick a theme.")
                    .font(Theme.Typography.subheadline)
                    .foregroundColor(Theme.Colors.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                PhotosPicker(selection: $selectedItem, matching: .images, photoLibrary: .shared()) {
                    Group {
                        if let img = sourceImage {
                            Image(uiImage: img)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 320)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        } else {
                            VStack(spacing: Theme.Spacing.md) {
                                Image(systemName: "photo.on.rectangle.angled")
                                    .font(.system(size: 48))
                                    .foregroundStyle(Theme.Colors.secondaryText)
                                Text("Tap to choose photo")
                                    .font(Theme.Typography.body)
                                    .foregroundColor(Theme.Colors.secondaryText)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 240)
                            .background(Theme.Colors.secondaryBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(isProcessing)

                if sourceImage != nil {
                    Button("Next: Choose theme") {
                        step = .chooseTheme
                        selectedTheme = nil
                        resultImage = nil
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding(Theme.Spacing.lg)
        }
    }

    private var chooseThemeSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text("Pick a theme background")
                    .font(Theme.Typography.headline)
                    .foregroundColor(Theme.Colors.primaryText)
                Text("Use one of our themes to keep your shop looking consistent.")
                    .font(Theme.Typography.subheadline)
                    .foregroundColor(Theme.Colors.secondaryText)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: Theme.Spacing.sm)], spacing: Theme.Spacing.sm) {
                    ForEach(ThemeBackground.all) { theme in
                        ThemeCard(
                            theme: theme,
                            isSelected: selectedTheme?.id == theme.id,
                            action: { selectedTheme = theme }
                        )
                    }
                }

                if let theme = selectedTheme {
                    Button("Apply & preview") {
                        applyAndPreview(theme: theme)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .disabled(isProcessing)
                    if isProcessing {
                        ProgressView()
                            .padding(.top, Theme.Spacing.sm)
                    }
                }
                if let err = errorMessage {
                    Text(err)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.error)
                }
            }
            .padding(Theme.Spacing.lg)
        }
    }

    private var previewSection: some View {
        VStack(spacing: Theme.Spacing.lg) {
            if let img = resultImage {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
            }
            Spacer(minLength: 0)
            VStack(spacing: Theme.Spacing.sm) {
                Button("Save to Photos") {
                    saveToPhotos()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                Button("Start over") {
                    step = .pickPhoto
                    sourceImage = nil
                    selectedItem = nil
                    resultImage = nil
                    selectedTheme = nil
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.xl)
        }
    }

    private func loadImage(_ item: PhotosPickerItem?) async {
        guard let item = item else {
            sourceImage = nil
            return
        }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        await MainActor.run {
            sourceImage = image
            step = .pickPhoto
        }
    }

    private func applyAndPreview(theme: ThemeBackground) {
        guard let image = sourceImage else { return }
        isProcessing = true
        errorMessage = nil
        Task {
            do {
                let result = try await service.removeBackground(from: image, theme: theme)
                await MainActor.run {
                    resultImage = result
                    step = .preview
                    isProcessing = false
                }
            } catch let err as BackgroundRemovalError {
                await MainActor.run {
                    errorMessage = err.errorDescription ?? "Could not process image."
                    isProcessing = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isProcessing = false
                }
            }
        }
    }

    private func saveToPhotos() {
        guard let img = resultImage else { return }
        UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
        showSaveConfirmation = true
    }
}

private struct ThemeCard: View {
    let theme: ThemeBackground
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Theme.Spacing.xs) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        theme.colorBottom != nil
                            ? LinearGradient(
                                colors: [Color(uiColor: theme.colorTop), Color(uiColor: theme.colorBottom!)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            : LinearGradient(colors: [Color(uiColor: theme.colorTop)], startPoint: .top, endPoint: .bottom)
                    )
                    .frame(height: 64)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isSelected ? Theme.primaryColor : Color.clear, lineWidth: 3)
                    )
                Text(theme.name)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.primaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PlainTappableButtonStyle())
    }
}


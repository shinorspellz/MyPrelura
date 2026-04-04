import SwiftUI

/// AsyncImage wrapper that retries loading once on failure (e.g. transient network in chat/product lists).
struct RetryAsyncImage<Placeholder: View, FailurePlaceholder: View>: View {
    let url: URL?
    let width: CGFloat
    let height: CGFloat
    let cornerRadius: CGFloat
    @ViewBuilder let placeholder: () -> Placeholder
    @ViewBuilder let failurePlaceholder: () -> FailurePlaceholder

    @State private var retryId = 0

    init(
        url: URL?,
        width: CGFloat,
        height: CGFloat,
        cornerRadius: CGFloat = 8,
        @ViewBuilder placeholder: @escaping () -> Placeholder,
        @ViewBuilder failurePlaceholder: @escaping () -> FailurePlaceholder
    ) {
        self.url = url
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
        self.placeholder = placeholder
        self.failurePlaceholder = failurePlaceholder
    }

    var body: some View {
        Group {
            if let url = url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        placeholder()
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: width, height: height)
                            .clipped()
                    case .failure:
                        failurePlaceholder()
                            .onAppear {
                                if retryId == 0 {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                        retryId = 1
                                    }
                                }
                            }
                    @unknown default:
                        failurePlaceholder()
                    }
                }
                .id(retryId)
            } else {
                failurePlaceholder()
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .cornerRadius(cornerRadius)
    }
}


import SwiftUI

struct AdminAvatar: View {
    let urlString: String?
    var size: CGFloat = 44

    private var url: URL? {
        MediaURL.resolvedURL(from: urlString)
    }

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(width: size, height: size)
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Theme.Colors.secondaryText.opacity(0.25), lineWidth: 1))
    }

    private var placeholder: some View {
        Image(systemName: "person.crop.circle.fill")
            .resizable()
            .scaledToFit()
            .foregroundStyle(Theme.Colors.secondaryText.opacity(0.6))
            .padding(size * 0.12)
    }
}

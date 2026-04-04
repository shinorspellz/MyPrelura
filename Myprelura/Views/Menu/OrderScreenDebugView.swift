import SwiftUI

/// Debug-only order screen that replicates the reference design: header with order/delivery dates, processing progress bar, product card with attributes and pricing, contact info, customer, shipping address. No Download Invoice button.
struct OrderScreenDebugView: View {
    private static let cardCornerRadius: CGFloat = 16

    private let orderId = "PR23DG2DF3"
    private let orderDate = "Nov 29, 2024"
    private let deliveryDate = "Nov 31, 2024"
    private let statusLabel = "Processing"
    private let progressPercent = 40
    private let productName = "MX Master - 3S"
    private let productAttributes = "Color: Black | Material: Plastic"
    private let originalPrice = "£30,910"
    private let finalPrice = "£25,100"
    private let buyerUsername = "jasontodd"
    private let orderCount = "1 Order"
    /// Same as sell page: width / height = 1 / 1.3
    private static let productThumbnailAspectRatio: CGFloat = 1.0 / 1.3
    private let shippingLines = ["123 High Street", "London", "SW1A 1AA", "United Kingdom"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                headerSection
                processingCard
                productCard
                contactSection
                shippingAddressSection
            }
            .padding(Theme.Spacing.md)
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .background(Theme.Colors.background)
        .navigationTitle("Order details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }

    // MARK: - Header: title + order date + delivery (green)
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Order - \(orderId)")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(Theme.Colors.primaryText)
            HStack(spacing: Theme.Spacing.sm) {
                Text("Order date: \(orderDate)")
                    .font(Theme.Typography.subheadline)
                    .foregroundColor(Theme.Colors.secondaryText)
                Text("|")
                    .foregroundColor(Theme.Colors.secondaryText)
                Image(systemName: "truck.box.fill")
                    .font(.subheadline)
                    .foregroundColor(.green)
                Text("Delivery: \(deliveryDate)")
                    .font(Theme.Typography.subheadline)
                    .foregroundColor(.green)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Processing: icon + label, progress bar (green / green / orange / gray), 40%
    private var processingCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Image("ParcelIcon")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 25)
                    .foregroundColor(Theme.Colors.secondaryText)
                Text(statusLabel)
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.primaryText)
                Spacer()
                Text("\(progressPercent)%")
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.primaryText)
            }
            processingProgressBar
        }
        .padding(Theme.Spacing.md)
        .clipShape(RoundedRectangle(cornerRadius: Self.cardCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Self.cardCornerRadius)
                .stroke(Theme.Colors.glassBorder, lineWidth: 1)
        )
    }

    /// Five dashes with gaps (no solid track): green, green, orange, grey, grey. Container is border only.
    private var processingProgressBar: some View {
        let dashCount = 5
        let gap: CGFloat = 6
        return GeometryReader { geo in
            let w = geo.size.width
            let totalGaps = gap * CGFloat(dashCount - 1)
            let dashWidth = max(4, (w - totalGaps) / CGFloat(dashCount))
            let colors: [Color] = [.green, .green, .orange, Theme.Colors.tertiaryBackground, Theme.Colors.tertiaryBackground]
            HStack(spacing: gap) {
                ForEach(0..<dashCount, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(colors[i])
                        .frame(width: dashWidth, height: 8)
                }
            }
        }
        .frame(height: 8)
        .padding(Theme.Spacing.sm)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Theme.Colors.glassBorder, lineWidth: 1)
        )
        .background(Color.clear)
    }

    // MARK: - Product card: thumbnail (sell aspect 1:1.3), name, attributes, prices, discount tag
    private var productCard: some View {
        ZStack(alignment: .topTrailing) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                productThumbnailView
                VStack(alignment: .leading, spacing: 4) {
                    Text(productName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Theme.Colors.primaryText)
                    Text(productAttributes)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.secondaryText)
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(originalPrice)
                            .font(Theme.Typography.caption)
                            .strikethrough()
                            .foregroundColor(Theme.Colors.secondaryText)
                        Text(finalPrice)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(Theme.Colors.primaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                Spacer(minLength: 0)
            }
            .padding(Theme.Spacing.md)
            .clipShape(RoundedRectangle(cornerRadius: Self.cardCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Self.cardCornerRadius)
                    .stroke(Theme.Colors.glassBorder, lineWidth: 1)
            )
            Image(systemName: "tag.circle.fill")
                .font(.system(size: 22))
                .foregroundColor(Color(red: 1, green: 0.45, blue: 0.5))
                .padding(Theme.Spacing.sm)
        }
    }

    /// Product thumbnail: same aspect ratio as sell page (1 : 1.3). Placeholder until real image URL is wired.
    private var productThumbnailView: some View {
        let width: CGFloat = 72
        let height = width / Self.productThumbnailAspectRatio
        return RoundedRectangle(cornerRadius: 8)
            .fill(Theme.Colors.tertiaryBackground)
            .overlay(Image(systemName: "photo").font(.title2).foregroundColor(Theme.Colors.secondaryText))
            .frame(width: width, height: height)
            .clipped()
    }

    // MARK: - Buyer: card with profile placeholder avatar + jasontodd, bag + order count
    private var contactSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Buyer")
                .font(Theme.Typography.headline)
                .foregroundColor(Theme.Colors.primaryText)
            HStack(spacing: Theme.Spacing.md) {
                profilePhotoPlaceholderView
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(buyerUsername)
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.primaryText)
                    HStack(spacing: 4) {
                        Image(systemName: "bag.fill")
                            .font(.caption)
                            .foregroundColor(Theme.Colors.secondaryText)
                        Text(orderCount)
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.secondaryText)
                    }
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.md)
            .clipShape(RoundedRectangle(cornerRadius: Self.cardCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Self.cardCornerRadius)
                    .stroke(Theme.Colors.glassBorder, lineWidth: 1)
            )
        }
    }

    /// Default profile placeholder used across the app: purple circle + person icon (matches ProfileView).
    private var profilePhotoPlaceholderView: some View {
        Circle()
            .fill(Theme.primaryColor)
            .frame(width: 44, height: 44)
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.white)
            )
    }

    // MARK: - Shipping address (instead of Download Invoice button)
    private var shippingAddressSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Shipping Address")
                .font(Theme.Typography.headline)
                .foregroundColor(Theme.Colors.primaryText)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                ForEach(shippingLines, id: \.self) { line in
                    Text(line)
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.primaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.md)
            .clipShape(RoundedRectangle(cornerRadius: Self.cardCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Self.cardCornerRadius)
                    .stroke(Theme.Colors.glassBorder, lineWidth: 1)
            )
        }
    }
}

#Preview {
    NavigationStack {
        OrderScreenDebugView()
    }
}

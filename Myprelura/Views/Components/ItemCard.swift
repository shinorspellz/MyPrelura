import SwiftUI

struct ItemCard: View {
    let item: Item
    
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            // Image placeholder
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Glass.cornerRadius)
                    .fill(
                        LinearGradient(
                            colors: [
                                Theme.primaryColor.opacity(0.3),
                                Theme.primaryColor.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .aspectRatio(1, contentMode: .fit)
                
                Image(systemName: "photo")
                    .font(.system(size: 40))
                    .foregroundColor(Theme.primaryColor.opacity(0.5))
            }
            
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(item.title)
                    .font(Theme.Typography.subheadline)
                    .foregroundColor(Theme.Colors.primaryText)
                    .lineLimit(2)
                
                Text(item.formattedPrice)
                    .font(Theme.Typography.headline)
                    .foregroundColor(Theme.primaryColor)
            }
            .padding(.horizontal, Theme.Spacing.xs)
            .padding(.bottom, Theme.Spacing.xs)
        }
        .glassEffect()
    }
}

#Preview {
    ItemCard(item: Item.sampleItems[0])
        .padding()
        .preferredColorScheme(.dark)
}

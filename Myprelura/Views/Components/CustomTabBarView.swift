import SwiftUI

/// Custom tab bar overlay that can animate in from the bottom when the navbar reappears.
struct CustomTabBarView: View {
    @Binding var selectedTab: Int
    let tabItems: [(tag: Int, label: String, icon: String)] = [
        (0, "Home", "house.fill"),
        (1, "Discover", "magnifyingglass"),
        (2, "Sell", "plus"),
        (3, "Inbox", "envelope"),
        (4, "Profile", "person.fill")
    ]
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabItems, id: \.tag) { item in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = item.tag
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: item.icon)
                            .font(.system(size: 22, weight: .medium))
                        Text(item.label)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundColor(selectedTab == item.tag ? Theme.primaryColor : Color(uiColor: .secondaryLabel))
                }
                .buttonStyle(PlainTappableButtonStyle())
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(Color(uiColor: UIColor.systemBackground.withAlphaComponent(0.9)))
        .ignoresSafeArea(edges: .bottom)
    }
}

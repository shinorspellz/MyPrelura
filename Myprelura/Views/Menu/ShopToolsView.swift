//
//  ShopToolsView.swift
//  Prelura-swift
//
//  Shop tools submenu: Background replacer (BETA), etc.
//

import SwiftUI

struct ShopToolsView: View {
    var body: some View {
        List {
            NavigationLink(destination: BackgroundReplacerView()) {
                HStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "person.crop.rectangle.badge.plus")
                        .font(.body)
                        .foregroundStyle(Theme.Colors.secondaryText)
                    Text(L10n.string("Background replacer"))
                    Spacer()
                    Text("BETA")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Theme.primaryColor))
                }
            }
        }
        .listStyle(.insetGrouped)
        .background(Theme.Colors.background)
        .navigationTitle(L10n.string("Shop tools"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }
}

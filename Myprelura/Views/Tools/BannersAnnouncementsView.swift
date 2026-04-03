import SwiftUI

struct BannersAnnouncementsView: View {
    @Environment(AdminSession.self) private var session
    @State private var banners: [BannerRow] = []
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                Text("Banners are the primary in-app promotional surface exposed to this GraphQL schema. Broadcast push to arbitrary segments still flows through Django / ops tooling today.")
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(Theme.Colors.error)
            }
            ForEach(banners) { b in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(b.title ?? "Banner")
                            .font(Theme.Typography.headline)
                        Spacer()
                        if b.isActive == true {
                            Text("ACTIVE")
                                .font(.caption2.weight(.bold))
                                .padding(4)
                                .background(Color.green.opacity(0.25))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    Text(b.season ?? "")
                        .font(Theme.Typography.footnote)
                        .foregroundStyle(Theme.Colors.secondaryText)
                    Text("\(b.bannerUrl?.count ?? 0) image URLs")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.tertiaryText)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Banners")
        .adminNavigationChrome()
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.background)
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        errorMessage = nil
        do {
            banners = try await PreluraAdminAPI.banners(client: session.graphQL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

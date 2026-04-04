import SwiftUI

/// Shared order issue detail page for both buyer and seller from chat "Issue with order" card.
struct OrderIssueDetailView: View {
    var issueId: Int? = nil
    var publicId: String? = nil

    @EnvironmentObject var authService: AuthService
    @State private var issue: OrderIssueDetails?
    @State private var isLoading = false
    @State private var errorMessage: String?
    private let userService = UserService()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, Theme.Spacing.md)
                } else if let issue {
                    issueBody(issue)
                } else if let errorMessage {
                    Text(errorMessage)
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.error)
                } else {
                    Text("Issue unavailable")
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.secondaryText)
                }
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.Colors.background)
        .navigationTitle("Issue with order")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task { await load() }
    }

    @ViewBuilder
    private func issueBody(_ issue: OrderIssueDetails) -> some View {
        sectionLabel("Issue type")
        card {
            Text(humanReadableIssueType(issue.issueType))
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.primaryText)
        }

        sectionLabel("Description")
        card {
            Text(issue.description)
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.primaryText)
        }

        if let other = issue.otherIssueDescription, !other.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sectionLabel("Additional details")
            card {
                Text(other)
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.primaryText)
            }
        }

        if !issue.imagesUrl.isEmpty {
            sectionLabel("Images")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(issue.imagesUrl, id: \.self) { urlString in
                        if let url = URL(string: urlString) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let image):
                                    image.resizable().scaledToFill()
                                default:
                                    Rectangle().fill(Theme.Colors.tertiaryBackground)
                                }
                            }
                            .frame(width: 120, height: 120)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            }
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(Theme.Typography.caption)
            .foregroundColor(Theme.Colors.secondaryText)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Glass.cornerRadius))
    }

    private func load() async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        userService.updateAuthToken(authService.authToken)
        do {
            let result = try await userService.getOrderIssue(issueId: issueId, publicId: publicId)
            await MainActor.run {
                issue = result
                isLoading = false
                if issue == nil { errorMessage = "Issue not found" }
            }
        } catch {
            await MainActor.run {
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func humanReadableIssueType(_ raw: String) -> String {
        switch raw {
        case "NOT_AS_DESCRIBED": return "Item not as described"
        case "TOO_SMALL": return "Item is too small"
        case "COUNTERFEIT": return "Item is counterfeit"
        case "DAMAGED": return "Item is damaged or broken"
        case "WRONG_COLOR": return "Item is wrong colour"
        case "WRONG_SIZE": return "Item is wrong size"
        case "DEFECTIVE": return "Item doesn't work / defective"
        case "OTHER": return "Other"
        default: return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}


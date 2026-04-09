import SwiftUI

/// Shared order issue detail page for both buyer and seller from chat "Issue with order" card.
struct OrderIssueDetailView: View {
    var issueId: Int? = nil
    var publicId: String? = nil

    @EnvironmentObject var authService: AuthService
    @State private var issue: OrderIssueDetails?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showWithdrawConfirm = false
    @State private var isWithdrawing = false
    @State private var actionMessage: String?

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
        .confirmationDialog(
            "Withdraw this report?",
            isPresented: $showWithdrawConfirm,
            titleVisibility: .visible
        ) {
            Button("Accept order and withdraw report", role: .destructive) {
                Task { await withdrawReport() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "You will not be able to open another report for this order. If delivery was already confirmed, the sale will be marked complete."
            )
        }
    }

    @ViewBuilder
    private func issueBody(_ issue: OrderIssueDetails) -> some View {
        if let formatted = Self.formatReportDate(issue.createdAt) {
            sectionLabel("Report date and time")
            card {
                Text(formatted)
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.primaryText)
            }
        }

        sectionLabel("Status")
        card {
            Text(humanReadableStatus(issue))
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.primaryText)
        }

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

        if let actionMessage, !actionMessage.isEmpty {
            Text(actionMessage)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.secondaryText)
        }

        if isCurrentUserReporter(issue), isIssuePending(issue) {
            Button {
                showWithdrawConfirm = true
            } label: {
                HStack {
                    if isWithdrawing {
                        ProgressView()
                            .tint(.white)
                    }
                    Text("Cancel report and accept order")
                        .font(Theme.Typography.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.md)
                .background(isWithdrawing ? Theme.Colors.tertiaryBackground : Theme.primaryColor)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Glass.cornerRadius))
            }
            .buttonStyle(.plain)
            .disabled(isWithdrawing)
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

    private func isIssuePending(_ issue: OrderIssueDetails) -> Bool {
        (issue.status ?? "").uppercased() == "PENDING"
    }

    private func isCurrentUserReporter(_ issue: OrderIssueDetails) -> Bool {
        let me = (authService.username ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let reporter = (issue.raisedBy?.username ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !me.isEmpty, !reporter.isEmpty else { return false }
        return me == reporter
    }

    private func humanReadableStatus(_ issue: OrderIssueDetails) -> String {
        let s = (issue.status ?? "").uppercased()
        switch s {
        case "PENDING": return "Pending — under review"
        case "RESOLVED": return resolutionLine(issue) ?? "Resolved"
        case "DECLINED": return "Declined"
        case "WITHDRAWN": return "Withdrawn — you accepted the order"
        default:
            return s.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func resolutionLine(_ issue: OrderIssueDetails) -> String? {
        let res = (issue.resolution ?? "").uppercased()
        if res == "REFUND_WITHOUT_RETURN" { return "Resolved — refund without return" }
        if res == "REFUND_WITH_RETURN" {
            if issue.returnPostagePaidBy == "SELLER" { return "Resolved — refund with return (seller pays return postage)" }
            if issue.returnPostagePaidBy == "BUYER" { return "Resolved — refund with return (buyer pays return postage)" }
            return "Resolved — refund with return"
        }
        return nil
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

    private func withdrawReport() async {
        guard let id = issue?.id else { return }
        await MainActor.run {
            isWithdrawing = true
            actionMessage = nil
        }
        userService.updateAuthToken(authService.authToken)
        do {
            let result = try await userService.withdrawOrderCase(issueId: id)
            await MainActor.run {
                isWithdrawing = false
                if result.success {
                    actionMessage = result.message
                } else {
                    actionMessage = result.message ?? "Could not withdraw this report."
                }
            }
            if result.success {
                await load()
            }
        } catch {
            await MainActor.run {
                isWithdrawing = false
                actionMessage = error.localizedDescription
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

    private static func formatReportDate(_ iso: String?) -> String? {
        guard let iso, !iso.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let trimmed = iso.trimmingCharacters(in: .whitespacesAndNewlines)
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        let date = f1.date(from: trimmed) ?? f2.date(from: trimmed)
        guard let date else { return trimmed }
        let out = DateFormatter()
        out.dateStyle = .medium
        out.timeStyle = .short
        return out.string(from: date)
    }
}

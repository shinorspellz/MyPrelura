import SwiftUI

struct MyReportsView: View {
    @EnvironmentObject var authService: AuthService
    private let userService = UserService()

    @State private var reports: [MyReportRow] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedType: ReportTypeFilter = .all

    private enum ReportTypeFilter: String, CaseIterable {
        case all = "All"
        case product = "Product reports"
        case account = "User reports"
    }

    private var filteredReports: [MyReportRow] {
        switch selectedType {
        case .all:
            return reports
        case .product:
            return reports.filter { ($0.reportType ?? "").uppercased() == "PRODUCT" }
        case .account:
            return reports.filter { ($0.reportType ?? "").uppercased() == "ACCOUNT" }
        }
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            if !reports.isEmpty {
                filterPills
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.top, Theme.Spacing.xs)
            }
            Group {
                if isLoading && reports.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage, reports.isEmpty {
                    Text(errorMessage)
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.error)
                        .multilineTextAlignment(.center)
                        .padding()
                } else if filteredReports.isEmpty {
                    Text("No reports yet.")
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.secondaryText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(filteredReports) { report in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(report.publicId ?? "Report #\(report.id)")
                                    .font(Theme.Typography.headline)
                                    .foregroundColor(Theme.Colors.primaryText)
                                Text((report.reportType ?? "REPORT") + " • " + (report.status ?? "PENDING"))
                                    .font(Theme.Typography.caption)
                                    .foregroundColor(Theme.Colors.secondaryText)
                                if let target = report.accountReportedUsername, !target.isEmpty {
                                    Text("Reported account: \(target)")
                                        .font(Theme.Typography.caption)
                                        .foregroundColor(Theme.Colors.secondaryText)
                                } else if let name = report.productName, !name.isEmpty {
                                    Text("Reported product: \(name)")
                                        .font(Theme.Typography.caption)
                                        .foregroundColor(Theme.Colors.secondaryText)
                                }
                                if let created = report.dateCreated, !created.isEmpty {
                                    Text(Self.formatAdminRelativeDate(iso: created))
                                        .font(Theme.Typography.caption)
                                        .foregroundColor(Theme.Colors.secondaryText)
                                }
                            }
                            .padding(.vertical, Theme.Spacing.xs)
                        }
                    }
                    .listStyle(.plain)
                }
            }
        }
        .background(Theme.Colors.background)
        .navigationTitle("My reports")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .refreshable { await load() }
        .task {
            userService.updateAuthToken(authService.authToken)
            await load()
        }
    }

    private var filterPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.xs) {
                ForEach(ReportTypeFilter.allCases, id: \.rawValue) { filter in
                    Button {
                        selectedType = filter
                    } label: {
                        Text(filter.rawValue)
                            .font(Theme.Typography.caption.weight(.semibold))
                            .foregroundColor(selectedType == filter ? Theme.Colors.primaryText : Theme.Colors.secondaryText)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(selectedType == filter ? Theme.Colors.secondaryBackground : Theme.Colors.background)
                            )
                            .overlay(Capsule().stroke(Theme.Colors.glassBorder, lineWidth: 1))
                    }
                    .buttonStyle(PlainTappableButtonStyle())
                }
            }
        }
    }

    private func load() async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        do {
            let rows = try await userService.getMyReports()
            await MainActor.run {
                reports = rows
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    private static func formatAdminRelativeDate(iso: String) -> String {
        let parsers: [ISO8601DateFormatter] = {
            let f1 = ISO8601DateFormatter()
            f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let f2 = ISO8601DateFormatter()
            f2.formatOptions = [.withInternetDateTime]
            return [f1, f2]
        }()
        guard let date = parsers.compactMap({ $0.date(from: iso) }).first else { return iso }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

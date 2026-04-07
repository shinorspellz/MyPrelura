import SwiftUI

struct HostedWebArticleView: View {
    let title: String
    let urlString: String
    @State private var isLoading = true

    var body: some View {
        Group {
            if let url = URL(string: urlString) {
                ZStack(alignment: .top) {
                    WebView(url: url, isLoading: $isLoading)
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Theme.Colors.background)
                    }
                }
            } else {
                legalFallback(title: title, message: "Unable to load this page.")
            }
        }
        .background(Theme.Colors.background)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }
}

struct TermsAndConditionsView: View {
    @State private var isLoading = true
    private var url: URL? { URL(string: Constants.termsAndConditionsURL) }

    var body: some View {
        Group {
            if let url = url {
                ZStack(alignment: .top) {
                    WebView(url: url, isLoading: $isLoading)
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Theme.Colors.background)
                    }
                }
            } else {
                legalFallback(title: "Terms & Conditions", message: "Unable to load the terms page.")
            }
        }
        .background(Theme.Colors.background)
        .navigationTitle("Terms & Conditions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }
}

struct PrivacyPolicyView: View {
    @State private var isLoading = true
    private var url: URL? { URL(string: Constants.privacyPolicyURL) }

    var body: some View {
        Group {
            if let url = url {
                ZStack(alignment: .top) {
                    WebView(url: url, isLoading: $isLoading)
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Theme.Colors.background)
                    }
                }
            } else {
                legalFallback(title: "Privacy Policy", message: "Unable to load the privacy policy.")
            }
        }
        .background(Theme.Colors.background)
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }
}

struct AcknowledgementsView: View {
    @State private var isLoading = true
    private var url: URL? { URL(string: Constants.acknowledgementsURL) }

    var body: some View {
        Group {
            if let url = url {
                ZStack(alignment: .top) {
                    WebView(url: url, isLoading: $isLoading)
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Theme.Colors.background)
                    }
                }
            } else {
                staticAcknowledgements
            }
        }
        .background(Theme.Colors.background)
        .navigationTitle("Acknowledgements")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }

    private var staticAcknowledgements: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text("Prelura thanks the following open-source projects and services that help power this app.")
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.secondaryText)
                Text("• Swift & SwiftUI (Apple)")
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.primaryText)
                Text("• Additional acknowledgements may be available on our website.")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.md)
        }
    }
}

struct HMRCReportingView: View {
    @State private var isLoading = true
    private var url: URL? { URL(string: Constants.hmrcReportingURL) }

    var body: some View {
        Group {
            if let url = url {
                ZStack(alignment: .top) {
                    WebView(url: url, isLoading: $isLoading)
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Theme.Colors.background)
                    }
                }
            } else {
                legalFallback(title: "HMRC reporting centre", message: "You can report fraud or an untrustworthy website via the UK government’s HMRC contact page.")
            }
        }
        .background(Theme.Colors.background)
        .navigationTitle("HMRC reporting centre")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }
}

// MARK: - Shared helpers
private func legalFallback(title: String, message: String) -> some View {
    ScrollView {
        Text(message)
            .font(Theme.Typography.body)
            .foregroundColor(Theme.Colors.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.md)
    }
}

import SwiftUI

/// Matches Flutter LegalInformationScreen: Terms, Privacy Policy, Acknowledgements, HMRC reporting centre.
struct LegalInformationView: View {
    var body: some View {
        List {
            NavigationLink(destination: TermsAndConditionsView()) {
                menuRow("Terms & Conditions", icon: "doc.text")
            }
            NavigationLink(destination: PrivacyPolicyView()) {
                menuRow("Privacy Policy", icon: "lock.shield")
            }
            NavigationLink(destination: AcknowledgementsView()) {
                menuRow("Acknowledgements", icon: "checkmark.circle")
            }
            NavigationLink(destination: HMRCReportingView()) {
                menuRow("HMRC reporting centre", icon: "building.2")
            }
        }
        .listStyle(.insetGrouped)
        .background(Theme.Colors.background)
        .navigationTitle("Legal Information")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }

    private func menuRow(_ title: String, icon: String) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(Theme.Colors.secondaryText)
            Text(title)
                .foregroundColor(Theme.Colors.primaryText)
        }
    }
}

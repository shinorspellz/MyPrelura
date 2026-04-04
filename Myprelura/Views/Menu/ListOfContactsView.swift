import SwiftUI
import Contacts

/// Contacts screen: request access, show contact list, and invite friends to Prelura via share sheet.
struct ListOfContactsView: View {
    @State private var authorizationStatus: CNAuthorizationStatus = .notDetermined
    @State private var contacts: [ContactDisplay] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showShareSheet = false
    @State private var shareItem: ShareItem?

    private let store = CNContactStore()
    private static var inviteMessage: String {
        "Join me on Prelura — buy and sell preloved fashion. \(Constants.inviteToPreluraURL)"
    }

    var body: some View {
        Group {
            if authorizationStatus == .notDetermined {
                accessPromptView
            } else if authorizationStatus == .denied || authorizationStatus == .restricted {
                accessDeniedView
            } else {
                contactListView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.background)
        .navigationTitle(L10n.string("Contacts"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task { await updateAuthorizationStatus() }
        .onChange(of: authorizationStatus) { _, new in
            if new == .authorized { Task { await fetchContacts() } }
        }
        .sheet(item: $shareItem) { item in
            ActivityView(activityItems: item.items)
        }
    }

    private var accessPromptView: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                VStack(spacing: Theme.Spacing.md) {
                    Text("Access your contacts to invite friends")
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.secondaryText)
                        .multilineTextAlignment(.center)
                    Text("to Prelura.")
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, Theme.Spacing.xl)
                Spacer(minLength: 0)
            }
            PrimaryButtonBar {
                PrimaryGlassButton("Allow access", action: requestAccess)
            }
        }
    }

    private var accessDeniedView: some View {
        VStack(spacing: Theme.Spacing.md) {
            Spacer()
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 56))
                .foregroundColor(Theme.Colors.secondaryText)
            Text("Contact access was denied.")
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.primaryText)
                .multilineTextAlignment(.center)
            Text("You can allow access in Settings → Prelura → Contacts.")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button(action: openSettings) {
                Text("Open Settings")
                    .font(Theme.Typography.headline)
                    .foregroundColor(Theme.primaryColor)
            }
            .padding(.top, Theme.Spacing.sm)
            Spacer()
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private var contactListView: some View {
        VStack(spacing: 0) {
            if let err = errorMessage {
                Text(err)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.error)
                    .padding(Theme.Spacing.md)
            }
            if isLoading && contacts.isEmpty {
                Spacer()
                ProgressView()
                Spacer()
            } else if contacts.isEmpty {
                Spacer()
                Text("No contacts found.")
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.secondaryText)
                Spacer()
            } else {
                List {
                    ForEach(contacts) { contact in
                        HStack(spacing: Theme.Spacing.md) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(contact.displayName)
                                    .font(Theme.Typography.headline)
                                    .foregroundColor(Theme.Colors.primaryText)
                                if let phone = contact.phoneNumber {
                                    Text(phone)
                                        .font(Theme.Typography.caption)
                                        .foregroundColor(Theme.Colors.secondaryText)
                                }
                            }
                            Spacer(minLength: 0)
                            Button(action: { invite(contact: contact) }) {
                                Text("Invite")
                                    .font(Theme.Typography.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(Theme.primaryColor)
                            }
                            .buttonStyle(HapticTapButtonStyle(haptic: { HapticManager.primaryAction() }))
                        }
                        .padding(.vertical, Theme.Spacing.xs)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private func updateAuthorizationStatus() async {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        await MainActor.run { authorizationStatus = status }
    }

    private func requestAccess() {
        Task {
            do {
                let granted = try await store.requestAccess(for: .contacts)
                await MainActor.run {
                    authorizationStatus = granted ? .authorized : .denied
                }
            } catch {
                await MainActor.run {
                    authorizationStatus = .denied
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func fetchContacts() async {
        await MainActor.run { isLoading = true; errorMessage = nil }
        defer { Task { @MainActor in isLoading = false } }
        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor
        ]
        let request = CNContactFetchRequest(keysToFetch: keys)
        request.sortOrder = .givenName
        var result: [ContactDisplay] = []
        do {
            try store.enumerateContacts(with: request) { contact, _ in
                let name = [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")
                let phone = contact.phoneNumbers.first?.value.stringValue
                if !name.isEmpty {
                    result.append(ContactDisplay(id: contact.identifier, displayName: name, phoneNumber: phone))
                }
            }
            await MainActor.run { contacts = result }
        } catch {
            await MainActor.run {
                contacts = []
                errorMessage = error.localizedDescription
            }
        }
    }

    private func invite(contact: ContactDisplay) {
        shareItem = ShareItem(items: [Self.inviteMessage as Any])
    }
}

private struct ContactDisplay: Identifiable {
    let id: String
    let displayName: String
    let phoneNumber: String?
}

private struct ShareItem: Identifiable {
    let id = UUID()
    let items: [Any]
}

// MARK: - UIKit share sheet wrapper
private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

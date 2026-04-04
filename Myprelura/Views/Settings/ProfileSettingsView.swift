import SwiftUI

/// Profile details: username, bio, location only. Same UI pattern as Account Settings (ScrollView + SettingsTextField/Editor + PrimaryButtonBar).
/// Load from UserService.getUser(); save via UserService.updateProfile(bio:username:location:).
struct ProfileSettingsView: View {
    @State private var username: String = ""
    @State private var bio: String = ""
    @State private var location: String = ""

    private let bioMaxLength = 100

    @State private var isLoading = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showSuccess = false
    @FocusState private var focusedField: Field?
    @State private var loadedUser: User?

    private let userService = UserService()

    private enum Field { case username, bio, location }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    SettingsTextField(
                        placeholder: L10n.string("Username"),
                        text: $username,
                        textContentType: .username
                    )
                    .focused($focusedField, equals: .username)

                    ZStack(alignment: .bottomTrailing) {
                        SettingsTextEditor(placeholder: L10n.string("Bio"), text: $bio, minHeight: 100, maxLength: bioMaxLength)
                            .focused($focusedField, equals: .bio)
                        Text("\(bio.count)/\(bioMaxLength)")
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.secondaryText)
                            .padding(Theme.Spacing.sm)
                    }

                    LocationSuggestionField(
                        placeholder: L10n.string("Location"),
                        text: $location,
                        isFocused: focusedField == .location
                    )
                    .focused($focusedField, equals: .location)

                    if let err = errorMessage {
                        Text(err)
                            .font(Theme.Typography.caption)
                            .foregroundColor(.red)
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.lg)
                .padding(.bottom, 100)
            }
            .background(Theme.Colors.background)

            PrimaryButtonBar {
                PrimaryGlassButton(L10n.string("Save"), isLoading: isSaving, action: save)
            }
        }
        .navigationTitle(L10n.string("Profile"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .onAppear(perform: loadUser)
        .alert(L10n.string("Saved"), isPresented: $showSuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(L10n.string("Your profile has been updated."))
        }
    }

    private func loadUser() {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let user = try await userService.getUser()
                await MainActor.run {
                    loadedUser = user
                    username = user.username
                    bio = String((user.bio ?? "").prefix(bioMaxLength))
                    location = user.location ?? ""
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

    private func save() {
        guard let user = loadedUser else { return }
        isSaving = true
        errorMessage = nil
        Task {
            do {
                let usernameTrimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
                let bioTrimmed = bio.trimmingCharacters(in: .whitespacesAndNewlines)
                let locationTrimmed = location.trimmingCharacters(in: .whitespacesAndNewlines)
                // Only send username if it changed (backend rejects "already taken" when sending current username).
                let usernameToSend: String? = {
                    let new = usernameTrimmed.isEmpty ? nil : usernameTrimmed.lowercased()
                    guard let n = new else { return nil }
                    if n == user.username.lowercased() { return nil }
                    return n
                }()
                try await userService.updateProfile(
                    bio: bioTrimmed.isEmpty ? nil : String(bioTrimmed.prefix(bioMaxLength)),
                    username: usernameToSend,
                    location: locationTrimmed.isEmpty ? nil : locationTrimmed
                )
                await MainActor.run {
                    isSaving = false
                    showSuccess = true
                    NotificationCenter.default.post(name: .preluraUserProfileDidUpdate, object: nil)
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSaving = false
                }
            }
        }
    }
}

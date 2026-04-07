import SwiftUI

/// Staff: opened from the profile flag — report, suspend, or ban. Consumer builds only see Report.
struct StaffProfileModerationMenuView: View {
    let username: String
    let userId: Int?
    /// When nil (consumer app / no staff session), only the report row is shown.
    var staffGraphQL: GraphQLClient?

    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var busy = false
    @State private var confirmSuspend = false
    @State private var confirmBan = false

    private var canModerate: Bool {
        staffGraphQL != nil && userId != nil
    }

    var body: some View {
        List {
            Section {
                NavigationLink {
                    ReportUserView(username: username)
                } label: {
                    Label("Report user", systemImage: "flag")
                }
            }

            if canModerate {
                Section("Admin") {
                    Button(role: .destructive) {
                        confirmSuspend = true
                    } label: {
                        Label("Suspend account", systemImage: "pause.circle")
                    }
                    .disabled(busy)

                    Button(role: .destructive) {
                        confirmBan = true
                    } label: {
                        Label("Ban user", systemImage: "hand.raised.fill")
                    }
                    .disabled(busy)
                }
            }
        }
        .navigationTitle("User actions")
        .navigationBarTitleDisplayMode(.inline)
        .adminNavigationChrome()
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.background)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        .overlay {
            if busy {
                ProgressView()
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .alert("Suspend this user?", isPresented: $confirmSuspend) {
            Button("Cancel", role: .cancel) {}
            Button("Suspend", role: .destructive) {
                Task { await runSuspend() }
            }
        } message: {
            Text("They will not be able to sign in until re-enabled in Django admin.")
        }
        .alert("Ban this user?", isPresented: $confirmBan) {
            Button("Cancel", role: .cancel) {}
            Button("Ban", role: .destructive) {
                Task { await runBan() }
            }
        } message: {
            Text("Marks the account as banned on the marketplace.")
        }
        .alert("Done", isPresented: Binding(
            get: { successMessage != nil },
            set: { if !$0 { successMessage = nil; dismiss() } }
        )) {
            Button("OK", role: .cancel) {
                successMessage = nil
                dismiss()
            }
        } message: {
            Text(successMessage ?? "")
        }
        .alert("Could not complete action", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func runSuspend() async {
        guard let client = staffGraphQL, let uid = userId else { return }
        busy = true
        defer { busy = false }
        do {
            let r = try await PreluraAdminAPI.adminSuspendUser(client: client, userId: uid)
            if r.success == true {
                successMessage = r.message ?? "User suspended."
            } else {
                errorMessage = r.message ?? "Suspend failed."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func runBan() async {
        guard let client = staffGraphQL, let uid = userId else { return }
        busy = true
        defer { busy = false }
        do {
            let r = try await PreluraAdminAPI.adminBanUser(client: client, userId: uid)
            if r.success == true {
                successMessage = r.message ?? "User banned."
            } else {
                errorMessage = r.message ?? "Ban failed."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

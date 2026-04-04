import Foundation
import Observation

@MainActor
@Observable
final class AdminSession {
    private let client = GraphQLClient()
    private static let kToken = "MYPRELURA_AUTH_TOKEN"
    private static let kRefresh = "MYPRELURA_REFRESH_TOKEN"
    private static let kUsername = "MYPRELURA_USERNAME"

    private(set) var accessToken: String?
    private(set) var refreshToken: String?
    private(set) var username: String?
    private(set) var accessLevel: StaffAccessLevel = .staff
    private(set) var isBootstrapped = false

    var isSignedIn: Bool { accessToken != nil }

    var graphQL: GraphQLClient { client }

    init() {
        accessToken = UserDefaults.standard.string(forKey: Self.kToken)
        refreshToken = UserDefaults.standard.string(forKey: Self.kRefresh)
        username = UserDefaults.standard.string(forKey: Self.kUsername)
        client.setAuthToken(accessToken)
        syncConsumerUserDefaultsFromStaffSession()
    }

    /// Runs once per app launch after UI is ready; restores staff role when tokens were saved from a prior session.
    func bootstrapIfNeeded() async {
        guard !isBootstrapped else { return }
        isBootstrapped = true
        guard isSignedIn else { return }
        await refreshRoleFromServer()
    }

    func refreshRoleFromServer() async {
        guard isSignedIn else { return }
        do {
            if let me = try await PreluraAdminAPI.viewMe(client: client) {
                if me.isSuperuser == true {
                    accessLevel = .admin
                } else {
                    accessLevel = .staff
                }
                if let u = me.username { username = u }
            }
        } catch {
            // Keep cached role; token may be expired.
        }
    }

    func signIn(username: String, password: String) async throws {
        let payload = try await PreluraAdminAPI.adminLogin(client: client, username: username, password: password)
        guard let token = payload.token, let refresh = payload.refreshToken else {
            throw GraphQLError.graphQLErrors([GraphQLErrorResponse(message: "Missing tokens")])
        }
        let uname = payload.user?.username ?? username
        UserDefaults.standard.set(token, forKey: Self.kToken)
        UserDefaults.standard.set(refresh, forKey: Self.kRefresh)
        UserDefaults.standard.set(uname, forKey: Self.kUsername)
        accessToken = token
        refreshToken = refresh
        self.username = uname
        client.setAuthToken(token)
        syncConsumerUserDefaultsFromStaffSession()
        await refreshRoleFromServer()
    }

    func signOut() {
        UserDefaults.standard.removeObject(forKey: Self.kToken)
        UserDefaults.standard.removeObject(forKey: Self.kRefresh)
        UserDefaults.standard.removeObject(forKey: Self.kUsername)
        accessToken = nil
        refreshToken = nil
        username = nil
        accessLevel = .staff
        client.setAuthToken(nil)
        isBootstrapped = false
        clearConsumerUserDefaultsStaffMirror()
    }

    /// So `UserService` / `UserProfileViewModel` use the same Bearer token as `adminLogin`.
    private func syncConsumerUserDefaultsFromStaffSession() {
        guard let accessToken, !accessToken.isEmpty else {
            clearConsumerUserDefaultsStaffMirror()
            return
        }
        UserDefaults.standard.set(accessToken, forKey: "AUTH_TOKEN")
        if let refreshToken, !refreshToken.isEmpty {
            UserDefaults.standard.set(refreshToken, forKey: "REFRESH_TOKEN")
        }
        if let username, !username.isEmpty {
            UserDefaults.standard.set(username, forKey: "USERNAME")
        }
        UserDefaults.standard.set(false, forKey: "IS_GUEST_MODE")
    }

    private func clearConsumerUserDefaultsStaffMirror() {
        UserDefaults.standard.removeObject(forKey: "AUTH_TOKEN")
        UserDefaults.standard.removeObject(forKey: "REFRESH_TOKEN")
        UserDefaults.standard.removeObject(forKey: "USERNAME")
    }
}

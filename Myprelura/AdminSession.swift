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
    }

    func bootstrapIfNeeded() async {
        guard !isBootstrapped, isSignedIn else {
            isBootstrapped = true
            return
        }
        await refreshRoleFromServer()
        isBootstrapped = true
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
    }
}

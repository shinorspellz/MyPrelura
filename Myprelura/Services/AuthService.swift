import Combine
import FirebaseCore
import FirebaseMessaging
import Foundation
import OSLog
import UIKit
import UserNotifications

private let authSessionLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Prelura", category: "AuthSession")

@MainActor
class AuthService: ObservableObject {
    private let client: GraphQLClient
    @Published var authToken: String?
    @Published var refreshToken: String?
    @Published var username: String?
    /// When true, user chose "Continue as guest" and can browse without logging in. No auth sent for feed/product APIs.
    @Published var isGuestMode: Bool = false
    /// Set to true after email verification + login so the app shows onboarding then feed.
    @Published var shouldShowOnboardingAfterLogin: Bool = false

    private static let kGuestMode = "IS_GUEST_MODE"
    private static let kOnboardingCompleted = "ONBOARDING_COMPLETED"
    
    init(client: GraphQLClient = GraphQLClient()) {
        self.client = client
        loadStoredTokens()
    }
    
    /// Call after Myprelura staff signs in/out via `AdminSession` (syncs `AUTH_TOKEN` keys).
    func reloadTokensFromStorage() {
        loadStoredTokens()
        objectWillChange.send()
    }

    private func loadStoredTokens() {
        // Load from UserDefaults
        authToken = UserDefaults.standard.string(forKey: "AUTH_TOKEN")
        refreshToken = UserDefaults.standard.string(forKey: "REFRESH_TOKEN")
        username = UserDefaults.standard.string(forKey: "USERNAME")
        isGuestMode = UserDefaults.standard.bool(forKey: Self.kGuestMode)
        
        if isGuestMode {
            authToken = nil
            refreshToken = nil
            username = nil
            client.setAuthToken(nil)
        } else if let token = authToken {
            client.setAuthToken(token)
        }
    }
    
    private func storeTokens(token: String, refreshToken: String, username: String) {
        UserDefaults.standard.set(token, forKey: "AUTH_TOKEN")
        UserDefaults.standard.set(refreshToken, forKey: "REFRESH_TOKEN")
        UserDefaults.standard.set(username, forKey: "USERNAME")
        UserDefaults.standard.set(false, forKey: Self.kGuestMode)
        self.authToken = token
        self.refreshToken = refreshToken
        self.username = username
        self.isGuestMode = false
        client.setAuthToken(token)
        // After login, upload FCM token to backend (same moment GraphQL has Bearer token).
        NotificationCenter.default.post(name: .preluraDeviceTokenDidUpdate, object: nil)
        // OSLog: visible when filtering `subsystem == com.prelura.preloved`. Never log raw JWTs.
        authSessionLogger.info("Session stored for \(username, privacy: .public) — access JWT \(token.count, privacy: .public) chars, refresh \(refreshToken.count, privacy: .public) chars.")
        print("[Auth] Session stored for \(username) — access JWT \(token.count) chars, refresh \(refreshToken.count) chars.")
    }
    
    func login(username: String, password: String) async throws -> LoginResponse {
        let query = """
        mutation Login($username: String!, $password: String!) {
          login(username: $username, password: $password) {
            token
            refreshToken
            user {
              id
              username
              email
            }
          }
        }
        """
        
        let variables: [String: Any] = [
            "username": username,
            "password": password
        ]
        
        let response: LoginGraphQLResponse = try await client.execute(
            query: query,
            variables: variables,
            responseType: LoginGraphQLResponse.self
        )
        
        guard let loginData = response.login else {
            throw AuthError.invalidResponse
        }
        
        guard let token = loginData.token,
              let refreshToken = loginData.refreshToken else {
            throw AuthError.invalidResponse
        }
        
        storeTokens(
            token: token,
            refreshToken: refreshToken,
            username: loginData.user?.username ?? username
        )
        
        // Update other services with new token
        objectWillChange.send()
        
        return loginData
    }
    
    /// Verify email/account with code from verification link. Matches Flutter verifyAccount(code). No auth required.
    func verifyAccount(code: String) async throws -> Bool {
        let mutation = """
        mutation VerifyAccount($code: String!) {
          verifyAccount(code: $code) {
            success
          }
        }
        """
        struct Payload: Decodable { let verifyAccount: VerifyResult? }
        struct VerifyResult: Decodable { let success: Bool? }
        let response: Payload = try await client.execute(
            query: mutation,
            variables: ["code": code],
            responseType: Payload.self
        )
        return response.verifyAccount?.success ?? false
    }

    /// Resend verification code to the given email. No auth required. Use when user didn't receive the code.
    func resendActivationEmail(email: String) async throws -> Bool {
        let mutation = """
        mutation ResendActivationEmail($email: String!) {
          resendActivationEmail(email: $email) {
            success
          }
        }
        """
        struct Payload: Decodable { let resendActivationEmail: ResendResult? }
        struct ResendResult: Decodable { let success: Bool? }
        let response: Payload = try await client.execute(
            query: mutation,
            variables: ["email": email],
            responseType: Payload.self
        )
        return response.resendActivationEmail?.success ?? false
    }

    func register(
        email: String,
        firstName: String,
        lastName: String,
        username: String,
        password1: String,
        password2: String
    ) async throws -> RegisterResponse {
        let query = """
        mutation Register($email: String!, $firstName: String!, $lastName: String!, $username: String!, $password1: String!, $password2: String!) {
          register(
            email: $email
            firstName: $firstName
            lastName: $lastName
            username: $username
            password1: $password1
            password2: $password2
          ) {
            success
            errors
          }
        }
        """
        
        let variables: [String: Any] = [
            "email": email,
            "firstName": firstName,
            "lastName": lastName,
            "username": username,
            "password1": password1,
            "password2": password2
        ]
        
        let response: RegisterGraphQLResponse = try await client.execute(
            query: query,
            variables: variables,
            responseType: RegisterGraphQLResponse.self
        )
        
        guard let registerData = response.register else {
            throw AuthError.invalidResponse
        }
        
        if let errors = registerData.errors, !errors.isEmpty {
            // Extract first error message
            for (_, messages) in errors {
                if let firstMessage = messages.first {
                    throw AuthError.registrationError(firstMessage)
                }
            }
            throw AuthError.registrationError("Registration failed")
        }
        
        return registerData
    }
    
    /// Signs out locally and, when possible, tells the server to drop this device’s FCM token (same as Flutter `logout` + `FirebaseMessaging.getToken`).
    func logout() async {
        let refresh = refreshToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let fcmFromDevice = UserDefaults.standard.string(forKey: kDeviceTokenKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fcmLastUploaded = UserDefaults.standard.string(forKey: kLastFcmTokenSentToBackendKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fcmForServer = [fcmFromDevice, fcmLastUploaded].compactMap { $0 }.first { !$0.isEmpty }

        if !refresh.isEmpty, authToken != nil {
            let mutation = """
            mutation Logout($refreshToken: String!, $fcmToken: String) {
              logout(refreshToken: $refreshToken, fcmToken: $fcmToken) {
                message
              }
            }
            """
            struct LogoutPayload: Decodable {
                let logout: LogoutMessage?
            }
            struct LogoutMessage: Decodable {
                let message: String?
            }
            var variables: [String: Any] = ["refreshToken": refresh]
            if let t = fcmForServer, !t.isEmpty {
                variables["fcmToken"] = t
            }
            var didLogoutOnServer = false
            for attempt in 1...3 {
                do {
                    _ = try await client.execute(
                        query: mutation,
                        variables: variables,
                        responseType: LogoutPayload.self
                    )
                    didLogoutOnServer = true
                    authSessionLogger.info("Server logout succeeded — FCM token removed from account when provided.")
                    break
                } catch {
                    if attempt == 3 {
                        authSessionLogger.warning("Server logout failed after retries (session still cleared locally): \(error.localizedDescription, privacy: .public)")
                    } else {
                        try? await Task.sleep(nanoseconds: 500_000_000)
                    }
                }
            }
            if !didLogoutOnServer {
                NotificationDebugLog.append(
                    source: "auth",
                    message: "Logout could not unregister FCM token on server after retries",
                    isError: true
                )
            }
        }

        clearTokens()
        UserDefaults.standard.removeObject(forKey: kDeviceTokenKey)
        UserDefaults.standard.removeObject(forKey: PushRegistrationDebug.uploadSummaryKey)
        UserDefaults.standard.removeObject(forKey: PushRegistrationDebug.uploadDetailKey)
        UserDefaults.standard.removeObject(forKey: PushRegistrationDebug.uploadTimestampKey)
        clearLocalNotificationState()

        await revokeLocalFCMRegistration()
        objectWillChange.send()
    }

    /// Invalidates the FCM instance token so this install stops receiving pushes targeted at the old registration.
    private func revokeLocalFCMRegistration() async {
        guard FirebaseApp.app() != nil else { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            Messaging.messaging().deleteToken { _ in
                cont.resume()
            }
        }
    }

    /// Continue as guest: clear tokens and set flag so feed uses public (no-auth) API. Matches Flutter isGuestModeProvider + clearTokenForGuest.
    func continueAsGuest() {
        UserDefaults.standard.removeObject(forKey: "AUTH_TOKEN")
        UserDefaults.standard.removeObject(forKey: "REFRESH_TOKEN")
        UserDefaults.standard.removeObject(forKey: "USERNAME")
        UserDefaults.standard.set(true, forKey: Self.kGuestMode)
        authToken = nil
        refreshToken = nil
        username = nil
        isGuestMode = true
        client.setAuthToken(nil)
        UserDefaults.standard.removeObject(forKey: kDeviceTokenKey)
        UserDefaults.standard.removeObject(forKey: kLastFcmTokenSentToBackendKey)
        clearLocalNotificationState()
        Task { await revokeLocalFCMRegistration() }
        objectWillChange.send()
    }

    /// Leave guest mode and return to login screen (no token).
    func clearGuestMode() {
        UserDefaults.standard.set(false, forKey: Self.kGuestMode)
        isGuestMode = false
        objectWillChange.send()
    }

    /// Request password reset: sends OTP/code to email (matches Flutter resetPassword(email)).
    func requestPasswordReset(email: String) async throws {
        let query = """
        mutation ResetPassword($email: String) {
          resetPassword(email: $email) {
            message
          }
        }
        """
        struct Payload: Decodable {
            let resetPassword: ResetPasswordResult?
        }
        struct ResetPasswordResult: Decodable {
            let message: String?
        }
        let response: Payload = try await client.execute(query: query, variables: ["email": email], responseType: Payload.self)
        if response.resetPassword == nil {
            throw AuthError.invalidResponse
        }
    }

    /// Set new password with code from email (matches Flutter passwordReset).
    func resetPasswordWithCode(email: String, code: String, newPassword: String) async throws {
        let query = """
        mutation PasswordReset($email: String!, $code: String!, $password: String!) {
          passwordReset(email: $email, code: $code, password: $password) {
            message
          }
        }
        """
        struct Payload: Decodable {
            let passwordReset: PasswordResetResult?
        }
        struct PasswordResetResult: Decodable {
            let message: String?
        }
        let variables: [String: Any] = ["email": email, "code": code, "password": newPassword]
        let response: Payload = try await client.execute(query: query, variables: variables, responseType: Payload.self)
        if response.passwordReset == nil {
            throw AuthError.invalidResponse
        }
    }

    private func clearTokens() {
        UserDefaults.standard.removeObject(forKey: kLastFcmTokenSentToBackendKey)
        UserDefaults.standard.removeObject(forKey: "AUTH_TOKEN")
        UserDefaults.standard.removeObject(forKey: "REFRESH_TOKEN")
        UserDefaults.standard.removeObject(forKey: "USERNAME")
        UserDefaults.standard.set(false, forKey: Self.kGuestMode)
        authToken = nil
        refreshToken = nil
        username = nil
        isGuestMode = false
        client.setAuthToken(nil)
    }

    private func clearLocalNotificationState() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        UIApplication.shared.applicationIconBadgeNumber = 0
    }
    
    var isAuthenticated: Bool {
        authToken != nil
    }

    /// Call after user completes onboarding (e.g. after verify-email flow). Hides onboarding and persists so we don't show again.
    func markOnboardingCompleted() {
        shouldShowOnboardingAfterLogin = false
        UserDefaults.standard.set(true, forKey: Self.kOnboardingCompleted)
    }

    /// Whether we should show onboarding (e.g. first time after verification). Respects kOnboardingCompleted.
    var hasCompletedOnboarding: Bool {
        UserDefaults.standard.bool(forKey: Self.kOnboardingCompleted)
    }
}

// Response Models
struct LoginGraphQLResponse: Decodable {
    let login: LoginResponse?
}

struct RegisterGraphQLResponse: Decodable {
    let register: RegisterResponse?
}

struct LoginResponse: Decodable {
    let token: String?
    let refreshToken: String?
    let user: UserResponse?
}

struct UserResponse: Decodable {
    let id: String?
    let username: String?
    let email: String?
}

struct RegisterResponse: Decodable {
    let success: Bool?
    let errors: [String: [String]]?
}

enum AuthError: Error, LocalizedError {
    case invalidResponse
    case registrationError(String)
    case networkError(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .registrationError(let message):
            return message
        case .networkError(let error):
            return error.localizedDescription
        }
    }
}

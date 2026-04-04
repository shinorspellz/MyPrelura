import FirebaseMessaging
import UIKit

/// Firebase `Messaging.token()` requires an APNs device token first (`Messaging.apnsToken`).
/// On launch and simulator, `token()` is often called too early → "No APNS token specified…".
/// This helper waits and retries instead of treating that as a fatal error.
enum PreluraFCMRegistration {
    /// APNs can arrive several seconds after `registerForRemoteNotifications()` (especially right after the permission prompt).
    private static let retryDelay: TimeInterval = 0.45
    #if targetEnvironment(simulator)
    private static let maxAttempts = 50
    #else
    /// Physical devices / TestFlight: APNs can be slow; ~54s before we give up (was ~22s).
    private static let maxAttempts = 120
    #endif

    /// Resolves the current FCM registration token after APNs is ready (or fails after retries).
    static func fetchRegistrationToken(
        attempt: Int = 0,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        if Messaging.messaging().apnsToken == nil {
            UIApplication.shared.registerForRemoteNotifications()
            guard attempt < maxAttempts else {
                completion(.failure(Self.apnsTimeoutError))
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay) {
                fetchRegistrationToken(attempt: attempt + 1, completion: completion)
            }
            return
        }

        Messaging.messaging().token { token, error in
            if let error {
                if Self.isApnsNotReady(error), attempt < maxAttempts {
                    DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay) {
                        fetchRegistrationToken(attempt: attempt + 1, completion: completion)
                    }
                    return
                }
                completion(.failure(error))
                return
            }
            guard let token, !token.isEmpty else {
                completion(.failure(Self.emptyTokenError))
                return
            }
            completion(.success(token))
        }
    }

    private static var apnsTimeoutError: NSError {
        #if targetEnvironment(simulator)
        let hint = " Simulator often never receives an APNs token — test FCM + banners on a physical iPhone with Push capability."
        #else
        let hint =
            " On device: Apple Developer → Identifiers → com.prelura.preloved → enable Push Notifications, then regenerate the provisioning profile / reinstall the app. Also confirm notification permission and that the TestFlight build uses Release signing (production APNs)."
        #endif
        return NSError(
            domain: "PreluraFCM",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "APNs device token not received in time (~\(Int(Double(maxAttempts) * retryDelay))s).\(hint)"]
        )
    }

    private static var emptyTokenError: NSError {
        NSError(domain: "PreluraFCM", code: 2, userInfo: [NSLocalizedDescriptionKey: "FCM returned an empty token"])
    }

    private static func isApnsNotReady(_ error: Error) -> Bool {
        let s = error.localizedDescription.lowercased()
        return s.contains("apns") && s.contains("token")
    }
}

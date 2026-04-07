import OSLog
import UIKit
import UserNotifications
import FirebaseCore
import FirebaseMessaging

private let pushBootstrapLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Prelura", category: "PushBootstrap")

/// Name for the notification posted when user taps a push notification (payload in userInfo).
let kNotificationTapPayloadKey = "payload"

/// UserDefaults key for the current APNs device token (hex string). Used to send token to backend when user is logged in.
let kDeviceTokenKey = "prelura_device_token"
/// Last FCM token string successfully sent via `updateProfile`; cleared on logout so the next session always registers.
let kLastFcmTokenSentToBackendKey = "prelura_last_fcm_token_sent_to_backend"

/// Menu → Push diagnostics schedules this to prove alerts work without any server (UserNotifications only).
let kPreluraLocalPushTestNotificationId = "prelura_debug_local_test"
/// `userInfo` flag on that local request so delegates can log and ignore deep-link routing.
let kPreluraLocalPushTestUserInfoKey = "prelura_local_test"

extension Notification.Name {
    static let preluraNotificationTapped = Notification.Name("PreluraNotificationTapped")
    /// Posted when a new APNs device token is received so the app can register it with the backend.
    static let preluraDeviceTokenDidUpdate = Notification.Name("PreluraDeviceTokenDidUpdate")
    /// Posted when vacation mode (or other profile flags) are updated so Profile can refresh.
    static let preluraUserProfileDidUpdate = Notification.Name("PreluraUserProfileDidUpdate")
    /// Posted when the user views a product so Discover (and Recently viewed) can refresh.
    static let preluraRecentlyViewedDidUpdate = Notification.Name("PreluraRecentlyViewedDidUpdate")
    /// Posted after admin wipes orders/payments so Dashboard can refetch `userEarnings`.
    static let preluraSellerEarningsShouldRefresh = Notification.Name("PreluraSellerEarningsShouldRefresh")
    /// In-app notification list changed (read/delete) so the home bell badge can refresh.
    static let preluraInAppNotificationsDidChange = Notification.Name("PreluraInAppNotificationsDidChange")
}

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {

    /// `FirebaseApp.configure()` aborts if the default plist is missing or invalid. Only true after a successful configure.
    private static var isFirebaseConfigured: Bool { FirebaseApp.app() != nil }

    private static func isPreluraLocalPushTest(userInfo: [AnyHashable: Any], requestIdentifier: String) -> Bool {
        if requestIdentifier == kPreluraLocalPushTestNotificationId { return true }
        let v = userInfo[kPreluraLocalPushTestUserInfoKey]
        if let i = v as? Int, i == 1 { return true }
        if let n = v as? NSNumber, n.intValue == 1 { return true }
        return false
    }

    /// When FCM payload looks like a chat/DM notification, append a `chat_push` line for Debug → Message push trace.
    private static func logChatPushPayloadIfRelevant(_ userInfo: [AnyHashable: Any], context: String) {
        let isLocalFlag = userInfo[kPreluraLocalPushTestUserInfoKey]
        if let i = isLocalFlag as? Int, i == 1 { return }
        if let n = isLocalFlag as? NSNumber, n.intValue == 1 { return }

        var parts: [String] = []
        if let data = userInfo["data"] as? [String: Any] {
            for (k, v) in data {
                let kl = k.lowercased()
                guard kl.contains("conversation") || kl.contains("chat") || kl == "model_group" else { continue }
                let vs = String(describing: v)
                parts.append("data.\(k)=\(vs.count > 72 ? String(vs.prefix(72)) + "…" : vs)")
            }
        }
        for pair in userInfo {
            let k = String(describing: pair.key).lowercased()
            guard k != "aps", k != "data" else { continue }
            if k.contains("conversation") || k.contains("chat") || k == "model_group" {
                let vs = String(describing: pair.value)
                parts.append("\(k)=\(vs.count > 72 ? String(vs.prefix(72)) + "…" : vs)")
            }
        }
        let keysLower = userInfo.keys.map { String(describing: $0).lowercased() }.joined(separator: ",")
        var modelGroupChat = false
        for (key, val) in userInfo where String(describing: key).lowercased() == "model_group" {
            modelGroupChat = String(describing: val).lowercased().contains("chat")
            break
        }
        let looksChat = !parts.isEmpty || keysLower.contains("conversation") || modelGroupChat
        guard looksChat else { return }
        let summary = parts.isEmpty
            ? "payload keys: \(String(keysLower.prefix(200)))"
            : parts.joined(separator: " ")
        NotificationDebugLog.append(
            source: "chat_push",
            message: "\(context): \(String(summary.prefix(320)))",
            isError: false
        )
    }
    /// Payload to route after splash: cold-open from push (`launchOptions`) or tap received while splash is visible (root `onReceive` cannot present yet).
    static var pendingPostSplashNotificationUserInfo: [AnyHashable: Any]?

    static func takePendingPostSplashNotificationUserInfo() -> [AnyHashable: Any]? {
        defer { pendingPostSplashNotificationUserInfo = nil }
        return pendingPostSplashNotificationUserInfo
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        configureFirebaseIfPossible()
        if Self.isFirebaseConfigured {
            Messaging.messaging().delegate = self
        }
        UNUserNotificationCenter.current().delegate = self
        if let remote = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
            Self.pendingPostSplashNotificationUserInfo = remote
            let mid = remote["gcm.message_id"].map { String(describing: $0) } ?? "none"
            NotificationDebugLog.append(
                source: "launch",
                message: "Cold start with remote-notification payload (gcm.message_id=\(mid))",
                isError: false
            )
            Self.logChatPushPayloadIfRelevant(remote, context: "Cold start remote")
        }
        requestNotificationPermissionAndRegister(application: application)
        return true
    }

    /// Loads `GoogleService-Info.plist` when present and not a template. Calling `FirebaseApp.configure()` with no plist aborts the process.
    private func configureFirebaseIfPossible() {
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              FileManager.default.fileExists(atPath: path) else {
            pushBootstrapLog.error("GoogleService-Info.plist missing from app bundle — Firebase push disabled. Add from Firebase Console (docs/FIREBASE_IOS_SETUP.md).")
            NotificationDebugLog.append(source: "firebase", message: "GoogleService-Info.plist missing from app bundle", isError: true)
            #if DEBUG
            print("[Push] No GoogleService-Info.plist in bundle — add Prelura-swift/GoogleService-Info.plist for FCM.")
            #endif
            return
        }
        guard let plist = NSDictionary(contentsOfFile: path) as? [String: Any] else {
            pushBootstrapLog.error("GoogleService-Info.plist could not be read — Firebase push disabled.")
            NotificationDebugLog.append(source: "firebase", message: "GoogleService-Info.plist could not be read", isError: true)
            return
        }
        let apiKey = (plist["API_KEY"] as? String) ?? ""
        let googleAppId = (plist["GOOGLE_APP_ID"] as? String) ?? ""
        if apiKey.contains("REPLACE_ME") || googleAppId.contains("REPLACE_ME") {
            pushBootstrapLog.warning("GoogleService-Info.plist still has REPLACE_ME placeholders — Firebase not configured.")
            NotificationDebugLog.append(source: "firebase", message: "GoogleService-Info.plist still has REPLACE_ME placeholders", isError: true)
            #if DEBUG
            print("[Push] Replace placeholders in GoogleService-Info.plist with values from Firebase Console.")
            #endif
            return
        }
        guard let options = FirebaseOptions(contentsOfFile: path) else {
            pushBootstrapLog.error("FirebaseOptions could not load GoogleService-Info.plist — Firebase push disabled.")
            NotificationDebugLog.append(source: "firebase", message: "FirebaseOptions could not load plist path", isError: true)
            return
        }
        // Use plist BUNDLE_ID as shipped from Firebase; avoid overriding (can confuse FCM ↔ APNs linkage).
        FirebaseApp.configure(options: options)
        if let projectId = plist["PROJECT_ID"] as? String {
            pushBootstrapLog.info("Firebase PROJECT_ID=\(projectId, privacy: .public) — must match server GOOGLE_CRED_PROJECT_ID.")
            #if DEBUG
            print("[Push] Firebase PROJECT_ID=\(projectId)")
            #endif
            NotificationDebugLog.append(
                source: "firebase",
                message: "Firebase configured (PROJECT_ID=\(projectId), BUNDLE_ID=\(plist["BUNDLE_ID"] as? String ?? "?"))",
                isError: false
            )
        }
        // TestFlight needs this too — wrong plist (e.g. Flutter’s GOOGLE_APP_ID) breaks APNs-linked FCM.
        diagnoseFirebasePlistVersusRuntime(plist: plist)
    }

    /// Helps explain “Flutter push works, Swift doesn’t”: each `GOOGLE_APP_ID` belongs to one iOS app registration in Firebase (one bundle). Overriding `options.bundleID` does not change that.
    private func diagnoseFirebasePlistVersusRuntime(plist: [String: Any]) {
        let plistBundle = (plist["BUNDLE_ID"] as? String) ?? ""
        let runtimeBundle = Bundle.main.bundleIdentifier ?? ""
        let googleAppId = (plist["GOOGLE_APP_ID"] as? String) ?? ""
        if !plistBundle.isEmpty, !runtimeBundle.isEmpty, plistBundle != runtimeBundle {
            pushBootstrapLog.warning("GoogleService BUNDLE_ID (\(plistBundle, privacy: .public)) ≠ executable (\(runtimeBundle, privacy: .public)) — replace plist from Firebase for this target.")
            print("[Push] WARNING: plist BUNDLE_ID (\(plistBundle)) ≠ app bundle (\(runtimeBundle)).")
            NotificationDebugLog.append(
                source: "firebase",
                message: "WARNING: plist BUNDLE_ID (\(plistBundle)) ≠ runtime (\(runtimeBundle))",
                isError: false
            )
        }
        // Prelura Flutter iOS app (com.prelura.app) uses this id in-repo; Swift must use a plist from a *separate* Firebase iOS app for com.prelura.preloved (different GOOGLE_APP_ID).
        let flutterIOSGoogleAppId = "1:756569142928:ios:f4f7f4a1af7989832d4a15"
        if runtimeBundle == "com.prelura.preloved", googleAppId == flutterIOSGoogleAppId {
            pushBootstrapLog.warning("This GOOGLE_APP_ID is the Flutter iOS client. FCM may issue a token, but APNs delivery for com.prelura.preloved often fails. Add an iOS app in Firebase for com.prelura.preloved and replace GoogleService-Info.plist (new GOOGLE_APP_ID).")
            print("[Push] WARNING: plist still uses Flutter’s GOOGLE_APP_ID. Download a new plist from Firebase → iOS app com.prelura.preloved (not com.prelura.app).")
            NotificationDebugLog.append(
                source: "firebase",
                message: "WARNING: GOOGLE_APP_ID matches Flutter app — use Firebase iOS app for com.prelura.preloved",
                isError: false
            )
        }
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let ok: Bool
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral: ok = true
            default: ok = false
            }
            guard ok else { return }
            DispatchQueue.main.async {
                application.registerForRemoteNotifications()
                guard Self.isFirebaseConfigured else { return }
                // Wait for APNs before token(); avoids "No APNS token specified" on cold start / simulator.
                PreluraFCMRegistration.fetchRegistrationToken { result in
                    guard case .success(let token) = result, !token.isEmpty else {
                        if case .failure(let error) = result {
                            pushBootstrapLog.error("FCM foreground refresh error: \(error.localizedDescription, privacy: .public)")
                            NotificationDebugLog.append(
                                source: "fcm",
                                message: "Foreground FCM token (after APNs wait): \(error.localizedDescription)",
                                isError: true
                            )
                        }
                        return
                    }
                    let prev = UserDefaults.standard.string(forKey: kDeviceTokenKey)
                    if prev != token {
                        UserDefaults.standard.set(token, forKey: kDeviceTokenKey)
                        NotificationCenter.default.post(name: .preluraDeviceTokenDidUpdate, object: nil)
                    }
                }
            }
        }
    }

    /// Registers for APNs when already allowed; only prompts when status is `notDetermined`.
    private func requestNotificationPermissionAndRegister(application: UIApplication) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                switch settings.authorizationStatus {
                case .authorized, .provisional, .ephemeral:
                    application.registerForRemoteNotifications()
                case .notDetermined:
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
                        DispatchQueue.main.async {
                            if granted {
                                application.registerForRemoteNotifications()
                                // Without an explicit token fetch here, FCM can lag until the next foreground cycle.
                                guard Self.isFirebaseConfigured else { return }
                                PreluraFCMRegistration.fetchRegistrationToken { result in
                                    guard case .success(let token) = result, !token.isEmpty else {
                                        if case .failure(let error) = result {
                                            pushBootstrapLog.error("FCM token after permission: \(error.localizedDescription, privacy: .public)")
                                            NotificationDebugLog.append(
                                                source: "fcm",
                                                message: "FCM token after permission (APNs wait): \(error.localizedDescription)",
                                                isError: true
                                            )
                                        }
                                        return
                                    }
                                    UserDefaults.standard.set(token, forKey: kDeviceTokenKey)
                                    NotificationCenter.default.post(name: .preluraDeviceTokenDidUpdate, object: nil)
                                }
                            } else {
                                pushBootstrapLog.warning("User declined notification permission — enable in Settings → Prelura → Notifications.")
                                NotificationDebugLog.append(
                                    source: "permission",
                                    message: "User declined notification permission in system prompt",
                                    isError: true
                                )
                            }
                        }
                    }
                case .denied:
                    pushBootstrapLog.warning("Notifications denied for Prelura — enable in Settings → Notifications.")
                    NotificationDebugLog.append(
                        source: "permission",
                        message: "Notifications authorization denied (Settings → Prelura → Notifications)",
                        isError: true
                    )
                @unknown default:
                    break
                }
            }
        }
    }

    /// Store device token and notify so the app can send it to the backend when the user is logged in.
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        if Self.isFirebaseConfigured {
            Messaging.messaging().apnsToken = deviceToken
        } else {
            NotificationDebugLog.append(
                source: "apns",
                message: "APNs device token received (\(deviceToken.count) bytes) but Firebase is not configured — not passed to FCM (fix GoogleService-Info.plist)",
                isError: true
            )
            return
        }
        NotificationDebugLog.append(
            source: "apns",
            message: "APNs device token received (\(deviceToken.count) bytes); fetching FCM token…",
            isError: false
        )
        // Explicit fetch: delegate can lag; ensures UserDefaults + backend sync see a token.
        PreluraFCMRegistration.fetchRegistrationToken { result in
            switch result {
            case .success(let token):
                UserDefaults.standard.set(token, forKey: kDeviceTokenKey)
                NotificationCenter.default.post(name: .preluraDeviceTokenDidUpdate, object: nil)
            case .failure(let error):
                pushBootstrapLog.error("FCM token after APNs registration: \(error.localizedDescription, privacy: .public)")
                NotificationDebugLog.append(
                    source: "fcm",
                    message: "FCM token after APNs registration: \(error.localizedDescription)",
                    isError: true
                )
                #if DEBUG
                print("[Push] FCM token error after APNs: \(error.localizedDescription)")
                #endif
            }
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        pushBootstrapLog.error("APNs registration failed: \(error.localizedDescription, privacy: .public)")
        NotificationDebugLog.append(
            source: "apns",
            message: "didFailToRegisterForRemoteNotifications: \(error.localizedDescription)",
            isError: true
        )
        print("[Push] APNs registration failed: \(error.localizedDescription)")
    }

    /// Background / data updates; required to call `completionHandler` within ~30s. Helps FCM + iOS delivery bookkeeping.
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        if Self.isFirebaseConfigured {
            _ = Messaging.messaging().appDidReceiveMessage(userInfo)
        }
        let mid = userInfo["gcm.message_id"].map { String(describing: $0) } ?? "?"
        NotificationDebugLog.append(
            source: "remote",
            message: "didReceiveRemoteNotification (background) gcm.message_id=\(mid)",
            isError: false
        )
        Self.logChatPushPayloadIfRelevant(userInfo, context: "Background remote")
        completionHandler(.newData)
    }

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken, !fcmToken.isEmpty else { return }
        UserDefaults.standard.set(fcmToken, forKey: kDeviceTokenKey)
        NotificationCenter.default.post(name: .preluraDeviceTokenDidUpdate, object: nil)
        NotificationDebugLog.append(
            source: "fcm",
            message: "FCM registration token refreshed (\(fcmToken.count) chars)",
            isError: false
        )
        pushBootstrapLog.info("FCM token length=\(fcmToken.count, privacy: .public) — stored; upload runs when logged in.")
        // Log prefix in Release too so Console.app / TestFlight feedback helps without DEBUG.
        let prefix = fcmToken.prefix(16)
        print("[Push] FCM token received (\(fcmToken.count) chars), prefix: \(prefix)…")
        #if DEBUG
        print("[FCM TEST] Copy full token into Firebase → Send test message:\n\(fcmToken)")
        #endif
    }

    /// Called when user taps a notification (foreground or background). Post so SwiftUI can route.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if Self.isPreluraLocalPushTest(userInfo: userInfo, requestIdentifier: response.notification.request.identifier) {
            NotificationDebugLog.append(
                source: "local",
                message: "Tapped local on-device test notification (no server)",
                isError: false
            )
            completionHandler()
            return
        }
        let mid = userInfo["gcm.message_id"].map { String(describing: $0) } ?? "?"
        NotificationDebugLog.append(
            source: "tap",
            message: "User tapped notification (gcm.message_id=\(mid))",
            isError: false
        )
        Self.logChatPushPayloadIfRelevant(userInfo, context: "Tapped notification")
        NotificationCenter.default.post(
            name: .preluraNotificationTapped,
            object: nil,
            userInfo: [kNotificationTapPayloadKey: userInfo]
        )
        completionHandler()
    }

    /// Show banner + sound when a notification arrives while the app is open (otherwise iOS stays silent).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let u = notification.request.content.userInfo
        let isLocalDebug = Self.isPreluraLocalPushTest(userInfo: u, requestIdentifier: notification.request.identifier)
        if isLocalDebug {
            NotificationDebugLog.append(
                source: "local",
                message: "willPresent — local test banner (app was foreground; for lock-screen test, background the app before it fires)",
                isError: false
            )
            completionHandler([.banner, .badge, .sound])
            return
        }
        if let mid = u["gcm.message_id"] {
            pushBootstrapLog.info("willPresent remote notification gcm.message_id=\(String(describing: mid), privacy: .public)")
            print("[Push] Foreground notification (gcm.message_id=\(mid))")
        }
        let midStr = u["gcm.message_id"].map { String(describing: $0) } ?? "?"
        NotificationDebugLog.append(
            source: "present",
            message: "willPresent — remote FCM banner/sound (foreground) gcm.message_id=\(midStr)",
            isError: false
        )
        Self.logChatPushPayloadIfRelevant(u, context: "Foreground willPresent")
        completionHandler([.banner, .badge, .sound])
    }
}

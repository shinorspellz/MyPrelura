import Combine
import Foundation

/// Drives the home notification bell red dot. Overlapping refreshes use a monotonic serial so only
/// the latest completion updates UI (no Task cancellation, which was clearing valid unread state).
final class BellUnreadStore: ObservableObject {
    @Published private(set) var hasUnread: Bool = false

    private var requestSerial: UInt64 = 0
    private let notificationService = NotificationService()

    func scheduleRefresh(authService: AuthService) {
        Task { @MainActor in
            guard authService.isAuthenticated, !authService.isGuestMode else {
                hasUnread = false
                return
            }
            requestSerial += 1
            let serial = requestSerial
            notificationService.updateAuthToken(authService.authToken)
            do {
                let n = try await notificationService.countUnreadBellEligibleNotifications()
                guard serial == requestSerial else { return }
                hasUnread = n > 0
            } catch {
                guard serial == requestSerial else { return }
                hasUnread = false
            }
        }
    }
}

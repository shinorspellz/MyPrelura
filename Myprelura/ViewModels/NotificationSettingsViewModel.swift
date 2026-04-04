import Foundation
import Combine

@MainActor
class NotificationSettingsViewModel: ObservableObject {
    @Published var preference: NotificationPreference?
    @Published var isLoading = true
    @Published var errorMessage: String?
    @Published var isUpdating = false

    let channel: NotificationSettingsChannel
    private let service = NotificationService()

    var isEmailMode: Bool { channel.isEmailMode }
    var mainToggleOn: Bool {
        get {
            guard let p = preference else { return true }
            return isEmailMode ? p.isEmailNotification : p.isPushNotification
        }
        set {
            guard var p = preference else { return }
            if isEmailMode { p.isEmailNotification = newValue } else { p.isPushNotification = newValue }
            preference = p
        }
    }

    var subPreferences: NotificationSubPreferences {
        get {
            guard let p = preference else {
                return NotificationSubPreferences(likes: true, messages: true, newFollowers: true, profileView: true)
            }
            return isEmailMode ? p.emailNotifications : p.inappNotifications
        }
        set {
            guard var p = preference else { return }
            if isEmailMode { p.emailNotifications = newValue } else { p.inappNotifications = newValue }
            preference = p
        }
    }

    var subTogglesDisabled: Bool { !mainToggleOn }

    init(channel: NotificationSettingsChannel) {
        self.channel = channel
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            preference = try await service.getNotificationPreference()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setMainToggle(_ value: Bool) {
        mainToggleOn = value
        Task { await updateMain(value) }
    }

    func setSub(keyPath: WritableKeyPath<NotificationSubPreferences, Bool>, value: Bool) {
        var sub = subPreferences
        sub[keyPath: keyPath] = value
        subPreferences = sub
        Task { await updateSub() }
    }

    private func updateMain(_ value: Bool) async {
        isUpdating = true
        errorMessage = nil
        defer { isUpdating = false }
        do {
            if isEmailMode {
                try await service.updateNotificationPreference(isEmailNotification: value)
            } else {
                try await service.updateNotificationPreference(isPushNotification: value)
                // Backend may expect a fresh FCM registration after push prefs change (parity with typical client flows).
                NotificationCenter.default.post(name: .preluraDeviceTokenDidUpdate, object: nil)
            }
        } catch {
            errorMessage = error.localizedDescription
            await load()
        }
    }

    private func updateSub() async {
        isUpdating = true
        errorMessage = nil
        defer { isUpdating = false }
        do {
            if isEmailMode {
                try await service.updateNotificationPreference(emailNotifications: subPreferences)
            } else {
                try await service.updateNotificationPreference(inappNotifications: subPreferences)
                NotificationCenter.default.post(name: .preluraDeviceTokenDidUpdate, object: nil)
            }
        } catch {
            errorMessage = error.localizedDescription
            await load()
        }
    }
}

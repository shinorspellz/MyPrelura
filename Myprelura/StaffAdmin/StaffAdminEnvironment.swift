import SwiftUI

/// Set from `UserDetailView` so shared `UserProfileView` can call staff-only APIs when non-nil.
private struct StaffAdminSessionKey: EnvironmentKey {
    static var defaultValue: AdminSession? = nil
}

extension EnvironmentValues {
    var staffAdminSession: AdminSession? {
        get { self[StaffAdminSessionKey.self] }
        set { self[StaffAdminSessionKey.self] = newValue }
    }
}

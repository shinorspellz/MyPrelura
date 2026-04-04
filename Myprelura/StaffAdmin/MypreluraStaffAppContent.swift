import SwiftUI

/// Bundle ID gate: `com.myprelura.preloved` runs the staff shell (`AdminRootShellView`) on top of the cloned Prelura codebase.
enum MypreluraStaffBuild {
    static var isStaffProduct: Bool {
        Bundle.main.bundleIdentifier == "com.myprelura.preloved"
    }
}

/// Holds `AdminSession` and hosts staff chrome (tabs, login, admin settings). Consumer `AuthService` is supplied by `Prelura_swiftApp`.
struct MypreluraStaffAppContent: View {
    @State private var session = AdminSession()

    var body: some View {
        AdminRootShellView()
            .environment(session)
    }
}

import SwiftUI

/// Circular X close button matching the Payment screen: dark grey circle, white xmark. Use in toolbars for dismissing modals.
struct CircleCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(Theme.Colors.primaryText)
                .frame(width: Theme.AppBar.buttonSize, height: Theme.AppBar.buttonSize)
                .background(Theme.Colors.secondaryBackground)
                .clipShape(Circle())
        }
        .buttonStyle(HapticTapButtonStyle())
    }
}

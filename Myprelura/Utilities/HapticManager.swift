import SwiftUI
import UIKit

/// Matches `PreluraSwift` haptic usage for primary actions and taps.
enum HapticManager {
    private static var hapticsEnabled: Bool {
        UserDefaults.standard.object(forKey: "myprelura.settings.haptics") as? Bool ?? true
    }

    static func primaryAction() {
        guard hapticsEnabled else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.8)
    }

    static func tap() {
        guard hapticsEnabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.5)
    }

    static func selection() {
        guard hapticsEnabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

struct PlainTappableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
    }
}

struct HapticTapButtonStyle: ButtonStyle {
    var haptic: () -> Void = { HapticManager.tap() }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed { haptic() }
            }
    }
}

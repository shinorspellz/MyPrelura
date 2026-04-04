import SwiftUI
import UIKit

/// Central haptic feedback for the app. Use different styles so every tap feels special.
enum HapticManager {
    /// Tab bar / navigation taps — light, subtle
    static func tabTap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.7)
    }

    /// Primary CTA buttons (Buy, Save, Submit) — medium, satisfying
    static func primaryAction() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.8)
    }

    /// Secondary / outline buttons — light
    static func secondaryAction() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.6)
    }

    /// Selection (pills, toggles, list rows) — selection style
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// Toggle / switch — light impact
    static func toggle() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.5)
    }

    /// Like / favourite — light, pleasant
    static func like() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.6)
    }

    /// Success (e.g. saved, uploaded) — notification success
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Error / destructive — notification warning
    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    /// Refresh triggered — light
    static func refresh() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.5)
    }

    /// Generic tap (menu items, links) — light
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.5)
    }

    /// Destructive action (logout, delete) — warning
    static func destructive() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}

// MARK: - Button styles with haptics

/// Same as `.plain` but the entire label frame is tappable, not only text/icon glyphs.
struct PlainTappableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
    }
}

/// ButtonStyle that fires haptic on press. Use for icon buttons, menu items, etc.
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

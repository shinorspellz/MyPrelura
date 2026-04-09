import SwiftUI
import UIKit

/// Thin horizontal separator between content sections (e.g. Sell form, profile, item detail).
/// Use as a standalone view or in `.overlay(ContentDivider(), alignment: .bottom)` / `.top`.
/// Do not use for menu card row dividers (those stay as `menuDivider` in ProfileMenuView).
///
/// **Thickness:** Uses **one physical pixel** (`1 / screen scale` in points), not a fixed 0.5pt.
/// A literal 0.5pt line on @3x is 1.5 device pixels—SwiftUI often anti-aliases across two rows, so identical code
/// can look thinner or thicker depending on vertical alignment; matching the pixel grid keeps dividers consistent.
struct ContentDivider: View {
    private var hairlineHeight: CGFloat {
        1.0 / max(UIScreen.main.scale, 1)
    }

    var body: some View {
        Rectangle()
            .fill(Theme.Colors.glassBorder)
            .frame(height: hairlineHeight)
    }
}

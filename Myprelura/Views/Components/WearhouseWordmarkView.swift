import SwiftUI

/// Text wordmark aligned with the consumer WEARHOUSE app.
struct WearhouseWordmarkView: View {
    enum Style {
        case toolbar
        case splash
    }

    var style: Style = .toolbar

    var body: some View {
        let metrics = metrics(for: style)
        wordmark(metrics: metrics)
            .foregroundStyle(Theme.primaryColor)
    }

    private func metrics(for style: Style) -> (fontSize: CGFloat, tracking: CGFloat) {
        switch style {
        case .toolbar: return (16, 4.0)
        case .splash: return (28, 6.5)
        }
    }

    private func wordmark(metrics: (fontSize: CGFloat, tracking: CGFloat)) -> some View {
        Text("WEARHOUSE")
            .font(.system(size: metrics.fontSize, weight: .black, design: .rounded))
            .tracking(metrics.tracking)
            .minimumScaleFactor(0.72)
            .lineLimit(1)
    }
}

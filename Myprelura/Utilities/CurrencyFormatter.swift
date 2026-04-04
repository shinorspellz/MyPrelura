import Foundation

enum CurrencyFormatter {
    /// Format GBP values for UI:
    /// - `70` -> `£70`
    /// - `14.5` -> `£14.50`
    /// - `17.45` -> `£17.45`
    static func gbp(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        let sign = rounded < 0 ? "-" : ""
        let absValue = abs(rounded)
        if absValue == floor(absValue) {
            return "\(sign)£\(Int(absValue))"
        }
        return "\(sign)£\(String(format: "%.2f", absValue))"
    }
}

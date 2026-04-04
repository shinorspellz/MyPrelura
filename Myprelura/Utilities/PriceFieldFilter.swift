import Foundation
import SwiftUI

/// Keeps price input to numbers only: digits and at most one decimal point (comma or dot).
enum PriceFieldFilter {
    /// Sanitizes a string so it contains only digits and at most one decimal separator (`.` or `,`).
    /// Non-numeric characters are removed; multiple decimal separators are collapsed to one.
    static func sanitizePriceInput(_ string: String) -> String {
        let allowed = CharacterSet(charactersIn: "0123456789.,")
        let filtered = string.unicodeScalars.filter { allowed.contains($0) }
        var result = String(String.UnicodeScalarView(filtered))
        result = result.replacingOccurrences(of: ",", with: ".")
        if let firstDot = result.firstIndex(of: ".") {
            let afterDot = result[result.index(after: firstDot)...].filter { $0 != "." }
            result = String(result[..<firstDot]) + "." + afterDot
        }
        return result
    }

    /// Returns a binding that sanitizes the value on set. Use for all price text fields.
    static func binding(get: @escaping () -> String, set: @escaping (String) -> Void) -> Binding<String> {
        Binding(
            get: get,
            set: { set(sanitizePriceInput($0)) }
        )
    }
}

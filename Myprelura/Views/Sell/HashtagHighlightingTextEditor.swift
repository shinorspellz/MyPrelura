import SwiftUI
import UIKit

/// Multiline editor that keeps listing `description` plain text while coloring `#hashtags` with the app primary colour.
struct HashtagHighlightingTextEditor: UIViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate = context.coordinator
        tv.font = .preferredFont(forTextStyle: .body)
        tv.adjustsFontForContentSizeCategory = true
        tv.backgroundColor = .clear
        tv.textContainerInset = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        tv.textContainer.lineFragmentPadding = 0
        tv.text = text
        tv.keyboardDismissMode = .interactive
        Coordinator.applyHighlighting(to: tv)
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        guard uiView.text != text else { return }
        let sel = uiView.selectedRange
        uiView.text = text
        Coordinator.applyHighlighting(to: uiView)
        let n = (uiView.text as NSString).length
        if sel.location <= n {
            let maxLen = max(0, n - sel.location)
            let len = min(sel.length, maxLen)
            uiView.selectedRange = NSRange(location: sel.location, length: len)
        } else {
            uiView.selectedRange = NSRange(location: n, length: 0)
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: HashtagHighlightingTextEditor

        init(_ parent: HashtagHighlightingTextEditor) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text ?? ""
            Self.applyHighlighting(to: textView)
        }

        /// Primary purple `#AB28B2` (matches `Theme.primaryColor`).
        private static let hashtagUIColor = UIColor(red: 171 / 255, green: 40 / 255, blue: 178 / 255, alpha: 1)

        static func applyHighlighting(to textView: UITextView) {
            let plain = textView.text ?? ""
            let selectedRange = textView.selectedTextRange
            let ns = plain as NSString
            let full = NSRange(location: 0, length: ns.length)
            let attr = NSMutableAttributedString(string: plain)
            let font = textView.font ?? UIFont.preferredFont(forTextStyle: .body)
            attr.addAttributes(
                [.foregroundColor: UIColor.label, .font: font],
                range: full
            )
            guard let regex = try? NSRegularExpression(pattern: HashtagTextSupport.hashtagPattern, options: []) else {
                textView.attributedText = attr
                textView.selectedTextRange = selectedRange
                return
            }
            regex.enumerateMatches(in: plain, options: [], range: full) { match, _, _ in
                guard let match = match else { return }
                attr.addAttribute(.foregroundColor, value: hashtagUIColor, range: match.range)
            }
            textView.attributedText = attr
            textView.selectedTextRange = selectedRange
        }
    }
}

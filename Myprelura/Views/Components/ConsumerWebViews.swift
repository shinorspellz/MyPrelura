import SwiftUI
import WebKit

/// Same public pages shoppers use (`prelura.uk`); embed for parity with the consumer app without duplicating native screens.
struct ConsumerWebPageView: View {
    let url: URL
    let title: String

    var body: some View {
        AdminWebViewRepresentable(url: url)
            .ignoresSafeArea(edges: .bottom)
            .background(Theme.Colors.background)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .adminNavigationChrome()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
    }
}

/// Sheet wrapper with Done (for modal presentation).
struct PublicProfileWebView: View {
    let username: String
    @Environment(\.dismiss) private var dismiss

    private var url: URL? {
        Constants.publicProfileURL(username: username)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let url {
                    AdminWebViewRepresentable(url: url)
                        .ignoresSafeArea(edges: .bottom)
                        .background(Theme.Colors.background)
                        .navigationTitle("@\(username)")
                        .navigationBarTitleDisplayMode(.inline)
                        .adminNavigationChrome()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { dismiss() }
                            }
                            ToolbarItem(placement: .primaryAction) {
                                ShareLink(item: url) {
                                    Image(systemName: "square.and.arrow.up")
                                }
                            }
                        }
                } else {
                    ContentUnavailableView("Invalid username", systemImage: "person.crop.circle.badge.xmark")
                        .background(Theme.Colors.background)
                }
            }
        }
    }
}

struct AdminWebViewRepresentable: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            // Surface in console; SwiftUI layer has no binding here yet.
            #if DEBUG
            print("AdminWebView navigation failed: \(error.localizedDescription)")
            #endif
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            #if DEBUG
            print("AdminWebView provisional failed: \(error.localizedDescription)")
            #endif
        }
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.preferredContentMode = .mobile
        let w = WKWebView(frame: .zero, configuration: config)
        w.navigationDelegate = context.coordinator
        w.customUserAgent =
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1 PreluraMyprelura/1"
        applyChrome(to: w)
        return w
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        applyChrome(to: uiView)
        let req = URLRequest(url: url)
        if uiView.url != url {
            uiView.load(req)
        }
    }

    private func applyChrome(to w: WKWebView) {
        let dark = Theme.effectiveColorScheme == .dark
        let bg: UIColor = dark
            ? UIColor(red: 12 / 255, green: 12 / 255, blue: 12 / 255, alpha: 1)
            : .systemBackground
        w.isOpaque = true
        w.backgroundColor = bg
        w.scrollView.backgroundColor = bg
        if #available(iOS 15.0, *) {
            w.underPageBackgroundColor = bg
        }
    }
}

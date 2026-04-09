import SwiftUI
import SafariServices
import WebKit

// MARK: - Safari (public mywearhouse.co.uk — same rendering as Safari; WKWebView often stays blank on the SPA)

/// Uses `SFSafariViewController` so profile and listing pages match what users see in the main app / Safari.
struct SafariViewRepresentable: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.barCollapsingEnabled = true
        let vc = SFSafariViewController(url: url, configuration: config)
        if Theme.effectiveColorScheme == .dark {
            vc.preferredBarTintColor = UIColor(red: 12 / 255, green: 12 / 255, blue: 12 / 255, alpha: 1)
        } else {
            vc.preferredBarTintColor = .systemBackground
        }
        vc.preferredControlTintColor = UIColor(red: 171 / 255, green: 40 / 255, blue: 178 / 255, alpha: 1)
        return vc
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

/// Same public pages shoppers use (`mywearhouse.co.uk`); **Safari** engine avoids empty WKWebView on the Next/React site.
struct ConsumerWebPageView: View {
    let url: URL
    let title: String

    var body: some View {
        SafariViewRepresentable(url: url)
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
                    SafariViewRepresentable(url: url)
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

// MARK: - WKWebView (listing moderation only — toolbar actions; improve load visibility)

struct AdminWebViewRepresentable: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
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
        let target = url.absoluteString
        let current = uiView.url?.absoluteString
        guard current != target else { return }
        uiView.load(URLRequest(url: url))
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

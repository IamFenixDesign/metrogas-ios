import SwiftUI
import WebKit

/// WebView mínimo que abre solo el login de Google (OAuth de MetroGAS/SAP).
struct GoogleAuthView: UIViewRepresentable {
    let url: URL
    var onNavigate: ((URL) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onNavigate: onNavigate)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        context.coordinator.loadIfNeeded(webView, url: url)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onNavigate = onNavigate
        context.coordinator.loadIfNeeded(webView, url: url)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var onNavigate: ((URL) -> Void)?
        private var lastLoaded: URL?

        init(onNavigate: ((URL) -> Void)?) {
            self.onNavigate = onNavigate
        }

        func loadIfNeeded(_ webView: WKWebView, url: URL) {
            if lastLoaded == url { return }
            lastLoaded = url
            webView.load(URLRequest(url: url))
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if let url = webView.url {
                onNavigate?(url)
            }
        }

        @MainActor
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            if let url = navigationAction.request.url {
                onNavigate?(url)
            }
            decisionHandler(.allow)
        }
    }
}

struct GoogleAuthSheet: View {
    @EnvironmentObject private var session: AppSession
    let startURL: URL

    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            ZStack {
                GoogleAuthView(url: startURL) { destination in
                    session.handleGoogleAuthNavigation(destination)
                    let host = destination.host?.lowercased() ?? ""
                    if MetrogasURLs.isAuthenticatedSessionHost(host)
                        || host.contains("accounts.google.com") {
                        isLoading = false
                    }
                }

                if session.isConfirmingGoogleSession {
                    ProgressView("Confirmando sesión MetroGAS…")
                        .padding(16)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else if isLoading {
                    ProgressView("Abriendo Google…")
                        .padding(16)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .navigationTitle(session.canContinueWithGoogle ? "Continuar" : "Continuar con Google")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        session.cancelGoogleLogin()
                    }
                }
            }
        }
    }
}

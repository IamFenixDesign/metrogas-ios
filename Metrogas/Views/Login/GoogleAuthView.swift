import SwiftUI
import WebKit

/// WebView del mismo login que la Oficina Virtual web:
/// portal → authn MDS → `asskova9q.../saml2/idp/sso/...` (Acceso Mi Cuenta / Google).
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
    @State private var currentHost = ""

    private var statusText: String {
        if session.isConfirmingWebSession {
            return "Confirmando sesión MetroGAS…"
        }
        if currentHost.contains("accounts.google.com") {
            return "Continuando con Google…"
        }
        if MetrogasURLs.isIdentityLoginHost(currentHost) {
            return "Acceso Mi Cuenta…"
        }
        return "Abriendo inicio de sesión…"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GoogleAuthView(url: startURL) { destination in
                    session.handleWebLoginNavigation(destination)
                    let host = destination.host?.lowercased() ?? ""
                    currentHost = host
                    if MetrogasURLs.isAuthenticatedSessionHost(host)
                        || MetrogasURLs.isIdentityLoginHost(host)
                        || host.contains("accounts.google.com") {
                        isLoading = false
                    }
                }

                if session.isConfirmingWebSession || isLoading {
                    ProgressView(statusText)
                        .padding(16)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .navigationTitle("Acceso Mi Cuenta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        session.cancelWebLogin()
                    }
                }
            }
        }
    }
}

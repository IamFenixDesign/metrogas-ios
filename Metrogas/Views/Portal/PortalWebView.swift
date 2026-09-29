import SwiftUI
import WebKit

struct PortalWebView: UIViewRepresentable {
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
        webView.backgroundColor = .systemBackground
        webView.isOpaque = false
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

/// Contenedor nativo alrededor del portal oficial de MetroGAS.
struct MetrogasPortalScreen: View {
    @EnvironmentObject private var session: AppSession
    let title: String
    var url: URL = MetrogasURLs.portalMobile
    var showsConfirmLogin: Bool = false

    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            PortalWebView(url: url) { destination in
                session.handlePortalNavigation(destination)
                isLoading = false
            }
            .background(MetrogasTheme.brandSky.opacity(0.35))
        }
        .overlay(alignment: .top) {
            if isLoading {
                ProgressView()
                    .padding(10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 8)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Asegura cookies de la sesión nativa en el WKWebView.
            let cookies = await MetrogasAuthService.shared.exportCookiesForWebKit()
            await WebCookieBridge.syncHTTPCookiesToWebKit(cookies)
        }
    }
}

import SwiftUI
import WebKit

/// WKWebView embebido para flujos MetroGAS (pago, guías) sin salir a Safari.
struct InAppBrowserView: UIViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool
    @Binding var pageTitle: String
    var canGoBack: Binding<Bool>? = nil
    var goBackToken: Binding<Int>? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.allowsInlineMediaPlayback = true

        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        context.coordinator.webView = webView
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        if let token = goBackToken?.wrappedValue,
           token != context.coordinator.lastGoBackToken {
            context.coordinator.lastGoBackToken = token
            if webView.canGoBack {
                webView.goBack()
            }
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: InAppBrowserView
        weak var webView: WKWebView?
        var lastGoBackToken = 0

        init(parent: InAppBrowserView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.isLoading = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
            parent.pageTitle = webView.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? "MetroGAS"
            parent.canGoBack?.wrappedValue = webView.canGoBack
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
            parent.canGoBack?.wrappedValue = webView.canGoBack
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            parent.isLoading = false
            parent.canGoBack?.wrappedValue = webView.canGoBack
        }

        @MainActor
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            guard let destination = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            let scheme = (destination.scheme ?? "").lowercased()
            if scheme == "http" || scheme == "https" || scheme == "about" || scheme == "blob" {
                decisionHandler(.allow)
                return
            }

            // Schemes de billeteras / bancos: intentar abrir la app instalada.
            if UIApplication.shared.canOpenURL(destination) {
                UIApplication.shared.open(destination)
            }
            decisionHandler(.cancel)
        }

        /// Pop-ups / target=_blank de pasarelas de pago → misma WebView.
        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }
    }
}

struct InAppBrowserSheet: View {
    let url: URL
    var title: String = "Pagar"

    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = true
    @State private var pageTitle = ""
    @State private var canGoBack = false
    @State private var goBackToken = 0

    var body: some View {
        NavigationStack {
            ZStack {
                InAppBrowserView(
                    url: url,
                    isLoading: $isLoading,
                    pageTitle: $pageTitle,
                    canGoBack: $canGoBack,
                    goBackToken: $goBackToken
                )
                .ignoresSafeArea(edges: .bottom)

                if isLoading {
                    ProgressView("Cargando…")
                        .padding(16)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .navigationTitle(pageTitle.isEmpty ? title : pageTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if canGoBack {
                        Button {
                            goBackToken += 1
                        } label: {
                            Image(systemName: "chevron.backward")
                        }
                        .accessibilityLabel("Atrás")
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
    }
}

/// Destino presentable en `.sheet(item:)` para el browser in-app.
struct InAppBrowserDestination: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    var title: String = "Pagar"
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

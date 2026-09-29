import Foundation
import UIKit
import WebKit

/// Motor de sync: carga el portal autenticado en un WKWebView oculto,
/// intercepta XHR/fetch del OvServiceHub/UI5 y parsea facturas/consumo/cuenta.
/// La UI de la app sigue siendo 100% nativa.
@MainActor
final class PortalDataBridge: NSObject {
    static let shared = PortalDataBridge()

    private var webView: WKWebView?
    private var hostView: UIView?
    private var captured: [(url: String, body: String)] = []
    private var domText = ""
    private var finishTask: Task<Void, Never>?
    private var continuation: CheckedContinuation<MetrogasDataSnapshot, Error>?
    private var loginHint: String?

    func sync(loginHint: String?, timeoutSeconds: Double = 20) async throws -> MetrogasDataSnapshot {
        if continuation != nil {
            throw MetrogasAuthError.unexpectedResponse
        }

        self.loginHint = loginHint
        captured.removeAll()
        domText = ""

        // Cookies de URLSession → WK
        let cookies = await MetrogasAuthService.shared.exportCookiesForWebKit()
        await WebCookieBridge.syncHTTPCookiesToWebKit(cookies)

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        let userContent = config.userContentController
        userContent.add(self, name: "metrogasSync")
        userContent.addUserScript(WKUserScript(source: Self.hookScript, injectionTime: .atDocumentStart, forMainFrameOnly: false))

        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: config)
        webView.navigationDelegate = self
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        webView.isOpaque = false
        webView.alpha = 0.01

        // Debe estar en jerarquía para que cargue con normalidad.
        if let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows).first {
            webView.frame = CGRect(x: -4, y: -4, width: 2, height: 2)
            window.addSubview(webView)
            hostView = window
        }

        self.webView = webView

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            // Cargar OV2 (apps reales) y también mobile.
            webView.load(URLRequest(url: MetrogasURLs.portalOV2))

            finishTask = Task { [weak self] in
                // Dar tiempo a SAML residual + tiles UI5 + XHR.
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                await self?.completeIfNeeded()
            }
        }
    }

    private func completeIfNeeded() async {
        guard let continuation else { return }
        self.continuation = nil
        finishTask?.cancel()
        finishTask = nil

        // Sync cookies de vuelta por si el portal renovó sesión.
        await WebCookieBridge.syncWebKitCookiesToHTTP()

        let snapshot = PortalPayloadParser.parse(
            payloads: captured,
            domText: domText,
            loginHint: loginHint
        )

        teardown()
        continuation.resume(returning: snapshot)
    }

    private func teardown() {
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "metrogasSync")
        webView?.navigationDelegate = nil
        webView?.stopLoading()
        webView?.removeFromSuperview()
        webView = nil
        hostView = nil
    }

    private static let hookScript = """
    (function() {
      if (window.__metrogasHooked) return;
      window.__metrogasHooked = true;
      function post(type, payload) {
        try {
          window.webkit.messageHandlers.metrogasSync.postMessage({type: type, payload: payload});
        } catch (e) {}
      }
      var XO = XMLHttpRequest.prototype.open;
      var XS = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.open = function(method, url) {
        this.__mgURL = String(url || '');
        this.__mgMethod = String(method || 'GET');
        return XO.apply(this, arguments);
      };
      XMLHttpRequest.prototype.send = function() {
        var xhr = this;
        xhr.addEventListener('loadend', function() {
          try {
            post('net', {
              url: xhr.__mgURL || '',
              method: xhr.__mgMethod || 'GET',
              status: xhr.status || 0,
              body: (xhr.responseText || '').substring(0, 600000)
            });
          } catch (e) {}
        });
        return XS.apply(this, arguments);
      };
      var ofetch = window.fetch;
      window.fetch = function(input, init) {
        var url = (typeof input === 'string') ? input : (input && input.url) ? input.url : String(input);
        return ofetch(input, init).then(function(res) {
          try {
            res.clone().text().then(function(text) {
              post('net', {
                url: String(url),
                method: (init && init.method) || 'GET',
                status: res.status,
                body: (text || '').substring(0, 600000)
              });
            });
          } catch (e) {}
          return res;
        });
      };
      function scrape() {
        try {
          var text = document.body ? (document.body.innerText || '') : '';
          post('dom', { text: text.substring(0, 250000), href: location.href });
        } catch (e) {}
      }
      setInterval(scrape, 2500);
      setTimeout(scrape, 1500);
      post('ready', { href: location.href });
    })();
    """
}

extension PortalDataBridge: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "metrogasSync",
              let dict = message.body as? [String: Any],
              let type = dict["type"] as? String else { return }

        if type == "net", let payload = dict["payload"] as? [String: Any] {
            let url = payload["url"] as? String ?? ""
            let body = payload["body"] as? String ?? ""
            let status = payload["status"] as? Int ?? 0
            guard status >= 200, status < 400, !body.isEmpty else { return }
            // Priorizar APIs / JSON.
            if url.localizedCaseInsensitiveContains("OvServiceHub")
                || url.localizedCaseInsensitiveContains("odata")
                || url.localizedCaseInsensitiveContains("factura")
                || url.localizedCaseInsensitiveContains("invoice")
                || url.localizedCaseInsensitiveContains("consumo")
                || url.localizedCaseInsensitiveContains("account")
                || body.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{")
                || body.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("[") {
                captured.append((url, body))
            }
        } else if type == "dom", let payload = dict["payload"] as? [String: Any] {
            if let text = payload["text"] as? String, text.count > domText.count {
                domText = text
            }
        } else if type == "ready" {
            // Tras el shell, intentar también el sitio mobile.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                if let webView, !(webView.url?.absoluteString.contains("ovmetrogasmobile") ?? false) {
                    webView.load(URLRequest(url: MetrogasURLs.portalMobile))
                }
            }
        }

        // Completar temprano si ya hay facturas parseables.
        let early = PortalPayloadParser.parse(payloads: captured, domText: domText, loginHint: loginHint)
        if !early.invoices.isEmpty || (!early.readings.isEmpty && early.account.customerNumber != "—") {
            Task { await completeIfNeeded() }
        }
    }
}

extension PortalDataBridge: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Re-inyectar por si el document start no corrió en algún frame.
        webView.evaluateJavaScript(Self.hookScript, completionHandler: nil)
    }
}

enum PortalPayloadParser {
    static func parse(payloads: [(url: String, body: String)], domText: String, loginHint: String?) -> MetrogasDataSnapshot {
        var account = AccountProfile.empty
        if let loginHint, !loginHint.isEmpty {
            account.email = loginHint
            let local = loginHint.split(separator: "@").first.map(String.init) ?? loginHint
            account.holderName = local.replacingOccurrences(of: ".", with: " ").capitalized
        }

        var invoices: [Invoice] = []
        var readings: [ConsumptionReading] = []

        for item in payloads {
            guard let data = item.body.data(using: .utf8) else { continue }
            let parsed = MetrogasJSONParser.parse(data)
            if invoices.isEmpty || parsed.invoices.count > invoices.count {
                invoices = mergeInvoices(invoices, parsed.invoices)
            }
            if readings.isEmpty || parsed.readings.count > readings.count {
                readings = mergeReadings(readings, parsed.readings)
            }
            account = MetrogasJSONParser.mergeAccount(account, parsed.account)
        }

        if invoices.isEmpty || readings.isEmpty {
            let fromDOM = MetrogasJSONParser.parseDOMText(domText)
            if invoices.isEmpty { invoices = fromDOM.invoices }
            if readings.isEmpty { readings = fromDOM.readings }
            account = MetrogasJSONParser.mergeAccount(account, fromDOM.account)
        }

        if readings.isEmpty && !invoices.isEmpty {
            readings = MetrogasJSONParser.deriveReadings(from: invoices)
        }

        return MetrogasDataSnapshot(account: account, invoices: invoices, readings: readings)
    }

    private static func mergeInvoices(_ a: [Invoice], _ b: [Invoice]) -> [Invoice] {
        var map: [String: Invoice] = [:]
        for inv in a + b { map[inv.id] = inv }
        return Array(map.values).sorted { $0.dueDate > $1.dueDate }
    }

    private static func mergeReadings(_ a: [ConsumptionReading], _ b: [ConsumptionReading]) -> [ConsumptionReading] {
        let all = a + b
        var seen = Set<String>()
        return all.filter { r in
            let key = "\(r.periodStart.timeIntervalSince1970)-\(r.cubicMeters)"
            return seen.insert(key).inserted
        }.sorted { $0.periodStart < $1.periodStart }
    }
}

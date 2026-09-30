import Foundation
import UIKit
import WebKit

/// Sync real contra saldos.micuenta (OvServiceHub M360):
/// carga la SPA pública, resuelve reCAPTCHA invisible y captura
/// publicbilling / listR2 / consumption. La UI de la app sigue nativa.
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
    private var accountId: String = ""
    private var didTriggerAPISync = false

    /// Sincroniza facturas, deuda, consumo y titular para un N° de cliente de 11 dígitos.
    func sync(accountId: String, loginHint: String?, timeoutSeconds: Double = 28) async throws -> MetrogasDataSnapshot {
        if continuation != nil {
            throw MetrogasAuthError.unexpectedResponse
        }

        guard let normalized = MetrogasURLs.normalizedCustomerNumber(accountId) else {
            throw MetrogasAuthError.unexpectedResponse
        }

        self.accountId = normalized
        self.loginHint = loginHint
        self.didTriggerAPISync = false
        captured.removeAll()
        domText = ""

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

            // Deep link real de la SPA: dispara consulta de deuda con captcha.
            webView.load(URLRequest(url: MetrogasURLs.saldosGo(accountId: normalized)))

            finishTask = Task { [weak self] in
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

        await WebCookieBridge.syncWebKitCookiesToHTTP()

        var snapshot = PortalPayloadParser.parse(
            payloads: captured,
            domText: domText,
            loginHint: loginHint
        )
        if MetrogasURLs.normalizedCustomerNumber(snapshot.account.customerNumber) == nil {
            snapshot.account.customerNumber = accountId
        }

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

    /// Tras cargar la SPA, fuerza N° cliente (string 11 dígitos) y pide
    /// deuda + facturas + consumo vía reCAPTCHA invisible del sitio.
    private func triggerAPISyncIfNeeded() {
        guard !didTriggerAPISync, let webView, !accountId.isEmpty else { return }
        didTriggerAPISync = true
        let js = Self.syncScript(accountId: accountId)
        webView.evaluateJavaScript(js, completionHandler: nil)
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

    private static func syncScript(accountId: String) -> String {
        // Sitekey + sufijo reales de BaseController (saldos M360).
        """
        (function() {
          var ACCOUNT = "\(accountId)";
          var SITEKEY = "6LfBwaEsAAAAAN5TTI0xROYdHwXd0skXXNDBtfWM";
          var SUFFIX = "captchaMG2";
          if (window.__metrogasAPISyncStarted) return;
          window.__metrogasAPISyncStarted = true;

          function postNative(type, payload) {
            try { window.webkit.messageHandlers.metrogasSync.postMessage({type: type, payload: payload}); } catch (e) {}
          }

          function ensureRecaptcha(cb) {
            if (window.grecaptcha && window.grecaptcha.render) { cb(); return; }
            var s = document.createElement('script');
            s.src = 'https://www.google.com/recaptcha/api.js?render=explicit';
            s.onload = function() {
              var n = 0;
              var t = setInterval(function() {
                n++;
                if (window.grecaptcha && window.grecaptcha.render) { clearInterval(t); cb(); }
                else if (n > 40) { clearInterval(t); postNative('syncError', { message: 'recaptcha' }); }
              }, 250);
            };
            s.onerror = function() { postNative('syncError', { message: 'recaptcha-load' }); };
            document.head.appendChild(s);
          }

          function waitGrecaptchaReady(cb) {
            try {
              window.grecaptcha.ready(cb);
            } catch (e) {
              setTimeout(function() { waitGrecaptchaReady(cb); }, 200);
            }
          }

          function getToken(cb) {
            waitGrecaptchaReady(function() {
              var host = document.getElementById('__mg_captcha_host');
              if (!host) {
                host = document.createElement('div');
                host.id = '__mg_captcha_host';
                host.style.cssText = 'position:fixed;left:-9999px;width:1px;height:1px;opacity:0;';
                document.body.appendChild(host);
              }
              var done = false;
              function finish(token) {
                if (done) return;
                done = true;
                cb(token ? (token + SUFFIX) : '');
              }
              try {
                if (typeof window.__mgCaptchaId !== 'number') {
                  window.__mgCaptchaId = window.grecaptcha.render(host, {
                    sitekey: SITEKEY,
                    size: 'invisible',
                    callback: finish,
                    'error-callback': function() { finish(''); },
                    'expired-callback': function() { finish(''); }
                  });
                }
                window.grecaptcha.reset(window.__mgCaptchaId);
                window.grecaptcha.execute(window.__mgCaptchaId);
                setTimeout(function() { finish(''); }, 12000);
              } catch (e) {
                finish('');
              }
            });
          }

          function postJSON(path, bodyObj, cb) {
            getToken(function(token) {
              if (!token) { cb(0, ''); return; }
              var payload = Object.assign({}, bodyObj);
              if (path.indexOf('/consumption/') !== -1) {
                payload.captcha = token;
              } else {
                payload.captcha2 = token;
              }
              var xhr = new XMLHttpRequest();
              xhr.open('POST', path, true);
              xhr.setRequestHeader('Content-Type', 'application/json');
              xhr.setRequestHeader('Accept', 'application/json,*/*');
              xhr.onreadystatechange = function() {
                if (xhr.readyState === 4) {
                  cb(xhr.status, xhr.responseText || '');
                }
              };
              xhr.send(JSON.stringify(payload));
            });
          }

          function tryUI5Debt() {
            try {
              var inputs = document.querySelectorAll('input');
              for (var i = 0; i < inputs.length; i++) {
                var el = inputs[i];
                if ((el.value && el.value.length >= 10) || (el.id && el.id.toLowerCase().indexOf('cust') !== -1)) {
                  el.value = ACCOUNT;
                  el.dispatchEvent(new Event('input', { bubbles: true }));
                  el.dispatchEvent(new Event('change', { bubbles: true }));
                }
              }
            } catch (e) {}
          }

          function run() {
            tryUI5Debt();
            postNative('syncStart', { accountId: ACCOUNT });

            postJSON('/OvServiceHub/api/v1/M360/publicbilling/r2', {
              accountId: ACCOUNT,
              relation: 'FD'
            }, function(status, body) {
              postNative('net', { url: '/OvServiceHub/api/v1/M360/publicbilling/r2', method: 'POST', status: status, body: body });

              postJSON('/OvServiceHub/api/v1/M360/publicinvoice/listR2', {
                accountId: ACCOUNT
              }, function(status2, body2) {
                postNative('net', { url: '/OvServiceHub/api/v1/M360/publicinvoice/listR2', method: 'POST', status: status2, body: body2 });

                postJSON('/OvServiceHub/api/v1/M360/publicinvoice/consumption/' + ACCOUNT, {}, function(status3, body3) {
                  postNative('net', { url: '/OvServiceHub/api/v1/M360/publicinvoice/consumption/' + ACCOUNT, method: 'POST', status: status3, body: body3 });
                  postNative('syncDone', { accountId: ACCOUNT });
                });
              });
            });
          }

          ensureRecaptcha(function() {
            // Dar tiempo a que la SPA monte el shell / hash /go/
            setTimeout(run, 2500);
          });
        })();
        """
    }
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
            if url.localizedCaseInsensitiveContains("OvServiceHub")
                || url.localizedCaseInsensitiveContains("publicbilling")
                || url.localizedCaseInsensitiveContains("publicinvoice")
                || url.localizedCaseInsensitiveContains("consumption")
                || body.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{")
                || body.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("[") {
                captured.append((url, body))
            }
        } else if type == "dom", let payload = dict["payload"] as? [String: Any] {
            if let text = payload["text"] as? String, text.count > domText.count {
                domText = text
            }
        } else if type == "ready" || type == "pageReady" {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 3_500_000_000)
                triggerAPISyncIfNeeded()
            }
        } else if type == "syncDone" {
            Task { await completeIfNeeded() }
        }

        let early = PortalPayloadParser.parse(payloads: captured, domText: domText, loginHint: loginHint)
        let hasBilling = captured.contains { $0.url.localizedCaseInsensitiveContains("publicbilling") }
        let hasInvoices = !early.invoices.isEmpty
        let hasReadings = !early.readings.isEmpty
        // Esperar al menos deuda o facturas; si ya hay ambos (o consumo), cerrar.
        if hasInvoices && (hasBilling || hasReadings || early.account.holderName.isEmpty == false) {
            // No cerrar demasiado temprano: aún puede faltar consumption.
            if hasInvoices && hasReadings {
                Task { await completeIfNeeded() }
            }
        }
    }
}

extension PortalDataBridge: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript(Self.hookScript, completionHandler: nil)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            triggerAPISyncIfNeeded()
        }
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
            invoices = mergeInvoices(invoices, parsed.invoices)
            readings = mergeReadings(readings, parsed.readings)
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

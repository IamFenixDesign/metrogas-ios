import Foundation
import UIKit
import WebKit

/// Sync automático con la sesión de Oficina Virtual (Google o MetroGAS):
/// 1) Descubre N° de cliente / perfil en el portal autenticado
/// 2) Consulta saldos.micuenta (M360) con reCAPTCHA para facturas/consumo
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
    private var mode: SyncMode = .discover
    private var pageQueue: [URL] = []

    private enum SyncMode {
        case discover
        case saldos
    }

    /// Flujo completo: descubrir cuenta con la sesión y sincronizar M360.
    func syncFromSession(
        loginHint: String?,
        preferredAccountId: String?,
        timeoutSeconds: Double = 36
    ) async throws -> MetrogasDataSnapshot {
        var account = AccountProfile.empty
        if let loginHint, !loginHint.isEmpty {
            account.email = loginHint
            let local = loginHint.split(separator: "@").first.map(String.init) ?? loginHint
            account.holderName = local.replacingOccurrences(of: ".", with: " ").capitalized
        }

        // 1) Portal autenticado: N° de cliente / titular / lo que exponga la OV.
        let discovery = try await runCapture(
            mode: .discover,
            accountId: "",
            loginHint: loginHint,
            startURLs: [
                MetrogasURLs.portalOV2,
                MetrogasURLs.accesoOV2,
                MetrogasURLs.portalMobile,
                MetrogasURLs.acceso
            ],
            timeoutSeconds: min(18, timeoutSeconds * 0.45)
        )

        account = MetrogasJSONParser.mergeAccount(account, discovery.account)
        var invoices = discovery.invoices
        var readings = discovery.readings

        let discoveredId =
            MetrogasURLs.normalizedCustomerNumber(preferredAccountId ?? "")
            ?? MetrogasURLs.normalizedCustomerNumber(discovery.account.customerNumber)
            ?? extractCustomerNumber(from: discovery)
            ?? extractCustomerNumber(fromDOM: discovery)

        guard let accountId = discoveredId else {
            return MetrogasDataSnapshot(account: account, invoices: invoices, readings: readings)
        }

        account.customerNumber = accountId

        // 2) Saldos M360 con el N° descubierto (o el ya persistido).
        let saldos = try await runCapture(
            mode: .saldos,
            accountId: accountId,
            loginHint: loginHint,
            startURLs: [MetrogasURLs.saldosGo(accountId: accountId)],
            timeoutSeconds: max(22, timeoutSeconds * 0.55)
        )

        account = MetrogasJSONParser.mergeAccount(account, saldos.account)
        account.customerNumber = accountId
        invoices = mergeInvoices(invoices, saldos.invoices)
        readings = mergeReadings(readings, saldos.readings)

        if readings.isEmpty && !invoices.isEmpty {
            readings = MetrogasJSONParser.deriveReadings(from: invoices)
        }

        return MetrogasDataSnapshot(account: account, invoices: invoices, readings: readings)
    }

    /// Solo saldos (cuando ya hay N° de cliente).
    func sync(accountId: String, loginHint: String?, timeoutSeconds: Double = 28) async throws -> MetrogasDataSnapshot {
        guard let normalized = MetrogasURLs.normalizedCustomerNumber(accountId) else {
            throw MetrogasAuthError.unexpectedResponse
        }
        return try await runCapture(
            mode: .saldos,
            accountId: normalized,
            loginHint: loginHint,
            startURLs: [MetrogasURLs.saldosGo(accountId: normalized)],
            timeoutSeconds: timeoutSeconds
        )
    }

    // MARK: - Core capture

    private func runCapture(
        mode: SyncMode,
        accountId: String,
        loginHint: String?,
        startURLs: [URL],
        timeoutSeconds: Double
    ) async throws -> MetrogasDataSnapshot {
        if continuation != nil {
            throw MetrogasAuthError.unexpectedResponse
        }

        self.mode = mode
        self.accountId = accountId
        self.loginHint = loginHint
        self.didTriggerAPISync = false
        self.pageQueue = Array(startURLs.dropFirst())
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
            if let first = startURLs.first {
                webView.load(URLRequest(url: first))
            } else {
                Task { await self.completeIfNeeded() }
            }

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
        if !accountId.isEmpty,
           MetrogasURLs.normalizedCustomerNumber(snapshot.account.customerNumber) == nil {
            snapshot.account.customerNumber = accountId
        }

        // También intentar sacar N° / email del DOM crudo.
        if MetrogasURLs.normalizedCustomerNumber(snapshot.account.customerNumber) == nil,
           let found = MetrogasJSONParser.firstCustomerNumber(in: domText) {
            snapshot.account.customerNumber = found
        }
        if snapshot.account.email.isEmpty,
           let email = MetrogasJSONParser.firstEmail(in: domText) {
            snapshot.account.email = email
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
        pageQueue.removeAll()
    }

    private func loadNextPageIfNeeded() {
        guard mode == .discover, let webView, let next = pageQueue.first else { return }
        pageQueue.removeFirst()
        webView.load(URLRequest(url: next))
    }

    private func triggerSaldosAPISyncIfNeeded() {
        guard mode == .saldos, !didTriggerAPISync, let webView, !accountId.isEmpty else { return }
        didTriggerAPISync = true
        webView.evaluateJavaScript(Self.syncScript(accountId: accountId), completionHandler: nil)
    }

    private func triggerPortalDiscoveryProbe() {
        guard mode == .discover, let webView else { return }
        webView.evaluateJavaScript(Self.discoveryProbeScript, completionHandler: nil)
    }

    private func extractCustomerNumber(from snapshot: MetrogasDataSnapshot) -> String? {
        MetrogasURLs.normalizedCustomerNumber(snapshot.account.customerNumber)
            ?? MetrogasJSONParser.firstCustomerNumber(in: snapshot.account.supplyAddress)
    }

    private func extractCustomerNumber(fromDOM snapshot: MetrogasDataSnapshot) -> String? {
        // El parser DOM ya pudo setear customerNumber; también buscamos en invoices.
        if let id = MetrogasURLs.normalizedCustomerNumber(snapshot.account.customerNumber) {
            return id
        }
        for inv in snapshot.invoices {
            if let id = MetrogasURLs.normalizedCustomerNumber(inv.number) { return id }
            if let id = MetrogasURLs.normalizedCustomerNumber(inv.supplyPoint) { return id }
        }
        return nil
    }

    private func mergeInvoices(_ a: [Invoice], _ b: [Invoice]) -> [Invoice] {
        var map: [String: Invoice] = [:]
        for inv in a + b { map[inv.id] = inv }
        return Array(map.values).sorted { $0.dueDate > $1.dueDate }
    }

    private func mergeReadings(_ a: [ConsumptionReading], _ b: [ConsumptionReading]) -> [ConsumptionReading] {
        var seen = Set<String>()
        return (a + b).filter { r in
            let key = "\(r.periodStart.timeIntervalSince1970)-\(r.cubicMeters)"
            return seen.insert(key).inserted
        }.sorted { $0.periodStart < $1.periodStart }
    }

    // MARK: - Injected scripts

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
      setInterval(scrape, 2200);
      setTimeout(scrape, 1200);
      post('ready', { href: location.href });
    })();
    """

    /// Desde el portal autenticado, prueba endpoints típicos y reporta JSON.
    private static let discoveryProbeScript = """
    (function() {
      if (window.__metrogasDiscoveryProbe) return;
      window.__metrogasDiscoveryProbe = true;
      function post(type, payload) {
        try { window.webkit.messageHandlers.metrogasSync.postMessage({type: type, payload: payload}); } catch (e) {}
      }
      var paths = [
        '/OvServiceHub/api/v1/web/M360/account',
        '/OvServiceHub/api/v1/web/M360/accounts',
        '/OvServiceHub/api/v1/web/M360/customer',
        '/OvServiceHub/api/v1/web/M360/profile',
        '/OvServiceHub/api/v1/web/M360/home',
        '/OvServiceHub/api/v1/web/M360/dashboard',
        '/OvServiceHub/api/v1/web/M360/invoices',
        '/OvServiceHub/api/v1/web/M360/billing',
        '/OvServiceHub/api/v1/web/M360/balance',
        '/OvServiceHub/api/v1/web/M360/consumption',
        '/OvServiceHub/api/v1/secured/M360/account',
        '/OvServiceHub/api/v1/secured/M360/invoices',
        '/OvServiceHub/api/v1/secured/M360/balance',
        '/OvServiceHub/api/v1/M360/account',
        '/OvServiceHub/api/v1/M360/customer'
      ];
      paths.forEach(function(path) {
        try {
          var xhr = new XMLHttpRequest();
          xhr.open('GET', path, true);
          xhr.setRequestHeader('Accept', 'application/json,*/*');
          xhr.setRequestHeader('X-Requested-With', 'XMLHttpRequest');
          xhr.onreadystatechange = function() {
            if (xhr.readyState === 4) {
              post('net', { url: path, method: 'GET', status: xhr.status, body: (xhr.responseText || '').substring(0, 600000) });
            }
          };
          xhr.send();
        } catch (e) {}
      });
      try {
        var text = document.body ? (document.body.innerText || '') : '';
        post('dom', { text: text.substring(0, 250000), href: location.href });
      } catch (e) {}
      post('discoverDone', { href: location.href });
    })();
    """

    private static func syncScript(accountId: String) -> String {
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
            try { window.grecaptcha.ready(cb); }
            catch (e) { setTimeout(function() { waitGrecaptchaReady(cb); }, 200); }
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
              } catch (e) { finish(''); }
            });
          }

          function postJSON(path, bodyObj, cb) {
            getToken(function(token) {
              if (!token) { cb(0, ''); return; }
              var payload = Object.assign({}, bodyObj);
              if (path.indexOf('/consumption/') !== -1) payload.captcha = token;
              else payload.captcha2 = token;
              var xhr = new XMLHttpRequest();
              xhr.open('POST', path, true);
              xhr.setRequestHeader('Content-Type', 'application/json');
              xhr.setRequestHeader('Accept', 'application/json,*/*');
              xhr.onreadystatechange = function() {
                if (xhr.readyState === 4) cb(xhr.status, xhr.responseText || '');
              };
              xhr.send(JSON.stringify(payload));
            });
          }

          function run() {
            postNative('syncStart', { accountId: ACCOUNT });
            postJSON('/OvServiceHub/api/v1/M360/publicbilling/r2', {
              accountId: ACCOUNT, relation: 'FD'
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

          ensureRecaptcha(function() { setTimeout(run, 2200); });
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
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            if url.localizedCaseInsensitiveContains("OvServiceHub")
                || url.localizedCaseInsensitiveContains("publicbilling")
                || url.localizedCaseInsensitiveContains("publicinvoice")
                || url.localizedCaseInsensitiveContains("consumption")
                || url.localizedCaseInsensitiveContains("account")
                || url.localizedCaseInsensitiveContains("customer")
                || url.localizedCaseInsensitiveContains("invoice")
                || trimmed.hasPrefix("{")
                || trimmed.hasPrefix("[") {
                captured.append((url, body))
            }
        } else if type == "dom", let payload = dict["payload"] as? [String: Any] {
            if let text = payload["text"] as? String, text.count > domText.count {
                domText = text
            }
        } else if type == "ready" {
            if mode == .discover {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    triggerPortalDiscoveryProbe()
                    try? await Task.sleep(nanoseconds: 3_500_000_000)
                    loadNextPageIfNeeded()
                }
            } else {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    triggerSaldosAPISyncIfNeeded()
                }
            }
        } else if type == "discoverDone" {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                // Si ya hay N° de cliente usable, podemos cortar discovery.
                let early = PortalPayloadParser.parse(payloads: captured, domText: domText, loginHint: loginHint)
                if MetrogasURLs.normalizedCustomerNumber(early.account.customerNumber) != nil
                    || MetrogasJSONParser.firstCustomerNumber(in: domText) != nil {
                    if pageQueue.isEmpty {
                        await completeIfNeeded()
                    } else {
                        loadNextPageIfNeeded()
                    }
                } else {
                    loadNextPageIfNeeded()
                }
            }
        } else if type == "syncDone" {
            Task { await completeIfNeeded() }
        }

        if mode == .saldos {
            let early = PortalPayloadParser.parse(payloads: captured, domText: domText, loginHint: loginHint)
            if !early.invoices.isEmpty && !early.readings.isEmpty {
                Task { await completeIfNeeded() }
            }
        }
    }
}

extension PortalDataBridge: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript(Self.hookScript, completionHandler: nil)
        if mode == .saldos {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 3_500_000_000)
                triggerSaldosAPISyncIfNeeded()
            }
        } else {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                triggerPortalDiscoveryProbe()
            }
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

        let fromDOM = MetrogasJSONParser.parseDOMText(domText)
        if invoices.isEmpty { invoices = fromDOM.invoices }
        if readings.isEmpty { readings = fromDOM.readings }
        account = MetrogasJSONParser.mergeAccount(account, fromDOM.account)

        if account.email.isEmpty, let email = MetrogasJSONParser.firstEmail(in: domText) {
            account.email = email
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

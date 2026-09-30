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
    /// Candidatos de N° descubiertos en la sesión autenticada del portal.
    private var discoveredAccountIds: [String] = []
    private enum SyncMode {
        case discover
        case saldos
    }

    /// Flujo completo: descubre N° en el portal autenticado y luego consulta M360.
    /// `preferredAccountId` solo se usa si aparece entre los candidatos del portal.
    /// Nunca sincroniza un N° preferido sin candidatos de sesión (M360 es público).
    func syncFromSession(
        loginHint: String?,
        preferredAccountId: String?,
        forcePortalDiscovery: Bool = true,
        timeoutSeconds: Double = 36
    ) async throws -> MetrogasDataSnapshot {
        var account = AccountProfile.empty
        if let loginHint, !loginHint.isEmpty {
            account.email = loginHint
        }

        let preferred = MetrogasURLs.normalizedCustomerNumber(preferredAccountId ?? "")

        // Camino rápido solo si el caller lo pide Y hay N° — igual se valida ownership abajo.
        // En la práctica MetrogasDataService siempre fuerza discovery tras Google.
        if !forcePortalDiscovery, let linkedId = preferred {
            let saldos = try await syncSaldosOnly(
                accountId: linkedId,
                loginHint: loginHint,
                base: account,
                timeout: min(16, timeoutSeconds)
            )
            let ownership = Self.emailOwnership(loginHint: loginHint, accountEmail: saldos.account.email)
            // Sin match de email no confiamos en un N° “recordado” (M360 es público).
            if ownership == .match || ownership == .unknown {
                var out = saldos
                if let loginHint, !loginHint.isEmpty { out.account.email = loginHint }
                out.account.customerNumber = linkedId
                return out
            }
            // mismatch → caer a discovery
        }

        // 1) Portal autenticado de ESTA sesión Google/MetroGAS → candidatos reales.
        discoveredAccountIds = []
        let discovery = try await runCapture(
            mode: .discover,
            accountId: "",
            loginHint: loginHint,
            startURLs: [
                MetrogasURLs.portalOV2,
                MetrogasURLs.portalMobile,
                MetrogasURLs.accesoOV2,
                MetrogasURLs.acceso
            ],
            timeoutSeconds: min(20, timeoutSeconds * 0.5)
        )

        account = MetrogasJSONParser.mergeAccount(account, discovery.account)

        let portalCandidates = uniqueAccountIds(
            discoveredAccountIds
            + [
                MetrogasURLs.normalizedCustomerNumber(discovery.account.customerNumber),
                MetrogasJSONParser.labeledCustomerNumber(in: domText),
                MetrogasJSONParser.labeledCustomerNumber(in: domTextAfterLastCapture(discovery))
            ].compactMap { $0 }
        )

        // Sin candidatos del portal → NO adivinar con preferred (evita titular/N° ajenos).
        guard !portalCandidates.isEmpty else {
            return MetrogasDataSnapshot(account: account, invoices: [], readings: [])
        }

        var ordered = portalCandidates
        if let preferred, let idx = ordered.firstIndex(of: preferred) {
            ordered.remove(at: idx)
            ordered.insert(preferred, at: 0)
        }

        // 2) M360 solo enriquece N° ya vistos en el portal de esta sesión.
        // Preferir match email Google == factura digital; si no hay email en M360,
        // aceptar candidato del portal (la sesión OV ya lo autoriza).
        // Mismatch estricto se SALTEA (sería otra cuenta).
        var matched: MetrogasDataSnapshot?
        var unknownFromPortal: MetrogasDataSnapshot?
        let saldosTimeout = max(14, timeoutSeconds * 0.45)
        let portalSet = Set(portalCandidates)

        for accountId in ordered.prefix(3) {
            guard portalSet.contains(accountId) else { continue }

            let saldos = try await syncSaldosOnly(
                accountId: accountId,
                loginHint: loginHint,
                base: account,
                timeout: saldosTimeout
            )
            let ownership = Self.emailOwnership(loginHint: loginHint, accountEmail: saldos.account.email)

            let hasSignal = !saldos.account.holderName.isEmpty
                || (!saldos.account.supplyAddress.isEmpty && saldos.account.supplyAddress != "—")
                || !saldos.invoices.isEmpty
            guard hasSignal else { continue }

            var enriched = saldos
            if let loginHint, !loginHint.isEmpty {
                enriched.account.email = loginHint
            }
            enriched.account.customerNumber = accountId

            switch ownership {
            case .match:
                matched = enriched
                return enriched
            case .unknown:
                if unknownFromPortal == nil { unknownFromPortal = enriched }
            case .mismatch:
                // Email de factura digital ≠ Google → no es esta cuenta. Seguir buscando.
                continue
            }
        }

        if let matched { return matched }
        if let unknownFromPortal { return unknownFromPortal }
        return MetrogasDataSnapshot(account: account, invoices: [], readings: [])
    }

    private enum EmailOwnership {
        case match
        case mismatch
        case unknown
    }

    private static func emailOwnership(loginHint: String?, accountEmail: String) -> EmailOwnership {
        let login = loginHint?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let account = accountEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard login.contains("@"), account.contains("@") else { return .unknown }
        return login == account ? .match : .mismatch
    }

    private func syncSaldosOnly(
        accountId: String,
        loginHint: String?,
        base: AccountProfile,
        timeout: Double
    ) async throws -> MetrogasDataSnapshot {
        var account = base
        let saldos = try await runCapture(
            mode: .saldos,
            accountId: accountId,
            loginHint: loginHint,
            startURLs: [MetrogasURLs.saldosGo(accountId: accountId)],
            timeoutSeconds: timeout
        )
        account = MetrogasJSONParser.mergeAccount(account, saldos.account)
        if let billingId = MetrogasURLs.normalizedCustomerNumber(saldos.account.customerNumber) {
            account.customerNumber = billingId
        } else {
            account.customerNumber = accountId
        }
        var invoices = saldos.invoices
        var readings = saldos.readings
        if readings.isEmpty && !invoices.isEmpty {
            readings = MetrogasJSONParser.deriveReadings(from: invoices)
        }
        return MetrogasDataSnapshot(account: account, invoices: invoices, readings: readings)
    }

    private func uniqueAccountIds(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for raw in ids {
            guard let id = MetrogasURLs.normalizedCustomerNumber(raw), !seen.contains(id) else { continue }
            seen.insert(id)
            out.append(id)
        }
        return out
    }

    private func domTextAfterLastCapture(_ snapshot: MetrogasDataSnapshot) -> String {
        // El DOM crudo ya se aplicó al snapshot; reutilizamos campos de cuenta.
        [
            snapshot.account.customerNumber,
            snapshot.account.supplyAddress,
            snapshot.account.holderName,
            snapshot.account.email
        ].joined(separator: " ")
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
        if mode == .discover {
            discoveredAccountIds = []
        }

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

        // Solo N° etiquetado en DOM (nunca un bloque suelto de 11 dígitos).
        if MetrogasURLs.normalizedCustomerNumber(snapshot.account.customerNumber) == nil,
           let found = MetrogasJSONParser.labeledCustomerNumber(in: domText) {
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
    }

    private func extractCustomerNumber(fromDOM snapshot: MetrogasDataSnapshot) -> String? {
        // Nunca usar nro. de factura / supplyPoint como N° de cliente.
        MetrogasURLs.normalizedCustomerNumber(snapshot.account.customerNumber)
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
      setInterval(scrape, 1400);
      setTimeout(scrape, 400);
      post('ready', { href: location.href });
    })();
    """

    /// Lee storage/UI5/DOM del portal autenticado y reporta el N° ligado (sin XHR basura).
    private static let discoveryProbeScript = """
    (function() {
      // Permitir re-probe: UI5/Google tarda en hidratar storage/modelos.
      function post(type, payload) {
        try { window.webkit.messageHandlers.metrogasSync.postMessage({type: type, payload: payload}); } catch (e) {}
      }
      function collectElevenDigitIds(text) {
        var out = [];
        if (!text) return out;
        var re = /\\b(\\d{11})\\b/g;
        var m;
        while ((m = re.exec(String(text))) !== null) {
          if (out.indexOf(m[1]) === -1) out.push(m[1]);
        }
        return out;
      }
      function isAccountKey(k) {
        var lk = String(k || '').toLowerCase();
        // Evitar claves vagas (account/cuenta) que metían N° de facturas ajenos.
        return lk.indexOf('nro_cliente') !== -1 || lk.indexOf('nrocliente') !== -1
          || lk.indexOf('numero_cliente') !== -1 || lk.indexOf('pve_nro') !== -1
          || lk === 'vkont' || lk.indexOf('vkont') !== -1
          || lk.indexOf('accountid') !== -1 || lk.indexOf('account_id') !== -1
          || lk.indexOf('cta_contrato') !== -1 || lk.indexOf('ctacontrato') !== -1
          || (lk.indexOf('cliente') !== -1 && lk.indexOf('mail') === -1 && lk.indexOf('email') === -1
              && lk.indexOf('factura') === -1);
      }
      function walk(node, bag, depth, fromAccountKey) {
        if (!node || depth > 7) return;
        if (typeof node === 'string' || typeof node === 'number') {
          if (fromAccountKey) {
            collectElevenDigitIds(String(node)).forEach(function(id) {
              if (bag.indexOf(id) === -1) bag.push(id);
            });
          }
          return;
        }
        if (Array.isArray(node)) {
          node.slice(0, 60).forEach(function(item) { walk(item, bag, depth + 1, fromAccountKey); });
          return;
        }
        if (typeof node === 'object') {
          Object.keys(node).forEach(function(k) {
            walk(node[k], bag, depth + 1, fromAccountKey || isAccountKey(k));
          });
        }
      }
      var found = [];
      try {
        for (var i = 0; i < localStorage.length; i++) {
          var lk = localStorage.key(i);
          walk(localStorage.getItem(lk), found, 0, isAccountKey(lk));
        }
        for (var j = 0; j < sessionStorage.length; j++) {
          var sk = sessionStorage.key(j);
          walk(sessionStorage.getItem(sk), found, 0, isAccountKey(sk));
        }
      } catch (e) {}
      try {
        if (window.sap && sap.ui && sap.ui.getCore) {
          var core = sap.ui.getCore();
          if (core && core.getModel) {
            ['', 'appModel'].forEach(function(name) {
              try {
                var model = name ? core.getModel(name) : core.getModel();
                if (model && model.getData) walk(model.getData(), found, 0, false);
              } catch (e2) {}
            });
          }
        }
      } catch (e) {}
      try {
        var text = document.body ? (document.body.innerText || '') : '';
        // Solo etiquetados en DOM visible (no cualquier bloque de 11 dígitos).
        var labeled = text.match(/(?:N[°º]?\\s*(?:de\\s*)?cliente|nro\\.?\\s*(?:de\\s*)?cliente|accountId|PVE_NRO_CLIENTE|VKONT)\\s*[:#=]?\\s*([0-9]{11})/i);
        if (labeled && labeled[1] && found.indexOf(labeled[1]) === -1) found.unshift(labeled[1]);
        post('dom', { text: text.substring(0, 250000), href: location.href });
      } catch (e) {}
      try {
        var cookieText = String(document.cookie || '');
        var cookieBits = cookieText.split(';');
        for (var c = 0; c < cookieBits.length; c++) {
          var part = cookieBits[c].split('=');
          var ck = (part[0] || '').trim();
          var cv = part.slice(1).join('=');
          if (isAccountKey(ck)) {
            collectElevenDigitIds(cv).forEach(function(id) {
              if (found.indexOf(id) === -1) found.push(id);
            });
          }
        }
      } catch (e) {}
      if (found.length) {
        post('linkedAccounts', { ids: found });
        post('net', {
          url: '/metrogas/linked-account-discovery',
          method: 'GET',
          status: 200,
          body: JSON.stringify({ accountId: found[0], linkedAccounts: found, source: 'portal-session' })
        });
      }
      post('discoverDone', { href: location.href, linked: found });
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
                setTimeout(function() { finish(''); }, 7000);
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

          function getJSON(path, cb) {
            getToken(function(token) {
              if (!token) { cb(0, ''); return; }
              var url = path;
              if (path.indexOf('/publicSubscription/') !== -1) {
                url = path.replace(/\\/?$/, '/') + token;
              }
              var xhr = new XMLHttpRequest();
              xhr.open('GET', url, true);
              xhr.setRequestHeader('Accept', 'application/json,*/*');
              xhr.onreadystatechange = function() {
                if (xhr.readyState === 4) cb(xhr.status, xhr.responseText || '');
              };
              xhr.send();
            });
          }

          function run() {
            postNative('syncStart', { accountId: ACCOUNT });
            var finished = false;
            function finishSync() {
              if (finished) return;
              finished = true;
              postNative('syncDone', { accountId: ACCOUNT });
            }
            // Billing (titular/dirección/medidor) → publicAccount (contacto/perfil) →
            // facturas → factura digital (email) → consumo.
            postJSON('/OvServiceHub/api/v1/M360/publicbilling/r2', {
              accountId: ACCOUNT, relation: 'FD'
            }, function(status, body) {
              postNative('net', { url: '/OvServiceHub/api/v1/M360/publicbilling/r2', method: 'POST', status: status, body: body });
              postJSON('/OvServiceHub/api/v1/M360/publicAccount', {
                accountId: ACCOUNT, relation: 'FD'
              }, function(statusA, bodyA) {
                postNative('net', { url: '/OvServiceHub/api/v1/M360/publicAccount', method: 'POST', status: statusA, body: bodyA });
                postJSON('/OvServiceHub/api/v1/publicAccount', {
                  accountId: ACCOUNT, relation: 'FD'
                }, function(statusB, bodyB) {
                  postNative('net', { url: '/OvServiceHub/api/v1/publicAccount', method: 'POST', status: statusB, body: bodyB });
                  postJSON('/OvServiceHub/api/v1/M360/publicinvoice/listR2', {
                    accountId: ACCOUNT
                  }, function(status2, body2) {
                    postNative('net', { url: '/OvServiceHub/api/v1/M360/publicinvoice/listR2', method: 'POST', status: status2, body: body2 });
                    getJSON('/OvServiceHub/api/v1/publicSubscription/' + ACCOUNT, function(status4, body4) {
                      postNative('net', { url: '/OvServiceHub/api/v1/publicSubscription/' + ACCOUNT, method: 'GET', status: status4, body: body4 });
                      getJSON('/OvServiceHub/api/v1/M360/publicSubscription/' + ACCOUNT, function(status5, body5) {
                        postNative('net', { url: '/OvServiceHub/api/v1/M360/publicSubscription/' + ACCOUNT, method: 'GET', status: status5, body: body5 });
                        postJSON('/OvServiceHub/api/v1/M360/publicinvoice/consumption/' + ACCOUNT, {}, function(status3, body3) {
                          postNative('net', { url: '/OvServiceHub/api/v1/M360/publicinvoice/consumption/' + ACCOUNT, method: 'POST', status: status3, body: body3 });
                          finishSync();
                        });
                      });
                    });
                  });
                });
              });
            });
            setTimeout(finishSync, 22000);
          }

          ensureRecaptcha(function() { setTimeout(run, 400); });
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
                || url.localizedCaseInsensitiveContains("publicsubscription")
                || url.localizedCaseInsensitiveContains("publicAccount")
                || url.localizedCaseInsensitiveContains("consumption")
                || url.localizedCaseInsensitiveContains("account")
                || url.localizedCaseInsensitiveContains("customer")
                || url.localizedCaseInsensitiveContains("invoice")
                || url.localizedCaseInsensitiveContains("linked-account")
                || trimmed.hasPrefix("{")
                || trimmed.hasPrefix("[") {
                captured.append((url, body))
                maybeFinishSaldosEarly(url: url)
            }
        } else if type == "dom", let payload = dict["payload"] as? [String: Any] {
            if let text = payload["text"] as? String, text.count > domText.count {
                domText = text
            }
        } else if type == "ready" {
            if mode == .discover {
                Task { @MainActor in
                    // Esperar shell UI5/OV (Google/SAP tarda más en hidratar modelos).
                    try? await Task.sleep(nanoseconds: 1_600_000_000)
                    triggerPortalDiscoveryProbe()
                    try? await Task.sleep(nanoseconds: 1_800_000_000)
                    triggerPortalDiscoveryProbe()
                }
            } else {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    triggerSaldosAPISyncIfNeeded()
                }
            }
        } else if type == "linkedAccounts",
                  let payload = dict["payload"] as? [String: Any] {
            let ids = (payload["ids"] as? [Any] ?? []).compactMap { value -> String? in
                if let s = value as? String { return MetrogasURLs.normalizedCustomerNumber(s) }
                if let n = value as? NSNumber { return MetrogasURLs.normalizedCustomerNumber(n.stringValue) }
                return nil
            }
            discoveredAccountIds = uniqueAccountIds(discoveredAccountIds + ids)
        } else if type == "discoverDone" {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 250_000_000)
                if let payload = dict["payload"] as? [String: Any],
                   let linked = payload["linked"] as? [Any] {
                    let ids = linked.compactMap { value -> String? in
                        if let s = value as? String { return MetrogasURLs.normalizedCustomerNumber(s) }
                        if let n = value as? NSNumber { return MetrogasURLs.normalizedCustomerNumber(n.stringValue) }
                        return nil
                    }
                    discoveredAccountIds = uniqueAccountIds(discoveredAccountIds + ids)
                }
                // Cortar solo con candidatos de sesión o N° etiquetado (no dígitos sueltos).
                let early = PortalPayloadParser.parse(payloads: captured, domText: domText, loginHint: loginHint)
                let hasCandidate = !discoveredAccountIds.isEmpty
                    || MetrogasURLs.normalizedCustomerNumber(early.account.customerNumber) != nil
                    || MetrogasJSONParser.labeledCustomerNumber(in: domText) != nil
                if hasCandidate {
                    await completeIfNeeded()
                } else if !pageQueue.isEmpty {
                    loadNextPageIfNeeded()
                } else {
                    await completeIfNeeded()
                }
            }
        } else if type == "syncDone" {
            Task { await completeIfNeeded() }
        }
    }

    private func maybeFinishSaldosEarly(url: String) {
        guard mode == .saldos, continuation != nil else { return }
        let lower = url.lowercased()
        let isProfileEndpoint = lower.contains("publicbilling")
            || lower.contains("publicaccount")
            || lower.contains("publicsubscription")
        guard isProfileEndpoint || lower.contains("listr2") else { return }

        Task { @MainActor in
            // No cerrar hasta tener billing + intento de contacto (account/subscription).
            let urls = captured.map { $0.url.lowercased() }
            guard urls.contains(where: { $0.contains("publicbilling") }) else { return }
            let triedContact = urls.contains(where: {
                $0.contains("publicaccount") || $0.contains("publicsubscription")
            })
            guard triedContact else { return }

            let early = PortalPayloadParser.parse(payloads: captured, domText: domText, loginHint: loginHint)
            let profile = early.account
            let hasCoreProfile = !profile.holderName.isEmpty
                || (!profile.supplyAddress.isEmpty && profile.supplyAddress != "—")
                || (!profile.meterNumber.isEmpty && profile.meterNumber != "—")
            // Perfil “completo” para Cuenta: titular + domicilio + (email o teléfono si vino).
            let hasContact = !profile.email.isEmpty
                || (!profile.phone.isEmpty && profile.phone != "—")
            let contactAttemptDone = urls.contains(where: { $0.contains("publicsubscription") })
                && urls.contains(where: { $0.contains("publicaccount") })

            if hasCoreProfile && (hasContact || contactAttemptDone) {
                await completeIfNeeded()
            }
        }
    }
}

extension PortalDataBridge: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript(Self.hookScript, completionHandler: nil)
        if mode == .saldos {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 450_000_000)
                triggerSaldosAPISyncIfNeeded()
            }
        } else {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_200_000_000)
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

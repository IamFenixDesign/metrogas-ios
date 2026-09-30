import Foundation

enum MetrogasAuthError: LocalizedError {
    case bootstrapFailed
    case invalidCredentials
    case unexpectedResponse
    case googleStartFailed
    case cancelled
    case sessionExpired

    var errorDescription: String? {
        switch self {
        case .bootstrapFailed:
            return "No pudimos conectar con el acceso de MetroGAS. Probá de nuevo."
        case .invalidCredentials:
            return "Email o contraseña incorrectos."
        case .unexpectedResponse:
            return "La respuesta del servidor no fue la esperada."
        case .googleStartFailed:
            return "No pudimos abrir el inicio de sesión con Google."
        case .cancelled:
            return "Inicio de sesión cancelado."
        case .sessionExpired:
            return "Tu sesión venció. Volvé a iniciar sesión."
        }
    }
}

/// Autenticación contra SAP Identity de MetroGAS (Oficina Virtual).
/// Email/contraseña: flujo nativo HTTP. Google: obtiene la URL oficial de Google OAuth.
actor MetrogasAuthService {
    static let shared = MetrogasAuthService()

    private let session: URLSession
    private let cookieJar: HTTPCookieStorage

    private init() {
        let jar = HTTPCookieStorage.shared
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = jar
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.timeoutIntervalForRequest = 30
        self.cookieJar = jar
        self.session = URLSession(configuration: config)
    }

    // MARK: - Public

    func login(email: String, password: String) async throws {
        try await performCredentialLogin(email: email, password: password)
    }

    /// Revalida la sesión del portal. Si venció y hay credenciales, re-loguea en silencio.
    @discardableResult
    func ensureActiveSession(email: String?, password: String?) async throws -> Bool {
        if await probePortalSession() {
            return true
        }

        // Si todavía hay cookies de sesión, un fallo de probe puede ser red/transitorio.
        let hadCookies = hasMetrogasSessionCookie()

        if let email, let password, !email.isEmpty, !password.isEmpty {
            do {
                try await performCredentialLogin(email: email, password: password)
                if await probePortalSession() { return true }
            } catch MetrogasAuthError.invalidCredentials {
                throw MetrogasAuthError.invalidCredentials
            } catch {
                if hadCookies { return true }
                throw error
            }
        }

        if hadCookies {
            // Mantener sesión local; el fetch de datos dirá si realmente murió.
            return true
        }

        throw MetrogasAuthError.sessionExpired
    }

    /// True si el portal responde con shell autenticado (no pantalla de login).
    func probePortalSession() async -> Bool {
        do {
            var html = try await loadPortalHTML()
            for _ in 0..<5 {
                if looksLikeAuthenticatedPortal(html: html, urlHint: nil) {
                    return true
                }
                if htmlContainsUsernameField(html) || htmlContainsPasswordField(html) {
                    return false
                }
                guard let action = firstFormAction(in: html) else { break }
                let fields = extractFormFields(from: html)
                let result = try await post(action, fields: fields)
                html = String(data: result.data, encoding: .utf8) ?? ""
                if looksLikeAuthenticatedPortal(html: html, urlHint: result.url) {
                    return true
                }
                if htmlContainsUsernameField(html) || htmlContainsPasswordField(html) {
                    return false
                }
            }
            return hasMetrogasSessionCookie() && !htmlContainsUsernameField(html)
        } catch {
            return false
        }
    }

    private func performCredentialLogin(email: String, password: String) async throws {
        try await bootstrapLoginPage()
        var html = try await currentLoginHTML()

        // Paso email (pantalla condicional) o email+password juntos.
        html = try await submitLogin(html: html, email: email, password: nil)

        if htmlContainsPasswordField(html) {
            html = try await submitLogin(html: html, email: email, password: password)
        } else if !looksAuthenticated(html: html) {
            // Algunas sesiones piden password en la misma acción.
            html = try await submitLogin(html: html, email: email, password: password)
        }

        if htmlContainsInvalidCredentials(html) {
            throw MetrogasAuthError.invalidCredentials
        }

        // Seguir redirects residuales al portal.
        _ = try await get(MetrogasURLs.portalMobile)

        if hasMetrogasSessionCookie() || looksAuthenticated(html: html) {
            return
        }

        if await probePortalSession() {
            return
        }

        // Último intento: abrir portal y ver si ya no pide login
        let portal = try await get(MetrogasURLs.portalMobile)
        if portal.url?.host?.contains("accounts.ondemand.com") == true
            || htmlContainsPasswordField(String(data: portal.data, encoding: .utf8) ?? "") {
            throw MetrogasAuthError.invalidCredentials
        }
    }

    private func loadPortalHTML() async throws -> String {
        let portal = try await get(MetrogasURLs.portalMobile)
        return String(data: portal.data, encoding: .utf8) ?? ""
    }

    private func looksLikeAuthenticatedPortal(html: String, urlHint: URL?) -> Bool {
        if let host = urlHint?.host?.lowercased(),
           MetrogasURLs.isMetrogasPortalHost(host),
           !htmlContainsUsernameField(html),
           !htmlContainsPasswordField(html) {
            return true
        }
        let lowered = html.lowercased()
        if htmlContainsUsernameField(html) || htmlContainsPasswordField(html) {
            return false
        }
        return lowered.contains("sap-ui")
            || lowered.contains("flp")
            || lowered.contains("ovmetrogas")
            || lowered.contains("shell-home")
            || looksAuthenticated(html: html)
    }

    /// Prepara la URL de Google OAuth usada por MetroGAS/SAP Identity.
    func prepareGoogleOAuthURL() async throws -> URL {
        let loginHTML = try await bootstrapLoginPage()
        let fields = extractFormFields(from: loginHTML)
        guard !fields.isEmpty else { throw MetrogasAuthError.googleStartFailed }

        let action = URL(string: "https://asskova9q.accounts.ondemand.com/ui/oauth/socialProviderLogin?network=GOOGLE")!
        var request = URLRequest(url: action)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(MetrogasURLs.portalMobile.absoluteString, forHTTPHeaderField: "Referer")
        request.httpBody = formBody(fields)

        let (data, response) = try await session.data(for: request)
        let html = String(data: data, encoding: .utf8) ?? ""

        if let finalURL = response.url, finalURL.host?.contains("accounts.google.com") == true {
            return finalURL
        }

        if let googleURL = extractGoogleOAuthURL(from: html) {
            return googleURL
        }

        throw MetrogasAuthError.googleStartFailed
    }

    func exportCookiesForWebKit() -> [HTTPCookie] {
        let hosts = [
            "asskova9q.accounts.ondemand.com",
            "portal.micuenta.metrogas.com.ar",
            "acceso.micuenta.metrogas.com.ar",
            "authn.br1.hana.ondemand.com",
            "br1.hana.ondemand.com",
            "accounts.google.com",
            "metrogas.com.ar"
        ]
        var cookies: [HTTPCookie] = []
        for host in hosts {
            if let url = URL(string: "https://\(host)/"),
               let list = cookieJar.cookies(for: url) {
                cookies.append(contentsOf: list)
            }
        }
        return cookies
    }

    /// Intenta leer el email de la sesión (útil tras Google OAuth).
    func resolveSignedInEmail() async -> String? {
        // 1) Cookies con email tipico de IdP
        if let cookies = cookieJar.cookies {
            for cookie in cookies {
                let value = cookie.value
                if let email = MetrogasJSONParser.firstEmail(in: value) {
                    return email.lowercased()
                }
                let name = cookie.name.lowercased()
                if (name.contains("email") || name.contains("mail") || name.contains("user")) ,
                   value.contains("@"),
                   let email = MetrogasJSONParser.firstEmail(in: value) {
                    return email.lowercased()
                }
            }
        }

        // 2) HTML del portal / login residual
        for url in [MetrogasURLs.portalMobile, MetrogasURLs.portalOV2, MetrogasURLs.acceso] {
            guard let html = try? await loadHTML(url) else { continue }
            if let email = MetrogasJSONParser.firstEmail(in: html) {
                return email.lowercased()
            }
        }
        return nil
    }

    private func loadHTML(_ url: URL) async throws -> String {
        let result = try await get(url)
        return String(data: result.data, encoding: .utf8) ?? ""
    }

    func clearCookies() {
        cookieJar.cookies?.forEach(cookieJar.deleteCookie)
    }

    // MARK: - Bootstrap SAML → IDS login HTML

    @discardableResult
    private func bootstrapLoginPage() async throws -> String {
        // 1) Portal mobile
        let portal = try await get(MetrogasURLs.portalMobile)
        var html = String(data: portal.data, encoding: .utf8) ?? ""

        // 2) Auto-submit chain (authn → IDS)
        for _ in 0..<4 {
            guard let action = firstFormAction(in: html) else { break }
            let fields = extractFormFields(from: html)
            let result = try await post(action, fields: fields)
            html = String(data: result.data, encoding: .utf8) ?? ""
            if htmlContainsUsernameField(html) {
                return html
            }
            if let url = result.url, MetrogasURLs.isMetrogasAuthHost(url.host ?? "") ,
               htmlContainsUsernameField(html) {
                return html
            }
        }

        if htmlContainsUsernameField(html) { return html }
        throw MetrogasAuthError.bootstrapFailed
    }

    private func currentLoginHTML() async throws -> String {
        // Re-get might not work; bootstrap already left us on login.
        // Keep last bootstrap by calling again if needed.
        try await bootstrapLoginPage()
    }

    private func submitLogin(html: String, email: String, password: String?) async throws -> String {
        guard let action = firstFormAction(in: html) ??
                URL(string: "https://asskova9q.accounts.ondemand.com/saml2/idp/sso/asskova9q.accounts.ondemand.com")
        else { throw MetrogasAuthError.unexpectedResponse }

        var fields = extractFormFields(from: html)
        fields["j_username"] = email
        if let password {
            fields["j_password"] = password
        }
        // Prefer POST for credential submission
        fields["method"] = fields["method"]?.isEmpty == false ? fields["method"]! : "POST"

        let result = try await post(action, fields: fields)
        var next = String(data: result.data, encoding: .utf8) ?? ""

        // Follow auto-submit forms after successful auth
        for _ in 0..<5 {
            if htmlContainsUsernameField(next) || htmlContainsPasswordField(next) || htmlContainsInvalidCredentials(next) {
                break
            }
            guard let nextAction = firstFormAction(in: next),
                  next.lowercased().contains("document.forms") || next.lowercased().contains("onload")
            else { break }
            let nextFields = extractFormFields(from: next)
            let followed = try await post(nextAction, fields: nextFields)
            next = String(data: followed.data, encoding: .utf8) ?? ""
        }
        return next
    }

    // MARK: - HTTP helpers

    private func get(_ url: URL) async throws -> (data: Data, url: URL?) {
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        return (data, response.url)
    }

    private func post(_ url: URL, fields: [String: String]) async throws -> (data: Data, url: URL?) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        request.httpBody = formBody(fields)
        let (data, response) = try await session.data(for: request)
        return (data, response.url)
    }

    private func formBody(_ fields: [String: String]) -> Data {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: ":#[]@!$&'()*+,;=")
        let pairs = fields.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(k)=\(v)"
        }
        return pairs.joined(separator: "&").data(using: .utf8) ?? Data()
    }

    // MARK: - HTML parsing

    private func firstFormAction(in html: String) -> URL? {
        guard let match = html.range(of: #"action="([^"]+)""#, options: .regularExpression) else { return nil }
        let snippet = String(html[match])
        guard let inner = snippet.split(separator: "\"").dropFirst().first else { return nil }
        let raw = String(inner)
        if raw.hasPrefix("http") { return URL(string: raw) }
        return URL(string: raw, relativeTo: URL(string: "https://asskova9q.accounts.ondemand.com")!)?.absoluteURL
    }

    private func extractFormFields(from html: String) -> [String: String] {
        var fields: [String: String] = [:]
        let pattern = #"<(?:input|INPUT)[^>]*name="([^"]+)"[^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [:] }
        let ns = html as NSString
        for match in regex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let tag = ns.substring(with: match.range)
            guard let name = capture(tag, #"name="([^"]+)""#) else { continue }
            let value = capture(tag, #"value="([^"]*)""#) ?? ""
            // Skip unchecked checkboxes without value handling; rememberme optional
            if tag.lowercased().contains("type=\"checkbox\"") && !tag.lowercased().contains("checked") {
                continue
            }
            fields[name] = value
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&#x2713;", with: "✓")
        }
        return fields
    }

    private func capture(_ text: String, _ pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges > 1 else { return nil }
        return ns.substring(with: match.range(at: 1))
    }

    private func htmlContainsUsernameField(_ html: String) -> Bool {
        html.contains("j_username")
    }

    private func htmlContainsPasswordField(_ html: String) -> Bool {
        html.contains("j_password")
    }

    private func htmlContainsInvalidCredentials(_ html: String) -> Bool {
        let lowered = html.lowercased()
        return lowered.contains("incorrect")
            || lowered.contains("invalid")
            || lowered.contains("authentication failed")
            || lowered.contains("no pudimos verificar")
            || lowered.contains("usuario o contraseña")
    }

    private func looksAuthenticated(html: String) -> Bool {
        let lowered = html.lowercased()
        return lowered.contains("ovmetrogas")
            || lowered.contains("logout")
            || lowered.contains("cerrar sesión")
            || (!htmlContainsUsernameField(html) && lowered.contains("portal"))
    }

    private func extractGoogleOAuthURL(from html: String) -> URL? {
        // location.replace("https://accounts.google.com/...")
        if let range = html.range(of: #"https://accounts\.google\.com/[^"']+"#, options: .regularExpression) {
            let raw = String(html[range])
                .replacingOccurrences(of: "&amp;", with: "&")
            return URL(string: raw)
        }
        return nil
    }

    private func hasMetrogasSessionCookie() -> Bool {
        let cookies = exportCookiesForWebKit()
        return cookies.contains { cookie in
            let name = cookie.name.lowercased()
            let domain = cookie.domain.lowercased()
            return domain.contains("metrogas")
                || domain.contains("ondemand.com")
                || name.contains("saml")
                || name.contains("session")
                || name.contains("ids")
        }
    }
}

import Foundation

struct MetrogasDataSnapshot: Sendable {
    var account: AccountProfile
    var invoices: [Invoice]
    var readings: [ConsumptionReading]
}

/// Sincroniza datos reales de Oficina Virtual:
/// 1) Establece sesión en portal + acceso
/// 2) Consulta OvServiceHub (M360) por HTTP
/// 3) Si hace falta, usa el bridge oculto del portal (captura XHR UI5)
actor MetrogasDataService {
    static let shared = MetrogasDataService()

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.timeoutIntervalForRequest = 35
        session = URLSession(configuration: config)
    }

    func fetchAccountData(loginHint: String?) async throws -> MetrogasDataSnapshot {
        var account = AccountProfile.empty
        if let loginHint, !loginHint.isEmpty {
            account.email = loginHint
            let local = loginHint.split(separator: "@").first.map(String.init) ?? loginHint
            account.holderName = local.replacingOccurrences(of: ".", with: " ").capitalized
        }

        // 1) Entrar a portal OV2 + acceso (renueva cookies SAML/portal).
        _ = try await establishSiteSession(MetrogasURLs.portalOV2)
        _ = try await establishSiteSession(MetrogasURLs.portalMobile)
        _ = try await establishSiteSession(MetrogasURLs.accesoOV2)
        _ = try await establishSiteSession(MetrogasURLs.acceso)

        // 2) Probar Service Hub con la sesión.
        var invoices: [Invoice] = []
        var readings: [ConsumptionReading] = []

        for url in MetrogasURLs.serviceHubCandidates {
            guard let (data, response) = try? await getJSON(url) else { continue }
            let http = response as? HTTPURLResponse
            let mime = http?.mimeType ?? ""
            let body = String(data: data, encoding: .utf8) ?? ""
            // Ignorar HTML de login/SAML.
            if mime.contains("html") || body.lowercased().contains("<html") {
                continue
            }
            guard http?.statusCode == 200 || http?.statusCode == 206 else { continue }

            let parsed = MetrogasJSONParser.parse(data)
            if !parsed.invoices.isEmpty {
                invoices = mergeInvoices(invoices, parsed.invoices)
            }
            if !parsed.readings.isEmpty {
                readings = mergeReadings(readings, parsed.readings)
            }
            account = MetrogasJSONParser.mergeAccount(account, parsed.account)
        }

        // 3) Bridge del portal: captura las llamadas reales que hace la UI5/OvServiceHub.
        if invoices.isEmpty {
            let bridgeSnapshot = try await PortalDataBridge.shared.sync(loginHint: loginHint, timeoutSeconds: 18)
            invoices = mergeInvoices(invoices, bridgeSnapshot.invoices)
            readings = mergeReadings(readings, bridgeSnapshot.readings)
            account = MetrogasJSONParser.mergeAccount(account, bridgeSnapshot.account)
        }

        if readings.isEmpty && !invoices.isEmpty {
            readings = MetrogasJSONParser.deriveReadings(from: invoices)
        }

        return MetrogasDataSnapshot(account: account, invoices: invoices, readings: readings)
    }

    // MARK: - Session / HTTP

    @discardableResult
    private func establishSiteSession(_ start: URL) async throws -> String {
        var html = try await loadHTML(start)
        for _ in 0..<5 {
            if looksAuthenticatedShell(html) { return html }
            if html.contains("j_username") || html.contains("j_password") { return html }
            guard let action = firstFormAction(in: html) else { break }
            let fields = extractFormFields(from: html)
            html = try await postHTML(action, fields: fields)
        }
        return html
    }

    private func loadHTML(_ url: URL) async throws -> String {
        let (data, _) = try await get(url)
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func postHTML(_ url: URL, fields: [String: String]) async throws -> String {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = formBody(fields)
        let (data, _) = try await session.data(for: request)
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func get(_ url: URL) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json,text/html,*/*", forHTTPHeaderField: "Accept")
        return try await session.data(for: request)
    }

    private func getJSON(_ url: URL) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json, application/vnd.api+json, */*", forHTTPHeaderField: "Accept")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        return try await session.data(for: request)
    }

    private static let userAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

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

    private func firstFormAction(in html: String) -> URL? {
        guard let match = html.range(of: #"action="([^"]+)""#, options: .regularExpression) else { return nil }
        let snippet = String(html[match])
        guard let inner = snippet.split(separator: "\"").dropFirst().first else { return nil }
        let raw = String(inner)
        if raw.hasPrefix("http") { return URL(string: raw) }
        return URL(string: raw, relativeTo: URL(string: "https://portal.micuenta.metrogas.com.ar")!)?.absoluteURL
    }

    private func extractFormFields(from html: String) -> [String: String] {
        var fields: [String: String] = [:]
        let pattern = #"<(?:input|INPUT)[^>]*name="([^"]+)"[^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [:] }
        let ns = html as NSString
        for match in regex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let tag = ns.substring(with: match.range)
            guard let nameRange = tag.range(of: #"name="([^"]+)""#, options: .regularExpression) else { continue }
            let nameBits = String(tag[nameRange]).split(separator: "\"")
            guard nameBits.count >= 2 else { continue }
            let name = String(nameBits[1])
            let value: String
            if let valueRange = tag.range(of: #"value="([^"]*)""#, options: .regularExpression) {
                let bits = String(tag[valueRange]).split(separator: "\"", omittingEmptySubsequences: false)
                value = bits.count >= 2 ? String(bits[1]) : ""
            } else {
                value = ""
            }
            fields[name] = value.replacingOccurrences(of: "&quot;", with: "\"")
        }
        return fields
    }

    private func looksAuthenticatedShell(_ html: String) -> Bool {
        let lowered = html.lowercased()
        return !lowered.contains("j_username")
            && (lowered.contains("sap-ui") || lowered.contains("flp") || lowered.contains("ovmetrogas") || lowered.contains("shell"))
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
}

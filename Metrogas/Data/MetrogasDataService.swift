import Foundation

struct MetrogasDataSnapshot: Sendable {
    var account: AccountProfile
    var invoices: [Invoice]
    var readings: [ConsumptionReading]
}

/// Descarga datos de la Oficina Virtual con la sesión autenticada (cookies),
/// sin mostrar WebView. Intenta endpoints SAP/portal y parsea JSON/HTML útil.
actor MetrogasDataService {
    static let shared = MetrogasDataService()

    private let session: URLSession
    private let cookieJar: HTTPCookieStorage

    private init() {
        let jar = HTTPCookieStorage.shared
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = jar
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.timeoutIntervalForRequest = 35
        cookieJar = jar
        session = URLSession(configuration: config)
    }

    func fetchAccountData(loginHint: String?) async throws -> MetrogasDataSnapshot {
        var account = AccountProfile.empty
        if let loginHint, !loginHint.isEmpty {
            account.email = loginHint
            let local = loginHint.split(separator: "@").first.map(String.init) ?? loginHint
            account.holderName = local.replacingOccurrences(of: ".", with: " ").capitalized
        }

        // Entrar al portal (sigue auto-submit SAML residual si la sesión está viva).
        var html = try await loadHTML(MetrogasURLs.portalMobile)
        for _ in 0..<4 {
            guard let action = firstFormAction(in: html) else { break }
            let fields = extractFormFields(from: html)
            html = try await postHTML(action, fields: fields)
            if looksLikePortalShell(html) { break }
        }

        // Perfil desde HTML si aparece.
        if let name = firstMatch(html, #"("displayName"|"fullName"|"nombre")\s*[:=]\s*"([^"]+)""#) {
            account.holderName = name
        }
        if let email = firstMatch(html, #"("email"|"mail")\s*[:=]\s*"([^"]+@[^"]+)""#) {
            account.email = email
        }
        if let customer = firstMatch(html, #"(N[°º]?\s*de\s*cliente|customerNumber|BusinessPartner)[^0-9]*([0-9]{6,})"#) {
            account.customerNumber = customer
        }

        // Descubrir URLs de servicio en el HTML/JS del portal.
        var serviceURLs = extractServiceURLs(from: html)
        serviceURLs.append(contentsOf: Self.candidateServiceURLs)

        var invoices: [Invoice] = []
        var readings: [ConsumptionReading] = []

        for url in uniqueURLs(serviceURLs) {
            guard let (data, response) = try? await get(url) else { continue }
            let type = (response as? HTTPURLResponse)?.mimeType ?? ""
            let body = String(data: data, encoding: .utf8) ?? ""

            if type.contains("json") || body.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{")
                || body.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("[") {
                let parsed = parseJSONPayload(data)
                if invoices.isEmpty { invoices = parsed.invoices }
                if readings.isEmpty { readings = parsed.readings }
                if account.customerNumber == "—" || account.customerNumber.isEmpty,
                   !parsed.account.customerNumber.isEmpty,
                   parsed.account.customerNumber != "—" {
                    account = mergeAccount(account, parsed.account)
                }
            } else if body.count > 200 {
                let parsedHTML = parseHTMLTables(body)
                if invoices.isEmpty { invoices = parsedHTML.invoices }
                if readings.isEmpty { readings = parsedHTML.readings }
            }

            if !invoices.isEmpty && !readings.isEmpty { break }
        }

        // Lecturas derivadas de facturas si no hubo serie de consumo.
        if readings.isEmpty && !invoices.isEmpty {
            readings = deriveReadings(from: invoices)
        }

        return MetrogasDataSnapshot(account: account, invoices: invoices, readings: readings)
    }

    // MARK: - Candidates

    private static let candidateServiceURLs: [URL] = [
        "https://portal.micuenta.metrogas.com.ar/sap/opu/odata/sap/ZOV_FACTURA_SRV/?$format=json",
        "https://portal.micuenta.metrogas.com.ar/sap/opu/odata/sap/ZOV_FACTURAS_SRV/?$format=json",
        "https://portal.micuenta.metrogas.com.ar/sap/opu/odata/sap/ZOV_CONSUMO_SRV/?$format=json",
        "https://portal.micuenta.metrogas.com.ar/sap/opu/odata/sap/ZOV_CUENTA_SRV/?$format=json",
        "https://portal.micuenta.metrogas.com.ar/sap/opu/odata/sap/ZMI_CUENTA_SRV/?$format=json",
        "https://portal.micuenta.metrogas.com.ar/sap/opu/odata/IWFND/CATALOGSERVICE;v=2/ServiceCollection?$format=json"
    ].compactMap(URL.init(string:))

    // MARK: - HTTP

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

    // MARK: - Discovery helpers

    private func extractServiceURLs(from html: String) -> [URL] {
        var found: [URL] = []
        let patterns = [
            #"https://[^"'\s]+/sap/opu/odata/[^"'\s]+"#,
            #"/sap/opu/odata/[^"'\s]+"#,
            #"https://[^"'\s]+\.json"#,
            #""uri"\s*:\s*"([^"]+)""#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let ns = html as NSString
            for match in regex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
                let raw: String
                if match.numberOfRanges > 1 {
                    raw = ns.substring(with: match.range(at: 1))
                } else {
                    raw = ns.substring(with: match.range)
                }
                let cleaned = raw
                    .replacingOccurrences(of: "&amp;", with: "&")
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                if cleaned.hasPrefix("http"), let url = URL(string: cleaned) {
                    found.append(url)
                } else if cleaned.hasPrefix("/"),
                          let url = URL(string: cleaned, relativeTo: URL(string: "https://portal.micuenta.metrogas.com.ar")!)?.absoluteURL {
                    found.append(url)
                }
            }
        }
        return found
    }

    private func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { seen.insert($0.absoluteString).inserted }
    }

    private func looksLikePortalShell(_ html: String) -> Bool {
        let lowered = html.lowercased()
        return lowered.contains("sap-ui")
            || lowered.contains("flp")
            || lowered.contains("ovmetrogas")
            || lowered.contains("shell")
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
            guard let name = capture(tag, #"name="([^"]+)""#) else { continue }
            let value = capture(tag, #"value="([^"]*)""#) ?? ""
            fields[name] = value
                .replacingOccurrences(of: "&quot;", with: "\"")
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

    private func firstMatch(_ text: String, _ pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let idx = match.numberOfRanges > 2 ? 2 : 1
        guard match.numberOfRanges > idx else { return nil }
        return ns.substring(with: match.range(at: idx))
    }

    // MARK: - JSON parsing (flexible)

    private func parseJSONPayload(_ data: Data) -> MetrogasDataSnapshot {
        var account = AccountProfile.empty
        var invoices: [Invoice] = []
        var readings: [ConsumptionReading] = []

        guard let root = try? JSONSerialization.jsonObject(with: data) else {
            return MetrogasDataSnapshot(account: account, invoices: [], readings: [])
        }

        let arrays = collectArrays(from: root)
        for array in arrays {
            let asInvoices = array.compactMap { parseInvoice(from: $0) }
            if asInvoices.count > invoices.count { invoices = asInvoices }

            let asReadings = array.compactMap { parseReading(from: $0) }
            if asReadings.count > readings.count { readings = asReadings }

            for item in array {
                if let dict = item as? [String: Any] {
                    account = mergeAccount(account, parseAccount(from: dict))
                }
            }
        }

        if let dict = root as? [String: Any] {
            account = mergeAccount(account, parseAccount(from: dict))
            if let d = dict["d"] as? [String: Any] {
                account = mergeAccount(account, parseAccount(from: d))
            }
        }

        return MetrogasDataSnapshot(account: account, invoices: invoices, readings: readings)
    }

    private func collectArrays(from node: Any, depth: Int = 0) -> [[Any]] {
        guard depth < 6 else { return [] }
        var result: [[Any]] = []
        if let array = node as? [Any] {
            result.append(array)
            for item in array {
                result.append(contentsOf: collectArrays(from: item, depth: depth + 1))
            }
        } else if let dict = node as? [String: Any] {
            for value in dict.values {
                result.append(contentsOf: collectArrays(from: value, depth: depth + 1))
            }
        }
        return result
    }

    private func parseInvoice(from node: Any) -> Invoice? {
        guard let dict = node as? [String: Any] else { return nil }
        let number = stringValue(dict, keys: ["number", "InvoiceNumber", "NroFactura", "Factura", "DocNumber", "Belnr", "id", "ID"])
        let amount = decimalValue(dict, keys: ["amountARS", "Amount", "Importe", "Total", "GrossAmount", "OpenAmount", "Dmbtr"])
        let due = dateValue(dict, keys: ["dueDate", "DueDate", "Vencimiento", "FechaVto", "NetDueDate"])
        let issued = dateValue(dict, keys: ["issuedDate", "IssueDate", "FechaEmision", "BillingDate"]) ?? due
        let start = dateValue(dict, keys: ["periodStart", "PeriodStart", "FechaDesde"]) ?? issued ?? Date()
        let end = dateValue(dict, keys: ["periodEnd", "PeriodEnd", "FechaHasta"]) ?? start
        let m3 = doubleValue(dict, keys: ["consumptionM3", "Consumo", "Consumption", "M3", "Quantity"]) ?? 0
        let statusRaw = stringValue(dict, keys: ["status", "Status", "Estado", "ClearingStatus"])?.lowercased() ?? ""

        guard let number, let amount, let dueDate = due ?? issued else { return nil }

        let status: InvoiceStatus
        if statusRaw.contains("pag") || statusRaw.contains("paid") || statusRaw.contains("clear") {
            status = .paid
        } else if dueDate < Calendar.current.startOfDay(for: Date()) {
            status = .overdue
        } else if statusRaw.contains("venc") || statusRaw.contains("over") {
            status = .overdue
        } else {
            status = .pending
        }

        return Invoice(
            id: number,
            number: number,
            periodStart: start,
            periodEnd: end,
            dueDate: dueDate,
            issuedDate: issued ?? dueDate,
            amountARS: amount,
            status: status,
            consumptionM3: m3,
            supplyPoint: stringValue(dict, keys: ["supplyPoint", "Address", "Direccion"]) ?? "MetroGAS",
            notes: stringValue(dict, keys: ["notes", "Notes", "Observaciones"]) ?? "",
            breakdown: InvoiceBreakdown(
                cargoFijo: decimalValue(dict, keys: ["cargoFijo", "FixedCharge"]) ?? 0,
                cargoVariable: decimalValue(dict, keys: ["cargoVariable", "VariableCharge"]) ?? amount,
                impuestos: decimalValue(dict, keys: ["impuestos", "Tax"]) ?? 0,
                otros: decimalValue(dict, keys: ["otros", "Other"]) ?? 0
            )
        )
    }

    private func parseReading(from node: Any) -> ConsumptionReading? {
        guard let dict = node as? [String: Any] else { return nil }
        let m3 = doubleValue(dict, keys: ["cubicMeters", "Consumo", "Consumption", "M3", "Quantity", "Volume"])
        let start = dateValue(dict, keys: ["periodStart", "PeriodStart", "FechaDesde", "Month"])
        guard let m3, let start else { return nil }
        let end = dateValue(dict, keys: ["periodEnd", "PeriodEnd", "FechaHasta"])
            ?? Calendar.current.date(byAdding: DateComponents(month: 1, day: -1), to: start)
            ?? start
        let days = Double(Calendar.current.dateComponents([.day], from: start, to: end).day ?? 30) + 1
        let delta = doubleValue(dict, keys: ["comparedToPreviousPercent", "Delta", "Variacion"]) ?? 0
        return ConsumptionReading(
            id: UUID(),
            periodStart: start,
            periodEnd: end,
            cubicMeters: m3,
            averageDaily: m3 / max(days, 1),
            comparedToPreviousPercent: delta
        )
    }

    private func parseAccount(from dict: [String: Any]) -> AccountProfile {
        AccountProfile(
            holderName: stringValue(dict, keys: ["holderName", "Name", "Nombre", "CustomerName", "BpName"]) ?? "",
            customerNumber: stringValue(dict, keys: ["customerNumber", "Customer", "NroCliente", "BusinessPartner", "Partner"]) ?? "—",
            supplyAddress: stringValue(dict, keys: ["supplyAddress", "Address", "Direccion", "Street"]) ?? "—",
            locality: stringValue(dict, keys: ["locality", "City", "Localidad"]) ?? "—",
            postalCode: stringValue(dict, keys: ["postalCode", "PostalCode", "CP"]) ?? "—",
            email: stringValue(dict, keys: ["email", "Email", "Mail"]) ?? "",
            phone: stringValue(dict, keys: ["phone", "Phone", "Telefono"]) ?? "—",
            meterNumber: stringValue(dict, keys: ["meterNumber", "Meter", "Medidor", "SerialNumber"]) ?? "—",
            tariffCategory: stringValue(dict, keys: ["tariffCategory", "Tariff", "Categoria", "RateCategory"]) ?? "—"
        )
    }

    private func mergeAccount(_ base: AccountProfile, _ incoming: AccountProfile) -> AccountProfile {
        AccountProfile(
            holderName: prefer(incoming.holderName, base.holderName),
            customerNumber: prefer(incoming.customerNumber, base.customerNumber),
            supplyAddress: prefer(incoming.supplyAddress, base.supplyAddress),
            locality: prefer(incoming.locality, base.locality),
            postalCode: prefer(incoming.postalCode, base.postalCode),
            email: prefer(incoming.email, base.email),
            phone: prefer(incoming.phone, base.phone),
            meterNumber: prefer(incoming.meterNumber, base.meterNumber),
            tariffCategory: prefer(incoming.tariffCategory, base.tariffCategory)
        )
    }

    private func prefer(_ a: String, _ b: String) -> String {
        let bad: Set<String> = ["", "—", "-"]
        if !bad.contains(a) { return a }
        return b
    }

    // MARK: - HTML table fallback

    private func parseHTMLTables(_ html: String) -> MetrogasDataSnapshot {
        // Heurística mínima: montos $ y fechas dd/MM/yyyy en la misma zona.
        var invoices: [Invoice] = []
        let amountPattern = #"\$\s*([0-9]{1,3}(?:\.[0-9]{3})*(?:,[0-9]{2})|[0-9]+(?:,[0-9]{2})?)"#
        let datePattern = #"(\d{1,2}/\d{1,2}/\d{4})"#
        guard let amountRegex = try? NSRegularExpression(pattern: amountPattern),
              let dateRegex = try? NSRegularExpression(pattern: datePattern) else {
            return MetrogasDataSnapshot(account: .empty, invoices: [], readings: [])
        }

        let ns = html as NSString
        let amounts = amountRegex.matches(in: html, range: NSRange(location: 0, length: ns.length))
        let dates = dateRegex.matches(in: html, range: NSRange(location: 0, length: ns.length))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_AR")
        formatter.dateFormat = "dd/MM/yyyy"

        let limit = min(amounts.count, dates.count, 24)
        for i in 0..<limit {
            let amountText = ns.substring(with: amounts[i].range(at: 1))
                .replacingOccurrences(of: ".", with: "")
                .replacingOccurrences(of: ",", with: ".")
            let dateText = ns.substring(with: dates[i].range(at: 1))
            guard let amount = Decimal(string: amountText),
                  let due = formatter.date(from: dateText) else { continue }
            let id = "OV-\(i + 1)-\(dateText.replacingOccurrences(of: "/", with: ""))"
            let status: InvoiceStatus = due < Date() ? .overdue : .pending
            invoices.append(
                Invoice(
                    id: id,
                    number: id,
                    periodStart: Calendar.current.date(byAdding: .month, value: -1, to: due) ?? due,
                    periodEnd: due,
                    dueDate: due,
                    issuedDate: due,
                    amountARS: amount,
                    status: status,
                    consumptionM3: 0,
                    supplyPoint: "MetroGAS",
                    notes: "",
                    breakdown: InvoiceBreakdown(cargoFijo: 0, cargoVariable: amount, impuestos: 0, otros: 0)
                )
            )
        }

        return MetrogasDataSnapshot(account: .empty, invoices: invoices, readings: deriveReadings(from: invoices))
    }

    private func deriveReadings(from invoices: [Invoice]) -> [ConsumptionReading] {
        let withM3 = invoices.filter { $0.consumptionM3 > 0 }.sorted { $0.periodStart < $1.periodStart }
        var previous: Double?
        return withM3.map { invoice in
            let delta: Double
            if let previous {
                delta = previous == 0 ? 0 : ((invoice.consumptionM3 - previous) / previous) * 100
            } else {
                delta = 0
            }
            previous = invoice.consumptionM3
            let days = Double(Calendar.current.dateComponents([.day], from: invoice.periodStart, to: invoice.periodEnd).day ?? 30) + 1
            return ConsumptionReading(
                id: UUID(),
                periodStart: invoice.periodStart,
                periodEnd: invoice.periodEnd,
                cubicMeters: invoice.consumptionM3,
                averageDaily: invoice.consumptionM3 / max(days, 1),
                comparedToPreviousPercent: delta
            )
        }
    }

    // MARK: - Value helpers

    private func stringValue(_ dict: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dict[key] as? String, !value.isEmpty { return value }
            if let value = dict[key] as? NSNumber { return value.stringValue }
            // case-insensitive
            if let pair = dict.first(where: { $0.key.lowercased() == key.lowercased() }) {
                if let value = pair.value as? String, !value.isEmpty { return value }
                if let value = pair.value as? NSNumber { return value.stringValue }
            }
        }
        return nil
    }

    private func decimalValue(_ dict: [String: Any], keys: [String]) -> Decimal? {
        for key in keys {
            if let n = dict[key] as? NSNumber { return n.decimalValue }
            if let s = dict[key] as? String {
                let normalized = s
                    .replacingOccurrences(of: "$", with: "")
                    .replacingOccurrences(of: " ", with: "")
                    .replacingOccurrences(of: ".", with: "")
                    .replacingOccurrences(of: ",", with: ".")
                if let d = Decimal(string: normalized) { return d }
            }
            if let pair = dict.first(where: { $0.key.lowercased() == key.lowercased() }) {
                if let n = pair.value as? NSNumber { return n.decimalValue }
            }
        }
        return nil
    }

    private func doubleValue(_ dict: [String: Any], keys: [String]) -> Double? {
        if let d = decimalValue(dict, keys: keys) {
            return NSDecimalNumber(decimal: d).doubleValue
        }
        return nil
    }

    private func dateValue(_ dict: [String: Any], keys: [String]) -> Date? {
        let formatters: [DateFormatter] = {
            let formats = ["yyyy-MM-dd", "dd/MM/yyyy", "yyyyMMdd", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ssZ"]
            return formats.map { format in
                let f = DateFormatter()
                f.locale = Locale(identifier: "en_US_POSIX")
                f.dateFormat = format
                return f
            }
        }()

        for key in keys {
            let raw: Any? = dict[key] ?? dict.first(where: { $0.key.lowercased() == key.lowercased() })?.value
            if let date = raw as? Date { return date }
            if let s = raw as? String {
                // OData /Date(1234567890)/
                if let ms = capture(s, #"/Date\((-?\d+)\)/"#), let interval = Double(ms) {
                    return Date(timeIntervalSince1970: interval / 1000)
                }
                for formatter in formatters {
                    if let date = formatter.date(from: s) { return date }
                }
            }
            if let n = raw as? NSNumber {
                let value = n.doubleValue
                if value > 1_000_000_000_000 {
                    return Date(timeIntervalSince1970: value / 1000)
                }
                if value > 1_000_000_000 {
                    return Date(timeIntervalSince1970: value)
                }
            }
        }
        return nil
    }
}

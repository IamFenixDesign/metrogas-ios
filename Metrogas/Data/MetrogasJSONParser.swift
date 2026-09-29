import Foundation

enum MetrogasJSONParser {
    static func parse(_ data: Data) -> MetrogasDataSnapshot {
        var account = AccountProfile.empty
        var invoices: [Invoice] = []
        var readings: [ConsumptionReading] = []

        guard let root = try? JSONSerialization.jsonObject(with: data) else {
            return MetrogasDataSnapshot(account: account, invoices: [], readings: [])
        }

        for array in collectArrays(from: root) {
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
            // M360 envelopes comunes
            for key in ["data", "result", "results", "payload", "response", "body"] {
                if let nested = dict[key] {
                    let nestedData = (try? JSONSerialization.data(withJSONObject: nested)).flatMap { parse($0) }
                    if let nestedData {
                        if invoices.isEmpty { invoices = nestedData.invoices }
                        if readings.isEmpty { readings = nestedData.readings }
                        account = mergeAccount(account, nestedData.account)
                    }
                }
            }
        }

        return MetrogasDataSnapshot(account: account, invoices: invoices, readings: readings)
    }

    static func parseDOMText(_ text: String) -> MetrogasDataSnapshot {
        var invoices: [Invoice] = []
        var account = AccountProfile.empty

        if let customer = firstMatch(text, #"(?:N[°º]?\s*(?:de\s*)?cliente|Cliente)\s*[:#]?\s*([0-9]{6,})"#) {
            account.customerNumber = customer
        }
        if let meter = firstMatch(text, #"(?:Medidor|N[°º]?\s*medidor)\s*[:#]?\s*([A-Za-z0-9-]{4,})"#) {
            account.meterNumber = meter
        }

        let amountPattern = #"\$\s*([0-9]{1,3}(?:\.[0-9]{3})*(?:,[0-9]{2})|[0-9]+(?:,[0-9]{2})?)"#
        let datePattern = #"(\d{1,2}/\d{1,2}/\d{4})"#
        guard let amountRegex = try? NSRegularExpression(pattern: amountPattern),
              let dateRegex = try? NSRegularExpression(pattern: datePattern) else {
            return MetrogasDataSnapshot(account: account, invoices: [], readings: [])
        }

        let ns = text as NSString
        let amounts = amountRegex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        let dates = dateRegex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_AR")
        formatter.dateFormat = "dd/MM/yyyy"

        let limit = min(amounts.count, max(dates.count, 1), 30)
        for i in 0..<min(amounts.count, 30) {
            let amountText = ns.substring(with: amounts[i].range(at: 1))
                .replacingOccurrences(of: ".", with: "")
                .replacingOccurrences(of: ",", with: ".")
            guard let amount = Decimal(string: amountText) else { continue }
            let due: Date
            if i < dates.count, let d = formatter.date(from: ns.substring(with: dates[i].range(at: 1))) {
                due = d
            } else {
                due = Calendar.current.date(byAdding: .day, value: 10, to: Date()) ?? Date()
            }
            let id = "OV-\(i + 1)-\(Int(due.timeIntervalSince1970))"
            let status: InvoiceStatus = due < Date() ? .overdue : .pending
            // Evitar montos absurdos de UI chrome
            let asDouble = NSDecimalNumber(decimal: amount).doubleValue
            guard asDouble > 100, asDouble < 50_000_000 else { continue }
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
            if invoices.count >= limit { break }
        }

        return MetrogasDataSnapshot(account: account, invoices: invoices, readings: deriveReadings(from: invoices))
    }

    static func deriveReadings(from invoices: [Invoice]) -> [ConsumptionReading] {
        let withM3 = invoices.filter { $0.consumptionM3 > 0 }.sorted { $0.periodStart < $1.periodStart }
        var previous: Double?
        return withM3.map { invoice in
            let delta: Double
            if let previous, previous != 0 {
                delta = ((invoice.consumptionM3 - previous) / previous) * 100
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

    static func mergeAccount(_ base: AccountProfile, _ incoming: AccountProfile) -> AccountProfile {
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

    // MARK: - Internals

    private static func prefer(_ a: String, _ b: String) -> String {
        let bad: Set<String> = ["", "—", "-"]
        if !bad.contains(a) { return a }
        return b
    }

    private static func collectArrays(from node: Any, depth: Int = 0) -> [[Any]] {
        guard depth < 8 else { return [] }
        var result: [[Any]] = []
        if let array = node as? [Any] {
            result.append(array)
            for item in array { result.append(contentsOf: collectArrays(from: item, depth: depth + 1)) }
        } else if let dict = node as? [String: Any] {
            for value in dict.values { result.append(contentsOf: collectArrays(from: value, depth: depth + 1)) }
        }
        return result
    }

    private static func parseInvoice(from node: Any) -> Invoice? {
        guard let dict = flatten(node) else { return nil }
        let number = stringValue(dict, keys: [
            "number", "InvoiceNumber", "NroFactura", "Factura", "DocNumber", "Belnr",
            "id", "ID", "invoiceId", "billNumber", "nroComprobante", "PrintDoc"
        ])
        let amount = decimalValue(dict, keys: [
            "amountARS", "Amount", "Importe", "Total", "GrossAmount", "OpenAmount",
            "Dmbtr", "totalAmount", "amount", "saldo", "balance", "openBalance"
        ])
        let due = dateValue(dict, keys: [
            "dueDate", "DueDate", "Vencimiento", "FechaVto", "NetDueDate", "due", "fechaVencimiento"
        ])
        let issued = dateValue(dict, keys: [
            "issuedDate", "IssueDate", "FechaEmision", "BillingDate", "fechaEmision"
        ]) ?? due
        let start = dateValue(dict, keys: ["periodStart", "PeriodStart", "FechaDesde", "fromDate"]) ?? issued ?? Date()
        let end = dateValue(dict, keys: ["periodEnd", "PeriodEnd", "FechaHasta", "toDate"]) ?? start
        let m3 = doubleValue(dict, keys: ["consumptionM3", "Consumo", "Consumption", "M3", "Quantity", "volumen"]) ?? 0
        let statusRaw = stringValue(dict, keys: ["status", "Status", "Estado", "ClearingStatus", "state"])?.lowercased() ?? ""

        guard let amount, let dueDate = due ?? issued else { return nil }
        let id = number ?? "F-\(Int(dueDate.timeIntervalSince1970))-\(amount)"

        let status: InvoiceStatus
        if statusRaw.contains("pag") || statusRaw.contains("paid") || statusRaw.contains("clear") || statusRaw.contains("saldad") {
            status = .paid
        } else if dueDate < Calendar.current.startOfDay(for: Date()) {
            status = .overdue
        } else if statusRaw.contains("venc") || statusRaw.contains("over") {
            status = .overdue
        } else {
            status = .pending
        }

        return Invoice(
            id: id,
            number: number ?? id,
            periodStart: start,
            periodEnd: end,
            dueDate: dueDate,
            issuedDate: issued ?? dueDate,
            amountARS: amount,
            status: status,
            consumptionM3: m3,
            supplyPoint: stringValue(dict, keys: ["supplyPoint", "Address", "Direccion", "address"]) ?? "MetroGAS",
            notes: stringValue(dict, keys: ["notes", "Notes", "Observaciones"]) ?? "",
            breakdown: InvoiceBreakdown(
                cargoFijo: decimalValue(dict, keys: ["cargoFijo", "FixedCharge"]) ?? 0,
                cargoVariable: decimalValue(dict, keys: ["cargoVariable", "VariableCharge"]) ?? amount,
                impuestos: decimalValue(dict, keys: ["impuestos", "Tax"]) ?? 0,
                otros: decimalValue(dict, keys: ["otros", "Other"]) ?? 0
            )
        )
    }

    private static func parseReading(from node: Any) -> ConsumptionReading? {
        guard let dict = flatten(node) else { return nil }
        let m3 = doubleValue(dict, keys: ["cubicMeters", "Consumo", "Consumption", "M3", "Quantity", "Volume", "volumen", "usage"])
        let start = dateValue(dict, keys: ["periodStart", "PeriodStart", "FechaDesde", "Month", "fromDate", "period"])
        guard let m3, let start else { return nil }
        let end = dateValue(dict, keys: ["periodEnd", "PeriodEnd", "FechaHasta", "toDate"])
            ?? Calendar.current.date(byAdding: DateComponents(month: 1, day: -1), to: start)
            ?? start
        let days = Double(Calendar.current.dateComponents([.day], from: start, to: end).day ?? 30) + 1
        let delta = doubleValue(dict, keys: ["comparedToPreviousPercent", "Delta", "Variacion", "variation"]) ?? 0
        return ConsumptionReading(
            id: UUID(),
            periodStart: start,
            periodEnd: end,
            cubicMeters: m3,
            averageDaily: m3 / max(days, 1),
            comparedToPreviousPercent: delta
        )
    }

    private static func parseAccount(from dict: [String: Any]) -> AccountProfile {
        let flat = flatten(dict) ?? dict
        return AccountProfile(
            holderName: stringValue(flat, keys: ["holderName", "Name", "Nombre", "CustomerName", "BpName", "fullName", "displayName", "firstname", "firstName"]) ?? "",
            customerNumber: stringValue(flat, keys: ["customerNumber", "Customer", "NroCliente", "BusinessPartner", "Partner", "bPartner", "bp", "accountNumber", "nroCuenta"]) ?? "—",
            supplyAddress: stringValue(flat, keys: ["supplyAddress", "Address", "Direccion", "Street", "street", "address"]) ?? "—",
            locality: stringValue(flat, keys: ["locality", "City", "Localidad", "city"]) ?? "—",
            postalCode: stringValue(flat, keys: ["postalCode", "PostalCode", "CP", "zip"]) ?? "—",
            email: stringValue(flat, keys: ["email", "Email", "Mail"]) ?? "",
            phone: stringValue(flat, keys: ["phone", "Phone", "Telefono", "telNumber"]) ?? "—",
            meterNumber: stringValue(flat, keys: ["meterNumber", "Meter", "Medidor", "SerialNumber", "anlage", "device"]) ?? "—",
            tariffCategory: stringValue(flat, keys: ["tariffCategory", "Tariff", "Categoria", "RateCategory", "tarifa"]) ?? "—"
        )
    }

    private static func flatten(_ node: Any) -> [String: Any]? {
        guard let dict = node as? [String: Any] else { return nil }
        var out = dict
        // OData V2 often wraps properties
        if let results = dict["results"] as? [String: Any] {
            out.merge(results) { _, new in new }
        }
        return out
    }

    private static func stringValue(_ dict: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dict[key] as? String, !value.isEmpty { return value }
            if let value = dict[key] as? NSNumber { return value.stringValue }
            if let pair = dict.first(where: { $0.key.lowercased() == key.lowercased() }) {
                if let value = pair.value as? String, !value.isEmpty { return value }
                if let value = pair.value as? NSNumber { return value.stringValue }
            }
        }
        // firstname + lastname
        if keys.contains("firstname") || keys.contains("firstName") {
            let first = (dict["firstname"] as? String) ?? (dict["firstName"] as? String) ?? ""
            let last = (dict["lastname"] as? String) ?? (dict["lastName"] as? String) ?? ""
            let full = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
            if !full.isEmpty { return full }
        }
        return nil
    }

    private static func decimalValue(_ dict: [String: Any], keys: [String]) -> Decimal? {
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
            if let pair = dict.first(where: { $0.key.lowercased() == key.lowercased() }),
               let n = pair.value as? NSNumber {
                return n.decimalValue
            }
        }
        return nil
    }

    private static func doubleValue(_ dict: [String: Any], keys: [String]) -> Double? {
        if let d = decimalValue(dict, keys: keys) {
            return NSDecimalNumber(decimal: d).doubleValue
        }
        return nil
    }

    private static func dateValue(_ dict: [String: Any], keys: [String]) -> Date? {
        let formats = ["yyyy-MM-dd", "dd/MM/yyyy", "yyyyMMdd", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ssZ"]
        let formatters: [DateFormatter] = formats.map {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = $0
            return f
        }

        for key in keys {
            let raw: Any? = dict[key] ?? dict.first(where: { $0.key.lowercased() == key.lowercased() })?.value
            if let date = raw as? Date { return date }
            if let s = raw as? String {
                if let ms = firstMatch(s, #"/Date\((-?\d+)\)/"#), let interval = Double(ms) {
                    return Date(timeIntervalSince1970: interval / 1000)
                }
                for formatter in formatters {
                    if let date = formatter.date(from: s) { return date }
                }
            }
            if let n = raw as? NSNumber {
                let value = n.doubleValue
                if value > 1_000_000_000_000 { return Date(timeIntervalSince1970: value / 1000) }
                if value > 1_000_000_000 { return Date(timeIntervalSince1970: value) }
            }
        }
        return nil
    }

    private static func firstMatch(_ text: String, _ pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges > 1 else { return nil }
        return ns.substring(with: match.range(at: 1))
    }
}

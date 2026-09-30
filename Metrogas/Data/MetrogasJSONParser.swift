import Foundation

enum MetrogasJSONParser {
    static func parse(_ data: Data) -> MetrogasDataSnapshot {
        var account = AccountProfile.empty
        var invoices: [Invoice] = []
        var readings: [ConsumptionReading] = []

        guard let root = try? JSONSerialization.jsonObject(with: data) else {
            return MetrogasDataSnapshot(account: account, invoices: [], readings: [])
        }

        // Respuestas M360 conocidas (saldos.micuenta).
        if let dict = root as? [String: Any] {
            let m360 = parseM360Envelope(dict)
            invoices = m360.invoices
            readings = m360.readings
            account = mergeAccount(account, m360.account)
        }

        // Si el JSON trae un N° de cliente asociado (cuenta Google/MetroGAS), capturarlo.
        if MetrogasURLs.normalizedCustomerNumber(account.customerNumber) == nil,
           let found = firstCustomerNumber(inJSON: root) {
            account.customerNumber = found
        }

        if invoices.isEmpty || readings.isEmpty {
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
        }

        if let dict = root as? [String: Any] {
            account = mergeAccount(account, parseAccount(from: dict))
        }

        return MetrogasDataSnapshot(account: account, invoices: invoices, readings: readings)
    }

    /// Parsea las formas reales de OvServiceHub M360.
    static func parseM360Envelope(_ dict: [String: Any]) -> MetrogasDataSnapshot {
        var account = AccountProfile.empty
        var history: [Invoice] = []
        var debts: [Invoice] = []
        var readings: [ConsumptionReading] = []

        // publicinvoice/listR2 → historial completo (pagadas + pendientes).
        if let isu = dict["ISU"] as? [[String: Any]] {
            history.append(contentsOf: isu.compactMap { parseM360Invoice($0, source: .history) })
        }
        if let ipost = dict["IPOST"] as? [[String: Any]] {
            for row in ipost {
                if let inv = parseM360IPost(row) { history.append(inv) }
            }
        }

        // publicbilling/r2 → info + deudas (solo adeudadas).
        if let info = dict["info"] as? [String: Any] {
            account = mergeAccount(account, parseM360Info(info))
        }
        if let deudas = dict["deudas"] as? [String: Any],
           let items = deudas["items"] as? [[String: Any]] {
            for item in items {
                if let inv = parseM360DebtItem(item) { debts.append(inv) }
            }
        }

        // publicinvoice/consumption/{id} → { PTE_CONSUMOS: [...] }
        if let consumos = dict["PTE_CONSUMOS"] as? [[String: Any]] {
            readings = consumos.compactMap { parseM360Consumption($0) }
        }

        // Base = historial (incluye pagadas); las deudas solo actualizan pendientes.
        var map: [String: Invoice] = [:]
        for inv in history { map[inv.id] = inv }
        for debt in debts {
            if var existing = map[debt.id] {
                existing.status = debt.status
                existing.amountARS = debt.amountARS
                map[debt.id] = existing
            } else {
                map[debt.id] = debt
            }
        }

        let invoices = Array(map.values).sorted { $0.dueDate > $1.dueDate }
        return MetrogasDataSnapshot(account: account, invoices: invoices, readings: readings)
    }

    static func parseDOMText(_ text: String) -> MetrogasDataSnapshot {
        var account = AccountProfile.empty
        if let customer = firstCustomerNumber(in: text) {
            account.customerNumber = customer
        }
        if let email = firstEmail(in: text) {
            account.email = email
        }
        if let meter = firstMatch(text, #"(?:Medidor|N[°º]?\s*medidor)\s*[:#]?\s*([A-Za-z0-9-]{4,})"#) {
            account.meterNumber = meter
        }
        if let name = firstMatch(text, #"(?:Titular|Nombre)\s*[:#]?\s*([A-Za-zÁÉÍÓÚÜÑáéíóúüñ][A-Za-zÁÉÍÓÚÜÑáéíóúüñ\s.'-]{3,60})"#) {
            account.holderName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return MetrogasDataSnapshot(account: account, invoices: [], readings: [])
    }

    static func firstCustomerNumber(in text: String) -> String? {
        if let labeled = firstMatch(text, #"(?:N[°º]?\s*(?:de\s*)?cliente|Cliente|Account|Contrato)\s*[:#]?\s*([0-9]{11})"#),
           let normalized = MetrogasURLs.normalizedCustomerNumber(labeled) {
            return normalized
        }
        // Fallback: primer bloque de 11 dígitos (evita teléfonos de 10).
        guard let raw = firstMatch(text, #"\b([0-9]{11})\b"#) else { return nil }
        return MetrogasURLs.normalizedCustomerNumber(raw)
    }

    static func firstEmail(in text: String) -> String? {
        firstMatch(text, #"([A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,})"#)
    }

    /// Busca un N° de cliente de 11 dígitos en cualquier JSON (portal / M360).
    static func firstCustomerNumber(inJSON node: Any, depth: Int = 0) -> String? {
        guard depth < 10 else { return nil }

        if let dict = node as? [String: Any] {
            let priorityKeys = [
                "accountId", "custNumber", "customerNumber", "NroCliente", "nroCliente",
                "NRO_CLIENTE", "ctaContrato", "CUENTA", "VKONT", "contrato", "Contrato",
                "PVE_NRO_CLIENTE", "account", "cuenta"
            ]
            for key in priorityKeys {
                if let raw = stringValue(dict, keys: [key]),
                   let normalized = MetrogasURLs.normalizedCustomerNumber(raw) {
                    return normalized
                }
                // A veces CUENTA viene con más dígitos y el cliente son los últimos 11.
                if let raw = stringValue(dict, keys: [key]) {
                    let digits = raw.filter(\.isNumber)
                    if digits.count > 11,
                       let normalized = MetrogasURLs.normalizedCustomerNumber(String(digits.suffix(11))) {
                        return normalized
                    }
                }
            }
            for value in dict.values {
                if let found = firstCustomerNumber(inJSON: value, depth: depth + 1) {
                    return found
                }
            }
        } else if let array = node as? [Any] {
            for item in array {
                if let found = firstCustomerNumber(inJSON: item, depth: depth + 1) {
                    return found
                }
            }
        } else if let s = node as? String {
            return MetrogasURLs.normalizedCustomerNumber(s) ?? firstCustomerNumber(in: s)
        } else if let n = node as? NSNumber {
            return MetrogasURLs.normalizedCustomerNumber(n.stringValue)
        }
        return nil
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

    // MARK: - M360 field mappers

    private enum InvoiceSource {
        case history
        case debt
    }

    private static func parseM360Invoice(_ dict: [String: Any], source: InvoiceSource = .history) -> Invoice? {
        let number = stringValue(dict, keys: ["NUMERO_FACTURA", "NRO_FACTURA", "nro_factura", "codigo"])
        let total = decimalValue(dict, keys: ["MONTO_TOTAL", "TOTALAPAGAR", "importe", "IMPORTE"])
        let pending = decimalValue(dict, keys: ["IMPORTE_PENDIENTE", "importe"])
        let amount = total ?? pending
        let due = dateValue(dict, keys: ["FECHA_VENCIMIENTO", "vencimiento", "FECHA_VTO"])
        let issued = dateValue(dict, keys: ["FECHA_FACTURA", "FECHA_EMISION"]) ?? due
        let paidAt = dateValue(dict, keys: ["FECHA_PAGO", "fecha_pago", "FECHA_PAGADO"])
        let start = dateValue(dict, keys: ["FECHA_LEC_ANTERIOR"]) ?? issued ?? Date()
        let end = dateValue(dict, keys: ["FECHA_LEC_ACTUAL"]) ?? start
        let m3 = doubleValue(dict, keys: ["CONSUMO", "M3", "CONSUMO_PERIODO"]) ?? 0
        let statusRaw = (stringValue(dict, keys: ["ESTADO", "estado"]) ?? "").lowercased()

        guard let amount else { return nil }
        let dueDate = due ?? issued ?? Date()
        let id = number ?? "F-\(Int(dueDate.timeIntervalSince1970))"

        let status: InvoiceStatus
        if source == .debt {
            status = dueDate < Calendar.current.startOfDay(for: Date()) ? .overdue : .pending
        } else if paidAt != nil {
            status = .paid
        } else if let pending, pending <= 0 {
            status = .paid
        } else if statusRaw.contains("pag") || statusRaw.contains("saldad") || statusRaw.contains("cancel") {
            status = .paid
        } else if let pending, pending > 0 {
            status = dueDate < Calendar.current.startOfDay(for: Date()) ? .overdue : .pending
        } else if statusRaw.contains("venc") || statusRaw.contains("deud") {
            status = .overdue
        } else if statusRaw.contains("pend") {
            status = .pending
        } else {
            // Historial sin deuda explícita → pagada (como en la web de saldos).
            status = .paid
        }

        let displayAmount: Decimal
        if status == .paid {
            displayAmount = total ?? amount
        } else {
            displayAmount = pending ?? amount
        }

        return Invoice(
            id: id,
            number: number ?? id,
            periodStart: start,
            periodEnd: end,
            dueDate: dueDate,
            issuedDate: issued ?? dueDate,
            amountARS: displayAmount,
            status: status,
            consumptionM3: m3,
            supplyPoint: "MetroGAS",
            notes: "",
            breakdown: InvoiceBreakdown(cargoFijo: 0, cargoVariable: total ?? amount, impuestos: 0, otros: 0)
        )
    }

    private static func parseM360IPost(_ dict: [String: Any]) -> Invoice? {
        // IPOST: CUENTA, FECHA_EMISION, PERIODO_CONSUMO "dd/MM/yyyy - dd/MM/yyyy", M3, TOTALAPAGAR
        var mapped = dict
        if let cuenta = stringValue(dict, keys: ["CUENTA"]), cuenta.count >= 11 {
            mapped["NUMERO_FACTURA"] = String(cuenta.suffix(11))
        }
        if let periodo = stringValue(dict, keys: ["PERIODO_CONSUMO"]), periodo.count >= 23 {
            let start = String(periodo.prefix(10))
            let end = String(periodo.suffix(10))
            mapped["FECHA_LEC_ANTERIOR"] = start
            mapped["FECHA_LEC_ACTUAL"] = end
        }
        if mapped["FECHA_FACTURA"] == nil {
            mapped["FECHA_FACTURA"] = dict["FECHA_EMISION"]
        }
        mapped["MONTO_TOTAL"] = dict["TOTALAPAGAR"] ?? dict["MONTO_TOTAL"]
        mapped["CONSUMO"] = dict["M3"] ?? dict["CONSUMO"]
        return parseM360Invoice(mapped, source: .history)
    }

    private static func parseM360DebtItem(_ dict: [String: Any]) -> Invoice? {
        // deudas.items: codigo, importe, vencimiento, ...
        let codigo = stringValue(dict, keys: ["codigo", "nro_factura"]) ?? ""
        if codigo.uppercased().contains("PP") { return nil } // plan de pagos
        var mapped = dict
        if let n = dict["nro_factura"] {
            mapped["NUMERO_FACTURA"] = n
        } else if codigo.count >= 6 {
            mapped["NUMERO_FACTURA"] = codigo
        }
        mapped["MONTO_TOTAL"] = dict["importe"] ?? dict["MONTO_TOTAL"]
        mapped["FECHA_VENCIMIENTO"] = dict["vencimiento"] ?? dict["FECHA_VENCIMIENTO"]
        mapped["IMPORTE_PENDIENTE"] = dict["importe"]
        mapped["ESTADO"] = "Pendiente"
        return parseM360Invoice(mapped, source: .debt)
    }

    private static func parseM360Info(_ info: [String: Any]) -> AccountProfile {
        var meter = "—"
        if let meters = info["meters"] as? [[String: Any]],
           let first = meters.first,
           let n = stringValue(first, keys: ["NRO_MEDIDOR", "nro_medidor"]) {
            meter = n
        }
        let customer = stringValue(info, keys: ["PVE_NRO_CLIENTE", "NRO_CLIENTE", "accountId", "custNumber", "CUENTA"]) ?? "—"
        return AccountProfile(
            holderName: stringValue(info, keys: ["PVE_TITULAR", "titular", "PVE_NOMBRE"]) ?? "",
            customerNumber: MetrogasURLs.normalizedCustomerNumber(customer) ?? customer,
            supplyAddress: stringValue(info, keys: ["PVE_DIRECCION", "direccion"]) ?? "—",
            locality: stringValue(info, keys: ["PVE_LOCALIDAD", "localidad"]) ?? "—",
            postalCode: stringValue(info, keys: ["PVE_CP", "cp"]) ?? "—",
            email: stringValue(info, keys: ["PVE_EMAIL", "email"]) ?? "",
            phone: stringValue(info, keys: ["PVE_TELEFONO", "telefono"]) ?? "—",
            meterNumber: meter,
            tariffCategory: stringValue(info, keys: ["PVE_TARIFA", "categoria", "tarifa"]) ?? "—"
        )
    }

    private static func parseM360Consumption(_ dict: [String: Any]) -> ConsumptionReading? {
        let m3 = doubleValue(dict, keys: ["CONSUMO_PERIODO", "CONSUMO", "M3"])
        guard let m3 else { return nil }

        let year = Int(stringValue(dict, keys: ["ANO_PERIODO"]) ?? "") ?? Calendar.current.component(.year, from: Date())
        let periodNum = Int(stringValue(dict, keys: ["NUMERO_PERIODO"]) ?? "") ?? 1
        // bimestres ≈ 2 meses; aproximamos mes = period*2-1
        let month = min(max(periodNum * 2 - 1, 1), 12)
        let start = Calendar.metrogasDate(year: year, month: month, day: 1)
        let end = Calendar.current.date(byAdding: DateComponents(month: 2, day: -1), to: start) ?? start
        let prev = doubleValue(dict, keys: ["CONSUMO_PERIODO_ANO_ANTERIOR"]) ?? 0
        let delta = prev > 0 ? ((m3 - prev) / prev) * 100 : 0
        let days = Double(Calendar.current.dateComponents([.day], from: start, to: end).day ?? 60) + 1
        return ConsumptionReading(
            id: UUID(),
            periodStart: start,
            periodEnd: end,
            cubicMeters: m3,
            averageDaily: m3 / max(days, 1),
            comparedToPreviousPercent: delta
        )
    }

    // MARK: - Generic helpers

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
        guard let dict = node as? [String: Any] else { return nil }
        if let m360 = parseM360Invoice(dict) { return m360 }
        let number = stringValue(dict, keys: ["number", "InvoiceNumber", "NroFactura", "Factura", "id", "ID"])
        let amount = decimalValue(dict, keys: ["amountARS", "Amount", "Importe", "Total", "amount", "saldo"])
        let due = dateValue(dict, keys: ["dueDate", "DueDate", "Vencimiento", "due"])
        let issued = dateValue(dict, keys: ["issuedDate", "IssueDate", "FechaEmision"]) ?? due
        guard let amount, let dueDate = due ?? issued else { return nil }
        let id = number ?? "F-\(Int(dueDate.timeIntervalSince1970))"
        return Invoice(
            id: id, number: number ?? id,
            periodStart: issued ?? dueDate, periodEnd: dueDate,
            dueDate: dueDate, issuedDate: issued ?? dueDate,
            amountARS: amount, status: dueDate < Date() ? .overdue : .pending,
            consumptionM3: doubleValue(dict, keys: ["consumptionM3", "Consumo", "M3"]) ?? 0,
            supplyPoint: "MetroGAS", notes: "",
            breakdown: InvoiceBreakdown(cargoFijo: 0, cargoVariable: amount, impuestos: 0, otros: 0)
        )
    }

    private static func parseReading(from node: Any) -> ConsumptionReading? {
        if let dict = node as? [String: Any], let m360 = parseM360Consumption(dict) { return m360 }
        guard let dict = node as? [String: Any] else { return nil }
        let m3 = doubleValue(dict, keys: ["cubicMeters", "Consumo", "M3", "Quantity"])
        let start = dateValue(dict, keys: ["periodStart", "FechaDesde", "period"])
        guard let m3, let start else { return nil }
        let end = dateValue(dict, keys: ["periodEnd", "FechaHasta"]) ?? start
        let days = Double(Calendar.current.dateComponents([.day], from: start, to: end).day ?? 30) + 1
        return ConsumptionReading(
            id: UUID(), periodStart: start, periodEnd: end, cubicMeters: m3,
            averageDaily: m3 / max(days, 1), comparedToPreviousPercent: 0
        )
    }

    private static func parseAccount(from dict: [String: Any]) -> AccountProfile {
        if dict["PVE_DIRECCION"] != nil || dict["meters"] != nil {
            return parseM360Info(dict)
        }
        return AccountProfile(
            holderName: stringValue(dict, keys: ["holderName", "Name", "Nombre", "PVE_TITULAR", "fullName"]) ?? "",
            customerNumber: stringValue(dict, keys: ["customerNumber", "accountId", "NroCliente", "custNumber"]) ?? "—",
            supplyAddress: stringValue(dict, keys: ["supplyAddress", "Address", "PVE_DIRECCION"]) ?? "—",
            locality: stringValue(dict, keys: ["locality", "City", "PVE_LOCALIDAD"]) ?? "—",
            postalCode: stringValue(dict, keys: ["postalCode", "PVE_CP"]) ?? "—",
            email: stringValue(dict, keys: ["email", "Email"]) ?? "",
            phone: stringValue(dict, keys: ["phone", "Telefono"]) ?? "—",
            meterNumber: stringValue(dict, keys: ["meterNumber", "Medidor", "NRO_MEDIDOR"]) ?? "—",
            tariffCategory: stringValue(dict, keys: ["tariffCategory", "Categoria"]) ?? "—"
        )
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
        return nil
    }

    private static func decimalValue(_ dict: [String: Any], keys: [String]) -> Decimal? {
        for key in keys {
            if let n = dict[key] as? NSNumber { return n.decimalValue }
            if let s = dict[key] as? String {
                let normalized = s.replacingOccurrences(of: "$", with: "")
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

import Foundation

enum InvoiceStatus: String, Codable, CaseIterable, Identifiable {
    case pending = "Pendiente"
    case paid = "Pagada"
    case overdue = "Vencida"

    var id: String { rawValue }

    var sortRank: Int {
        switch self {
        case .overdue: return 0
        case .pending: return 1
        case .paid: return 2
        }
    }

    var symbolName: String {
        switch self {
        case .paid: return "checkmark.circle.fill"
        case .pending: return "clock.fill"
        case .overdue: return "exclamationmark.triangle.fill"
        }
    }
}

struct Invoice: Identifiable, Hashable, Codable {
    let id: String
    let number: String
    let periodStart: Date
    let periodEnd: Date
    let dueDate: Date
    let issuedDate: Date
    var amountARS: Decimal
    var status: InvoiceStatus
    let consumptionM3: Double
    let supplyPoint: String
    var notes: String
    let breakdown: InvoiceBreakdown

    var periodLabel: String {
        let formatter = DateFormatter.metrogasMonthYear
        let start = formatter.string(from: periodStart)
        let end = formatter.string(from: periodEnd)
        if start == end { return start.capitalized }
        return "\(start.capitalized) – \(end.capitalized)"
    }
}

struct InvoiceBreakdown: Hashable, Codable {
    let cargoFijo: Decimal
    let cargoVariable: Decimal
    let impuestos: Decimal
    let otros: Decimal
}

enum InvoiceFilter: String, CaseIterable, Identifiable {
    case all = "Todas"
    case pending = "Pendientes"
    case paid = "Pagadas"
    case overdue = "Vencidas"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .all: return "doc.text.fill"
        case .pending: return "clock.fill"
        case .paid: return "checkmark.circle.fill"
        case .overdue: return "exclamationmark.triangle.fill"
        }
    }

    func matches(_ invoice: Invoice) -> Bool {
        switch self {
        case .all: return true
        case .pending: return invoice.status == .pending
        case .paid: return invoice.status == .paid
        case .overdue: return invoice.status == .overdue
        }
    }
}

import Foundation

struct ConsumptionReading: Identifiable, Hashable, Codable {
    let id: String
    let periodStart: Date
    let periodEnd: Date
    let cubicMeters: Double
    let averageDaily: Double
    let comparedToPreviousPercent: Double
    /// Bimestre MetroGAS (1…6), como `NUMERO_PERIODO` en la web.
    let periodNumber: Int
    /// Año del período (`ANO_PERIODO`).
    let year: Int
    /// Consumo del mismo bimestre el año anterior (`CONSUMO_PERIODO_ANO_ANTERIOR`).
    let previousYearCubicMeters: Double
    /// Etiqueta igual a la web: `(3-24) 2024 / 2023`.
    let periLabel: String

    /// Eje del gráfico (corto), ej. `(3-24)`.
    var chartLabel: String {
        if let open = periLabel.firstIndex(of: "("),
           let close = periLabel.firstIndex(of: ")"),
           open < close {
            return String(periLabel[open...close])
        }
        if periodNumber > 0, year > 0 {
            let yy = String(format: "%02d", year % 100)
            return "(\(periodNumber)-\(yy))"
        }
        return DateFormatter.metrogasShortMonth.string(from: periodStart).capitalized
    }

    var monthLabel: String { chartLabel }

    var fullPeriodLabel: String {
        if !periLabel.isEmpty { return periLabel }
        if periodNumber > 0, year > 0 {
            return "Bimestre \(periodNumber) · \(year)"
        }
        let f = DateFormatter.metrogasMonthYear
        return f.string(from: periodStart).capitalized
    }
}

enum ConsumptionPeriod: String, CaseIterable, Identifiable {
    /// Igual que la web de saldos (`slice(-6)`).
    case last6 = "6 períodos"
    case last12 = "12 períodos"
    case all = "Todos"

    var id: String { rawValue }

    func suffixCount(total: Int) -> Int? {
        switch self {
        case .last6: return min(6, total)
        case .last12: return min(12, total)
        case .all: return nil
        }
    }
}

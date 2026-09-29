import Foundation

struct ConsumptionReading: Identifiable, Hashable, Codable {
    let id: UUID
    let periodStart: Date
    let periodEnd: Date
    let cubicMeters: Double
    let averageDaily: Double
    let comparedToPreviousPercent: Double

    var monthLabel: String {
        DateFormatter.metrogasShortMonth.string(from: periodStart).capitalized
    }

    var fullPeriodLabel: String {
        let f = DateFormatter.metrogasMonthYear
        return f.string(from: periodStart).capitalized
    }
}

enum ConsumptionPeriod: String, CaseIterable, Identifiable {
    case last6 = "6 meses"
    case last12 = "12 meses"
    case yearToDate = "Año actual"

    var id: String { rawValue }

    func includes(_ reading: ConsumptionReading, relativeTo now: Date = .now) -> Bool {
        let calendar = Calendar.current
        switch self {
        case .last6:
            guard let cutoff = calendar.date(byAdding: .month, value: -6, to: now) else { return true }
            return reading.periodStart >= cutoff
        case .last12:
            guard let cutoff = calendar.date(byAdding: .month, value: -12, to: now) else { return true }
            return reading.periodStart >= cutoff
        case .yearToDate:
            let year = calendar.component(.year, from: now)
            return calendar.component(.year, from: reading.periodStart) == year
        }
    }
}

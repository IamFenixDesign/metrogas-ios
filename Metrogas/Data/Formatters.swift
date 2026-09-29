import Foundation

extension Locale {
    static let argentina = Locale(identifier: "es_AR")
}

extension DateFormatter {
    static let metrogasDayMonthYear: DateFormatter = {
        let f = DateFormatter()
        f.locale = .argentina
        f.dateFormat = "d MMM yyyy"
        return f
    }()

    static let metrogasMonthYear: DateFormatter = {
        let f = DateFormatter()
        f.locale = .argentina
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    static let metrogasShortMonth: DateFormatter = {
        let f = DateFormatter()
        f.locale = .argentina
        f.dateFormat = "MMM"
        return f
    }()

    static let metrogasFullDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = .argentina
        f.dateStyle = .long
        f.timeStyle = .none
        return f
    }()
}

enum Formatters {
    static let currencyARS: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = .argentina
        f.numberStyle = .currency
        f.currencyCode = "ARS"
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 2
        return f
    }()

    static let cubicMeters: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = .argentina
        f.numberStyle = .decimal
        f.maximumFractionDigits = 1
        f.minimumFractionDigits = 1
        return f
    }()

    static let percent: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = .argentina
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        f.positivePrefix = "+"
        return f
    }()

    static func money(_ value: Decimal) -> String {
        currencyARS.string(from: value as NSDecimalNumber) ?? "$ \(value)"
    }

    static func m3(_ value: Double) -> String {
        let n = cubicMeters.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)
        return "\(n) m³"
    }

    static func signedPercent(_ value: Double) -> String {
        let n = percent.string(from: NSNumber(value: value)) ?? "\(Int(value))"
        return "\(n)%"
    }
}

extension Calendar {
    static func metrogasDate(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return Calendar(identifier: .gregorian).date(from: components) ?? Date()
    }
}

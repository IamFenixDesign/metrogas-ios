import Foundation
import SwiftUI
import Combine

@MainActor
final class MockDataStore: ObservableObject {
    @Published var invoices: [Invoice]
    @Published var readings: [ConsumptionReading]
    @Published var account: AccountProfile
    @Published var searchText: String = ""
    @Published var invoiceFilter: InvoiceFilter = .all
    @Published var consumptionPeriod: ConsumptionPeriod = .last12
    @Published var appearanceMode: AppearanceMode = .system

    enum AppearanceMode: String, CaseIterable, Identifiable {
        case system = "Sistema"
        case light = "Claro"
        case dark = "Oscuro"

        var id: String { rawValue }
    }

    var preferredColorScheme: ColorScheme? {
        switch appearanceMode {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    init() {
        self.account = Self.sampleAccount
        self.invoices = Self.sampleInvoices
        self.readings = Self.sampleReadings
    }

    var filteredInvoices: [Invoice] {
        invoices
            .filter { invoiceFilter.matches($0) }
            .filter { invoice in
                guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return true }
                let q = searchText.lowercased()
                return invoice.number.lowercased().contains(q)
                    || invoice.periodLabel.lowercased().contains(q)
                    || invoice.status.rawValue.lowercased().contains(q)
                    || invoice.notes.lowercased().contains(q)
            }
            .sorted {
                if $0.status.sortRank != $1.status.sortRank {
                    return $0.status.sortRank < $1.status.sortRank
                }
                return $0.dueDate > $1.dueDate
            }
    }

    var nextDueInvoice: Invoice? {
        upcomingDueInvoices.first
    }

    /// Unpaid invoices sorted by soonest due date (overdue first).
    var upcomingDueInvoices: [Invoice] {
        invoices
            .filter { $0.status == .pending || $0.status == .overdue }
            .sorted { $0.dueDate < $1.dueDate }
    }

    var totalPendingARS: Decimal {
        invoices
            .filter { $0.status != .paid }
            .map(\.amountARS)
            .reduce(0, +)
    }

    var latestReading: ConsumptionReading? {
        readings.sorted { $0.periodEnd > $1.periodEnd }.first
    }

    var visibleReadings: [ConsumptionReading] {
        readings
            .filter { consumptionPeriod.includes($0) }
            .sorted { $0.periodStart < $1.periodStart }
    }

    var averageConsumption: Double {
        let values = visibleReadings.map(\.cubicMeters)
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    func invoice(id: String) -> Invoice? {
        invoices.first { $0.id == id }
    }

    func markAsPaid(_ id: String) {
        guard let index = invoices.firstIndex(where: { $0.id == id }) else { return }
        invoices[index].status = .paid
    }

    func updateNotes(_ id: String, notes: String) {
        guard let index = invoices.firstIndex(where: { $0.id == id }) else { return }
        invoices[index].notes = notes
    }

    func resetDemoData() {
        invoices = Self.sampleInvoices
        readings = Self.sampleReadings
        account = Self.sampleAccount
        searchText = ""
        invoiceFilter = .all
        consumptionPeriod = .last12
    }
}

extension MockDataStore {
    static let sampleAccount = AccountProfile(
        holderName: "María Laura Fernández",
        customerNumber: "004582193",
        supplyAddress: "Av. Rivadavia 4872, Piso 3° B",
        locality: "Caballito, CABA",
        postalCode: "C1424CET",
        email: "ml.fernandez@email.com",
        phone: "+54 11 4567-8901",
        meterNumber: "MG-882941",
        tariffCategory: "R3 – Residencial"
    )

    static var sampleInvoices: [Invoice] {
        let calendar = Calendar(identifier: .gregorian)
        func period(year: Int, month: Int) -> (Date, Date) {
            let start = Calendar.metrogasDate(year: year, month: month, day: 1)
            let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start) ?? start
            return (start, end)
        }

        // Paid history uses fixed calendar months; unpaid dues are relative to "today"
        // so reminders and "próximos vencimientos" stay demoable.
        let today = Date()
        let pendingDue = calendar.date(byAdding: .day, value: 5, to: calendar.startOfDay(for: today)) ?? today
        let overdueDue = calendar.date(byAdding: .day, value: -12, to: calendar.startOfDay(for: today)) ?? today

        let paidItems: [(String, Int, Int, Int, Int, Int, Decimal, Double, String, InvoiceBreakdown)] = [
            ("F-2026-0728", 2026, 6, 15, 7, 5, 52_340.80, 128.6, "Pagada con débito automático", InvoiceBreakdown(cargoFijo: 8_450, cargoVariable: 34_890.80, impuestos: 7_600, otros: 1_400)),
            ("F-2026-0619", 2026, 5, 15, 6, 5, 39_210.40, 91.0, "", InvoiceBreakdown(cargoFijo: 8_200, cargoVariable: 23_410.40, impuestos: 6_200, otros: 1_400)),
            ("F-2026-0511", 2026, 4, 15, 5, 5, 36_890.15, 84.7, "", InvoiceBreakdown(cargoFijo: 8_200, cargoVariable: 21_490.15, impuestos: 5_800, otros: 1_400)),
            ("F-2026-0402", 2026, 3, 15, 4, 5, 44_560.00, 105.3, "", InvoiceBreakdown(cargoFijo: 8_200, cargoVariable: 28_160, impuestos: 6_800, otros: 1_400)),
            ("F-2026-0308", 2026, 2, 15, 3, 5, 58_120.75, 141.8, "Invierno – calefacción", InvoiceBreakdown(cargoFijo: 8_200, cargoVariable: 40_320.75, impuestos: 8_200, otros: 1_400)),
            ("F-2026-0214", 2026, 1, 15, 2, 5, 61_450.30, 149.2, "", InvoiceBreakdown(cargoFijo: 7_950, cargoVariable: 43_100.30, impuestos: 9_000, otros: 1_400)),
            ("F-2025-1218", 2025, 12, 15, 1, 5, 55_980.00, 136.5, "", InvoiceBreakdown(cargoFijo: 7_950, cargoVariable: 38_230, impuestos: 8_400, otros: 1_400)),
            ("F-2025-1109", 2025, 11, 15, 12, 5, 42_110.60, 99.4, "", InvoiceBreakdown(cargoFijo: 7_950, cargoVariable: 26_560.60, impuestos: 6_200, otros: 1_400)),
            ("F-2025-1015", 2025, 10, 15, 11, 5, 38_740.20, 88.1, "", InvoiceBreakdown(cargoFijo: 7_700, cargoVariable: 23_840.20, impuestos: 5_800, otros: 1_400)),
            ("F-2025-0922", 2025, 9, 15, 10, 5, 35_220.00, 79.6, "", InvoiceBreakdown(cargoFijo: 7_700, cargoVariable: 20_920, impuestos: 5_200, otros: 1_400)),
        ]

        let pendingPeriod = period(year: 2026, month: 8)
        let overduePeriod = period(year: 2026, month: 7)

        var result: [Invoice] = [
            Invoice(
                id: "F-2026-0912",
                number: "F-2026-0912",
                periodStart: pendingPeriod.0,
                periodEnd: pendingPeriod.1,
                dueDate: pendingDue,
                issuedDate: Calendar.metrogasDate(year: 2026, month: 8, day: 15),
                amountARS: 48_920.55,
                status: .pending,
                consumptionM3: 112.4,
                supplyPoint: "Caballito – MG-882941",
                notes: "",
                breakdown: InvoiceBreakdown(cargoFijo: 8_450, cargoVariable: 31_200.55, impuestos: 7_870, otros: 1_400)
            ),
            Invoice(
                id: "F-2026-0831",
                number: "F-2026-0831",
                periodStart: overduePeriod.0,
                periodEnd: overduePeriod.1,
                dueDate: overdueDue,
                issuedDate: Calendar.metrogasDate(year: 2026, month: 7, day: 15),
                amountARS: 41_780.00,
                status: .overdue,
                consumptionM3: 98.2,
                supplyPoint: "Caballito – MG-882941",
                notes: "Recordatorio enviado por mail",
                breakdown: InvoiceBreakdown(cargoFijo: 8_450, cargoVariable: 25_110, impuestos: 6_820, otros: 1_400)
            ),
        ]

        result += paidItems.map { item in
            let (number, year, month, issueDay, dueMonth, dueDay, amount, m3, notes, breakdown) = item
            let (start, end) = period(year: year, month: month)
            let dueYear = dueMonth == 1 && month == 12 ? year + 1 : year
            return Invoice(
                id: number,
                number: number,
                periodStart: start,
                periodEnd: end,
                dueDate: Calendar.metrogasDate(year: dueYear, month: dueMonth, day: dueDay),
                issuedDate: Calendar.metrogasDate(year: year, month: month, day: issueDay),
                amountARS: amount,
                status: .paid,
                consumptionM3: m3,
                supplyPoint: "Caballito – MG-882941",
                notes: notes,
                breakdown: breakdown
            )
        }
        return result
    }

    static var sampleReadings: [ConsumptionReading] {
        let series: [(Int, Int, Double, Double)] = [
            (2025, 9, 79.6, -4),
            (2025, 10, 88.1, 11),
            (2025, 11, 99.4, 13),
            (2025, 12, 136.5, 37),
            (2026, 1, 149.2, 9),
            (2026, 2, 141.8, -5),
            (2026, 3, 105.3, -26),
            (2026, 4, 84.7, -20),
            (2026, 5, 91.0, 7),
            (2026, 6, 128.6, 41),
            (2026, 7, 98.2, -24),
            (2026, 8, 112.4, 14),
        ]

        return series.map { year, month, m3, delta in
            let start = Calendar.metrogasDate(year: year, month: month, day: 1)
            let end = Calendar.current.date(byAdding: DateComponents(month: 1, day: -1), to: start) ?? start
            let days = Double(Calendar.current.dateComponents([.day], from: start, to: end).day ?? 30) + 1
            return ConsumptionReading(
                id: UUID(),
                periodStart: start,
                periodEnd: end,
                cubicMeters: m3,
                averageDaily: m3 / days,
                comparedToPreviousPercent: delta
            )
        }
    }
}

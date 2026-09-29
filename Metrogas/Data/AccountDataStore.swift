import Foundation
import SwiftUI
import Combine

@MainActor
final class AccountDataStore: ObservableObject {
    @Published var invoices: [Invoice] = []
    @Published var readings: [ConsumptionReading] = []
    @Published var account: AccountProfile = .empty
    @Published var searchText: String = ""
    @Published var invoiceFilter: InvoiceFilter = .all
    @Published var consumptionPeriod: ConsumptionPeriod = .last12
    @Published var isLoading = false
    @Published var lastSync: Date?
    @Published var syncMessage: String?

    private enum Keys {
        static let cache = "metrogas.account.cache.v1"
        static let lastSync = "metrogas.account.lastSync"
    }

    init() {
        loadCache()
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

    var nextDueInvoice: Invoice? { upcomingDueInvoices.first }

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
        persistCache()
    }

    func updateNotes(_ id: String, notes: String) {
        guard let index = invoices.firstIndex(where: { $0.id == id }) else { return }
        invoices[index].notes = notes
        persistCache()
    }

    func applyLoginHint(email: String?) {
        let trimmed = email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return }
        if account.email.isEmpty || account.email == AccountProfile.empty.email {
            account.email = trimmed
        }
        if account.holderName.isEmpty || account.holderName == AccountProfile.empty.holderName {
            let local = trimmed.split(separator: "@").first.map(String.init) ?? trimmed
            account.holderName = local.replacingOccurrences(of: ".", with: " ").capitalized
        }
        persistCache()
    }

    func refresh(loginHint: String? = nil) async {
        isLoading = true
        syncMessage = nil
        defer { isLoading = false }

        if let loginHint { applyLoginHint(email: loginHint) }

        do {
            let snapshot = try await MetrogasDataService.shared.fetchAccountData(loginHint: loginHint ?? account.email)
            if !snapshot.account.holderName.isEmpty {
                account = snapshot.account
            } else if let loginHint, !loginHint.isEmpty {
                applyLoginHint(email: loginHint)
            }
            if !snapshot.invoices.isEmpty { invoices = snapshot.invoices }
            if !snapshot.readings.isEmpty { readings = snapshot.readings }
            lastSync = Date()
            UserDefaults.standard.set(lastSync, forKey: Keys.lastSync)
            persistCache()
            if snapshot.invoices.isEmpty && snapshot.readings.isEmpty {
                syncMessage = "Sesión activa. Todavía no encontramos facturas o consumo para mostrar. Deslizá para reintentar."
            } else {
                syncMessage = nil
            }
        } catch {
            syncMessage = "No pudimos sincronizar con la Oficina Virtual. Revisá tu conexión e intentá de nuevo."
        }
    }

    func clear() {
        invoices = []
        readings = []
        account = .empty
        searchText = ""
        invoiceFilter = .all
        consumptionPeriod = .last12
        lastSync = nil
        syncMessage = nil
        UserDefaults.standard.removeObject(forKey: Keys.cache)
        UserDefaults.standard.removeObject(forKey: Keys.lastSync)
    }

    private func persistCache() {
        let payload = CachePayload(account: account, invoices: invoices, readings: readings)
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: Keys.cache)
        }
    }

    private func loadCache() {
        if let data = UserDefaults.standard.data(forKey: Keys.cache),
           let payload = try? JSONDecoder().decode(CachePayload.self, from: data) {
            account = payload.account
            invoices = payload.invoices
            readings = payload.readings
        }
        lastSync = UserDefaults.standard.object(forKey: Keys.lastSync) as? Date
    }

    private struct CachePayload: Codable {
        var account: AccountProfile
        var invoices: [Invoice]
        var readings: [ConsumptionReading]
    }
}

extension AccountProfile {
    static let empty = AccountProfile(
        holderName: "",
        customerNumber: "—",
        supplyAddress: "—",
        locality: "—",
        postalCode: "—",
        email: "",
        phone: "—",
        meterNumber: "—",
        tariffCategory: "—"
    )
}

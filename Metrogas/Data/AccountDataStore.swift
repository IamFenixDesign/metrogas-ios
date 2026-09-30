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
    /// La sesión SAP venció y hace falta volver a iniciar sesión.
    @Published var needsReauthentication = false
    /// Falta el N° de cliente de 11 dígitos para consultar M360.
    @Published var needsCustomerNumber = false
    @Published var customerNumberDraft: String = ""

    private enum Keys {
        static let cache = "metrogas.account.cache.v1"
        static let lastSync = "metrogas.account.lastSync"
        static let customerNumber = "metrogas.account.customerNumber"
    }

    init() {
        loadCache()
        if let saved = UserDefaults.standard.string(forKey: Keys.customerNumber),
           let normalized = MetrogasURLs.normalizedCustomerNumber(saved) {
            account.customerNumber = normalized
            customerNumberDraft = normalized
        }
        needsCustomerNumber = MetrogasURLs.normalizedCustomerNumber(account.customerNumber) == nil
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

    var resolvedCustomerNumber: String? {
        MetrogasURLs.normalizedCustomerNumber(account.customerNumber)
            ?? MetrogasURLs.normalizedCustomerNumber(customerNumberDraft)
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

    @discardableResult
    func saveCustomerNumber(_ raw: String) -> Bool {
        guard let normalized = MetrogasURLs.normalizedCustomerNumber(raw) else {
            syncMessage = "Ingresá el N° de cliente de 11 dígitos (como figura en tu factura)."
            needsCustomerNumber = true
            return false
        }
        account.customerNumber = normalized
        customerNumberDraft = normalized
        UserDefaults.standard.set(normalized, forKey: Keys.customerNumber)
        needsCustomerNumber = false
        persistCache()
        return true
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
        guard !isLoading else { return }
        isLoading = true
        syncMessage = nil
        defer { isLoading = false }

        if let loginHint { applyLoginHint(email: loginHint) }

        guard let customerNumber = resolvedCustomerNumber else {
            needsCustomerNumber = true
            syncMessage = "Para cargar facturas y saldo necesitamos tu N° de cliente de 11 dígitos."
            return
        }
        needsCustomerNumber = false

        // Revalidar sesión SAP antes de pedir datos (cubre app reabierta con flag local).
        let saved = CredentialStore.load()
        do {
            _ = try await MetrogasAuthService.shared.ensureActiveSession(
                email: saved?.email ?? loginHint ?? account.email,
                password: saved?.password
            )
        } catch MetrogasAuthError.sessionExpired {
            syncMessage = MetrogasAuthError.sessionExpired.errorDescription
            needsReauthentication = true
            return
        } catch MetrogasAuthError.invalidCredentials {
            syncMessage = "Tu sesión venció. Volvé a ingresar."
            needsReauthentication = true
            return
        } catch {
            // Seguimos: puede ser un glitch de red con cookies aún válidas.
        }

        do {
            let snapshot = try await MetrogasDataService.shared.fetchAccountData(
                accountId: customerNumber,
                loginHint: loginHint ?? account.email
            )
            var nextAccount = snapshot.account
            nextAccount.customerNumber = customerNumber
            if nextAccount.email.isEmpty {
                nextAccount.email = loginHint ?? account.email
            }
            if nextAccount.holderName.isEmpty {
                applyLoginHint(email: loginHint ?? account.email)
                nextAccount.holderName = account.holderName
            }
            account = nextAccount
            invoices = snapshot.invoices
            readings = snapshot.readings
            lastSync = Date()
            UserDefaults.standard.set(lastSync, forKey: Keys.lastSync)
            UserDefaults.standard.set(customerNumber, forKey: Keys.customerNumber)
            persistCache()
            if snapshot.invoices.isEmpty && snapshot.readings.isEmpty {
                syncMessage = "No encontramos facturas para el N° \(customerNumber). Verificá el número o reintentá en unos segundos."
            } else {
                syncMessage = nil
            }
        } catch {
            syncMessage = "No pudimos sincronizar con MetroGAS. Revisá tu conexión e intentá de nuevo."
        }
    }

    func clear() {
        invoices = []
        readings = []
        let keptCustomer = UserDefaults.standard.string(forKey: Keys.customerNumber)
        account = .empty
        if let keptCustomer, let normalized = MetrogasURLs.normalizedCustomerNumber(keptCustomer) {
            account.customerNumber = normalized
            customerNumberDraft = normalized
            needsCustomerNumber = false
        } else {
            customerNumberDraft = ""
            needsCustomerNumber = true
        }
        searchText = ""
        invoiceFilter = .all
        consumptionPeriod = .last12
        lastSync = nil
        syncMessage = nil
        needsReauthentication = false
        UserDefaults.standard.removeObject(forKey: Keys.cache)
        UserDefaults.standard.removeObject(forKey: Keys.lastSync)
    }

    private func persistCache() {
        let payload = CachePayload(account: account, invoices: invoices, readings: readings)
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: Keys.cache)
        }
        if let normalized = MetrogasURLs.normalizedCustomerNumber(account.customerNumber) {
            UserDefaults.standard.set(normalized, forKey: Keys.customerNumber)
        }
    }

    private func loadCache() {
        if let data = UserDefaults.standard.data(forKey: Keys.cache),
           let payload = try? JSONDecoder().decode(CachePayload.self, from: data) {
            account = payload.account
            invoices = payload.invoices
            readings = payload.readings
            customerNumberDraft = MetrogasURLs.normalizedCustomerNumber(payload.account.customerNumber) ?? ""
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

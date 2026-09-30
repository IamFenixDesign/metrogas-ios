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
    /// Solo como respaldo si la OV no devolvió N° de cliente.
    @Published var needsCustomerNumber = false
    @Published var customerNumberDraft: String = ""
    private enum Keys {
        static let cache = "metrogas.account.cache.v1"
        static let lastSync = "metrogas.account.lastSync"
        static let customerNumber = "metrogas.account.customerNumber"
    }

    init() {
        LinkedAccountStore.migrateIfNeeded()
        loadCache()
        // Preferir N° ligado al email; si el login es solo por cliente, el global.
        if let linked = LinkedAccountStore.customerNumber(forEmail: account.email.isEmpty ? nil : account.email)
            ?? LinkedAccountStore.lastCustomerNumber()
            ?? MetrogasURLs.normalizedCustomerNumber(account.customerNumber) {
            account.customerNumber = linked
            customerNumberDraft = linked
        } else {
            customerNumberDraft = ""
            account.customerNumber = "—"
        }
        needsCustomerNumber = false
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
        LinkedAccountStore.resolvePreferredCustomerNumber(
            loginEmail: account.email.isEmpty ? nil : account.email,
            fallback: MetrogasURLs.normalizedCustomerNumber(account.customerNumber)
                ?? MetrogasURLs.normalizedCustomerNumber(customerNumberDraft)
                ?? LinkedAccountStore.lastCustomerNumber()
        )
    }

    func preferredCustomerNumber(forLogin email: String?) -> String? {
        LinkedAccountStore.resolvePreferredCustomerNumber(
            loginEmail: email ?? account.email,
            fallback: resolvedCustomerNumber
        )
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
    func saveCustomerNumber(_ raw: String, forEmail email: String? = nil) -> Bool {
        guard let normalized = MetrogasURLs.normalizedCustomerNumber(raw) else {
            syncMessage = "Ingresá el N° de cliente de 11 dígitos (como figura en tu factura)."
            needsCustomerNumber = true
            return false
        }
        account.customerNumber = normalized
        customerNumberDraft = normalized
        if let mail = email ?? (account.email.isEmpty ? nil : account.email) {
            LinkedAccountStore.bind(email: mail, customerNumber: normalized)
        } else {
            LinkedAccountStore.bindCustomerOnly(normalized)
        }
        needsCustomerNumber = false
        persistCache(bindCustomer: true)
        return true
    }

    /// Ajusta identidad al email de login (Google o MetroGAS) sin inventar el nombre.
    /// Si cambia el email, limpia perfil/facturas de la cuenta anterior.
    func applyLoginHint(email: String?) {
        let trimmed = email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return }

        let previous = account.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let next = trimmed.lowercased()
        let switchedAccount = !previous.isEmpty && previous != next

        if switchedAccount {
            invoices = []
            readings = []
            account = .empty
            lastSync = nil
            syncMessage = nil
            UserDefaults.standard.removeObject(forKey: Keys.cache)
            UserDefaults.standard.removeObject(forKey: Keys.lastSync)
        }

        account.email = trimmed

        // Nunca fabricar titular desde el email: eso mostraba nombres falsos.
        // El nombre real llega de M360 (PVE_TITULAR) tras discovery del portal.
        if looksLikeFabricatedName(account.holderName, email: trimmed) {
            account.holderName = ""
        }

        // No pintar N°/titular de un vínculo previo hasta que el sync confirme
        // contra el portal de ESTA sesión Google (evita mostrar cuenta ajena).
        if switchedAccount || LinkedAccountStore.customerNumber(forEmail: trimmed) == nil {
            account.holderName = ""
            account.customerNumber = "—"
            account.supplyAddress = "—"
            account.locality = "—"
            account.postalCode = "—"
            account.phone = "—"
            account.meterNumber = "—"
            account.tariffCategory = "—"
            customerNumberDraft = ""
        } else {
            // Hay vínculo: dejar draft interno pero no inventar titular hasta M360.
            if let linked = LinkedAccountStore.customerNumber(forEmail: trimmed) {
                customerNumberDraft = linked
            }
            account.holderName = ""
            account.customerNumber = "—"
            account.supplyAddress = "—"
        }
        persistCache()
    }

    /// Detecta nombres inventados tipo "juan.perez" → "Juan Perez" desde el email.
    private func looksLikeFabricatedName(_ name: String, email: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let local = email.split(separator: "@").first.map(String.init)?.lowercased() ?? ""
        guard !local.isEmpty else { return false }
        let normalizedName = trimmed
            .lowercased()
            .replacingOccurrences(of: " ", with: ".")
            .replacingOccurrences(of: "_", with: ".")
        let normalizedLocal = local
            .replacingOccurrences(of: " ", with: ".")
            .replacingOccurrences(of: "_", with: ".")
        return normalizedName == normalizedLocal
            || trimmed.lowercased() == local.replacingOccurrences(of: ".", with: " ")
            || trimmed.lowercased() == local.replacingOccurrences(of: "_", with: " ")
    }

    /// Aplica el snapshot del login por N° de cliente (sin volver a pedir red).
    func applyCustomerLoginSnapshot(_ snapshot: MetrogasDataSnapshot, customerNumber: String) {
        guard let id = MetrogasURLs.normalizedCustomerNumber(customerNumber) else { return }
        invoices = snapshot.invoices
        readings = snapshot.readings.isEmpty && !snapshot.invoices.isEmpty
            ? MetrogasJSONParser.deriveReadings(from: snapshot.invoices)
            : snapshot.readings
        account = snapshot.account
        account.customerNumber = id
        customerNumberDraft = id
        needsCustomerNumber = false
        needsReauthentication = false
        syncMessage = invoices.isEmpty
            ? "No encontramos facturas todavía. Deslizá hacia abajo para reintentar."
            : nil
        lastSync = Date()
        UserDefaults.standard.set(lastSync, forKey: Keys.lastSync)
        LinkedAccountStore.bindCustomerOnly(id)
        persistCache(bindCustomer: true)
    }

    /// Sync de cuenta/facturas/consumo.
    /// Con login por N° de cliente consulta M360 saldos (Tu Factura).
    func refresh(loginHint: String? = nil, customerNumber: String? = nil, force: Bool = false) async {
        guard !isLoading else { return }
        guard force else { return }

        isLoading = true
        syncMessage = nil
        needsCustomerNumber = false
        defer { isLoading = false }

        let number = MetrogasURLs.normalizedCustomerNumber(customerNumber ?? "")
            ?? MetrogasURLs.normalizedCustomerNumber(account.customerNumber)
            ?? MetrogasURLs.normalizedCustomerNumber(customerNumberDraft)
            ?? LinkedAccountStore.lastCustomerNumber()

        guard let number else {
            needsCustomerNumber = true
            syncMessage = "Ingresá tu N° de cliente de 11 dígitos para sincronizar."
            return
        }

        do {
            let snapshot = try await MetrogasDataService.shared.fetchByCustomerNumber(number)
            let hasFreshProfile = !snapshot.account.holderName.isEmpty
                || (!snapshot.account.supplyAddress.isEmpty && snapshot.account.supplyAddress != "—")
            let hasFreshInvoices = !snapshot.invoices.isEmpty

            if hasFreshProfile || hasFreshInvoices {
                applyCustomerLoginSnapshot(snapshot, customerNumber: number)
                if let loginHint, !loginHint.isEmpty, account.email.isEmpty {
                    account.email = loginHint
                    persistCache(bindCustomer: true)
                }
            } else {
                account.customerNumber = number
                customerNumberDraft = number
                syncMessage = "No encontramos datos para ese N°. Revisalo en Cuenta."
                needsCustomerNumber = true
            }
        } catch {
            syncMessage = "No pudimos sincronizar con MetroGAS. Deslizá hacia abajo para reintentar."
        }
    }

    func clear() {
        invoices = []
        readings = []
        account = .empty
        customerNumberDraft = ""
        needsCustomerNumber = false
        searchText = ""
        invoiceFilter = .all
        consumptionPeriod = .last12
        lastSync = nil
        syncMessage = nil
        needsReauthentication = false
        isLoading = false
        UserDefaults.standard.removeObject(forKey: Keys.cache)
        UserDefaults.standard.removeObject(forKey: Keys.lastSync)
        // Los vínculos confirmados por billing quedan por email; al volver a entrar
        // se revalidan contra el portal (forcePortalDiscovery).
    }

    private func persistCache(bindCustomer: Bool = false) {
        let payload = CachePayload(account: account, invoices: invoices, readings: readings)
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: Keys.cache)
        }
        // Solo re-vincular cuando el sync acaba de confirmar billing.
        if bindCustomer,
           let normalized = MetrogasURLs.normalizedCustomerNumber(account.customerNumber) {
            LinkedAccountStore.bind(email: account.email, customerNumber: normalized)
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

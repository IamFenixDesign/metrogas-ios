import Foundation
import SwiftUI
import Combine
import WidgetKit

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
        loadCache()
        // Solo rehidratar N° si la caché ya tiene el email de esa misma cuenta.
        if !account.email.isEmpty,
           let linked = LinkedAccountStore.customerNumber(forEmail: account.email) {
            account.customerNumber = linked
            customerNumberDraft = linked
        } else {
            customerNumberDraft = MetrogasURLs.normalizedCustomerNumber(account.customerNumber) ?? ""
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
        LinkedAccountStore.bind(email: email ?? account.email, customerNumber: normalized)
        needsCustomerNumber = false
        persistCache()
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
            WidgetSnapshotStore.clear()
            WidgetCenter.shared.reloadAllTimelines()
        }

        account.email = trimmed

        // Nunca fabricar titular desde el email: eso mostraba nombres falsos.
        // El nombre real llega de M360 (PVE_TITULAR).
        if looksLikeFabricatedName(account.holderName, email: trimmed) {
            account.holderName = ""
        }

        if let linked = LinkedAccountStore.customerNumber(forEmail: trimmed) {
            account.customerNumber = linked
            customerNumberDraft = linked
            needsCustomerNumber = false
        } else if switchedAccount {
            account.customerNumber = "—"
            customerNumberDraft = ""
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

    /// Sync de cuenta/facturas/consumo.
    /// `force: false` solo usa caché local. `force: true` consulta la red
    /// (login, vincular N°, pull-to-refresh, o caché vacía al reabrir).
    func refresh(loginHint: String? = nil, force: Bool = false) async {
        guard !isLoading else { return }

        // Sin `force` no hay red: la info queda en caché local.
        guard force else { return }

        isLoading = true
        syncMessage = nil
        needsCustomerNumber = false
        defer { isLoading = false }

        // Email de login / Google. El N° solo viene de vínculo confirmado o discovery/M360.
        let identity = await MetrogasAuthService.shared.resolveSignedInIdentity()
        let emailHint: String? = {
            if let loginHint, !loginHint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return loginHint
            }
            if let email = identity.email, !email.isEmpty { return email }
            return account.email.isEmpty ? nil : account.email
        }()
        if let emailHint { applyLoginHint(email: emailHint) }

        let saved = CredentialStore.load()
        do {
            _ = try await MetrogasAuthService.shared.ensureActiveSession(
                email: saved?.email ?? emailHint,
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
            // Seguimos: cookies de Google/portal pueden seguir válidas.
        }

        // Solo N° ya vinculado a ESTE email (o etiquetado con alta confianza).
        let linkedId = preferredCustomerNumber(forLogin: emailHint)
            ?? identity.customerNumber

        do {
            let snapshot = try await MetrogasDataService.shared.fetchAccountData(
                loginHint: emailHint,
                preferredAccountId: linkedId
            )

            var nextAccount = snapshot.account
            let confirmedId = MetrogasURLs.normalizedCustomerNumber(snapshot.account.customerNumber)
            if let id = confirmedId {
                nextAccount.customerNumber = id
                customerNumberDraft = id
                LinkedAccountStore.bind(email: emailHint ?? nextAccount.email, customerNumber: id)
                needsCustomerNumber = false
            } else if let linkedId,
                      !snapshot.invoices.isEmpty {
                // M360 respondió con facturas para el N° vinculado → confirmar vínculo.
                nextAccount.customerNumber = linkedId
                customerNumberDraft = linkedId
                LinkedAccountStore.bind(email: emailHint ?? nextAccount.email, customerNumber: linkedId)
                needsCustomerNumber = false
            } else if let linkedId, snapshot.invoices.isEmpty,
                      nextAccount.holderName.isEmpty {
                // Vínculo previo erróneo (scrape): soltarlo para no mostrar datos ajenos.
                LinkedAccountStore.unbind(email: emailHint)
                nextAccount.customerNumber = "—"
                customerNumberDraft = ""
            }

            // Email de login (Google) siempre gana como contacto de la sesión.
            if let emailHint, !emailHint.isEmpty {
                nextAccount.email = emailHint
            }
            // No rellenar titular con basura del email; dejar vacío hasta PVE_TITULAR.
            if looksLikeFabricatedName(nextAccount.holderName, email: nextAccount.email) {
                nextAccount.holderName = ""
            }
            if looksLikeFabricatedName(account.holderName, email: emailHint ?? account.email) {
                account.holderName = ""
            }

            // Datos frescos de M360 pisan caché de perfil cuando hay titular/dirección reales.
            account = MetrogasJSONParser.mergeAccount(account, nextAccount)
            if !nextAccount.holderName.isEmpty { account.holderName = nextAccount.holderName }
            if !nextAccount.supplyAddress.isEmpty, nextAccount.supplyAddress != "—" {
                account.supplyAddress = nextAccount.supplyAddress
            }
            if let confirmedId {
                account.customerNumber = confirmedId
            }

            if !snapshot.invoices.isEmpty {
                invoices = snapshot.invoices
            } else if invoices.isEmpty {
                invoices = snapshot.invoices
            }
            if !snapshot.readings.isEmpty || readings.isEmpty {
                readings = snapshot.readings
            }
            lastSync = Date()
            UserDefaults.standard.set(lastSync, forKey: Keys.lastSync)
            persistCache()

            if MetrogasURLs.normalizedCustomerNumber(account.customerNumber) == nil
                && invoices.isEmpty {
                needsCustomerNumber = true
                syncMessage = "Tu usuario no tiene un N° de cliente asociado todavía. Si lo sabés, cargalo en Cuenta una vez y queda vinculado."
            } else if invoices.isEmpty && readings.isEmpty {
                syncMessage = "No encontramos facturas todavía. Deslizá hacia abajo para reintentar."
            } else {
                syncMessage = nil
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
        WidgetSnapshotStore.clear()
        WidgetCenter.shared.reloadAllTimelines()
        // No conservar N° de cliente en memoria: el vínculo queda por email en LinkedAccountStore.
    }

    private func persistCache() {
        let payload = CachePayload(account: account, invoices: invoices, readings: readings)
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: Keys.cache)
        }
        if let normalized = MetrogasURLs.normalizedCustomerNumber(account.customerNumber) {
            LinkedAccountStore.bind(email: account.email, customerNumber: normalized)
        }
        publishWidgetSnapshot()
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
        publishWidgetSnapshot()
    }

    private func publishWidgetSnapshot() {
        let items = invoices
            .sorted { $0.issuedDate > $1.issuedDate }
            .prefix(10)
            .map { invoice in
                WidgetSnapshotStore.Item(
                    id: invoice.id,
                    number: invoice.number,
                    periodLabel: invoice.periodLabel,
                    amountText: Formatters.money(invoice.amountARS),
                    statusLabel: invoice.status.rawValue,
                    dueDateText: DateFormatter.metrogasDayMonthYear.string(from: invoice.dueDate),
                    issuedAt: invoice.issuedDate
                )
            }
        WidgetSnapshotStore.save(
            WidgetSnapshotStore.Snapshot(updatedAt: Date(), items: Array(items))
        )
        WidgetCenter.shared.reloadAllTimelines()
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

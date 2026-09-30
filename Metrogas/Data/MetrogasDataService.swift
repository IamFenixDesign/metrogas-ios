import Foundation

struct MetrogasDataSnapshot: Sendable {
    var account: AccountProfile
    var invoices: [Invoice]
    var readings: [ConsumptionReading]
}

/// Sincroniza con Oficina Virtual (Google o MetroGAS) vía portal + M360 saldos.
actor MetrogasDataService {
    static let shared = MetrogasDataService()

    private init() {}

    func fetchAccountData(loginHint: String?, preferredAccountId: String?) async throws -> MetrogasDataSnapshot {
        LinkedAccountStore.migrateIfNeeded()

        let identity = await MetrogasAuthService.shared.resolveSignedInIdentity()
        let email: String? = {
            if let loginHint, !loginHint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return loginHint
            }
            return identity.email
        }()

        // Hint: solo vínculo confirmado. Nunca scrapes de cookies/HTML.
        let preferredHint = MetrogasURLs.normalizedCustomerNumber(preferredAccountId ?? "")
            ?? LinkedAccountStore.customerNumber(forEmail: email)

        // Siempre discovery en portal autenticado; el hint solo gana si aparece ahí.
        var snapshot = try await PortalDataBridge.shared.syncFromSession(
            loginHint: email,
            preferredAccountId: preferredHint,
            forcePortalDiscovery: true,
            timeoutSeconds: 32
        )

        let billingId = MetrogasURLs.normalizedCustomerNumber(snapshot.account.customerNumber)
        let hasProfile = !snapshot.account.holderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasAddress = !snapshot.account.supplyAddress.isEmpty && snapshot.account.supplyAddress != "—"
        let hasInvoices = !snapshot.invoices.isEmpty
        let confirmed = billingId != nil && (hasProfile || hasAddress || hasInvoices)

        // Si el hint no coincide con lo que billing/discovery confirmó → soltar veneno.
        if let preferredHint, let billingId, preferredHint != billingId, confirmed {
            LinkedAccountStore.unbind(email: email)
        }
        if let preferredHint, !confirmed {
            LinkedAccountStore.unbind(email: email)
            // Reintentar discovery puro (sin hint) una vez.
            snapshot = try await PortalDataBridge.shared.syncFromSession(
                loginHint: email,
                preferredAccountId: nil,
                forcePortalDiscovery: true,
                timeoutSeconds: 32
            )
        }

        var account = seedAccount(loginHint: email, customerNumber: nil)
        account = MetrogasJSONParser.mergeAccount(account, snapshot.account)

        let finalId = MetrogasURLs.normalizedCustomerNumber(snapshot.account.customerNumber)
        let finalProfile = !snapshot.account.holderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let finalAddress = !snapshot.account.supplyAddress.isEmpty && snapshot.account.supplyAddress != "—"
        let finalInvoices = !snapshot.invoices.isEmpty
        let finalConfirmed = finalId != nil && (finalProfile || finalAddress || finalInvoices)

        if let finalId, finalConfirmed {
            account.customerNumber = finalId
            LinkedAccountStore.bind(email: email, customerNumber: finalId)
        } else {
            account.customerNumber = "—"
            if let email { LinkedAccountStore.unbind(email: email) }
        }

        if let email, !email.isEmpty {
            account.email = email
        }

        var invoices = snapshot.invoices
        var readings = snapshot.readings
        if readings.isEmpty && !invoices.isEmpty {
            readings = MetrogasJSONParser.deriveReadings(from: invoices)
        }

        return MetrogasDataSnapshot(account: account, invoices: invoices, readings: readings)
    }

    private func seedAccount(loginHint: String?, customerNumber: String?) -> AccountProfile {
        var account = AccountProfile.empty
        if let customerNumber, let normalized = MetrogasURLs.normalizedCustomerNumber(customerNumber) {
            account.customerNumber = normalized
        }
        if let loginHint, !loginHint.isEmpty {
            account.email = loginHint
        }
        return account
    }
}

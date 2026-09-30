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

        // Esperar sesión de portal usable (crítico tras Google OAuth / IdP).
        var portalReady = false
        for _ in 0..<16 {
            if await MetrogasAuthService.shared.probePortalSession() {
                portalReady = true
                break
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
        }

        // Hint: solo vínculo confirmado. Nunca scrapes.
        let preferredHint = MetrogasURLs.normalizedCustomerNumber(preferredAccountId ?? "")
            ?? LinkedAccountStore.customerNumber(forEmail: email)

        // Discovery en portal; si no hay candidatos, PortalDataBridge usa preferredHint.
        var snapshot = try await PortalDataBridge.shared.syncFromSession(
            loginHint: email,
            preferredAccountId: preferredHint,
            forcePortalDiscovery: true,
            timeoutSeconds: 44
        )

        // Tras Google a veces el shell SAP hidrata tarde: reintentar discovery una vez.
        let firstEmpty = MetrogasURLs.normalizedCustomerNumber(snapshot.account.customerNumber) == nil
            && snapshot.invoices.isEmpty
        if firstEmpty, portalReady {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            snapshot = try await PortalDataBridge.shared.syncFromSession(
                loginHint: email,
                preferredAccountId: preferredHint,
                forcePortalDiscovery: true,
                timeoutSeconds: 36
            )
        }

        var account = seedAccount(loginHint: email, customerNumber: nil)
        account = MetrogasJSONParser.mergeAccount(account, snapshot.account)

        let finalId = MetrogasURLs.normalizedCustomerNumber(snapshot.account.customerNumber)
        let finalProfile = !snapshot.account.holderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let finalAddress = !snapshot.account.supplyAddress.isEmpty && snapshot.account.supplyAddress != "—"
        let finalInvoices = !snapshot.invoices.isEmpty
        // La sesión autenticada del portal ya prueba que es TU cuenta Google/MetroGAS.
        // No exigir match con el email de factura digital (suele ser otro).
        let finalConfirmed = finalId != nil && (finalProfile || finalAddress || finalInvoices)

        if let email, !email.isEmpty {
            account.email = email
        }

        guard let finalId, finalConfirmed else {
            account.customerNumber = "—"
            // No borrar un vínculo previo válido solo porque discovery falló esta vez.
            return MetrogasDataSnapshot(account: account, invoices: [], readings: [])
        }

        account.customerNumber = finalId
        LinkedAccountStore.bind(email: email, customerNumber: finalId)

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

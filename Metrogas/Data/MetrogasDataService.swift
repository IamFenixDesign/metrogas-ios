import Foundation

struct MetrogasDataSnapshot: Sendable {
    var account: AccountProfile
    var invoices: [Invoice]
    var readings: [ConsumptionReading]
}

/// Sincroniza con Oficina Virtual (Google o MetroGAS) vía portal + M360 saldos.
/// M360 es público: NUNCA se consulta un N° que no venga del portal de ESTA sesión
/// (o de un match estricto email Google == email de factura digital).
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

        // Esperar sesión portal usable (crítico tras Google OAuth).
        for _ in 0..<16 {
            if await MetrogasAuthService.shared.probePortalSession() { break }
            try? await Task.sleep(nanoseconds: 400_000_000)
        }

        // Solo hint de orden: debe aparecer entre candidatos del portal.
        let preferredHint = MetrogasURLs.normalizedCustomerNumber(preferredAccountId ?? "")
            ?? LinkedAccountStore.customerNumber(forEmail: email)

        // SIEMPRE discovery en el portal autenticado (igual que la web tras Google).
        // Nunca saldos-only con un N° guardado: eso mostraba cuentas ajenas.
        var snapshot = try await PortalDataBridge.shared.syncFromSession(
            loginHint: email,
            preferredAccountId: preferredHint,
            forcePortalDiscovery: true,
            timeoutSeconds: 44
        )

        let firstEmpty = MetrogasURLs.normalizedCustomerNumber(snapshot.account.customerNumber) == nil
            && snapshot.invoices.isEmpty
        if firstEmpty {
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
        if let email, !email.isEmpty { account.email = email }

        let finalId = MetrogasURLs.normalizedCustomerNumber(snapshot.account.customerNumber)
        let hasProfile = !snapshot.account.holderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || (!snapshot.account.supplyAddress.isEmpty && snapshot.account.supplyAddress != "—")
        let hasInvoices = !snapshot.invoices.isEmpty

        guard let finalId, hasProfile || hasInvoices else {
            account.customerNumber = "—"
            // Vínculo viejo/erróneo: soltarlo para no reinyectar un N° ajeno.
            if let email { LinkedAccountStore.unbind(email: email) }
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

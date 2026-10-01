import Foundation

struct MetrogasDataSnapshot: Sendable {
    var account: AccountProfile
    var invoices: [Invoice]
    var readings: [ConsumptionReading]
}

/// Sincroniza datos de MetroGAS.
/// Login por N° de cliente → M360 saldos (misma fuente que “Tu Factura” web).
actor MetrogasDataService {
    static let shared = MetrogasDataService()

    private init() {}

    /// Carga titular/facturas/consumo solo con el N° de cliente (11 dígitos).
    func fetchByCustomerNumber(_ customerNumber: String) async throws -> MetrogasDataSnapshot {
        guard let id = MetrogasURLs.normalizedCustomerNumber(customerNumber) else {
            throw MetrogasAuthError.unexpectedResponse
        }

        let snapshot = try await PortalDataBridge.shared.sync(
            accountId: id,
            loginHint: nil,
            timeoutSeconds: 6
        )

        var account = AccountProfile.empty
        account = MetrogasJSONParser.mergeAccount(account, snapshot.account)
        account.customerNumber = id
        // Completar localidad/CP desde la dirección si billing no los mandó sueltos.
        if (account.locality == "—" || account.locality.isEmpty),
           account.supplyAddress != "—", !account.supplyAddress.isEmpty {
            let enriched = MetrogasJSONParser.enrichAccountFromAnyJSON(
                ["PVE_DIRECCION": account.supplyAddress],
                into: account
            )
            account = MetrogasJSONParser.mergeAccount(account, enriched)
            account.customerNumber = id
        }

        var invoices = snapshot.invoices
        var readings = snapshot.readings
        if readings.isEmpty && !invoices.isEmpty {
            readings = MetrogasJSONParser.deriveReadings(from: invoices)
        }

        return MetrogasDataSnapshot(account: account, invoices: invoices, readings: readings)
    }

    /// Flujo legacy portal+Google (se mantiene por si se reutiliza).
    func fetchAccountData(loginHint: String?, preferredAccountId: String?) async throws -> MetrogasDataSnapshot {
        if let preferred = MetrogasURLs.normalizedCustomerNumber(preferredAccountId ?? "") {
            return try await fetchByCustomerNumber(preferred)
        }

        LinkedAccountStore.migrateIfNeeded()
        let identity = await MetrogasAuthService.shared.resolveSignedInIdentity()
        let email: String? = {
            if let loginHint, !loginHint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return loginHint
            }
            return identity.email
        }()

        for _ in 0..<12 {
            if await MetrogasAuthService.shared.probePortalSession() { break }
            try? await Task.sleep(nanoseconds: 400_000_000)
        }

        let preferredHint = LinkedAccountStore.customerNumber(forEmail: email)
        let snapshot = try await PortalDataBridge.shared.syncFromSession(
            loginHint: email,
            preferredAccountId: preferredHint,
            forcePortalDiscovery: true,
            timeoutSeconds: 40
        )

        var account = AccountProfile.empty
        if let email, !email.isEmpty { account.email = email }
        account = MetrogasJSONParser.mergeAccount(account, snapshot.account)

        guard let finalId = MetrogasURLs.normalizedCustomerNumber(snapshot.account.customerNumber),
              !snapshot.account.holderName.isEmpty || !snapshot.invoices.isEmpty
                || (!snapshot.account.supplyAddress.isEmpty && snapshot.account.supplyAddress != "—")
        else {
            account.customerNumber = "—"
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
}

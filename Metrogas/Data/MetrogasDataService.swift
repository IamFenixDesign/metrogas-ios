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

        // Esperar sesión de portal usable (crítico tras Google OAuth).
        for _ in 0..<8 {
            if await MetrogasAuthService.shared.probePortalSession() { break }
            try? await Task.sleep(nanoseconds: 400_000_000)
        }

        // Hint: solo vínculo confirmado. Nunca scrapes.
        let preferredHint = MetrogasURLs.normalizedCustomerNumber(preferredAccountId ?? "")
            ?? LinkedAccountStore.customerNumber(forEmail: email)

        // Discovery siempre; preferred solo si el portal lo lista como candidato.
        let snapshot = try await PortalDataBridge.shared.syncFromSession(
            loginHint: email,
            preferredAccountId: preferredHint,
            forcePortalDiscovery: true,
            timeoutSeconds: 40
        )

        var account = seedAccount(loginHint: email, customerNumber: nil)
        account = MetrogasJSONParser.mergeAccount(account, snapshot.account)

        let finalId = MetrogasURLs.normalizedCustomerNumber(snapshot.account.customerNumber)
        let finalProfile = !snapshot.account.holderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let finalAddress = !snapshot.account.supplyAddress.isEmpty && snapshot.account.supplyAddress != "—"
        let finalInvoices = !snapshot.invoices.isEmpty
        let ownershipOK = emailOwnershipAllowsBind(loginHint: email, accountEmail: snapshot.account.email)
        let finalConfirmed = finalId != nil
            && (finalProfile || finalAddress || finalInvoices)
            && ownershipOK

        if let email, !email.isEmpty {
            account.email = email
        }

        guard let finalId, finalConfirmed else {
            account.customerNumber = "—"
            if let email { LinkedAccountStore.unbind(email: email) }
            // Sin confirmación de sesión/email: no mostrar datos ajenos.
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

    /// Si hay email de login y email de cuenta/subscription, deben coincidir.
    private func emailOwnershipAllowsBind(loginHint: String?, accountEmail: String) -> Bool {
        let login = loginHint?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let account = accountEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard login.contains("@"), account.contains("@") else {
            // Sin email de cuenta no podemos negar; discovery de sesión ya filtró candidatos.
            return true
        }
        return login == account
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

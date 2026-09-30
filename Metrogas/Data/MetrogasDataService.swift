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
        var portalReady = false
        for _ in 0..<16 {
            if await MetrogasAuthService.shared.probePortalSession() {
                portalReady = true
                break
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
        }

        // Si el email Google/MetroGAS ya tiene N° vinculado → cargar esa cuenta al toque.
        let preferredHint = MetrogasURLs.normalizedCustomerNumber(preferredAccountId ?? "")
            ?? LinkedAccountStore.customerNumber(forEmail: email)

        if let preferredHint, portalReady {
            let quick = try await PortalDataBridge.shared.syncFromSession(
                loginHint: email,
                preferredAccountId: preferredHint,
                forcePortalDiscovery: false,
                timeoutSeconds: 22
            )
            if let completed = completedSnapshot(quick, email: email, fallbackId: preferredHint) {
                LinkedAccountStore.bind(email: email, customerNumber: completed.account.customerNumber)
                return completed
            }
        }

        // Discovery en portal; si el email de factura digital coincide con el login → auto-vínculo.
        var snapshot = try await PortalDataBridge.shared.syncFromSession(
            loginHint: email,
            preferredAccountId: preferredHint,
            forcePortalDiscovery: true,
            timeoutSeconds: 44
        )

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

        if let completed = completedSnapshot(snapshot, email: email, fallbackId: preferredHint) {
            LinkedAccountStore.bind(email: email, customerNumber: completed.account.customerNumber)
            return completed
        }

        var account = seedAccount(loginHint: email, customerNumber: nil)
        account = MetrogasJSONParser.mergeAccount(account, snapshot.account)
        if let email, !email.isEmpty { account.email = email }
        account.customerNumber = "—"
        return MetrogasDataSnapshot(account: account, invoices: [], readings: [])
    }

    /// Confirma N° + perfil/facturas y deja el email de login (Google) en la cuenta.
    private func completedSnapshot(
        _ snapshot: MetrogasDataSnapshot,
        email: String?,
        fallbackId: String?
    ) -> MetrogasDataSnapshot? {
        var account = seedAccount(loginHint: email, customerNumber: nil)
        account = MetrogasJSONParser.mergeAccount(account, snapshot.account)

        let finalId = MetrogasURLs.normalizedCustomerNumber(snapshot.account.customerNumber)
            ?? MetrogasURLs.normalizedCustomerNumber(fallbackId ?? "")
        let finalProfile = !snapshot.account.holderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let finalAddress = !snapshot.account.supplyAddress.isEmpty && snapshot.account.supplyAddress != "—"
        let finalInvoices = !snapshot.invoices.isEmpty
        guard let finalId, finalProfile || finalAddress || finalInvoices else { return nil }

        account.customerNumber = finalId
        if let email, !email.isEmpty { account.email = email }

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

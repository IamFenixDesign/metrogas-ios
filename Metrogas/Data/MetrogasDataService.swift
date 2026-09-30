import Foundation

struct MetrogasDataSnapshot: Sendable {
    var account: AccountProfile
    var invoices: [Invoice]
    var readings: [ConsumptionReading]
}

/// Sincroniza con Oficina Virtual (Google o MetroGAS) vía M360 saldos.
actor MetrogasDataService {
    static let shared = MetrogasDataService()

    private init() {}

    func fetchAccountData(loginHint: String?, preferredAccountId: String?) async throws -> MetrogasDataSnapshot {
        let identity = await MetrogasAuthService.shared.resolveSignedInIdentity()
        let email: String? = {
            if let loginHint, !loginHint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return loginHint
            }
            return identity.email
        }()

        // Preferir solo N° ya vinculado al email o etiquetado; nunca dígitos sueltos de cookies.
        let preferred =
            MetrogasURLs.normalizedCustomerNumber(preferredAccountId ?? "")
            ?? identity.customerNumber

        var account = seedAccount(loginHint: email, customerNumber: preferred)
        let hasLinkedId = preferred != nil

        var snapshot = try await PortalDataBridge.shared.syncFromSession(
            loginHint: email,
            preferredAccountId: preferred,
            timeoutSeconds: hasLinkedId ? 18 : 26
        )

        // Si el N° vinculado no trajo perfil/facturas, fue un vínculo basura → rediscovery.
        let linkedLooksEmpty = hasLinkedId
            && snapshot.invoices.isEmpty
            && snapshot.account.holderName.isEmpty
            && (snapshot.account.supplyAddress.isEmpty || snapshot.account.supplyAddress == "—")

        if linkedLooksEmpty, let email {
            LinkedAccountStore.unbind(email: email)
            snapshot = try await PortalDataBridge.shared.syncFromSession(
                loginHint: email,
                preferredAccountId: nil,
                timeoutSeconds: 26
            )
        }

        account = MetrogasJSONParser.mergeAccount(account, snapshot.account)
        if let id = MetrogasURLs.normalizedCustomerNumber(snapshot.account.customerNumber) {
            account.customerNumber = id
        } else if !linkedLooksEmpty, let preferred {
            account.customerNumber = preferred
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

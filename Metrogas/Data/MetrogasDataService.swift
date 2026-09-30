import Foundation

struct MetrogasDataSnapshot: Sendable {
    var account: AccountProfile
    var invoices: [Invoice]
    var readings: [ConsumptionReading]
}

/// Sincroniza con Oficina Virtual (Google o MetroGAS) vía M360 saldos.
actor MetrogasDataService {
    static let shared = MetrogasDataService()

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.timeoutIntervalForRequest = 18
        session = URLSession(configuration: config)
    }

    func fetchAccountData(loginHint: String?, preferredAccountId: String?) async throws -> MetrogasDataSnapshot {
        // Identidad rápida desde cookies/HTML (Google) sin WebView.
        let identity = await MetrogasAuthService.shared.resolveSignedInIdentity()
        let email: String? = {
            if let loginHint, !loginHint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return loginHint
            }
            return identity.email
        }()

        let preferred =
            MetrogasURLs.normalizedCustomerNumber(preferredAccountId ?? "")
            ?? identity.customerNumber

        var account = seedAccount(loginHint: email, customerNumber: preferred)
        let hasLinkedId = preferred != nil

        // Camino rápido: N° ya conocido → solo M360 (sin discovery ni warm-up de portal).
        let snapshot = try await PortalDataBridge.shared.syncFromSession(
            loginHint: email,
            preferredAccountId: preferred,
            timeoutSeconds: hasLinkedId ? 16 : 22
        )

        account = MetrogasJSONParser.mergeAccount(account, snapshot.account)
        if let id = MetrogasURLs.normalizedCustomerNumber(snapshot.account.customerNumber)
            ?? preferred {
            account.customerNumber = id
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
        // Solo email de login: el titular real viene de M360 (PVE_TITULAR).
        if let loginHint, !loginHint.isEmpty {
            account.email = loginHint
        }
        return account
    }
}

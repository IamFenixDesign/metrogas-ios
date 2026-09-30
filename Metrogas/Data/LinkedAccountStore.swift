import Foundation

/// Vincula el email de login (Google o MetroGAS) con el N° de cliente
/// para que, al volver a entrar con la misma cuenta, la info cargue sola.
enum LinkedAccountStore {
    private static let prefix = "metrogas.linkedCustomer."
    private static let lastEmailKey = "metrogas.linkedCustomer.lastEmail"
    private static let globalCustomerKey = "metrogas.account.customerNumber"

    static func customerNumber(forEmail email: String?) -> String? {
        guard let key = storageKey(for: email) else { return nil }
        guard let raw = UserDefaults.standard.string(forKey: key) else { return nil }
        return MetrogasURLs.normalizedCustomerNumber(raw)
    }

    static func bind(email: String?, customerNumber: String) {
        guard let normalized = MetrogasURLs.normalizedCustomerNumber(customerNumber) else { return }
        guard let key = storageKey(for: email), let email = normalizedEmail(email) else {
            // Sin email no guardamos un N° “global” reutilizable entre cuentas.
            return
        }
        UserDefaults.standard.set(normalized, forKey: key)
        UserDefaults.standard.set(normalized, forKey: globalCustomerKey)
        UserDefaults.standard.set(email, forKey: lastEmailKey)
    }

    /// Quita un vínculo erróneo (p. ej. N° inventado por scrape) para forzar rediscovery.
    static func unbind(email: String?) {
        guard let key = storageKey(for: email), let email = normalizedEmail(email) else { return }
        UserDefaults.standard.removeObject(forKey: key)
        if lastBoundEmail()?.lowercased() == email {
            UserDefaults.standard.removeObject(forKey: lastEmailKey)
            UserDefaults.standard.removeObject(forKey: globalCustomerKey)
        }
    }

    static func lastBoundEmail() -> String? {
        UserDefaults.standard.string(forKey: lastEmailKey)
    }

    /// Solo el N° ligado a ESTE email (o el fallback explícito ya normalizado).
    /// No reutiliza el último N° del dispositivo si el email no tiene vínculo:
    /// eso mezclaba cuentas Google/MetroGAS distintas.
    static func resolvePreferredCustomerNumber(loginEmail: String?, fallback: String?) -> String? {
        if let linked = customerNumber(forEmail: loginEmail) {
            return linked
        }
        if let loginEmail, normalizedEmail(loginEmail) != nil {
            // Email conocido pero sin vínculo → no inventar con el N° de otra cuenta.
            return MetrogasURLs.normalizedCustomerNumber(fallback ?? "")
        }
        return MetrogasURLs.normalizedCustomerNumber(fallback ?? "")
    }

    private static func storageKey(for email: String?) -> String? {
        guard let email = normalizedEmail(email) else { return nil }
        return prefix + email
    }

    private static func normalizedEmail(_ email: String?) -> String? {
        let trimmed = email?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        guard trimmed.contains("@"), trimmed.count >= 5 else { return nil }
        return trimmed
    }
}

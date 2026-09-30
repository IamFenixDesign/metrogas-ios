import Foundation

/// Guarda el N° de cliente MetroGAS usado en la app.
/// Login actual: solo N° (11 dígitos). El vínculo por email queda como legado.
enum LinkedAccountStore {
    private static let prefix = "metrogas.linkedCustomer."
    private static let confirmedPrefix = "metrogas.linkedCustomer.confirmed."
    private static let lastEmailKey = "metrogas.linkedCustomer.lastEmail"
    private static let globalCustomerKey = "metrogas.account.customerNumber"
    private static let schemaKey = "metrogas.linkedCustomer.schemaVersion"
    /// Subir esto limpia vínculos viejos/envenenados una vez por dispositivo.
    /// 6: login por N° de cliente — descarta vínculos Google/email previos.
    private static let currentSchema = 6

    /// Migración: borra vínculos previos al esquema actual (scrapes / fast-path erróneos).
    static func migrateIfNeeded() {
        let stored = UserDefaults.standard.integer(forKey: schemaKey)
        guard stored < currentSchema else { return }
        clearAllBindings()
        UserDefaults.standard.set(currentSchema, forKey: schemaKey)
    }

    static func customerNumber(forEmail email: String?) -> String? {
        migrateIfNeeded()
        guard let email = normalizedEmail(email) else { return nil }
        // Solo devolver vínculos confirmados por billing.
        let confirmedKey = confirmedPrefix + email
        if let raw = UserDefaults.standard.string(forKey: confirmedKey),
           let normalized = MetrogasURLs.normalizedCustomerNumber(raw) {
            return normalized
        }
        return nil
    }

    /// Guarda N° solo tras confirmación M360 (titular/billing) o ingreso manual.
    static func bind(email: String?, customerNumber: String) {
        migrateIfNeeded()
        guard let normalized = MetrogasURLs.normalizedCustomerNumber(customerNumber) else { return }
        UserDefaults.standard.set(normalized, forKey: globalCustomerKey)
        guard let email = normalizedEmail(email) else { return }
        UserDefaults.standard.set(normalized, forKey: prefix + email)
        UserDefaults.standard.set(normalized, forKey: confirmedPrefix + email)
        UserDefaults.standard.set(email, forKey: lastEmailKey)
    }

    /// Login directo por N° de cliente (sin email Google/MetroGAS).
    static func bindCustomerOnly(_ customerNumber: String) {
        migrateIfNeeded()
        guard let normalized = MetrogasURLs.normalizedCustomerNumber(customerNumber) else { return }
        UserDefaults.standard.set(normalized, forKey: globalCustomerKey)
    }

    static func lastCustomerNumber() -> String? {
        migrateIfNeeded()
        return MetrogasURLs.normalizedCustomerNumber(
            UserDefaults.standard.string(forKey: globalCustomerKey) ?? ""
        )
    }

    /// Quita un vínculo erróneo para forzar rediscovery en el portal.
    static func unbind(email: String?) {
        migrateIfNeeded()
        guard let email = normalizedEmail(email) else { return }
        UserDefaults.standard.removeObject(forKey: prefix + email)
        UserDefaults.standard.removeObject(forKey: confirmedPrefix + email)
        if lastBoundEmail()?.lowercased() == email {
            UserDefaults.standard.removeObject(forKey: lastEmailKey)
            UserDefaults.standard.removeObject(forKey: globalCustomerKey)
        }
    }

    static func clearAllBindings() {
        let defaults = UserDefaults.standard
        let all = defaults.dictionaryRepresentation()
        for key in all.keys where key.hasPrefix(prefix) || key.hasPrefix(confirmedPrefix) {
            defaults.removeObject(forKey: key)
        }
        defaults.removeObject(forKey: lastEmailKey)
        defaults.removeObject(forKey: globalCustomerKey)
    }

    static func lastBoundEmail() -> String? {
        UserDefaults.standard.string(forKey: lastEmailKey)
    }

    /// Solo el N° confirmado ligado a ESTE email (o el fallback ya normalizado).
    static func resolvePreferredCustomerNumber(loginEmail: String?, fallback: String?) -> String? {
        migrateIfNeeded()
        if let linked = customerNumber(forEmail: loginEmail) {
            return linked
        }
        if let loginEmail, normalizedEmail(loginEmail) != nil {
            // Email conocido pero sin vínculo confirmado → no inventar con otro N°.
            return MetrogasURLs.normalizedCustomerNumber(fallback ?? "")
        }
        return MetrogasURLs.normalizedCustomerNumber(fallback ?? "")
    }

    private static func normalizedEmail(_ email: String?) -> String? {
        let trimmed = email?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        guard trimmed.contains("@"), trimmed.count >= 5 else { return nil }
        return trimmed
    }
}

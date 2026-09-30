import Foundation

/// Vincula el email de login (Google o MetroGAS) con el N° de cliente
/// para que, al volver a entrar, la info cargue sola.
enum LinkedAccountStore {
    private static let prefix = "metrogas.linkedCustomer."
    private static let lastEmailKey = "metrogas.linkedCustomer.lastEmail"

    static func customerNumber(forEmail email: String?) -> String? {
        guard let key = storageKey(for: email) else { return nil }
        guard let raw = UserDefaults.standard.string(forKey: key) else { return nil }
        return MetrogasURLs.normalizedCustomerNumber(raw)
    }

    static func bind(email: String?, customerNumber: String) {
        guard let normalized = MetrogasURLs.normalizedCustomerNumber(customerNumber) else { return }
        guard let key = storageKey(for: email) else {
            UserDefaults.standard.set(normalized, forKey: "metrogas.account.customerNumber")
            return
        }
        UserDefaults.standard.set(normalized, forKey: key)
        UserDefaults.standard.set(normalized, forKey: "metrogas.account.customerNumber")
        if let email = normalizedEmail(email) {
            UserDefaults.standard.set(email, forKey: lastEmailKey)
        }
    }

    static func lastBoundEmail() -> String? {
        UserDefaults.standard.string(forKey: lastEmailKey)
    }

    /// Resuelve el N° asociado a este login, o el último conocido del dispositivo.
    static func resolvePreferredCustomerNumber(loginEmail: String?, fallback: String?) -> String? {
        if let linked = customerNumber(forEmail: loginEmail) { return linked }
        if let fallback, let n = MetrogasURLs.normalizedCustomerNumber(fallback) { return n }
        if let global = UserDefaults.standard.string(forKey: "metrogas.account.customerNumber"),
           let n = MetrogasURLs.normalizedCustomerNumber(global) {
            return n
        }
        return nil
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

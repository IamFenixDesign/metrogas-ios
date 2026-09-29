import Foundation
import Security

/// Guarda email/contraseña en Keychain para revalidar la sesión al reabrir la app.
enum CredentialStore {
    private static let service = "ar.com.metrogas.demo.credentials"
    private static let accountKey = "oficina-virtual"

    struct Credentials: Equatable {
        let email: String
        let password: String
    }

    static func save(email: String, password: String) {
        let payload = ["email": email, "password": password]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountKey
        ]
        SecItemDelete(query as CFDictionary)

        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    static func load() -> Credentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let email = json["email"], !email.isEmpty,
              let password = json["password"], !password.isEmpty else {
            return nil
        }
        return Credentials(email: email, password: password)
    }

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountKey
        ]
        SecItemDelete(query as CFDictionary)
    }
}

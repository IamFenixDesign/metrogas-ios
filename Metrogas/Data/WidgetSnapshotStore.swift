import Foundation

/// Snapshot compartido con widgets.
/// Usa App Group si el dispositivo lo permite; si no, escribe también en un
/// archivo del contenedor del grupo (nil sin entitlement) y en UserDefaults
/// estándar como respaldo local.
enum WidgetSnapshotStore {
    static let appGroupID = "group.ar.com.metrogas.demo"
    private static let key = "widget.invoices.v1"
    private static let fileName = "widget-invoices-v1.json"

    struct Item: Codable, Identifiable, Hashable {
        let id: String
        let number: String
        let periodLabel: String
        let amountText: String
        let statusLabel: String
        let dueDateText: String
        let issuedAt: Date
    }

    struct Snapshot: Codable, Hashable {
        var updatedAt: Date
        var items: [Item]

        var newest: Item? {
            items.sorted { $0.issuedAt > $1.issuedAt }.first
        }
    }

    private static var suiteDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    private static var sharedFileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(fileName)
    }

    static func save(_ snapshot: Snapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }

        // App Group suite (compartido cuando hay entitlement + provisioning).
        suiteDefaults.set(data, forKey: key)
        suiteDefaults.synchronize()

        // Respaldo en UserDefaults de la app (útil si el grupo no está activo).
        UserDefaults.standard.set(data, forKey: key)

        if let url = sharedFileURL {
            try? data.write(to: url, options: .atomic)
        }
    }

    static func load() -> Snapshot? {
        if let data = suiteDefaults.data(forKey: key),
           let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
            return snapshot
        }
        if let url = sharedFileURL,
           let data = try? Data(contentsOf: url),
           let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
            return snapshot
        }
        if let data = UserDefaults.standard.data(forKey: key),
           let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
            return snapshot
        }
        return nil
    }

    static func clear() {
        suiteDefaults.removeObject(forKey: key)
        suiteDefaults.synchronize()
        UserDefaults.standard.removeObject(forKey: key)
        if let url = sharedFileURL {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

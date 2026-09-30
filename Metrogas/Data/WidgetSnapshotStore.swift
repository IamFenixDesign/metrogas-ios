import Foundation

/// Snapshot compartido con widgets vía App Group.
enum WidgetSnapshotStore {
    static let appGroupID = "group.ar.com.metrogas.demo"
    private static let key = "widget.invoices.v1"

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

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    static func save(_ snapshot: Snapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
        defaults.synchronize()
    }

    static func load() -> Snapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    static func clear() {
        defaults.removeObject(forKey: key)
        defaults.synchronize()
    }
}

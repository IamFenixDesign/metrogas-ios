import Foundation

enum AppNotificationKind: String, Codable, CaseIterable {
    case newInvoice
    case dueReminder
    case test
    case general

    var systemImage: String {
        switch self {
        case .newInvoice: return "doc.text.fill"
        case .dueReminder: return "bell.fill"
        case .test: return "bell.badge.fill"
        case .general: return "app.badge.fill"
        }
    }

    var label: String {
        switch self {
        case .newInvoice: return "Factura nueva"
        case .dueReminder: return "Vencimiento"
        case .test: return "Prueba"
        case .general: return "Aviso"
        }
    }

    static func infer(fromIdentifier id: String) -> AppNotificationKind {
        if id.hasPrefix("new-invoice") || id.hasPrefix("new-invoices") { return .newInvoice }
        if id.hasPrefix("test-new-invoice") { return .test }
        if id.hasPrefix("due-") { return .dueReminder }
        return .general
    }
}

struct AppNotificationItem: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let title: String
    let body: String
    let createdAt: Date
    var isRead: Bool
    let kind: AppNotificationKind

    init(
        id: String = UUID().uuidString,
        title: String,
        body: String,
        createdAt: Date = Date(),
        isRead: Bool = false,
        kind: AppNotificationKind = .general
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.createdAt = createdAt
        self.isRead = isRead
        self.kind = kind
    }
}

import Foundation
import UserNotifications
import Combine

/// Recordatorios locales nativos de iOS (`UNUserNotificationCenter`).
@MainActor
final class ReminderService: NSObject, ObservableObject {
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published var remindersEnabled: Bool {
        didSet {
            UserDefaults.standard.set(remindersEnabled, forKey: Keys.enabled)
        }
    }
    /// Avisar cuando aparece una factura nueva tras sincronizar.
    @Published var newInvoiceAlertsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(newInvoiceAlertsEnabled, forKey: Keys.newInvoiceAlerts)
        }
    }
    /// Días antes del vencimiento (1–7).
    @Published var daysBeforeDue: Int {
        didSet { UserDefaults.standard.set(daysBeforeDue, forKey: Keys.daysBefore) }
    }
    @Published private(set) var lastTestNotificationAt: Date?
    @Published var testNotificationMessage: String?

    private enum Keys {
        static let enabled = "metrogas.reminders.enabled"
        static let daysBefore = "metrogas.reminders.daysBefore"
        static let newInvoiceAlerts = "metrogas.reminders.newInvoiceAlerts"
        static let knownInvoiceIDs = "metrogas.reminders.knownInvoiceIDs"
    }

    override init() {
        remindersEnabled = UserDefaults.standard.object(forKey: Keys.enabled) as? Bool ?? true
        newInvoiceAlertsEnabled = UserDefaults.standard.object(forKey: Keys.newInvoiceAlerts) as? Bool ?? true
        let stored = UserDefaults.standard.object(forKey: Keys.daysBefore) as? Int ?? 3
        daysBeforeDue = min(max(stored, 1), 7)
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    /// Pide el permiso nativo de iOS al entrar a la app (solo si aún no se decidió).
    @discardableResult
    func requestPermissionOnLaunch() async -> Bool {
        await refreshAuthorizationStatus()
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                let granted = try await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound, .badge])
                await refreshAuthorizationStatus()
                return granted
            } catch {
                await refreshAuthorizationStatus()
                return false
            }
        @unknown default:
            return false
        }
    }

    @discardableResult
    func requestPermissionIfNeeded() async -> Bool {
        await requestPermissionOnLaunch()
    }

    var isAuthorized: Bool {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

    func reschedule(for invoices: [Invoice]) async {
        let center = UNUserNotificationCenter.current()
        // Conservar notificaciones de “factura nueva” ya disparadas; limpia solo vencimientos.
        let pending = await center.pendingNotificationRequests()
        let dueIDs = pending
            .map(\.identifier)
            .filter { $0.hasPrefix("due-before-") || $0.hasPrefix("due-day-") }
        center.removePendingNotificationRequests(withIdentifiers: dueIDs)

        guard remindersEnabled else { return }
        let granted = await requestPermissionIfNeeded()
        guard granted else { return }

        let calendar = Calendar.current
        let unpaid = invoices.filter { $0.status == .pending || $0.status == .overdue }

        for invoice in unpaid {
            guard let remindDay = calendar.date(byAdding: .day, value: -daysBeforeDue, to: invoice.dueDate) else {
                continue
            }
            var components = calendar.dateComponents([.year, .month, .day], from: remindDay)
            components.hour = 10
            components.minute = 0

            var dueComponents = calendar.dateComponents([.year, .month, .day], from: invoice.dueDate)
            dueComponents.hour = 9
            dueComponents.minute = 0

            schedule(
                id: "due-before-\(invoice.id)",
                title: "Vence pronto tu factura MetroGAS",
                body: "\(invoice.number) por \(Formatters.money(invoice.amountARS)) vence el \(DateFormatter.metrogasDayMonthYear.string(from: invoice.dueDate)).",
                components: components,
                center: center
            )

            schedule(
                id: "due-day-\(invoice.id)",
                title: "Hoy vence tu factura MetroGAS",
                body: "Recordá pagar \(Formatters.money(invoice.amountARS)) (\(invoice.number)).",
                components: dueComponents,
                center: center
            )
        }
    }

    /// Detecta facturas nuevas tras un sync y manda notificación local.
    /// La primera vez solo guarda el set (sin spamear el historial).
    func notifyNewInvoices(from invoices: [Invoice]) async {
        let currentIDs = Set(invoices.map(\.id))
        let previous = Set(UserDefaults.standard.stringArray(forKey: Keys.knownInvoiceIDs) ?? [])
        UserDefaults.standard.set(Array(currentIDs), forKey: Keys.knownInvoiceIDs)

        guard newInvoiceAlertsEnabled else { return }
        guard !previous.isEmpty else { return } // seed inicial

        let freshIDs = currentIDs.subtracting(previous)
        guard !freshIDs.isEmpty else { return }

        let fresh = invoices
            .filter { freshIDs.contains($0.id) }
            .sorted { $0.issuedDate > $1.issuedDate }

        let granted = await requestPermissionIfNeeded()
        guard granted else { return }

        if fresh.count == 1, let invoice = fresh.first {
            await postImmediate(
                id: "new-invoice-\(invoice.id)-\(Int(Date().timeIntervalSince1970))",
                title: "Nueva factura MetroGAS",
                body: "\(invoice.number) por \(Formatters.money(invoice.amountARS)). Vence el \(DateFormatter.metrogasDayMonthYear.string(from: invoice.dueDate))."
            )
        } else if let first = fresh.first {
            await postImmediate(
                id: "new-invoices-\(Int(Date().timeIntervalSince1970))",
                title: "Nuevas facturas MetroGAS",
                body: "Llegaron \(fresh.count) facturas. La más reciente es \(first.number) por \(Formatters.money(first.amountARS))."
            )
        }
    }

    /// Botón de prueba: dispara una notificación de “nueva factura” en 1 segundo.
    func sendTestNewInvoiceNotification() async {
        testNotificationMessage = nil
        let granted = await requestPermissionIfNeeded()
        guard granted else {
            testNotificationMessage = "Activá las notificaciones en Ajustes → Metrogas."
            return
        }

        await postImmediate(
            id: "test-new-invoice-\(Int(Date().timeIntervalSince1970))",
            title: "Nueva factura MetroGAS",
            body: "Prueba: tenés una nueva factura disponible. Abrí la app para verla y pagarla.",
            delaySeconds: 1
        )
        lastTestNotificationAt = Date()
        testNotificationMessage = "Notificación de prueba enviada. Debería aparecer en ~1s."
    }

    private func postImmediate(
        id: String,
        title: String,
        body: String,
        delaySeconds: TimeInterval = 0.2
    ) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.badge = NSNumber(value: 1)
        content.categoryIdentifier = "NEW_INVOICE"

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(delaySeconds, 0.1),
            repeats: false
        )
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
    }

    private func schedule(
        id: String,
        title: String,
        body: String,
        components: DateComponents,
        center: UNUserNotificationCenter
    ) {
        if let fire = Calendar.current.date(from: components), fire < Date() {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.badge = NSNumber(value: 1)

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        center.add(request)
    }
}

extension ReminderService: UNUserNotificationCenterDelegate {
    /// Muestra banner/sonido nativos también con la app abierta.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound, .badge]
    }
}

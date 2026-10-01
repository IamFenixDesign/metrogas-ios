import SwiftUI
import UIKit

@main
struct MetrogasApp: App {
    @StateObject private var session = AppSession()
    @StateObject private var store = AccountDataStore()
    @StateObject private var reminders = ReminderService()

    init() {
        Self.configureNavigationBar()
    }

    var body: some Scene {
        WindowGroup {
            RootContainerView()
                .environmentObject(session)
                .environmentObject(store)
                .environmentObject(reminders)
                .preferredColorScheme(session.preferredColorScheme)
        }
    }

    /// Nav bar siempre transparente: evita la franja negra/opaca al cambiar de tab
    /// (el fondo liquid glass del root queda visible debajo).
    private static func configureNavigationBar() {
        let clear = UINavigationBarAppearance()
        clear.configureWithTransparentBackground()
        clear.backgroundColor = .clear
        clear.backgroundEffect = nil
        clear.shadowColor = .clear
        clear.largeTitleTextAttributes = [
            .foregroundColor: UIColor.label
        ]
        clear.titleTextAttributes = [
            .foregroundColor: UIColor.label
        ]

        let nav = UINavigationBar.appearance()
        nav.standardAppearance = clear
        nav.compactAppearance = clear
        nav.scrollEdgeAppearance = clear
        nav.compactScrollEdgeAppearance = clear
        nav.isTranslucent = true
        nav.prefersLargeTitles = true
    }
}

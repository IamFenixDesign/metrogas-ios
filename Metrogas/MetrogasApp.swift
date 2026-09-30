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

    /// Large title sin fondo al tope; al scrollear se achica con barra estándar (estilo WhatsApp/Instagram).
    private static func configureNavigationBar() {
        let clear = UINavigationBarAppearance()
        clear.configureWithTransparentBackground()
        clear.backgroundColor = .clear
        clear.shadowColor = .clear
        clear.largeTitleTextAttributes = [
            .foregroundColor: UIColor.label
        ]
        clear.titleTextAttributes = [
            .foregroundColor: UIColor.label
        ]

        let scrolled = UINavigationBarAppearance()
        scrolled.configureWithDefaultBackground()
        scrolled.shadowColor = .clear
        scrolled.largeTitleTextAttributes = [
            .foregroundColor: UIColor.label
        ]
        scrolled.titleTextAttributes = [
            .foregroundColor: UIColor.label
        ]

        let nav = UINavigationBar.appearance()
        nav.standardAppearance = scrolled
        nav.compactAppearance = scrolled
        nav.scrollEdgeAppearance = clear
        nav.compactScrollEdgeAppearance = clear
        nav.prefersLargeTitles = true
    }
}

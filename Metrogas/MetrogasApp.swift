import SwiftUI

@main
struct MetrogasApp: App {
    @StateObject private var session = AppSession()
    @StateObject private var store = AccountDataStore()
    @StateObject private var reminders = ReminderService()

    var body: some Scene {
        WindowGroup {
            RootContainerView()
                .environmentObject(session)
                .environmentObject(store)
                .environmentObject(reminders)
                .preferredColorScheme(session.preferredColorScheme)
        }
    }
}

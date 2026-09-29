import SwiftUI

@main
struct MetrogasApp: App {
    @StateObject private var store = MockDataStore()
    @StateObject private var reminders = ReminderService()

    var body: some Scene {
        WindowGroup {
            RootContainerView()
                .environmentObject(store)
                .environmentObject(reminders)
                .preferredColorScheme(store.preferredColorScheme)
        }
    }
}

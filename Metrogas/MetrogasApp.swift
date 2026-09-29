import SwiftUI

@main
struct MetrogasApp: App {
    @StateObject private var session = AppSession()
    @StateObject private var reminders = ReminderService()

    var body: some Scene {
        WindowGroup {
            RootContainerView()
                .environmentObject(session)
                .environmentObject(reminders)
                .preferredColorScheme(session.preferredColorScheme)
        }
    }
}

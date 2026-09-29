import SwiftUI

@main
struct MetrogasApp: App {
    @StateObject private var store = MockDataStore()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(store)
                .preferredColorScheme(store.preferredColorScheme)
        }
    }
}

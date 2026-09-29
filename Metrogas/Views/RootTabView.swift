import SwiftUI

struct RootTabView: View {
    @EnvironmentObject private var store: MockDataStore

    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Inicio", systemImage: "flame.fill")
                }

            InvoiceListView()
                .tabItem {
                    Label("Facturas", systemImage: "doc.text.fill")
                }

            ConsumptionView()
                .tabItem {
                    Label("Consumo", systemImage: "chart.bar.fill")
                }

            AccountView()
                .tabItem {
                    Label("Cuenta", systemImage: "person.crop.circle")
                }
        }
        .tint(MetrogasTheme.brandBlue)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
    }
}

#Preview {
    RootTabView()
        .environmentObject(MockDataStore())
        .environmentObject(ReminderService())
}

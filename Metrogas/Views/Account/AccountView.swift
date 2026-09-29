import SwiftUI

struct AccountView: View {
    @EnvironmentObject private var store: MockDataStore
    @State private var showResetAlert = false

    var body: some View {
        NavigationStack {
            ZStack {
                MetrogasBackground()

                List {
                    Section {
                        profileHeader
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    }

                    Section("Suministro") {
                        labeled("N° de cliente", store.account.customerNumber)
                        labeled("Medidor", store.account.meterNumber)
                        labeled("Categoría", store.account.tariffCategory)
                        labeled("Dirección", store.account.supplyAddress)
                        labeled("Localidad", store.account.locality)
                        labeled("CP", store.account.postalCode)
                    }

                    Section("Contacto") {
                        labeled("Email", store.account.email)
                        labeled("Teléfono", store.account.phone)
                    }

                    Section("Preferencias") {
                        Picker("Apariencia", selection: $store.appearanceMode) {
                            ForEach(MockDataStore.AppearanceMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                    }

                    Section("Demo") {
                        Text("Esta app usa datos de ejemplo Metrogas. No se conecta a la API real.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        Button("Restablecer datos de demostración", role: .destructive) {
                            showResetAlert = true
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Cuenta")
            .alert("¿Restablecer demo?", isPresented: $showResetAlert) {
                Button("Cancelar", role: .cancel) {}
                Button("Restablecer", role: .destructive) {
                    store.resetDemoData()
                }
            } message: {
                Text("Se volverán a cargar facturas, consumo y notas de ejemplo.")
            }
        }
    }

    private var profileHeader: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(MetrogasTheme.brandBlue.opacity(0.15))
                    .frame(width: 64, height: 64)
                Text(initials)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(MetrogasTheme.brandBlue)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(store.account.holderName)
                    .font(.title3.weight(.semibold))
                Text("Titular del servicio")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var initials: String {
        let parts = store.account.holderName.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first.map(String.init) }
        return letters.joined().uppercased()
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body.weight(.medium))
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    AccountView()
        .environmentObject(MockDataStore())
}

import SwiftUI

struct AccountView: View {
    @EnvironmentObject private var store: MockDataStore
    @EnvironmentObject private var reminders: ReminderService
    @State private var showResetAlert = false
    @State private var permissionMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                MetrogasBackground()

                List {
                    Section {
                        VStack(spacing: 14) {
                            MetrogasLogo(height: 32, alignment: .center)
                                .frame(maxWidth: 160)
                            profileHeader
                        }
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

                    Section {
                        Toggle("Recordatorios de vencimiento", isOn: $reminders.remindersEnabled)

                        Stepper(
                            "Avisar \(reminders.daysBeforeDue) día\(reminders.daysBeforeDue == 1 ? "" : "s") antes",
                            value: $reminders.daysBeforeDue,
                            in: 1...7
                        )
                        .disabled(!reminders.remindersEnabled)

                        LabeledContent("Permiso notificaciones") {
                            Text(permissionLabel)
                                .foregroundStyle(.secondary)
                        }

                        Button("Activar notificaciones") {
                            Task {
                                let granted = await reminders.requestPermissionIfNeeded()
                                await reminders.reschedule(for: store.invoices)
                                permissionMessage = granted
                                    ? "Notificaciones activadas. Programamos avisos para tus facturas pendientes."
                                    : "No pudimos activar notificaciones. Revisá Ajustes → Metrogas."
                            }
                        }
                        .disabled(!reminders.remindersEnabled)
                    } header: {
                        Text("Recordatorios")
                    } footer: {
                        Text("Enviamos avisos locales el día del vencimiento y unos días antes. No se usa la API real de MetroGAS.")
                    }

                    Section("Preferencias") {
                        Picker("Apariencia", selection: $store.appearanceMode) {
                            ForEach(MockDataStore.AppearanceMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                    }

                    Section("Demo") {
                        Text("Esta app usa datos de ejemplo MetroGAS. El logo proviene del sitio oficial metrogas.com.ar.")
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
            .task {
                await reminders.refreshAuthorizationStatus()
            }
            .alert("¿Restablecer demo?", isPresented: $showResetAlert) {
                Button("Cancelar", role: .cancel) {}
                Button("Restablecer", role: .destructive) {
                    store.resetDemoData()
                }
            } message: {
                Text("Se volverán a cargar facturas, consumo y notas de ejemplo.")
            }
            .alert("Recordatorios", isPresented: Binding(
                get: { permissionMessage != nil },
                set: { if !$0 { permissionMessage = nil } }
            )) {
                Button("Listo", role: .cancel) { permissionMessage = nil }
            } message: {
                Text(permissionMessage ?? "")
            }
        }
    }

    private var permissionLabel: String {
        switch reminders.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return "Permitido"
        case .denied: return "Denegado"
        case .notDetermined: return "Sin pedir"
        @unknown default: return "—"
        }
    }

    private var profileHeader: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [MetrogasTheme.brandBlue, MetrogasTheme.brandCyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ).opacity(0.18)
                    )
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
        .environmentObject(ReminderService())
}
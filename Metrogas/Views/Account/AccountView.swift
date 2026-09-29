import SwiftUI

struct AccountView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var reminders: ReminderService
    @State private var showLogoutConfirm = false
    @State private var permissionMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                MetrogasBackground()

                List {
                    Section {
                        VStack(spacing: 14) {
                            MetrogasLogo(height: 34, alignment: .center)
                                .frame(maxWidth: 170)
                            Text("Cuenta MetroGAS")
                                .font(.title3.weight(.semibold))
                            Text("Sesión vinculada a la Oficina Virtual oficial")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .listRowBackground(Color.clear)
                    }

                    Section("Oficina Virtual") {
                        Button {
                            session.openPortal()
                        } label: {
                            Label("Abrir portal MetroGAS", systemImage: "safari")
                        }

                        Link(destination: MetrogasURLs.sitioInstitucional) {
                            Label("Sitio web metrogas.com.ar", systemImage: "link")
                        }
                    }

                    Section {
                        Toggle("Recordatorios de vencimiento", isOn: $reminders.remindersEnabled)

                        Stepper(
                            "Avisar \(reminders.daysBeforeDue) día\(reminders.daysBeforeDue == 1 ? "" : "s") antes",
                            value: $reminders.daysBeforeDue,
                            in: 1...7
                        )
                        .disabled(!reminders.remindersEnabled)

                        Button("Activar notificaciones") {
                            Task {
                                let granted = await reminders.requestPermissionIfNeeded()
                                permissionMessage = granted
                                    ? "Notificaciones activadas."
                                    : "Revisá el permiso en Ajustes → Metrogas."
                            }
                        }
                    } header: {
                        Text("Recordatorios")
                    } footer: {
                        Text("Los avisos locales se pueden usar cuando registres vencimientos desde tu gestión en la Oficina Virtual.")
                    }

                    Section("Preferencias") {
                        Picker("Apariencia", selection: $session.appearanceMode) {
                            ForEach(AppSession.AppearanceMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .onChange(of: session.appearanceMode) { _, _ in
                            session.persistAppearance()
                        }
                    }

                    Section {
                        Button("Cerrar sesión", role: .destructive) {
                            showLogoutConfirm = true
                        }
                    } footer: {
                        Text("Al cerrar sesión se eliminan las cookies del portal MetroGAS en este dispositivo.")
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Cuenta")
            .sheet(isPresented: $session.showLoginPortal) {
                NavigationStack {
                    MetrogasPortalScreen(title: "Oficina Virtual", url: session.portalStartURL)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cerrar") { session.showLoginPortal = false }
                            }
                        }
                }
            }
            .alert("¿Cerrar sesión?", isPresented: $showLogoutConfirm) {
                Button("Cancelar", role: .cancel) {}
                Button("Cerrar sesión", role: .destructive) {
                    Task { await session.logout() }
                }
            } message: {
                Text("Vas a salir de tu cuenta real de MetroGAS en esta app.")
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
}

#Preview {
    AccountView()
        .environmentObject(AppSession())
        .environmentObject(ReminderService())
}

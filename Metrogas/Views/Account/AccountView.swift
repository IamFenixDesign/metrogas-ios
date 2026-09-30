import SwiftUI

struct AccountView: View {
    @EnvironmentObject private var store: AccountDataStore
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var reminders: ReminderService
    @State private var showLogoutConfirm = false
    @State private var permissionMessage: String?
    @State private var customerNumberError: String?

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

                    Section {
                        TextField("11 dígitos", text: $store.customerNumberDraft)
                            .keyboardType(.numberPad)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.body.monospacedDigit())
                        if let customerNumberError {
                            Text(customerNumberError)
                                .font(.caption)
                                .foregroundStyle(MetrogasTheme.brandFlame)
                        }
                        Button("Guardar y sincronizar") {
                            if store.saveCustomerNumber(store.customerNumberDraft) {
                                customerNumberError = nil
                                Task { await store.refresh(loginHint: session.loginEmail) }
                            } else {
                                customerNumberError = "El N° de cliente debe tener exactamente 11 dígitos."
                            }
                        }
                        .disabled(store.isLoading)
                    } header: {
                        Text("N° de cliente MetroGAS")
                    } footer: {
                        Text("Lo usamos para consultar facturas, saldo y consumo en Tu Factura / Saldos. Aparece en tu factura impresa o digital.")
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
                        labeled("Email", displayEmail)
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

                        Button("Activar notificaciones") {
                            Task {
                                let granted = await reminders.requestPermissionIfNeeded()
                                await reminders.reschedule(for: store.invoices)
                                permissionMessage = granted
                                    ? "Notificaciones activadas."
                                    : "Revisá el permiso en Ajustes → Metrogas."
                            }
                        }
                        .disabled(!reminders.remindersEnabled)
                    } header: {
                        Text("Recordatorios")
                    } footer: {
                        Text("Avisos locales según tus facturas sincronizadas en la app.")
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

                        Button {
                            Task { await store.refresh(loginHint: session.loginEmail) }
                        } label: {
                            if store.isLoading {
                                Label("Sincronizando…", systemImage: "arrow.triangle.2.circlepath")
                            } else {
                                Label("Sincronizar cuenta", systemImage: "arrow.triangle.2.circlepath")
                            }
                        }
                        .disabled(store.isLoading)
                    }

                    Section {
                        Button("Cerrar sesión", role: .destructive) {
                            showLogoutConfirm = true
                        }
                    } footer: {
                        Text("Al cerrar sesión se borran cookies y datos sincronizados de este dispositivo.")
                    }
                }
                .scrollContentBackground(.hidden)
                .refreshable {
                    await store.refresh(loginHint: session.loginEmail)
                }
            }
            .navigationTitle("Cuenta")
            .task {
                await reminders.refreshAuthorizationStatus()
            }
            .alert("¿Cerrar sesión?", isPresented: $showLogoutConfirm) {
                Button("Cancelar", role: .cancel) {}
                Button("Cerrar sesión", role: .destructive) {
                    Task {
                        store.clear()
                        await session.logout()
                    }
                }
            } message: {
                Text("Vas a salir de tu cuenta MetroGAS en esta app.")
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

    private var displayEmail: String {
        if !store.account.email.isEmpty { return store.account.email }
        if let email = session.loginEmail, !email.isEmpty { return email }
        return "—"
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
                Text(store.account.holderName.isEmpty ? "Cuenta MetroGAS" : store.account.holderName)
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
        let name = store.account.holderName.isEmpty ? "MG" : store.account.holderName
        let parts = name.split(separator: " ")
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

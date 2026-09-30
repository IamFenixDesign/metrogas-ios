import SwiftUI

struct AccountView: View {
    @EnvironmentObject private var store: AccountDataStore
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var reminders: ReminderService
    @EnvironmentObject private var tabScroll: TabBarScrollState
    @State private var showLogoutConfirm = false
    @State private var customerNumberError: String?
    @State private var appear = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 16) {
                        TabBarScrollProbe()
                            .frame(maxWidth: .infinity, alignment: .leading)

                        MetrogasLogo(height: 32, alignment: .center)
                            .frame(maxWidth: 160)
                        profileHeader
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 16, trailing: 0))
                    .appearMotion(visible: appear, index: 0)
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
                    Button("Actualizar datos de este N°") {
                        if store.saveCustomerNumber(store.customerNumberDraft, forEmail: session.loginEmail) {
                            customerNumberError = nil
                            session.customerNumber = MetrogasURLs.normalizedCustomerNumber(store.customerNumberDraft)
                            Task {
                                await store.refresh(
                                    loginHint: session.loginEmail,
                                    customerNumber: session.customerNumber,
                                    force: true
                                )
                            }
                        } else {
                            customerNumberError = "El N° de cliente debe tener exactamente 11 dígitos."
                        }
                    }
                    .disabled(store.isLoading)
                } header: {
                    Text("N° de cliente")
                } footer: {
                    Text("Podés cambiar el N° y volver a sincronizar facturas y titular desde MetroGAS.")
                }
                .listRowBackground(glassListRow)
                .listRowInsets(sectionRowInsets)

                Section("Suministro") {
                    labeled("N° de cliente", display(store.account.customerNumber))
                    labeled("Medidor", display(store.account.meterNumber))
                    labeled("Categoría", display(store.account.tariffCategory))
                    labeled("Dirección", display(store.account.supplyAddress))
                    labeled("Localidad", display(store.account.locality))
                    labeled("CP", display(store.account.postalCode))
                }
                .listRowBackground(glassListRow)
                .listRowInsets(sectionRowInsets)

                Section("Contacto") {
                    labeled("Email", displayEmail)
                    labeled("Teléfono", display(store.account.phone))
                }
                .listRowBackground(glassListRow)
                .listRowInsets(sectionRowInsets)

                Section {
                    Toggle("Recordatorios de vencimiento", isOn: $reminders.remindersEnabled)
                        .padding(.vertical, 4)
                        .onChange(of: reminders.remindersEnabled) { _, _ in
                            Task { await reminders.reschedule(for: store.invoices) }
                        }

                    Stepper(
                        "Avisar \(reminders.daysBeforeDue) día\(reminders.daysBeforeDue == 1 ? "" : "s") antes",
                        value: $reminders.daysBeforeDue,
                        in: 1...7
                    )
                    .padding(.vertical, 4)
                    .disabled(!reminders.remindersEnabled)
                    .onChange(of: reminders.daysBeforeDue) { _, _ in
                        Task { await reminders.reschedule(for: store.invoices) }
                    }
                } header: {
                    Text("Recordatorios")
                } footer: {
                    if reminders.authorizationStatus == .denied {
                        Text("Las notificaciones están desactivadas. Activalas en Ajustes → Metrogas → Notificaciones.")
                    } else {
                        Text("Avisos nativos de iOS según tus facturas sincronizadas.")
                    }
                }
                .listRowBackground(glassListRow)
                .listRowInsets(sectionRowInsets)

                Section("Preferencias") {
                    Picker("Apariencia", selection: $session.appearanceMode) {
                        ForEach(AppSession.AppearanceMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .padding(.vertical, 4)
                    .onChange(of: session.appearanceMode) { _, _ in
                        session.persistAppearance()
                    }

                    if store.isLoading {
                        Label("Sincronizando con tu cuenta…", systemImage: "arrow.triangle.2.circlepath")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                            .symbolEffect(.pulse, options: .repeating.speed(0.6), isActive: store.isLoading)
                    } else if let last = store.lastSync {
                        Text("Última sync: \(DateFormatter.metrogasDayMonthYear.string(from: last))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    }
                }
                .listRowBackground(glassListRow)
                .listRowInsets(sectionRowInsets)

                Section {
                    Button("Cerrar sesión", role: .destructive) {
                        showLogoutConfirm = true
                    }
                    .padding(.vertical, 6)
                } footer: {
                    Text("Al cerrar sesión se borran cookies y datos sincronizados de este dispositivo.")
                }
                .listRowBackground(glassListRow)
                .listRowInsets(sectionRowInsets)

                Section {
                    FloatingTabBarSpacer()
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .listSectionSpacing(28)
            .tracksFloatingTabBar(tabScroll)
            .background { LiquidGlassBackground() }
            .navigationTitle("Cuenta")
            .navigationBarTitleDisplayMode(.large)
            .task {
                await reminders.refreshAuthorizationStatus()
            }
            .onAppear {
                withAnimation(MetrogasTheme.springSoft) { appear = true }
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
        }
    }

    private var sectionRowInsets: EdgeInsets {
        EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)
    }

    private var glassListRow: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.28), lineWidth: 0.8)
            )
            .padding(.vertical, 4)
    }

    private var displayEmail: String {
        if !store.account.email.isEmpty { return store.account.email }
        if let email = session.loginEmail, !email.isEmpty { return email }
        return "—"
    }

    private func display(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "—" : trimmed
    }

    private var profileHeader: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 68, height: 68)
                    .overlay(
                        Circle()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.7),
                                        MetrogasTheme.brandCyan.opacity(0.5),
                                        Color.white.opacity(0.2)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.2
                            )
                    )
                Text(initials)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(MetrogasTheme.brandBlue)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(store.account.holderName.isEmpty ? "Cuenta MetroGAS" : store.account.holderName)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                Text("Titular del servicio")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(18)
        .liquidGlass(cornerRadius: 22, prominent: true)
    }

    private var initials: String {
        let name = store.account.holderName.isEmpty ? "MG" : store.account.holderName
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first.map(String.init) }
        return letters.joined().uppercased()
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body.weight(.medium))
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

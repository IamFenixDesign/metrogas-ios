import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: AccountDataStore
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var reminders: ReminderService
    @EnvironmentObject private var tabScroll: TabBarScrollState
    @State private var appear = false
    @State private var payBrowser: InAppBrowserDestination?
    @State private var showNotificationCenter = false

    private var resolvedCustomerNumber: String? {
        MetrogasURLs.normalizedCustomerNumber(session.customerNumber ?? "")
            ?? MetrogasURLs.normalizedCustomerNumber(store.account.customerNumber)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                brandHero
                    .appearMotion(visible: appear, index: 0)

                if store.isLoading {
                    syncBanner
                        .appearMotion(visible: appear, index: 1)
                }

                if let message = store.syncMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .liquidGlass(cornerRadius: 16)
                        .appearMotion(visible: appear, index: 1)
                }

                balancePanel
                    .appearMotion(visible: appear, index: 2)

                recentActivity
                    .appearMotion(visible: appear, index: 3)

                Spacer(minLength: 0)

                FloatingTabBarSpacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background { LiquidGlassBackground() }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
            .onAppear {
                tabScroll.reset()
                TabBarScrollState.shared = tabScroll
                withAnimation(MetrogasTheme.springSoft) { appear = true }
            }
        }
    }

    private var brandHero: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                let first = store.account.holderName.components(separatedBy: " ").first
                Text(first?.isEmpty == false ? "Hola, \(first!)" : "Hola")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("Tu gas natural en un vistazo")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            notificationButton
        }
        .fullScreenCover(isPresented: $showNotificationCenter) {
            NotificationCenterView()
                .environmentObject(reminders)
        }
    }

    private var notificationButton: some View {
        Button {
            showNotificationCenter = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: reminders.unreadCount > 0 ? "bell.badge.fill" : "bell.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(MetrogasTheme.brandBlue)
                    .frame(width: 44, height: 44)
                    .background {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.white.opacity(0.45), lineWidth: 0.8)
                            )
                    }

                if reminders.unreadCount > 0 {
                    Text(reminders.unreadCount > 9 ? "9+" : "\(reminders.unreadCount)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(MetrogasTheme.brandFlame))
                        .offset(x: 4, y: -2)
                }
            }
        }
        .buttonStyle(PressableGlassStyle())
        .accessibilityLabel(
            reminders.unreadCount > 0
                ? "Notificaciones, \(reminders.unreadCount) sin leer"
                : "Notificaciones"
        )
    }

    private var syncBanner: some View {
        ProgressView("Sincronizando tu cuenta…")
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .liquidGlass(cornerRadius: 16)
    }

    private var balancePanel: some View {
        let pending = store.totalPendingARS
        let next = store.nextDueInvoice

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Saldo pendiente")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let next {
                    StatusBadge(status: next.status, compact: true)
                }
            }

            Text(Formatters.money(pending))
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
                .minimumScaleFactor(0.7)
                .lineLimit(1)

            if let next, pending > 0 {
                Text(dueLine(for: next))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            } else if pending <= 0 {
                Text("No tenés deudas por pagar")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(MetrogasTheme.success)
            }

            if pending > 0, let customerNumber = resolvedCustomerNumber {
                Button {
                    payBrowser = InAppBrowserDestination(
                        url: MetrogasURLs.saldosPagar(accountId: customerNumber)
                    )
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "dollarsign.circle.fill")
                            .font(.title3)
                        Text("Pagar ahora")
                            .font(.headline)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    .background {
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        MetrogasTheme.brandFlame,
                                        MetrogasTheme.brandFlame.opacity(0.82)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .shadow(color: MetrogasTheme.brandFlame.opacity(0.28), radius: 10, y: 5)
                    }
                }
                .buttonStyle(PressableGlassStyle())
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(cornerRadius: 24, prominent: true)
        .fullScreenCover(item: $payBrowser) { destination in
            InAppBrowserSheet(url: destination.url, title: destination.title)
        }
    }

    private var recentActivity: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Actividad reciente", subtitle: "Últimas facturas")

            if store.invoices.isEmpty {
                Text(store.isLoading ? "Buscando movimientos…" : "Todavía no hay movimientos para mostrar.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .liquidGlass(cornerRadius: 18)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(store.invoices.prefix(3))) { invoice in
                        NavigationLink {
                            InvoiceDetailView(invoiceID: invoice.id)
                        } label: {
                            InvoiceRowView(invoice: invoice, compact: true)
                        }
                        .buttonStyle(PressableGlassStyle())

                        if invoice.id != store.invoices.prefix(3).last?.id {
                            Divider().padding(.leading, 52).opacity(0.35)
                        }
                    }
                }
                .padding(.vertical, 4)
                .liquidGlass(cornerRadius: 20)
            }
        }
    }

    private func dueLine(for invoice: Invoice) -> String {
        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: Date()),
            to: Calendar.current.startOfDay(for: invoice.dueDate)
        ).day ?? 0
        let date = DateFormatter.metrogasDayMonthYear.string(from: invoice.dueDate)
        if days < 0 {
            return "Vencida el \(date) · \(invoice.periodLabel)"
        }
        if days == 0 {
            return "Vence hoy · \(invoice.periodLabel)"
        }
        if days == 1 {
            return "Vence mañana · \(invoice.periodLabel)"
        }
        return "Vence el \(date) · \(invoice.periodLabel)"
    }
}

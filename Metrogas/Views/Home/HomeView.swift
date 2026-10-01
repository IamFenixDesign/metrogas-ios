import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: AccountDataStore
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var tabScroll: TabBarScrollState
    @State private var appear = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                brandHero
                    .appearMotion(visible: appear, index: 0)

                if store.isLoading {
                    ProgressView("Sincronizando tu cuenta…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 14)
                        .liquidGlass(cornerRadius: 16)
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

                nextInvoiceCard
                    .appearMotion(visible: appear, index: 2)

                if let invoice = store.nextDueInvoice,
                   let customerNumber = MetrogasURLs.normalizedCustomerNumber(session.customerNumber ?? "")
                    ?? MetrogasURLs.normalizedCustomerNumber(store.account.customerNumber) {
                    PaymentOptionsCard(
                        customerNumber: customerNumber,
                        amountLabel: Formatters.money(invoice.amountARS),
                        compact: true
                    )
                    .padding(16)
                    .liquidGlass(cornerRadius: 22)
                    .appearMotion(visible: appear, index: 3)
                }

                UpcomingDueSection()
                    .appearMotion(visible: appear, index: 4)

                quickMetrics
                    .appearMotion(visible: appear, index: 5)

                recentActivity
                    .appearMotion(visible: appear, index: 6)

                Spacer(minLength: 0)

                FloatingTabBarSpacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background { LiquidGlassBackground() }
            .navigationTitle("Inicio")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                tabScroll.reset()
                TabBarScrollState.shared = tabScroll
                withAnimation(MetrogasTheme.springSoft) { appear = true }
            }
        }
    }

    private var brandHero: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Tu gas natural en un vistazo")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            let first = store.account.holderName.components(separatedBy: " ").first
            Text(first?.isEmpty == false ? "Hola, \(first!)" : "Hola")
                .font(.system(.title2, design: .rounded).weight(.semibold))
                .foregroundStyle(.primary)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var nextInvoiceCard: some View {
        if let invoice = store.nextDueInvoice {
            NavigationLink {
                InvoiceDetailView(invoiceID: invoice.id)
            } label: {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(invoice.status == .overdue ? "Factura vencida" : "Próximo vencimiento")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.92))
                        Spacer()
                        StatusBadge(status: invoice.status)
                            .colorScheme(.light)
                    }

                    Text(Formatters.money(invoice.amountARS))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                        .contentTransition(.numericText())

                    HStack {
                        Label(invoice.periodLabel, systemImage: "calendar")
                        Spacer()
                        Label(
                            "Vence \(DateFormatter.metrogasDayMonthYear.string(from: invoice.dueDate))",
                            systemImage: "bell.fill"
                        )
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.88))
                }
                .padding(18)
                .background {
                    ZStack {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        MetrogasTheme.deepNavy,
                                        MetrogasTheme.brandBlue,
                                        MetrogasTheme.brandCyan.opacity(0.95)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.28),
                                        Color.white.opacity(0.02),
                                        Color.white.opacity(0.12)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .blendMode(.plusLighter)
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.55),
                                        Color.white.opacity(0.12),
                                        Color.white.opacity(0.3)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
                    .shadow(color: MetrogasTheme.brandBlue.opacity(0.35), radius: 14, y: 8)
                }
            }
            .buttonStyle(PressableGlassStyle())
        }
    }

    private var quickMetrics: some View {
        HStack(spacing: 12) {
            MetricTile(
                title: "Pendiente",
                value: Formatters.money(store.totalPendingARS),
                icon: "dollarsign.circle.fill",
                accent: MetrogasTheme.brandFlame
            )
            MetricTile(
                title: "Último consumo",
                value: Formatters.m3(store.latestReading?.cubicMeters ?? 0),
                icon: "gauge.with.dots.needle.67percent",
                accent: MetrogasTheme.brandBlue
            )
        }
    }

    private var recentActivity: some View {
        VStack(alignment: .leading, spacing: 10) {
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
                            Divider().padding(.leading, 12).opacity(0.35)
                        }
                    }
                }
                .padding(.vertical, 2)
                .liquidGlass(cornerRadius: 20)
            }
        }
    }
}

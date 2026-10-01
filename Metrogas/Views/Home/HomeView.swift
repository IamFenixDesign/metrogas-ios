import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: AccountDataStore
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var tabScroll: TabBarScrollState
    @Environment(\.openURL) private var openURL
    @State private var appear = false

    private var resolvedCustomerNumber: String? {
        MetrogasURLs.normalizedCustomerNumber(session.customerNumber ?? "")
            ?? MetrogasURLs.normalizedCustomerNumber(store.account.customerNumber)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    TabBarScrollProbe()

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

                    quickMetrics
                        .appearMotion(visible: appear, index: 3)

                    recentActivity
                        .appearMotion(visible: appear, index: 4)

                    FloatingTabBarSpacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 8)
            }
            .scrollIndicators(.hidden)
            .tracksFloatingTabBar(tabScroll)
            .background { LiquidGlassBackground() }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                tabScroll.reset()
                TabBarScrollState.shared = tabScroll
                withAnimation(MetrogasTheme.springSoft) { appear = true }
            }
        }
    }

    private var brandHero: some View {
        VStack(alignment: .leading, spacing: 10) {
            MetrogasLogo(height: 28, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                let first = store.account.holderName.components(separatedBy: " ").first
                Text(first?.isEmpty == false ? "Hola, \(first!)" : "Hola")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("Tu gas natural en un vistazo")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
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
                    openURL(MetrogasURLs.saldosPagar(accountId: customerNumber))
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "dollarsign.circle.fill")
                            .font(.title3)
                        Text("Pagar ahora")
                            .font(.headline)
                        Spacer()
                        Image(systemName: "arrow.up.right")
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
    }

    private var quickMetrics: some View {
        HStack(spacing: 12) {
            MetricTile(
                title: "Último consumo",
                value: Formatters.m3(store.latestReading?.cubicMeters ?? 0),
                icon: "gauge.with.dots.needle.67percent",
                accent: MetrogasTheme.brandBlue
            )
            MetricTile(
                title: "Medidor",
                value: meterLabel,
                icon: "wrench.and.screwdriver.fill",
                accent: MetrogasTheme.brandCyan
            )
        }
    }

    private var meterLabel: String {
        let meter = store.account.meterNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        return meter.isEmpty || meter == "—" ? "—" : meter
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
                    ForEach(Array(store.invoices.prefix(4))) { invoice in
                        NavigationLink {
                            InvoiceDetailView(invoiceID: invoice.id)
                        } label: {
                            InvoiceRowView(invoice: invoice, compact: true)
                        }
                        .buttonStyle(PressableGlassStyle())

                        if invoice.id != store.invoices.prefix(4).last?.id {
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

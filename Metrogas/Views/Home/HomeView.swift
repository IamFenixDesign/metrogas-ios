import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: AccountDataStore
    @EnvironmentObject private var session: AppSession

    var body: some View {
        NavigationStack {
            ZStack {
                MetrogasBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        brandHero
                        if store.isLoading {
                            ProgressView("Sincronizando tu cuenta…")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        if let message = store.syncMessage {
                            Text(message)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color(.secondarySystemGroupedBackground))
                                )
                        }
                        nextInvoiceCard
                        UpcomingDueSection()
                        quickMetrics
                        recentActivity
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)
                }
                .refreshable {
                    await store.refresh(loginHint: session.loginEmail)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Image("MetrogasLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 22)
                        .accessibilityHidden(true)
                }
            }
            .task {
                // Si no hay datos aún, sincroniza sola con la sesión activa.
                if store.invoices.isEmpty && !store.isLoading {
                    await store.refresh(loginHint: session.loginEmail)
                }
            }
        }
    }

    private var brandHero: some View {
        VStack(alignment: .leading, spacing: 14) {
            MetrogasLogo(height: 44, alignment: .leading)
                .frame(maxWidth: 200, alignment: .leading)
                .padding(.top, 4)

            Text("Tu gas natural en un vistazo")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            let first = store.account.holderName.components(separatedBy: " ").first
            Text(first?.isEmpty == false ? "Hola, \(first!)" : "Hola")
                .font(.title3.weight(.semibold))
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
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text(invoice.status == .overdue ? "Factura vencida" : "Próximo vencimiento")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.9))
                        Spacer()
                        StatusBadge(status: invoice.status)
                            .colorScheme(.light)
                    }

                    Text(Formatters.money(invoice.amountARS))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()

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
                .padding(20)
                .background(
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
                        .shadow(color: MetrogasTheme.brandBlue.opacity(0.35), radius: 16, y: 8)
                )
            }
            .buttonStyle(.plain)
        } else if !store.isLoading {
            VStack(alignment: .leading, spacing: 8) {
                Text(store.invoices.isEmpty ? "Sincronizando tu cuenta" : "Estás al día")
                    .font(.headline)
                Text(
                    store.invoices.isEmpty
                        ? "Estamos cargando facturas y saldo de tu Oficina Virtual."
                        : "No hay facturas pendientes en este momento."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
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
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Actividad reciente", subtitle: "Últimas facturas")

            if store.invoices.isEmpty {
                Text(store.isLoading ? "Buscando movimientos…" : "Todavía no hay movimientos para mostrar.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(.secondarySystemGroupedBackground))
                    )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(store.invoices.prefix(4))) { invoice in
                        NavigationLink {
                            InvoiceDetailView(invoiceID: invoice.id)
                        } label: {
                            InvoiceRowView(invoice: invoice, compact: true)
                        }
                        .buttonStyle(.plain)

                        if invoice.id != store.invoices.prefix(4).last?.id {
                            Divider().padding(.leading, 12)
                        }
                    }
                }
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
            }
        }
    }
}

import SwiftUI

struct InvoiceListView: View {
    @EnvironmentObject private var store: AccountDataStore
    @State private var appear = false

    private var pendingCount: Int {
        store.invoices.filter { $0.status == .pending }.count
    }

    private var overdueCount: Int {
        store.invoices.filter { $0.status == .overdue }.count
    }

    private var paidCount: Int {
        store.invoices.filter { $0.status == .paid }.count
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.isLoading && store.invoices.isEmpty {
                    ProgressView("Cargando facturas…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if store.invoices.isEmpty {
                    ScrollView {
                        emptyState(noData: true)
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                        FloatingTabBarSpacer()
                    }
                } else {
                    invoiceScroll
                }
            }
            .background { LiquidGlassBackground() }
            .navigationTitle("Facturas")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $store.searchText, prompt: "Buscar N° o período")
            .onAppear {
                withAnimation(MetrogasTheme.springSoft) { appear = true }
            }
        }
    }

    private var invoiceScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                summaryHeader
                    .appearMotion(visible: appear, index: 0)

                filterBar
                    .appearMotion(visible: appear, index: 1)

                if store.filteredInvoices.isEmpty {
                    emptyState(noData: false)
                        .appearMotion(visible: appear, index: 2)
                } else {
                    invoiceStack
                        .appearMotion(visible: appear, index: 2)
                }

                FloatingTabBarSpacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
        .scrollIndicators(.automatic)
    }

    private var summaryHeader: some View {
        HStack(spacing: 8) {
            summaryTile(
                title: "Pendientes",
                value: "\(pendingCount)",
                icon: InvoiceStatus.pending.symbolName,
                tint: MetrogasTheme.warning
            )
            summaryTile(
                title: "Vencidas",
                value: "\(overdueCount)",
                icon: InvoiceStatus.overdue.symbolName,
                tint: MetrogasTheme.danger
            )
            summaryTile(
                title: "Pagadas",
                value: "\(paidCount)",
                icon: InvoiceStatus.paid.symbolName,
                tint: MetrogasTheme.success
            )
        }
    }

    private func summaryTile(title: String, value: String, icon: String, tint: Color) -> some View {
        Button {
            withAnimation(MetrogasTheme.springSnappy) {
                switch title {
                case "Pendientes": store.invoiceFilter = .pending
                case "Vencidas": store.invoiceFilter = .overdue
                case "Pagadas": store.invoiceFilter = .paid
                default: break
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: icon)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
                Text(value)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .liquidGlass(cornerRadius: 16)
        }
        .buttonStyle(PressableGlassStyle())
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(InvoiceFilter.allCases) { filter in
                    GlassChip(
                        title: filter.rawValue,
                        icon: filter.symbolName,
                        selected: store.invoiceFilter == filter
                    ) {
                        withAnimation(MetrogasTheme.springSnappy) {
                            store.invoiceFilter = filter
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var invoiceStack: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "list.bullet.rectangle.portrait.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MetrogasTheme.brandBlue)
                Text("\(store.filteredInvoices.count) factura\(store.filteredInvoices.count == 1 ? "" : "s")")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if store.totalPendingARS > 0, store.invoiceFilter == .all || store.invoiceFilter == .pending || store.invoiceFilter == .overdue {
                    Text(Formatters.money(store.totalPendingARS))
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(MetrogasTheme.brandFlame)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            ForEach(Array(store.filteredInvoices.enumerated()), id: \.element.id) { index, invoice in
                NavigationLink {
                    InvoiceDetailView(invoiceID: invoice.id)
                } label: {
                    InvoiceRowView(invoice: invoice)
                }
                .buttonStyle(PressableGlassStyle())

                if index < store.filteredInvoices.count - 1 {
                    Divider()
                        .padding(.leading, 56)
                        .opacity(0.28)
                }
            }
        }
        .liquidGlass(cornerRadius: 20)
    }

    private func emptyState(noData: Bool) -> some View {
        VStack(spacing: 12) {
            Image(systemName: noData ? "doc.text.fill" : "doc.text.magnifyingglass")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(MetrogasTheme.brandBlue)
                .symbolRenderingMode(.hierarchical)

            Text(noData ? "Sin facturas" : "Sin resultados")
                .font(.headline)

            Text(
                noData
                    ? (store.isLoading
                        ? "Estamos cargando las facturas de tu Oficina Virtual…"
                        : "Las facturas aparecen cuando sincronizás al iniciar sesión.")
                    : "Probá otro filtro o borrá la búsqueda."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .liquidGlass(cornerRadius: 20)
    }
}

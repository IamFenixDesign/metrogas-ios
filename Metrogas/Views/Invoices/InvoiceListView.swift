import SwiftUI

struct InvoiceListView: View {
    @EnvironmentObject private var store: AccountDataStore
    @State private var appear = false

    var body: some View {
        NavigationStack {
            Group {
                if store.isLoading && store.invoices.isEmpty {
                    ProgressView("Cargando facturas…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if store.invoices.isEmpty {
                    emptyState(noData: true)
                } else {
                    invoiceList
                }
            }
            .background { LiquidGlassBackground() }
            .navigationTitle("Facturas")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .searchable(text: $store.searchText, prompt: "Buscar por número o período")
            .onAppear {
                withAnimation(MetrogasTheme.springSoft) { appear = true }
            }
        }
    }

    private var invoiceList: some View {
        List {
            Section {
                filterBar
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            if store.filteredInvoices.isEmpty {
                Section {
                    emptyState(noData: false)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            } else {
                Section {
                    ForEach(Array(store.filteredInvoices.enumerated()), id: \.element.id) { index, invoice in
                        NavigationLink {
                            InvoiceDetailView(invoiceID: invoice.id)
                        } label: {
                            InvoiceRowView(invoice: invoice)
                        }
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .strokeBorder(
                                            LinearGradient(
                                                colors: [
                                                    Color.white.opacity(0.55),
                                                    Color.white.opacity(0.12),
                                                    Color.white.opacity(0.28)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1
                                        )
                                )
                                .shadow(color: Color.black.opacity(0.06), radius: 12, y: 5)
                                .padding(.vertical, 3)
                        )
                        .listRowSeparator(.hidden)
                        .appearMotion(visible: appear, index: min(index + 1, 8))
                    }
                }
            }

            Section {
                FloatingTabBarSpacer()
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .listSectionSpacing(8)
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(InvoiceFilter.allCases) { filter in
                    GlassChip(title: filter.rawValue, selected: store.invoiceFilter == filter) {
                        withAnimation(MetrogasTheme.springSnappy) {
                            store.invoiceFilter = filter
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func emptyState(noData: Bool) -> some View {
        ContentUnavailableView {
            Label(
                noData ? "Sin facturas" : "Sin resultados",
                systemImage: noData ? "doc.text" : "doc.text.magnifyingglass"
            )
        } description: {
            Text(
                noData
                    ? (store.isLoading
                        ? "Estamos cargando las facturas de tu Oficina Virtual…"
                        : "Las facturas aparecen cuando sincronizás al iniciar sesión.")
                    : "Probá otro filtro o borrá la búsqueda."
            )
        }
        .padding(24)
        .liquidGlass(cornerRadius: 24)
        .frame(maxWidth: .infinity)
        .appearMotion(visible: appear, index: 1)
    }
}

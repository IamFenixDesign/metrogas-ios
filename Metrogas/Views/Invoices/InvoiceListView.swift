import SwiftUI

struct InvoiceListView: View {
    @EnvironmentObject private var store: AccountDataStore
    @State private var appear = false

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidGlassBackground()

                VStack(spacing: 0) {
                    filterBar
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                        .appearMotion(visible: appear, index: 0)

                    if store.isLoading && store.invoices.isEmpty {
                        ProgressView("Cargando facturas…")
                            .padding(20)
                            .liquidGlass(cornerRadius: 20)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if store.filteredInvoices.isEmpty {
                        emptyState
                            .appearMotion(visible: appear, index: 1)
                    } else {
                        List {
                            ForEach(Array(store.filteredInvoices.enumerated()), id: \.element.id) { index, invoice in
                                NavigationLink {
                                    InvoiceDetailView(invoiceID: invoice.id)
                                } label: {
                                    InvoiceRowView(invoice: invoice)
                                }
                                .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                                .listRowBackground(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(.ultraThinMaterial)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 18, style: .continuous)
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
                                        )
                                        .shadow(color: Color.black.opacity(0.06), radius: 10, y: 4)
                                        .padding(.vertical, 4)
                                )
                                .listRowSeparator(.hidden)
                                .appearMotion(visible: appear, index: min(index + 1, 6))
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle("Facturas")
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .searchable(text: $store.searchText, prompt: "Buscar por número o período")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Image("MetrogasLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 18)
                        .accessibilityHidden(true)
                }
            }
            .onAppear {
                withAnimation(MetrogasTheme.springSoft) { appear = true }
            }
        }
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

    private var emptyState: some View {
        ContentUnavailableView {
            Label(
                store.invoices.isEmpty ? "Sin facturas" : "Sin resultados",
                systemImage: store.invoices.isEmpty ? "doc.text" : "doc.text.magnifyingglass"
            )
        } description: {
            Text(
                store.invoices.isEmpty
                    ? (store.isLoading
                        ? "Estamos cargando las facturas de tu Oficina Virtual…"
                        : "Las facturas aparecen cuando sincronizás al iniciar sesión.")
                    : "Probá otro filtro o borrá la búsqueda."
            )
        }
        .padding(24)
        .liquidGlass(cornerRadius: 24)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

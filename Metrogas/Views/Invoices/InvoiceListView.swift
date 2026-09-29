import SwiftUI

struct InvoiceListView: View {
    @EnvironmentObject private var store: MockDataStore

    var body: some View {
        NavigationStack {
            ZStack {
                MetrogasBackground()

                VStack(spacing: 0) {
                    filterBar
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 12)

                    if store.filteredInvoices.isEmpty {
                        emptyState
                    } else {
                        List {
                            ForEach(store.filteredInvoices) { invoice in
                                NavigationLink {
                                    InvoiceDetailView(invoiceID: invoice.id)
                                } label: {
                                    InvoiceRowView(invoice: invoice)
                                }
                                .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                                .listRowBackground(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(Color(.secondarySystemGroupedBackground))
                                        .padding(.vertical, 4)
                                )
                                .listRowSeparator(.hidden)
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle("Facturas")
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
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(InvoiceFilter.allCases) { filter in
                    Button {
                        withAnimation(.snappy) {
                            store.invoiceFilter = filter
                        }
                    } label: {
                        Text(filter.rawValue)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(store.invoiceFilter == filter
                                          ? MetrogasTheme.brandBlue
                                          : Color(.secondarySystemGroupedBackground))
                            )
                            .foregroundStyle(store.invoiceFilter == filter ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "Sin resultados",
            systemImage: "doc.text.magnifyingglass",
            description: Text("Probá otro filtro o borrá la búsqueda.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    InvoiceListView()
        .environmentObject(MockDataStore())
}

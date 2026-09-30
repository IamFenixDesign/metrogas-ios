import SwiftUI

struct InvoiceDetailView: View {
    @EnvironmentObject private var store: AccountDataStore
    let invoiceID: String

    @State private var draftNotes: String = ""
    @State private var showPaidConfirmation = false
    @State private var appear = false
    @FocusState private var notesFocused: Bool

    private var invoice: Invoice? {
        store.invoice(id: invoiceID)
    }

    var body: some View {
        Group {
            if let invoice {
                content(for: invoice)
            } else {
                ContentUnavailableView("Factura no encontrada", systemImage: "exclamationmark.triangle")
            }
        }
        .navigationTitle("Detalle")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .onAppear {
            draftNotes = invoice?.notes ?? ""
            withAnimation(MetrogasTheme.springSoft) { appear = true }
        }
        .alert("¿Marcar como pagada?", isPresented: $showPaidConfirmation) {
            Button("Cancelar", role: .cancel) {}
            Button("Confirmar") {
                store.markAsPaid(invoiceID)
            }
        } message: {
            Text("Se actualiza el estado solo en este dispositivo.")
        }
    }

    @ViewBuilder
    private func content(for invoice: Invoice) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(invoice)
                    .appearMotion(visible: appear, index: 0)
                detailsCard(invoice)
                    .appearMotion(visible: appear, index: 1)
                breakdownCard(invoice)
                    .appearMotion(visible: appear, index: 2)
                notesCard(invoice)
                    .appearMotion(visible: appear, index: 3)
                actions(invoice)
                    .appearMotion(visible: appear, index: 4)

                FloatingTabBarSpacer()
            }
            .padding(20)
        }
        .background { LiquidGlassBackground() }
    }

    private func header(_ invoice: Invoice) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(invoice.number)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                StatusBadge(status: invoice.status)
            }

            Text(Formatters.money(invoice.amountARS))
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .contentTransition(.numericText())

            Text(invoice.periodLabel)
                .font(.system(.title3, design: .rounded).weight(.semibold))
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(cornerRadius: 24, prominent: true)
    }

    private func detailsCard(_ invoice: Invoice) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Datos de la factura")

            detailRow(
                "Período",
                "\(DateFormatter.metrogasDayMonthYear.string(from: invoice.periodStart)) – \(DateFormatter.metrogasDayMonthYear.string(from: invoice.periodEnd))"
            )
            detailRow("Emisión", DateFormatter.metrogasDayMonthYear.string(from: invoice.issuedDate))
            detailRow("Vencimiento", DateFormatter.metrogasDayMonthYear.string(from: invoice.dueDate))
            detailRow("Consumo", Formatters.m3(invoice.consumptionM3))
            detailRow("Punto de suministro", invoice.supplyPoint)
        }
        .padding(18)
        .liquidGlass(cornerRadius: 22)
    }

    private func breakdownCard(_ invoice: Invoice) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Detalle de cargos")

            breakdownRow("Cargo fijo", invoice.breakdown.cargoFijo)
            breakdownRow("Cargo variable", invoice.breakdown.cargoVariable)
            breakdownRow("Impuestos y tasas", invoice.breakdown.impuestos)
            breakdownRow("Otros conceptos", invoice.breakdown.otros)

            Divider().opacity(0.35)

            HStack {
                Text("Total")
                    .font(.headline)
                Spacer()
                Text(Formatters.money(invoice.amountARS))
                    .font(.headline.monospacedDigit())
            }
        }
        .padding(18)
        .liquidGlass(cornerRadius: 22)
    }

    private func notesCard(_ invoice: Invoice) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Notas", subtitle: "Solo en este dispositivo")

            TextField("Agregar una nota…", text: $draftNotes, axis: .vertical)
                .lineLimit(3...6)
                .padding(12)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.45))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.4), lineWidth: 0.8)
                        )
                }
                .focused($notesFocused)

            Button("Guardar nota") {
                store.updateNotes(invoice.id, notes: draftNotes.trimmingCharacters(in: .whitespacesAndNewlines))
                notesFocused = false
            }
            .buttonStyle(.bordered)
            .disabled(draftNotes.trimmingCharacters(in: .whitespacesAndNewlines) == invoice.notes)
        }
        .padding(18)
        .liquidGlass(cornerRadius: 22)
    }

    @ViewBuilder
    private func actions(_ invoice: Invoice) -> some View {
        if invoice.status != .paid {
            Button {
                showPaidConfirmation = true
            } label: {
                Label("Marcar como pagada", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundStyle(.white)
                    .background {
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [MetrogasTheme.brandBlue, MetrogasTheme.brandCyan],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .shadow(color: MetrogasTheme.brandBlue.opacity(0.35), radius: 12, y: 6)
                    }
            }
            .buttonStyle(PressableGlassStyle())
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(value)
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.trailing)
        }
    }

    private func breakdownRow(_ title: String, _ value: Decimal) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(Formatters.money(value))
                .font(.subheadline.monospacedDigit())
        }
    }
}

import SwiftUI

struct UpcomingDueSection: View {
    @EnvironmentObject private var store: AccountDataStore

    var body: some View {
        let items = store.upcomingDueInvoices
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(
                    title: "Próximos vencimientos",
                    subtitle: "Facturas a pagar"
                )

                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, invoice in
                        NavigationLink {
                            InvoiceDetailView(invoiceID: invoice.id)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: invoice.status == .overdue
                                      ? "exclamationmark.bell.fill"
                                      : "bell.fill")
                                    .foregroundStyle(invoice.status == .overdue
                                                     ? MetrogasTheme.danger
                                                     : MetrogasTheme.brandFlame)
                                    .frame(width: 28)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(invoice.periodLabel)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text(dueCaption(for: invoice))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer(minLength: 8)

                                Text(Formatters.money(invoice.amountARS))
                                    .font(.subheadline.weight(.bold).monospacedDigit())
                                    .foregroundStyle(.primary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)

                        if index < items.count - 1 {
                            Divider().padding(.leading, 54)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
            }
        }
    }

    private func dueCaption(for invoice: Invoice) -> String {
        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: Date()),
            to: Calendar.current.startOfDay(for: invoice.dueDate)
        ).day ?? 0
        if days < 0 {
            return "Vencida hace \(abs(days)) día\(abs(days) == 1 ? "" : "s")"
        }
        if days == 0 { return "Vence hoy" }
        if days == 1 { return "Vence mañana" }
        return "Vence en \(days) días"
    }
}

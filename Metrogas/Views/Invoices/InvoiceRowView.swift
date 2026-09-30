import SwiftUI

struct InvoiceRowView: View {
    let invoice: Invoice
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.4), lineWidth: 0.8)
                    )
                    .frame(width: 44, height: 44)
                Image(systemName: "doc.text.fill")
                    .foregroundStyle(MetrogasTheme.brandBlue)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(invoice.periodLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(compact ? invoice.number : "Vence \(DateFormatter.metrogasDayMonthYear.string(from: invoice.dueDate))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 6) {
                Text(Formatters.money(invoice.amountARS))
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                StatusBadge(status: invoice.status)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, compact ? 12 : 14)
        .contentShape(Rectangle())
    }
}

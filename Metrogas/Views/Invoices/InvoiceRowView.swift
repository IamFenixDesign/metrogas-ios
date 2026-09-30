import SwiftUI

struct InvoiceRowView: View {
    let invoice: Invoice
    var compact: Bool = false

    private var statusTint: Color {
        switch invoice.status {
        case .paid: return MetrogasTheme.success
        case .pending: return MetrogasTheme.warning
        case .overdue: return MetrogasTheme.danger
        }
    }

    var body: some View {
        HStack(spacing: compact ? 10 : 12) {
            invoiceIcon

            VStack(alignment: .leading, spacing: 2) {
                Text(invoice.periodLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(invoice.number)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text("·")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(DateFormatter.metrogasDayMonthYear.string(from: invoice.dueDate))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 4) {
                Text(Formatters.money(invoice.amountARS))
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                StatusBadge(status: invoice.status, compact: true)
            }
        }
        .padding(.horizontal, compact ? 12 : 12)
        .padding(.vertical, compact ? 10 : 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(invoice.periodLabel), \(Formatters.money(invoice.amountARS)), \(invoice.status.rawValue)"
        )
    }

    private var invoiceIcon: some View {
        ZStack {
            Circle()
                .fill(statusTint.opacity(0.14))
                .overlay(
                    Circle()
                        .strokeBorder(statusTint.opacity(0.28), lineWidth: 0.8)
                )
                .frame(width: 32, height: 32)

            Image(systemName: invoice.status.symbolName)
                .font(.caption.weight(.bold))
                .foregroundStyle(statusTint)
                .symbolRenderingMode(.hierarchical)
        }
        .accessibilityHidden(true)
    }
}

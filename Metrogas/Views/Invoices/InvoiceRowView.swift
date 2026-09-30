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
        if compact {
            compactRow
        } else {
            fullRow
        }
    }

    private var compactRow: some View {
        HStack(spacing: 14) {
            statusIcon
            VStack(alignment: .leading, spacing: 4) {
                Text(invoice.periodLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(invoice.number)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                Text(Formatters.money(invoice.amountARS))
                    .font(.subheadline.weight(.bold).monospacedDigit())
                StatusBadge(status: invoice.status)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private var fullRow: some View {
        HStack(spacing: 0) {
            Capsule(style: .continuous)
                .fill(statusTint)
                .frame(width: 4)
                .padding(.vertical, 14)
                .padding(.leading, 4)

            HStack(alignment: .center, spacing: 14) {
                statusIcon

                VStack(alignment: .leading, spacing: 5) {
                    Text(invoice.periodLabel)
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(invoice.number)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Label(
                        "Vence \(DateFormatter.metrogasDayMonthYear.string(from: invoice.dueDate))",
                        systemImage: "calendar"
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 10)

                VStack(alignment: .trailing, spacing: 8) {
                    Text(Formatters.money(invoice.amountARS))
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                    StatusBadge(status: invoice.status)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
        }
        .contentShape(Rectangle())
    }

    private var statusIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(statusTint.opacity(0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(statusTint.opacity(0.28), lineWidth: 0.8)
                )
                .frame(width: 42, height: 42)
            Image(systemName: invoice.status == .paid ? "checkmark.doc.fill" : "doc.text.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(statusTint)
        }
    }
}

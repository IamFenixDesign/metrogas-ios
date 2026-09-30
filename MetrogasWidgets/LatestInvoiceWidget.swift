import WidgetKit
import SwiftUI

struct LatestInvoiceProvider: TimelineProvider {
    func placeholder(in context: Context) -> LatestInvoiceEntry {
        LatestInvoiceEntry(date: .now, item: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (LatestInvoiceEntry) -> Void) {
        completion(LatestInvoiceEntry(date: .now, item: loadNewest() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LatestInvoiceEntry>) -> Void) {
        let entry = LatestInvoiceEntry(date: .now, item: loadNewest())
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now.addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func loadNewest() -> WidgetSnapshotStore.Item? {
        WidgetSnapshotStore.load()?.newest
    }
}

struct LatestInvoiceEntry: TimelineEntry {
    let date: Date
    let item: WidgetSnapshotStore.Item?
}

struct LatestInvoiceWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: LatestInvoiceEntry

    var body: some View {
        Group {
            if let item = entry.item {
                content(item)
            } else {
                emptyState
            }
        }
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [
                    Color(red: 0.00, green: 0.30, blue: 0.67),
                    Color(red: 0.00, green: 0.65, blue: 0.87)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private func content(_ item: WidgetSnapshotStore.Item) -> some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 6 : 8) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text.fill")
                    .font(.caption.weight(.semibold))
                Text("Última factura")
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 0)
                statusChip(item.statusLabel)
            }
            .foregroundStyle(.white.opacity(0.92))

            Spacer(minLength: 0)

            Text(item.amountText)
                .font(family == .systemSmall ? .title3.weight(.bold) : .title2.weight(.bold))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.7)
                .lineLimit(1)

            Text(item.periodLabel)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)

            if family != .systemSmall {
                Text("Vence \(item.dueDateText) · N° \(item.number)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(1)
            } else {
                Text("N° \(item.number)")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(1)
            }
        }
        .padding(2)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Última factura", systemImage: "doc.text.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))
            Spacer(minLength: 0)
            Text("Sin datos")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
            Text("Abrí la app e iniciá sesión para sincronizar.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(2)
    }

    private func statusChip(_ label: String) -> some View {
        Text(label)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.white.opacity(0.22), in: Capsule())
            .foregroundStyle(.white)
    }
}

struct LatestInvoiceWidget: Widget {
    let kind = "LatestInvoiceWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LatestInvoiceProvider()) { entry in
            LatestInvoiceWidgetView(entry: entry)
        }
        .configurationDisplayName("MetroGAS — Última factura")
        .description("Muestra la última factura emitida de tu cuenta MetroGAS.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

private extension WidgetSnapshotStore.Item {
    static let placeholder = WidgetSnapshotStore.Item(
        id: "placeholder",
        number: "00000000",
        periodLabel: "Marzo 2026",
        amountText: "$ 12.450,00",
        statusLabel: "Pendiente",
        dueDateText: "15 mar 2026",
        issuedAt: .now
    )
}

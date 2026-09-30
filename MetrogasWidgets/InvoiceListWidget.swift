import WidgetKit
import SwiftUI

struct InvoiceListProvider: TimelineProvider {
    func placeholder(in context: Context) -> InvoiceListEntry {
        InvoiceListEntry(date: .now, items: WidgetSnapshotStore.Item.placeholders)
    }

    func getSnapshot(in context: Context, completion: @escaping (InvoiceListEntry) -> Void) {
        let items = WidgetSnapshotStore.load()?.items ?? WidgetSnapshotStore.Item.placeholders
        completion(InvoiceListEntry(date: .now, items: Array(items.prefix(limit(for: context.family)))))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<InvoiceListEntry>) -> Void) {
        let loaded = WidgetSnapshotStore.load()?.items ?? []
        let items = Array(loaded.sorted { $0.issuedAt > $1.issuedAt }.prefix(limit(for: context.family)))
        let entry = InvoiceListEntry(date: .now, items: items)
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now.addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func limit(for family: WidgetFamily) -> Int {
        switch family {
        case .systemMedium: return 3
        case .systemLarge: return 6
        default: return 3
        }
    }
}

struct InvoiceListEntry: TimelineEntry {
    let date: Date
    let items: [WidgetSnapshotStore.Item]
}

struct InvoiceListWidgetView: View {
    var entry: InvoiceListEntry

    var body: some View {
        Group {
            if entry.items.isEmpty {
                emptyState
            } else {
                listContent
            }
        }
        .containerBackground(for: .widget) {
            Color(red: 0.96, green: 0.98, blue: 1.0)
        }
    }

    private var listContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "list.bullet.rectangle.fill")
                    .foregroundStyle(Color(red: 0.00, green: 0.30, blue: 0.67))
                Text("Facturas")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color(red: 0.00, green: 0.14, blue: 0.36))
                Spacer(minLength: 0)
                Text("MetroGAS")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color(red: 0.00, green: 0.65, blue: 0.87))
            }

            ForEach(Array(entry.items.enumerated()), id: \.element.id) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.periodLabel)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color(red: 0.00, green: 0.14, blue: 0.36))
                            .lineLimit(1)
                        Text("N° \(item.number) · \(item.statusLabel)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Text(item.amountText)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(statusColor(item.statusLabel))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                if index < entry.items.count - 1 {
                    Divider().opacity(0.35)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(2)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Facturas", systemImage: "list.bullet.rectangle.fill")
                .font(.headline.weight(.bold))
                .foregroundStyle(Color(red: 0.00, green: 0.14, blue: 0.36))
            Spacer(minLength: 0)
            Text("Todavía no hay facturas para mostrar.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Sincronizá desde la app MetroGAS.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(2)
    }

    private func statusColor(_ label: String) -> Color {
        switch label {
        case "Pagada":
            return Color(red: 0.12, green: 0.55, blue: 0.38)
        case "Vencida":
            return Color(red: 0.78, green: 0.22, blue: 0.22)
        default:
            return Color(red: 0.00, green: 0.30, blue: 0.67)
        }
    }
}

struct InvoiceListWidget: Widget {
    let kind = "InvoiceListWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: InvoiceListProvider()) { entry in
            InvoiceListWidgetView(entry: entry)
        }
        .configurationDisplayName("Lista de facturas")
        .description("Listado compacto de tus últimas facturas MetroGAS.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

extension WidgetSnapshotStore.Item {
    static let placeholders: [WidgetSnapshotStore.Item] = [
        .init(
            id: "p1",
            number: "1001",
            periodLabel: "Marzo 2026",
            amountText: "$ 12.450,00",
            statusLabel: "Pendiente",
            dueDateText: "15 mar 2026",
            issuedAt: .now
        ),
        .init(
            id: "p2",
            number: "1000",
            periodLabel: "Febrero 2026",
            amountText: "$ 11.890,00",
            statusLabel: "Pagada",
            dueDateText: "14 feb 2026",
            issuedAt: .now.addingTimeInterval(-86400 * 30)
        ),
        .init(
            id: "p3",
            number: "0999",
            periodLabel: "Enero 2026",
            amountText: "$ 13.210,00",
            statusLabel: "Pagada",
            dueDateText: "15 ene 2026",
            issuedAt: .now.addingTimeInterval(-86400 * 60)
        )
    ]
}

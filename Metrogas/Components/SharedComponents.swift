import SwiftUI

struct StatusBadge: View {
    let status: InvoiceStatus
    var compact: Bool = false

    private var tint: Color {
        switch status {
        case .paid: return MetrogasTheme.success
        case .pending: return MetrogasTheme.warning
        case .overdue: return MetrogasTheme.danger
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: status.symbolName)
                .font(compact ? .caption2.weight(.bold) : .caption.weight(.semibold))
            if !compact {
                Text(status.rawValue)
                    .font(.caption.weight(.semibold))
            }
        }
        .foregroundStyle(tint)
        .padding(.horizontal, compact ? 7 : 10)
        .padding(.vertical, compact ? 4 : 5)
        .background {
            Capsule(style: .continuous)
                .fill(tint.opacity(0.16))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(tint.opacity(0.28), lineWidth: 0.8)
                )
        }
        .accessibilityLabel("Estado: \(status.rawValue)")
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(MetrogasTheme.sectionFont)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MetricTile: View {
    let title: String
    let value: String
    let icon: String
    var accent: Color = MetrogasTheme.brandBlue

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(accent)
                .symbolEffect(.pulse, options: .repeating.speed(0.35), isActive: true)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(cornerRadius: 20)
    }
}

struct GlassChip: View {
    let title: String
    var icon: String? = nil
    var selected: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon)
                        .font(.caption.weight(.semibold))
                }
                Text(title)
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background {
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        if selected {
                            Capsule(style: .continuous)
                                .fill(MetrogasTheme.brandBlue.opacity(0.92))
                        }
                    }
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(
                                selected ? Color.white.opacity(0.35) : Color.white.opacity(0.45),
                                lineWidth: 1
                            )
                    )
            }
            .foregroundStyle(selected ? .white : .primary)
        }
        .buttonStyle(.plain)
        .animation(MetrogasTheme.springSnappy, value: selected)
    }
}

struct PressableGlassStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(MetrogasTheme.springSnappy, value: configuration.isPressed)
    }
}

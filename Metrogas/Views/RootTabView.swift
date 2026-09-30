import SwiftUI

enum AppTab: Hashable, CaseIterable {
    case home, invoices, consumption, account

    var title: String {
        switch self {
        case .home: return "Inicio"
        case .invoices: return "Facturas"
        case .consumption: return "Consumo"
        case .account: return "Cuenta"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "flame.fill"
        case .invoices: return "doc.text.fill"
        case .consumption: return "chart.bar.fill"
        case .account: return "person.crop.circle.fill"
        }
    }
}

struct RootTabView: View {
    @State private var selected: AppTab = .home
    @Namespace private var tabNamespace

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selected {
                case .home:
                    HomeView()
                case .invoices:
                    InvoiceListView()
                case .consumption:
                    ConsumptionView()
                case .account:
                    AccountView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            glassTabBar
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
                // El tab bar flota; el espacio lo reservan los scrolls de cada tab.
                .allowsHitTesting(true)
        }
        .animation(MetrogasTheme.springSoft, value: selected)
    }

    private var glassTabBar: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                tabButton(tab)
            }
        }
        .padding(6)
        .liquidGlass(cornerRadius: 28, prominent: true)
        .accessibilityElement(children: .contain)
    }

    private func tabButton(_ tab: AppTab) -> some View {
        let isSelected = selected == tab
        return Button {
            withAnimation(MetrogasTheme.springBouncy) {
                selected = tab
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .symbolEffect(.bounce, value: isSelected)
                    .frame(height: 22)
                Text(tab.title)
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.72))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background {
                if isSelected {
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [MetrogasTheme.brandBlue, MetrogasTheme.brandCyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: MetrogasTheme.brandBlue.opacity(0.35), radius: 10, y: 4)
                        .matchedGeometryEffect(id: "tabGlow", in: tabNamespace)
                }
            }
        }
        .buttonStyle(PressableGlassStyle())
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Espaciador inferior para que el tab bar flotante no tape filas/botones.
struct FloatingTabBarSpacer: View {
    var body: some View {
        Color.clear
            .frame(height: MetrogasTheme.floatingTabBarClearance)
            .accessibilityHidden(true)
    }
}

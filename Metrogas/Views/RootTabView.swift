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
    @StateObject private var tabScroll = TabBarScrollState()
    @State private var selected: AppTab = .home
    @Namespace private var tabNamespace

    private var isCompact: Bool { tabScroll.isCompact }

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
            .environmentObject(tabScroll)

            glassTabBar
                .padding(.horizontal, isCompact ? 40 : 20)
                .padding(.bottom, isCompact ? 6 : 8)
                .allowsHitTesting(true)
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.88), value: isCompact)
        .animation(MetrogasTheme.springSoft, value: selected)
        .onAppear {
            TabBarScrollState.shared = tabScroll
        }
        .onChange(of: selected) { _, _ in
            tabScroll.reset()
            TabBarScrollState.shared = tabScroll
        }
    }

    private var glassTabBar: some View {
        HStack(spacing: isCompact ? 2 : 4) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                tabButton(tab)
            }
        }
        .padding(isCompact ? 4 : 6)
        .liquidGlass(cornerRadius: isCompact ? 22 : 28, prominent: true)
        .accessibilityElement(children: .contain)
    }

    private func tabButton(_ tab: AppTab) -> some View {
        let isSelected = selected == tab
        return Button {
            withAnimation(MetrogasTheme.springBouncy) {
                selected = tab
                tabScroll.reset()
            }
        } label: {
            VStack(spacing: isCompact ? 0 : 4) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: isCompact ? 16 : 18, weight: .semibold))
                    .symbolEffect(.bounce, value: isSelected)
                    .frame(height: isCompact ? 18 : 22)

                if !isCompact {
                    Text(tab.title)
                        .font(.caption2.weight(.semibold))
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.72))
            .frame(maxWidth: .infinity)
            .padding(.vertical, isCompact ? 8 : 10)
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

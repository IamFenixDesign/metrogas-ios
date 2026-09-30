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
                .padding(.horizontal, tabScroll.isCompact ? 56 : 20)
                .padding(.bottom, tabScroll.isCompact ? 0 : 8)
                .scaleEffect(tabScroll.isCompact ? 0.86 : 1, anchor: .bottom)
                .offset(y: tabScroll.isCompact ? 44 : 0)
                .opacity(tabScroll.isCompact ? 0.0 : 1)
                // Cuando está compacta queda casi oculta abajo; un toque en el borde inferior la restaura.
                .overlay(alignment: .bottom) {
                    if tabScroll.isCompact {
                        Color.clear
                            .frame(height: 28)
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                tabScroll.reset()
                            }
                            .offset(y: 36)
                    }
                }
                .allowsHitTesting(true)
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.88), value: tabScroll.isCompact)
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
                tabScroll.reset()
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

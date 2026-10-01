import SwiftUI

enum AppTab: Hashable, CaseIterable, Identifiable {
    case home, invoices, consumption, account

    var id: Self { self }

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

    /// Spring corto para el pill del tab bar.
    private var tabSpring: Animation {
        .spring(response: 0.34, dampingFraction: 0.84, blendDuration: 0.12)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Fondo fijo bajo todos los tabs → nunca se ve negro al cambiar.
            LiquidGlassBackground()

            ZStack {
                ForEach(AppTab.allCases) { tab in
                    tabRoot(tab)
                        .environment(\.metrogasTabActive, selected == tab)
                        // Tabs inactivos sin nav bar → evita franja negra al cruzar stacks.
                        .toolbar(selected == tab && tab != .home ? .automatic : .hidden, for: .navigationBar)
                        .toolbarBackground(.hidden, for: .navigationBar)
                        // Sin scale/offset: esos dejaban un hueco arriba (franja negra).
                        .opacity(selected == tab ? 1 : 0)
                        .allowsHitTesting(selected == tab)
                        .zIndex(selected == tab ? 1 : 0)
                        .accessibilityHidden(selected != tab)
                        // El contenido cambia al instante; solo anima el pill.
                        .transaction { transaction in
                            transaction.animation = nil
                        }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environmentObject(tabScroll)

            glassTabBar
                .padding(.horizontal, isCompact ? 40 : 20)
                .padding(.bottom, isCompact ? 6 : 8)
                .allowsHitTesting(true)
                .animation(tabSpring, value: isCompact)
        }
        .sensoryFeedback(.selection, trigger: selected)
        .onAppear {
            TabBarScrollState.shared = tabScroll
        }
        .onChange(of: selected) { _, _ in
            tabScroll.reset()
            TabBarScrollState.shared = tabScroll
        }
    }

    @ViewBuilder
    private func tabRoot(_ tab: AppTab) -> some View {
        switch tab {
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

    private var glassTabBar: some View {
        HStack(spacing: isCompact ? 2 : 4) {
            ForEach(AppTab.allCases) { tab in
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
            guard selected != tab else { return }
            withAnimation(tabSpring) {
                selected = tab
            }
        } label: {
            VStack(spacing: isCompact ? 0 : 4) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: isCompact ? 16 : 18, weight: .semibold))
                    .symbolEffect(.bounce, options: .speed(1.35), value: isSelected)
                    .frame(height: isCompact ? 18 : 22)

                if !isCompact {
                    Text(tab.title)
                        .font(.caption2.weight(.semibold))
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .bottom)),
                                removal: .opacity
                            )
                        )
                }
            }
            .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.72))
            .frame(maxWidth: .infinity)
            .padding(.vertical, isCompact ? 8 : 10)
            .contentShape(Rectangle())
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
        .buttonStyle(TabBarButtonStyle())
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Feedback de toque liviano: no pelea con el spring del pill.
private struct TabBarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
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

import SwiftUI

/// Controla si el tab bar flotante se muestra compacto al scrollear.
@MainActor
final class TabBarScrollState: ObservableObject {
    @Published private(set) var isCompact = false

    private var lastOffset: CGFloat = 0
    private var hasBaseline = false
    private var baselineMinY: CGFloat = 0

    func reset() {
        isCompact = false
        lastOffset = 0
        hasBaseline = false
        baselineMinY = 0
    }

    /// `minY` global del probe al tope del contenido scrolleable.
    func handleProbeMinY(_ minY: CGFloat) {
        if !hasBaseline {
            baselineMinY = minY
            hasBaseline = true
            lastOffset = 0
            return
        }

        // Al scrollear hacia abajo el probe sube (minY baja) → offset positivo.
        let offset = max(0, baselineMinY - minY)
        apply(offset: offset)
    }

    private func apply(offset: CGFloat) {
        let delta = offset - lastOffset
        lastOffset = offset

        if offset <= 12 {
            setCompact(false)
            return
        }

        guard abs(delta) > 1 else { return }

        if delta > 6 {
            setCompact(true)
        } else if delta < -4 {
            setCompact(false)
        }
    }

    private func setCompact(_ value: Bool) {
        guard isCompact != value else { return }
        withAnimation(MetrogasTheme.springSnappy) {
            isCompact = value
        }
    }
}

private struct TabBarScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Probe de 0 altura al inicio del contenido; reporta su minY global.
struct TabBarScrollProbe: View {
    var body: some View {
        GeometryReader { geo in
            Color.clear
                .preference(key: TabBarScrollOffsetKey.self, value: geo.frame(in: .global).minY)
        }
        .frame(height: 0)
        .accessibilityHidden(true)
    }
}

extension View {
    /// Escucha el probe y actualiza el tab bar.
    func tracksFloatingTabBar(_ state: TabBarScrollState) -> some View {
        onPreferenceChange(TabBarScrollOffsetKey.self) { minY in
            state.handleProbeMinY(minY)
        }
    }
}

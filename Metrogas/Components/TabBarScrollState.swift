import SwiftUI
import UIKit

/// Controla si el tab bar flotante se muestra compacto al scrollear.
@MainActor
final class TabBarScrollState: ObservableObject {
    @Published var isCompact = false

    private var lastOffset: CGFloat = 0
    private var accumulated: CGFloat = 0

    func reset() {
        isCompact = false
        lastOffset = 0
        accumulated = 0
    }

    func handleScroll(offsetY: CGFloat) {
        let delta = offsetY - lastOffset
        lastOffset = offsetY

        // Cerca del tope: siempre expandida.
        if offsetY <= 8 {
            if isCompact {
                withAnimation(MetrogasTheme.springSnappy) { isCompact = false }
            }
            accumulated = 0
            return
        }

        // Ignorar micro-movimientos.
        guard abs(delta) > 0.5 else { return }

        if delta * accumulated < 0 {
            accumulated = 0
        }
        accumulated += delta

        if accumulated > 24, !isCompact {
            withAnimation(MetrogasTheme.springSnappy) { isCompact = true }
            accumulated = 0
        } else if accumulated < -18, isCompact {
            withAnimation(MetrogasTheme.springSnappy) { isCompact = false }
            accumulated = 0
        }
    }
}

/// Observa el UIScrollView contenedor (ScrollView o List) y reporta el offset.
struct ScrollOffsetReader: UIViewRepresentable {
    let onOffsetChange: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onOffsetChange: onOffsetChange)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onOffsetChange = onOffsetChange
        DispatchQueue.main.async {
            context.coordinator.attach(to: uiView)
        }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator: NSObject {
        var onOffsetChange: (CGFloat) -> Void
        private weak var scrollView: UIScrollView?
        private var observation: NSKeyValueObservation?

        init(onOffsetChange: @escaping (CGFloat) -> Void) {
            self.onOffsetChange = onOffsetChange
        }

        func attach(to view: UIView) {
            guard let scroll = view.enclosingScrollView() else { return }
            if scrollView === scroll, observation != nil { return }
            detach()
            scrollView = scroll
            observation = scroll.observe(\.contentOffset, options: [.new]) { [weak self] scrollView, _ in
                let y = max(0, scrollView.contentOffset.y + scrollView.adjustedContentInset.top)
                DispatchQueue.main.async {
                    self?.onOffsetChange(y)
                }
            }
        }

        func detach() {
            observation?.invalidate()
            observation = nil
            scrollView = nil
        }
    }
}

private extension UIView {
    func enclosingScrollView() -> UIScrollView? {
        var current: UIView? = self
        while let view = current {
            if let scroll = view as? UIScrollView {
                return scroll
            }
            current = view.superview
        }
        return nil
    }
}

extension View {
    /// Engancha el scroll de esta pantalla al tab bar compactable.
    func tracksFloatingTabBar(_ state: TabBarScrollState) -> some View {
        background {
            ScrollOffsetReader { offset in
                state.handleScroll(offsetY: offset)
            }
        }
    }
}

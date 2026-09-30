import SwiftUI
import UIKit

/// Estado compartido del tab bar (también accesible desde UIKit).
@MainActor
final class TabBarScrollState: ObservableObject {
    static weak var shared: TabBarScrollState?

    @Published private(set) var isCompact = false

    private var lastOffset: CGFloat = 0
    private var didReceiveOffset = false

    func reset() {
        setCompact(false)
        lastOffset = 0
        didReceiveOffset = false
    }

    /// Offset del scroll (0 = tope). Baja → oculta; sube o tope → muestra.
    func update(offset: CGFloat) {
        if !didReceiveOffset {
            didReceiveOffset = true
            lastOffset = offset
            return
        }

        let delta = offset - lastOffset
        lastOffset = offset

        if offset < 20 {
            setCompact(false)
            return
        }

        guard abs(delta) > 2.5 else { return }

        if delta > 0 {
            setCompact(true)
        } else {
            setCompact(false)
        }
    }

    private func setCompact(_ value: Bool) {
        guard isCompact != value else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
            isCompact = value
        }
    }
}

/// Vista UIKit colocada DENTRO del contenido scrolleable; observa el UIScrollView padre.
struct TabBarScrollProbe: View {
    var body: some View {
        ScrollOffsetMonitorView()
            .frame(width: 1, height: 1)
            .opacity(0.01)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct ScrollOffsetMonitorView: UIViewRepresentable {
    func makeUIView(context: Context) -> ScrollOffsetMonitorUIView {
        ScrollOffsetMonitorUIView()
    }

    func updateUIView(_ uiView: ScrollOffsetMonitorUIView, context: Context) {
        uiView.ensureAttached()
    }
}

private final class ScrollOffsetMonitorUIView: UIView {
    private var observation: NSKeyValueObservation?
    private weak var observedScrollView: UIScrollView?
    private var retryWorkItem: DispatchWorkItem?
    private var retries = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        ensureAttached()
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        ensureAttached()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        ensureAttached()
    }

    func ensureAttached() {
        if observation != nil, observedScrollView != nil { return }

        retryWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.attachIfPossible()
        }
        retryWorkItem = work
        DispatchQueue.main.async(execute: work)
    }

    private func attachIfPossible() {
        if let scroll = findEnclosingScrollView() {
            beginObserving(scroll)
            return
        }

        retries += 1
        guard retries < 40 else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.attachIfPossible()
        }
        retryWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }

    private func beginObserving(_ scroll: UIScrollView) {
        observation?.invalidate()
        observedScrollView = scroll
        observation = scroll.observe(\.contentOffset, options: [.initial, .new]) { scrollView, _ in
            let insetTop = scrollView.adjustedContentInset.top
            let y = scrollView.contentOffset.y + insetTop
            let offset = max(0, y)
            DispatchQueue.main.async {
                TabBarScrollState.shared?.update(offset: offset)
            }
        }
    }

    private func findEnclosingScrollView() -> UIScrollView? {
        var current: UIView? = self
        while let view = current {
            if let scroll = view as? UIScrollView {
                // Evitar scrap/horizontal chips: preferir scroll views verticales grandes.
                if scroll.bounds.height > 80 || scroll is UITableView || scroll is UICollectionView {
                    return scroll
                }
            }
            current = view.superview
        }

        // Fallback: buscar en el window el scroll view que contiene este punto.
        guard let window else { return nil }
        let point = convert(bounds.center, to: window)
        return window.findVerticalScrollView(containing: point)
    }

    deinit {
        observation?.invalidate()
        retryWorkItem?.cancel()
    }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}

private extension UIView {
    func findVerticalScrollView(containing point: CGPoint) -> UIScrollView? {
        var best: UIScrollView?
        var bestArea: CGFloat = 0

        func visit(_ view: UIView) {
            if let scroll = view as? UIScrollView,
               scroll.bounds.height > 120,
               scroll.contentSize.height > scroll.bounds.height + 20 {
                let frameInWindow = scroll.convert(scroll.bounds, to: nil)
                if frameInWindow.contains(point) || best == nil {
                    let area = scroll.bounds.width * scroll.bounds.height
                    if area > bestArea {
                        bestArea = area
                        best = scroll
                    }
                }
            }
            for sub in view.subviews {
                visit(sub)
            }
        }

        visit(self)
        return best
    }
}

extension View {
    /// Compat: el probe ya actualiza el estado; se mantiene por claridad en las vistas.
    func tracksFloatingTabBar(_ state: TabBarScrollState) -> some View {
        onAppear {
            TabBarScrollState.shared = state
        }
    }
}

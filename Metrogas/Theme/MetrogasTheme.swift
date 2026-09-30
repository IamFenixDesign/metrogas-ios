import SwiftUI

enum MetrogasTheme {
    /// Azul institucional oficial (#004cac)
    static let brandBlue = Color("BrandBlue")
    /// Cian del isotipo (#00a6dd)
    static let brandCyan = Color("BrandCyan")
    /// Naranja llama oficial (#ff5200)
    static let brandFlame = Color("BrandFlame")
    static let brandSky = Color("BrandSky")

    static let deepNavy = Color(red: 0.00, green: 0.14, blue: 0.36)

    static let success = Color(red: 0.12, green: 0.55, blue: 0.38)
    static let warning = Color(red: 0.85, green: 0.52, blue: 0.08)
    static let danger = Color(red: 0.78, green: 0.22, blue: 0.22)

    static var displayFont: Font {
        .system(.largeTitle, design: .rounded).weight(.bold)
    }

    static var sectionFont: Font {
        .system(.headline, design: .rounded).weight(.semibold)
    }

    static var titleFont: Font {
        .system(.title2, design: .rounded).weight(.semibold)
    }

    // MARK: Motion

    static let springSnappy = Animation.spring(response: 0.38, dampingFraction: 0.86)
    static let springSoft = Animation.spring(response: 0.55, dampingFraction: 0.84)
    static let springBouncy = Animation.spring(response: 0.45, dampingFraction: 0.72)
}

// MARK: - Liquid Glass surfaces

struct LiquidGlassBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: false)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [MetrogasTheme.deepNavy, Color(red: 0.05, green: 0.12, blue: 0.22), Color.black]
                        : [
                            MetrogasTheme.brandCyan.opacity(0.22),
                            MetrogasTheme.brandSky.opacity(0.95),
                            Color(.systemBackground),
                            MetrogasTheme.brandBlue.opacity(0.10)
                        ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .fill(MetrogasTheme.brandCyan.opacity(colorScheme == .dark ? 0.22 : 0.16))
                    .frame(width: 300, height: 300)
                    .blur(radius: 48)
                    .offset(x: 120 + CGFloat(sin(t * 0.35)) * 18, y: -190 + CGFloat(cos(t * 0.28)) * 14)

                Circle()
                    .fill(MetrogasTheme.brandFlame.opacity(colorScheme == .dark ? 0.14 : 0.10))
                    .frame(width: 260, height: 260)
                    .blur(radius: 42)
                    .offset(x: -150 + CGFloat(cos(t * 0.32)) * 16, y: 320 + CGFloat(sin(t * 0.26)) * 12)

                Circle()
                    .fill(MetrogasTheme.brandBlue.opacity(colorScheme == .dark ? 0.18 : 0.08))
                    .frame(width: 200, height: 200)
                    .blur(radius: 36)
                    .offset(x: 40 + CGFloat(sin(t * 0.22)) * 22, y: 120)
            }
        }
        .ignoresSafeArea()
    }
}

/// Alias para no romper llamadas existentes.
struct MetrogasBackground: View {
    var body: some View { LiquidGlassBackground() }
}

struct LiquidGlassShape: ViewModifier {
    var cornerRadius: CGFloat = 24
    var prominent: Bool = false

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(prominent ? 0.28 : 0.18),
                                    Color.white.opacity(0.02),
                                    Color.white.opacity(0.08)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .blendMode(.plusLighter)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.65),
                                    Color.white.opacity(0.12),
                                    Color.white.opacity(0.35)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
                .shadow(color: Color.black.opacity(0.10), radius: prominent ? 24 : 16, y: prominent ? 12 : 8)
            }
    }
}

extension View {
    func liquidGlass(cornerRadius: CGFloat = 24, prominent: Bool = false) -> some View {
        modifier(LiquidGlassShape(cornerRadius: cornerRadius, prominent: prominent))
    }

    /// Entrada escalonada tipo Liquid Glass.
    func appearMotion(visible: Bool, index: Int = 0) -> some View {
        self
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : 18)
            .scaleEffect(visible ? 1 : 0.97)
            .animation(MetrogasTheme.springSoft.delay(Double(index) * 0.06), value: visible)
    }
}

struct MetrogasLogo: View {
    var height: CGFloat = 36
    var alignment: Alignment = .leading

    var body: some View {
        Image("MetrogasLogo")
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .frame(maxWidth: .infinity, alignment: alignment)
            .accessibilityLabel("MetroGAS")
    }
}

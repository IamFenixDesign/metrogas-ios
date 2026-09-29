import SwiftUI

enum MetrogasTheme {
    /// Azul institucional oficial (#004cac)
    static let brandBlue = Color("BrandBlue")
    /// Cian del isotipo (#00a6dd)
    static let brandCyan = Color("BrandCyan")
    /// Naranja llama oficial (#ff5200)
    static let brandFlame = Color("BrandFlame")
    /// Fondo cielo suave
    static let brandSky = Color("BrandSky")

    /// Azul profundo derivado del institucional
    static let deepNavy = Color(red: 0.00, green: 0.18, blue: 0.42)
    static let softMist = Color(red: 0.93, green: 0.96, blue: 0.99)
    static let warmSand = Color(red: 0.98, green: 0.96, blue: 0.94)

    static let success = Color(red: 0.12, green: 0.55, blue: 0.38)
    static let warning = Color(red: 0.85, green: 0.52, blue: 0.08)
    static let danger = Color(red: 0.78, green: 0.22, blue: 0.22)

    static var displayFont: Font {
        .system(.largeTitle, design: .rounded).weight(.bold)
    }

    static var titleFont: Font {
        .system(.title2, design: .rounded).weight(.semibold)
    }

    static var sectionFont: Font {
        .system(.headline, design: .rounded).weight(.semibold)
    }
}

extension View {
    func metrogasCardBackground() -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.background.opacity(0.92))
                    .shadow(color: MetrogasTheme.deepNavy.opacity(0.08), radius: 12, y: 4)
            )
    }
}

struct MetrogasBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    MetrogasTheme.brandCyan.opacity(0.18),
                    MetrogasTheme.brandSky.opacity(0.95),
                    Color(.systemBackground),
                    MetrogasTheme.brandBlue.opacity(0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Soft brand mark wash (top-right)
            Circle()
                .fill(MetrogasTheme.brandCyan.opacity(0.12))
                .frame(width: 280, height: 280)
                .blur(radius: 40)
                .offset(x: 140, y: -180)

            Circle()
                .fill(MetrogasTheme.brandFlame.opacity(0.08))
                .frame(width: 220, height: 220)
                .blur(radius: 36)
                .offset(x: -150, y: 320)
        }
        .ignoresSafeArea()
    }
}

/// Official MetroGAS wordmark from metrogas.com.ar asset catalog.
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

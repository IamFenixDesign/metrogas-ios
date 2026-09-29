import SwiftUI

enum MetrogasTheme {
    /// Azul institucional Metrogas
    static let brandBlue = Color("BrandBlue")
    /// Llama / acento cálido
    static let brandFlame = Color("BrandFlame")
    /// Cielo suave para fondos
    static let brandSky = Color("BrandSky")

    static let deepNavy = Color(red: 0.05, green: 0.16, blue: 0.32)
    static let softMist = Color(red: 0.93, green: 0.96, blue: 0.98)
    static let warmSand = Color(red: 0.98, green: 0.96, blue: 0.93)

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
        LinearGradient(
            colors: [
                MetrogasTheme.brandSky.opacity(0.95),
                Color(.systemBackground),
                MetrogasTheme.warmSand.opacity(0.55)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

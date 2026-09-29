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

    static var sectionFont: Font {
        .system(.headline, design: .rounded).weight(.semibold)
    }
}

struct MetrogasBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    MetrogasTheme.brandCyan.opacity(0.16),
                    MetrogasTheme.brandSky.opacity(0.9),
                    Color(.systemBackground),
                    MetrogasTheme.brandBlue.opacity(0.07)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(MetrogasTheme.brandCyan.opacity(0.10))
                .frame(width: 260, height: 260)
                .blur(radius: 36)
                .offset(x: 130, y: -170)

            Circle()
                .fill(MetrogasTheme.brandFlame.opacity(0.07))
                .frame(width: 220, height: 220)
                .blur(radius: 30)
                .offset(x: -140, y: 300)
        }
        .ignoresSafeArea()
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

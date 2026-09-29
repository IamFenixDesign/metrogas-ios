import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var session: AppSession

    var body: some View {
        NavigationStack {
            ZStack {
                MetrogasBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        hero
                        sessionCard
                        actions
                        infoNote
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Image("MetrogasLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 22)
                        .accessibilityHidden(true)
                }
            }
            .sheet(isPresented: $session.showLoginPortal) {
                NavigationStack {
                    MetrogasPortalScreen(title: "Oficina Virtual", url: session.portalStartURL)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cerrar") { session.showLoginPortal = false }
                            }
                        }
                }
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            MetrogasLogo(height: 40, alignment: .leading)
                .frame(maxWidth: 190, alignment: .leading)
                .padding(.top, 6)

            Text("Tu cuenta MetroGAS")
                .font(.system(size: 28, weight: .bold, design: .rounded))

            Text("Facturas, consumo y trámites con tu usuario real de la Oficina Virtual.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var sessionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Sesión activa", systemImage: "checkmark.shield.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.92))

            Text("Estás conectado a la Oficina Virtual de MetroGAS.")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)

            Text("Los datos de facturación y consumo se muestran desde el portal oficial.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            MetrogasTheme.deepNavy,
                            MetrogasTheme.brandBlue,
                            MetrogasTheme.brandCyan.opacity(0.95)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: MetrogasTheme.brandBlue.opacity(0.28), radius: 16, y: 8)
        )
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Accesos", subtitle: "Abrí el portal oficial de MetroGAS")

            actionRow(
                title: "Ver Oficina Virtual",
                subtitle: "Inicio de tu cuenta",
                icon: "house.fill",
                tint: MetrogasTheme.brandBlue
            ) {
                session.openPortal(at: MetrogasURLs.portalMobile)
            }

            actionRow(
                title: "Facturas y pagos",
                subtitle: "Consultá y pagá en el portal",
                icon: "doc.text.fill",
                tint: MetrogasTheme.brandFlame
            ) {
                session.openPortal(at: MetrogasURLs.portalMobile)
            }

            actionRow(
                title: "Consumo y lecturas",
                subtitle: "Historial disponible en Oficina Virtual",
                icon: "chart.bar.fill",
                tint: MetrogasTheme.brandCyan
            ) {
                session.openPortal(at: MetrogasURLs.portalMobile)
            }
        }
    }

    private func actionRow(
        title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(tint.opacity(0.14))
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .foregroundStyle(tint)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
        .buttonStyle(.plain)
    }

    private var infoNote: some View {
        Text("Esta app no usa datos de demostración. El acceso y la información corresponden a tu cuenta real en micuenta.metrogas.com.ar.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
    }
}

#Preview {
    HomeView()
        .environmentObject(AppSession())
}

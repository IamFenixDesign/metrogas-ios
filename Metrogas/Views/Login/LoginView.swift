import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var session: AppSession
    @State private var appear = false

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                Spacer(minLength: 24)

                VStack(spacing: 18) {
                    Image("MetrogasLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 52)
                        .padding(.horizontal, 36)
                        .colorScheme(.dark)
                        .opacity(appear ? 1 : 0)
                        .offset(y: appear ? 0 : 12)

                    Text("Oficina Virtual")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .opacity(appear ? 1 : 0)

                    Text("Ingresá con tu cuenta real de MetroGAS para ver facturas, consumo y gestiones.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.88))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                        .opacity(appear ? 1 : 0)
                }

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        session.beginLogin()
                    } label: {
                        Text("Iniciar sesión")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(MetrogasTheme.brandFlame)

                    Button {
                        session.beginRegistration()
                    } label: {
                        Text("Registrarme en Oficina Virtual")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)

                    Link("Sitio oficial MetroGAS", destination: MetrogasURLs.sitioInstitucional)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(.top, 4)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 36)
                .opacity(appear ? 1 : 0)
                .offset(y: appear ? 0 : 18)
            }
        }
        .sheet(isPresented: $session.showLoginPortal) {
            NavigationStack {
                MetrogasPortalScreen(
                    title: "Acceso MetroGAS",
                    url: session.portalStartURL,
                    showsConfirmLogin: true
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cerrar") { session.showLoginPortal = false }
                    }
                }
            }
            .presentationDetents([.large])
            .interactiveDismissDisabled(false)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.7)) { appear = true }
        }
        .onChange(of: session.isAuthenticated) { _, loggedIn in
            if loggedIn { session.showLoginPortal = false }
        }
    }

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [
                    MetrogasTheme.deepNavy,
                    MetrogasTheme.brandBlue,
                    MetrogasTheme.brandCyan
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(MetrogasTheme.brandFlame.opacity(0.18))
                .frame(width: 280, height: 280)
                .blur(radius: 30)
                .offset(x: 140, y: -220)

            Circle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 320, height: 320)
                .offset(x: -160, y: 260)
        }
    }
}

#Preview {
    LoginView()
        .environmentObject(AppSession())
}

import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var session: AppSession

    @State private var appear = false
    @State private var showOtherAccountForm = false

    private var showContinueCard: Bool {
        session.canContinueWithSavedAccount && !showOtherAccountForm
    }

    var body: some View {
        ZStack {
            LiquidGlassBackground()

            ScrollView {
                VStack(spacing: 0) {
                    brandHeader
                        .padding(.top, 56)
                        .padding(.bottom, 28)
                        .appearMotion(visible: appear, index: 0)

                    Group {
                        if showContinueCard {
                            continueCard
                        } else {
                            loginCard
                        }
                    }
                    .padding(.horizontal, 20)
                    .appearMotion(visible: appear, index: 1)

                    footerLinks
                        .padding(.top, 22)
                        .padding(.bottom, 36)
                        .appearMotion(visible: appear, index: 2)
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .sheet(isPresented: $session.showWebLogin) {
            if let url = session.webLoginURL {
                GoogleAuthSheet(startURL: url)
                    .environmentObject(session)
                    .presentationDetents([.large])
            }
        }
        .onAppear {
            showOtherAccountForm = false
            withAnimation(MetrogasTheme.springSoft) { appear = true }
        }
        .onChange(of: session.canContinueWithSavedAccount) { _, canContinue in
            if canContinue {
                showOtherAccountForm = false
            }
        }
    }

    private var brandHeader: some View {
        VStack(spacing: 16) {
            Image("MetrogasLogo")
                .resizable()
                .scaledToFit()
                .frame(height: 48)
                .padding(.horizontal, 28)
                .padding(.vertical, 18)
                .liquidGlass(cornerRadius: 26, prominent: true)

            Text("Oficina Virtual")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text(showContinueCard
                 ? "Tu sesión quedó lista para continuar."
                 : "Entrá con el mismo Acceso Mi Cuenta de la web.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
    }

    private var continueCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(MetrogasTheme.brandBlue.opacity(0.12))
                        .frame(width: 52, height: 52)
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(MetrogasTheme.brandBlue)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Continuar")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(session.rememberedAccountEmail ?? "")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 0)
            }
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.55))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.5), lineWidth: 1)
                    )
            }

            if let error = session.loginError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(MetrogasTheme.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                Task { await session.continueWithSavedAccount() }
            } label: {
                HStack {
                    if session.isLoggingIn && !session.showWebLogin {
                        ProgressView().tint(.white)
                    }
                    Text("Continuar")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(.white)
                .background {
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [MetrogasTheme.brandBlue, MetrogasTheme.brandCyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: MetrogasTheme.brandBlue.opacity(0.3), radius: 12, y: 6)
                }
            }
            .buttonStyle(PressableGlassStyle())
            .disabled(session.isLoggingIn)

            Button {
                withAnimation(MetrogasTheme.springSnappy) {
                    session.useAnotherAccount()
                    showOtherAccountForm = true
                }
            } label: {
                Text("Usar otra cuenta")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MetrogasTheme.brandBlue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .disabled(session.isLoggingIn)
        }
        .padding(22)
        .liquidGlass(cornerRadius: 28, prominent: true)
    }

    private var loginCard: some View {
        VStack(spacing: 16) {
            Text("Se abre el mismo inicio de sesión de MetroGAS (Acceso Mi Cuenta), con email o Google.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let error = session.loginError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(MetrogasTheme.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Button {
                Task { await session.startWebLogin() }
            } label: {
                HStack {
                    if session.isLoggingIn && !session.showWebLogin {
                        ProgressView().tint(.white)
                    }
                    Text("Ingresar")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(.white)
                .background {
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [MetrogasTheme.brandFlame, MetrogasTheme.brandFlame.opacity(0.85)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: MetrogasTheme.brandFlame.opacity(0.35), radius: 12, y: 6)
                }
            }
            .buttonStyle(PressableGlassStyle())
            .disabled(session.isLoggingIn)
        }
        .padding(22)
        .liquidGlass(cornerRadius: 28, prominent: true)
    }

    private var footerLinks: some View {
        VStack(spacing: 12) {
            Link("Registrarme en Oficina Virtual", destination: MetrogasURLs.registro)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MetrogasTheme.brandBlue)

            Link("Sitio oficial MetroGAS", destination: MetrogasURLs.sitioInstitucional)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}

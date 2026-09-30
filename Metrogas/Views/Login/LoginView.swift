import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var session: AppSession

    @State private var email = ""
    @State private var password = ""
    @State private var appear = false
    @State private var showOtherAccountForm = false
    @FocusState private var focusedField: Field?

    private enum Field {
        case email, password
    }

    private var showGoogleContinue: Bool {
        session.canContinueWithGoogle && !showOtherAccountForm
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
                        if showGoogleContinue {
                            googleContinueCard
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
        .sheet(isPresented: $session.showGoogleAuth) {
            if let url = session.googleAuthURL {
                GoogleAuthSheet(startURL: url)
                    .environmentObject(session)
                    .presentationDetents([.large])
            }
        }
        .onAppear {
            if email.isEmpty, let saved = session.loginEmail {
                email = saved
            }
            showOtherAccountForm = false
            withAnimation(MetrogasTheme.springSoft) { appear = true }
        }
        .onChange(of: session.canContinueWithGoogle) { _, canContinue in
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

            Text(showGoogleContinue
                 ? "Tu cuenta de Google ya está lista para continuar."
                 : "Ingresá con tu cuenta MetroGAS.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
    }

    /// Sección sin email/contraseña cuando Google ya estuvo iniciado.
    private var googleContinueCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(MetrogasTheme.brandBlue.opacity(0.12))
                        .frame(width: 52, height: 52)
                    Image(systemName: "g.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(MetrogasTheme.brandBlue)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Continuar con Google")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(session.rememberedGoogleEmail ?? "")
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
                focusedField = nil
                Task { await session.continueWithSavedGoogleAccount() }
            } label: {
                HStack {
                    if session.isLoggingIn && !session.showGoogleAuth {
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
                    email = ""
                    password = ""
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
            VStack(spacing: 12) {
                TextField("Email", text: $email)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .password }
                    .padding(14)
                    .background(fieldBackground)

                SecureField("Contraseña", text: $password)
                    .textContentType(.password)
                    .focused($focusedField, equals: .password)
                    .submitLabel(.go)
                    .onSubmit { Task { await session.login(email: email, password: password) } }
                    .padding(14)
                    .background(fieldBackground)
            }

            if let error = session.loginError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(MetrogasTheme.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Button {
                focusedField = nil
                Task { await session.login(email: email, password: password) }
            } label: {
                HStack {
                    if session.isLoggingIn && !session.showGoogleAuth {
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

            HStack {
                Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 1)
                Text("o")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 1)
            }

            Button {
                focusedField = nil
                Task { await session.startGoogleLogin() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "g.circle.fill")
                        .font(.title3)
                    Text("Continuar con Google")
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .foregroundStyle(.primary)
                .background {
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(Color.white.opacity(0.45), lineWidth: 1)
                        )
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

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.white.opacity(0.72))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.55), lineWidth: 1)
            )
    }
}

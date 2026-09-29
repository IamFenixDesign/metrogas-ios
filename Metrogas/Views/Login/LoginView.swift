import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var session: AppSession

    @State private var email = ""
    @State private var password = ""
    @State private var appear = false
    @FocusState private var focusedField: Field?

    private enum Field {
        case email, password
    }

    var body: some View {
        ZStack {
            background

            ScrollView {
                VStack(spacing: 0) {
                    brandHeader
                        .padding(.top, 48)
                        .padding(.bottom, 28)

                    loginCard
                        .padding(.horizontal, 20)

                    footerLinks
                        .padding(.top, 20)
                        .padding(.bottom, 36)
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
            withAnimation(.easeOut(duration: 0.65)) { appear = true }
        }
    }

    private var brandHeader: some View {
        VStack(spacing: 14) {
            Image("MetrogasLogo")
                .resizable()
                .scaledToFit()
                .frame(height: 48)
                .padding(.horizontal, 40)
                .colorScheme(.dark)
                .opacity(appear ? 1 : 0)
                .offset(y: appear ? 0 : 10)

            Text("Oficina Virtual")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .opacity(appear ? 1 : 0)

            Text("Ingresá con tu cuenta MetroGAS.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.88))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
                .opacity(appear ? 1 : 0)
        }
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
                    .foregroundStyle(Color.red.opacity(0.95))
                    .frame(maxWidth: .infinity, alignment: .leading)
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
            }
            .buttonStyle(.borderedProminent)
            .tint(MetrogasTheme.brandFlame)
            .disabled(session.isLoggingIn)

            HStack {
                Rectangle().fill(.white.opacity(0.25)).frame(height: 1)
                Text("o")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Rectangle().fill(.white.opacity(0.25)).frame(height: 1)
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
            }
            .buttonStyle(.bordered)
            .tint(.white)
            .disabled(session.isLoggingIn)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(.white.opacity(0.22), lineWidth: 1)
                )
        )
        .opacity(appear ? 1 : 0)
        .offset(y: appear ? 0 : 16)
    }

    private var footerLinks: some View {
        VStack(spacing: 12) {
            Link("Registrarme en Oficina Virtual", destination: MetrogasURLs.registro)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)

            Link("Sitio oficial MetroGAS", destination: MetrogasURLs.sitioInstitucional)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.75))
        }
        .opacity(appear ? 1 : 0)
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white.opacity(0.92))
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

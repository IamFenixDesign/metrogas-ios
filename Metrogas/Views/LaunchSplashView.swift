import SwiftUI

struct LaunchSplashView: View {
    @State private var pulse = false
    @State private var appear = false

    var body: some View {
        ZStack {
            LiquidGlassBackground()

            VStack(spacing: 18) {
                Image("MetrogasLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 56)
                    .padding(.horizontal, 48)
                    .padding(22)
                    .liquidGlass(cornerRadius: 28, prominent: true)
                    .scaleEffect(appear ? 1 : 0.9)
                    .opacity(appear ? 1 : 0)
                    .scaleEffect(pulse ? 1.02 : 1)

                Text("Oficina Virtual")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.primary.opacity(0.85))
                    .opacity(appear ? 1 : 0)
                    .offset(y: appear ? 0 : 8)
            }
        }
        .onAppear {
            withAnimation(MetrogasTheme.springSoft) { appear = true }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

struct RootContainerView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var store: AccountDataStore
    @EnvironmentObject private var reminders: ReminderService
    @State private var showSplash = true
    @State private var didRunInitialBootstrap = false

    var body: some View {
        ZStack {
            Group {
                if session.isAuthenticated {
                    RootTabView()
                        .transition(.opacity.combined(with: .scale(scale: 0.985)))
                } else {
                    LoginView()
                        .transition(.opacity.combined(with: .scale(scale: 0.985)))
                }
            }

            if showSplash {
                LaunchSplashView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(MetrogasTheme.springSoft, value: session.isAuthenticated)
        .task {
            // Splash corto; la restauración/sync corre en paralelo y no bloquea la UI.
            async let bootstrap: Void = bootstrapSessionAndData()
            try? await Task.sleep(nanoseconds: 280_000_000)
            withAnimation(.easeOut(duration: 0.28)) {
                showSplash = false
            }
            // Pedir permiso nativo de iOS al entrar (diálogo del sistema, sin botón).
            async let permission: Bool = reminders.requestPermissionOnLaunch()
            await bootstrap
            _ = await permission
        }
        .onChange(of: session.isAuthenticated) { wasLoggedIn, loggedIn in
            // Única sync de la app: al iniciar sesión (Google o MetroGAS).
            guard loggedIn, !wasLoggedIn, didRunInitialBootstrap else {
                if !loggedIn { store.clear() }
                return
            }
            Task {
                await store.refresh(loginHint: session.loginEmail, force: true)
                await reminders.reschedule(for: store.invoices)
            }
        }
        .onChange(of: store.needsReauthentication) { _, needsReauth in
            guard needsReauth else { return }
            Task {
                store.needsReauthentication = false
                await session.expireSession(clearSavedPassword: true)
                store.clear()
            }
        }
    }

    private func bootstrapSessionAndData() async {
        await reminders.refreshAuthorizationStatus()

        if session.isAuthenticated {
            let usable = await session.restoreSessionIfNeeded()
            if usable {
                if session.loginEmail == nil || session.loginEmail?.isEmpty == true,
                   let email = await MetrogasAuthService.shared.resolveSignedInEmail() {
                    session.loginEmail = email
                }
                // Reabrir app: solo caché local, sin sync de red.
                await store.refresh(loginHint: session.loginEmail, force: false)
                await reminders.reschedule(for: store.invoices)
            }
        }

        didRunInitialBootstrap = true
    }
}

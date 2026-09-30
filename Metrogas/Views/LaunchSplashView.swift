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
    @State private var pendingLoginSync = false

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
            if !loggedIn {
                store.clear()
                pendingLoginSync = false
                return
            }
            guard loggedIn, !wasLoggedIn else { return }

            // Si el bootstrap todavía no terminó, encolar la sync de login.
            guard didRunInitialBootstrap else {
                pendingLoginSync = true
                return
            }
            Task { await syncAfterLogin() }
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

    private func syncAfterLogin() async {
        // Re-resolver email Google/SAP. El N° lo confirma LinkedAccountStore o M360.
        for _ in 0..<8 {
            let identity = await MetrogasAuthService.shared.resolveSignedInIdentity()
            if let email = identity.email, !email.isEmpty {
                session.loginEmail = email
                break
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }

        await store.refresh(loginHint: session.loginEmail, force: true)
        await reminders.reschedule(for: store.invoices)
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
                // Caché vacía o sin sync previo → red. Si hay datos locales, no saturar.
                let needsNetwork = store.invoices.isEmpty
                    || store.lastSync == nil
                    || MetrogasURLs.normalizedCustomerNumber(store.account.customerNumber) == nil
                await store.refresh(loginHint: session.loginEmail, force: needsNetwork)
                await reminders.reschedule(for: store.invoices)
            }
        }

        didRunInitialBootstrap = true
        if pendingLoginSync, session.isAuthenticated {
            pendingLoginSync = false
            await syncAfterLogin()
        }
    }
}

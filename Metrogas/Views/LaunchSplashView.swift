import SwiftUI

struct LaunchSplashView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    MetrogasTheme.deepNavy,
                    MetrogasTheme.brandBlue,
                    MetrogasTheme.brandCyan.opacity(0.9)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 16) {
                Image("MetrogasLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 52)
                    .colorScheme(.dark)
                    .padding(.horizontal, 48)

                Text("Oficina Virtual")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
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
                        .transition(.opacity)
                } else {
                    LoginView()
                        .transition(.opacity)
                }
            }

            if showSplash || session.isRestoringSession {
                LaunchSplashView()
                    .overlay(alignment: .bottom) {
                        if session.isRestoringSession {
                            ProgressView("Reanudando sesión…")
                                .padding(.bottom, 48)
                                .tint(.white)
                                .foregroundStyle(.white)
                        }
                    }
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: session.isAuthenticated)
        .task {
            await bootstrapSessionAndData()
            try? await Task.sleep(nanoseconds: 450_000_000)
            withAnimation(.easeOut(duration: 0.35)) {
                showSplash = false
            }
        }
        .onChange(of: session.isAuthenticated) { wasLoggedIn, loggedIn in
            // Solo sync extra al pasar de login → autenticado (no en cold start).
            guard loggedIn, !wasLoggedIn, didRunInitialBootstrap else {
                if !loggedIn { store.clear() }
                return
            }
            Task {
                await store.refresh(loginHint: session.loginEmail)
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
                await store.refresh(loginHint: session.loginEmail)
                await reminders.reschedule(for: store.invoices)
            }
        }

        didRunInitialBootstrap = true
    }
}

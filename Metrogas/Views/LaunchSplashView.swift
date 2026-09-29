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

            if showSplash {
                LaunchSplashView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: session.isAuthenticated)
        .task {
            await reminders.refreshAuthorizationStatus()
            try? await Task.sleep(nanoseconds: 900_000_000)
            withAnimation(.easeOut(duration: 0.4)) {
                showSplash = false
            }
        }
        .onChange(of: session.isAuthenticated) { _, loggedIn in
            if loggedIn {
                Task {
                    await store.refresh(loginHint: session.loginEmail)
                    await reminders.reschedule(for: store.invoices)
                }
            } else {
                store.clear()
            }
        }
        .task(id: session.isAuthenticated) {
            guard session.isAuthenticated else { return }
            await store.refresh(loginHint: session.loginEmail)
            await reminders.reschedule(for: store.invoices)
        }
    }
}

import SwiftUI

struct LaunchSplashView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    MetrogasTheme.deepNavy,
                    MetrogasTheme.brandBlue,
                    MetrogasTheme.brandCyan.opacity(0.85)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                Image("MetrogasLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 56)
                    .colorScheme(.dark)
                    .padding(.horizontal, 48)
                    .accessibilityLabel("MetroGAS")

                Text("Damos calor")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
    }
}

struct RootContainerView: View {
    @EnvironmentObject private var store: MockDataStore
    @EnvironmentObject private var reminders: ReminderService
    @State private var showSplash = true

    var body: some View {
        ZStack {
            RootTabView()

            if showSplash {
                LaunchSplashView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .task {
            await reminders.refreshAuthorizationStatus()
            await reminders.reschedule(for: store.invoices)
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            withAnimation(.easeOut(duration: 0.45)) {
                showSplash = false
            }
        }
        .onChange(of: store.invoices) { _, newValue in
            Task { await reminders.reschedule(for: newValue) }
        }
        .onChange(of: reminders.remindersEnabled) { _, _ in
            Task { await reminders.reschedule(for: store.invoices) }
        }
        .onChange(of: reminders.daysBeforeDue) { _, _ in
            Task { await reminders.reschedule(for: store.invoices) }
        }
    }
}

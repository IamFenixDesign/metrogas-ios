import SwiftUI

struct NotificationCenterView: View {
    @EnvironmentObject private var reminders: ReminderService
    @Environment(\.dismiss) private var dismiss
    @State private var appear = false
    @State private var confirmClearAll = false

    var body: some View {
        NavigationStack {
            Group {
                if reminders.inbox.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .background { LiquidGlassBackground() }
            .navigationTitle("Notificaciones")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !reminders.inbox.isEmpty {
                        Menu {
                            Button {
                                reminders.markAllNotificationsRead()
                            } label: {
                                Label("Marcar como leídas", systemImage: "envelope.open")
                            }
                            Button(role: .destructive) {
                                confirmClearAll = true
                            } label: {
                                Label("Borrar todas", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .accessibilityLabel("Opciones")
                    }
                }
            }
            .confirmationDialog(
                "¿Borrar todas las notificaciones?",
                isPresented: $confirmClearAll,
                titleVisibility: .visible
            ) {
                Button("Borrar todas", role: .destructive) {
                    withAnimation(MetrogasTheme.springSnappy) {
                        reminders.clearAllNotifications()
                    }
                }
                Button("Cancelar", role: .cancel) {}
            }
            .onAppear {
                reminders.markAllNotificationsRead()
                withAnimation(MetrogasTheme.springSoft) { appear = true }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Sin notificaciones", systemImage: "bell.slash")
        } description: {
            Text("Acá vas a ver avisos de facturas nuevas y vencimientos. Podés borrarlas cuando quieras.")
        }
        .appearMotion(visible: appear, index: 0)
    }

    private var list: some View {
        List {
            ForEach(reminders.inbox) { item in
                notificationRow(item)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowSeparator(.hidden)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            withAnimation(MetrogasTheme.springSnappy) {
                                reminders.deleteNotification(id: item.id)
                            }
                        } label: {
                            Label("Borrar", systemImage: "trash")
                        }
                    }
            }
            .onDelete { indexSet in
                withAnimation(MetrogasTheme.springSnappy) {
                    reminders.deleteNotifications(at: indexSet)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .appearMotion(visible: appear, index: 0)
    }

    private func notificationRow(_ item: AppNotificationItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(MetrogasTheme.brandBlue.opacity(item.isRead ? 0.10 : 0.18))
                    .frame(width: 40, height: 40)
                Image(systemName: item.kind.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MetrogasTheme.brandBlue)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.title)
                        .font(.subheadline.weight(item.isRead ? .semibold : .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Text(relativeTime(item.createdAt))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Text(item.body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(item.kind.label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(MetrogasTheme.brandCyan)
            }

            if !item.isRead {
                Circle()
                    .fill(MetrogasTheme.brandFlame)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)
            }
        }
        .padding(14)
        .liquidGlass(cornerRadius: 18)
        .opacity(item.isRead ? 0.92 : 1)
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "es_AR")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

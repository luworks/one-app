import SwiftUI
import SwiftData
import UserNotifications

/// Real alarms only (AlarmKit: they ring through Silent and Focus), plus the tasks and events you
/// marked "Ring as alarm". Reminders and event alerts live in Apple Reminders / Calendar, not here.
struct AlarmsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\OneAlarm.hour), SortDescriptor(\OneAlarm.minute)]) private var alarms: [OneAlarm]
    @Query(sort: \OneEvent.start) private var events: [OneEvent]
    @Query(sort: \OneTask.createdAt) private var tasks: [OneTask]
    @State private var status: UNAuthorizationStatus = .authorized
    @State private var editing: OneAlarm?

    var body: some View {
        List {
            if status != .authorized && status != .provisional {
                permissionCard
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
            }
            if Ringer.isDenied {
                deniedRow
            }
            Section {
                ForEach(alarms) { alarm in
                    AlarmRow(alarm: alarm) { editing = alarm }
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) { withAnimation { context.delete(alarm) } } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            Button { editing = alarm } label: { Label("Edit", systemImage: "pencil") }
                            Button(role: .destructive) { withAnimation { context.delete(alarm) } } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
            if !ringing.isEmpty {
                Section("From your items") {
                    ForEach(ringing) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                Text("Rings " + DayLabel.withTime(item.fire))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "alarm").foregroundStyle(Color.accentColor)
                        }
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .overlay {
            if alarms.isEmpty && ringing.isEmpty {
                ContentUnavailableView("No alarms", systemImage: "alarm",
                                       description: Text("Tap + to add one. Alarms ring through Silent and Focus."))
            }
        }
        .sheet(item: $editing) { AlarmEditor(alarm: $0) }
        .task(id: scenePhase) { status = await Reminders.shared.authorizationStatus() }
    }

    private struct Ringing: Identifiable {
        let id: String
        let title: String
        let fire: Date
    }

    /// Items that will ring as an alarm, soonest first.
    private var ringing: [Ringing] {
        let now = Date.now
        let t = tasks.filter { $0.ringsAsAlarm && !$0.isDone }.compactMap { task in
            task.reminderDate.map { Ringing(id: "t\(task.persistentModelID.hashValue)", title: task.title, fire: $0) }
        }
        let e = events.filter(\.ringsAsAlarm).compactMap { event in
            event.reminderDate.map { Ringing(id: "e\(event.persistentModelID.hashValue)", title: event.title, fire: $0) }
        }
        return (t + e).filter { $0.fire > now }.sorted { $0.fire < $1.fire }
    }

    /// One quiet line, not a card: alarms need the user's OK in Settings.
    private var deniedRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "alarm.slash").foregroundStyle(.secondary)
            Text("Alarms are off for Today").font(.subheadline)
            Spacer(minLength: 8)
            Button("Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
        }
        .padding(.vertical, 4)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Notifications are off", systemImage: "bell.slash")
                .font(.headline)
            Text(status == .denied
                 ? "Notifications are turned off for Today. Turn them on in Settings to get reminded at the right time."
                 : "Allow notifications so Today can remind you when a task or event starts.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button(status == .denied ? "Open Settings" : "Turn on notifications") {
                if status == .denied {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                } else {
                    Task {
                        await Reminders.shared.requestPermission()
                        status = await Reminders.shared.authorizationStatus()
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 16))
    }
}

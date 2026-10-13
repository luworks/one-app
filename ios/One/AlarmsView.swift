import SwiftUI
import SwiftData
import UserNotifications

/// Everything with a reminder in the next 7 days, plus the notification permission state.
struct AlarmsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Query(sort: \OneEvent.start) private var events: [OneEvent]
    @Query(sort: \OneTask.createdAt) private var tasks: [OneTask]
    @State private var status: UNAuthorizationStatus = .authorized

    private let cal = Calendar.current

    var body: some View {
        List {
            if status != .authorized && status != .provisional {
                permissionCard
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
            }
            ForEach(days, id: \.self) { day in
                Section(DayLabel.text(for: day)) {
                    ForEach(items.filter { cal.isDate($0.start, inSameDayAs: day) }) { item in
                        switch item {
                        case .event(let event):
                            HStack(spacing: 0) {
                                EventRow(event: event)
                                ReminderMenu(minutes: Binding(get: { event.reminderOffsetMinutes },
                                                              set: { event.reminderOffsetMinutes = $0 }))
                            }
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 8))
                        case .task(let task):
                            HStack(spacing: 0) {
                                TaskRow(task: task, showsTime: true)
                                ReminderMenu(minutes: Binding(get: { task.reminderOffsetMinutes },
                                                              set: { task.reminderOffsetMinutes = $0 }))
                            }
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 8))
                        case .nowMarker:
                            EmptyView()
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .overlay {
            if items.isEmpty {
                ContentUnavailableView("Nothing timed in the next 7 days", systemImage: "alarm",
                                       description: Text("Tasks and events with a time show up here."))
            }
        }
        .task(id: scenePhase) { status = await Reminders.shared.authorizationStatus() }
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Reminders are off", systemImage: "bell.slash")
                .font(.headline)
            Text(status == .denied
                 ? "Notifications are turned off for one. Turn them on in Settings to get reminded at the right time."
                 : "Allow notifications so one. can remind you when a task or event starts, and keep nudging until it's done.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button(status == .denied ? "Open Settings" : "Turn on reminders") {
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

    private var items: [TimelineItem] {
        let now = Date.now
        guard let end = cal.date(byAdding: .day, value: 7, to: now) else { return [] }
        let upcoming = events.filter { $0.start >= now && $0.start < end }.map(TimelineItem.event)
            + tasks.filter { task in
                guard !task.isDone, let start = task.plannedStart else { return false }
                return start >= now && start < end
            }.map(TimelineItem.task)
        return upcoming.sorted { $0.start < $1.start }
    }

    private var days: [Date] {
        var seen: [Date] = []
        for item in items {
            let d = cal.startOfDay(for: item.start)
            if seen.last != d { seen.append(d) }
        }
        return seen
    }
}

/// Bell button: shows whether an item reminds you, and lets you pick when.
struct ReminderMenu: View {
    @Binding var minutes: Int?

    var body: some View {
        Menu {
            Picker("Remind me", selection: $minutes) {
                ForEach(ReminderOffset.choices, id: \.0) { label, value in
                    Text(label).tag(value)
                }
            }
        } label: {
            Image(systemName: minutes == nil ? "bell.slash" : "bell.fill")
                .font(.subheadline)
                .foregroundStyle(minutes == nil ? Color.secondary : Color.accentColor)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel("Reminder: \(ReminderOffset.label(minutes))")
    }
}

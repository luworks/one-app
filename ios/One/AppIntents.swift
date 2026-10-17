import AppIntents
import SwiftData
import SwiftUI

// Siri, Spotlight and the Shortcuts app. Asking Siri is the user's own decision, so these act directly
// (AI prepares, the user decides: here the user decided). They run in the app's process on the app's store
// (`OneStore`); only Open Today brings the app forward. Phrases in Chinese: AppShortcuts.xcstrings.

/// "Add a reminder in Today": a title or one sentence ("call Mom tomorrow at 6pm"), read by `CaptureParser`.
struct AddReminderIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Reminder"
    static let description = IntentDescription("Adds a reminder. Say it in one sentence, like “Call Mom tomorrow at 6pm”.")
    static let openAppWhenRun = false

    @Parameter(title: "Reminder", requestValueDialog: "What’s the reminder?")
    var text: String

    @Parameter(title: "Date")
    var date: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$text)") { \.$date }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let capture = IntentReminder.capture(text: text, date: date) else {
            throw $text.needsValueError("What’s the reminder?")
        }
        let context = OneStore.start().mainContext
        // A task without an alarm request always becomes a `OneTask`; the save also queues the Apple Reminders sync.
        capture.insert(into: context, actor: .siri, channel: .intent)
        ActivityCenter.record(ActivityEvents.intentRun(name: "add_reminder", outcome: "ok"))
        await Reminders.shared.resync()
        IntentSupport.refreshWidgets(context)
        return .result(dialog: "Added “\(capture.title)”. \(capture.summary).")
    }
}

/// "Start a timer in Today": the one countdown on the Alarms tab (AlarmKit), same as its Start button.
struct StartTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Timer"
    static let description = IntentDescription("Starts the countdown timer. It rings like an alarm, even on Silent.")
    static let openAppWhenRun = false

    @Parameter(title: "Minutes", inclusiveRange: (1, 90), requestValueDialog: "How many minutes?")
    var minutes: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Start a \(\.$minutes) minute timer")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let seconds = IntentTimer.seconds(minutes: minutes) else {
            throw IntentMessage("Timers can run from 1 to \(IntentTimer.maxMinutes) minutes.")
        }
        let controller = TimerController.shared
        controller.refresh()
        // There is one timer; replacing a running one is the user's call.
        if controller.running != nil {
            try await requestConfirmation(actionName: .start, dialog: "A timer is already running. Replace it?")
        }
        await controller.start(seconds: seconds)
        ActivityCenter.record(ActivityEvents.intentRun(name: "start_timer", outcome: controller.message == nil ? "ok" : "failed"))
        if let message = controller.message { throw IntentMessage(message) }
        return .result(dialog: "Timer started for \(IntentTimer.spoken(minutes: minutes)).")
    }
}

/// "What's next in Today": the next three items today (or tomorrow's first), as the Next Up widget picks them.
struct WhatsNextIntent: AppIntent {
    static let title: LocalizedStringResource = "What’s Next Today"
    static let description = IntentDescription("Tells you the next three things today: events, reminders with a time, and alarms.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let context = OneStore.start().mainContext
        let now = Date.now
        let next = NextItems.select(from: IntentSupport.widgetItems(context, now: now), now: now)
        ActivityCenter.record(ActivityEvents.intentRun(name: "whats_next", outcome: "ok"))
        return .result(dialog: "\(NextUpSpeech.line(next, now: now))", view: NextUpSnippet(next: next, now: now))
    }
}

/// "Show my day in Today": opens the Today tab on today, through the same link the widgets use.
struct OpenTodayIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Today"
    static let description = IntentDescription("Opens the Today tab on today.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(WidgetLink.url()))
    }
}

struct TodayShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AddReminderIntent(), phrases: [
            "Add a reminder in \(.applicationName)",
            "Remind me with \(.applicationName)",
            "New \(.applicationName) reminder",
        ], shortTitle: "Add Reminder", systemImageName: "checklist")
        AppShortcut(intent: StartTimerIntent(), phrases: [
            "Start a timer in \(.applicationName)",
            "Start a \(.applicationName) timer",
        ], shortTitle: "Start Timer", systemImageName: "timer")
        AppShortcut(intent: WhatsNextIntent(), phrases: [
            "What’s next in \(.applicationName)",
            "What’s next today in \(.applicationName)",
        ], shortTitle: "What’s Next", systemImageName: "list.bullet.clipboard")
        AppShortcut(intent: OpenTodayIntent(), phrases: [
            "Show my day in \(.applicationName)",
            "Show today in \(.applicationName)",
        ], shortTitle: "Open Today", systemImageName: "sun.max")
    }
}

/// An error Siri reads out as is.
struct IntentMessage: Error, CustomLocalizedStringResourceConvertible {
    let text: String
    init(_ text: String) { self.text = text }
    var localizedStringResource: LocalizedStringResource { "\(text)" }
}

@MainActor
enum IntentSupport {
    /// The widget's items for today and tomorrow, from the store and Apple Calendar.
    static func widgetItems(_ context: ModelContext, now: Date) -> [WidgetItem] {
        CalendarSync.shared.prepare()
        let (tasks, events, alarms) = fetch(context)
        return WidgetFeed.items(tasks: tasks, events: events, alarms: alarms, now: now, calendar: .current)
    }

    /// After a change made with the app closed, the widgets still show it.
    static func refreshWidgets(_ context: ModelContext) {
        CalendarSync.shared.prepare()
        let (tasks, events, alarms) = fetch(context)
        WidgetFeed.update(tasks: tasks, events: events, alarms: alarms)
    }

    /// Open tasks and alarms that are on: done tasks are never next, and their number only grows.
    private static func fetch(_ context: ModelContext) -> ([OneTask], [OneEvent], [OneAlarm]) {
        let tasks = (try? context.fetch(FetchDescriptor<OneTask>(predicate: #Predicate { !$0.isDone }))) ?? []
        let events = (try? context.fetch(FetchDescriptor<OneEvent>())) ?? []
        let alarms = (try? context.fetch(FetchDescriptor<OneAlarm>(predicate: #Predicate { $0.isOn }))) ?? []
        return (tasks, events, alarms)
    }
}

/// The card under Siri's answer: up to three rows, time and title, like the widget.
private struct NextUpSnippet: View {
    let next: NextUp
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if next.today.isEmpty {
                Text("Nothing left today").font(.headline)
                if let first = next.tomorrow {
                    Text("Tomorrow").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    row(first)
                }
            } else {
                ForEach(next.today) { row($0) }
                let more = next.remainingToday - next.today.count
                if more > 0 {
                    Text("\(more) more today").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }

    private func row(_ item: WidgetItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol(item.kind))
                .foregroundStyle(item.kind == .alarm ? .orange : .accentColor)
                .frame(width: 20)
            Text(item.title).font(.body).lineLimit(1)
            Spacer(minLength: 8)
            Text(timeText(item)).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    private func timeText(_ item: WidgetItem) -> String {
        if item.isAllDay { return "All day" }
        if item.start <= now { return "Now" }
        return item.start.formatted(date: .omitted, time: .shortened)
    }

    private func symbol(_ kind: WidgetItem.Kind) -> String {
        switch kind {
        case .event: "calendar"
        case .reminder: "checklist"
        case .alarm: "alarm"
        }
    }
}

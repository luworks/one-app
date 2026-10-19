#if os(iOS)
import TodayCore
import TodayShared
import TodayData
import TodayPlatform
import AppIntents
import SwiftData
import SwiftUI

// Siri, Spotlight and the Shortcuts app. Asking Siri is the user's own decision, so these act directly
// (AI prepares, the user decides: here the user decided). They run in the app's process on the app's store
// (`OneStore`); only Open Today brings the app forward. Phrases in Chinese: AppShortcuts.xcstrings.

/// "Add a reminder in Today": a title or one sentence ("call Mom tomorrow at 6pm"), read by `CaptureParser`.
public struct AddReminderIntent: AppIntent {
    public init() {}
    public static let title: LocalizedStringResource = "Add Reminder"
    public static let description = IntentDescription("Adds a reminder. Say it in one sentence, like “Call Mom tomorrow at 6pm”.")
    public static let openAppWhenRun = false

    @Parameter(title: "Reminder", requestValueDialog: "What’s the reminder?")
    public var text: String

    @Parameter(title: "Date")
    public var date: Date?

    public static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$text)") { \.$date }
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
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

/// "What's next in Today": the next three items today (or tomorrow's first), as the Next Up widget picks them.
public struct WhatsNextIntent: AppIntent {
    public init() {}
    public static let title: LocalizedStringResource = "What’s Next Today"
    public static let description = IntentDescription("Tells you the next three things today: events, reminders with a time, and alarms.")
    public static let openAppWhenRun = false

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let context = OneStore.start().mainContext
        let now = Date.now
        let next = NextItems.select(from: IntentSupport.widgetItems(context, now: now), now: now)
        ActivityCenter.record(ActivityEvents.intentRun(name: "whats_next", outcome: "ok"))
        return .result(dialog: "\(NextUpSpeech.line(next, now: now))", view: NextUpSnippet(next: next, now: now))
    }
}

/// "Show my day in Today": opens the Today tab on today, through the same link the widgets use.
public struct OpenTodayIntent: AppIntent {
    public init() {}
    public static let title: LocalizedStringResource = "Open Today"
    public static let description = IntentDescription("Opens the Today tab on today.")
    public static let openAppWhenRun = false

    @MainActor
    public func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(WidgetLink.url()))
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
#endif

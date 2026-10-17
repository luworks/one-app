import SwiftUI
import SwiftData

/// One day's view: all-day events, one overdue line, then one timeline: events, planned tasks, reminders
/// due at a time, alarms, and suggested times for reminders due that day without one.
/// Today shows the current day, followed by a short look at tomorrow (see `TomorrowPreview`);
/// the Calendar tab adds the week strip to pick a day.
struct DayAgenda: View {
    @Binding var day: Date
    var showsWeekStrip: Bool

    @Query(sort: \OneEvent.start) private var events: [OneEvent]
    @Query(sort: \OneTask.createdAt) private var tasks: [OneTask]
    @Query private var alarms: [OneAlarm]
    @AppStorage(SettingsKey.showOverdue) private var showsOverdue = true
    @AppStorage(SettingsKey.showAlarms) private var showsAlarms = true
    @AppStorage(SettingsKey.jumpToNow) private var jumpsToNow = true
    @AppStorage(SettingsKey.healthSummary) private var showsHealth = true
    @Environment(\.scenePhase) private var scenePhase
    @State private var health = HealthLineModel()
    /// The open "Review today" sheet: tomorrow and its first items, taken when the row is tapped.
    @State private var review: ReviewRequest?

    private let cal = Calendar.current
    @State private var showsAllOverdue = false
    /// nil = follow `TomorrowPreview` (open in the evening); otherwise the user's own "more" / "Show less".
    @State private var expandsTomorrow: Bool?
    /// Refreshed every minute, so the Now line moves and Tomorrow opens at 18:00 without a relaunch.
    @State private var now = TodayClock.now
    /// A repeating system event whose Delete is waiting for "this event or the series?".
    @State private var pendingDelete: CalEntry?

    var body: some View {
        ScrollViewReader { proxy in
            list
                .onAppear { scrollToNow(proxy) }
                .onChange(of: day) { _, _ in scrollToNow(proxy) }
        }
        .task(id: [showsHealth, isTodayTab, scenePhase == .active]) {
            // Asks for Health access only the first time the line would show (Today, setting on).
            guard showsHealth, isTodayTab, scenePhase == .active else { return }
            await health.load()
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                now = TodayClock.now
            }
        }
    }

    /// Open on what is happening now: the day's schedule scrolls to the "now" line.
    private func scrollToNow(_ proxy: ScrollViewProxy) {
        guard cal.isDateInToday(day), jumpsToNow else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(.snappy) { proxy.scrollTo("now-line", anchor: .center) }
        }
    }

    /// The Today tab on today (not the Calendar tab, not another day).
    private var isTodayTab: Bool { !showsWeekStrip && cal.isDateInToday(day) }

    private var list: some View {
        let items = items(on: day, now: now)
        return List {
            if isTodayTab, showsHealth, let line = health.line {
                TodayHealthLine(line: line)
            }
            if !showsWeekStrip, !cal.isDateInToday(day) {
                Button { withAnimation(.snappy) { day = cal.startOfDay(for: .now) } } label: {
                    Label("Back to today", systemImage: "arrow.uturn.backward").font(.subheadline)
                        .frame(minHeight: 44)
                }
                .listRowSeparator(.hidden)
            }
            if showsWeekStrip {
                Section {
                    WeekStrip(selected: $day)
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 4, bottom: 6, trailing: 4))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            if !items.allDay.isEmpty || !items.externalAllDay.isEmpty {
                Section {
                    ForEach(items.allDay) { EventRow(event: $0, pendingDelete: $pendingDelete) }
                    ForEach(items.externalAllDay) { ExternalEventRow(event: $0, pendingDelete: $pendingDelete) }
                } header: { AgendaHeader(title: "All day") }
            }
            if cal.isDateInToday(day), showsOverdue, !overdue.isEmpty {
                Section {
                    Button {
                        withAnimation(.snappy) { showsAllOverdue.toggle() }
                    } label: {
                        HStack {
                            Text("\(overdue.count) overdue").font(.subheadline.weight(.semibold)).foregroundStyle(.red)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .rotationEffect(.degrees(showsAllOverdue ? 90 : 0))
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                    .accessibilityHint(showsAllOverdue ? "Hides the overdue tasks" : "Shows the overdue tasks")
                    if showsAllOverdue { ForEach(overdue) { TaskRow(task: $0, compact: true) } }
                }
            }
            Section {
                if items.timeline.isEmpty, items.anytime.isEmpty {
                    Text("Nothing planned").foregroundStyle(.secondary)
                        .listRowSeparator(.hidden)
                }
                ForEach(items.timeline) { timelineRow($0) }
                if !items.anytime.isEmpty {
                    AnytimeLabel(title: cal.isDateInToday(day) ? "Anytime today" : "Anytime")
                    ForEach(items.anytime) { TaskRow(task: $0, compact: true) }
                }
            } header: {
                AgendaHeader(title: showsWeekStrip || !cal.isDateInToday(day) ? day.formatted(.dateTime.month().day().weekday(.wide)) : "Schedule")
            }
            if !showsWeekStrip, cal.isDateInToday(day) { tomorrowSection(after: items) }
        }
        .listStyle(.plain)
        // Rows set their own 44pt minimum where they can be tapped; this lets the alarm and now lines sit tighter.
        .environment(\.defaultMinListRowHeight, 24)
        .listSectionSpacing(6)
        .scrollContentBackground(.hidden)
        .entryDeleteDialog($pendingDelete)
        .sheet(item: $review) { r in EveningReviewSheet(now: now, tomorrow: r.tomorrow, peek: r.peek) }
    }

    @ViewBuilder
    private func timelineRow(_ item: TimelineItem) -> some View {
        switch item {
        case .event(let event, let start): EventRow(event: event, start: start, pendingDelete: $pendingDelete)
        case .external(let e): ExternalEventRow(event: e, pendingDelete: $pendingDelete)
        case .task(let task): TaskRow(task: task, showsTime: true, compact: true)
        case .due(let task): TaskRow(task: task, showsTime: true, time: task.due, compact: true)
        case .suggested(let task, let start): TaskRow(task: task, compact: true, suggested: start)
        case .alarm(let alarm, let date): AlarmMarkRow(alarm: alarm, date: date)
        case .gap(let free): FreeRow(free: free)
        case .nowMarker(let date): NowRow(date: date).id("now-line")
        }
    }

    // MARK: Tomorrow

    /// Tomorrow under today's schedule: its first few items by day, all of them in the evening.
    /// The header opens tomorrow as its own day. Overdue items never show here: they stay with today.
    @ViewBuilder
    private func tomorrowSection(after today: DayItems) -> some View {
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: day)) ?? day
        let next = items(on: tomorrow, now: now)
        // Free time stays out of the short look at tomorrow.
        let entries = next.entries.filter { if case .timeline(.gap) = $0 { false } else { true } }
        let todayStarts = today.timeline.filter {
            switch $0 { case .nowMarker, .gap: false
            default: true }
        }.map(\.start)
        let expanded = expandsTomorrow ?? TomorrowPreview.opensByItself(now: now, todayStarts: todayStarts)
        let shown = expanded ? entries : Array(entries.prefix(TomorrowPreview.limit))
        Section {
            if EveningReview.shows(now: now) {
                Button {
                    review = ReviewRequest(tomorrow: tomorrow, peek: Array(entries.compactMap(Self.peek).prefix(EveningReview.tomorrowLimit)))
                } label: {
                    Label("Review today", systemImage: "checklist.checked")
                        .font(.subheadline)
                        .foregroundStyle(Color.accentColor)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowSeparator(.hidden)
                .accessibilityHint("Done and left today, and tomorrow's first items")
                .accessibilityIdentifier("reviewToday")
            }
            if entries.isEmpty {
                Text("Nothing planned").foregroundStyle(.secondary)
                    .listRowSeparator(.hidden)
            }
            ForEach(shown) { entry in
                switch entry {
                case .allDay(let e): EventRow(event: e, pendingDelete: $pendingDelete)
                case .externalAllDay(let e): ExternalEventRow(event: e, pendingDelete: $pendingDelete)
                case .anytime(let t): TaskRow(task: t, compact: true)
                case .timeline(let item): timelineRow(item)
                }
            }
            if !expanded, entries.count > shown.count {
                moreButton("\(entries.count - shown.count) more") { expandsTomorrow = true }
                    .accessibilityHint("Shows the rest of tomorrow")
            } else if expandsTomorrow == true {
                moreButton("Show less") { expandsTomorrow = false }
            }
        } header: {
            Button { withAnimation(.snappy) { day = tomorrow } } label: {
                HStack {
                    Text("Tomorrow · " + tomorrow.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .textCase(nil)
            .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 0, trailing: 20))
            .accessibilityLabel("Tomorrow")
            .accessibilityHint("Opens tomorrow")
            .accessibilityIdentifier("tomorrowHeader")
        }
    }

    /// Tomorrow's entry as a plain line for the review; the Now line and free time are left out.
    private static func peek(_ entry: DayEntry) -> ReviewPeek? {
        switch entry {
        case .allDay(let e): return ReviewPeek(id: entry.id, time: nil, title: e.title)
        case .externalAllDay(let e): return ReviewPeek(id: entry.id, time: nil, title: e.title)
        case .anytime(let t): return ReviewPeek(id: entry.id, time: nil, title: t.title)
        case .timeline(let item):
            switch item {
            case .event(let e, let d): return ReviewPeek(id: entry.id, time: d, title: e.title)
            case .external(let e): return ReviewPeek(id: entry.id, time: e.start, title: e.title)
            case .task(let t), .due(let t): return ReviewPeek(id: entry.id, time: item.start, title: t.title)
            case .suggested(let t, let d): return ReviewPeek(id: entry.id, time: d, title: t.title)
            case .alarm(let a, let d): return ReviewPeek(id: entry.id, time: d, title: a.label.isEmpty ? "Alarm" : a.label)
            case .gap, .nowMarker: return nil
            }
        }
    }

    private func moreButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button { withAnimation(.snappy) { action() } } label: {
            Text(title).font(.subheadline).foregroundStyle(Color.accentColor)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowSeparator(.hidden)
    }

    // MARK: One day's items

    private func items(on day: Date, now: Date) -> DayItems {
        let external = CalendarSync.shared.events(on: day, excluding: Set(events.compactMap(\.externalID)))
        var timeline: [TimelineItem] = []
        var busy: [DateInterval] = []
        for e in events where !e.isAllDay {
            for start in e.occurs(on: day) {
                timeline.append(.event(e, start))
                busy.append(DateInterval(start: start, duration: TimeInterval(e.durationMinutes * 60)))
            }
        }
        for e in external where !e.isAllDay {
            timeline.append(.external(e))
            busy.append(DateInterval(start: e.start, end: max(e.start, e.end)))
        }
        // Overdue reminders stay in the overdue line, never inside a day's timeline.
        // A completed task leaves the day (Undo in the toast brings it back).
        let open = tasks.filter { !$0.isDone && !$0.isOverdue }
        var untimed: [OneTask] = []
        for task in open {
            if let start = task.plannedStart {
                guard cal.isDate(start, inSameDayAs: day) else { continue }
                timeline.append(.task(task))
                busy.append(DateInterval(start: start, duration: TimeInterval(task.durationMinutes * 60)))
            } else if let due = task.due, cal.isDate(due, inSameDayAs: day) {
                // Planned time is not a deadline: only a task with no plan shows at its due time.
                if task.dueHasTime {
                    timeline.append(.due(task))
                    busy.append(DateInterval(start: due, duration: TimeInterval(task.durationMinutes * 60)))
                } else {
                    untimed.append(task)
                }
            }
        }
        // Untimed reminders get a suggested time in a free gap (flagged first); what doesn't fit is "Anytime".
        untimed.sort { ($0.flagged ? 0 : 1, $0.createdAt) < ($1.flagged ? 0 : 1, $1.createdAt) }
        let starts = DaySchedule.suggestedStarts(minutes: untimed.map(\.durationMinutes), busy: busy, day: day, now: now)
        var anytime: [OneTask] = []
        for (task, start) in zip(untimed, starts) {
            if let start {
                timeline.append(.suggested(task, start))
                busy.append(DateInterval(start: start, duration: TimeInterval(task.durationMinutes * 60)))
            } else {
                anytime.append(task)
            }
        }
        // What is still free after the suggestions, as quiet "Free 1 h 30 min" rows.
        timeline += DaySchedule.freeGaps(busy: busy, day: day, now: now).map(TimelineItem.gap)
        if showsAlarms { timeline += alarms.compactMap { a in a.fires(on: day).map { TimelineItem.alarm(a, $0) } } }
        if cal.isDateInToday(day), !timeline.isEmpty {
            timeline.append(.nowMarker(now))
        }
        return DayItems(
            allDay: events.filter { $0.isAllDay && !$0.occurs(on: day).isEmpty },
            externalAllDay: external.filter(\.isAllDay),
            // At the same minute the Now line comes first, so free time from now sits under it.
            timeline: timeline.sorted { ($0.start, $0.isNow ? 0 : 1) < ($1.start, $1.isNow ? 0 : 1) },
            anytime: anytime)
    }

    /// Oldest deadline first.
    private var overdue: [OneTask] {
        tasks.filter(\.isOverdue).sorted { ($0.due ?? .distantPast) < ($1.due ?? .distantPast) }
    }
}

struct ReviewRequest: Identifiable {
    let id = UUID()
    let tomorrow: Date
    let peek: [ReviewPeek]
}

/// What one day holds, in the order the day view shows it.
struct DayItems {
    var allDay: [OneEvent]
    var externalAllDay: [ExternalEvent]
    var timeline: [TimelineItem]
    /// Due this day with no time, and no free gap left to suggest one.
    var anytime: [OneTask]

    /// Everything as one list (all day, the timeline, then anytime), for the short Tomorrow view.
    var entries: [DayEntry] {
        allDay.map(DayEntry.allDay) + externalAllDay.map(DayEntry.externalAllDay)
            + timeline.map(DayEntry.timeline) + anytime.map(DayEntry.anytime)
    }
}

enum DayEntry: Identifiable {
    case allDay(OneEvent)
    case externalAllDay(ExternalEvent)
    case anytime(OneTask)
    case timeline(TimelineItem)

    var id: AnyHashable {
        switch self {
        case .allDay(let e): return ["allDay", AnyHashable(ObjectIdentifier(e))]
        case .externalAllDay(let e): return ["allDay", AnyHashable(e.id)]
        case .anytime(let t): return ["anytime", AnyHashable(ObjectIdentifier(t))]
        case .timeline(let item): return ["timeline", item.id]
        }
    }
}

/// The time Today reasons about. UI tests can pin it with `-uiTestingNow HH:mm` (today's date, that time).
enum TodayClock {
    static var now: Date {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-uiTesting"), let i = args.firstIndex(of: "-uiTestingNow"), i + 1 < args.count {
            let parts = args[i + 1].split(separator: ":").compactMap { Int($0) }
            if parts.count == 2, let pinned = Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: .now) {
                return pinned
            }
        }
        #endif
        return .now
    }
}

enum TimelineItem: Identifiable {
    case event(OneEvent, Date)
    case external(ExternalEvent)
    case task(OneTask)
    /// A reminder with no plan, at the time it is due.
    case due(OneTask)
    /// A reminder due this day with no time, at a suggested free time. Nothing is saved until Plan.
    case suggested(OneTask, Date)
    case alarm(OneAlarm, Date)
    /// Free time of 30 minutes or more, from now on.
    case gap(DateInterval)
    case nowMarker(Date)

    var id: AnyHashable {
        switch self {
        case .event(let e, let d): return [AnyHashable(ObjectIdentifier(e)), AnyHashable(d)]
        case .external(let e): return e.id
        case .task(let t): return ObjectIdentifier(t)
        case .due(let t): return ["due", AnyHashable(ObjectIdentifier(t))]
        case .suggested(let t, _): return ["suggested", AnyHashable(ObjectIdentifier(t))]
        case .alarm(let a, _): return ObjectIdentifier(a)
        case .gap(let free): return ["gap", AnyHashable(free.start)]
        case .nowMarker: return "now"
        }
    }

    var isNow: Bool { if case .nowMarker = self { true } else { false } }

    var start: Date {
        switch self {
        case .event(_, let d): return d
        case .external(let e): return e.start
        case .task(let t): return t.plannedStart ?? .distantFuture
        case .due(let t): return t.due ?? .distantFuture
        case .suggested(_, let d): return d
        case .alarm(_, let d): return d
        case .gap(let free): return free.start
        case .nowMarker(let d): return d
        }
    }
}

/// Small section label for the day view, so headers take less space than the default plain-list header.
struct AgendaHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(nil)
            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 2, trailing: 20))
    }
}

/// Starts the reminders that are due this day with no time and no free gap to suggest.
struct AnytimeLabel: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 0, trailing: 20))
    }
}

/// Free time between items: one quiet line, aligned with the titles.
struct FreeRow: View {
    let free: DateInterval
    var body: some View {
        Text(DaySchedule.freeLabel(free.duration))
            .font(.caption)
            .foregroundStyle(.tertiary)
            .padding(.leading, 68)
            .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
            .accessibilityLabel(DaySchedule.freeLabel(free.duration) + " from " + free.start.formatted(date: .omitted, time: .shortened))
    }
}

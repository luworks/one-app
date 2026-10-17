import SwiftUI
import SwiftData

/// Search everything in one place: reminders, calendar events (Today's and the whole system calendar) and alarms.
/// Native search field with scopes; results are grouped, and tapping one opens it in its own editor.
struct SearchView: View {
    enum Scope: String, CaseIterable, Identifiable {
        case all = "All", reminders = "Reminders", events = "Events", alarms = "Alarms"
        var id: Self { self }
    }

    private enum Opened: Identifiable {
        case task(OneTask), event(OneEvent), system(String), alarm(OneAlarm)
        var id: String {
            switch self {
            case .task(let t): "t\(t.persistentModelID.hashValue)"
            case .event(let e): "e\(e.persistentModelID.hashValue)"
            case .system(let s): "s\(s)"
            case .alarm(let a): "a\(a.persistentModelID.hashValue)"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \OneTask.createdAt, order: .reverse) private var tasks: [OneTask]
    @Query(sort: \OneEvent.start) private var events: [OneEvent]
    @Query private var alarms: [OneAlarm]
    @State private var query = ""
    @FocusState private var focused: Bool
    @State private var scope: Scope = .all
    @State private var opened: Opened?
    @State private var recents = Recents.load()
    @State private var quick: Quick?

    private let limit = 25

    /// Suggested searches shown before you type: they list things without needing words.
    enum Quick: String, CaseIterable, Identifiable {
        case overdue = "Overdue", today = "Due today", flagged = "Flagged", events = "Upcoming events", alarms = "Alarms on"
        var id: Self { self }
        var symbol: String {
            switch self {
            case .overdue: "exclamationmark.circle"
            case .today: "sun.max"
            case .flagged: "flag"
            case .events: "calendar"
            case .alarms: "alarm"
            }
        }
        var tint: Color {
            switch self {
            case .overdue: .red
            case .today: .blue
            case .flagged: .orange
            case .events: .indigo
            case .alarms: .orange
            }
        }
    }

    var body: some View {
        NavigationStack {
            let r = results
            List {
                if !query.isEmpty {
                    Picker("Search in", selection: $scope) {
                        ForEach(Scope.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }
                if query.isEmpty, quick == nil {
                    Section("Suggestions") {
                        ForEach(Quick.allCases) { q in
                            Button { quick = q } label: {
                                Label { Text(q.rawValue).foregroundStyle(.primary) } icon: {
                                    Image(systemName: q.symbol).foregroundStyle(q.tint)
                                }
                            }
                        }
                    }
                    if !recents.isEmpty {
                        Section {
                            ForEach(recents, id: \.self) { term in
                                Button { query = term } label: {
                                    Label(term, systemImage: "clock.arrow.circlepath").foregroundStyle(.primary)
                                }
                            }
                        } header: {
                            HStack {
                                Text("Recent")
                                Spacer()
                                Button("Clear") { Recents.clear(); recents = [] }.font(.footnote)
                            }
                        }
                    }
                } else {
                    if let quick {
                        Section {
                            Button { self.quick = nil } label: {
                                Label("\(quick.rawValue) · Clear", systemImage: "xmark.circle.fill").foregroundStyle(.secondary)
                            }
                        }
                    }
                    if !r.tasks.isEmpty {
                        Section(header: header("Reminders", r.tasks.count)) {
                            ForEach(r.tasks.prefix(limit)) { task in
                                Button { opened = .task(task) } label: {
                                    ResultRow(symbol: task.isDone ? "checkmark.circle.fill" : "circle", tint: task.isDone ? .green : .blue,
                                              title: task.title, detail: detail(task), dimmed: task.isDone)
                                }
                            }
                        }
                    }
                    if !r.events.isEmpty {
                        Section(header: header("Events", r.events.count)) {
                            ForEach(r.events.prefix(limit)) { hit in
                                Button {
                                    if case .system(let id) = hit.opened { NativeEvents.edit(identifier: id) } else { opened = hit.opened }
                                } label: {
                                    ResultRow(symbol: "calendar", tint: hit.color, title: hit.title, detail: hit.detail, dimmed: hit.start < .now)
                                }
                            }
                        }
                    }
                    if !r.alarms.isEmpty {
                        Section(header: header("Alarms", r.alarms.count)) {
                            ForEach(r.alarms) { alarm in
                                Button { opened = .alarm(alarm) } label: { alarmRow(alarm) }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .safeAreaInset(edge: .top, spacing: 0) { searchBar }
            .overlay {
                if (!query.isEmpty || quick != nil), r.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear { focused = true }
            .sheet(item: $opened) { item in
                switch item {
                case .task(let t): TaskEditor(task: t)
                case .event(let e): EventEditor(event: e)
                case .system(let id): NativeEventSheet(identifier: id)
                case .alarm(let a): AlarmEditor(alarm: a)
                }
            }
        }
    }

    /// Our own search bar: the field, and an X that closes Search straight away (no empty page or pop-up left behind).
    private var searchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Reminders, events, alarms", text: $query)
                    .focused($focused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .onSubmit { Recents.add(query); recents = Recents.load() }
                    .accessibilityIdentifier("search.field")
                if !query.isEmpty {
                    Button { query = ""; focused = true } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Clear text")
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(Color(.secondarySystemFill), in: Capsule())
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .glassCircle()
            }
            .buttonStyle(PressScale())
            .accessibilityLabel("Close search")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func header(_ title: String, _ count: Int) -> some View {
        HStack { Text(title); Spacer(); Text("\(count)").monospacedDigit() }
    }

    // MARK: Results

    private struct EventHit: Identifiable {
        let id: String
        let title: String
        let detail: String
        let start: Date
        let color: Color
        let opened: Opened
    }

    private struct Results {
        var tasks: [OneTask] = []
        var events: [EventHit] = []
        var alarms: [OneAlarm] = []
        var isEmpty: Bool { tasks.isEmpty && events.isEmpty && alarms.isEmpty }
    }

    private var results: Results {
        if query.trimmingCharacters(in: .whitespaces).isEmpty, let quick { return quickResults(quick) }
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return Results() }
        var out = Results()
        if scope == .all || scope == .reminders {
            out.tasks = tasks.filter { SearchMatch.matches(q, in: [$0.title, $0.note, $0.listName] + $0.tags) }
                .sorted { ($0.isDone ? 1 : 0, $0.due ?? $0.plannedStart ?? .distantFuture) < ($1.isDone ? 1 : 0, $1.due ?? $1.plannedStart ?? .distantFuture) }
        }
        if scope == .all || scope == .events {
            var hits: [EventHit] = events.filter { SearchMatch.matches(q, in: [$0.title, $0.calendarName]) }.map { e in
                EventHit(id: "o\(e.persistentModelID.hashValue)", title: e.title,
                         detail: DayLabel.withTime(e.start) + " · " + e.calendarName, start: e.start, color: .blue, opened: .event(e))
            }
            // The whole system calendar, two years either side of today (events Today mirrored are not listed twice).
            let window = DateInterval(start: Calendar.current.date(byAdding: .year, value: -2, to: .now) ?? .now,
                                      end: Calendar.current.date(byAdding: .year, value: 2, to: .now) ?? .now)
            for s in CalendarSync.shared.events(in: window, excluding: Set(events.compactMap(\.externalID)))
            where SearchMatch.matches(q, in: [s.title, s.location, s.calendarTitle]) {
                hits.append(EventHit(id: "s\(s.id)", title: s.title, detail: DayLabel.withTime(s.start) + " · " + s.calendarTitle,
                                     start: s.start, color: s.color, opened: .system(s.eventIdentifier)))
            }
            // Upcoming first (soonest first), then the past (most recent first).
            let now = Date.now
            out.events = hits.filter { $0.start >= now }.sorted { $0.start < $1.start }
                + hits.filter { $0.start < now }.sorted { $0.start > $1.start }
        }
        if scope == .all || scope == .alarms {
            out.alarms = alarms.filter { SearchMatch.matches(q, in: [$0.label, alarmTime($0), $0.repeatValue, "alarm"]) }
                .sorted { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
        }
        return out
    }

    private func quickResults(_ q: Quick) -> Results {
        let cal = Calendar.current
        var out = Results()
        switch q {
        case .overdue:
            out.tasks = tasks.filter(\.isOverdue).sorted { ($0.due ?? .distantPast) < ($1.due ?? .distantPast) }
        case .today:
            out.tasks = tasks.filter { t in
                guard !t.isDone else { return false }
                if let d = t.due, cal.isDateInToday(d) { return true }
                if let p = t.plannedStart, cal.isDateInToday(p) { return true }
                return false
            }
        case .flagged:
            out.tasks = tasks.filter { $0.flagged && !$0.isDone }
        case .events:
            let end = cal.date(byAdding: .day, value: 7, to: .now) ?? .now
            let window = DateInterval(start: .now, end: end)
            var hits: [EventHit] = events.compactMap { e in
                guard let next = e.occurrences(in: window).first(where: { $0 >= .now }) else { return nil }
                return EventHit(id: "o\(e.persistentModelID.hashValue)", title: e.title,
                                detail: DayLabel.withTime(next) + " · " + e.calendarName, start: next, color: .blue, opened: .event(e))
            }
            for s in CalendarSync.shared.events(in: window, excluding: Set(events.compactMap(\.externalID))) where s.start >= .now {
                hits.append(EventHit(id: "s\(s.id)", title: s.title, detail: DayLabel.withTime(s.start) + " · " + s.calendarTitle,
                                     start: s.start, color: s.color, opened: .system(s.eventIdentifier)))
            }
            out.events = hits.sorted { $0.start < $1.start }
        case .alarms:
            out.alarms = alarms.filter(\.isOn).sorted { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
        }
        return out
    }

    private func detail(_ t: OneTask) -> String {
        var parts: [String] = []
        if let due = t.due { parts.append("Due " + DayLabel.withTime(due)) }
        else if let p = t.plannedStart { parts.append(DayLabel.withTime(p)) }
        if !t.listName.isEmpty { parts.append(ListName.display(t.listName)) }
        return parts.joined(separator: " · ")
    }

    private func alarmRow(_ alarm: OneAlarm) -> some View {
        let title = alarm.label.isEmpty ? "Alarm" : alarm.label
        let detail = alarmTime(alarm) + " · " + alarm.repeatValue
        return ResultRow(symbol: "alarm", tint: .orange, title: title, detail: detail, dimmed: !alarm.isOn)
    }

    private func alarmTime(_ a: OneAlarm) -> String {
        let p = AlarmPlan.timeParts(hour: a.hour, minute: a.minute)
        return p.time + (p.suffix.map { " " + $0 } ?? "")
    }
}

private struct ResultRow: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String
    var dimmed = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(tint.gradient, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(dimmed ? .secondary : .primary).lineLimit(2)
                if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// The last few searches the user submitted, kept on the device.
private enum Recents {
    private static let key = "today.search.recents"
    static func load() -> [String] { UserDefaults.standard.stringArray(forKey: key) ?? [] }
    static func clear() { UserDefaults.standard.removeObject(forKey: key) }
    static func add(_ term: String) {
        let t = term.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        let list = ([t] + load().filter { $0.caseInsensitiveCompare(t) != .orderedSame }).prefix(6)
        UserDefaults.standard.set(Array(list), forKey: key)
    }
}

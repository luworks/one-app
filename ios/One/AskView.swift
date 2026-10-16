import SwiftUI
import SwiftData

struct ChatMessage: Identifiable, Equatable {
    enum Role { case user, ai }
    let id = UUID()
    let role: Role
    let text: String
}

/// Full-screen AI page, modeled on ChatGPT / Claude mobile.
/// No live model yet: statements become a capture preview; questions get a local summary.
/// Nothing is created until the user taps Add on the preview card.
struct AskView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(UndoToast.self) private var toast: UndoToast?
    @Query(sort: \OneTask.createdAt) private var tasks: [OneTask]
    @Query(sort: \OneEvent.start) private var events: [OneEvent]

    var onAdded: (Capture) -> Void = { _ in }

    @State private var messages: [ChatMessage] = []
    @State private var draft = ""
    @State private var pending: Capture?
    @State private var plan: [(task: OneTask, start: Date)] = []
    @State private var voice = VoiceInput()
    @State private var understanding: Task<Void, Never>?
    @State private var change: PendingChange?
    @State private var undoRow: UndoRow?
    @FocusState private var focused: Bool

    private let suggestions = [
        "Plan my day",
        "Call Alex tomorrow at 3pm",
        "Send the Q3 report by Friday",
        "What's left today?",
    ]

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    if messages.isEmpty {
                        emptyState
                    } else {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(messages) { MessageView(message: $0).id($0.id) }
                        }
                        .padding(20)
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messages) {
                    if let last = messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
            .safeAreaInset(edge: .bottom) { inputArea }
            .navigationTitle("AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                }
            }
            .task {
                focused = true
                Understander.prewarm()
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("What do you want to plan?")
                .font(.title2.bold())
            VStack(alignment: .leading, spacing: 10) {
                ForEach(suggestions, id: \.self) { s in
                    Button { send(s) } label: {
                        Text(s)
                            .font(.subheadline)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color(.secondarySystemFill), in: Capsule())
                    }
                    .buttonStyle(PressScale())
                    .tint(.primary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 60)
    }

    private var inputArea: some View {
        VStack(spacing: 8) {
            if !plan.isEmpty {
                PlanCard(plan: plan, onApply: applyPlan, onCancel: { plan = [] })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if let undo = undoRow {
                HStack(spacing: 12) {
                    Text(undo.label).font(.subheadline).lineLimit(2)
                    Spacer(minLength: 8)
                    Button("Undo") { undo.action(); undoRow = nil }
                        .font(.subheadline.weight(.semibold))
                        .accessibilityIdentifier("ask-undo")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if let change {
                ChangeCard(change: change, onApply: { apply(change) }, onCancel: { self.change = nil })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if understanding != nil {
                ProgressView().frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 16)
            }
            if let capture = pending {
                CaptureCard(capture: Binding(get: { pending ?? capture }, set: { pending = $0 }),
                            onAdd: { add(pending ?? capture) }, onCancel: { pending = nil })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Ask AI or add anything", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($focused)
                    .onChange(of: draft) { _, text in
                        // Return sends, like a chat app (a vertical TextField would insert a newline).
                        if text.hasSuffix("\n") { send(String(text.dropLast())) }
                    }
                    .padding(.vertical, 8)
                if isEmpty || voice.state == .listening {
                    Button { Task { await voice.toggle() } } label: {
                        Image(systemName: voice.state == .listening ? "stop.circle.fill" : "mic.fill")
                            .font(voice.state == .listening ? .system(size: 28) : .body)
                            .foregroundStyle(voice.state == .listening ? Color.red : Color.secondary)
                            .symbolEffect(.pulse, isActive: voice.state == .listening)
                            .frame(width: 36, height: 36)
                    }
                    .accessibilityLabel(voice.state == .listening ? "Stop dictation" : "Dictate")
                } else {
                    Button { send(draft) } label: {
                        Image(systemName: "arrow.up.circle.fill").font(.system(size: 32))
                    }
                    .accessibilityLabel("Send")
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 6)
            .padding(.vertical, 4)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 24))
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
        .animation(.snappy, value: pending)
        .animation(.snappy, value: plan.count)
        .animation(.snappy, value: change)
        .animation(.snappy, value: undoRow?.id)
        .onChange(of: voice.transcript) { _, text in
            if !text.isEmpty { draft = text }
        }
        .onChange(of: voice.state) { _, state in
            switch state {
            case .denied: messages.append(ChatMessage(role: .ai, text: "Microphone or speech access is off. Turn it on in Settings to dictate."))
            case .unavailable: messages.append(ChatMessage(role: .ai, text: "Dictation isn't available here. It works on iPhone."))
            default: break
            }
        }
    }

    private var isEmpty: Bool {
        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        messages.append(ChatMessage(role: .user, text: text))
        understanding?.cancel()
        understanding = nil
        pending = nil
        plan = []
        change = nil
        undoRow = nil
        if isPlanRequest(text) {
            proposePlan()
        } else if isQuestion(text) {
            messages.append(ChatMessage(role: .ai, text: todaySummary))
        } else if Editing.looksLikeEdit(text, items: editCandidates().items) {
            proposeEdit(text)
        } else {
            understand(text)
        }
    }

    /// On-device model when available, scripted parser otherwise. Only produces the preview card.
    private func understand(_ text: String) {
        understanding = Task {
            let capture = await Understander.parse(text)
            guard !Task.isCancelled else { return }
            pending = capture
            understanding = nil
            messages.append(ChatMessage(role: .ai, text: "Here's what I understood. Nothing is added until you confirm."))
        }
    }

    // MARK: Editing existing items

    /// Open tasks and the next week's events, with short ids the model can point at.
    private func editCandidates() -> (items: [EditItem], tasks: [String: OneTask], events: [String: OneEvent]) {
        let cal = Calendar.current
        let window = DateInterval(start: cal.startOfDay(for: .now), end: cal.date(byAdding: .day, value: 8, to: cal.startOfDay(for: .now)) ?? .now)
        var items: [EditItem] = []
        var taskByID: [String: OneTask] = [:]
        var eventByID: [String: OneEvent] = [:]
        let eventPairs = events.compactMap { e in e.occurrences(in: window).first.map { (e, $0) } }
            .sorted { $0.1 < $1.1 }.prefix(8)
        for (i, pair) in eventPairs.enumerated() {
            let id = "e\(i + 1)"
            eventByID[id] = pair.0
            let n = CalendarSync.shared.audience(externalID: pair.0.externalID)?.attendees ?? 0
            items.append(EditItem(id: id, type: "event", title: pair.0.title, start: pair.1, minutes: pair.0.durationMinutes, attendees: n))
        }
        let openTasks = tasks.filter { t in
            guard !t.isDone else { return false }
            guard let s = t.plannedStart else { return true }
            return window.contains(s)
        }.sorted { ($0.plannedStart ?? .distantFuture) < ($1.plannedStart ?? .distantFuture) }.prefix(12)
        for (i, t) in openTasks.enumerated() {
            let id = "t\(i + 1)"
            taskByID[id] = t
            items.append(EditItem(id: id, type: "task", title: t.title, start: t.plannedStart, minutes: t.durationMinutes, attendees: 0))
        }
        return (items, taskByID, eventByID)
    }

    /// Edit sentence → a ChangeCard, a question in the chat, or (not an edit after all) a capture. Nothing is written here.
    private func proposeEdit(_ text: String) {
        guard Understanding.unavailableReason(localeID: Locale.current.identifier) == nil else {
            messages.append(ChatMessage(role: .ai, text: "Apple Intelligence isn't available on this device, so I can't change existing items from a sentence. Open the item to edit it. Adding new things still works."))
            return
        }
        let candidates = editCandidates()
        understanding = Task {
            let plan = try? await Editing.plan(text, items: candidates.items, now: .now, calendar: .current)
            guard !Task.isCancelled else { return }
            understanding = nil
            let decision = Editing.decide(text: text, plan: plan, items: candidates.items, now: .now, calendar: .current)
            switch decision.op {
            case .none:
                understand(text)
            case .clarify:
                messages.append(ChatMessage(role: .ai, text: clarifyQuestion(decision, plan: plan, items: candidates.items)))
            case .move, .delete:
                guard let id = decision.target else { return }
                present(decision, id: id, candidates: candidates)
            }
        }
    }

    private func clarifyQuestion(_ d: EditDecision, plan: EditPlan?, items: [EditItem]) -> String {
        if d.reason.hasPrefix("several items match:") {
            let ids = d.reason.dropFirst("several items match:".count).split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
            let names = ids.compactMap { id in items.first { $0.id == id }?.title }.map { "“\($0)”" }
            return "Which one do you mean: " + names.joined(separator: ", ") + "?"
        }
        switch d.reason {
        case "several items": return "I change one item at a time. Which one first?"
        case "no item named": return "Which item do you mean?"
        case "no new time": return "When should I move it to?"
        case "model unavailable": return "I couldn't read that. Try rephrasing, or open the item to edit it."
        default: return "Which item do you mean, and to when?"
        }
    }

    private func present(_ d: EditDecision, id: String, candidates: (items: [EditItem], tasks: [String: OneTask], events: [String: OneEvent])) {
        if let event = candidates.events[id] {
            guard event.repeatRule == nil else {
                messages.append(ChatMessage(role: .ai, text: "“\(event.title)” repeats. Changing a single occurrence isn't supported yet. Open the event to edit it."))
                return
            }
            let audience = CalendarSync.shared.audience(externalID: event.externalID)
            var notes: [String] = []
            if let a = audience, a.attendees > 0 {
                notes.append(a.isOrganizer ? "The invitation update goes to \(a.attendees) attendee\(a.attendees == 1 ? "" : "s")."
                                           : "You're not the organizer: this changes your own calendar only; \(a.attendees) attendee\(a.attendees == 1 ? "" : "s") won't be told.")
            } else {
                notes.append("Only on your calendar. No one else is notified.")
            }
            notes.append("Meetings move only when you ask. This changes this one event.")
            change = PendingChange(subject: .event(event), delete: d.op == .delete, title: event.title,
                                   oldText: DayLabel.withTime(event.start), newStart: d.newStart, notes: notes)
        } else if let task = candidates.tasks[id] {
            var notes: [String] = []
            if d.op == .move {
                notes.append("Only the planned time changes." + (task.due != nil ? " The deadline stays." : ""))
                if task.ringsAsAlarm { notes.append("Its alarm follows the new time.") }
            }
            change = PendingChange(subject: .task(task), delete: d.op == .delete, title: task.title,
                                   oldText: task.plannedStart.map { DayLabel.withTime($0) } ?? "Not scheduled", newStart: d.newStart, notes: notes)
        } else { return }
        messages.append(ChatMessage(role: .ai, text: "Here's the change. Nothing changes until you apply it."))
    }

    private func apply(_ c: PendingChange) {
        change = nil
        switch c.subject {
        case .task(let task):
            if c.delete {
                let backup = task.copy()
                withAnimation { context.delete(task) }
                offerUndo("Deleted “\(backup.title)”.") { context.insert(backup) }
            } else if let new = c.newStart {
                let old = task.plannedStart // `due` is never touched
                withAnimation { task.plannedStart = new }
                messages.append(ChatMessage(role: .ai, text: "Moved “\(task.title)” to \(DayLabel.withTime(new))."))
                offerUndo("Moved “\(task.title)”.") { task.plannedStart = old }
            }
        case .event(let event):
            if c.delete {
                let backup = event.copy()
                CalendarSync.shared.delete(externalID: event.externalID, span: .thisEvent)
                withAnimation { context.delete(event) }
                messages.append(ChatMessage(role: .ai, text: "Deleted “\(backup.title)”."))
                offerUndo("Deleted “\(backup.title)”. Attendee updates already sent can't be recalled.") {
                    backup.externalID = CalendarSync.shared.save(backup, span: .thisEvent)
                    context.insert(backup)
                }
            } else if let new = c.newStart {
                let old = event.start
                event.start = new
                if event.externalID != nil, CalendarSync.shared.isOn, CalendarSync.shared.save(event, span: .thisEvent) == nil {
                    event.start = old
                    messages.append(ChatMessage(role: .ai, text: "Couldn't update the calendar event, so nothing changed."))
                    return
                }
                messages.append(ChatMessage(role: .ai, text: "Moved “\(event.title)” to \(DayLabel.withTime(new))."))
                offerUndo("Moved “\(event.title)”. Attendee updates already sent can't be recalled.") {
                    event.start = old
                    if event.externalID != nil { _ = CalendarSync.shared.save(event, span: .thisEvent) }
                }
            }
        }
    }

    /// The app's toast sits behind this full-screen page, so Undo lives here.
    private func offerUndo(_ label: String, _ action: @escaping () -> Void) {
        undoRow = UndoRow(label: label, action: { withAnimation { action() } })
    }

    private func add(_ capture: Capture) {
        capture.insert(into: context)
        onAdded(capture)
        messages.append(ChatMessage(role: .ai, text: "Added “\(capture.title)” · \(capture.summary)."))
        pending = nil
    }

    private func isPlanRequest(_ text: String) -> Bool {
        let t = text.lowercased()
        return ["plan my day", "plan today", "schedule my day", "安排今天", "规划今天", "帮我安排"].contains { t.contains($0) }
    }

    /// Proposes start times for today's flexible tasks around fixed events. Nothing moves until Apply.
    private func proposePlan() {
        let cal = Calendar.current
        let now = Date.now
        guard let endOfDay = cal.date(bySettingHour: 21, minute: 0, second: 0, of: now), endOfDay > now else {
            messages.append(ChatMessage(role: .ai, text: "It's late. Ask me to plan tomorrow instead."))
            return
        }
        let start = max(now, cal.date(bySettingHour: 8, minute: 0, second: 0, of: now) ?? now)
        let window = DateInterval(start: start, end: endOfDay)
        var busy = events.filter { !$0.isAllDay }.flatMap { e in
            e.occurs(on: now).map { DateInterval(start: $0, duration: e.duration) }
        }
        busy += CalendarSync.shared.events(on: now).filter { !$0.isAllDay }.map { DateInterval(start: $0.start, end: $0.end) }
        busy += tasks.compactMap { t in
            guard !t.isDone, let s = t.plannedStart, cal.isDateInToday(s) else { return nil }
            return DateInterval(start: s, duration: TimeInterval(t.durationMinutes * 60))
        }
        func rank(_ t: OneTask) -> Int {
            if t.isOverdue { return 0 }
            if let d = t.due, cal.isDateInToday(d) { return 1 }
            if t.flagged { return 2 }
            return 3
        }
        let candidates = tasks.filter { !$0.isDone && $0.plannedStart == nil && rank($0) < 3 }
            .sorted { (rank($0), $0.createdAt) < (rank($1), $1.createdAt) }
        let items = candidates.enumerated().map { DayPlanner.Item(id: $0.offset, minutes: $0.element.durationMinutes) }
        let result = DayPlanner.plan(items, busy: busy, window: window)
        plan = result.map { (candidates[$0.id], $0.start) }
        if plan.isEmpty {
            messages.append(ChatMessage(role: .ai, text: candidates.isEmpty
                ? "Nothing urgent to place: no overdue, due-today or flagged tasks without a time."
                : "Your day is full. Nothing fits before 9 PM."))
        } else {
            let skipped = candidates.count - plan.count
            messages.append(ChatMessage(role: .ai, text: "Here's a plan around your meetings. Meetings stay fixed; only tasks move. Nothing changes until you apply it."
                + (skipped > 0 ? " \(skipped) task\(skipped == 1 ? "" : "s") didn't fit." : "")))
        }
    }

    private func applyPlan() {
        let applied = plan
        withAnimation {
            for p in applied { p.task.plannedStart = p.start }
        }
        plan = []
        messages.append(ChatMessage(role: .ai, text: "Planned \(applied.count) task\(applied.count == 1 ? "" : "s") for today."))
        offerUndo("Planned \(applied.count) task\(applied.count == 1 ? "" : "s").") {
            for p in applied { p.task.plannedStart = nil }
        }
    }

    private func isQuestion(_ text: String) -> Bool {
        text.hasSuffix("?") || text.hasSuffix("？") || ["什么", "怎么", "吗", "多少", "几"].contains { text.contains($0) }
            || ["what", "how", "when", "which", "do ", "is ", "am ", "any"].contains { text.lowercased().hasPrefix($0) }
    }

    private var todaySummary: String {
        let cal = Calendar.current
        let open = tasks.filter { task in
            guard !task.isDone else { return false }
            if task.isOverdue { return true }
            if let s = task.plannedStart, cal.isDateInToday(s) { return true }
            if let d = task.due, cal.isDateInToday(d) { return true }
            return false
        }
        let todayEvents = events.compactMap { e in e.occurs(on: .now).first { $0 > .now }.map { (e, $0) } }
        var lines = ["Today: \(open.count) open task\(open.count == 1 ? "" : "s") and \(todayEvents.count) upcoming event\(todayEvents.count == 1 ? "" : "s")."]
        lines += open.prefix(5).map { "· " + $0.title }
        lines += todayEvents.prefix(3).map { "· " + $0.1.formatted(date: .omitted, time: .shortened) + " " + $0.0.title }
        lines.append("(No AI model connected yet. This is a summary of your local data.)")
        return lines.joined(separator: "\n")
    }
}

/// User messages are bubbles on the right; AI replies are plain text, no bubble.
struct MessageView: View {
    let message: ChatMessage

    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 48)
                Text(message.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 20))
            }
        case .ai:
            Text(message.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// AI plan preview: proposed start times, applied only on tap.
struct PlanCard: View {
    let plan: [(task: OneTask, start: Date)]
    var onApply: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Plan for today", systemImage: "sparkles")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(Array(plan.enumerated()), id: \.offset) { _, p in
                HStack(spacing: 10) {
                    Text(p.start.formatted(date: .omitted, time: .shortened))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 64, alignment: .leading)
                    Text(p.task.title).font(.subheadline)
                    Spacer(minLength: 0)
                    Text(DurationLabel.text(minutes: p.task.durationMinutes))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                Button("Cancel", action: onCancel).buttonStyle(.bordered)
                Spacer()
                Button("Apply", action: onApply).buttonStyle(.borderedProminent)
            }
            .padding(.top, 4)
        }
        .padding(14)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.secondary.opacity(0.25)))
    }
}

/// An AI edit waiting for Apply: what changes and who it reaches. Nothing has been written yet.
struct PendingChange: Equatable, Identifiable {
    enum Subject { case task(OneTask), event(OneEvent) }
    let id = UUID()
    let subject: Subject
    let delete: Bool
    let title: String
    let oldText: String
    let newStart: Date?
    let notes: [String]

    static func == (a: PendingChange, b: PendingChange) -> Bool { a.id == b.id }

    var isEvent: Bool { if case .event = subject { true } else { false } }
}

struct UndoRow: Identifiable {
    let id = UUID()
    let label: String
    let action: () -> Void
}

/// AI change preview: old → new, who is affected, applied only on tap.
struct ChangeCard: View {
    let change: PendingChange
    var onApply: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(heading, systemImage: "sparkles")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(change.title).font(.headline)
            if change.delete {
                Text(change.oldText).font(.subheadline).foregroundStyle(.secondary)
            } else if let new = change.newStart {
                Text("\(change.oldText) → \(DayLabel.withTime(new))")
                    .font(.subheadline)
                    .accessibilityIdentifier("change-times")
            }
            ForEach(change.notes, id: \.self) { note in
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("Cancel", action: onCancel).buttonStyle(.bordered)
                Spacer()
                Button(change.delete ? "Delete" : "Apply", action: onApply).buttonStyle(.borderedProminent)
            }
            .padding(.top, 4)
        }
        .padding(14)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.secondary.opacity(0.25)))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("change-card")
    }

    private var heading: String {
        switch (change.delete, change.isEvent) {
        case (false, false): "Move task"
        case (false, true): "Move event"
        case (true, false): "Delete task"
        case (true, true): "Delete event"
        }
    }
}

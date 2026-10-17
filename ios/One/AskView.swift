import SwiftUI
import SwiftData

struct ChatMessage: Identifiable, Equatable, Codable {
    enum Role: String, Codable { case user, ai }
    var id = UUID()
    let role: Role
    let text: String

    /// One of the app's own status sentences (see `MessageCopy`): no Copy button under it.
    var isTemplate: Bool { MessageCopy.isTemplate(isUser: role == .user, text: text) }
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
    /// Asks the presenter to show what this screen goes back to (`true`), underneath it, or to undo that
    /// when a back swipe is cancelled (`false`). Called before the screen closes, by the close button or a swipe.
    var onBack: (Bool) -> Void = { _ in }

    /// The saved conversation this screen continues. nil = a new chat; the thread is created on the first user message.
    @State private var thread: ChatThread?
    @State private var messages: [ChatMessage]
    @State private var draft = ""
    /// Every item proposed from the last line, shown together. Added ones stay a moment as a check, then leave.
    @State private var proposals: [CaptureProposal] = []
    @Query(sort: \OneList.order) private var lists: [OneList]
    @State private var thinking = false
    @State private var captureTask: Task<Void, Never>?
    @State private var plan: [(task: OneTask, start: Date)] = []
    /// The "Plan reminders into free time" grant, while one is active (the plan card then says so instead of offering it).
    @State private var planGrant: AIGrant?
    /// "Tidy overdue": a new date per overdue reminder, waiting for Apply.
    @State private var tidy: [TidyRow] = []
    @State private var voice = VoiceInput()
    @State private var change: PendingChange?
    @State private var undoRow: UndoRow?
    /// What the last turn left open (a "which one?" with real items, or a "when?"), so the next message can answer it.
    @State private var followup: Followup?
    /// Title of the item the conversation touched last: what "it" means.
    @State private var lastTouched: String?
    @FocusState private var focused: Bool
    /// Swipe right to go back: horizontal offset of the screen while the finger moves, 0 otherwise.
    @State private var backDrag: CGFloat = 0
    /// nil until the first event of a drag decides whether it is a back swipe.
    @State private var backClaim: Bool?
    @GestureState private var backActive = false
    @State private var screenWidth: CGFloat = 0
    /// Drags that start on the "which one?" chips scroll them instead of going back.
    @State private var choiceFrame: CGRect = .zero

    init(thread: ChatThread? = nil, onBack: @escaping (Bool) -> Void = { _ in }, onAdded: @escaping (Capture) -> Void = { _ in }) {
        self.onAdded = onAdded
        self.onBack = onBack
        _thread = State(initialValue: thread)
        _messages = State(initialValue: thread?.messages ?? [])
    }

    private let suggestions = [
        "Plan my day",
        "Tidy overdue",
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
                            if thinking {
                                HStack(spacing: 8) {
                                    ProgressView()
                                    Text("Thinking…").foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(20)
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .defaultScrollAnchor(messages.isEmpty ? .top : .bottom)
                .onChange(of: messages) {
                    persist()
                    if let last = messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
            .safeAreaInset(edge: .bottom) { inputArea }
            .navigationTitle("AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { close() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                }
            }
            .task {
                // A reopened conversation starts at its end with the keyboard down; a new chat is ready to type.
                if messages.isEmpty { focused = true }
                Understander.prewarm()
            }
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        // A soft edge on the left while the screen slides away, like the drawer's page.
        .background(alignment: .leading) {
            LinearGradient(colors: [.clear, .black.opacity(0.10)], startPoint: .leading, endPoint: .trailing)
                .frame(width: 14)
                .offset(x: -14)
                .ignoresSafeArea()
                .opacity(backDrag > 0 ? 1 : 0)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { screenWidth = $0 }
        .offset(x: backDrag)
        .simultaneousGesture(backSwipe)
        // `onEnded` is skipped when the system cancels a drag; settle a claimed one by position.
        .onChange(of: backActive) { _, isActive in
            guard !isActive else { return }
            Task { @MainActor in
                if backClaim == true { settleBack(projected: backDrag) } else { backClaim = nil }
            }
        }
        // Clear, so what this screen goes back to (the sidebar or the page) shows underneath during a back swipe.
        .presentationBackground(.clear)
    }

    // MARK: Going back

    /// Closes the screen and returns to where it was opened from (the sidebar, when opened there).
    private func close(animated: Bool = true) {
        onBack(true)
        if animated {
            dismiss()
        } else {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { dismiss() }
        }
    }

    /// Swipe right anywhere to go back, like a pushed screen. Mostly-horizontal rightward drags only,
    /// so scrolling the conversation is left alone.
    private var backSwipe: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .updating($backActive) { _, state, _ in state = true }
            .onChanged { v in
                if backClaim == nil {
                    let t = v.translation
                    let rightward = t.width > 0 && t.width > abs(t.height) * 1.2
                    backClaim = rightward && !choiceFrame.contains(v.startLocation)
                    if backClaim == true {
                        focused = false
                        onBack(true)
                    }
                }
                guard backClaim == true else { return }
                backDrag = max(v.translation.width, 0)
            }
            .onEnded { v in
                guard backClaim == true else { backClaim = nil; return }
                settleBack(projected: v.predictedEndTranslation.width)
            }
    }

    /// Finishes the back swipe when the finger was heading past half the screen (`projected` includes momentum), otherwise springs back.
    private func settleBack(projected: CGFloat) {
        backClaim = nil
        let width = max(screenWidth, 1)
        if max(projected, backDrag) > width / 2 && projected > 0 {
            withAnimation(DrawerModel.spring) { backDrag = width } completion: { close(animated: false) }
        } else {
            withAnimation(DrawerModel.spring) { backDrag = 0 }
            onBack(false)
        }
    }

    /// Saves the conversation as it grows: the thread is created with the first user message and updated after
    /// every later message (AI replies included). Only text is kept.
    private func persist() {
        guard let first = messages.first(where: { $0.role == .user }) else { return }
        if let thread {
            thread.messages = messages
            thread.updatedAt = .now
            // Continuing an archived conversation brings it back to the main list.
            thread.archived = false
        } else {
            let created = ChatThread(title: ConversationHistory.title(from: first.text), messages: messages)
            context.insert(created)
            thread = created
        }
        try? context.save()
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
                    .accessibilityIdentifier("ask-suggestion")
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
                PlanCard(plan: plan, grantUntil: planGrant?.expires, onApply: { applyPlan() }, onAlways: applyPlanAlways,
                         onCancel: { plan = [] })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if !tidy.isEmpty {
                TidyCard(rows: $tidy, onApply: applyTidy, onCancel: { tidy = [] })
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
            if case .chooseItem(_, let options)? = followup {
                ChoiceBar(options: options, onPick: tapChoice)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { choiceFrame = $0 }
                    .onDisappear { choiceFrame = .zero }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if let change {
                ChangeCard(change: change, onApply: { apply(change) }, onCancel: { self.change = nil })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if !proposals.isEmpty {
                CaptureStack(proposals: $proposals, lists: lists.map(\.name),
                             onAdd: add, onSkip: skip, onAddAll: addAll)
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
        .animation(.snappy, value: proposals)
        .animation(.snappy, value: plan.count)
        .animation(.snappy, value: change)
        .animation(.snappy, value: followup)
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
        captureTask?.cancel()
        thinking = false
        let history = Dialogue.recap(messages.map { ($0.role == .user, $0.text) })
        messages.append(ChatMessage(role: .user, text: text))
        plan = []
        tidy = []
        undoRow = nil
        // The message may answer what the last turn left open, or edit the preview that is showing.
        if answerOpenTurn(text, history: history) { return }
        followup = nil
        if OverdueTidy.isRequest(text) {
            clearPreviews()
            proposeTidy()
        } else if isPlanRequest(text) {
            clearPreviews()
            proposePlan()
        } else if isQuestion(text) {
            // A question does not throw away the card the user is looking at.
            messages.append(ChatMessage(role: .ai, text: todaySummary))
        } else if Editing.looksLikeEdit(text, items: editCandidates().items) {
            clearPreviews()
            proposeEdit(text, history: history)
        } else {
            clearPreviews()
            propose(text)
        }
    }

    private func clearPreviews() {
        proposals = []
        change = nil
    }

    /// The first item still waiting for Add: what a follow-up like "make it 5pm" edits. Setting nil drops them all.
    private var pending: Capture? {
        get { proposals.first { $0.state == .open }?.capture }
        nonmutating set {
            guard let newValue else { proposals = []; return }
            if let i = proposals.firstIndex(where: { $0.state == .open }) { proposals[i].capture = newValue }
        }
    }

    // MARK: Multi-turn

    /// A turn that asked something. The options are real items; tapping one and typing "the second one" take the same path.
    enum Followup: Equatable {
        case chooseItem(text: String, options: [ChoiceOption])
        case needTime(ChoiceOption)
        case alarmTime
    }

    struct ChoiceOption: Identifiable, Equatable {
        let id = UUID()
        let title: String
        let type: String
        let when: Date?
    }

    /// Reads `text` as the answer to the previous turn. False means it is something new.
    private func answerOpenTurn(_ text: String, history: String) -> Bool {
        let now = Date.now
        let cal = Calendar.current
        switch followup {
        case .chooseItem(let original, let options):
            if let i = Dialogue.answerToWhichOne(text, from: options.map(\.title)) {
                followup = nil
                choose(options[i], original: original, history: history)
                return true
            }
        case .needTime(let option):
            let candidates = editCandidates()
            if let item = fresh(option, in: candidates.items) {
                if let start = Dialogue.answerTime(text, keeping: item.start, now: now, calendar: cal) {
                    followup = nil
                    present(EditDecision(op: .move, target: item.id, newStart: start, reason: "ok"), id: item.id, candidates: candidates)
                    return true
                }
            } else {
                followup = nil
            }
        case .alarmTime:
            if let capture = pending, case .updated(let c) = Dialogue.refine(capture, with: "alarm " + text, now: now, calendar: cal) {
                followup = nil
                pending = c
                messages.append(ChatMessage(role: .ai, text: "Set as an alarm. Nothing is added until you confirm."))
                return true
            }
        case nil: break
        }

        if Dialogue.refine(Capture(title: "_", day: .now, hasDay: false), with: text) == .dismissed, pending != nil || change != nil {
            clearPreviews()
            followup = nil
            messages.append(ChatMessage(role: .ai, text: "OK, dropped it."))
            return true
        }
        if let capture = pending {
            switch Dialogue.refine(capture, with: text, now: now, calendar: cal) {
            case .updated(let c):
                pending = c
                messages.append(ChatMessage(role: .ai, text: "Updated. Nothing is added until you confirm."))
                return true
            case .needsTime:
                followup = .alarmTime
                messages.append(ChatMessage(role: .ai, text: "What time should it ring?"))
                return true
            case .dismissed, .notARefinement:
                break
            }
        }
        if let current = change, !current.delete, Dialogue.isOnlyWhen(text),
           let new = Dialogue.answerTime(text, keeping: current.newStart, now: now, calendar: cal) {
            var updated = current
            updated.newStart = new
            change = updated
            messages.append(ChatMessage(role: .ai, text: "Updated. Nothing changes until you apply it."))
            return true
        }
        return false
    }

    /// The item for an option, looked up again in today's candidates (ids are only valid within one request).
    private func fresh(_ option: ChoiceOption, in items: [EditItem]) -> EditItem? {
        items.first { $0.title == option.title && $0.type == option.type }
    }

    private func option(_ item: EditItem) -> ChoiceOption {
        ChoiceOption(title: item.title, type: item.type, when: item.start)
    }

    /// The user picked one of the offered items (tap or words): continue the sentence that raised the question.
    private func choose(_ option: ChoiceOption, original: String, history: String) {
        let candidates = editCandidates()
        guard let item = fresh(option, in: candidates.items) else {
            messages.append(ChatMessage(role: .ai, text: "“\(option.title)” isn't in your next week any more."))
            return
        }
        let d = Editing.decide(text: original, chosen: item, delete: false, now: .now, calendar: .current)
        handle(d, text: original, plan: nil, candidates: candidates, history: history)
    }

    private func tapChoice(_ option: ChoiceOption) {
        guard case .chooseItem(let original, _)? = followup else { return }
        messages.append(ChatMessage(role: .user, text: option.title))
        followup = nil
        choose(option, original: original, history: Dialogue.recap(messages.map { ($0.role == .user, $0.text) }))
    }

    /// On-device model when available, scripted parser otherwise. Only produces the preview card.
    private func understand(_ text: String) {
        thinking = true
        captureTask = Task { @MainActor in
            let capture = await Understander.parse(text)
            guard !Task.isCancelled else { return }
            thinking = false
            show([capture])
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
    private func proposeEdit(_ text: String, history: String) {
        let candidates = editCandidates()
        // The words usually settle which item is meant; the model is asked only when they do not.
        guard Editing.needsModel(text, items: candidates.items) else {
            handle(Editing.decide(text: text, plan: nil, items: candidates.items, now: .now, calendar: .current, focus: focusItem(candidates.items)),
                   text: text, plan: nil, candidates: candidates, history: history)
            return
        }
        guard Understanding.unavailableReason(localeID: Locale.current.identifier) == nil else {
            messages.append(ChatMessage(role: .ai, text: "Apple Intelligence isn't available on this device, so I can't tell which item you mean from that sentence. Name the item, or open it to edit it."))
            return
        }
        thinking = true
        captureTask = Task { @MainActor in
            let items = candidates.items
            let plan = await ModelTimeout.run(seconds: 20) { try? await Editing.plan(text, items: items, now: .now, calendar: .current, history: history) }
            guard !Task.isCancelled else { return }
            thinking = false
            if plan == nil {
                messages.append(ChatMessage(role: .ai, text: "The on-device model didn't answer in time. Try again in a moment, or name the item."))
                return
            }
            handle(Editing.decide(text: text, plan: plan?.pick, items: items, now: .now, calendar: .current, focus: focusItem(items)),
                   text: text, plan: plan, candidates: candidates, history: history)
        }
    }

    private func focusItem(_ items: [EditItem]) -> EditItem? {
        lastTouched.flatMap { title in items.first { $0.title == title } }
    }

    private func handle(_ decision: EditDecision, text: String, plan: EditPlan?,
                        candidates: (items: [EditItem], tasks: [String: OneTask], events: [String: OneEvent]), history: String) {
        switch decision.op {
        case .none:
            propose(text)
        case .clarify:
            clarify(decision, text: text, plan: plan, items: candidates.items)
        case .move, .delete:
            guard let id = decision.target else { return }
            present(decision, id: id, candidates: candidates)
        }
    }

    /// Asks one question and remembers it. When the answer is a choice between items, the choices are real items and are tappable.
    private func clarify(_ d: EditDecision, text: String, plan: EditPlan?, items: [EditItem]) {
        if d.reason.hasPrefix("several items match:") {
            let ids = d.reason.dropFirst("several items match:".count).split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
            let options = ids.compactMap { id in items.first { $0.id == id } }.prefix(5).map(option)
            followup = .chooseItem(text: text, options: Array(options))
            messages.append(ChatMessage(role: .ai, text: "Which one do you mean?"))
        } else if d.reason == "no new time", let id = d.target, let item = items.first(where: { $0.id == id }) {
            followup = .needTime(option(item))
            messages.append(ChatMessage(role: .ai, text: "When should I move “\(item.title)” to?"))
        } else if d.reason == "no item named", !items.isEmpty {
            followup = .chooseItem(text: text, options: items.prefix(5).map(option))
            messages.append(ChatMessage(role: .ai, text: "Which item do you mean?"))
        } else {
            messages.append(ChatMessage(role: .ai, text: clarifyQuestion(d, plan: plan, items: items)))
        }
    }

    private func clarifyQuestion(_ d: EditDecision, plan: EditPlan?, items: [EditItem]) -> String {
        switch d.reason {
        case "several items": return "I change one item at a time. Which one first?"
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
            lastTouched = event.title
            change = PendingChange(subject: .event(event), delete: d.op == .delete, title: event.title,
                                   oldText: DayLabel.withTime(event.start), newStart: d.newStart, notes: notes,
                                   attendees: audience?.attendees ?? 0)
        } else if let task = candidates.tasks[id] {
            var notes: [String] = []
            if d.op == .move {
                notes.append("Only the planned time changes." + (task.due != nil ? " The deadline stays." : ""))
                if task.ringsAsAlarm { notes.append("Its alarm follows the new time.") }
            }
            lastTouched = task.title
            change = PendingChange(subject: .task(task), delete: d.op == .delete, title: task.title,
                                   oldText: task.plannedStart.map { DayLabel.withTime($0) } ?? "Not scheduled", newStart: d.newStart, notes: notes,
                                   attendees: 0)
        } else { return }
        messages.append(ChatMessage(role: .ai, text: "Here's the change. Nothing changes until you apply it."))
    }

    private func apply(_ c: PendingChange) {
        change = nil
        switch c.subject {
        case .task(let task):
            if c.delete {
                let backup = task.copy()
                let entry = Ledger.record(.deleted, title: backup.title, actor: .todayAI, channel: .ask, approval: .asked,
                                          snapshot: Ledger.snapshot(of: task), context: context)
                withAnimation { context.delete(task) }
                offerUndo("Deleted “\(backup.title)”.") {
                    context.insert(backup)
                    Ledger.recordUndo(of: entry, channel: .ask, context: context)
                }
            } else if let new = c.newStart {
                let old = task.plannedStart // `due` is never touched
                let entry = TaskActions.setPlanned(task, to: new, context: context, actor: .todayAI, channel: .ask, approval: .asked)
                messages.append(ChatMessage(role: .ai, text: "Moved “\(task.title)” to \(DayLabel.withTime(new))."))
                offerUndo("Moved “\(task.title)”.") {
                    task.plannedStart = old
                    if let entry { Ledger.recordUndo(of: entry, channel: .ask, context: context) }
                }
            }
        case .event(let event):
            if c.delete {
                let backup = event.copy()
                guard CalendarSync.shared.delete(event, span: .thisEvent) else {
                    messages.append(ChatMessage(role: .ai, text: "Couldn't delete the calendar event, so nothing changed."))
                    return
                }
                Ledger.record(.deleted, kind: "event", title: backup.title, before: c.oldText, actor: .todayAI, channel: .ask,
                              approval: .asked, context: context)
                withAnimation { context.delete(event) }
                messages.append(ChatMessage(role: .ai, text: "Deleted “\(backup.title)”."))
                offerUndo("Deleted “\(backup.title)”." + recallNote(c)) {
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
                Ledger.record(.moved, kind: "event", title: event.title, before: DayLabel.withTime(old), after: DayLabel.withTime(new),
                              actor: .todayAI, channel: .ask, approval: .asked, context: context)
                messages.append(ChatMessage(role: .ai, text: "Moved “\(event.title)” to \(DayLabel.withTime(new))."))
                offerUndo("Moved “\(event.title)”." + recallNote(c)) {
                    event.start = old
                    if event.externalID != nil { _ = CalendarSync.shared.save(event, span: .thisEvent) }
                }
            }
        }
    }

    private func recallNote(_ c: PendingChange) -> String {
        c.attendees > 0 ? " Attendee updates already sent can't be recalled." : ""
    }

    /// The app's toast sits behind this full-screen page, so Undo lives here.
    private func offerUndo(_ label: String, _ action: @escaping () -> Void) {
        undoRow = UndoRow(label: label, action: { withAnimation { action() } })
    }

    /// One item per line: the rule parser reads the day / time / title and the on-device model only says task / event / alarm.
    /// A line that lists several things goes to the multi-item model path when it is available.
    private func propose(_ text: String) {
        // UI tests only (`-uiTesting -uiTestingMultiCapture`): the simulator has no on-device model, so a line with ";"
        // is split by the rule parser into several proposals, to exercise the multi-item card.
        if ProcessInfo.processInfo.arguments.contains("-uiTestingMultiCapture"), text.contains(";") {
            show(text.split(separator: ";").map { CaptureParser.parse(String($0).trimmingCharacters(in: .whitespaces)) })
            return
        }
        if AICapture.isAvailable, text.range(of: #"[；;\n]|然后|另外还|\band then\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
            proposeList(text)
        } else {
            understand(text)
        }
    }

    /// A line that lists several things: the multi-item Apple Intelligence path when the model is available, else the parser.
    private func proposeList(_ text: String) {
        guard AICapture.isAvailable else {
            show([CaptureParser.parse(text)])
            return
        }
        thinking = true
        captureTask = Task { @MainActor in
            let proposed = await AICapture.propose(text)
            guard !Task.isCancelled else { return }
            thinking = false
            show(proposed ?? [CaptureParser.parse(text)])
        }
    }

    private func show(_ captures: [Capture]) {
        proposals = captures.map { CaptureProposal(capture: filed($0), batchSize: captures.count) }
        messages.append(ChatMessage(role: .ai, text: captures.count == 1
            ? "Here's what I understood. Nothing is added until you confirm."
            : "I found \(captures.count) items. Add them one by one or all at once; nothing is added until you confirm."))
    }

    /// A task goes to the list it clearly belongs to, else the Inbox. Never silently to whatever list is the default.
    private func filed(_ capture: Capture) -> Capture {
        guard capture.kind == .task, !capture.ringsAsAlarm, capture.listName == nil else { return capture }
        var c = capture
        let names = lists.map(\.name)
        let candidates = lists.map { list in
            ListGuess.Candidate(name: list.name, titles: tasks.filter { $0.listName == list.name }.suffix(300).map(\.title))
        }
        c.listName = ListGuess.guess(c.title, lists: candidates).list ?? ListGuess.inbox(in: names)
        return c
    }

    private func add(_ id: UUID) {
        guard let capture = commit(id) else { return }
        messages.append(ChatMessage(role: .ai, text: "Added “\(capture.title)” · \(addedDetail(capture))."))
    }

    private func addAll() {
        let added = proposals.filter { $0.state == .open }.compactMap { commit($0.id) }
        guard !added.isEmpty else { return }
        messages.append(ChatMessage(role: .ai, text: "Added \(added.count) items:\n"
            + added.map { "· “\($0.title)” · \(addedDetail($0))" }.joined(separator: "\n")))
    }

    /// Writes one proposal, marks it added (the card turns into a check), and lets it leave a moment later.
    private func commit(_ id: UUID) -> Capture? {
        guard let i = proposals.firstIndex(where: { $0.id == id && $0.state == .open }) else { return nil }
        let capture = proposals[i].capture
        let item = capture.insert(into: context, actor: .todayAI, channel: .ask, approval: .asked)
        thread?.items.append(item)
        lastTouched = capture.title
        onAdded(capture)
        withAnimation(.snappy) { proposals[i].state = .added }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.4))
            withAnimation(.snappy) { proposals.removeAll { $0.id == id } }
        }
        return capture
    }

    private func skip(_ id: UUID) {
        withAnimation(.snappy) { proposals.removeAll { $0.id == id } }
    }

    private func addedDetail(_ c: Capture) -> String {
        guard c.kind == .task, !c.ringsAsAlarm else { return c.summary }
        return c.summary + " · " + c.listLabel
    }

    private func isPlanRequest(_ text: String) -> Bool {
        let t = text.lowercased()
        return ["plan my day", "plan today", "schedule my day", "安排今天", "规划今天", "帮我安排"].contains { t.contains($0) }
    }

    /// Proposes start times for today's flexible tasks around fixed events. Nothing moves until Apply.
    private func proposePlan() {
        let cal = Calendar.current
        let now = TodayClock.now
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
        planGrant = GrantStore.active(.planFreeTime, context: context, now: .now)
        if planGrant != nil, !plan.isEmpty {
            // Under the grant, what the policy allows applies by itself; the rest (overdue, …) stays on the card.
            let grants = GrantStore.infos(context)
            let protected = Ledger.protectedRefs(context, now: .now)
            let auto = plan.filter { p in
                let ref = Ledger.ref(p.task.persistentModelID)
                let change = ProposedChange(target: .reminder, operation: .setPlannedTime, isOverdue: p.task.isOverdue,
                                            isDone: p.task.isDone, ringsAsAlarm: p.task.ringsAsAlarm,
                                            aiChangedRecently: ref.map(protected.aiRecent.contains) ?? false,
                                            userChoseTime: ref.map(protected.userChose.contains) ?? false)
                return AutonomyPolicy.decide(change, grants: grants, now: .now) == .auto
            }
            if !auto.isEmpty {
                let autoIDs = Set(auto.map { ObjectIdentifier($0.task) })
                plan.removeAll { autoIDs.contains(ObjectIdentifier($0.task)) }
                applyPlan(auto, approval: .autoUnderGrant)
                return
            }
        }
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

    /// Writes the plan's planned times (never deadlines) and records each in Activity. `rows` defaults to the card's.
    private func applyPlan(_ rows: [(task: OneTask, start: Date)]? = nil, approval: LedgerApproval = .asked) {
        let applied = rows ?? plan
        let auto = approval == .autoUnderGrant
        let entries = applied.compactMap { p in
            TaskActions.setPlanned(p.task, to: p.start, context: context, actor: .todayAI,
                                   channel: auto ? .automatic : .ask, approval: approval)
        }
        if rows == nil { plan = [] }
        let n = applied.count
        let label = auto ? LedgerFormat.autoPlanned(n) + "." : "Planned \(n) task\(n == 1 ? "" : "s")."
        var text = auto ? label + " Automatic until \(DayLabel.text(for: planGrant?.expires ?? .now))."
                        : "Planned \(n) task\(n == 1 ? "" : "s") for today."
        if auto, !plan.isEmpty { text += " \(plan.count) more need\(plan.count == 1 ? "s" : "") your OK." }
        messages.append(ChatMessage(role: .ai, text: text))
        offerUndo(label) {
            for p in applied where p.task.plannedStart == p.start { p.task.plannedStart = nil }
            for e in entries { Ledger.recordUndo(of: e, channel: .ask, context: context) }
        }
    }

    /// "Always for 7 days": applies this card now (the user's tap) and lets the same kind of change apply by itself for
    /// 7 days, under `AutonomyPolicy`. Revoke in Settings → AI → Automatic changes.
    private func applyPlanAlways() {
        planGrant = GrantStore.grant(.planFreeTime, context: context)
        applyPlan()
        messages.append(ChatMessage(role: .ai, text: "For the next 7 days I'll plan reminders due today into free time by myself "
            + "and tell you each time. Only Today's planned times change. Revoke it in Settings."))
    }

    /// Suggests a new date for every overdue reminder (see `OverdueTidy`). Nothing changes until Apply.
    private func proposeTidy() {
        let overdue = tasks.filter(\.isOverdue)
        guard !overdue.isEmpty else {
            messages.append(ChatMessage(role: .ai, text: "Nothing is overdue."))
            return
        }
        let items = overdue.enumerated().compactMap { i, t in
            t.due.map { OverdueTidy.Item(id: i, due: $0, flagged: t.flagged, repeats: t.repeats != nil) }
        }
        tidy = OverdueTidy.suggest(items).compactMap { s in
            overdue[s.id].due.map { TidyRow(task: overdue[s.id], oldDue: $0, choice: s.choice) }
        }
        let n = tidy.count
        messages.append(ChatMessage(role: .ai, text: "\(n) overdue reminder\(n == 1 ? "" : "s"). Flagged and recent ones first, three a day; "
            + "ones older than a month lose their date but stay in their list. Change any row, then Apply. Nothing changes until you do."))
    }

    private func applyTidy() {
        let changes = tidy.filter { $0.choice != .keep }
        var entries: [LedgerEntry] = []
        withAnimation {
            for r in changes {
                let new = OverdueTidy.newDue(r.oldDue, r.choice)
                r.task.due = new
                entries.append(Ledger.record(.redated, task: r.task, title: r.task.title, before: LedgerFormat.time(r.oldDue, none: "No date"),
                                             after: LedgerFormat.time(new, none: "No date"), beforeDate: r.oldDue, afterDate: new,
                                             actor: .todayAI, channel: .ask, approval: .asked, context: context))
            }
        }
        try? context.save()
        tidy = []
        let label = "Moved \(changes.count) reminder\(changes.count == 1 ? "" : "s")."
        messages.append(ChatMessage(role: .ai, text: label))
        offerUndo(label) {
            for r in changes { r.task.due = r.oldDue }
            for e in entries { Ledger.recordUndo(of: e, channel: .ask, context: context) }
            try? context.save()
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
        return lines.joined(separator: "\n")
    }
}

/// User messages are bubbles on the right; AI replies are plain text, no bubble. Text can be selected
/// (long-press), and a small copy button sits under each message, as in ChatGPT.
struct MessageView: View {
    let message: ChatMessage
    @State private var copied = false

    var body: some View {
        switch message.role {
        case .user:
            VStack(alignment: .trailing, spacing: 4) {
                HStack {
                    Spacer(minLength: 48)
                    Text(message.text)
                        .textSelection(.enabled)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 20))
                }
                copyButton
            }
        case .ai:
            VStack(alignment: .leading, spacing: 4) {
                Text(message.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                // The app's own status sentences ("Here's what I understood…", "Updated…") have nothing worth copying.
                if !message.isTemplate { copyButton }
            }
        }
    }

    private var copyButton: some View {
        Button {
            UIPasteboard.general.string = message.text
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                copied = false
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.success, trigger: copied) { _, new in new }
        .accessibilityLabel(copied ? "Copied" : "Copy message")
        .accessibilityIdentifier("message.copy")
    }
}

/// One overdue reminder on the tidy card, with the date the user picked for it.
struct TidyRow: Identifiable {
    let id = UUID()
    let task: OneTask
    let oldDue: Date
    var choice: OverdueTidy.Choice
}

/// "Tidy overdue" preview: a suggested date per reminder, each changeable from its menu; Apply writes them all.
struct TidyCard: View {
    @Binding var rows: [TidyRow]
    var onApply: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("New dates for overdue", systemImage: "sparkles")
                .font(.caption)
                .foregroundStyle(.secondary)
            ViewThatFits(in: .vertical) {
                list
                ScrollView { list }
            }
            .frame(maxHeight: 240)
            HStack {
                Button("Cancel", action: onCancel).buttonStyle(.bordered)
                Spacer()
                Button("Apply", action: onApply)
                    .buttonStyle(.borderedProminent)
                    .disabled(rows.allSatisfy { $0.choice == .keep })
                    .accessibilityIdentifier("tidy.apply")
            }
            .padding(.top, 4)
        }
        .padding(14)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.secondary.opacity(0.25)))
    }

    private var list: some View {
        VStack(spacing: 6) {
            ForEach($rows) { $row in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.task.title).font(.subheadline).lineLimit(1)
                        Text("was " + DayLabel.withTime(row.oldDue)).font(.caption).foregroundStyle(.red)
                    }
                    Spacer(minLength: 8)
                    Menu {
                        Picker("New date", selection: $row.choice) {
                            ForEach(OverdueTidy.choices(repeats: row.task.repeats != nil)) { Text($0.rawValue).tag($0) }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(row.choice.rawValue)
                            Image(systemName: "chevron.up.chevron.down").font(.caption2)
                        }
                        .font(.subheadline)
                        .foregroundStyle(row.choice == .keep ? Color.secondary : Color.accentColor)
                    }
                    .accessibilityIdentifier("tidy.choice.\(row.task.title)")
                    .accessibilityValue(row.choice.rawValue)
                }
            }
        }
    }
}

/// AI plan preview: proposed start times, applied only on tap.
struct PlanCard: View {
    let plan: [(task: OneTask, start: Date)]
    /// Set while a "Plan reminders into free time" grant is active: the card then only offers Apply.
    var grantUntil: Date? = nil
    var onApply: () -> Void
    /// "Always for 7 days": apply now and allow this kind of change by itself (only Today's own planned times).
    var onAlways: () -> Void = {}
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
            Text(grantUntil.map { "Only Today's planned times change; deadlines stay. Automatic until \(DayLabel.text(for: $0))." }
                 ?? "Only Today's planned times change; deadlines stay.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button("Cancel", action: onCancel).buttonStyle(.bordered)
                Spacer(minLength: 0)
                if grantUntil == nil {
                    Button("Always for 7 days", action: onAlways)
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("plan.always")
                }
                Button("Apply", action: onApply)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("plan.apply")
            }
            .lineLimit(1)
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
    var newStart: Date?
    let notes: [String]
    let attendees: Int

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

/// The items a "which one?" question offers. Each is a real item from the calendar or task list; tapping one answers the question.
struct ChoiceBar: View {
    let options: [AskView.ChoiceOption]
    var onPick: (AskView.ChoiceOption) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options) { option in
                    Button { onPick(option) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.title).font(.subheadline).lineLimit(1)
                            if let when = option.when {
                                Text(DayLabel.withTime(when)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(PressScale())
                    .tint(.primary)
                    .accessibilityIdentifier("ask-choice")
                }
            }
            .padding(.horizontal, 2)
        }
    }
}

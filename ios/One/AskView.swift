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
    /// Further items from the same line; each is shown, and confirmed or skipped, one at a time.
    @State private var queue: [Capture] = []
    @State private var thinking = false
    @State private var captureTask: Task<Void, Never>?
    @State private var plan: [(task: OneTask, start: Date)] = []
    @State private var voice = VoiceInput()
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
            .task { focused = true }
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
            if let capture = pending {
                CaptureCard(capture: Binding(get: { pending ?? capture }, set: { pending = $0 }),
                            onAdd: { add(pending ?? capture) }, onCancel: advance)
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
        messages.append(ChatMessage(role: .user, text: text))
        pending = nil
        queue = []
        plan = []
        if isPlanRequest(text) {
            proposePlan()
        } else if isQuestion(text) {
            messages.append(ChatMessage(role: .ai, text: todaySummary))
        } else {
            propose(text)
        }
    }

    /// Apple Intelligence (on device) when it is available, otherwise the rule-based parser. A failure of the
    /// model also falls back to the parser, so a line always produces a preview. Only the preview is set here.
    private func propose(_ text: String) {
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
        pending = captures.first
        queue = Array(captures.dropFirst())
        messages.append(ChatMessage(role: .ai, text: queue.isEmpty
            ? "Here's what I understood. Nothing is added until you confirm."
            : "I found \(captures.count) items. Here's the first; the next one shows after you add or cancel this one. Nothing is added until you confirm."))
    }

    /// Shows the next item from the same line, if any.
    private func advance() {
        pending = queue.isEmpty ? nil : queue.removeFirst()
    }

    private func add(_ capture: Capture) {
        capture.insert(into: context)
        onAdded(capture)
        messages.append(ChatMessage(role: .ai, text: "Added “\(capture.title)” · \(capture.summary)."))
        advance()
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
        toast?.show("Planned \(applied.count) task\(applied.count == 1 ? "" : "s")") {
            withAnimation { for p in applied { p.task.plannedStart = nil } }
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

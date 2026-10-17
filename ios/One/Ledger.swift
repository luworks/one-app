import SwiftUI
import SwiftData

/// The OLD home of the Activity ledger. Since the Activity data store (`ActivityStore`, SQLite) took over, nothing writes
/// `LedgerEntry` any more: existing rows are copied into the store once at launch (`LedgerMigration`) and removed in a later
/// launch when the copy was verified. The model stays in the schema, unused, so existing installs migrate (like `Habit`).
/// Pure parts (actors, formatting, undo rules) are in `LedgerLogic.swift`, the item type and the import in `ActivityLedger.swift`.
@Model
final class LedgerEntry {
    #Index<LedgerEntry>([\.date], [\.actor, \.date])

    var id: UUID
    var date: Date
    /// `LedgerActor.raw`: you / ai / siri / shortcut / share / agent:<name>.
    var actor: String
    /// `LedgerChannel.rawValue`.
    var channel: String
    /// `LedgerAction.rawValue`.
    var action: String
    /// "task", "event", "alarm" or "grant".
    var itemKind: String
    /// The reminder's `PersistentIdentifier` (JSON), filled in once it is saved. nil for events, alarms and deletes.
    var itemRef: String?
    var title: String
    var before: String
    var after: String
    /// `LedgerApproval.rawValue`.
    var approval: String
    /// Planned time or deadline before and after, for Undo.
    var beforeDate: Date?
    var afterDate: Date?
    /// A deleted reminder (`TaskSnapshot`, JSON), so Activity can put it back.
    var snapshot: Data?
    /// For an `undone` entry: the entry it undid.
    var undoOf: UUID?

    init(date: Date = .now, actor: LedgerActor, channel: LedgerChannel, action: LedgerAction, itemKind: String, title: String,
         before: String = "", after: String = "", approval: LedgerApproval) {
        self.id = UUID()
        self.date = date
        self.actor = actor.raw
        self.channel = channel.rawValue
        self.action = action.rawValue
        self.itemKind = itemKind
        self.title = title
        self.before = before
        self.after = after
        self.approval = approval.rawValue
    }
}

extension LedgerEntry {
    var legacyRow: LegacyLedgerRow {
        LegacyLedgerRow(id: id, date: date, actor: actor, channel: channel, action: action, itemKind: itemKind, itemRef: itemRef,
                        title: title, before: before, after: after, approval: approval, beforeDate: beforeDate, afterDate: afterDate,
                        snapshot: snapshot, undoOf: undoOf)
    }
}

/// A grant the user gave with "Always for 7 days" (see `AutonomyPolicy`). Revoking keeps the row (with `revoked`) for the record.
@Model
final class AIGrant {
    var id: UUID
    /// `GrantScope.rawValue`.
    var scope: String
    var granted: Date
    var expires: Date
    var revoked: Date?

    init(scope: GrantScope, granted: Date = .now) {
        self.id = UUID()
        self.scope = scope.rawValue
        self.granted = granted
        self.expires = Grants.expiry(from: granted)
    }

    var info: GrantInfo? {
        GrantScope(rawValue: scope).map { GrantInfo(scope: $0, granted: granted, expires: expires, revoked: revoked) }
    }
}

/// Records changes in the ledger. Called from the write paths (TaskActions, Ask AI, App Intents, Share, sync).
/// Items are held a moment and written together, after the reminders they point at have their final ids. The ledger lives in the
/// Activity store (`ActivityCenter.shared.store`); the reads (Activity screen, Undo, the policy's look-back) are SQL queries.
@MainActor
enum Ledger {
    private struct Pending {
        var item: LedgerItem
        var snapshot: Data?
        var task: OneTask?
    }

    private static var pending: [Pending] = []
    private static var flushScheduled = false

    @discardableResult
    static func record(_ action: LedgerAction, task: OneTask? = nil, kind: String = "task", title: String,
                       before: String = "", after: String = "", beforeDate: Date? = nil, afterDate: Date? = nil,
                       actor: LedgerActor = .you, channel: LedgerChannel = .app, approval: LedgerApproval = .userMade,
                       snapshot: TaskSnapshot? = nil, undoOf: UUID? = nil, context: ModelContext) -> LedgerItem {
        var item = LedgerItem(actor: actor, channel: channel, action: action, itemKind: kind, title: title,
                              before: before, after: after, approval: approval)
        item.beforeDate = beforeDate
        item.afterDate = afterDate
        item.undoOf = undoOf
        let data = snapshot.flatMap { try? JSONEncoder().encode($0) }
        item.hasSnapshot = data != nil
        pending.append(Pending(item: item, snapshot: data, task: task))
        scheduleFlush(context)
        return item
    }

    /// Records that `entry` was undone (by you, unless said otherwise).
    @discardableResult
    static func recordUndo(of entry: LedgerItem, task: OneTask? = nil, actor: LedgerActor = .you, channel: LedgerChannel = .app,
                           context: ModelContext) -> LedgerItem {
        record(.undone, task: task, kind: entry.itemKind, title: entry.title, before: entry.after, after: entry.before,
               actor: actor, channel: channel, approval: .userMade, undoOf: entry.id, context: context)
    }

    private static func scheduleFlush(_ context: ModelContext) {
        guard !flushScheduled else { return }
        flushScheduled = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            flush(context)
        }
    }

    /// Saves what is waiting: the reminders first (a new one's id becomes final on save), then the items with their ids, into
    /// the store. After this the Activity screen and the policy queries see everything recorded so far.
    static func flush(_ context: ModelContext) {
        flushScheduled = false
        if !pending.isEmpty {
            if pending.contains(where: { $0.task != nil }) { try? context.save() }
            let recorder = ActivityCenter.shared.recorder
            for var p in pending {
                if let task = p.task, !task.isDeleted, task.modelContext != nil { p.item.itemRef = ref(task.persistentModelID) }
                recorder.record(p.item.event(snapshot: p.snapshot))
            }
            pending = []
            recorder.flush()
        }
        try? context.save()
    }

    static func ref(_ id: PersistentIdentifier) -> String? {
        (try? JSONEncoder().encode(id)).flatMap { String(data: $0, encoding: .utf8) }
    }

    /// The reminder an entry points at, if it still exists.
    static func task(for entry: LedgerItem, in context: ModelContext) -> OneTask? {
        guard let ref = entry.itemRef, let data = ref.data(using: .utf8),
              let id = try? JSONDecoder().decode(PersistentIdentifier.self, from: data) else { return nil }
        var d = FetchDescriptor<OneTask>(predicate: #Predicate { $0.persistentModelID == id })
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first
    }

    /// Drops expired activity (the changes ledger by the Settings choice: 90 days, 1 year or forever) and, in a launch after the
    /// old ledger was copied and verified, the old SwiftData rows. Called at launch.
    static func prune(_ context: ModelContext, now: Date = .now) {
        let center = ActivityCenter.shared
        guard let store = center.store else { return }
        _ = try? store.prune(retention: center.settings.retention, now: now)
        if LedgerImport.mayRemoveLegacy(store, session: center.recorder.session) {
            try? context.delete(model: LedgerEntry.self)
            try? context.save()
            try? store.setMeta(LedgerImport.legacyRemovedKey, "1")
        }
    }

    /// Changes recorded (tier 1).
    static func count() -> Int {
        ActivityCenter.shared.recorder.flush()
        return (try? ActivityCenter.shared.store?.count(ActivityQuery(tiers: [.changes]))) ?? 0
    }

    /// Clears the changes ledger (the old SwiftData rows too). Everything else: `ActivityCenter.clear`.
    static func clear(_ context: ModelContext) {
        pending = []
        ActivityCenter.clear(tiers: [.changes], context: context)
    }

    /// Clears every kind of activity and the old rows; used by Delete All Data.
    static func clearAll(_ context: ModelContext) {
        pending = []
        ActivityCenter.clear(tiers: nil, context: context)
    }

    /// Reminders the AI changed within the last 24 hours (applied or undone), and reminders whose planned time the
    /// user set or cleared themselves (within `ActivityWindows.userChoseDays`, not the ledger's retention): the policy asks
    /// before changing them again. Two indexed queries on the store.
    static func protectedRefs(_ context: ModelContext, now: Date = .now) -> (aiRecent: Set<String>, userChose: Set<String>) {
        flush(context)
        guard let store = ActivityCenter.shared.store else { return ([], []) }
        let since = ActivityClock.ms(now.addingTimeInterval(-AutonomyPolicy.recentWindow))
        let cutoff = ActivityWindows.cutoffMs(days: ActivityWindows.userChoseDays, now: now)
        let timeKinds = [LedgerAction.planned, .moved, .unscheduled].map { ActivityKind.changePrefix + $0.rawValue }
        let ai = (try? store.subjectRefs(actor: LedgerActor.todayAI.raw, sinceMs: since)) ?? []
        let mine = (try? store.subjectRefs(actor: LedgerActor.you.raw, kinds: timeKinds, sinceMs: cutoff)) ?? []
        return (ai, mine)
    }

    static func snapshot(of t: OneTask) -> TaskSnapshot {
        TaskSnapshot(title: t.title, note: t.note, isDone: t.isDone, doneAt: t.doneAt, plannedStart: t.plannedStart,
                     durationMinutes: t.durationMinutes, due: t.due, createdAt: t.createdAt,
                     reminderOffsetMinutes: t.reminderOffsetMinutes, listName: t.listName, tags: t.tags, flagged: t.flagged,
                     repeatRule: t.repeatRule, checklist: t.checklist, ringsAsAlarm: t.ringsAsAlarm)
    }

    static func task(from s: TaskSnapshot) -> OneTask {
        let t = OneTask(title: s.title, note: s.note, plannedStart: s.plannedStart, durationMinutes: s.durationMinutes, due: s.due)
        t.isDone = s.isDone
        t.doneAt = s.doneAt
        // A new creation date, so it is written to Apple Reminders again when that is connected (as TaskActions' Undo does).
        t.createdAt = .now
        t.reminderOffsetMinutes = s.reminderOffsetMinutes
        t.listName = s.listName
        t.tags = s.tags
        t.flagged = s.flagged
        t.repeatRule = s.repeatRule
        t.checklist = s.checklist
        t.ringsAsAlarm = s.ringsAsAlarm
        return t
    }

    /// Undo from Activity: puts the reminder back as it was before this entry, and records the undo.
    /// False when it can't (the reminder is gone, or it changed again since).
    @discardableResult
    static func undo(_ entry: LedgerItem, context: ModelContext) -> Bool {
        flush(context)
        let action = entry.actionValue
        if action == .deleted {
            guard let stored = try? ActivityCenter.shared.store?.snapshot(uid: entry.id.uuidString),
                  let s = try? JSONDecoder().decode(TaskSnapshot.self, from: stored) else { return false }
            let t = task(from: s)
            context.insert(t)
            try? context.save()
            recordUndo(of: entry, task: t, context: context)
            flush(context)
            return true
        }
        guard let t = task(for: entry, in: context) else { return false }
        switch action {
        case .completed:
            guard t.isDone else { return false }
            t.toggleDone()
        case .reopened:
            guard !t.isDone else { return false }
            t.toggleDone()
        case .planned, .moved, .unscheduled:
            t.plannedStart = entry.beforeDate
        case .redated:
            t.due = entry.beforeDate
        case .created:
            RemindersSync.shared.noteDeleted(reminder: t.externalID)
            context.delete(t)
        case .deleted, .undone, .granted, .revoked:
            return false
        }
        recordUndo(of: entry, task: action == .created ? nil : t, context: context)
        flush(context)
        return true
    }
}

/// The one-time copy of the old SwiftData ledger into the Activity store, at launch (`LedgerImport` does the work and is tested).
/// Nothing is deleted here; the old rows go in a later launch (`Ledger.prune`) once the copy was verified.
@MainActor
enum LedgerMigration {
    static func run(context: ModelContext) {
        let center = ActivityCenter.shared
        guard let store = center.store, !LedgerImport.isMigrated(store) else { return }
        let total = (try? context.fetchCount(FetchDescriptor<LedgerEntry>())) ?? 0
        let outcome = try? LedgerImport.run(into: store, total: total, session: center.recorder.session) { offset, limit in
            var d = FetchDescriptor<LedgerEntry>(sortBy: [SortDescriptor(\.date), SortDescriptor(\.id)])
            d.fetchOffset = offset
            d.fetchLimit = limit
            return ((try? context.fetch(d)) ?? []).map(\.legacyRow)
        }
        if let outcome, !outcome.verified { print("LEDGER import not verified: \(outcome)") }
    }

    #if DEBUG
    /// UI tests only (`-uiTesting -uiTestingLegacyLedgerRows <n>`): writes n old-style `LedgerEntry` rows, as an install from
    /// before the Activity store would have them, so the real import can be tested end to end. Only when there are none yet.
    static func seedLegacyForTests(context: ModelContext) {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-uiTesting"), let i = args.firstIndex(of: "-uiTestingLegacyLedgerRows"), i + 1 < args.count,
              let n = Int(args[i + 1]), n >= 5,
              ((try? context.fetchCount(FetchDescriptor<LedgerEntry>())) ?? 0) == 0 else { return }
        func entry(_ minutesAgo: Int, _ actor: LedgerActor, _ action: LedgerAction, _ title: String, approval: LedgerApproval = .userMade) -> LedgerEntry {
            LedgerEntry(date: Date.now.addingTimeInterval(-Double(minutesAgo) * 60), actor: actor, channel: .app, action: action,
                        itemKind: "task", title: title, before: "Not planned", after: "Today 10:00", approval: approval)
        }
        let plan = entry(1, .todayAI, .planned, "Legacy plan", approval: .asked)
        let deleted = entry(2, .you, .deleted, "Legacy deleted")
        deleted.snapshot = try? JSONEncoder().encode(TaskSnapshot(title: "Legacy deleted"))
        let done = entry(3, .you, .completed, "Legacy done")
        let undo = entry(4, .you, .undone, "Legacy done")
        undo.undoOf = done.id
        for e in [plan, deleted, done, undo] { context.insert(e) }
        for k in 4..<n { context.insert(entry(5 + k, .siri, .created, "Legacy filler \(k)")) }
        try? context.save()
    }
    #endif
}

/// Grants in the store (SwiftData: in memory under `-uiTesting`, so a test's grant never leaks into the next run).
@MainActor
enum GrantStore {
    static func all(_ context: ModelContext) -> [AIGrant] {
        (try? context.fetch(FetchDescriptor<AIGrant>(sortBy: [SortDescriptor(\.expires, order: .reverse)]))) ?? []
    }

    static func infos(_ context: ModelContext) -> [GrantInfo] { all(context).compactMap(\.info) }

    static func active(_ scope: GrantScope, context: ModelContext, now: Date = .now) -> AIGrant? {
        all(context).first { $0.info.map { $0.scope == scope && $0.isActive(at: now) } ?? false }
    }

    @discardableResult
    static func grant(_ scope: GrantScope, context: ModelContext) -> AIGrant {
        let g = AIGrant(scope: scope)
        context.insert(g)
        Ledger.record(.granted, kind: "grant", title: scope.title, after: "Until " + DayLabel.text(for: g.expires),
                      channel: .ask, context: context)
        return g
    }

    static func revoke(_ g: AIGrant, context: ModelContext) {
        g.revoked = .now
        Ledger.record(.revoked, kind: "grant", title: GrantScope(rawValue: g.scope)?.title ?? g.scope, context: context)
    }
}

/// Under a "Plan reminders into free time" grant: when the app becomes active, reminders due today without a time get
/// the free-gap time Today already suggests for them (`DaySchedule`), each one checked by `AutonomyPolicy`. One toast with
/// Undo, one Activity entry per reminder. Planned time only: deadlines, events and Apple Reminders are never touched.
@MainActor
enum AutoPlan {
    /// `now` places the day (Today's clock, pinned in UI tests); grants and the 24-hour rule always use the real time.
    static func run(context: ModelContext, toast: UndoToast, now: Date = TodayClock.now) {
        guard GrantStore.active(.planFreeTime, context: context, now: .now) != nil else { return }
        // Nothing applies by itself without an Activity entry and an Undo: when changes are not being recorded (Settings →
        // Activity data), the plan waits for a tap like any other card.
        guard ActivityCenter.recordsChanges else { return }
        // Fetched here, not taken from a view's @Query, which may not have caught up yet at launch.
        let tasks = (try? context.fetch(FetchDescriptor<OneTask>(predicate: #Predicate { !$0.isDone }))) ?? []
        let events = (try? context.fetch(FetchDescriptor<OneEvent>())) ?? []
        let cal = Calendar.current
        let day = cal.startOfDay(for: now)
        // The same busy time and order as Today's own suggestions (DayAgenda), so what lands is what was shown.
        var busy: [DateInterval] = []
        for e in events where !e.isAllDay {
            for start in e.occurs(on: day) { busy.append(DateInterval(start: start, duration: e.duration)) }
        }
        let external = CalendarSync.shared.events(on: day, excluding: Set(events.compactMap(\.externalID)))
        busy += external.filter { !$0.isAllDay }.map { DateInterval(start: $0.start, end: max($0.start, $0.end)) }
        var untimed: [OneTask] = []
        for t in tasks where !t.isDone && !t.isOverdue {
            if let s = t.plannedStart {
                if cal.isDate(s, inSameDayAs: day) { busy.append(DateInterval(start: s, duration: TimeInterval(t.durationMinutes * 60))) }
            } else if let due = t.due, cal.isDate(due, inSameDayAs: day) {
                if t.dueHasTime { busy.append(DateInterval(start: due, duration: TimeInterval(t.durationMinutes * 60))) }
                else { untimed.append(t) }
            }
        }
        guard !untimed.isEmpty else { return }
        untimed.sort { ($0.flagged ? 0 : 1, $0.createdAt) < ($1.flagged ? 0 : 1, $1.createdAt) }
        let starts = DaySchedule.suggestedStarts(minutes: untimed.map(\.durationMinutes), busy: busy, day: day, now: now)
        let grants = GrantStore.infos(context)
        let protected = Ledger.protectedRefs(context, now: .now)
        var applied: [(task: OneTask, start: Date, entry: LedgerItem)] = []
        for (task, start) in zip(untimed, starts) {
            guard let start else { continue }
            let ref = Ledger.ref(task.persistentModelID)
            let change = ProposedChange(target: .reminder, operation: .setPlannedTime, isOverdue: task.isOverdue, isDone: task.isDone,
                                        ringsAsAlarm: task.ringsAsAlarm,
                                        aiChangedRecently: ref.map(protected.aiRecent.contains) ?? false,
                                        userChoseTime: ref.map(protected.userChose.contains) ?? false)
            guard AutonomyPolicy.decide(change, grants: grants, now: .now) == .auto else { continue }
            task.plannedStart = start
            let entry = Ledger.record(.planned, task: task, title: task.title, before: LedgerFormat.time(nil),
                                      after: LedgerFormat.time(start), beforeDate: nil, afterDate: start,
                                      actor: .todayAI, channel: .automatic, approval: .autoUnderGrant, context: context)
            applied.append((task, start, entry))
        }
        guard !applied.isEmpty else { return }
        try? context.save()
        toast.show(LedgerFormat.autoPlanned(applied.count)) {
            for a in applied where a.task.plannedStart == a.start {
                a.task.plannedStart = nil
                Ledger.recordUndo(of: a.entry, context: context)
            }
            try? context.save()
        }
    }
}

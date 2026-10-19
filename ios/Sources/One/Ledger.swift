#if os(iOS)
import TodayCore
import TodayShared
import TodayData
import TodayPlatform
import SwiftUI
import SwiftData

/// Records changes in the ledger. Called from the write paths (TaskActions, Ask AI, App Intents, Share, sync).
/// Items are held a moment and written together, after the reminders they point at have their final ids. The ledger lives in the
/// Activity store (`activity.store`); the reads (Activity screen, Undo, the policy's look-back) are SQL queries.
@MainActor
package final class Ledger {
    package let activity: ActivityCenter
    private let reminders: any ReminderService
    private let runtime: PlannerRuntime
    private var flushTask: Task<Void, Never>?
    private var pendingContext: ModelContext?
    private var disposed = false
    private var undoneIDs: Set<UUID> = []

    package init(activity: ActivityCenter, reminders: any ReminderService, runtime: PlannerRuntime) {
        self.activity = activity; self.reminders = reminders; self.runtime = runtime
    }

    package func timeLabel(_ date: Date?, none: String = "Not planned") -> String {
        date.map { plannerDayLabel($0, runtime: runtime) } ?? none
    }

    package func dayLabel(_ date: Date) -> String {
        plannerDayLabel(date, runtime: runtime, includeTime: false)
    }

    package func dispose() {
        if let context = pendingContext { flush(context) }
        flushTask?.cancel(); flushTask = nil; pendingContext = nil
        disposed = true
    }

    private struct Pending {
        var item: LedgerItem
        var snapshot: Data?
        var task: OneTask?
    }

    private var pending: [Pending] = []
    private var flushScheduled = false

    @discardableResult
    package func record(_ action: LedgerAction, task: OneTask? = nil, kind: String = "task", title: String,
                       before: String = "", after: String = "", beforeDate: Date? = nil, afterDate: Date? = nil,
                       actor: LedgerActor = .you, channel: LedgerChannel = .app, approval: LedgerApproval = .userMade,
                       snapshot: TaskSnapshot? = nil, undoOf: UUID? = nil, context: ModelContext) -> LedgerItem {
        var item = LedgerItem(actor: actor, channel: channel, action: action, itemKind: kind, title: title,
                              before: before, after: after, approval: approval)
        item.id = runtime.nextID()
        item.date = runtime.now()
        item.beforeDate = beforeDate
        item.afterDate = afterDate
        item.undoOf = undoOf
        let data = snapshot.flatMap { try? JSONEncoder().encode($0) }
        item.hasSnapshot = data != nil
        guard !disposed else { return item }
        pending.append(Pending(item: item, snapshot: data, task: task))
        scheduleFlush(context)
        return item
    }

    /// Records that `entry` was undone (by you, unless said otherwise).
    @discardableResult
    package func recordUndo(of entry: LedgerItem, task: OneTask? = nil, actor: LedgerActor = .you, channel: LedgerChannel = .app,
                           context: ModelContext) -> LedgerItem {
        undoneIDs.insert(entry.id)
        return record(.undone, task: task, kind: entry.itemKind, title: entry.title, before: entry.after, after: entry.before,
               actor: actor, channel: channel, approval: .userMade, undoOf: entry.id, context: context)
    }

    private func scheduleFlush(_ context: ModelContext) {
        guard !disposed, !flushScheduled else { return }
        pendingContext = context
        flushScheduled = true
        flushTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            guard let self, !self.disposed, !Task.isCancelled else { return }
            self.flush(context)
        }
    }

    /// Saves what is waiting: the reminders first (a new one's id becomes final on save), then the items with their ids, into
    /// the store. After this the Activity screen and the policy queries see everything recorded so far.
    package func flush(_ context: ModelContext) {
        flushTask?.cancel(); flushTask = nil; pendingContext = nil
        flushScheduled = false
        if !pending.isEmpty {
            if pending.contains(where: { $0.task != nil }) {
                do { try context.save() } catch { pendingContext = context; return }
            }
            let recorder = activity.recorder
            for var p in pending {
                if let task = p.task, !task.isDeleted, task.modelContext != nil { p.item.itemRef = Self.ref(task.persistentModelID) }
                recorder.record(p.item.event(snapshot: p.snapshot, calendar: runtime.calendar))
            }
            pending = []
            recorder.flush()
        }
        try? context.save()
    }

    private func cancelPendingFlush() {
        flushTask?.cancel(); flushTask = nil
        pendingContext = nil; flushScheduled = false
    }

    package static func ref(_ id: PersistentIdentifier) -> String? {
        (try? JSONEncoder().encode(id)).flatMap { String(data: $0, encoding: .utf8) }
    }

    /// The reminder an entry points at, if it still exists.
    package func task(for entry: LedgerItem, in context: ModelContext) -> OneTask? {
        guard let ref = entry.itemRef, let data = ref.data(using: .utf8),
              let id = try? JSONDecoder().decode(PersistentIdentifier.self, from: data) else { return nil }
        var d = FetchDescriptor<OneTask>(predicate: #Predicate { $0.persistentModelID == id })
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first
    }

    /// Drops expired activity (the changes ledger by the Settings choice: 90 days, 1 year or forever) and, in a launch after the
    /// old ledger was copied and verified, the old SwiftData rows. Called at launch.
    package func prune(_ context: ModelContext, now: Date) {
        let center = activity
        guard let store = center.store else { return }
        _ = try? store.prune(retention: center.settings.retention, now: now)
        if LedgerImport.mayRemoveLegacy(store, session: center.recorder.session) {
            try? context.delete(model: LedgerEntry.self)
            try? context.save()
            try? store.setMeta(LedgerImport.legacyRemovedKey, "1")
        }
    }

    /// Changes recorded (tier 1).
    package func count() -> Int {
        activity.recorder.flush()
        return (try? activity.store?.count(ActivityQuery(tiers: [.changes]))) ?? 0
    }

    /// Clears the changes ledger (the old SwiftData rows too). Everything else: `activity.clear`.
    package func clear(_ context: ModelContext) {
        cancelPendingFlush()
        pending = []
        activity.clear(tiers: [.changes], context: context)
    }

    /// Clears every kind of activity and the old rows; used by Delete All Data.
    package func clearAll(_ context: ModelContext) {
        cancelPendingFlush()
        pending = []
        activity.clear(tiers: nil, context: context)
    }

    /// Reminders the AI changed within the last 24 hours (applied or undone), and reminders whose planned time the
    /// user set or cleared themselves (within `ActivityWindows.userChoseDays`, not the ledger's retention): the policy asks
    /// before changing them again. Two indexed queries on the store.
    package func protectedRefs(_ context: ModelContext, now: Date) -> (aiRecent: Set<String>, userChose: Set<String>) {
        flush(context)
        guard let store = activity.store else { return ([], []) }
        let since = ActivityClock.ms(now.addingTimeInterval(-AutonomyPolicy.recentWindow))
        let cutoff = ActivityWindows.cutoffMs(days: ActivityWindows.userChoseDays, now: now, calendar: runtime.calendar)
        let timeKinds = [LedgerAction.planned, .moved, .unscheduled].map { ActivityKind.changePrefix + $0.rawValue }
        let ai = (try? store.subjectRefs(actor: LedgerActor.todayAI.raw, sinceMs: since)) ?? []
        let mine = (try? store.subjectRefs(actor: LedgerActor.you.raw, kinds: timeKinds, sinceMs: cutoff)) ?? []
        return (ai, mine)
    }

    package static func snapshot(of t: OneTask) -> TaskSnapshot {
        TaskSnapshot(title: t.title, note: t.note, isDone: t.isDone, doneAt: t.doneAt, plannedStart: t.plannedStart,
                     durationMinutes: t.durationMinutes, due: t.due, createdAt: t.createdAt,
                     reminderOffsetMinutes: t.reminderOffsetMinutes, listName: t.listName, tags: t.tags, flagged: t.flagged,
                     repeatRule: t.repeatRule, checklist: t.checklist, ringsAsAlarm: t.ringsAsAlarm)
    }

    package func task(from s: TaskSnapshot) -> OneTask {
        let t = OneTask(title: s.title, note: s.note, plannedStart: s.plannedStart, durationMinutes: s.durationMinutes, due: s.due)
        t.isDone = s.isDone
        t.doneAt = s.doneAt
        // A new creation date, so it is written to Apple Reminders again when that is connected (as TaskActions' Undo does).
        t.createdAt = runtime.now()
        t.reminderOffsetMinutes = s.reminderOffsetMinutes
        t.listName = s.listName
        t.tags = s.tags
        t.flagged = s.flagged
        t.repeatRule = s.repeatRule
        t.checklist = s.checklist
        t.ringsAsAlarm = s.ringsAsAlarm
        return t
    }

    @discardableResult
    package func removeCreatedTask(_ task: OneTask, context: ModelContext, channel: LedgerChannel) -> Bool {
        guard !task.isDeleted, task.modelContext != nil else { return true }
        reminders.noteDeleted(reminder: task.externalID)
        let title = task.title
        context.delete(task)
        do { try context.save() } catch { return false }
        record(.deleted, title: title, channel: channel, context: context)
        return true
    }

    /// Undo from Activity: puts the reminder back as it was before this entry, and records the undo.
    /// False when it can't (the reminder is gone, or it changed again since).
    @discardableResult
    package func undo(_ entry: LedgerItem, context: ModelContext) -> Bool {
        flush(context)
        guard !disposed, !undoneIDs.contains(entry.id) else { return false }
        if let undone = try? activity.store?.undone(among: [entry.id.uuidString]),
           undone.contains(entry.id.uuidString) { return false }
        let action = entry.actionValue
        if action == .deleted {
            guard let stored = try? activity.store?.snapshot(uid: entry.id.uuidString),
                  let s = try? JSONDecoder().decode(TaskSnapshot.self, from: stored) else { return false }
            let t = task(from: s)
            context.insert(t)
            do { try context.save() } catch { context.delete(t); return false }
            recordUndo(of: entry, task: t, context: context)
            flush(context)
            return true
        }
        guard let t = task(for: entry, in: context) else { return false }
        let oldDoneAt = t.doneAt
        switch action {
        case .completed:
            guard t.isDone else { return false }
            do { _ = try reminders.commitCompletion(t, done: !t.isDone) } catch { return false }
            t.isDone.toggle()
            t.doneAt = t.isDone ? runtime.now() : nil
            do { try context.save() } catch {
                if t.externalID != nil { reminders.scheduleReconcile(after: .milliseconds(50)) }
                else { t.isDone.toggle(); t.doneAt = oldDoneAt }
                return false
            }
            reminders.didPersistCompletion(t)
        case .reopened:
            guard !t.isDone else { return false }
            do { _ = try reminders.commitCompletion(t, done: !t.isDone) } catch { return false }
            t.isDone.toggle()
            t.doneAt = t.isDone ? runtime.now() : nil
            do { try context.save() } catch {
                if t.externalID != nil { reminders.scheduleReconcile(after: .milliseconds(50)) }
                else { t.isDone.toggle(); t.doneAt = oldDoneAt }
                return false
            }
            reminders.didPersistCompletion(t)
        case .planned, .moved, .unscheduled:
            t.plannedStart = entry.beforeDate
        case .redated:
            t.due = entry.beforeDate
        case .renamed:
            guard t.title == entry.after else { return false }
            t.title = entry.before
            try? context.save()
            reminders.scheduleReconcile()
        case .created:
            reminders.noteDeleted(reminder: t.externalID)
            context.delete(t)
        case .deleted, .undone, .granted, .revoked:
            return false
        }
        do { try context.save() } catch {
            reminders.scheduleReconcile(after: .milliseconds(50))
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
package enum LedgerMigration {
    package static func run(context: ModelContext, ledger: Ledger) {
        let center = ledger.activity
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
    package static func seedLegacyForTests(context: ModelContext, arguments: [String], runtime: PlannerRuntime) {
        let args = arguments
        guard args.contains("-uiTesting"), let i = args.firstIndex(of: "-uiTestingLegacyLedgerRows"), i + 1 < args.count,
              let n = Int(args[i + 1]), n >= 5,
              ((try? context.fetchCount(FetchDescriptor<LedgerEntry>())) ?? 0) == 0 else { return }
        func entry(_ minutesAgo: Int, _ actor: LedgerActor, _ action: LedgerAction, _ title: String, approval: LedgerApproval = .userMade) -> LedgerEntry {
            LedgerEntry(date: runtime.now().addingTimeInterval(-Double(minutesAgo) * 60), actor: actor, channel: .app, action: action,
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
package enum GrantStore {
    package static func all(_ context: ModelContext) -> [AIGrant] {
        (try? context.fetch(FetchDescriptor<AIGrant>(sortBy: [SortDescriptor(\.expires, order: .reverse)]))) ?? []
    }

    package static func infos(_ context: ModelContext) -> [GrantInfo] { all(context).compactMap(\.info) }

    package static func active(_ scope: GrantScope, context: ModelContext, now: Date) -> AIGrant? {
        all(context).first { $0.info.map { $0.scope == scope && $0.isActive(at: now) } ?? false }
    }

    /// Settings grants the same scope as a plan card. Turning off revokes every active copy of that scope.
    package static func setEnabled(_ enabled: Bool, scope: GrantScope, context: ModelContext, ledger: Ledger, runtime: PlannerRuntime) throws {
        let now = runtime.now()
        let changed: [AIGrant]
        if enabled {
            guard active(scope, context: context, now: now) == nil else { return }
            let g = AIGrant(scope: scope, granted: now)
            g.id = runtime.nextID(); g.expires = Grants.expiry(from: now, calendar: runtime.calendar)
            context.insert(g)
            changed = [g]
        } else {
            changed = all(context).filter { $0.info.map { $0.scope == scope && $0.isActive(at: now) } ?? false }
            for g in changed { g.revoked = now }
        }
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        // Publish successful grant changes only after persistence; rollback must not leave a success in Activity.
        for g in changed { record(g, granted: enabled, context: context, ledger: ledger) }
    }

    private static func record(_ g: AIGrant, granted: Bool, context: ModelContext, ledger: Ledger) {
        let title = GrantScope(rawValue: g.scope)?.title ?? g.scope
        if granted {
            ledger.record(.granted, kind: "grant", title: title, after: "Until " + ledger.dayLabel(g.expires),
                          channel: .ask, context: context)
        } else {
            ledger.record(.revoked, kind: "grant", title: title, context: context)
        }
    }

    @discardableResult
    package static func grant(_ scope: GrantScope, context: ModelContext, ledger: Ledger, runtime: PlannerRuntime) -> AIGrant {
        let g = AIGrant(scope: scope, granted: runtime.now())
        g.id = runtime.nextID(); g.expires = Grants.expiry(from: g.granted, calendar: runtime.calendar)
        context.insert(g)
        record(g, granted: true, context: context, ledger: ledger)
        return g
    }

    package static func revoke(_ g: AIGrant, context: ModelContext, ledger: Ledger, runtime: PlannerRuntime) {
        g.revoked = runtime.now()
        record(g, granted: false, context: context, ledger: ledger)
    }
}

/// Under a "Plan reminders into free time" grant: when the app becomes active, reminders due today without a time get
/// the free-gap time Today already suggests for them (`DaySchedule`), each one checked by `AutonomyPolicy`. One toast with
/// Undo, one Activity entry per reminder. Planned time only: deadlines, events and Apple Reminders are never touched.
@MainActor
package enum AutoPlan {
    /// The injected session clock supplies both the plan day and policy look-back windows.
    package static func run(context: ModelContext, toast: UndoToast, calendar: any CalendarService, ledger: Ledger, runtime: PlannerRuntime) {
        let now = runtime.now()
        guard GrantStore.active(.planFreeTime, context: context, now: now) != nil else { return }
        // Nothing applies by itself without an Activity entry and an Undo: when changes are not being recorded (Settings →
        // Activity data), the plan waits for a tap like any other card.
        guard ledger.activity.recordsChanges else { return }
        // Fetched here, not taken from a view's @Query, which may not have caught up yet at launch.
        let tasks = (try? context.fetch(FetchDescriptor<OneTask>(predicate: #Predicate { !$0.isDone }))) ?? []
        let events = (try? context.fetch(FetchDescriptor<OneEvent>())) ?? []
        let cal = runtime.calendar
        let day = cal.startOfDay(for: now)
        // The same busy time and order as Today's own suggestions (DayAgenda), so what lands is what was shown.
        var busy: [DateInterval] = []
        for e in events where !e.isAllDay {
            for start in Recurrence.occurrences(start: e.start, duration: e.duration, rule: e.repeats, in: DateInterval(start: day, end: cal.date(byAdding: .day, value: 1, to: day) ?? day), calendar: cal) { busy.append(DateInterval(start: start, duration: e.duration)) }
        }
        let external = calendar.events(on: day, excluding: Set(events.compactMap(\.externalID)))
        busy += external.filter { !$0.isAllDay }.map { DateInterval(start: $0.start, end: max($0.start, $0.end)) }
        var untimed: [OneTask] = []
        for t in tasks where !t.isDone && !(t.due.map { $0 < day } ?? false) {
            if let s = t.plannedStart {
                if cal.isDate(s, inSameDayAs: day) { busy.append(DateInterval(start: s, duration: TimeInterval(t.durationMinutes * 60))) }
            } else if let due = t.due, cal.isDate(due, inSameDayAs: day) {
                if cal.dateComponents([.hour, .minute], from: due) != DateComponents(hour: 0, minute: 0) { busy.append(DateInterval(start: due, duration: TimeInterval(t.durationMinutes * 60))) }
                else { untimed.append(t) }
            }
        }
        guard !untimed.isEmpty else { return }
        untimed.sort { ($0.flagged ? 0 : 1, $0.createdAt) < ($1.flagged ? 0 : 1, $1.createdAt) }
        let starts = DaySchedule.suggestedStarts(minutes: untimed.map(\.durationMinutes), busy: busy, day: day, now: now, calendar: cal)
        let grants = GrantStore.infos(context)
        let protected = ledger.protectedRefs(context, now: now)
        var applied: [(task: OneTask, start: Date, entry: LedgerItem)] = []
        for (task, start) in zip(untimed, starts) {
            guard let start else { continue }
            let ref = Ledger.ref(task.persistentModelID)
            let change = ProposedChange(target: .reminder, operation: .setPlannedTime, isOverdue: task.due.map { $0 < day } ?? false, isDone: task.isDone,
                                        ringsAsAlarm: task.ringsAsAlarm,
                                        aiChangedRecently: ref.map(protected.aiRecent.contains) ?? false,
                                        userChoseTime: ref.map(protected.userChose.contains) ?? false)
            guard AutonomyPolicy.decide(change, grants: grants, now: now) == .auto else { continue }
            task.plannedStart = start
            let entry = ledger.record(.planned, task: task, title: task.title, before: ledger.timeLabel(nil),
                                      after: ledger.timeLabel(start), beforeDate: nil, afterDate: start,
                                      actor: .todayAI, channel: .automatic, approval: .autoUnderGrant, context: context)
            applied.append((task, start, entry))
        }
        guard !applied.isEmpty else { return }
        try? context.save()
        toast.show(LedgerFormat.autoPlanned(applied.count)) {
            for a in applied where !a.task.isDeleted && a.task.modelContext != nil && a.task.plannedStart == a.start {
                a.task.plannedStart = nil
                ledger.recordUndo(of: a.entry, context: context)
            }
            try? context.save()
        }
    }
}
#endif

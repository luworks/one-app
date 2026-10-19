#if os(iOS)
import TodayCore
import TodayShared
import TodayData
import TodayPlatform
import EventKit
import SwiftData
import SwiftUI
import os

/// Two-way sync between the app's reminders and lists (SwiftData) and Apple Reminders (EventKit).
///
/// Apple wins: when a reminder or list changed on both sides since the last sync, the Apple version is kept.
/// Rules that keep your real data safe:
/// - Nothing is written to Apple Reminders until the user connects (and allows access).
/// - Reminders and lists that existed locally before connecting are linked to an Apple one with the same title and
///   list when there is one, and otherwise stay local. Only items created after connecting are uploaded.
/// - A sync pass that would delete more than `maxRemoteDeletes` Apple items is aborted (a local data reset must never
///   empty Apple Reminders).
/// - "Planned time" and duration are Today-only concepts: they stay local, never overwrite Apple's due date.
@MainActor
@Observable
package final class RemindersSync {
    package static let shared = RemindersSync()
    @ObservationIgnored private let log = Logger(subsystem: "com.luworks.one", category: "reminders-sync")

    private static let enabledKey = "today.remindersSync.enabled"
    private static let baseKey = "today.remindersSync.base"          // ids known on both sides after the last pass
    private static let listBaseKey = "today.remindersSync.listBase"
    private static let fpKey = "today.remindersSync.fp"              // id -> fingerprint both sides agreed on
    private static let uploadFromKey = "today.remindersSync.uploadFrom"
    private static let pendingKey = "today.remindersSync.pendingDeletes"          // reminders the user deleted in the app
    private static let pendingListsKey = "today.remindersSync.pendingListDeletes" // lists the user deleted in the app
    package static let maxRemoteDeletes = 10

    /// Created on first use: EKEventStore is slow to set up.
    @ObservationIgnored private lazy var store: EKEventStore = {
        let s = EKEventStore()
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: s, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.scheduleReconcile() }
        }
        return s
    }()

    @ObservationIgnored private var container: ModelContainer?
    @ObservationIgnored private var debounce: Task<Void, Never>?
    @ObservationIgnored private var running = false
    @ObservationIgnored private var again = false
    @ObservationIgnored private var completionFence = ReminderCompletionFence()

    /// Bumped after each finished pass so views that care can refresh.
    package private(set) var version = 0
    package private(set) var lastError: String?
    #if DEBUG
    /// UI tests only (`-uiTestingSyncDump <prefix>`): what Apple Reminders and the app hold after the last pass.
    package private(set) var debugAppleDump = ""
    package private(set) var debugAppDump = ""
    package private(set) var debugPersistedDump = ""
    @ObservationIgnored private var debugOpsDone = false
    #endif
    /// UI tests start with Apple Reminders off (a saved "on" from an earlier run would upload and pull test data);
    /// the test that needs it passes `-uiTestingRemindersSync`.
    package private(set) var enabled = UserDefaults.standard.bool(forKey: RemindersSync.enabledKey)
        && (!ProcessInfo.processInfo.arguments.contains("-uiTesting") || ProcessInfo.processInfo.arguments.contains("-uiTestingRemindersSync"))

    package var hasAccess: Bool { EKEventStore.authorizationStatus(for: .reminder) == .fullAccess }
    /// True once the user allowed access to Apple Reminders and sync is on.
    package var isConnected: Bool { enabled && hasAccess }

    private init() {}

    /// Titles are personal: they are only logged in debug builds.
    private func debugLog(_ message: String) {
        #if DEBUG
        log.info("\(message, privacy: .public)")
        #endif
    }

    // MARK: Lifecycle

    /// Call once at launch. Starts watching local saves; syncs right away when already connected.
    package func configure(_ container: ModelContainer) {
        self.container = container
        NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.scheduleReconcile() }
        }
        if isConnected { scheduleReconcile(after: .seconds(2)) }
    }

    /// iOS lets the app ask only once; after a "Don't Allow" the user has to change it in Settings.
    package var isDenied: Bool {
        let s = EKEventStore.authorizationStatus(for: .reminder)
        return s == .denied || s == .restricted
    }

    /// The first time the Reminders tab opens, show iOS's own permission prompt. Does nothing afterwards.
    package func connectIfFirstRun() async {
        guard !ProcessInfo.processInfo.arguments.contains("-uiTesting"),
              EKEventStore.authorizationStatus(for: .reminder) == .notDetermined else { return }
        await connect()
    }

    /// Asks for access (the first time) and turns sync on.
    package func connect() async {
        if !hasAccess {
            do {
                let granted = try await store.requestFullAccessToReminders()
                log.info("reminders access request: granted \(granted)")
            } catch {
                log.error("reminders access request failed: \((error as NSError).code, privacy: .public)")
            }
        }
        log.info("reminders authorization status: \(EKEventStore.authorizationStatus(for: .reminder).rawValue)")
        enabled = hasAccess
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        guard enabled else { return }
        if UserDefaults.standard.object(forKey: Self.uploadFromKey) == nil {
            UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: Self.uploadFromKey)
        }
        await reconcile()
    }

    /// Stops syncing and forgets what was linked. Nothing is deleted on either side.
    package func disconnect() {
        enabled = false
        forgetLink()
        UserDefaults.standard.set(false, forKey: Self.enabledKey)
    }

    /// Forget the linkage (not the data). Call before wiping local data so the wipe is never mirrored to Apple.
    package func forgetLink() {
        for k in [Self.baseKey, Self.listBaseKey, Self.fpKey, Self.uploadFromKey, Self.pendingKey, Self.pendingListsKey] {
            UserDefaults.standard.removeObject(forKey: k)
        }
    }

    /// The user deleted a synced reminder in the app: delete it in Apple Reminders too.
    /// Only explicit deletes like this are mirrored; a reminder that is merely missing locally (a wiped or
    /// rebuilt local store) is restored from Apple instead of being deleted there.
    package func noteDeleted(reminder externalID: String?) {
        guard let externalID, isConnected else { return }
        saveSet(loadSet(Self.pendingKey).union([externalID]), Self.pendingKey)
        scheduleReconcile()
    }

    package func noteDeleted(list externalID: String?) {
        guard let externalID, isConnected else { return }
        saveSet(loadSet(Self.pendingListsKey).union([externalID]), Self.pendingListsKey)
        scheduleReconcile()
    }

    package func scheduleReconcile(after delay: Duration = .milliseconds(1200)) {
        guard isConnected else { return }
        debounce?.cancel()
        debounce = Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await reconcile()
        }
    }

    /// A completion is an explicit user write, not a whole-reminder fingerprint edit. Commit it before
    /// the row or the success toast changes. Only this field is written, preserving concurrent Apple edits.
    @discardableResult
    package func commitCompletion(_ task: OneTask, done: Bool, restoringDue: Date? = nil, restoresDue: Bool = false,
                          expected: Remote? = nil) throws -> Remote? {
        guard let id = task.externalID else { return nil }
        var accepted: Remote?
        guard isConnected else { throw CompletionError.disconnected }
        try completionFence.commit {
            guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else {
                throw CompletionError.missing
            }
            guard reminder.calendar.allowsContentModifications else { throw CompletionError.readOnly }
            if let expected {
                let current = Remote(reminder)
                guard current.isDone == expected.isDone, current.due == expected.due,
                      current.doneAt == expected.doneAt else { throw CompletionError.changedOutside }
            }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-uiTestingFailReminderCompletion") {
                throw CompletionError.injected
            }
            #endif
            // Already completed externally is success; never reopen it as a side effect of completing.
            if reminder.isCompleted != done || restoresDue {
                reminder.isCompleted = done
                if restoresDue { reminder.dueDateComponents = restoringDue.map(Self.components(for:)) }
                do { try store.save(reminder, commit: true) }
                catch { reminder.reset(); throw error }
            }
            accepted = Remote(reminder)
        }
        return accepted
    }

    /// Keep the agreed completion fingerprint in step with the accepted user write. A repeating reminder
    /// that Apple advanced will differ and be pulled normally on the next pass.
    package func didPersistCompletion(_ task: OneTask, restoredDue: Bool = false) {
        if let id = task.externalID, isConnected {
            var fp = storedFP
            if let agreed = fp[id] {
                fp[id] = ReminderCompletionFence.baseline(agreed, done: task.isDone,
                    restoredDue: restoredDue ? (task.due.map { String(Int($0.timeIntervalSince1970)) } ?? "-") : nil)
                storedFP = fp
            }
        }
        scheduleReconcile(after: .milliseconds(50))
    }

    private enum CompletionError: LocalizedError {
        case disconnected, missing, readOnly, injected, changedOutside
        var errorDescription: String? {
            switch self {
            case .disconnected: return "Connect Apple Reminders in Settings, then tap the circle to retry."
            case .missing: return "This Apple reminder is unavailable. Refresh Reminders, then try again."
            case .readOnly: return "This reminder list is read-only. Choose a writable list in Apple Reminders."
            case .changedOutside: return "This reminder changed in Apple Reminders. Refresh before trying again."
            case .injected: return "The reminder could not be saved (test failure). Tap the circle to retry."
            }
        }
    }

    // MARK: Values

    /// A reminder as read from EventKit (plain values, safe to pass around).
    package struct Remote: Sendable {
        let id: String
        let title: String
        let notes: String
        let isDone: Bool
        let doneAt: Date?
        let due: Date?
        let listID: String
        let listTitle: String
        let flagged: Bool
        let repeatRule: String?
        /// Repeats in Apple Reminders, also with a rule the app has no name for (every 2 weeks): it rolls forward when completed.
        let repeats: Bool

        init(_ r: EKReminder) {
            id = r.calendarItemIdentifier
            title = r.title ?? ""
            notes = r.notes ?? ""
            isDone = r.isCompleted
            doneAt = r.completionDate
            due = r.dueDateComponents.flatMap { RemindersSync.date(from: $0) }
            listID = r.calendar.calendarIdentifier
            listTitle = r.calendar.title
            flagged = r.priority == 1
            repeatRule = RemindersSync.repeatRule(from: r.recurrenceRules)?.rawValue
            repeats = !(r.recurrenceRules ?? []).isEmpty
        }

        var fingerprint: String {
            [title, notes, isDone ? "1" : "0", due.map { String(Int($0.timeIntervalSince1970)) } ?? "-", listTitle,
             flagged ? "1" : "0", repeatRule ?? "-"].joined(separator: "\u{1F}")
        }
    }

    package static func fingerprint(of t: OneTask) -> String {
        [t.title, t.note, t.isDone ? "1" : "0", t.due.map { String(Int($0.timeIntervalSince1970)) } ?? "-", t.listName,
         t.flagged ? "1" : "0", t.repeatRule ?? "-"].joined(separator: "\u{1F}")
    }

    package static func fingerprint(of l: OneList) -> String { "\(l.name)\u{1F}\(l.colorIndex)" }

    // MARK: Date / recurrence mapping

    /// A due date with no time of day is stored as midnight, like everywhere else in the app.
    package nonisolated static func date(from c: DateComponents) -> Date? {
        var comps = c
        if comps.hour == nil { comps.hour = 0; comps.minute = 0 }
        return (comps.calendar ?? Calendar.current).date(from: comps)
    }

    package static func components(for due: Date) -> DateComponents {
        let cal = Calendar.current
        let t = cal.dateComponents([.hour, .minute], from: due)
        let hasTime = !(t.hour == 0 && t.minute == 0)
        return cal.dateComponents(hasTime ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day], from: due)
    }

    package nonisolated static func repeatRule(from rules: [EKRecurrenceRule]?) -> RepeatRule? {
        guard let rules, rules.count == 1, let r = rules.first, r.interval == 1 else { return nil }
        switch r.frequency {
        case .daily: return .daily
        case .monthly: return .monthly
        case .yearly: return .yearly
        case .weekly:
            // Positional weekdays and extra filters cannot be represented by a plain weekly set.
            guard (r.daysOfTheWeek ?? []).allSatisfy({ $0.weekNumber == 0 }),
                  (r.daysOfTheMonth ?? []).isEmpty, (r.monthsOfTheYear ?? []).isEmpty,
                  (r.weeksOfTheYear ?? []).isEmpty, (r.daysOfTheYear ?? []).isEmpty,
                  (r.setPositions ?? []).isEmpty else { return nil }
            let days = Set((r.daysOfTheWeek ?? []).map { $0.dayOfTheWeek.rawValue })
            if days == [2, 3, 4, 5, 6] { return .weekdays }
            return days.isEmpty ? .weekly : .weeklyOn(days.sorted())
        @unknown default: return nil
        }
    }

    package static func recurrence(for rule: RepeatRule) -> EKRecurrenceRule {
        switch rule {
        case .daily: return EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil)
        case .weekly: return EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil)
        case .monthly: return EKRecurrenceRule(recurrenceWith: .monthly, interval: 1, end: nil)
        case .yearly: return EKRecurrenceRule(recurrenceWith: .yearly, interval: 1, end: nil)
        case .weekdays, .weeklyOn:
            let values: [Int]
            if case .weeklyOn(let selected) = rule { values = selected } else { values = [2, 3, 4, 5, 6] }
            precondition(!values.isEmpty && values.allSatisfy { (1...7).contains($0) }, "Invalid weekly weekdays")
            let days = Set(values).sorted().map { EKRecurrenceDayOfWeek(EKWeekday(rawValue: $0)!) }
            return EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, daysOfTheWeek: days, daysOfTheMonth: nil,
                                    monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: nil, end: nil)
        }
    }

    /// The palette color nearest to a calendar color.
    package static func colorIndex(for cg: CGColor) -> Int {
        let ui = UIColor(cgColor: cg)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        var best = 6, bestD = CGFloat.greatestFiniteMagnitude
        for (i, c) in ReminderPalette.colors.enumerated() {
            var cr: CGFloat = 0, cg2: CGFloat = 0, cb: CGFloat = 0, ca: CGFloat = 0
            UIColor(c).getRed(&cr, green: &cg2, blue: &cb, alpha: &ca)
            let d = (r - cr) * (r - cr) + (g - cg2) * (g - cg2) + (b - cb) * (b - cb)
            if d < bestD { bestD = d; best = i }
        }
        return best
    }

    // MARK: Reconcile

    package func reconcile() async {
        guard isConnected, let container else { return }
        if running { again = true; return }
        running = true
        defer {
            running = false
            if again { again = false; scheduleReconcile() }
        }
        do {
            #if DEBUG
            let firstPass = !debugOpsDone
            if firstPass { await debugRunAppleOps() }
            #endif
            try await pass(container.mainContext)
            #if DEBUG
            if firstPass { debugOpsDone = true; debugRunAppOps(container.mainContext) }
            await debugRefreshDump(container.mainContext)
            #endif
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            log.error("sync failed: \((error as NSError).code, privacy: .public)")
        }
        version += 1
    }

    private func loadSet(_ key: String) -> Set<String> { Set(UserDefaults.standard.stringArray(forKey: key) ?? []) }
    private func saveSet(_ s: Set<String>, _ key: String) { UserDefaults.standard.set(Array(s), forKey: key) }
    private var storedFP: [String: String] {
        get { (UserDefaults.standard.dictionary(forKey: Self.fpKey) as? [String: String]) ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: Self.fpKey) }
    }

    private func fetchRemote() async -> [Remote] {
        let store = self.store
        let cals = store.calendars(for: .reminder)
        let open = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: cals)
        let since = Calendar.current.date(byAdding: .day, value: -30, to: .now)
        let done = store.predicateForCompletedReminders(withCompletionDateStarting: since, ending: .now, calendars: cals)
        let incomplete = await Self.fetch(store, open)
        let completed = await Self.fetch(store, done)
        return incomplete + completed
    }

    /// The store and predicates stay on their owning actor. The callback copies EventKit rows
    /// immediately into Sendable values before resuming the actor's continuation.
    private static func fetch(_ store: EKEventStore, _ predicate: NSPredicate) async -> [Remote] {
        await withCheckedContinuation { c in
            store.fetchReminders(matching: predicate) { c.resume(returning: ($0 ?? []).map(Remote.init)) }
        }
    }

    private func pass(_ context: ModelContext) async throws {
        // Only items created after connecting are uploaded. A missing mark (e.g. after forgetLink) means "from now".
        if UserDefaults.standard.object(forKey: Self.uploadFromKey) == nil {
            UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: Self.uploadFromKey)
        }
        let uploadFrom = Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: Self.uploadFromKey))
        var fp = storedFP

        // ---- Lists ----
        let allCalendars = store.calendars(for: .reminder)
        let calByID = Dictionary(uniqueKeysWithValues: allCalendars.map { ($0.calendarIdentifier, $0) })
        var lists = try context.fetch(FetchDescriptor<OneList>())
        var listBase = loadSet(Self.listBaseKey)
        var remoteDeletes = 0
        var pendingLists = loadSet(Self.pendingListsKey)
        // A delete Apple refused (or one over this pass's cap) stays pending and is tried again next time. Forgetting it
        // would make the next pass see the list in Apple as new and bring it back ("deleted, then it came back").
        var listsToRetry = Set<String>()
        for id in pendingLists {
            if let cal = calByID[id] {
                remoteDeletes += 1
                var removed = false
                if remoteDeletes <= Self.maxRemoteDeletes {
                    do { try store.removeCalendar(cal, commit: true); removed = true }
                    catch { log.error("list delete failed: \((error as NSError).code, privacy: .public)") }
                }
                if !removed { listsToRetry.insert(id); continue }
            }
            listBase.remove(id)
            fp["list:" + id] = nil
        }
        let deletedLists = pendingLists   // not brought back this pass, even when the delete is retried later
        pendingLists = listsToRetry
        saveSet(pendingLists, Self.pendingListsKey)
        let calendars = allCalendars.filter { !deletedLists.contains($0.calendarIdentifier) }

        for cal in calendars {
            let id = cal.calendarIdentifier
            let remoteFP = "\(cal.title)\u{1F}\(Self.colorIndex(for: cal.cgColor))"
            if let local = lists.first(where: { $0.externalID == id }) ?? lists.first(where: { $0.externalID == nil && $0.name == cal.title }) {
                if local.externalID != id { local.externalID = id }
                let localFP = Self.fingerprint(of: local)
                let agreed = fp["list:" + id]
                if agreed == nil || (remoteFP != agreed) {
                    // Apple changed (or first link): take Apple's name and color.
                    if local.name != cal.title { renameTasks(from: local.name, to: cal.title, in: context) }
                    if local.name != cal.title { local.name = cal.title }
                    let ci = Self.colorIndex(for: cal.cgColor)
                    if local.colorIndex != ci { local.colorIndex = ci }
                } else if localFP != agreed, cal.allowsContentModifications {
                    // Only the app changed: write it to Apple.
                    cal.title = local.name
                    cal.cgColor = UIColor(ReminderPalette.color(local.colorIndex)).cgColor
                    try? store.saveCalendar(cal, commit: true)
                }
                fp["list:" + id] = Self.fingerprint(of: local)
                listBase.insert(id)
            } else {
                // Apple's default list goes first, like in Apple Reminders.
                let isDefault = cal.calendarIdentifier == store.defaultCalendarForNewReminders()?.calendarIdentifier
                let o = OneList(name: cal.title, colorIndex: Self.colorIndex(for: cal.cgColor), symbol: "list.bullet",
                                order: isDefault ? (lists.map(\.order).min() ?? 0) - 1 : (lists.map(\.order).max() ?? -1) + 1)
                o.externalID = id
                context.insert(o)
                lists.append(o)
                fp["list:" + id] = Self.fingerprint(of: o)
                listBase.insert(id)
            }
        }
        // Lists deleted in Apple disappear here; lists deleted here are deleted in Apple.
        for l in lists {
            guard let id = l.externalID else { continue }
            if calByID[id] == nil, listBase.contains(id) {
                context.delete(l)
                listBase.remove(id)
            }
        }
        // New local lists (created after connecting) go to Apple.
        for l in lists where l.externalID == nil && l.createdAt >= uploadFrom {
            guard let source = store.defaultCalendarForNewReminders()?.source else { break }
            let cal = EKCalendar(for: .reminder, eventStore: store)
            cal.title = l.name
            cal.cgColor = UIColor(ReminderPalette.color(l.colorIndex)).cgColor
            cal.source = source
            if (try? store.saveCalendar(cal, commit: true)) != nil {
                l.externalID = cal.calendarIdentifier
                listBase.insert(cal.calendarIdentifier)
                fp["list:" + cal.calendarIdentifier] = Self.fingerprint(of: l)
            }
        }
        saveSet(listBase, Self.listBaseKey)
        if context.hasChanges { try context.save() }

        // ---- Reminders ----
        let completionRevision = completionFence.revision
        let remote = await fetchRemote()
        // A completion can commit while EventKit is fetching. This snapshot predates that write;
        // do not apply it or publish its old fingerprints as the next conflict baseline.
        guard completionFence.accepts(snapshot: completionRevision) else { again = true; return }
        let remoteByID = Dictionary(remote.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var tasks = try context.fetch(FetchDescriptor<OneTask>())
        var base = loadSet(Self.baseKey)
        let pending = loadSet(Self.pendingKey)
        var remindersToRetry = Set<String>()
        let calendarByTitle = Dictionary(calendars.map { ($0.title, $0) }, uniquingKeysWith: { a, _ in a })
        let defaultCal = store.defaultCalendarForNewReminders()

        // Link unlinked local tasks to an Apple reminder with the same title and list (never duplicate).
        var claimed = Set(tasks.compactMap(\.externalID))
        for r in remote where !claimed.contains(r.id) {
            // A task with no list lives in Apple's default list.
            if let t = tasks.first(where: { $0.externalID == nil && $0.title == r.title && ($0.listName.isEmpty ? defaultCal?.title : $0.listName) == r.listTitle }) {
                t.externalID = r.id
                claimed.insert(r.id)
                fp[r.id] = Self.fingerprint(of: t) == r.fingerprint ? r.fingerprint : nil
                base.insert(r.id)
            }
        }

        // Tasks with no list belong to Apple's default list: name it, so the default list is one row, not two.
        if let defaultTitle = defaultCal?.title {
            for t in tasks where t.listName.isEmpty { t.listName = defaultTitle }
        }

        // Apple -> app (new reminders and Apple-side edits)
        for r in remote {
            if let t = tasks.first(where: { $0.externalID == r.id }) {
                let agreed = fp[r.id]
                let local = Self.fingerprint(of: t)
                if agreed == nil || r.fingerprint != agreed {
                    // Apple changed (or Apple and the app both did: Apple wins).
                    if let agreed, local != agreed { ActivityCenter.record(ActivityEvents.syncConflict(source: "reminders")) }
                    apply(r, to: t)
                    fp[r.id] = r.fingerprint
                } else if local != agreed {
                    try push(t, remote: r)
                    fp[r.id] = Self.fingerprint(of: t)
                }
                base.insert(r.id)
            } else if pending.contains(r.id) {
                // The user deleted it in the app.
                remoteDeletes += 1
                var removed = false
                if remoteDeletes <= Self.maxRemoteDeletes, let ek = store.calendarItem(withIdentifier: r.id) as? EKReminder {
                    do { try store.remove(ek, commit: true); removed = true }
                    catch { log.error("reminder delete failed: \((error as NSError).code, privacy: .public)") }
                }
                if removed {
                    base.remove(r.id)
                    fp[r.id] = nil
                } else {
                    remindersToRetry.insert(r.id)   // tried again next pass; never pulled back in the meantime
                }
            } else {
                // New in Apple, or missing locally for any other reason (e.g. a rebuilt local store): bring it in.
                debugLog("pull \(r.title)")
                let t = OneTask(title: r.title)
                t.externalID = r.id
                apply(r, to: t)
                context.insert(t)
                tasks.append(t)
                fp[r.id] = r.fingerprint
                base.insert(r.id)
            }
        }

        // Linked tasks Apple no longer lists as open: completed there (still exists) or deleted there.
        for t in tasks {
            guard let id = t.externalID, remoteByID[id] == nil else { continue }
            if let ek = store.calendarItem(withIdentifier: id) as? EKReminder {
                if t.isDone == false, ek.isCompleted {
                    t.isDone = true
                    t.doneAt = ek.completionDate ?? .now
                    fp[id] = Self.fingerprint(of: t)
                } else if !t.isDone, !ek.isCompleted {
                    let r = Remote(ek)
                    apply(r, to: t)
                    fp[id] = r.fingerprint
                }
            } else if base.contains(id) {
                Ledger.record(.deleted, title: t.title, actor: .agent("Apple Reminders"), channel: .sync, approval: .observed,
                              context: context)
                context.delete(t)
                base.remove(id)
                fp[id] = nil
            } else {
                t.externalID = nil   // the link was stale (e.g. a restored backup); treat it as a new local task
            }
        }

        // app -> Apple: tasks created after connecting
        for t in tasks where t.externalID == nil && t.createdAt >= uploadFrom {
            let cal = (t.listName.isEmpty ? nil : calendarByTitle[t.listName]) ?? defaultCal
            guard let cal else { continue }
            debugLog("upload \(t.title)")
            let ek = EKReminder(eventStore: store)
            ek.calendar = cal
            try write(t, to: ek)
            if t.listName.isEmpty { t.listName = cal.title }
            t.externalID = ek.calendarItemIdentifier
            base.insert(ek.calendarItemIdentifier)
            fp[ek.calendarItemIdentifier] = Self.fingerprint(of: t)
        }

        // Publish an agreed baseline only after its local side is durable. A failed local save
        // must not make an old disk copy look like a new request to reopen an accepted completion.
        if context.hasChanges { try context.save() }
        saveSet(base, Self.baseKey)
        saveSet(remindersToRetry, Self.pendingKey)
        storedFP = fp
        log.info("sync ok: \(tasks.count) local, \(remote.count) in Apple Reminders, \(calendars.count) lists, \(remoteDeletes) Apple deletes")
    }

    // MARK: Field mapping

    private func renameTasks(from old: String, to new: String, in context: ModelContext) {
        let tasks = (try? context.fetch(FetchDescriptor<OneTask>(predicate: #Predicate { $0.listName == old }))) ?? []
        tasks.forEach { $0.listName = new }
    }

    /// Apple -> app. Planned time, duration, tags, checklist and reminder offsets stay as they are (a plan only goes when a
    /// repeating reminder rolls to its next occurrence).
    /// Only changed fields are written: SwiftData counts a same-value write as a change, which would loop the sync.
    private func apply(_ r: Remote, to t: OneTask) {
        if t.title != r.title { t.title = r.title }
        if t.note != r.notes { t.note = r.notes }
        if r.isDone != t.isDone {
            t.isDone = r.isDone
            t.doneAt = r.isDone ? (r.doneAt ?? .now) : nil
        }
        if t.due != r.due {
            // Apple rolled a repeating reminder to its next occurrence: the finished one's plan does not follow (see RepeatAdvance).
            let plan = RepeatAdvance.plannedStart(t.plannedStart, dueMovedFrom: t.due, to: r.due, repeats: r.repeats, isDone: r.isDone)
            if t.plannedStart != plan { t.plannedStart = plan }
            t.due = r.due
        }
        if t.listName != r.listTitle { t.listName = r.listTitle }
        if t.flagged != r.flagged { t.flagged = r.flagged }
        if t.repeatRule != r.repeatRule { t.repeatRule = r.repeatRule }
    }

    /// App -> Apple for an existing reminder.
    private func push(_ t: OneTask, remote r: Remote) throws {
        guard let ek = store.calendarItem(withIdentifier: r.id) as? EKReminder else { throw CompletionError.missing }
        if t.listName != r.listTitle, let cal = store.calendars(for: .reminder).first(where: { $0.title == t.listName }) {
            ek.calendar = cal
        }
        try write(t, to: ek, keepingRepeatIf: r.repeatRule == t.repeatRule)
    }

    private func write(_ t: OneTask, to ek: EKReminder, keepingRepeatIf keep: Bool = false) throws {
        ek.title = t.title
        ek.notes = t.note.isEmpty ? nil : t.note
        if ek.isCompleted != t.isDone { ek.isCompleted = t.isDone }
        ek.dueDateComponents = t.due.map(Self.components(for:))
        // Apple only alerts when the reminder has an alarm: a timed due date gets one at that time.
        let timed = t.due.map { Self.components(for: $0).hour != nil } ?? false
        ek.alarms?.filter { $0.absoluteDate != nil }.forEach { ek.removeAlarm($0) }
        if timed, let due = t.due { ek.addAlarm(EKAlarm(absoluteDate: due)) }
        ek.priority = t.flagged ? 1 : (ek.priority == 1 ? 0 : ek.priority)
        if !keep {
            ek.recurrenceRules?.forEach { ek.removeRecurrenceRule($0) }
            if let rule = t.repeats { ek.addRecurrenceRule(Self.recurrence(for: rule)) }
        }
        try store.save(ek, commit: true)
    }
}

#if DEBUG
// MARK: UI test hooks

/// Lets a UI test change Apple Reminders and the app's own data without typing, then read back both sides.
/// Debug builds with `-uiTesting` only. Each op is three arguments: `<op> <title> <value>` ("_" for no value).
/// - `-uiTestingAppleOp add|complete|rename|delete` runs on Apple Reminders directly, before the first pass
///   (`add` puts it in the default list, due tomorrow 9:00; the value is a `RepeatRule` raw value or "_").
/// - `-uiTestingAppOp complete|rename|delete|repeat` runs on the app's reminder after the first pass, through the
///   same `TaskActions` the screens use.
/// - `-uiTestingSyncDump <prefix>` shows both sides as hidden labels (`SyncDumpProbe`).
extension RemindersSync {
    private static func debugOps(_ flag: String) -> [(op: String, title: String, value: String)] {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-uiTesting") else { return [] }
        return args.indices.filter { args[$0] == flag && $0 + 3 < args.count }
            .map { (args[$0 + 1], args[$0 + 2], args[$0 + 3]) }
    }

    private static var debugPrefix: String? {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-uiTesting"), let i = args.firstIndex(of: "-uiTestingSyncDump"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    private func debugAllReminderIDs() async -> [String] {
        let store = self.store
        let predicate = store.predicateForReminders(in: nil)
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: (reminders ?? []).map(\.calendarItemIdentifier))
            }
        }
    }

    fileprivate func debugRunAppleOps() async {
        let ops = Self.debugOps("-uiTestingAppleOp")
        guard !ops.isEmpty else { return }
        for op in ops {
            let ids = await debugAllReminderIDs()
            let all = ids.compactMap { store.calendarItem(withIdentifier: $0) as? EKReminder }
            let match = all.first { $0.title == op.title && !$0.isCompleted } ?? all.first { $0.title == op.title }
            debugApply(op, to: match)
        }
    }

    private func debugApply(_ op: (op: String, title: String, value: String), to found: EKReminder?) {
        debugLog("apple op \(op.op) \(op.title)")
        if op.op == "add" || op.op == "addToday" {
            guard let cal = store.defaultCalendarForNewReminders() else { return }
            let ek = EKReminder(eventStore: store)
            ek.calendar = cal
            ek.title = op.title
            let tomorrow = Calendar.current.date(byAdding: .day, value: op.op == "addToday" ? 0 : 1, to: .now) ?? .now
            let due = Calendar.current.date(bySettingHour: op.op == "addToday" ? 12 : 9, minute: op.op == "addToday" ? 30 : 0, second: 0, of: tomorrow) ?? tomorrow
            ek.dueDateComponents = Self.components(for: due)
            if op.op == "addToday" { ek.notes = "Keep the water cup and documents together." }
            if let rule = RepeatRule(rawValue: op.value) { ek.addRecurrenceRule(Self.recurrence(for: rule)) }
            try? store.save(ek, commit: true)
            return
        }
        guard let ek = found else { return }
        switch op.op {
        case "complete": ek.isCompleted = true; try? store.save(ek, commit: true)
        case "rename": ek.title = op.value; try? store.save(ek, commit: true)
        case "delete": try? store.remove(ek, commit: true)
        default: break
        }
    }

    fileprivate func debugRunAppOps(_ context: ModelContext) {
        let ops = Self.debugOps("-uiTestingAppOp")
        guard !ops.isEmpty else { return }
        let tasks = (try? context.fetch(FetchDescriptor<OneTask>())) ?? []
        for op in ops {
            guard let t = tasks.first(where: { $0.title == op.title && !$0.isDone }) else { continue }
            switch op.op {
            case "complete": TaskActions.toggleDone(t, context: context, toast: nil)
            case "rename": t.title = op.value
            case "delete": TaskActions.delete(t, context: context, toast: nil)
            case "repeat": t.repeatRule = RepeatRule(rawValue: op.value)?.rawValue
            default: break
            }
        }
        try? context.save()
    }

    fileprivate func debugRefreshDump(_ context: ModelContext) async {
        guard let prefix = Self.debugPrefix else { return }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        func line(_ title: String, _ done: Bool, _ due: Date?, _ rule: String?) -> String {
            "\(title)|\(done ? "done" : "open")|\(due.map(f.string(from:)) ?? "-")|\(rule ?? "-")"
        }
        // A fresh EventKit store verifies the committed backend, not the object just mutated by the action.
        let verifyingStore = EKEventStore()
        let predicate = verifyingStore.predicateForReminders(in: nil)
        let all: [Remote] = await withCheckedContinuation { c in
            verifyingStore.fetchReminders(matching: predicate) { c.resume(returning: ($0 ?? []).map(Remote.init)) }
        }
        let apple = all.filter { $0.title.hasPrefix(prefix) }
        debugAppleDump = apple.map { line($0.title, $0.isDone, $0.due, $0.repeatRule) }.sorted().joined(separator: ";")
        let tasks = ((try? context.fetch(FetchDescriptor<OneTask>())) ?? []).filter { $0.title.hasPrefix(prefix) }
        debugAppDump = tasks.map { line($0.title, $0.isDone, $0.due, $0.repeatRule) }.sorted().joined(separator: ";")
        if let container {
            let persisted = ModelContext(container)
            persisted.autosaveEnabled = false
            let saved = ((try? persisted.fetch(FetchDescriptor<OneTask>())) ?? []).filter { $0.title.hasPrefix(prefix) }
            debugPersistedDump = saved.map { line($0.title, $0.isDone, $0.due, $0.repeatRule) }.sorted().joined(separator: ";")
        }
    }
}

/// Hidden labels a UI test reads: `syncDump.apple` and `syncDump.app`.
package struct SyncDumpProbe: View {
    private let sync = RemindersSync.shared

    package var body: some View {
        VStack {
            Text(sync.debugAppleDump).accessibilityIdentifier("syncDump.apple").accessibilityLabel(sync.debugAppleDump)
            Text(sync.debugAppDump).accessibilityIdentifier("syncDump.app").accessibilityLabel(sync.debugAppDump)
            Text(sync.debugPersistedDump).accessibilityIdentifier("syncDump.persisted").accessibilityLabel(sync.debugPersistedDump)
        }
        .font(.system(size: 1))
        .opacity(0.01)
        .allowsHitTesting(false)
    }
}
#endif
#endif

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
final class RemindersSync {
    static let shared = RemindersSync()
    @ObservationIgnored private let log = Logger(subsystem: "com.luworks.one", category: "reminders-sync")

    private static let enabledKey = "today.remindersSync.enabled"
    private static let baseKey = "today.remindersSync.base"          // ids known on both sides after the last pass
    private static let listBaseKey = "today.remindersSync.listBase"
    private static let fpKey = "today.remindersSync.fp"              // id -> fingerprint both sides agreed on
    private static let uploadFromKey = "today.remindersSync.uploadFrom"
    static let maxRemoteDeletes = 10

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

    /// Bumped after each finished pass so views that care can refresh.
    private(set) var version = 0
    private(set) var lastError: String?
    private(set) var enabled = UserDefaults.standard.bool(forKey: RemindersSync.enabledKey)

    var hasAccess: Bool { EKEventStore.authorizationStatus(for: .reminder) == .fullAccess }
    /// True once the user allowed access to Apple Reminders and sync is on.
    var isConnected: Bool { enabled && hasAccess }

    private init() {}

    // MARK: Lifecycle

    /// Call once at launch. Starts watching local saves; syncs right away when already connected.
    func configure(_ container: ModelContainer) {
        self.container = container
        NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.scheduleReconcile() }
        }
        if isConnected { scheduleReconcile(after: .seconds(2)) }
    }

    /// Asks for access (the first time) and turns sync on.
    func connect() async {
        if !hasAccess {
            _ = try? await store.requestFullAccessToReminders()
        }
        enabled = hasAccess
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        guard enabled else { return }
        if UserDefaults.standard.object(forKey: Self.uploadFromKey) == nil {
            UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: Self.uploadFromKey)
        }
        await reconcile()
    }

    /// Stops syncing and forgets what was linked. Nothing is deleted on either side.
    func disconnect() {
        enabled = false
        forgetLink()
        UserDefaults.standard.set(false, forKey: Self.enabledKey)
    }

    /// Forget the linkage (not the data). Call before wiping local data so the wipe is never mirrored to Apple.
    func forgetLink() {
        for k in [Self.baseKey, Self.listBaseKey, Self.fpKey, Self.uploadFromKey] { UserDefaults.standard.removeObject(forKey: k) }
    }

    func scheduleReconcile(after delay: Duration = .milliseconds(1200)) {
        guard isConnected else { return }
        debounce?.cancel()
        debounce = Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await reconcile()
        }
    }

    // MARK: Values

    /// A reminder as read from EventKit (plain values, safe to pass around).
    struct Remote: Sendable {
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
        }

        var fingerprint: String {
            [title, notes, isDone ? "1" : "0", due.map { String(Int($0.timeIntervalSince1970)) } ?? "-", listTitle,
             flagged ? "1" : "0", repeatRule ?? "-"].joined(separator: "\u{1F}")
        }
    }

    static func fingerprint(of t: OneTask) -> String {
        [t.title, t.note, t.isDone ? "1" : "0", t.due.map { String(Int($0.timeIntervalSince1970)) } ?? "-", t.listName,
         t.flagged ? "1" : "0", t.repeatRule ?? "-"].joined(separator: "\u{1F}")
    }

    static func fingerprint(of l: OneList) -> String { "\(l.name)\u{1F}\(l.colorIndex)" }

    // MARK: Date / recurrence mapping

    /// A due date with no time of day is stored as midnight, like everywhere else in the app.
    nonisolated static func date(from c: DateComponents) -> Date? {
        var comps = c
        if comps.hour == nil { comps.hour = 0; comps.minute = 0 }
        return (comps.calendar ?? Calendar.current).date(from: comps)
    }

    static func components(for due: Date) -> DateComponents {
        let cal = Calendar.current
        let t = cal.dateComponents([.hour, .minute], from: due)
        let hasTime = !(t.hour == 0 && t.minute == 0)
        return cal.dateComponents(hasTime ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day], from: due)
    }

    nonisolated static func repeatRule(from rules: [EKRecurrenceRule]?) -> RepeatRule? {
        guard let r = rules?.first, r.interval == 1 else { return nil }
        switch r.frequency {
        case .daily: return .daily
        case .monthly: return .monthly
        case .yearly: return .yearly
        case .weekly:
            let days = Set((r.daysOfTheWeek ?? []).map { $0.dayOfTheWeek.rawValue })
            if days == [2, 3, 4, 5, 6] { return .weekdays }
            return days.count <= 1 ? .weekly : nil
        @unknown default: return nil
        }
    }

    static func recurrence(for rule: RepeatRule) -> EKRecurrenceRule {
        switch rule {
        case .daily: return EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil)
        case .weekly: return EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil)
        case .monthly: return EKRecurrenceRule(recurrenceWith: .monthly, interval: 1, end: nil)
        case .yearly: return EKRecurrenceRule(recurrenceWith: .yearly, interval: 1, end: nil)
        case .weekdays:
            let days = [EKWeekday.monday, .tuesday, .wednesday, .thursday, .friday].map { EKRecurrenceDayOfWeek($0) }
            return EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, daysOfTheWeek: days, daysOfTheMonth: nil,
                                    monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: nil, end: nil)
        }
    }

    /// The palette color nearest to a calendar color.
    static func colorIndex(for cg: CGColor) -> Int {
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

    func reconcile() async {
        guard isConnected, let container else { return }
        if running { again = true; return }
        running = true
        defer {
            running = false
            if again { again = false; scheduleReconcile() }
        }
        do {
            try await pass(container.mainContext)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            log.error("sync failed: \(error.localizedDescription, privacy: .public)")
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
        async let a = Self.fetch(store, Unchecked(open))
        async let b = Self.fetch(store, Unchecked(done))
        return await a + b
    }

    /// EventKit objects are not Sendable; they are only touched inside this call.
    private struct Unchecked<T>: @unchecked Sendable { let value: T; init(_ v: T) { value = v } }

    private nonisolated static func fetch(_ store: EKEventStore, _ predicate: Unchecked<NSPredicate>) async -> [Remote] {
        await withCheckedContinuation { c in
            store.fetchReminders(matching: predicate.value) { c.resume(returning: ($0 ?? []).map(Remote.init)) }
        }
    }

    private func pass(_ context: ModelContext) async throws {
        let uploadFrom = Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: Self.uploadFromKey))
        var fp = storedFP

        // ---- Lists ----
        let calendars = store.calendars(for: .reminder)
        let calByID = Dictionary(uniqueKeysWithValues: calendars.map { ($0.calendarIdentifier, $0) })
        var lists = try context.fetch(FetchDescriptor<OneList>())
        var listBase = loadSet(Self.listBaseKey)
        var remoteDeletes = 0

        for cal in calendars {
            let id = cal.calendarIdentifier
            let remoteFP = "\(cal.title)\u{1F}\(Self.colorIndex(for: cal.cgColor))"
            if let local = lists.first(where: { $0.externalID == id }) ?? lists.first(where: { $0.externalID == nil && $0.name == cal.title }) {
                local.externalID = id
                let localFP = Self.fingerprint(of: local)
                let agreed = fp["list:" + id]
                if agreed == nil || (remoteFP != agreed) {
                    // Apple changed (or first link): take Apple's name and color.
                    if local.name != cal.title { renameTasks(from: local.name, to: cal.title, in: context) }
                    local.name = cal.title
                    local.colorIndex = Self.colorIndex(for: cal.cgColor)
                } else if localFP != agreed, cal.allowsContentModifications {
                    // Only the app changed: write it to Apple.
                    cal.title = local.name
                    cal.cgColor = UIColor(ReminderPalette.color(local.colorIndex)).cgColor
                    try? store.saveCalendar(cal, commit: true)
                }
                fp["list:" + id] = Self.fingerprint(of: local)
                listBase.insert(id)
            } else {
                let o = OneList(name: cal.title, colorIndex: Self.colorIndex(for: cal.cgColor), symbol: "list.bullet",
                                order: (lists.map(\.order).max() ?? -1) + 1)
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
        for id in listBase where !lists.contains(where: { $0.externalID == id }) {
            if let cal = calByID[id] {
                remoteDeletes += 1
                if remoteDeletes <= Self.maxRemoteDeletes { try? store.removeCalendar(cal, commit: true) }
            }
            listBase.remove(id)
            fp["list:" + id] = nil
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
        try context.save()

        // ---- Reminders ----
        let remote = await fetchRemote()
        let remoteByID = Dictionary(remote.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var tasks = try context.fetch(FetchDescriptor<OneTask>())
        var base = loadSet(Self.baseKey)
        let calendarByTitle = Dictionary(calendars.map { ($0.title, $0) }, uniquingKeysWith: { a, _ in a })
        let defaultCal = store.defaultCalendarForNewReminders()

        // Link unlinked local tasks to an Apple reminder with the same title and list (never duplicate).
        var claimed = Set(tasks.compactMap(\.externalID))
        for r in remote where !claimed.contains(r.id) {
            if let t = tasks.first(where: { $0.externalID == nil && $0.title == r.title && $0.listName == r.listTitle }) {
                t.externalID = r.id
                claimed.insert(r.id)
                fp[r.id] = Self.fingerprint(of: t) == r.fingerprint ? r.fingerprint : nil
                base.insert(r.id)
            }
        }

        // Apple -> app (new reminders and Apple-side edits)
        for r in remote {
            if let t = tasks.first(where: { $0.externalID == r.id }) {
                let agreed = fp[r.id]
                let local = Self.fingerprint(of: t)
                if agreed == nil || r.fingerprint != agreed {
                    // Apple changed (or Apple and the app both did: Apple wins).
                    apply(r, to: t)
                    fp[r.id] = r.fingerprint
                } else if local != agreed {
                    try push(t, remote: r)
                    fp[r.id] = Self.fingerprint(of: t)
                }
                base.insert(r.id)
            } else if !base.contains(r.id) {
                let t = OneTask(title: r.title)
                t.externalID = r.id
                apply(r, to: t)
                context.insert(t)
                tasks.append(t)
                fp[r.id] = r.fingerprint
                base.insert(r.id)
            } else {
                // Known on both sides before, gone locally: the user deleted it here.
                remoteDeletes += 1
                if remoteDeletes <= Self.maxRemoteDeletes,
                   let ek = store.calendarItem(withIdentifier: r.id) as? EKReminder { try? store.remove(ek, commit: true) }
                base.remove(r.id)
                fp[r.id] = nil
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
            let ek = EKReminder(eventStore: store)
            ek.calendar = cal
            try write(t, to: ek)
            if t.listName.isEmpty { t.listName = cal.title }
            t.externalID = ek.calendarItemIdentifier
            base.insert(ek.calendarItemIdentifier)
            fp[ek.calendarItemIdentifier] = Self.fingerprint(of: t)
        }

        saveSet(base, Self.baseKey)
        storedFP = fp
        try context.save()
    }

    // MARK: Field mapping

    private func renameTasks(from old: String, to new: String, in context: ModelContext) {
        let tasks = (try? context.fetch(FetchDescriptor<OneTask>(predicate: #Predicate { $0.listName == old }))) ?? []
        tasks.forEach { $0.listName = new }
    }

    /// Apple -> app. Planned time, duration, tags, checklist and reminder offsets stay as they are.
    private func apply(_ r: Remote, to t: OneTask) {
        t.title = r.title
        t.note = r.notes
        if r.isDone != t.isDone {
            t.isDone = r.isDone
            t.doneAt = r.isDone ? (r.doneAt ?? .now) : nil
        }
        t.due = r.due
        t.listName = r.listTitle
        t.flagged = r.flagged
        t.repeatRule = r.repeatRule
    }

    /// App -> Apple for an existing reminder.
    private func push(_ t: OneTask, remote r: Remote) throws {
        guard let ek = store.calendarItem(withIdentifier: r.id) as? EKReminder else { return }
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

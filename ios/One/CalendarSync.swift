import EventKit
import EventKitUI
import SwiftUI
import os

/// A read-only event from the system calendar (Apple Calendar, Google, Exchange…).
struct ExternalEvent: Identifiable, Hashable {
    let id: String
    /// EventKit identifier, for opening the event in Apple's own viewer.
    let eventIdentifier: String
    let title: String
    var location: String = ""
    let start: Date
    let end: Date
    let isAllDay: Bool
    var calendarID: String = ""
    let calendarTitle: String
    let color: Color

    var durationMinutes: Int { max(1, Int(end.timeIntervalSince(start) / 60)) }
}

/// A system calendar (one line in Apple's Calendars list).
struct SystemCalendar: Identifiable, Hashable {
    let id: String
    let title: String
    let sourceTitle: String
    let color: Color
}

/// EventKit bridge: shows system calendar events in Today / Calendar, and can save new events there.
@MainActor
@Observable
final class CalendarSync {
    static let shared = CalendarSync()
    @ObservationIgnored private let log = Logger(subsystem: "com.luworks.one", category: "calendar")

    /// Created on first use: EKEventStore is slow to set up and most launches don't need it.
    @ObservationIgnored private lazy var store: EKEventStore = {
        let s = EKEventStore()
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: s, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.version += 1 }
        }
        return s
    }()
    private static let enabledKey = "one.calendarSync.enabled"
    private static let hiddenKey = "one.calendarSync.hiddenCalendars"

    /// Bumped when the system calendar changes so views refetch.
    private(set) var version = 0
    /// UI tests start with Apple Calendar off (a saved "on" from an earlier run would leak test events into the
    /// system calendar); the tests that need it pass `-uiTestingCalendarSync`.
    private(set) var enabled = UserDefaults.standard.bool(forKey: CalendarSync.enabledKey)
        && (!ProcessInfo.processInfo.arguments.contains("-uiTesting") || ProcessInfo.processInfo.arguments.contains("-uiTestingCalendarSync"))
    /// Calendars turned off in the Calendars list. Stored as "hidden" so new calendars show by default, like Apple's.
    /// (UI tests start with every calendar shown, so an earlier run can't hide events from a later one.)
    private(set) var hiddenCalendarIDs: Set<String> = ProcessInfo.processInfo.arguments.contains("-uiTesting")
        ? [] : Set(UserDefaults.standard.stringArray(forKey: CalendarSync.hiddenKey) ?? [])

    var hasAccess: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }
    var isOn: Bool { enabled && hasAccess }

    /// Apple's own event editor is used when Calendar access is on. UI tests keep the in-app editor (no permission prompts).
    var usesNativeEditor: Bool { isOn && !ProcessInfo.processInfo.arguments.contains("-uiTesting") }

    private init() {}

    /// The store is created just after launch so the first frame never waits for EventKit.
    @ObservationIgnored private var storeReady = false
    @ObservationIgnored private var warming = false

    private func warmUp() {
        guard !warming else { return }
        warming = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            _ = store
            storeReady = true
            version += 1
        }
    }

    /// On the first launch show iOS's own Calendar permission prompt. Does nothing afterwards.
    func connectIfFirstRun() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-seedCalendarDemo") {
            await seedDemo()
            return
        }
        #endif
        guard !ProcessInfo.processInfo.arguments.contains("-uiTesting"),
              EKEventStore.authorizationStatus(for: .event) == .notDetermined else { return }
        await setEnabled(true)
    }

    /// Turns sync on (asking for access the first time) or off.
    func setEnabled(_ on: Bool) async {
        if on && !hasAccess {
            _ = try? await store.requestFullAccessToEvents()
        }
        storeReady = true
        enabled = on && hasAccess
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        version += 1
    }

    /// The store behind every system event, for Apple's own editor and calendar chooser.
    var eventStore: EKEventStore { store }

    /// Tells views to refetch (after Apple's editor saved or deleted something).
    func refresh() { version += 1 }

    // MARK: Calendars list

    /// All event calendars in the order Apple lists them: by account, then by name.
    func calendars() -> [SystemCalendar] {
        _ = version
        guard isOn, storeReady else { return [] }
        return store.calendars(for: .event)
            .sorted { ($0.source?.title ?? "", $0.title) < ($1.source?.title ?? "", $1.title) }
            .map(Self.describe)
    }

    /// Applies the Calendars list: `selected` calendars stay visible, the rest are hidden everywhere.
    func setVisibleCalendars(_ selected: Set<String>) {
        let all = Set(store.calendars(for: .event).map(\.calendarIdentifier))
        hiddenCalendarIDs = all.subtracting(selected)
        UserDefaults.standard.set(Array(hiddenCalendarIDs), forKey: Self.hiddenKey)
        version += 1
    }

    /// The calendars whose events are shown. nil = all of them.
    private func visibleCalendars() -> [EKCalendar]? {
        guard !hiddenCalendarIDs.isEmpty else { return nil }
        return store.calendars(for: .event).filter { !hiddenCalendarIDs.contains($0.calendarIdentifier) }
    }

    private static func describe(_ c: EKCalendar) -> SystemCalendar {
        SystemCalendar(id: c.calendarIdentifier, title: c.title, sourceTitle: c.source?.title ?? "", color: Color(cgColor: c.cgColor))
    }

    // MARK: Events

    /// System events overlapping `interval`, excluding ones Today created itself (`exclude`).
    func events(in interval: DateInterval, excluding exclude: Set<String> = []) -> [ExternalEvent] {
        _ = version
        guard isOn else { return [] }
        guard storeReady else {
            warmUp()
            return []
        }
        let visible = visibleCalendars()
        if let visible, visible.isEmpty { return [] }
        let predicate = store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: visible)
        return store.events(matching: predicate)
            .filter { !exclude.contains($0.eventIdentifier ?? "") }
            .map { e in
                ExternalEvent(id: (e.eventIdentifier ?? UUID().uuidString) + "@\(e.startDate.timeIntervalSince1970)",
                              eventIdentifier: e.eventIdentifier ?? "",
                              title: e.title ?? "Untitled", location: e.location ?? "",
                              start: e.startDate, end: e.endDate, isAllDay: e.isAllDay,
                              calendarID: e.calendar.calendarIdentifier,
                              calendarTitle: e.calendar.title, color: Color(cgColor: e.calendar.cgColor))
            }
    }

    func events(on day: Date, excluding exclude: Set<String> = []) -> [ExternalEvent] {
        guard let interval = Calendar.current.dateInterval(of: .day, for: day) else { return [] }
        return events(in: interval, excluding: exclude)
    }

    /// The calendar a mirrored event (one Today created) lives in: its color, and whether the Calendars list hides it.
    func calendar(forExternalID id: String?) -> SystemCalendar? {
        _ = version
        guard isOn, storeReady, let id else { return nil }
        if mirrorCacheVersion != version {
            mirrorCache = [:]
            mirrorCacheVersion = version
        }
        if let hit = mirrorCache[id] { return hit.calendar }
        let found = store.event(withIdentifier: id)?.calendar.map(Self.describe)
        mirrorCache[id] = MirrorLookup(calendar: found)
        return found
    }
    private struct MirrorLookup { let calendar: SystemCalendar? }
    @ObservationIgnored private var mirrorCache: [String: MirrorLookup] = [:]
    @ObservationIgnored private var mirrorCacheVersion = -1

    /// Color of a mirrored event's calendar, nil when unknown.
    func color(forExternalID id: String?) -> Color? { calendar(forExternalID: id)?.color }

    /// True when the Calendars list hides the calendar this mirrored event lives in.
    func isHidden(externalID id: String?) -> Bool {
        guard let c = calendar(forExternalID: id) else { return false }
        return hiddenCalendarIDs.contains(c.id)
    }

    /// A system event and the store it belongs to, for Apple's event viewer.
    func nativeEvent(identifier: String) -> (EKEvent, EKEventStore)? {
        guard isOn, let e = store.event(withIdentifier: identifier) else { return nil }
        return (e, store)
    }

    /// Saves a copy of `event` to the default calendar and returns its identifier.
    /// `span` is what a repeating event's change applies to; the default keeps the old behavior, AI edits pass `.thisEvent`.
    func save(_ event: OneEvent, span: EKSpan = .futureEvents) -> String? {
        guard isOn, let calendar = store.defaultCalendarForNewEvents else {
            log.error("save skipped isOn=\(self.isOn) default=\(self.store.defaultCalendarForNewEvents != nil)")
            return nil
        }
        let ek = event.externalID.flatMap { store.event(withIdentifier: $0) } ?? EKEvent(eventStore: store)
        ek.calendar = ek.calendar ?? calendar
        ek.title = event.title
        ek.startDate = event.start
        ek.endDate = event.start.addingTimeInterval(event.duration)
        ek.isAllDay = event.isAllDay
        if let rule = event.repeats {
            let freq: EKRecurrenceFrequency = switch rule {
            case .daily, .weekdays: .daily
            case .weekly: .weekly
            case .monthly: .monthly
            case .yearly: .yearly
            }
            var days: [EKRecurrenceDayOfWeek]?
            if rule == .weekdays { days = [.init(.monday), .init(.tuesday), .init(.wednesday), .init(.thursday), .init(.friday)] }
            ek.recurrenceRules = [EKRecurrenceRule(recurrenceWith: freq, interval: 1, daysOfTheWeek: days, daysOfTheMonth: nil,
                                                   monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: nil,
                                                   setPositions: nil, end: nil)]
        } else {
            ek.recurrenceRules = nil
        }
        do {
            try store.save(ek, span: span)
            log.info("saved \(ek.eventIdentifier ?? "nil", privacy: .public)")
            return ek.eventIdentifier
        } catch {
            log.error("save failed \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Removes the system copy of an event. False when the calendar refused (read-only or subscribed calendars such as
    /// Holidays and Birthdays), so callers can say so instead of acting as if it worked. A copy that is already gone,
    /// or no copy at all, counts as removed.
    @discardableResult
    func delete(externalID: String?, span: EKSpan = .futureEvents) -> Bool {
        guard isOn, let id = externalID, let ek = store.event(withIdentifier: id) else {
            log.info("delete: no system copy (isOn=\(self.isOn), id=\(externalID ?? "nil", privacy: .public))")
            return true
        }
        log.info("delete: \(ek.title ?? "", privacy: .public) calendar=\(ek.calendar.title, privacy: .public) source=\(ek.calendar.source?.title ?? "", privacy: .public) modifiable=\(ek.calendar.allowsContentModifications) recurring=\(ek.hasRecurrenceRules) span=\(span == .thisEvent ? "this" : "future", privacy: .public)")
        guard ek.calendar.allowsContentModifications else {
            log.error("delete refused: calendar is read-only")
            return false
        }
        do {
            try store.remove(ek, span: span)
            log.info("delete: removed, still there=\(self.store.event(withIdentifier: id) != nil)")
            return true
        } catch {
            log.error("delete failed \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Whether the system copy of an event can be deleted (its calendar accepts changes). True when there is no system copy.
    func canDelete(externalID: String?) -> Bool {
        guard isOn, let id = externalID, let ek = store.event(withIdentifier: id) else { return true }
        return ek.calendar.allowsContentModifications
    }

    /// Events Today created whose copy in Apple Calendar is gone (deleted there). Apple Calendar is the source of truth, so
    /// the local copy goes too. Empty unless Calendar sync is on and its store is ready, so a missing permission never counts as a delete.
    func removedMirrors(_ events: [OneEvent]) -> [OneEvent] {
        guard isOn, storeReady else { return [] }
        return events.filter { e in
            guard let id = e.externalID else { return false }
            return store.event(withIdentifier: id) == nil
        }
    }

    #if DEBUG
    /// UI-test hook: deletes system events with this title, as if they had been deleted in the Calendar app.
    func debugDeleteSystemEvents(titled title: String) {
        guard isOn else { return }
        storeReady = true
        let predicate = store.predicateForEvents(withStart: .now.addingTimeInterval(-86_400), end: .now.addingTimeInterval(14 * 86_400), calendars: nil)
        for e in store.events(matching: predicate) where e.title == title { try? store.remove(e, span: .futureEvents) }
        version += 1
    }
    #endif

    /// Whether the system copy of an event repeats (Delete then asks: this event or the series).
    func isRepeating(externalID: String?) -> Bool {
        guard isOn, let id = externalID, let ek = store.event(withIdentifier: id) else { return false }
        return ek.hasRecurrenceRules
    }

    /// Who a change to the system copy of an event reaches: attendee count and whether you organize it. Nil without a system copy.
    func audience(externalID: String?) -> (attendees: Int, isOrganizer: Bool)? {
        guard isOn, storeReady, let id = externalID, let ek = store.event(withIdentifier: id) else { return nil }
        return (ek.attendees?.count ?? 0, ek.organizer?.isCurrentUser ?? true)
    }
}

/// Row for a system calendar event (read-only, opens nothing).
struct ExternalEventRow: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let event: ExternalEvent
    /// The list that holds this row asks "this event or the series?" (see `entryDeleteDialog`).
    @Binding var pendingDelete: CalEntry?

    /// The same swipe and long-press actions as in the Calendar tab.
    private var entry: CalEntry {
        CalEntry(id: event.id, source: .system(event.eventIdentifier), title: event.title, location: event.location,
                 start: event.start, end: event.end, isAllDay: event.isAllDay, color: event.color, calendarTitle: event.calendarTitle)
    }

    var body: some View {
        HStack(spacing: 10) {
            if !event.isAllDay {
                TimeColumn(date: event.start)
            }
            CalendarBar(color: event.color)
            TitleDetail(title: Text(event.title), titleLines: typeSize.isAccessibilitySize ? nil : 2) {
                Label(event.isAllDay ? event.calendarTitle : "\(DurationLabel.text(minutes: event.durationMinutes)) · \(event.calendarTitle)",
                      systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .onTapGesture { NativeEvents.edit(identifier: event.eventIdentifier) }
        .entryActions(entry, pendingDelete: $pendingDelete, open: { _ in NativeEvents.edit(identifier: event.eventIdentifier) },
                      edit: { _ in NativeEvents.edit(identifier: event.eventIdentifier) })
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 1, leading: 20, bottom: 1, trailing: 20))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(EventSpeech.label(title: event.title, start: event.start, end: event.end, isAllDay: event.isAllDay,
                                              location: event.location, calendar: event.calendarTitle))
        .accessibilityAddTraits(.isButton)
    }
}

/// Shows Apple's event editor the way UIKit expects: presented over the top screen, not embedded in a SwiftUI sheet.
/// Embedded, its Delete Event confirmation closed without deleting anything (reproduced in the simulator), and a sheet
/// attached to each row of a long list could open the wrong event. One presenter for every place that opens it.
@MainActor
enum NativeEvents {
    private static var delegate: Delegate?
    private static let log = Logger(subsystem: "com.luworks.one", category: "calendar")

    /// `identifier` nil = a new event starting at `start`.
    static func edit(identifier: String? = nil, start: Date = .now) {
        let sync = CalendarSync.shared
        let vc = EKEventEditViewController()
        vc.eventStore = sync.eventStore
        if let identifier {
            guard let (existing, _) = sync.nativeEvent(identifier: identifier) else {
                log.error("edit: event not found")
                return
            }
            vc.event = existing
        } else {
            let event = EKEvent(eventStore: sync.eventStore)
            event.startDate = start
            event.endDate = start.addingTimeInterval(3600)
            event.calendar = sync.eventStore.defaultCalendarForNewEvents
            vc.event = event
        }
        let d = Delegate()
        delegate = d
        vc.editViewDelegate = d
        vc.presentationController?.delegate = d
        guard let top = topViewController() else { return }
        top.present(vc, animated: true)
        if let identifier { watch(vc, identifier: identifier) }
    }

    /// iOS 27's editor deletes the event but may not call its delegate, so it stays on screen and the list keeps the row,
    /// which looks like the delete failed (reproduced in the simulator: the event was gone from the calendar database).
    /// While the editor is up, check whether the event still exists; once it is gone, close the editor and refresh.
    private static func watch(_ vc: EKEventEditViewController, identifier: String) {
        Task { @MainActor [weak vc] in
            while let vc, vc.presentingViewController != nil {
                try? await Task.sleep(for: .milliseconds(400))
                if CalendarSync.shared.eventStore.event(withIdentifier: identifier) == nil {
                    log.info("editor: event is gone, closing")
                    CalendarSync.shared.refresh()
                    vc.dismiss(animated: true)
                    delegate = nil
                    return
                }
            }
            CalendarSync.shared.refresh()
        }
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        var top = scene?.keyWindow?.rootViewController ?? scene?.windows.first?.rootViewController
        while let next = top?.presentedViewController, !next.isBeingDismissed { top = next }
        return top
    }

    private final class Delegate: NSObject, EKEventEditViewDelegate, UIAdaptivePresentationControllerDelegate {
        /// Swiped down: nothing to save; refetch in case something changed meanwhile.
        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            Task { @MainActor in
                CalendarSync.shared.refresh()
                NativeEvents.delegate = nil
            }
        }

        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            print("NativeEvents: editor completed \(action.rawValue)")
            NativeEvents.log.info("apple editor done: \(action == .deleted ? "deleted" : action == .saved ? "saved" : "cancelled", privacy: .public)")
            Task { @MainActor in
                CalendarSync.shared.refresh()
                controller.dismiss(animated: true)
                NativeEvents.delegate = nil
            }
        }
    }
}

/// Opening a system event goes straight to Apple's editor (EventKitUI): title, start and end, all-day, calendar, alerts and
/// Delete Event are all editable at once, Done saves. Apple's read-only viewer made you tap Edit first and drew its own
/// Delete, so it is not used.
struct NativeEventSheet: View {
    let identifier: String

    var body: some View {
        NativeEventEditor(identifier: identifier).ignoresSafeArea()
    }
}

/// Apple's own event editor (EventKitUI), for a new event or an existing one. Saving, cancelling and deleting
/// (with Apple's "This event only / all future events" prompts) are all Apple's.
struct NativeEventEditor: UIViewControllerRepresentable {
    /// nil = a new event.
    var identifier: String?
    /// Where a new event starts (ignored when editing).
    var start: Date = .now
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let sync = CalendarSync.shared
        let vc = EKEventEditViewController()
        vc.eventStore = sync.eventStore
        if let identifier, let (existing, _) = sync.nativeEvent(identifier: identifier) {
            vc.event = existing
        } else {
            let event = EKEvent(eventStore: sync.eventStore)
            event.startDate = start
            event.endDate = start.addingTimeInterval(3600)
            event.calendar = sync.eventStore.defaultCalendarForNewEvents
            vc.event = event
        }
        vc.editViewDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(dismiss: { dismiss() }) }

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let dismiss: () -> Void
        init(dismiss: @escaping () -> Void) { self.dismiss = dismiss }
        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            Logger(subsystem: "com.luworks.one", category: "calendar").info("apple editor done: \(action == .deleted ? "deleted" : action == .saved ? "saved" : "cancelled", privacy: .public)")
            Task { @MainActor in CalendarSync.shared.refresh() }
            dismiss()
        }
    }
}

/// Apple's own calendar list (EventKitUI): accounts, color dots, checkmarks. Its selection is the Calendars filter.
struct NativeCalendarChooser: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UINavigationController {
        let sync = CalendarSync.shared
        let store = sync.eventStore
        let chooser = EKCalendarChooser(selectionStyle: .multiple, displayStyle: .allCalendars, entityType: .event, eventStore: store)
        let hidden = sync.hiddenCalendarIDs
        chooser.selectedCalendars = Set(store.calendars(for: .event).filter { !hidden.contains($0.calendarIdentifier) })
        chooser.showsDoneButton = true
        chooser.showsCancelButton = false
        chooser.delegate = context.coordinator
        chooser.navigationItem.title = "Calendars"
        return UINavigationController(rootViewController: chooser)
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(dismiss: { dismiss() }) }

    final class Coordinator: NSObject, EKCalendarChooserDelegate {
        let dismiss: () -> Void
        init(dismiss: @escaping () -> Void) { self.dismiss = dismiss }

        func calendarChooserSelectionDidChange(_ chooser: EKCalendarChooser) {
            let ids = Set(chooser.selectedCalendars.map(\.calendarIdentifier))
            Task { @MainActor in CalendarSync.shared.setVisibleCalendars(ids) }
        }
        func calendarChooserDidFinish(_ chooser: EKCalendarChooser) { dismiss() }
        func calendarChooserDidCancel(_ chooser: EKCalendarChooser) { dismiss() }
    }
}

/// VoiceOver text for an event, like Calendar's: "Lunch with Priya, 12:15 to 1:00 PM, Calendar: Work".
enum EventSpeech {
    static func label(title: String, start: Date, end: Date, isAllDay: Bool, location: String = "", calendar: String = "",
                      day: Date? = nil) -> String {
        var parts = [title]
        if isAllDay {
            parts.append("all-day")
        } else {
            // "12:15 – 1:00 PM" read as "12:15 to 1:00 PM".
            let range = Date.IntervalFormatStyle(time: .shortened).format(start..<max(end, start))
            let pieces = range.split(whereSeparator: { "–—-".contains($0) })
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            parts.append(pieces.count == 2 ? pieces.joined(separator: " to ") : range)
        }
        if !location.isEmpty { parts.append("Location: " + location) }
        if !calendar.isEmpty { parts.append("Calendar: " + calendar) }
        return parts.joined(separator: ", ")
    }
}

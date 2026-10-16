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
    let start: Date
    let end: Date
    let isAllDay: Bool
    let calendarTitle: String
    let color: Color

    var durationMinutes: Int { max(1, Int(end.timeIntervalSince(start) / 60)) }
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

    /// Bumped when the system calendar changes so views refetch.
    private(set) var version = 0
    private(set) var enabled = UserDefaults.standard.bool(forKey: CalendarSync.enabledKey)

    var hasAccess: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }
    var isOn: Bool { enabled && hasAccess }

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

    /// System events overlapping `interval`, excluding ones Today created itself (`exclude`).
    func events(in interval: DateInterval, excluding exclude: Set<String> = []) -> [ExternalEvent] {
        _ = version
        guard isOn else { return [] }
        guard storeReady else {
            warmUp()
            return []
        }
        let predicate = store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: nil)
        return store.events(matching: predicate)
            .filter { !exclude.contains($0.eventIdentifier ?? "") }
            .map { e in
                ExternalEvent(id: (e.eventIdentifier ?? UUID().uuidString) + "@\(e.startDate.timeIntervalSince1970)",
                              eventIdentifier: e.eventIdentifier ?? "",
                              title: e.title ?? "Untitled", start: e.startDate, end: e.endDate, isAllDay: e.isAllDay,
                              calendarTitle: e.calendar.title, color: Color(cgColor: e.calendar.cgColor))
            }
    }

    func events(on day: Date, excluding exclude: Set<String> = []) -> [ExternalEvent] {
        guard let interval = Calendar.current.dateInterval(of: .day, for: day) else { return [] }
        return events(in: interval, excluding: exclude)
    }

    /// A system event and the store it belongs to, for Apple's event viewer.
    func nativeEvent(identifier: String) -> (EKEvent, EKEventStore)? {
        guard isOn, let e = store.event(withIdentifier: identifier) else { return nil }
        return (e, store)
    }

    /// Saves a copy of `event` to the default calendar and returns its identifier.
    func save(_ event: OneEvent) -> String? {
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
            try store.save(ek, span: .futureEvents)
            log.info("saved \(ek.eventIdentifier ?? "nil", privacy: .public)")
            return ek.eventIdentifier
        } catch {
            log.error("save failed \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func delete(externalID: String?) {
        guard isOn, let id = externalID, let ek = store.event(withIdentifier: id) else { return }
        try? store.remove(ek, span: .futureEvents)
    }
}

/// Row for a system calendar event (read-only, opens nothing).
struct ExternalEventRow: View {
    let event: ExternalEvent
    @State private var showing = false

    var body: some View {
        HStack(spacing: 10) {
            if !event.isAllDay {
                TimeColumn(date: event.start)
            }
            RoundedRectangle(cornerRadius: 2)
                .fill(event.color)
                .frame(width: 4, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                Label(event.isAllDay ? event.calendarTitle : "\(DurationLabel.text(minutes: event.durationMinutes)) · \(event.calendarTitle)",
                      systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .onTapGesture { showing = true }
        .contextMenu { Button { showing = true } label: { Label("Show Details", systemImage: "info.circle") } }
        .sheet(isPresented: $showing) { NativeEventSheet(identifier: event.eventIdentifier) }
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// Apple's own event viewer (EventKitUI): editing, deleting and repeating-event prompts behave exactly like Calendar.
struct NativeEventSheet: UIViewControllerRepresentable {
    let identifier: String
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UINavigationController {
        guard let (event, store) = CalendarSync.shared.nativeEvent(identifier: identifier) else {
            return UINavigationController(rootViewController: UIViewController())
        }
        let vc = EKEventViewController()
        vc.event = event
        vc.allowsEditing = true
        vc.allowsCalendarPreview = true
        vc.delegate = context.coordinator
        _ = store
        return UINavigationController(rootViewController: vc)
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(dismiss: { dismiss() }) }

    final class Coordinator: NSObject, EKEventViewDelegate {
        let dismiss: () -> Void
        init(dismiss: @escaping () -> Void) { self.dismiss = dismiss }
        func eventViewController(_ controller: EKEventViewController, didCompleteWith action: EKEventViewAction) { dismiss() }
    }
}

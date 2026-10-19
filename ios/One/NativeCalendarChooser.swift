import SwiftUI
import EventKit
import EventKitUI

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

    @MainActor
    final class Coordinator: NSObject, @MainActor EKCalendarChooserDelegate {
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

#if os(iOS)
  import One
  import TodayDesignSystem
  import SwiftUI
  import EventKit
  import EventKitUI

  /// Apple's own calendar list (EventKitUI): accounts, color dots, checkmarks. Its selection is the Calendars filter.
  package struct NativeCalendarChooser: UIViewControllerRepresentable {
    let calendar: any NativeCalendarService
    package init(calendar: any NativeCalendarService) { self.calendar = calendar }
    @Environment(\.dismiss) private var dismiss

    package func makeUIViewController(context: Context) -> UINavigationController {
      let sync = calendar
      let store = sync.eventStore
      let chooser = EKCalendarChooser(
        selectionStyle: .multiple, displayStyle: .allCalendars, entityType: .event,
        eventStore: store)
      let hidden = sync.hiddenCalendarIDs
      chooser.selectedCalendars = Set(
        store.calendars(for: .event).filter { !hidden.contains($0.calendarIdentifier) })
      chooser.showsDoneButton = true
      chooser.showsCancelButton = false
      chooser.delegate = context.coordinator
      chooser.navigationItem.title = "Calendars"
      return UINavigationController(rootViewController: chooser)
    }

    package func updateUIViewController(_ controller: UINavigationController, context: Context) {}

    package func makeCoordinator() -> Coordinator {
      Coordinator(calendar: calendar, dismiss: { dismiss() })
    }

    @MainActor
    package final class Coordinator: NSObject, @MainActor EKCalendarChooserDelegate {
      let calendar: any NativeCalendarService
      let dismiss: () -> Void
      init(calendar: any NativeCalendarService, dismiss: @escaping () -> Void) {
        self.calendar = calendar
        self.dismiss = dismiss
      }

      package func calendarChooserSelectionDidChange(_ chooser: EKCalendarChooser) {
        let ids = Set(chooser.selectedCalendars.map(\.calendarIdentifier))
        calendar.setVisibleCalendars(ids)
      }
      package func calendarChooserDidFinish(_ chooser: EKCalendarChooser) { dismiss() }
      package func calendarChooserDidCancel(_ chooser: EKCalendarChooser) { dismiss() }
    }
  }

#endif

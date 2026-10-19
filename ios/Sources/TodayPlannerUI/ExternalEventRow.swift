#if os(iOS)
  import One
  import SwiftUI
  import TodayCore
  import TodayPlatform
  import TodayDesignSystem

  /// Row for a system calendar event (read-only, opens nothing).
  package struct ExternalEventRow: View {
    @Environment(PlannerPresentation.self) private var presentation
    package init(
      event: ExternalEvent, pendingDelete: Binding<CalEntry?>, calendar: any CalendarService,
      travel: any TravelTimeProviding
    ) {
      self.event = event
      _pendingDelete = pendingDelete
      self.calendar = calendar
      self.travelProvider = travel
    }
    private let calendar: any CalendarService
    private let travelProvider: any TravelTimeProviding
    @Environment(\.dynamicTypeSize) private var typeSize
    package let event: ExternalEvent
    /// The list that holds this row asks "this event or the series?" (see `entryDeleteDialog`).
    @Binding package var pendingDelete: CalEntry?
    @AppStorage(SettingsKey.travelTime) private var travelOn = true

    /// The same swipe and long-press actions as in the Calendar tab.
    private var entry: CalEntry {
      CalEntry(
        id: event.id, source: .system(event.eventIdentifier), title: event.title,
        location: event.location,
        start: event.start, end: event.end, isAllDay: event.isAllDay, color: event.color,
        calendarTitle: event.calendarTitle,
        repeats: event.repeats)
    }

    package var body: some View {
      HStack(spacing: 10) {
        if !event.isAllDay {
          TimeColumn(date: event.start)
        }
        CalendarBar(color: event.color)
        VStack(alignment: .leading, spacing: 1) {
          TitleDetail(title: Text(event.title), titleLines: typeSize.isAccessibilitySize ? nil : 2)
          {
            Label(
              event.isAllDay
                ? event.calendarTitle
                : "\(DurationLabel.text(minutes: event.durationMinutes)) · \(event.calendarTitle)",
              systemImage: "calendar"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
          }
          if let travel { TravelLine(text: travel) }
        }
        Spacer(minLength: 0)
      }
      .fixedSize(horizontal: false, vertical: true)
      .frame(minHeight: 44)
      .contentShape(Rectangle())
      .onTapGesture {
        (calendar as? any NativeCalendarService)?.edit(
          identifier: event.eventIdentifier, start: event.start, end: nil, fullOptions: false,
          onComplete: nil)
      }
      .entryActions(
        entry, pendingDelete: $pendingDelete,
        open: { _ in
          (calendar as? any NativeCalendarService)?.edit(
            identifier: event.eventIdentifier, start: event.start, end: nil, fullOptions: false,
            onComplete: nil)
        },
        edit: { _ in
          (calendar as? any NativeCalendarService)?.edit(
            identifier: event.eventIdentifier, start: event.start, end: nil, fullOptions: false,
            onComplete: nil)
        }, calendar: calendar
      )
      .listRowSeparator(.hidden)
      .listRowInsets(EdgeInsets(top: 1, leading: 20, bottom: 1, trailing: 20))
      .accessibilityElement(children: .combine)
      .accessibilityLabel(
        plannerEventSpeech(
          title: event.title, start: event.start, end: event.end, isAllDay: event.isAllDay,
          location: event.location, calendar: event.calendarTitle, runtime: presentation.runtime)
          + (travel.map { ". " + $0 } ?? "")
      )
      .accessibilityAddTraits(.isButton)
    }

    /// "Drive 18 min · Leave by 14:20" for an upcoming event with a location (today or tomorrow).
    private var travel: String? {
      guard travelOn else { return nil }
      return travelProvider.label(
        eventID: event.eventIdentifier, start: event.start, isAllDay: event.isAllDay,
        place: event.place, now: presentation.now)
    }
  }
#endif

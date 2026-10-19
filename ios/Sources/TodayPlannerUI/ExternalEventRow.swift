#if os(iOS)
import One
import SwiftUI
import TodayCore
import TodayPlatform
import TodayDesignSystem

/// Row for a system calendar event (read-only, opens nothing).
package struct ExternalEventRow: View {
    package init(event: ExternalEvent, pendingDelete: Binding<CalEntry?>) { self.event = event; _pendingDelete = pendingDelete }
    @Environment(\.dynamicTypeSize) private var typeSize
    package let event: ExternalEvent
    /// The list that holds this row asks "this event or the series?" (see `entryDeleteDialog`).
    @Binding package var pendingDelete: CalEntry?
    @AppStorage(SettingsKey.travelTime) private var travelOn = true

    /// The same swipe and long-press actions as in the Calendar tab.
    private var entry: CalEntry {
        CalEntry(id: event.id, source: .system(event.eventIdentifier), title: event.title, location: event.location,
                 start: event.start, end: event.end, isAllDay: event.isAllDay, color: event.color, calendarTitle: event.calendarTitle,
                 repeats: event.repeats)
    }

    package var body: some View {
        HStack(spacing: 10) {
            if !event.isAllDay {
                TimeColumn(date: event.start)
            }
            CalendarBar(color: event.color)
            VStack(alignment: .leading, spacing: 1) {
                TitleDetail(title: Text(event.title), titleLines: typeSize.isAccessibilitySize ? nil : 2) {
                    Label(event.isAllDay ? event.calendarTitle : "\(DurationLabel.text(minutes: event.durationMinutes)) · \(event.calendarTitle)",
                          systemImage: "calendar")
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
        .onTapGesture { NativeEvents.edit(identifier: event.eventIdentifier, start: event.start) }
        .entryActions(entry, pendingDelete: $pendingDelete, open: { _ in NativeEvents.edit(identifier: event.eventIdentifier, start: event.start) },
                      edit: { _ in NativeEvents.edit(identifier: event.eventIdentifier, start: event.start) })
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 1, leading: 20, bottom: 1, trailing: 20))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(EventSpeech.label(title: event.title, start: event.start, end: event.end, isAllDay: event.isAllDay,
                                              location: event.location, calendar: event.calendarTitle)
                            + (travel.map { ". " + $0 } ?? ""))
        .accessibilityAddTraits(.isButton)
    }

    /// "Drive 18 min · Leave by 14:20" for an upcoming event with a location (today or tomorrow).
    private var travel: String? {
        guard travelOn else { return nil }
        return TravelTimes.shared.label(eventID: event.eventIdentifier, start: event.start, isAllDay: event.isAllDay, place: event.place)
    }
}
#endif

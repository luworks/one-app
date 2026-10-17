import SwiftUI
import WidgetKit

// "Next up": the next three things today (events, reminders with a time, alarms), for the Lock Screen and Home Screen.
// The widget reads only the JSON snapshot the app writes into the App Group (see Shared/WidgetSnapshot.swift).

@main
struct TodayWidgetsBundle: WidgetBundle {
    var body: some Widget {
        NextUpWidget()
    }
}

struct NextUpWidget: Widget {
    let kind = "TodayNextUp"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NextUpProvider()) { entry in
            NextUpView(entry: entry)
        }
        .configurationDisplayName("Next Up")
        .description("The next three things today: events, reminders and alarms.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline, .systemSmall, .systemMedium])
    }
}

// MARK: Timeline

struct NextUpEntry: TimelineEntry {
    let date: Date
    let items: [WidgetItem]

    var next: NextUp { NextItems.select(from: items, now: date) }
    /// Items on this entry's day (left or not), for the circular gauge.
    var totalToday: Int { items.filter { Calendar.current.isDate($0.start, inSameDayAs: date) }.count }
}

struct NextUpProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextUpEntry {
        NextUpEntry(date: .now, items: Self.sample(now: .now))
    }

    func getSnapshot(in context: Context, completion: @escaping (NextUpEntry) -> Void) {
        let items = WidgetSnapshot.load()?.items ?? []
        // The widget gallery shows sample items when the app hasn't written anything yet.
        completion(NextUpEntry(date: .now, items: context.isPreview && items.isEmpty ? Self.sample(now: .now) : items))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextUpEntry>) -> Void) {
        let now = Date.now
        let items = WidgetSnapshot.load()?.items ?? []
        // One entry at each start and end, so the list advances by itself; the last one is midnight, then reload.
        let entries = NextItems.timelineDates(for: items, now: now).map { NextUpEntry(date: $0, items: items) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    static func sample(now: Date) -> [WidgetItem] {
        let base = Calendar.current.date(bySetting: .minute, value: 0, of: now.addingTimeInterval(3600)) ?? now
        return [
            WidgetItem(id: "s1", title: "Team standup", start: base, end: base.addingTimeInterval(900), kind: .event),
            WidgetItem(id: "s2", title: "Call Alex", start: base.addingTimeInterval(5400), kind: .reminder),
            WidgetItem(id: "s3", title: "Dentist", start: base.addingTimeInterval(10800), end: base.addingTimeInterval(14400), kind: .event),
        ]
    }
}

// MARK: Views

struct NextUpView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NextUpEntry

    var body: some View {
        content
            .widgetURL(WidgetLink.url())
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .accessoryRectangular: RectangularView(entry: entry).containerBackground(for: .widget) { Color.clear }
        case .accessoryCircular: CircularView(entry: entry).containerBackground(for: .widget) { Color.clear }
        case .accessoryInline: InlineView(entry: entry).containerBackground(for: .widget) { Color.clear }
        case .systemMedium: MediumView(entry: entry).containerBackground(.background, for: .widget)
        default: SmallView(entry: entry).containerBackground(.background, for: .widget)
        }
    }
}

/// "15:00" (in the user's 12/24-hour setting) or "All day".
struct TimeText: View {
    let item: WidgetItem
    var body: some View {
        if item.isAllDay {
            Text("All day")
        } else {
            Text(item.start, format: .dateTime.hour().minute())
        }
    }
}

extension WidgetItem.Kind {
    var symbol: String {
        switch self {
        case .event: "calendar"
        case .reminder: "circle"
        case .alarm: "alarm"
        }
    }
}

/// Under the clock: up to three lines "15:00 Dentist".
struct RectangularView: View {
    let entry: NextUpEntry

    var body: some View {
        let next = entry.next
        VStack(alignment: .leading, spacing: 0) {
            if next.today.isEmpty {
                Text("Nothing else today")
                    .font(.headline)
                    .widgetAccentable()
                if let t = next.tomorrow {
                    Text("Tomorrow")
                        .foregroundStyle(.secondary)
                    row(t)
                }
            } else {
                ForEach(next.today) { row($0) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func row(_ item: WidgetItem) -> some View {
        HStack(spacing: 4) {
            TimeText(item: item)
                .fontWeight(.semibold)
                .monospacedDigit()
                .widgetAccentable()
            Text(item.title)
        }
        .lineLimit(1)
    }
}

/// A ring of how much of today is done, with the next item's time in the middle.
struct CircularView: View {
    let entry: NextUpEntry

    var body: some View {
        let next = entry.next
        if let item = next.today.first {
            let total = max(entry.totalToday, next.remainingToday, 1)
            Gauge(value: Double(total - next.remainingToday), in: 0...Double(total)) {
                Image(systemName: item.kind.symbol)
            } currentValueLabel: {
                TimeText(item: item)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetAccentable()
            .accessibilityLabel(Text("Next: \(item.title). \(next.remainingToday) left today."))
        } else {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "checkmark")
                    .font(.title2.weight(.semibold))
                    .widgetAccentable()
            }
            .accessibilityLabel("Nothing else today")
        }
    }
}

/// Above the clock: "15:00 Dentist".
struct InlineView: View {
    let entry: NextUpEntry

    var body: some View {
        if let item = entry.next.today.first {
            if item.isAllDay {
                Text("All day \(item.title)")
            } else {
                Text("\(Text(item.start, format: .dateTime.hour().minute())) \(item.title)")
            }
        } else {
            Text("Nothing else today")
        }
    }
}

/// Home Screen small: the next item, its time and how long until it starts.
struct SmallView: View {
    let entry: NextUpEntry

    var body: some View {
        let next = entry.next
        VStack(alignment: .leading, spacing: 4) {
            Text(next.today.isEmpty && next.tomorrow != nil ? "TOMORROW" : "NEXT")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tint)
            if let item = next.today.first ?? next.tomorrow {
                TimeText(item: item)
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(item.title)
                    .font(.headline)
                    .lineLimit(2)
                Spacer(minLength: 0)
                if next.today.first != nil, !item.isAllDay {
                    if item.start > entry.date {
                        Text("in \(Text(item.start, style: .relative))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("Now").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if next.remainingToday > 1 {
                    Text("\(next.remainingToday - 1) more today")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Nothing else today")
                    .font(.headline)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Home Screen medium: the next three items, each opening Today on its day.
struct MediumView: View {
    let entry: NextUpEntry

    var body: some View {
        let next = entry.next
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Next Up")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
                Spacer()
                if next.remainingToday > next.today.count {
                    Text("+\(next.remainingToday - next.today.count) more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if next.today.isEmpty {
                Text("Nothing else today")
                    .font(.headline)
                if let t = next.tomorrow {
                    Text("Tomorrow").font(.caption).foregroundStyle(.secondary)
                    row(t)
                }
            } else {
                ForEach(next.today) { row($0) }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func row(_ item: WidgetItem) -> some View {
        Link(destination: WidgetLink.url(day: item.start)) {
            HStack(spacing: 8) {
                Image(systemName: item.kind.symbol)
                    .font(.caption)
                    .foregroundStyle(.tint)
                    .frame(width: 16)
                TimeText(item: item)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .frame(minWidth: 52, alignment: .leading)
                Text(item.title)
                    .font(.subheadline)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        }
    }
}

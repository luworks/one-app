import SwiftUI
import WidgetKit

/// One entry per day; the system asks for a new timeline right after midnight.
struct DayEntry: TimelineEntry {
    let date: Date
}

struct DayProvider: TimelineProvider {
    func placeholder(in context: Context) -> DayEntry { DayEntry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (DayEntry) -> Void) {
        completion(DayEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DayEntry>) -> Void) {
        let cal = Calendar.current
        let tomorrow = cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: .now) ?? .now)
        completion(Timeline(entries: [DayEntry(date: .now)], policy: .after(tomorrow)))
    }
}

private let accent = Color(red: 232 / 255, green: 116 / 255, blue: 59 / 255)

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DayEntry

    private var weekday: String { entry.date.formatted(.dateTime.weekday(.abbreviated)).uppercased() }
    private var day: String { entry.date.formatted(.dateTime.day()) }
    private var month: String { entry.date.formatted(.dateTime.month(.wide)) }

    var body: some View {
        switch family {
        case .accessoryCircular:
            VStack(spacing: 0) {
                Text(weekday).font(.system(size: 11, weight: .semibold))
                Text(day).font(.system(size: 24, weight: .medium))
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 0) {
                Text(weekday).font(.system(size: 13, weight: .semibold))
                Text("\(day) \(month)").font(.system(size: 20, weight: .medium))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            VStack(alignment: .leading, spacing: 0) {
                Text(weekday)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(accent)
                Spacer(minLength: 0)
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(day).font(.system(size: 64, weight: .medium))
                    Circle().fill(accent).frame(width: 10, height: 10)
                }
                Text(month).font(.system(size: 15)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

struct TodayWidget: Widget {
    let kind = "TodayDateWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DayProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color(red: 0.11, green: 0.11, blue: 0.12) }
                .environment(\.colorScheme, .dark)
        }
        .configurationDisplayName("Today")
        .description("The weekday and date, updated every day.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

@main
struct TodayWidgetBundle: WidgetBundle {
    var body: some Widget { TodayWidget() }
}

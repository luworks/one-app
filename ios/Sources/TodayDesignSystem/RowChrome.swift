#if os(iOS)
import SwiftUI
import TodayCore

struct TimeColumn: View {
    let date: Date
    var body: some View {
        Text(date.formatted(date: .omitted, time: .shortened))
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            // Never wraps: at large text sizes the column widens instead of breaking "09:00" over three lines.
            .lineLimit(1)
            .fixedSize()
            .frame(minWidth: 58, alignment: .leading)
    }
}

/// A row's title with its detail caption. Both sit on one line when they fit; otherwise the detail drops below.
/// Long titles stop at `titleLines` so one item can't fill the screen (the full title is in Show Details).
struct TitleDetail<Detail: View>: View {
    let title: Text
    var titleLines: Int? = 2
    @ViewBuilder var detail: Detail

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                title.lineLimit(1)
                detail
            }
            VStack(alignment: .leading, spacing: 1) {
                title.lineLimit(titleLines)
                detail
            }
        }
    }
}

/// The travel-time line under an event with a location: "Drive 18 min · Leave by 14:20".
struct TravelLine: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let text: String
    var body: some View {
        Label(text, systemImage: "car.fill")
            .font(.caption)
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
            // One line normally; at accessibility sizes "Drive 18 min · Leave by 14:20" wraps instead of losing the time.
            .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
    }
}

/// The calendar color bar beside an event; it stretches to the height of the row's text.
struct CalendarBar: View {
    let color: Color
    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(color)
            .frame(width: 4)
            .frame(minHeight: 18, maxHeight: .infinity)
    }
}

struct NowRow: View {
    let date: Date
    var body: some View {
        HStack(spacing: 8) {
            Text("Now " + date.formatted(date: .omitted, time: .shortened))
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.red)
            Rectangle().fill(Color.red).frame(height: 1)
        }
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 2, leading: 20, bottom: 2, trailing: 20))
    }
}


#endif

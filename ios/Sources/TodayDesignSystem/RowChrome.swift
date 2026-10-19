#if os(iOS)
import SwiftUI
import TodayCore

package struct TimeColumn: View {
    package init(date: Date) { self.date = date }
    package let date: Date
    package var body: some View {
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
package struct TitleDetail<Detail: View>: View {
    package init(title: Text, titleLines: Int? = 2, @ViewBuilder detail: () -> Detail) { self.title = title; self.titleLines = titleLines; self.detail = detail() }
    package let title: Text
    package var titleLines: Int? = 2
    @ViewBuilder package var detail: Detail

    package var body: some View {
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
package struct TravelLine: View {
    package init(text: String) { self.text = text }
    @Environment(\.dynamicTypeSize) private var typeSize
    package let text: String
    package var body: some View {
        Label(text, systemImage: "car.fill")
            .font(.caption)
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
            // One line normally; at accessibility sizes "Drive 18 min · Leave by 14:20" wraps instead of losing the time.
            .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
    }
}

/// The calendar color bar beside an event; it stretches to the height of the row's text.
package struct CalendarBar: View {
    package init(color: Color) { self.color = color }
    package let color: Color
    package var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(color)
            .frame(width: 4)
            .frame(minHeight: 18, maxHeight: .infinity)
    }
}

package struct NowRow: View {
    package init(date: Date) { self.date = date }
    package let date: Date
    package var body: some View {
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

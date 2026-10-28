#if os(iOS)
  import SwiftUI
  import TodayCore

  /// Today typography and geometry; semantic fonts continue to follow Dynamic Type.
  package enum AgendaRowStyle {
    package static let title = Font.callout
    package static let detail = Font.caption
    package static let disclosure = Font.footnote
    package static let iconWidth: CGFloat = 32
    package static let titleGap: CGFloat = 6
    package static let timeWidth: CGFloat = 50
  }

  /// The invisible title glyph supplies the real first-line baseline to the indicator.
  /// A 44pt checkbox can extend into the noninteractive time gutter, never into the title.
  package struct AgendaIconSlot: ViewModifier {
    package var enabled: Bool
    @Environment(\.dynamicTypeSize) private var typeSize
    package init(enabled: Bool) { self.enabled = enabled }
    @ViewBuilder package func body(content: Content) -> some View {
      if enabled {
        Text(" ").font(AgendaRowStyle.title).hidden()
          .frame(
            width: AgendaRowStyle.iconWidth, height: ButtonConfiguration.minimumHitSize,
            alignment: typeSize.isAccessibilitySize ? .center : .top
          )
          .overlay(alignment: typeSize.isAccessibilitySize ? .center : .top) { content }
          .padding(.trailing, AgendaRowStyle.titleGap)
      } else {
        content
      }
    }
  }

  package struct TimeColumn: View {
    package init(date: Date, compact: Bool = false) {
      self.date = date
      self.compact = compact
    }
    package var compact = false
    package let date: Date
    @Environment(PlannerPresentation.self) private var presentation
    private func label(_ value: Date) -> Text {
      Text(
        value.formatted(
          Date.FormatStyle(
            date: .omitted, time: .shortened, locale: presentation.locale,
            calendar: presentation.calendar, timeZone: presentation.calendar.timeZone)))
    }

    package var body: some View {
      ZStack(alignment: .leading) {
        if compact {
          // Reserve the same two-digit hour and AM/PM width in every Today row.
          // Hidden references size the localized column without truncating large text.
          ForEach([11, 23], id: \.self) { hour in
            label(
              presentation.calendar.date(bySettingHour: hour, minute: 58, second: 0, of: date)
                ?? date
            ).hidden()
          }
        }
        label(date)
      }
      .font(.caption.monospacedDigit())
      .foregroundStyle(.secondary)
      .lineLimit(1)
      .fixedSize()
      .frame(minWidth: compact ? AgendaRowStyle.timeWidth : 58, alignment: .leading)
    }
  }

  /// Title and detail share at most two lines, including at accessibility text sizes.
  package struct TitleDetail<Detail: View>: View {
    package init(title: Text, hasDetail: Bool = true, @ViewBuilder detail: () -> Detail) {
      self.title = title
      self.hasDetail = hasDetail
      self.detail = detail()
    }
    package let title: Text
    package let hasDetail: Bool
    @ViewBuilder package var detail: Detail

    @ViewBuilder package var body: some View {
      if hasDetail {
        ViewThatFits(in: .horizontal) {
          HStack(alignment: .firstTextBaseline, spacing: 8) {
            title.lineLimit(1)
            detail.lineLimit(1)
          }
          VStack(alignment: .leading, spacing: 1) {
            title.lineLimit(1)
            detail.lineLimit(1)
          }
        }
      } else {
        title.lineLimit(2)
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
    @Environment(PlannerPresentation.self) private var presentation
    package var body: some View {
      HStack(spacing: 8) {
        Text(
          "Now "
            + date.formatted(
              Date.FormatStyle(
                date: .omitted, time: .shortened, locale: presentation.locale,
                calendar: presentation.calendar, timeZone: presentation.calendar.timeZone))
        )
        .font(.caption.weight(.semibold).monospacedDigit())
        .foregroundStyle(.red)
        Rectangle().fill(Color.red).frame(height: 1)
      }
      .listRowSeparator(.hidden)
      .listRowInsets(EdgeInsets(top: 2, leading: 20, bottom: 2, trailing: 20))
    }
  }

#endif

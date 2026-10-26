#if os(iOS)
  import SwiftUI
  import TodayCore

  package struct WeekStrip: View {
    /// `calendar` sets the first day of the week; without it the week starts on Monday.
    package init(selected: Binding<Date>, calendar: Calendar? = nil) {
      _selected = selected
      self.calendar = calendar
    }
    @Binding package var selected: Date
    private let calendar: Calendar?
    @Environment(PlannerPresentation.self) private var presentation
    @Environment(\.colorScheme) private var colorScheme

    private var cal: Calendar {
      if let calendar { return calendar }
      var c = presentation.calendar
      c.firstWeekday = 2  // Monday
      return c
    }

    private var weekDays: [Date] {
      let start = cal.dateInterval(of: .weekOfYear, for: selected)?.start ?? selected
      return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    package var body: some View {
      let now = presentation.now
      return HStack(spacing: 2) {
        Button {
          shift(-7)
        } label: {
          Image(systemName: "chevron.left").padding(6)
        }
        .accessibilityLabel("Previous week")
        ForEach(weekDays, id: \.self) { d in
          let isSelected = cal.isDate(d, inSameDayAs: selected)
          Button {
            selected = cal.startOfDay(for: d)
          } label: {
            VStack(spacing: 4) {
              Text(
                d.formatted(
                  Date.FormatStyle(
                    locale: presentation.locale, calendar: cal, timeZone: cal.timeZone
                  ).weekday(.narrow))
              )
              .font(.caption2)
              .foregroundStyle(.secondary)
              Text("\(cal.component(.day, from: d))")
                .font(.callout.weight(isSelected ? .bold : .regular))
                .frame(width: 32, height: 32)
                .background(isSelected ? Color.accentColor : Color.clear, in: Circle())
                .foregroundStyle(
                  isSelected
                    ? Color.accentColor.contrastForeground(for: colorScheme)
                    : (cal.isDate(d, inSameDayAs: now) ? Color.accentColor : Color.primary))
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
          }
          .accessibilityLabel(
            d.formatted(
              Date.FormatStyle(locale: presentation.locale, calendar: cal, timeZone: cal.timeZone)
                .weekday(.wide).month(.wide).day())
          )
          .accessibilityAddTraits(isSelected ? .isSelected : [])
          .accessibilityIdentifier("weekStrip." + Self.key(d, cal))
        }
        Button {
          shift(7)
        } label: {
          Image(systemName: "chevron.right").padding(6)
        }
        .accessibilityLabel("Next week")
      }
      .buttonStyle(.borderless)
      .tint(.primary)
    }

    /// "weekStrip.2026-10-26": a stable handle for UI tests.
    private static func key(_ d: Date, _ cal: Calendar) -> String {
      let c = cal.dateComponents([.year, .month, .day], from: d)
      return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private func shift(_ days: Int) {
      if let d = cal.date(byAdding: .day, value: days, to: selected) { selected = d }
    }
  }

/// The title itself is the edit affordance, shared by full cards and compact rows.
/// Draft text is local to the sheet until Save; Add remains a separate decision.

#endif

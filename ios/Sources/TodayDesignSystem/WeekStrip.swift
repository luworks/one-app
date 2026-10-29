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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var dragging = false
    @State private var swipe = WeekStripSwipe()
    @State private var feedback = 0
    @State private var offset: CGFloat = 0
    @State private var outgoing: Date?
    @State private var direction: CGFloat = 0

    private var cal: Calendar {
      if let calendar { return calendar }
      var c = presentation.calendar
      c.firstWeekday = 2  // Monday
      return c
    }

    private func weekDays(containing day: Date) -> [Date] {
      let start = cal.dateInterval(of: .weekOfYear, for: day)?.start ?? day
      return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    package var body: some View {
      GeometryReader { geometry in
        let width = geometry.size.width
        ZStack {
          ForEach(-1...1, id: \.self) { index in
            if let day = cal.date(byAdding: .day, value: index * 7, to: outgoing ?? selected) {
              let active = index == (outgoing == nil ? 0 : Int(-direction))
              week(day, selectedDay: selected)
                .frame(width: width)
                .offset(x: CGFloat(index) * width + offset)
                .accessibilityHidden(!active)
                .allowsHitTesting(active && outgoing == nil)
            }
          }
        }
        .frame(width: width, height: 52)
        .clipped()
        .contentShape(Rectangle())
        .simultaneousGesture(
          DragGesture(minimumDistance: 10)
            .updating($dragging) { _, state, _ in state = true }
            .onChanged { value in
              guard outgoing == nil else { return }
              let x = value.translation.width
              let y = value.translation.height
              if let weeks = swipe.update(x: x, y: y) {
                guard let next = cal.date(byAdding: .day, value: weeks * 7, to: selected) else { return }
                feedback += 1
                if reduceMotion {
                  selected = next
                  offset = 0
                } else {
                  outgoing = selected
                  selected = next
                  direction = weeks > 0 ? -1 : 1
                  offset = direction * min(abs(x), 36)
                  withAnimation(.easeOut(duration: 0.22), completionCriteria: .logicallyComplete) {
                    offset = direction * width
                  } completion: {
                    outgoing = nil
                    offset = 0
                  }
                }
              } else if !swipe.hasCommitted && !reduceMotion {
                offset = abs(x) > abs(y) ? max(-36, min(36, x)) : 0
              }
            }
        )
        .onChange(of: dragging) { _, active in
          if !active {
            swipe.reset()
            if outgoing == nil {
              withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) { offset = 0 }
            }
          }
        }
      }
      .frame(height: 52)
      .sensoryFeedback(.selection, trigger: feedback)
      .accessibilityElement(children: .contain)
      .accessibilityAction(named: "Previous week") { shift(-7) }
      .accessibilityAction(named: "Next week") { shift(7) }
      .buttonStyle(.borderless)
      .tint(.primary)
    }

    private func week(_ day: Date, selectedDay: Date?) -> some View {
      let now = presentation.now
      return HStack(spacing: 2) {
        ForEach(weekDays(containing: day), id: \.self) { d in
          let isSelected = selectedDay.map { cal.isDate(d, inSameDayAs: $0) } ?? false
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
      }
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

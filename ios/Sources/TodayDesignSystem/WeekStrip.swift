#if os(iOS)
import SwiftUI
import TodayCore

struct WeekStrip: View {
    @Binding var selected: Date

    private var cal: Calendar {
        var c = Calendar.current
        c.firstWeekday = 2 // Monday
        return c
    }

    private var days: [Date] {
        let start = cal.dateInterval(of: .weekOfYear, for: selected)?.start ?? selected
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    var body: some View {
        HStack(spacing: 2) {
            Button { shift(-7) } label: { Image(systemName: "chevron.left").padding(6) }
            ForEach(days, id: \.self) { d in
                let isSelected = cal.isDate(d, inSameDayAs: selected)
                Button {
                    selected = cal.startOfDay(for: d)
                } label: {
                    VStack(spacing: 4) {
                        Text(d.formatted(.dateTime.weekday(.narrow)))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(Calendar.current.component(.day, from: d))")
                            .font(.callout.weight(isSelected ? .bold : .regular))
                            .frame(width: 32, height: 32)
                            .background(isSelected ? Color.accentColor : Color.clear, in: Circle())
                            .foregroundStyle(isSelected ? Color.white : (cal.isDateInToday(d) ? Color.accentColor : Color.primary))
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
            }
            Button { shift(7) } label: { Image(systemName: "chevron.right").padding(6) }
        }
        .buttonStyle(.borderless)
        .tint(.primary)
    }

    private func shift(_ days: Int) {
        if let d = cal.date(byAdding: .day, value: days, to: selected) { selected = d }
    }
}

/// The title itself is the edit affordance, shared by full cards and compact rows.
/// Draft text is local to the sheet until Save; Add remains a separate decision.

#endif

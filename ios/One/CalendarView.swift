import SwiftUI
import SwiftData

/// Calendar tab: Day (agenda), Week (time grid) and Month (grid) views, like Apple Calendar.
struct CalendarView: View {
    enum Mode: String, CaseIterable { case day = "Day", week = "Week", month = "Month" }

    @Binding var day: Date
    @State private var mode: Mode = .day

    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.bottom, 6)

            switch mode {
            case .day:
                DayAgenda(day: $day, showsWeekStrip: true)
            case .week:
                WeekGrid(day: $day) { picked in
                    day = picked
                    withAnimation(.snappy) { mode = .day }
                }
            case .month:
                MonthGrid(day: $day) { picked in
                    day = picked
                    withAnimation(.snappy) { mode = .day }
                }
            }
        }
    }
}

private var mondayCalendar: Calendar {
    var c = Calendar.current
    c.firstWeekday = 2
    return c
}

// MARK: - Week

/// 7-day time grid. Events are solid blue blocks (fixed); planned tasks are accent outlines (flexible).
struct WeekGrid: View {
    @Binding var day: Date
    var onPickDay: (Date) -> Void

    @Query(sort: \OneEvent.start) private var events: [OneEvent]
    @Query private var tasks: [OneTask]

    private let hourHeight: CGFloat = 48
    private let gutter: CGFloat = 40
    private let cal = mondayCalendar

    private var days: [Date] {
        let start = cal.dateInterval(of: .weekOfYear, for: day)?.start ?? day
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            allDayStrip
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    GeometryReader { geo in
                        let colWidth = (geo.size.width - gutter) / 7
                        ZStack(alignment: .topLeading) {
                            ForEach(0..<24, id: \.self) { h in
                                HStack(alignment: .top, spacing: 4) {
                                    Text(hourLabel(h))
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                        .frame(width: gutter - 4, alignment: .trailing)
                                        .offset(y: -6)
                                    Rectangle().fill(Color(.separator)).frame(height: 0.5)
                                }
                                .offset(y: CGFloat(h) * hourHeight)
                                .id(h)
                            }
                            ForEach(Array(days.enumerated()), id: \.offset) { index, d in
                                let x = gutter + CGFloat(index) * colWidth
                                ForEach(blocks(on: d), id: \.id) { b in
                                    block(b)
                                        .frame(width: colWidth - 2, height: max(18, b.height(hourHeight)))
                                        .offset(x: x + 1, y: b.y(hourHeight))
                                }
                                if cal.isDateInToday(d) {
                                    let y = minutes(Date.now) / 60 * hourHeight
                                    Rectangle().fill(Color.red).frame(width: colWidth, height: 1.5)
                                        .offset(x: x, y: y)
                                }
                            }
                        }
                    }
                    .frame(height: 24 * hourHeight)
                    .padding(.trailing, 8)
                    .padding(.top, 8)
                }
                .defaultScrollAnchor(UnitPoint(x: 0, y: 7.0 / 24))
            }
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            Button { shift(-7) } label: { Image(systemName: "chevron.left").frame(width: gutter, height: 44) }
                .tint(.primary)
            ForEach(days, id: \.self) { d in
                Button { onPickDay(cal.startOfDay(for: d)) } label: {
                    VStack(spacing: 2) {
                        Text(d.formatted(.dateTime.weekday(.narrow)))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(Calendar.current.component(.day, from: d))")
                            .font(.subheadline.weight(cal.isDateInToday(d) ? .bold : .regular))
                            .frame(width: 28, height: 28)
                            .background(cal.isDateInToday(d) ? Color.accentColor : .clear, in: Circle())
                            .foregroundStyle(cal.isDateInToday(d) ? Color.white : Color.primary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
            Button { shift(7) } label: { Image(systemName: "chevron.right").frame(width: 32, height: 44) }
                .tint(.primary)
        }
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var allDayStrip: some View {
        let items = days.map { d in events.filter { $0.isAllDay && !$0.occurs(on: d).isEmpty } }
        if items.contains(where: { !$0.isEmpty }) {
            HStack(alignment: .top, spacing: 0) {
                Text("all-day")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: gutter)
                ForEach(Array(items.enumerated()), id: \.offset) { _, list in
                    VStack(spacing: 2) {
                        ForEach(list) { e in
                            Text(e.title)
                                .font(.caption2)
                                .lineLimit(1)
                                .padding(.horizontal, 3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.blue.opacity(0.2), in: RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 1)
                }
            }
            .padding(.trailing, 8)
            .padding(.bottom, 4)
        }
    }

    struct Block {
        let id: String
        let title: String
        let startMinute: CGFloat
        let lengthMinutes: CGFloat
        let isTask: Bool
        func y(_ hourHeight: CGFloat) -> CGFloat { startMinute / 60 * hourHeight }
        func height(_ hourHeight: CGFloat) -> CGFloat { lengthMinutes / 60 * hourHeight - 1 }
    }

    private func blocks(on d: Date) -> [Block] {
        var result: [Block] = []
        for e in events where !e.isAllDay {
            for start in e.occurs(on: d) where cal.isDate(start, inSameDayAs: d) {
                result.append(Block(id: "e\(e.persistentModelID.hashValue)-\(start.timeIntervalSince1970)",
                                    title: e.title, startMinute: minutes(start),
                                    lengthMinutes: CGFloat(e.durationMinutes), isTask: false))
            }
        }
        for t in tasks where !t.isDone {
            if let s = t.plannedStart, cal.isDate(s, inSameDayAs: d) {
                result.append(Block(id: "t\(t.persistentModelID.hashValue)", title: t.title, startMinute: minutes(s),
                                    lengthMinutes: CGFloat(t.durationMinutes), isTask: true))
            }
        }
        return result
    }

    @ViewBuilder
    private func block(_ b: Block) -> some View {
        Text(b.title)
            .font(.system(size: 10, weight: .medium))
            .lineLimit(3)
            .padding(3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(b.isTask ? Color.accentColor.opacity(0.12) : Color.blue.opacity(0.22),
                        in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4)
                .strokeBorder(b.isTask ? Color.accentColor : .clear, lineWidth: 1))
    }

    private func minutes(_ date: Date) -> CGFloat {
        let c = cal.dateComponents([.hour, .minute], from: date)
        return CGFloat((c.hour ?? 0) * 60 + (c.minute ?? 0))
    }

    private func hourLabel(_ h: Int) -> String {
        h == 0 ? "" : (cal.date(bySettingHour: h, minute: 0, second: 0, of: .now) ?? .now)
            .formatted(.dateTime.hour(.defaultDigits(amPM: .abbreviated)))
    }

    private func shift(_ n: Int) {
        if let d = cal.date(byAdding: .day, value: n, to: day) { day = d }
    }
}

// MARK: - Month

struct MonthGrid: View {
    @Binding var day: Date
    var onPickDay: (Date) -> Void

    @Query(sort: \OneEvent.start) private var events: [OneEvent]
    @Query private var tasks: [OneTask]

    private let cal = mondayCalendar

    private var month: DateInterval {
        cal.dateInterval(of: .month, for: day) ?? DateInterval(start: day, duration: 86400 * 30)
    }

    /// Cells for the grid: nil = padding before the 1st.
    private var cells: [Date?] {
        let first = month.start
        let weekday = cal.component(.weekday, from: first)
        let lead = (weekday - cal.firstWeekday + 7) % 7
        let count = cal.range(of: .day, in: .month, for: first)?.count ?? 30
        return Array(repeating: nil, count: lead) + (0..<count).compactMap { cal.date(byAdding: .day, value: $0, to: first) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                HStack {
                    Text(month.start.formatted(.dateTime.month(.wide).year()))
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Button { shift(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                    Button { shift(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                }
                .tint(.primary)
                .padding(.horizontal, 20)

                let symbols = Array(cal.veryShortWeekdaySymbols[(cal.firstWeekday - 1)...] + cal.veryShortWeekdaySymbols[..<(cal.firstWeekday - 1)])
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 4) {
                    ForEach(Array(symbols.enumerated()), id: \.offset) { _, s in
                        Text(s).font(.caption2).foregroundStyle(.secondary)
                    }
                    ForEach(Array(cells.enumerated()), id: \.offset) { _, d in
                        if let d {
                            Button { onPickDay(d) } label: { cell(d) }
                                .buttonStyle(.plain)
                        } else {
                            Color.clear.frame(height: 52)
                        }
                    }
                }
                .padding(.horizontal, 12)
            }
        }
    }

    private func cell(_ d: Date) -> some View {
        let isToday = cal.isDateInToday(d)
        let eventCount = events.reduce(0) { $0 + $1.occurs(on: d).count }
        let taskCount = tasks.filter { t in
            !t.isDone && ((t.plannedStart.map { cal.isDate($0, inSameDayAs: d) } ?? false)
                || (t.due.map { cal.isDate($0, inSameDayAs: d) } ?? false))
        }.count
        return VStack(spacing: 4) {
            Text("\(Calendar.current.component(.day, from: d))")
                .font(.subheadline.weight(isToday ? .bold : .regular))
                .frame(width: 30, height: 30)
                .background(isToday ? Color.accentColor : .clear, in: Circle())
                .foregroundStyle(isToday ? Color.white : Color.primary)
            HStack(spacing: 3) {
                ForEach(0..<min(eventCount, 3), id: \.self) { _ in Circle().fill(Color.blue).frame(width: 5, height: 5) }
                ForEach(0..<min(taskCount, 2), id: \.self) { _ in Circle().fill(Color.accentColor).frame(width: 5, height: 5) }
            }
            .frame(height: 6)
        }
        .frame(maxWidth: .infinity, minHeight: 52)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(d.formatted(date: .complete, time: .omitted)), \(eventCount) events, \(taskCount) tasks")
    }

    private func shift(_ months: Int) {
        if let d = cal.date(byAdding: .month, value: months, to: day) { day = d }
    }
}

import SwiftUI
import Charts

/// The saved World Clock cities (time zone identifiers, in the user's order), kept in UserDefaults. The home city
/// (the device's time zone) is not stored: it is always shown first. A singleton, so the list survives leaving the tab.
/// UI tests start empty (or from `-uiTestingCities a,b`).
@MainActor
@Observable
final class WorldClockStore {
    static let shared = WorldClockStore()
    static let defaultsKey = "today.worldClock.cities"

    private(set) var identifiers: [String]
    /// The overlap chart is open (not saved: World Clock opens on the plain list).
    var showsOverlap = false

    private init() {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-uiTesting") {
            UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
            if let i = args.firstIndex(of: "-uiTestingCities"), i + 1 < args.count {
                identifiers = args[i + 1].split(separator: ",").map(String.init)
            } else {
                identifiers = []
            }
        } else {
            identifiers = WorldClock.load(UserDefaults.standard.stringArray(forKey: Self.defaultsKey),
                                          known: Set(TimeZone.knownTimeZoneIdentifiers))
        }
    }

    /// The device's time zone: the starred first card.
    var home: String { TimeZone.current.identifier }

    /// The cities after home, in the user's order.
    var others: [String] { WorldClock.others(identifiers, home: home) }

    func add(_ identifier: String) { set(WorldClock.adding(identifier, to: identifiers)) }

    func remove(_ identifier: String) { set(identifiers.filter { $0 != identifier }) }

    func insert(_ identifier: String, at index: Int) {
        guard !identifiers.contains(identifier) else { return }
        var list = others
        list.insert(identifier, at: min(max(0, index), list.count))
        set(list)
    }

    /// Reorders the cities after home (`others` indices, as `List.onMove` gives them).
    func move(from source: IndexSet, to destination: Int) {
        set(WorldClock.moving(others, from: source, to: destination))
    }

    private func set(_ list: [String]) {
        identifiers = list
        UserDefaults.standard.set(list, forKey: Self.defaultsKey)
    }
}

/// World Clock, modeled on the app "Overlap": one card per city, tinted by the time of day there (night indigo,
/// morning and evening blue, working hours green), home first with a star. Drag sideways anywhere on the list to move
/// every clock together in 15-minute steps; the capsule at the bottom says how far ("3 hours from now") and a tap on it
/// goes back to now. "Overlap" shows the hours today when every city is within working hours.
/// No Edit button (editing works as everywhere in the app): a long press on a city offers Move Up / Move Down and
/// Delete, and press, hold and drag reorders (the sideways swipe belongs to scrubbing). + adds a city.
struct WorldClockView: View {
    @Environment(UndoToast.self) private var toast: UndoToast?
    @State private var store = WorldClockStore.shared
    /// Minutes away from now; 0 = now.
    @State private var scrub = 0
    @State private var dragStart: Int?

    var body: some View {
        TimelineView(.everyMinute) { context in
            let date = WorldClock.Scrub.date(now: context.date, offset: scrub)
            List {
                controlsRow
                if store.showsOverlap { overlapRow(date: date, now: context.date) }
                CityCard(identifier: store.home, date: date, isHome: true)
                    .moveDisabled(true)
                    .deleteDisabled(true)
                // A sideways drag scrubs time, so there is no swipe-to-delete here: Delete and the order are in the
                // long-press menu, and a press, hold and drag reorders.
                ForEach(store.others, id: \.self) { id in
                    CityCard(identifier: id, date: date, isHome: false)
                        .contextMenu { cityMenu(id) }
                        .plainClockRow(top: 5, bottom: 5)
                        .deleteDisabled(true)
                }
                .onMove { store.move(from: $0, to: $1) }
                if store.others.isEmpty { hint }
            }
            .listStyle(.plain)
            .gesture(HorizontalPan(onChange: dragged, onEnd: { dragStart = nil }))
            .safeAreaInset(edge: .bottom, spacing: 0) { scrubCapsule }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: scrub)
    }

    // MARK: Scrubbing

    private func dragged(_ width: CGFloat) {
        if dragStart == nil { dragStart = scrub }
        let next = WorldClock.Scrub.offset(start: dragStart ?? 0, dragWidth: Double(width))
        if next != scrub { scrub = next }
    }

    private var scrubCapsule: some View {
        Button {
            withAnimation(.snappy) { scrub = 0 }
        } label: {
            HStack(spacing: 6) {
                if scrub != 0 { Image(systemName: "arrow.uturn.backward").font(.footnote.weight(.semibold)) }
                Text(WorldClock.Scrub.label(scrub))
                    .contentTransition(.numericText())
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(scrub == 0 ? Color.secondary : Color.primary)
            .padding(.horizontal, 16)
            .frame(minHeight: 36)
            .glassCapsule()
        }
        .buttonStyle(PressScale())
        .disabled(scrub == 0)
        .accessibilityLabel(WorldClock.Scrub.label(scrub))
        .accessibilityHint(scrub == 0 ? "Drag sideways on the cities to see other times." : "Goes back to now.")
        .accessibilityIdentifier("worldClock.scrub")
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
    }

    // MARK: Rows

    /// The Overlap switch. No Edit button: a city's long-press menu reorders and deletes.
    private var controlsRow: some View {
        HStack {
            PillButton(title: "Overlap", icon: "chart.line.uptrend.xyaxis", isSelected: store.showsOverlap,
                       identifier: "worldClock.overlap") {
                withAnimation(PillStyle.selectionAnimation) { store.showsOverlap.toggle() }
            }
            Spacer()
        }
        .plainClockRow(top: 2, bottom: 6)
        .moveDisabled(true)
        .deleteDisabled(true)
    }

    private func overlapRow(date: Date, now: Date) -> some View {
        OverlapCard(home: store.home, others: store.others, date: date) { start in
            // Tap the card: scrub to the start of the overlap.
            let minutes = Int(start.timeIntervalSince(now) / 60)
            withAnimation(.snappy) { scrub = WorldClock.Scrub.clamp(WorldClock.Scrub.snap(minutes)) }
        }
        .plainClockRow(top: 0, bottom: 8)
        .moveDisabled(true)
        .deleteDisabled(true)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var hint: some View {
        Text("Tap + to add a city. Drag sideways to see their time later or earlier.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
            .accessibilityIdentifier("worldClock.hint")
            .plainClockRow(top: 0, bottom: 0)
            .moveDisabled(true)
            .deleteDisabled(true)
    }

    /// A city's long-press menu: move it up or down among your cities (home stays first), or delete it.
    @ViewBuilder
    private func cityMenu(_ id: String) -> some View {
        let i = store.others.firstIndex(of: id) ?? 0
        Button { withAnimation(.snappy) { store.move(from: [i], to: i - 1) } } label: {
            Label("Move Up", systemImage: "arrow.up")
        }
        .disabled(i == 0)
        Button { withAnimation(.snappy) { store.move(from: [i], to: i + 2) } } label: {
            Label("Move Down", systemImage: "arrow.down")
        }
        .disabled(i >= store.others.count - 1)
        Divider()
        RowAction.delete { remove(id) }
    }

    private func remove(_ id: String) {
        guard let index = store.others.firstIndex(of: id) else { return }
        withAnimation(.snappy) { store.remove(id) }
        let name = WorldClock.cityName(fromIdentifier: id) ?? id
        toast?.show("Removed \(name)") {
            withAnimation(.snappy) { store.insert(id, at: index) }
        }
    }
}

private extension View {
    func plainClockRow(top: CGFloat, bottom: CGFloat) -> some View {
        listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: top, leading: 16, bottom: bottom, trailing: 16))
    }
}

/// A sideways pan that starts only when the finger moves clearly sideways, and runs alongside the list's own
/// scrolling, so vertical scrolling stays untouched.
private struct HorizontalPan: UIGestureRecognizerRepresentable {
    var onChange: (CGFloat) -> Void
    var onEnd: () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        return pan
    }

    func handleUIGestureRecognizerAction(_ pan: UIPanGestureRecognizer, context: Context) {
        switch pan.state {
        case .began, .changed: onChange(pan.translation(in: pan.view).x)
        case .ended, .cancelled, .failed: onEnd()
        default: break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard let pan = g as? UIPanGestureRecognizer else { return true }
            let v = pan.velocity(in: pan.view)
            return abs(v.x) > abs(v.y) * 1.5
        }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}

/// The card colors per time of day: deep in dark mode, a little lighter in light mode; white text on both.
private enum BandStyle {
    static func gradient(_ band: WorldClock.DayBand, dark: Bool) -> LinearGradient {
        let (top, bottom) = colors(band, dark: dark)
        return LinearGradient(colors: [top, bottom], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private static func colors(_ band: WorldClock.DayBand, dark: Bool) -> (Color, Color) {
        switch (band, dark) {
        case (.night, false): (Color(red: 0.31, green: 0.29, blue: 0.58), Color(red: 0.22, green: 0.20, blue: 0.46))
        case (.night, true): (Color(red: 0.18, green: 0.16, blue: 0.38), Color(red: 0.11, green: 0.10, blue: 0.27))
        case (.morning, false), (.evening, false): (Color(red: 0.35, green: 0.57, blue: 0.86), Color(red: 0.27, green: 0.47, blue: 0.78))
        case (.morning, true), (.evening, true): (Color(red: 0.14, green: 0.32, blue: 0.57), Color(red: 0.09, green: 0.23, blue: 0.45))
        case (.work, false): (Color(red: 0.33, green: 0.68, blue: 0.48), Color(red: 0.24, green: 0.58, blue: 0.40))
        case (.work, true): (Color(red: 0.13, green: 0.42, blue: 0.27), Color(red: 0.08, green: 0.32, blue: 0.20))
        }
    }
}

/// One city: "+3 hrs · Sat, Oct 18" and the name on the left, its time big and light on the right, on a card tinted
/// by the time of day there. Home has a star instead of the offset.
private struct CityCard: View {
    let identifier: String
    let date: Date
    let isHome: Bool

    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .largeTitle) private var timeSize = 44
    @ScaledMetric(relativeTo: .title) private var suffixSize = 22

    private var zone: TimeZone { TimeZone(identifier: identifier) ?? .current }
    private var name: String { WorldClock.cityName(fromIdentifier: identifier) ?? zone.localizedName(for: .generic, locale: .current) ?? identifier }
    private var band: WorldClock.DayBand { .init(zone: zone, at: date) }
    private var offset: String { WorldClock.offsetText(zone: zone, local: .current, at: date) }
    private var dateText: String { WorldClock.dateText(zone: zone, at: date) }
    private var parts: (time: String, suffix: String?) {
        let hm = WorldClock.hourMinute(zone: zone, at: date)
        return AlarmPlan.timeParts(hour: hm.hour, minute: hm.minute)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if isHome { Image(systemName: "star.fill").font(.caption2) }
                    Text((isHome ? "Home" : offset) + " · " + dateText)
                }
                .font(.subheadline)
                .opacity(0.85)
                Text(name)
                    .font(.title2.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 8)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(parts.time)
                    .font(.system(size: timeSize, weight: .light).monospacedDigit())
                    .contentTransition(.numericText())
                if let suffix = parts.suffix {
                    Text(suffix).font(.system(size: suffixSize, weight: .regular))
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.5)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(BandStyle.gradient(band, dark: colorScheme == .dark), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .animation(.easeInOut(duration: 0.35), value: band)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), \(isHome ? "Home" : offset), \(WorldClock.dayLabel(zone: zone, local: .current, at: date)), \(parts.time) \(parts.suffix ?? "")")
        .accessibilityIdentifier(isHome ? "worldClock.home" : "worldClock.row")
    }
}

/// When everyone is at work: a smooth wave of how many cities are within working hours across the home day, the
/// overlap shaded, a line at the time shown, and "Overlap for Dallas, Boston and 1 more when it's 08:00 in San Jose".
/// Tapping it moves the clocks to the start of the overlap.
private struct OverlapCard: View {
    let home: String
    let others: [String]
    let date: Date
    let jump: (Date) -> Void

    private var homeZone: TimeZone { TimeZone(identifier: home) ?? .current }
    private var zones: [TimeZone] { others.compactMap(TimeZone.init(identifier:)) }
    private func name(_ id: String) -> String { WorldClock.cityName(fromIdentifier: id) ?? id }

    var body: some View {
        let overlap = WorldClock.overlap(zones, home: homeZone, on: date)
        let curve = WorldClock.workCurve(zones, home: homeZone, on: date, stepMinutes: 30)
        let total = zones.count + 1
        VStack(alignment: .leading, spacing: 10) {
            if others.isEmpty {
                Text("Add a city to see when your working hours overlap.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text(WorldClock.overlapSentence(cities: others.map(name), home: name(home), homeZone: homeZone, overlap: overlap))
                    .font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("worldClock.overlapText")
                Chart {
                    ForEach(curve, id: \.date) { point in
                        AreaMark(x: .value("Time", point.date), y: .value("Working", point.count))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(LinearGradient(colors: [Color(.systemGreen).opacity(0.55), Color(.systemGreen).opacity(0.08)],
                                                            startPoint: .top, endPoint: .bottom))
                    }
                    ForEach(overlap, id: \.start) { window in
                        RectangleMark(xStart: .value("Start", window.start), xEnd: .value("End", window.end))
                            .foregroundStyle(Color(.systemGreen).opacity(0.22))
                    }
                    RuleMark(x: .value("Shown", date))
                        .foregroundStyle(Color.primary.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
                .chartYScale(domain: 0...total)
                .chartYAxis(.hidden)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                        AxisGridLine().foregroundStyle(Color.secondary.opacity(0.2))
                        AxisValueLabel(format: .dateTime.hour())
                    }
                }
                .frame(height: 84)
                .accessibilityHidden(true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onTapGesture { if let start = overlap.first?.start { jump(start) } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(overlap.isEmpty ? [] : .isButton)
        .accessibilityHint(overlap.isEmpty ? "" : "Moves the clocks to the start of the overlap.")
        .accessibilityIdentifier("worldClock.overlapCard")
    }
}

/// Add a city: every time zone with a place name, searchable, A to Z. Cities already shown (home included) are checked.
struct CityPicker: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = WorldClockStore.shared
    @State private var query = ""

    private static let all = WorldClock.cities(from: TimeZone.knownTimeZoneIdentifiers)

    var body: some View {
        let results = WorldClock.search(query, in: Self.all)
        NavigationStack {
            List(results) { city in
                let added = city.identifier == store.home || store.identifiers.contains(city.identifier)
                Button {
                    store.add(city.identifier)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(city.name).foregroundStyle(added ? .secondary : .primary)
                            if let zoneName = TimeZone(identifier: city.identifier)?.localizedName(for: .generic, locale: .current) {
                                Text(zoneName).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                        if added { Image(systemName: "checkmark").foregroundStyle(.secondary) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(added)
                .accessibilityIdentifier("city." + city.identifier)
            }
            .listStyle(.plain)
            .overlay {
                if results.isEmpty { ContentUnavailableView.search(text: query) }
            }
            .navigationTitle("Choose a City")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}

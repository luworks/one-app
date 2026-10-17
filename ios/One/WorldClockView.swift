import SwiftUI

/// The saved World Clock cities (time zone identifiers, in the user's order), kept in UserDefaults.
/// A singleton, so the list survives leaving the Alarms tab. UI tests start empty (or from `-uiTestingCities a,b`).
@MainActor
@Observable
final class WorldClockStore {
    static let shared = WorldClockStore()
    static let defaultsKey = "today.worldClock.cities"

    private(set) var identifiers: [String]

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

    func add(_ identifier: String) { set(WorldClock.adding(identifier, to: identifiers)) }

    func remove(_ identifier: String) { set(identifiers.filter { $0 != identifier }) }

    func insert(_ identifier: String, at index: Int) {
        guard !identifiers.contains(identifier) else { return }
        var list = identifiers
        list.insert(identifier, at: min(max(0, index), list.count))
        set(list)
    }

    func move(from source: IndexSet, to destination: Int) {
        set(WorldClock.moving(identifiers, from: source, to: destination))
    }

    private func set(_ list: [String]) {
        identifiers = list
        UserDefaults.standard.set(list, forKey: Self.defaultsKey)
    }
}

/// World Clock, as in Apple's Clock app: each city with "Today, +3 hrs" and its time, big and light like the alarm rows.
/// Swipe left to delete (with Undo), Edit to reorder. The bottom-right + adds a city.
struct WorldClockView: View {
    @Environment(UndoToast.self) private var toast: UndoToast?
    @State private var store = WorldClockStore.shared
    @State private var editMode: EditMode = .inactive

    var body: some View {
        // Redrawn on the minute; the offsets and day labels follow daylight saving changes too.
        TimelineView(.everyMinute) { context in
            List {
                if store.identifiers.isEmpty {
                    emptyState
                } else {
                    editRow
                    ForEach(store.identifiers, id: \.self) { id in
                        CityRow(identifier: id, now: context.date, isEditing: editMode.isEditing)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                RowAction.delete { remove(id) }
                            }
                    }
                    .onMove { store.move(from: $0, to: $1) }
                    .onDelete { offsets in offsets.map { store.identifiers[$0] }.forEach(remove) }
                }
            }
            .listStyle(.plain)
            .environment(\.editMode, $editMode)
        }
        .onChange(of: store.identifiers.isEmpty) { _, empty in if empty { editMode = .inactive } }
    }

    /// Clock has Edit in its navigation bar; this tab has none, so it sits on its own row above the cities.
    private var editRow: some View {
        HStack {
            Spacer()
            Button(editMode.isEditing ? "Done" : "Edit") {
                withAnimation(.snappy) { editMode = editMode.isEditing ? .inactive : .active }
            }
            .font(.body.weight(editMode.isEditing ? .semibold : .regular))
            .accessibilityIdentifier("worldClock.edit")
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
        .moveDisabled(true)
        .deleteDisabled(true)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "globe").font(.largeTitle).foregroundStyle(.secondary)
            Text("No World Clocks").font(.title3.weight(.semibold))
            Text("Tap + to add a city.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("worldClock.empty")
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private func remove(_ id: String) {
        guard let index = store.identifiers.firstIndex(of: id) else { return }
        withAnimation(.snappy) { store.remove(id) }
        let name = WorldClock.cityName(fromIdentifier: id) ?? id
        toast?.show("Removed \(name)") {
            withAnimation(.snappy) { store.insert(id, at: index) }
        }
    }
}

/// "Today, +3 hrs" over the city name on the left, the city's time on the right.
private struct CityRow: View {
    let identifier: String
    let now: Date
    let isEditing: Bool

    @ScaledMetric(relativeTo: .largeTitle) private var timeSize = 48
    @ScaledMetric(relativeTo: .title) private var suffixSize = 26

    private var zone: TimeZone { TimeZone(identifier: identifier) ?? .current }
    private var name: String { WorldClock.cityName(fromIdentifier: identifier) ?? identifier }
    private var subtitle: String { WorldClock.subtitle(zone: zone, local: .current, at: now) }
    private var parts: (time: String, suffix: String?) {
        let hm = WorldClock.hourMinute(zone: zone, at: now)
        return AlarmPlan.timeParts(hour: hm.hour, minute: hm.minute)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(name)
                    .font(.title2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 8)
            if !isEditing {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(parts.time)
                        .font(.system(size: timeSize, weight: .light).monospacedDigit())
                    if let suffix = parts.suffix {
                        Text(suffix).font(.system(size: suffixSize, weight: .regular))
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .transition(.opacity)
            }
        }
        .padding(.vertical, 6)
        .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), \(subtitle), \(parts.time) \(parts.suffix ?? "")")
        .accessibilityIdentifier("worldClock.row")
    }
}

/// Add a city: every time zone with a place name, searchable, A to Z. Cities already on the list are checked.
struct CityPicker: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = WorldClockStore.shared
    @State private var query = ""

    private static let all = WorldClock.cities(from: TimeZone.knownTimeZoneIdentifiers)

    var body: some View {
        NavigationStack {
            List(WorldClock.search(query, in: Self.all)) { city in
                let added = store.identifiers.contains(city.identifier)
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
                if WorldClock.search(query, in: Self.all).isEmpty { ContentUnavailableView.search(text: query) }
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

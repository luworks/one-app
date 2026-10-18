import SwiftUI

/// The Health sheet's state: which metrics are shown (saved), and their last 90 days from Apple Health (memory only).
/// Today never writes to Apple Health; nothing here goes to SwiftData, the widget snapshot or disk, except the choice
/// and order of metrics.
@MainActor
@Observable
final class HealthModel {
    static let days = 90

    private let source: HealthSource = HealthSources.current()
    private let store = HealthSelectionStore.shared
    private(set) var selection: HealthSelection
    private(set) var series: [HealthMetric: HealthSeries] = [:]
    /// False until the first load has answered, so the list does not flash "No data".
    private(set) var hasLoaded = false
    /// lb or kg, mi or km: what Apple Health is set to (the region until it has answered).
    private(set) var units = HealthUnits()

    init() { selection = HealthSelectionStore.shared.selection }

    var isAvailable: Bool { source.isAvailable }
    /// The page shows made-up numbers (UI tests and the simulator).
    var isSample: Bool { source is MockHealthSource }

    func load() async {
        guard source.isAvailable else { hasLoaded = true; return }
        await source.requestAccess(for: selection.shown)
        series = await source.series(for: selection.shown, days: Self.days, now: TodayClock.now)
        if let preferred = await source.preferredUnits() { units = preferred }
        hasLoaded = true
    }

    /// Adds metrics at the end, asks Apple Health for those types only (it skips the ones already allowed), loads them.
    func add(_ metrics: [HealthMetric]) async {
        guard !metrics.isEmpty else { return }
        update { $0.add(metrics) }
        await source.requestAccess(for: metrics)
        let loaded = await source.series(for: metrics, days: Self.days, now: TodayClock.now)
        series.merge(loaded) { _, new in new }
    }

    /// Hides the row only. Nothing is deleted from Apple Health.
    func hide(_ metric: HealthMetric) { update { $0.hide(metric) } }

    func move(in group: HealthGroup, from source: IndexSet, to destination: Int) {
        update { $0.move(in: group, from: source, to: destination) }
    }

    func nudge(_ metric: HealthMetric, by step: Int) { update { $0.nudge(metric, by: step) } }

    private func update(_ change: (inout HealthSelection) -> Void) {
        var next = selection
        change(&next)
        selection = next
        store.save(next)
    }

    func row(for metric: HealthMetric) -> HealthRowModel {
        HealthRowModel(metric: metric, series: series[metric], now: TodayClock.now, units: units)
    }
}

#if os(iOS)
import TodayCore
import TodayPlatform
import TodayDesignSystem
import SwiftUI

/// Reads Apple Health for the line at the top of Today. Health data stays in memory (never in SwiftData or the widget).
/// HealthKit permission is asked the first time the line would show, only for the metrics the line talks about; with
/// no data or no permission there is no line (Health never says which).
@MainActor
@Observable
public final class HealthLineModel {
    private let source: any HealthSource
    private let store: HealthSelectionStore
    private let defaults: UserDefaults
    private let runtime: PlannerRuntime
    private let gate: HealthAccessGate
    package private(set) var line: String?
    @ObservationIgnored nonisolated(unsafe) private var observer: NSObjectProtocol?

    public init(source: any HealthSource, store: HealthSelectionStore, defaults: UserDefaults, runtime: PlannerRuntime, gate: HealthAccessGate) {
        self.source = source
        self.store = store
        self.defaults = defaults
        self.runtime = runtime
        self.gate = gate
        // The line follows a changed choice of metrics (from the sheet or Settings), unless the line is switched off.
        observer = NotificationCenter.default.addObserver(forName: HealthSelectionStore.didChange, object: store, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.defaults.object(forKey: SettingsKey.healthSummary) as? Bool ?? true else { return }
                await self.load()
            }
        }
    }

    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    /// Answers that arrived during the current load (a stalled metric simply has none).
    private var arrived: [HealthMetric: HealthSeries] = [:]
    private var generation = 0
    private func note(_ metric: HealthMetric, _ series: HealthSeries, token: Int) {
        guard !Task.isCancelled, generation == token else { return }
        arrived[metric] = series
    }

    /// Never hangs and never blanks the line on a stall: the access request and each metric's query are bounded
    /// (`HealthLoader`), and a load where nothing answered leaves the line as it was.
    package func load() async {
        guard !Task.isCancelled, source.isAvailable else { return }
        generation += 1
        let token = generation
        let selection = store.selection
        let metrics = HealthLine.metrics(for: selection)
        guard !metrics.isEmpty else { line = nil; return }
        let now = runtime.now()
        arrived = [:]
        await HealthLoader.load(
            metrics, source: source, gate: gate, days: HealthSpark.days, now: now,
            onLateAccess: { [weak self] in Task { @MainActor in await self?.load() } },
            onResult: { [weak self] metric, result, _ in
                if case .series(let series) = result { await self?.note(metric, series, token: token) }
            })
        guard !Task.isCancelled, generation == token, !arrived.isEmpty else { return }
        let source = source
        let units: HealthUnits?
        if case .value(let preferred) = await HealthTimeout.race({ await source.preferredUnits() }) { units = preferred } else { units = nil }
        guard !Task.isCancelled, generation == token else { return }
        line = HealthLine.text(selection: selection, series: arrived, now: now, calendar: runtime.calendar, units: units ?? HealthUnits(locale: runtime.locale), locale: runtime.locale)
    }
}

/// One quiet line at the top of Today (today only): "6,240 steps · slept 7 hr 12 min". Tap opens the Health sheet (the
/// compact list of the metrics you chose). Read-only. Off with Settings → Today → Health summary.
package struct TodayHealthLine: View {
    let line: String
    package init(line: String) { self.line = line }
    @State private var showsDetail = false

    package var body: some View {
        Button { PerformanceTrace.shared.beginPage("health"); showsDetail = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "heart.fill").font(.caption2).foregroundStyle(HealthStyle.accent)
                Text(line).font(.footnote).foregroundStyle(.secondary).monospacedDigit()
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .frame(minHeight: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(line)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Shows your Health metrics")
        .accessibilityIdentifier("health.summary")
        .sheet(isPresented: $showsDetail) { HealthDetailSheet() }
    }
}

/// The Health list in a sheet, with Done.
package struct HealthDetailSheet: View {
    package init() {}
    @Environment(HealthModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    package var body: some View {
        NavigationStack {
            HealthView(model: model)
                .navigationTitle("Health")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDragIndicator(.visible)
    }
}

/// Settings → Today: "Health metrics" opens the same sheet, so the choice is reachable even on days the Today line has
/// nothing to say (or when every metric is hidden).
package struct HealthMetricsLink: View {
    package init() {}
    @State private var showsSheet = false

    package var body: some View {
        Button { PerformanceTrace.shared.beginPage("health"); showsSheet = true } label: {
            HStack {
                Text("Health metrics").foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
        .accessibilityIdentifier("settings.healthMetrics")
        .sheet(isPresented: $showsSheet) { HealthDetailSheet() }
    }
}

#endif

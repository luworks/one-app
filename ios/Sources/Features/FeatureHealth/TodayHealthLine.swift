import TodayCore
import TodayPlatform
import TodayDesignSystem
import SwiftUI

/// Reads Apple Health for the line at the top of Today. Health data stays in memory (never in SwiftData or the widget).
/// HealthKit permission is asked the first time the line would show, only for the metrics the line talks about; with
/// no data or no permission there is no line (Health never says which).
@MainActor
@Observable
final class HealthLineModel {
    private let source: any HealthSource
    private(set) var line: String?
    @ObservationIgnored nonisolated(unsafe) private var observer: NSObjectProtocol?

    init(source: any HealthSource) {
        self.source = source
        // The line follows a changed choice of metrics (from the sheet or Settings), unless the line is switched off.
        observer = NotificationCenter.default.addObserver(forName: HealthSelectionStore.didChange, object: nil, queue: .main) { [weak self] _ in
            guard UserDefaults.standard.object(forKey: SettingsKey.healthSummary) as? Bool ?? true else { return }
            Task { @MainActor in await self?.load() }
        }
    }

    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    /// Answers that arrived during the current load (a stalled metric simply has none).
    private var arrived: [HealthMetric: HealthSeries] = [:]
    private func note(_ metric: HealthMetric, _ series: HealthSeries) { arrived[metric] = series }

    /// Never hangs and never blanks the line on a stall: the access request and each metric's query are bounded
    /// (`HealthLoader`), and a load where nothing answered leaves the line as it was.
    func load() async {
        guard source.isAvailable else { return }
        let selection = HealthSelectionStore.shared.selection
        let metrics = HealthLine.metrics(for: selection)
        guard !metrics.isEmpty else { line = nil; return }
        let now = TodayClock.now
        arrived = [:]
        await HealthLoader.load(
            metrics, source: source, days: HealthSpark.days, now: now,
            onLateAccess: { [weak self] in Task { @MainActor in await self?.load() } },
            onResult: { [weak self] metric, result, _ in
                if case .series(let series) = result { await self?.note(metric, series) }
            })
        guard !arrived.isEmpty else { return }
        let source = source
        let units: HealthUnits?
        if case .value(let preferred) = await HealthTimeout.race({ await source.preferredUnits() }) { units = preferred } else { units = nil }
        line = HealthLine.text(selection: selection, series: arrived, now: now, units: units ?? HealthUnits())
    }
}

/// One quiet line at the top of Today (today only): "6,240 steps · slept 7 hr 12 min". Tap opens the Health sheet (the
/// compact list of the metrics you chose). Read-only. Off with Settings → Today → Health summary.
struct TodayHealthLine: View {
    let line: String
    @State private var showsDetail = false

    var body: some View {
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
struct HealthDetailSheet: View {
    @Environment(HealthModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
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
struct HealthMetricsLink: View {
    @State private var showsSheet = false

    var body: some View {
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

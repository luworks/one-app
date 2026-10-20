#if os(iOS)
  import SwiftUI
  import TodayCore
  import TodayDesignSystem
  import TodayPlatform

  /// The Health sheet's state: which metrics are shown (saved), and their chart history and trailing lookback from Apple Health (memory only).
  /// Today never writes to Apple Health; nothing here goes to SwiftData, the widget snapshot or disk, except the choice
  /// and order of metrics.
  ///
  /// Nothing here can hang the sheet: access requests and every metric's query run through `HealthLoader` with an 8 s
  /// timeout each. A row that is still waiting shows a spinner of its own; a row whose call stalled keeps its old data, or
  /// shows "—" with a quiet line and an action. The list itself is always on screen.
  @MainActor
  @Observable
  public final class HealthModel {
    public static let days = MovingAverage.historyDays

    private let source: any HealthSource
    private let store: HealthSelectionStore
    private let timeout: Double
    public let runtime: PlannerRuntime
    private let gate: HealthAccessGate
    public private(set) var selection: HealthSelection
    public private(set) var series: [HealthMetric: HealthSeries] = [:]
    /// Per metric: waiting, answered, or failed. A metric not listed has not started yet and counts as waiting.
    public private(set) var states: [HealthMetric: HealthMetricState] = [:]
    /// lb or kg, mi or km: what Apple Health is set to (the region until it has answered).
    public private(set) var units: HealthUnits
    /// The latest fetch started for each metric; an older fetch that answers late must not overwrite a newer answer.
    @ObservationIgnored private var generation: [HealthMetric: Int] = [:]

    @ObservationIgnored private var loadedDays: [HealthMetric: Int] = [:]
    @ObservationIgnored private var active: [HealthMetric: Int] = [:]

    /// App assembly owns one model for the Today line and every Health sheet. Workbench supplies its own source.
    public init(
      source: any HealthSource, store: HealthSelectionStore, runtime: PlannerRuntime,
      gate: HealthAccessGate, timeout: Double = HealthTimeout.seconds
    ) {
      self.source = source
      self.runtime = runtime
      self.gate = gate
      self.units = HealthUnits(locale: runtime.locale)
      self.store = store
      self.timeout = timeout
      selection = store.selection
    }

    public var recordSource: (any HealthRecordSource)? { source as? any HealthRecordSource }

    public var isAvailable: Bool { source.isAvailable }
    /// The page shows made-up numbers (UI tests and the simulator).
    public var isSample: Bool { source.isSample }

    public func state(for metric: HealthMetric) -> HealthMetricState { states[metric] ?? .loading }

    /// Opening the sheet, pull to refresh, and the app becoming active again (which also asks again for access that
    /// was never answered).
    public func load() async {
      guard !Task.isCancelled, source.isAvailable else { return }
      async let preferred: Void = refreshUnits()
      await run(selection.shown)
      await preferred
    }

    /// Existing Today lifecycle events refresh at most two metrics; active reads already supply their values.
    /// The computed summary only formats this model's state; it never starts a native query while rendering.
    package func loadSummary() async {
      let metrics = HealthLine.metrics(for: selection).filter {
        active[$0] == nil
      }
      guard !metrics.isEmpty else { return }
      async let preferred: Void = refreshUnits()
      await run(metrics, days: HealthSpark.days)
      await preferred
    }

    /// Adds metrics at the end, then asks Apple Health for those types only (the caller has dismissed the picker, so
    /// Apple's sheet can show), then reads them. The new rows are on screen at once, each with its own spinner.
    public func add(_ metrics: [HealthMetric]) async {
      let fresh = metrics.filter { !selection.shown.contains($0) }
      guard !fresh.isEmpty else { return }
      update { $0.add(fresh) }
      await run(fresh)
    }

    /// "Allow" / "Try Again" on one row.
    public func retry(_ metric: HealthMetric) async {
      states[metric] = .loading
      await run([metric])
    }

    /// Requests access (once per new batch of types), then reads each metric on its own.
    private func run(_ metrics: [HealthMetric], days: Int = HealthModel.days) async {
      guard !Task.isCancelled, !metrics.isEmpty else { return }
      for metric in metrics where states[metric] == nil { states[metric] = .loading }
      var tokens: [HealthMetric: Int] = [:]
      for metric in metrics {
        generation[metric, default: 0] += 1
        tokens[metric] = generation[metric]
        active[metric] = generation[metric]
      }
      let tokenSnapshot = tokens
      let now = runtime.now()
      defer {
        for metric in metrics where active[metric] == tokenSnapshot[metric] {
          active[metric] = nil
        }
        if Task.isCancelled {
          for metric in metrics
          where generation[metric] == tokenSnapshot[metric] && states[metric] == .loading {
            states[metric] = series[metric]?.points.isEmpty == false ? .loaded : .idle
          }
        }
      }
      await HealthLoader.load(
        metrics, source: source, gate: gate, days: days, now: now, timeout: timeout,
        onLateAccess: { [weak self] in
          // The permission sheet answered after the timeout: read what it allowed.
          Task { @MainActor in await self?.run(metrics, days: days) }
        },
        onResult: { [weak self] metric, result, access in
          await self?.apply(
            metric, result, access: access, token: tokenSnapshot[metric] ?? 0, days: days, now: now)
        })
    }

    private func apply(
      _ metric: HealthMetric, _ result: HealthFetchResult, access: HealthAccessOutcome, token: Int,
      days: Int, now: Date
    ) {
      guard !Task.isCancelled, generation[metric] == token else { return }
      if case .series(let incoming) = result {
        // A short refresh replaces its covered dates, preserving older chart history from a longer read.
        let window = HealthWindow(days: days, now: now, calendar: runtime.calendar)
        let retainedWindow = HealthWindow(
          days: max(loadedDays[metric] ?? 0, days), now: now, calendar: runtime.calendar)
        let older =
          series[metric]?.points.filter {
            $0.date >= retainedWindow.start && $0.date < window.start
          } ?? []
        series[metric] = HealthSeries(points: older + incoming.points)
        loadedDays[metric] = max(loadedDays[metric] ?? 0, days)
      }
      let hadData = series[metric].map { !$0.points.isEmpty } ?? false
      states[metric] = HealthMetricState.settled(result, access: access, hadData: hadData)
    }

    private func refreshUnits() async {
      let source = source
      if case .value(let preferred) = await HealthTimeout.race(
        seconds: timeout, { await source.preferredUnits() }), let preferred
      {
        guard !Task.isCancelled else { return }
        units = preferred
      }
    }

    /// Hides the row only. Nothing is deleted from Apple Health.
    public func hide(_ metric: HealthMetric) { update { $0.hide(metric) } }

    public func move(in group: HealthGroup, from source: IndexSet, to destination: Int) {
      update { $0.move(in: group, from: source, to: destination) }
    }

    public func move(from source: IndexSet, to destination: Int) {
      update { $0.move(from: source, to: destination) }
    }

    public func moveToTop(_ metric: HealthMetric) { update { $0.moveToTop(metric) } }

    /// Apply visibility and order together; permission requests only cover explicitly added metrics.
    public func customize(_ next: HealthSelection) async {
      let fresh = next.shown.filter { !selection.shown.contains($0) }
      update { $0 = next }
      if !fresh.isEmpty { await run(fresh) }
    }

    public func nudge(_ metric: HealthMetric, by step: Int) {
      update { $0.nudge(metric, by: step) }
    }

    private func update(_ change: (inout HealthSelection) -> Void) {
      var next = selection
      change(&next)
      selection = next
      store.save(next)
    }

    public func row(for metric: HealthMetric) -> HealthRowModel {
      HealthRowModel(
        metric: metric, series: series[metric], now: runtime.now(), calendar: runtime.calendar,
        units: units, locale: runtime.locale)
    }
  }
#endif

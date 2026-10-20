#if os(iOS)
  import Foundation
  import Testing
  import TodayCore
  @testable import FeatureHealth

  /// The real shared model, using controlled async reads rather than changing presentation state.
  @MainActor
  extension PlannerSessionTests {
    private actor HealthSummarySource: HealthSource, HealthQuerySource {
      nonisolated let isAvailable = true
      private(set) var days: [Int] = []
      private var pending: [Int: CheckedContinuation<HealthSeries, any Error>] = [:]
      func requestAccess(for metrics: [HealthMetric]) async {}
      func series(for metrics: [HealthMetric], days: Int, now: Date) async -> [HealthMetric:
        HealthSeries]
      { [:] }
      func query(_ metric: HealthMetric, days: Int, now: Date) async throws -> HealthSeries {
        let index = self.days.count
        self.days.append(days)
        return try await withCheckedThrowingContinuation { pending[index] = $0 }
      }
      func reply(_ index: Int, _ series: HealthSeries) {
        pending.removeValue(forKey: index)?.resume(returning: series)
      }
      func waitForQueries(_ count: Int) async -> Bool {
        for _ in 0..<100 {
          if days.count >= count { return true }
          try? await Task.sleep(for: .milliseconds(10))
        }
        return false
      }
    }

    private var healthSummaryNow: Date { Date(timeIntervalSince1970: 1_792_000_000) }
    private func makeHealthSummaryModel(_ source: HealthSummarySource) -> (
      HealthModel, HealthLineModel, UserDefaults
    ) {
      let defaults = UserDefaults(suiteName: "health-summary-\(UUID())")!
      let store = HealthSelectionStore(
        defaults: defaults, initialSelection: HealthSelection(shown: [.steps]))
      let instant = healthSummaryNow
      let runtime = PlannerRuntime(
        now: { instant }, nextID: { UUID() }, calendar: .current,
        locale: Locale(identifier: "en_US"))
      let model = HealthModel(
        source: source, store: store, runtime: runtime, gate: HealthAccessGate(), timeout: 2)
      return (model, HealthLineModel(model: model), defaults)
    }

    @Test
    func healthSheetUpdateSharesSummaryAndPreservesLongHistory() async {
      let source = HealthSummarySource()
      let (model, line, _) = makeHealthSummaryModel(source)
      let summary = Task { await line.load() }
      let first = await source.waitForQueries(1)
      #expect(first)
      await source.reply(
        0, HealthSeries(points: [HealthPoint(date: healthSummaryNow, value: 1111)]))
      await summary.value
      #expect(line.line?.contains("1,111") == true)

      let sheet = Task { await model.load() }
      let second = await source.waitForQueries(2)
      #expect(second)
      let history = HealthSeries(points: [
        HealthPoint(date: healthSummaryNow.addingTimeInterval(-80 * 86400), value: 800),
        HealthPoint(date: healthSummaryNow, value: 2222),
      ])
      await source.reply(1, history)
      await sheet.value
      #expect(model.series[.steps] == history)
      #expect(line.line?.contains("2,222") == true)
      _ = line.line
      let beforeRefresh = await source.days
      #expect(
        beforeRefresh == [HealthSpark.days, HealthModel.days], "deriving/dismissing adds no query")

      // The existing foreground/tab task still refreshes current values after a chart has been loaded.
      let foreground = Task { await line.load() }
      let third = await source.waitForQueries(3)
      #expect(third)
      await source.reply(
        2, HealthSeries(points: [HealthPoint(date: healthSummaryNow, value: 3333)]))
      await foreground.value
      #expect(
        model.series[.steps]?.points.first == history.points.first,
        "seven-day refresh keeps older chart history")
      #expect(model.series[.steps]?.latest?.value == 3333)
      #expect(line.line?.contains("3,333") == true)
      let requests = await source.days
      #expect(requests == [HealthSpark.days, HealthModel.days, HealthSpark.days])
    }

    @Test
    func healthLateShortReadCannotOverwriteNewLongWindow() async {
      let source = HealthSummarySource()
      let (model, line, _) = makeHealthSummaryModel(source)
      let summary = Task { await line.load() }
      let first = await source.waitForQueries(1)
      #expect(first)
      let sheet = Task { await model.load() }
      let second = await source.waitForQueries(2)
      #expect(second)
      let history = HealthSeries(points: [
        HealthPoint(date: healthSummaryNow.addingTimeInterval(-80 * 86400), value: 800),
        HealthPoint(date: healthSummaryNow, value: 2222),
      ])
      await source.reply(1, history)
      await sheet.value
      await source.reply(
        0, HealthSeries(points: [HealthPoint(date: healthSummaryNow, value: 1111)]))
      await summary.value
      #expect(model.series[.steps] == history)
      #expect(
        line.line?.contains("2,222") == true, "both presentations retain the latest generation")
      _ = line.line
      let requests = await source.days
      #expect(requests.count == 2)
    }
  }
#endif

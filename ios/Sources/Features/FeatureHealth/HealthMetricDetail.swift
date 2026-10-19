#if os(iOS)
  import SwiftUI
  import Charts
  import TodayCore
  import TodayDesignSystem
  import TodayPlatform

  /// One metric in detail: the latest value, a 7 / 30 / 90 day switch, a chart and plain range facts.
  /// Reading metrics also show a trailing average and its range change. No generated summary, goal or advice.
  public struct HealthMetricDetail: View {
    let metric: HealthMetric
    let series: HealthSeries
    let now: Date
    let units: HealthUnits
    let calendar: Calendar
    let locale: Locale

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var days = 30

    public init(
      metric: HealthMetric, series: HealthSeries, now: Date, units: HealthUnits, calendar: Calendar,
      locale: Locale
    ) {
      self.metric = metric
      self.series = series
      self.now = now
      self.units = units
      self.calendar = calendar
      self.locale = locale
    }

    private var latest: HealthPoint? { series.latest }
    private var points: [HealthPoint] {
      HealthStats.points(series, days: days, now: now, calendar: calendar)
    }
    private var stats: HealthRangeStats? {
      HealthStats.range(series, days: days, now: now, calendar: calendar)
    }

    private var averageDays: Int { MovingAverage.window(for: days) }
    private var averages: [HealthPoint] {
      guard !metric.isCumulative else { return [] }
      return MovingAverage.series(
        points: series.points, window: averageDays,
        days: HealthWindow(days: days, now: now, calendar: calendar), calendar: calendar)
    }

    public var body: some View {
      NavigationStack {
        ScrollView {
          VStack(alignment: .leading, spacing: 20) {
            header
            if HealthCatalog.quantities[metric]?.aggregation == .dailyAverage {
              Text("Daily averages · Missing days are not counted as zero.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            PillSwitcher(
              items: [7, 30, 90], selection: $days,
              title: { "\($0) Days" }, identifier: { "health.range.\($0)" })
            if !metric.isCumulative { legend }
            chart
            facts
          }
          .padding(.horizontal, 20)
          .padding(.top, 8)
          .padding(.bottom, 24)
        }
        .performanceDestination("health.detail")
        .navigationTitle(metric.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button("Done") { dismiss() }.accessibilityIdentifier("health.detail.done")
          }
        }
      }
      .environment(\.calendar, calendar)
      .environment(\.locale, locale)
      .environment(\.timeZone, calendar.timeZone)
      .presentationDetents([.fraction(0.72), .large])
      .presentationDragIndicator(.visible)
    }

    // MARK: Header

    private var header: some View {
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        if let latest {
          let value = HealthFormat.value(metric, latest.value, units: units, locale: locale)
          ForEach(Array(value.parts.enumerated()), id: \.offset) { index, part in
            Text(part.number)
              .font(.system(size: 44, weight: .semibold, design: .rounded))
              .monospacedDigit()
              .padding(.leading, index > 0 ? 4 : 0)
            Text(part.unit).font(.title3).foregroundStyle(.secondary)
          }
          Text(HealthFormat.dateLabel(latest.date, now: now, calendar: calendar, locale: locale))
            .font(.subheadline)
            .foregroundStyle(.tertiary)
            .padding(.leading, 4)
        } else {
          Text("—").font(.system(size: 44, weight: .semibold, design: .rounded)).foregroundStyle(
            .secondary)
          Text("No data").font(.subheadline).foregroundStyle(.tertiary)
        }
      }
      .lineLimit(1)
      .minimumScaleFactor(0.6)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(
        latest.map {
          "\(HealthFormat.value(metric, $0.value, units: units, locale: locale).text), \(HealthFormat.dateLabel($0.date, now: now, calendar: calendar, locale: locale))"
        } ?? "No data"
      )
      .accessibilityIdentifier("health.detail.value")
    }

    // MARK: Chart

    private func shown(_ p: HealthPoint) -> Double {
      HealthFormat.displayValue(metric, p.value, units: units)
    }

    private var yDomain: ClosedRange<Double> {
      let values = (points + averages).map(shown)
      guard let lo = values.min(), let hi = values.max() else { return 0...1 }
      if metric.shape == .bars { return 0...max(hi * 1.1, 0.001) }
      let pad = max((hi - lo) * 0.25, abs(hi) * 0.01, 0.001)
      return (lo - pad)...(hi + pad)
    }

    /// Sleep and daylight are drawn in hours, so their axis says so.
    private var axisUnit: String { metric == .sleep || metric == .daylight ? " h" : "" }

    private var chart: some View {
      let window = HealthWindow(days: days, now: now, calendar: calendar)
      let dotted = StrokeStyle(lineWidth: 0.5, dash: [1, 3])
      return Group {
        if points.isEmpty && averages.isEmpty {
          Text("No data in the last \(days) days.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 200)
            .accessibilityIdentifier("health.detail.empty")
        } else {
          Chart {
            ForEach(points, id: \.date) { p in
              if metric.shape == .bars {
                BarMark(
                  x: .value("Day", p.date, unit: .day), y: .value(metric.title, shown(p)),
                  width: .ratio(0.7)
                )
                .foregroundStyle(HealthStyle.accent)
                .clipShape(RoundedRectangle(cornerRadius: 2))
              } else {
                PointMark(x: .value("Date", p.date), y: .value(metric.title, shown(p)))
                  .symbolSize(days == 7 ? 18 : 10)
                  .foregroundStyle(HealthStyle.accent.opacity(0.35))
              }
            }
            ForEach(
              Array(MovingAverage.segments(averages, calendar: calendar).enumerated()), id: \.offset
            ) { index, segment in
              ForEach(segment, id: \.date) { p in
                LineMark(
                  x: .value("Date", p.date), y: .value("Average", shown(p)),
                  series: .value("Segment", index)
                )
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                .foregroundStyle(HealthStyle.accent)
                if segment.count == 1 {
                  PointMark(x: .value("Date", p.date), y: .value("Average", shown(p)))
                    .symbolSize(24)
                    .foregroundStyle(HealthStyle.accent)
                }
              }
            }
          }
          .chartXScale(
            domain: window.start...window.end,
            range: .plotDimension(startPadding: 4, endPadding: 28)
          )
          .chartYScale(domain: yDomain)
          .chartXAxis {
            AxisMarks(values: HealthStats.axisTicks(days: days, now: now, calendar: calendar)) {
              _ in
              AxisGridLine(stroke: dotted)
              AxisValueLabel(
                format: Date.FormatStyle(
                  locale: locale, calendar: calendar, timeZone: calendar.timeZone
                ).month(.abbreviated).day(), anchor: .top)
            }
          }
          .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
              AxisGridLine(stroke: dotted)
              AxisValueLabel {
                if let v = value.as(Double.self) {
                  Text(HealthFormat.axisLabel(v, locale: locale) + axisUnit)
                }
              }
            }
          }
          .frame(height: 220)
          .accessibilityIdentifier("health.detail.chart")
        }
      }
    }

    private var legend: some View {
      HStack(spacing: 16) {
        Label {
          Text("Readings")
        } icon: {
          Circle().fill(HealthStyle.accent.opacity(0.35)).frame(width: 5, height: 5)
        }
        Label {
          Text("\(averageDays)-day average")
        } icon: {
          Capsule().fill(HealthStyle.accent).frame(width: 18, height: 3)
        }
      }
      .font(.footnote)
      .foregroundStyle(.secondary)
      .accessibilityElement(children: .combine)
      .accessibilityIdentifier("health.detail.legend")
    }

    // MARK: Facts

    private var factsLayout: AnyLayout {
      dynamicTypeSize.isAccessibilitySize
        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
        : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
    }

    private var facts: some View {
      VStack(alignment: .leading, spacing: 14) {
        factsLayout {
          fact("Average", stats?.average)
          fact("Low", stats?.low)
          fact("High", stats?.high)
        }
        if !metric.isCumulative { trend }
        if let change = stats?.change {
          Text(
            "Average \(HealthFormat.change(metric, change, units: units, locale: locale)) vs previous \(days) days"
          )
          .font(.footnote)
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("health.detail.change")
        }
      }
    }

    private var trend: some View {
      VStack(alignment: .leading, spacing: 2) {
        Text("Trend").font(.footnote).foregroundStyle(.secondary)
        if let latest = averages.last {
          Text(HealthFormat.value(metric, latest.value, units: units, locale: locale).text)
            .font(.headline).monospacedDigit()
          Text(
            "\(averageDays)-day average · \(HealthFormat.dateLabel(latest.date, now: now, calendar: calendar, locale: locale))"
          )
          .font(.footnote).foregroundStyle(.secondary)
          if let first = averages.first, first.date != latest.date {
            Text(
              "\(HealthFormat.change(metric, latest.value - first.value, units: units, locale: locale)) over \(days) days"
            )
            .font(.footnote).foregroundStyle(.secondary)
          } else {
            Text("Not enough averages to compare this range.")
              .font(.footnote).foregroundStyle(.secondary)
          }
        } else {
          Text("At least two readings in a \(averageDays)-day window are needed.")
            .font(.footnote).foregroundStyle(.secondary)
        }
      }
      .accessibilityElement(children: .combine)
      .accessibilityIdentifier("health.fact.trend")
    }

    private func fact(_ title: String, _ value: Double?) -> some View {
      VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.footnote).foregroundStyle(.secondary)
        Text(value.map { HealthFormat.value(metric, $0, units: units, locale: locale).text } ?? "—")
          .font(.headline)
          .monospacedDigit()
          .lineLimit(1)
          .minimumScaleFactor(0.7)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityElement(children: .combine)
      .accessibilityIdentifier("health.fact.\(title.lowercased())")
    }
  }
#endif

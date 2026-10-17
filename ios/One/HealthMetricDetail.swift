import SwiftUI
import Charts

/// One metric in detail: the latest value, a 7 / 30 / 90 day switch, one clean chart and three plain facts (average,
/// low, high) with the change against the days before. Facts only: no generated summary, no goal, no advice.
struct HealthMetricDetail: View {
    let metric: HealthMetric
    let series: HealthSeries
    let now: Date

    @Environment(\.dismiss) private var dismiss
    @State private var days = 30
    private let units = HealthUnits()

    private var latest: HealthPoint? { series.latest }
    private var points: [HealthPoint] { HealthStats.points(series, days: days, now: now) }
    private var stats: HealthRangeStats? { HealthStats.range(series, days: days, now: now) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    PillSwitcher(items: [7, 30, 90], selection: $days,
                                 title: { "\($0) Days" }, identifier: { "health.range.\($0)" })
                    chart
                    facts
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .navigationTitle(metric.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("health.detail.done") } }
        }
        .presentationDetents([.fraction(0.72), .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let latest {
                let value = HealthFormat.value(metric, latest.value, units: units)
                ForEach(Array(value.parts.enumerated()), id: \.offset) { index, part in
                    Text(part.number)
                        .font(.system(size: 44, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .padding(.leading, index > 0 ? 4 : 0)
                    Text(part.unit).font(.title3).foregroundStyle(.secondary)
                }
                Text(HealthFormat.dateLabel(latest.date, now: now))
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 4)
            } else {
                Text("—").font(.system(size: 44, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
                Text("No data").font(.subheadline).foregroundStyle(.tertiary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(latest.map { "\(HealthFormat.value(metric, $0.value, units: units).text), \(HealthFormat.dateLabel($0.date, now: now))" } ?? "No data")
        .accessibilityIdentifier("health.detail.value")
    }

    // MARK: Chart

    private func shown(_ p: HealthPoint) -> Double { HealthFormat.displayValue(metric, p.value, units: units) }

    private var yDomain: ClosedRange<Double> {
        let values = points.map(shown)
        guard let lo = values.min(), let hi = values.max() else { return 0...1 }
        if metric.shape == .bars { return 0...max(hi * 1.1, 0.001) }
        let pad = max((hi - lo) * 0.25, abs(hi) * 0.01, 0.001)
        return (lo - pad)...(hi + pad)
    }

    /// Sleep and daylight are drawn in hours, so their axis says so.
    private var axisUnit: String { metric == .sleep || metric == .daylight ? " h" : "" }

    private var chart: some View {
        let window = HealthWindow(days: days, now: now)
        let dotted = StrokeStyle(lineWidth: 0.5, dash: [1, 3])
        return Group {
            if points.isEmpty {
                Text("No data in the last \(days) days.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 200)
                    .accessibilityIdentifier("health.detail.empty")
            } else {
                Chart {
                    ForEach(points, id: \.date) { p in
                        if metric.shape == .bars {
                            BarMark(x: .value("Day", p.date, unit: .day), y: .value(metric.title, shown(p)), width: .ratio(0.7))
                                .foregroundStyle(HealthStyle.accent)
                                .clipShape(RoundedRectangle(cornerRadius: 2))
                        } else {
                            LineMark(x: .value("Date", p.date), y: .value(metric.title, shown(p)))
                                .interpolationMethod(.linear)
                                .lineStyle(StrokeStyle(lineWidth: 1.5))
                                .foregroundStyle(HealthStyle.accent.opacity(0.5))
                            PointMark(x: .value("Date", p.date), y: .value(metric.title, shown(p)))
                                .symbolSize(days == 7 ? 36 : 18)
                                .foregroundStyle(HealthStyle.accent)
                        }
                    }
                }
                .chartXScale(domain: window.start...window.end, range: .plotDimension(startPadding: 4, endPadding: 28))
                .chartYScale(domain: yDomain)
                .chartXAxis {
                    AxisMarks(values: HealthStats.axisTicks(days: days, now: now)) { _ in
                        AxisGridLine(stroke: dotted)
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day(), anchor: .top)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine(stroke: dotted)
                        AxisValueLabel { if let v = value.as(Double.self) { Text(HealthFormat.axisLabel(v) + axisUnit) } }
                    }
                }
                .frame(height: 220)
                .accessibilityIdentifier("health.detail.chart")
            }
        }
    }

    // MARK: Facts

    private var facts: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                fact("Average", stats?.average)
                fact("Low", stats?.low)
                fact("High", stats?.high)
            }
            if let change = stats?.change {
                Text("Average \(HealthFormat.change(metric, change, units: units)) vs previous \(days) days")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("health.detail.change")
            }
        }
    }

    private func fact(_ title: String, _ value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.footnote).foregroundStyle(.secondary)
            Text(value.map { HealthFormat.value(metric, $0, units: units).text } ?? "—")
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

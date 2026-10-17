import SwiftUI
import Charts

/// The Health tab: three cards read from Apple Health, in the order people check them: steps today, weight, last night's sleep.
/// Modeled on the Summary page of Apple's Health app (big value, small chart), without its Trends, Highlights or Browse:
/// Health stays the place for the full history; tapping "Open Health" goes there. Read-only; + still adds a reminder.
struct HealthView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var source: HealthSource = HealthSources.current()
    @State private var snapshot: HealthSnapshot?
    @AppStorage("health.weightRange") private var weightDays = 30

    var body: some View {
        ScrollViewReader { proxy in
        List {
            if !source.isAvailable {
                unavailable
            } else if let snapshot {
                if snapshot.isSample {
                    Text("Sample data. On iPhone this page reads Apple Health.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("health.sample")
                        .plainRow(top: 4, bottom: 4)
                }
                StepsCard(days: snapshot.steps).plainRow(top: 8, bottom: 8)
                WeightCard(samples: snapshot.weights, days: $weightDays).plainRow(top: 8, bottom: 8)
                SleepCard(nights: snapshot.nights).plainRow(top: 8, bottom: 8).id("sleep")
                footer
            } else {
                ProgressView().frame(maxWidth: .infinity).plainRow(top: 40, bottom: 0)
            }
        }
        .listStyle(.plain)
        .background(Color(.systemBackground))
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await source.requestAccess()
            snapshot = (try? await source.snapshot(now: TodayClock.now)) ?? .empty
        }
        .refreshable { snapshot = (try? await source.snapshot(now: TodayClock.now)) ?? .empty }
        .onChange(of: snapshot) {
            // Screenshots only (`-uiTesting -uiTestingScrollTo sleep`).
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-uiTesting"), let i = args.firstIndex(of: "-uiTestingScrollTo"), i + 1 < args.count {
                let target = args[i + 1]
                Task { try? await Task.sleep(for: .milliseconds(400)); proxy.scrollTo(target, anchor: .top) }
            }
        }
        }
    }

    /// Health never tells an app that reading was denied, so the hint covers both "no data" and "not allowed".
    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Today only reads Apple Health; nothing leaves your iPhone. Missing something? Allow it in Health → Profile → Apps → Today.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button {
                if let url = URL(string: "x-apple-health://") { openURL(url) }
            } label: {
                Label("Open Health", systemImage: "heart.text.square")
            }
            .font(.subheadline.weight(.semibold))
        }
        .plainRow(top: 8, bottom: 24)
    }

    private var unavailable: some View {
        VStack(spacing: 8) {
            Image(systemName: "heart.slash").font(.largeTitle).foregroundStyle(.secondary)
            Text("Health Isn't Available").font(.title3.weight(.semibold))
            Text("This device doesn't have Apple Health.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .accessibilityElement(children: .combine)
        .plainRow(top: 0, bottom: 0)
    }
}

// MARK: Steps

private struct StepsCard: View {
    let days: [DayValue]
    private let goal = HealthSnapshot.stepGoal
    private var today: Double { days.last?.value ?? 0 }

    var body: some View {
        HealthCard(title: "Steps", symbol: "figure.walk", tint: .orange) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    BigValue(today.formatted(.number.precision(.fractionLength(0))), unit: "steps")
                    Text(today >= goal ? "Goal reached" : "\((goal - today).formatted(.number.precision(.fractionLength(0)))) to \(goal.formatted(.number.precision(.fractionLength(0))))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                GoalRing(progress: today / goal, tint: .orange)
                    .frame(width: 56, height: 56)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("health.steps")

            if days.contains(where: { $0.value > 0 }) {
                Chart {
                    ForEach(days) { d in
                        BarMark(x: .value("Day", d.day, unit: .day), y: .value("Steps", d.value), width: .ratio(0.55))
                            .foregroundStyle(Calendar.current.isDateInToday(d.day) ? Color.orange : Color.orange.opacity(0.35))
                            .clipShape(Capsule())
                    }
                    RuleMark(y: .value("Goal", goal))
                        .foregroundStyle(.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                .chartYScale(domain: 0...max(goal, days.map(\.value).max() ?? 0) * 1.1)
                .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow)) } }
                .chartYAxis { AxisMarks(position: .trailing, values: [0, goal / 2, goal]) }
                .frame(height: 110)
                if let avg = HealthMath.average(days.map(\.value)) {
                    Text("7-day average \(avg.formatted(.number.precision(.fractionLength(0))))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                NoData("No steps yet this week.")
            }
        }
    }
}

private struct GoalRing: View {
    let progress: Double
    let tint: Color

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.2), lineWidth: 7)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(tint, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int((min(progress, 9.99) * 100).rounded()))%")
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
        }
        .accessibilityHidden(true)
    }
}

// MARK: Weight

private struct WeightCard: View {
    let samples: [WeightSample]
    @Binding var days: Int

    /// kg or lb, from the region (Apple Health does the same).
    private var unit: UnitMass { Locale.current.measurementSystem == .us ? .pounds : .kilograms }
    private func display(_ kg: Double) -> Double { Measurement(value: kg, unit: UnitMass.kilograms).converted(to: unit).value }
    private var unitText: String { unit == .pounds ? "lb" : "kg" }
    private var window: [WeightSample] { HealthMath.weights(samples, lastDays: days, now: .now) }

    var body: some View {
        HealthCard(title: "Weight", symbol: "scalemass", tint: .purple) {
            if let latest = samples.last {
                HStack(alignment: .firstTextBaseline) {
                    BigValue(display(latest.kilograms).formatted(.number.precision(.fractionLength(1))), unit: unitText)
                    Spacer(minLength: 0)
                    Text(DayLabel.text(for: latest.date))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("health.weight")

                PillSwitcher(items: [30, 90], selection: $days,
                             title: { "\($0) Days" }, identifier: { "health.range.\($0)" })

                if window.count >= 2 {
                    let values = window.map { display($0.kilograms) }
                    let low = (values.min() ?? 0) - 0.6, high = (values.max() ?? 0) + 0.6
                    Chart(window) { s in
                        LineMark(x: .value("Date", s.date), y: .value("Weight", display(s.kilograms)))
                            .interpolationMethod(.linear)
                            .lineStyle(StrokeStyle(lineWidth: 1.5))
                            .foregroundStyle(Color.purple)
                        PointMark(x: .value("Date", s.date), y: .value("Weight", display(s.kilograms)))
                            .symbolSize(14)
                            .foregroundStyle(Color.purple.opacity(0.6))
                    }
                    .chartYScale(domain: low...high)
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated).day()) } }
                    .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) }
                    .frame(height: 120)
                    if let change = HealthMath.weightChange(window) {
                        let shown = display(change)
                        Text(abs(shown) < 0.05 ? "No change in \(days) days"
                             : "\(shown > 0 ? "+" : "−")\(abs(shown).formatted(.number.precision(.fractionLength(1)))) \(unitText) in \(days) days")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    NoData("Not enough weigh-ins in the last \(days) days for a trend.")
                }
            } else {
                NoData("No weight in the last 90 days.")
            }
        }
    }
}

// MARK: Sleep

private struct SleepCard: View {
    let nights: [SleepNight]

    var body: some View {
        HealthCard(title: "Sleep", symbol: "bed.double", tint: .indigo) {
            if let night = nights.last, Calendar.current.isDateInToday(night.day) {
                VStack(alignment: .leading, spacing: 2) {
                    BigValue(HealthMath.duration(night.asleep), unit: nil)
                    if let start = night.start, let end = night.end {
                        Text("Last night, \(start.formatted(date: .omitted, time: .shortened)) – \(end.formatted(date: .omitted, time: .shortened))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("health.sleep")
                StagesBar(night: night)
            } else {
                NoData("No sleep recorded last night.")
            }

            if nights.count >= 2 {
                Chart(nights) { n in
                    BarMark(x: .value("Night", n.day, unit: .day), y: .value("Hours", n.asleep / 3600), width: .ratio(0.55))
                        .foregroundStyle(Calendar.current.isDateInToday(n.day) ? Color.indigo : Color.indigo.opacity(0.35))
                        .clipShape(Capsule())
                }
                .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow)) } }
                .chartYAxis { AxisMarks(position: .trailing, values: [0, 4, 8]) { v in
                    AxisGridLine()
                    AxisValueLabel { if let h = v.as(Int.self) { Text("\(h) hr") } }
                } }
                .frame(height: 100)
                if let avg = HealthMath.average(nights.map(\.asleep)) {
                    Text("Average \(HealthMath.duration(avg)) over \(nights.count) nights")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Last night's stages as one bar (share of the night), with a legend: Awake, REM, Core, Deep, like Health's stage colors.
private struct StagesBar: View {
    let night: SleepNight
    private var total: TimeInterval { night.intervals.reduce(0) { $0 + $1.duration } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(night.stages, id: \.self) { stage in
                        Rectangle()
                            .fill(stage.color)
                            .frame(width: max(2, (geo.size.width - CGFloat(night.stages.count - 1) * 2) * night.total(stage) / max(total, 1)))
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 10)
            HStack(spacing: 14) {
                ForEach(night.stages, id: \.self) { stage in
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Circle().fill(stage.color).frame(width: 7, height: 7)
                            Text(stage.title).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(HealthMath.duration(night.total(stage))).font(.caption.weight(.semibold)).monospacedDigit()
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(night.stages.map { "\($0.title) \(HealthMath.duration(night.total($0)))" }.joined(separator: ", "))
    }
}

private extension SleepStage {
    var color: Color {
        switch self {
        case .awake: .orange
        case .rem: .cyan
        case .core: .blue
        case .deep: .indigo
        case .unspecified: .teal
        }
    }
}

// MARK: Building blocks

/// A rounded card like the banners on the Alarms tab: a small colored title, then content.
private struct HealthCard<Content: View>: View {
    let title: String
    let symbol: String
    let tint: Color
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .accessibilityAddTraits(.isHeader)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// "6,412 steps": a large rounded number with a small unit, like Health's Summary.
private struct BigValue: View {
    let value: String
    let unit: String?
    init(_ value: String, unit: String?) { self.value = value; self.unit = unit }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value).font(.system(.largeTitle, design: .rounded).weight(.semibold)).monospacedDigit()
            if let unit { Text(unit).font(.headline).foregroundStyle(.secondary) }
        }
    }
}

private struct NoData: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(.subheadline).foregroundStyle(.secondary) }
}

private extension View {
    /// A row with no separator and no background (same as the Alarms tab).
    func plainRow(top: CGFloat, bottom: CGFloat) -> some View {
        listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: top, leading: 20, bottom: bottom, trailing: 20))
    }
}

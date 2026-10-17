import SwiftUI

/// The Health sheet: a dense list of the metrics the user chose, one rounded container per group (Activity, Sleep &
/// Recovery, Body). Each row is the metric's name, its latest value with a quiet date label and a 7-day sparkline;
/// tapping opens the detail. Read-only: Today only reads Apple Health.
/// Editing has no Edit button, like everywhere in the app: swipe a row for Hide, long-press for Hide / Move Up /
/// Move Down, press, hold and drag to reorder inside a group, and Add Metric (a quiet row, also in the ··· menu)
/// offers the metrics not shown yet.
struct HealthView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var model = HealthModel()
    @State private var detail: HealthMetric?
    @State private var adding = false

    var body: some View {
        List {
            if !model.isAvailable {
                unavailable
            } else if !model.hasLoaded {
                ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear).listRowSeparator(.hidden)
            } else {
                ForEach(model.selection.groups, id: \.group) { entry in
                    Section {
                        ForEach(entry.metrics) { metric in row(metric) }
                            .onMove { model.move(in: entry.group, from: $0, to: $1) }
                    } header: {
                        Text(entry.group.title)
                    }
                }
                Section {
                    if model.selection.shown.isEmpty {
                        Text("No metrics shown.").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Button { adding = true } label: {
                        Label("Add Metric", systemImage: "plus")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(minHeight: 44, alignment: .leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("health.add")
                }
                footer
            }
        }
        .listStyle(.insetGrouped)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button { adding = true } label: { Label("Add Metric", systemImage: "plus") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("More")
                .accessibilityIdentifier("health.menu")
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await model.load()
        }
        .refreshable { await model.load() }
        .sheet(item: $detail) { metric in
            HealthMetricDetail(metric: metric, series: model.series[metric] ?? .empty, now: TodayClock.now)
        }
        .sheet(isPresented: $adding) {
            HealthMetricPicker(hidden: model.selection.hidden) { chosen in
                Task { await model.add(chosen) }
            }
        }
    }

    // MARK: Rows

    private func row(_ metric: HealthMetric) -> some View {
        let item = model.row(for: metric)
        return Button { detail = metric } label: {
            HealthRow(item: item)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.accessibilityText)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("health.row.\(metric.rawValue)")
        // Hide only hides the row; Apple Health keeps everything. Same icon-only look as every swipe action.
        .swipeActions(edge: .trailing) {
            Button { withAnimation(.snappy) { model.hide(metric) } } label: {
                Label("Hide", systemImage: "eye.slash.fill").labelStyle(.iconOnly)
            }
            .tint(Color(.systemGray))
        }
        .contextMenu {
            Button { withAnimation(.snappy) { model.hide(metric) } } label: { Label("Hide", systemImage: "eye.slash") }
            Button { withAnimation(.snappy) { model.nudge(metric, by: -1) } } label: { Label("Move Up", systemImage: "arrow.up") }
                .disabled(model.selection.metrics(in: metric.group).first == metric)
            Button { withAnimation(.snappy) { model.nudge(metric, by: 1) } } label: { Label("Move Down", systemImage: "arrow.down") }
                .disabled(model.selection.metrics(in: metric.group).last == metric)
        }
    }

    /// Health never tells an app that reading was denied, so the hint covers both "no data" and "not allowed".
    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.isSample {
                Text("Sample data. On iPhone this page reads Apple Health.")
                    .accessibilityIdentifier("health.sample")
            }
            Text("Today only reads Apple Health; nothing leaves your iPhone. Missing something? Allow it in Health → Profile → Apps → Today.")
            Button {
                if let url = URL(string: "x-apple-health://") { openURL(url) }
            } label: {
                Label("Open Health", systemImage: "heart.text.square")
            }
            .font(.subheadline.weight(.semibold))
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 24, trailing: 20))
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
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}

/// One row: name over the latest value (large number, small unit, quiet date label), and the sparkline on the right.
private struct HealthRow: View {
    let item: HealthRowModel
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.metric.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    if let value = item.value {
                        ForEach(Array(value.parts.enumerated()), id: \.offset) { index, part in
                            Text(part.number)
                                .font(.system(.title2, design: .rounded).weight(.semibold))
                                .monospacedDigit()
                                .padding(.leading, index > 0 ? 3 : 0)
                            if !part.unit.isEmpty {
                                Text(part.unit).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Text("—").font(.system(.title2, design: .rounded).weight(.semibold)).foregroundStyle(.secondary)
                    }
                    Text(item.dateLabel)
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 4)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 8)
            if !typeSize.isAccessibilitySize {
                HealthSparkline(values: item.spark, shape: item.metric.shape)
                    .frame(width: 68, height: 28)
            }
        }
        .frame(minHeight: 60)
        .contentShape(Rectangle())
    }
}

#if os(iOS)
  import SwiftUI
  import TodayCore
  import TodayDesignSystem
  import TodayPlatform

  /// A globally ordered read-only dashboard. Customize uses native List dragging and accessible move actions.
  public struct HealthView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    private let model: HealthModel
    @State private var detail: HealthMetric?
    @State private var adding = false
    @State private var recordsPresented = false
    @State private var draft = HealthSelection.default
    @State private var customizing = false

    public init(model: HealthModel) {
      self.model = model
    }

    private func manageMetrics() {
      PerformanceTrace.shared.beginPage("health.picker")
      draft = model.selection
      adding = true
    }

    public var body: some View {
      List {
        if !model.isAvailable {
          unavailable
        } else {
          Section {
            ForEach(model.selection.ordered) { metric in row(metric) }
              .onMove { model.move(from: $0, to: $1) }
          } header: {
            VStack(alignment: .leading, spacing: 4) {
              Text(customizing ? "Your order" : "Your health")
                .font(.headline.weight(.medium))
                .foregroundStyle(.primary)
              Text(
                customizing
                  ? "Drag any metric to any position."
                  : "Measurements from Apple Health, in your order."
              )
              .font(.footnote)
              .textCase(nil)
            }
            .padding(.bottom, 6)
          }
          Section {
            if model.selection.shown.isEmpty {
              Text("No metrics shown.").font(.subheadline).foregroundStyle(.secondary)
            }
            Button {
              manageMetrics()
            } label: {
              Label("Manage Metrics", systemImage: "slider.horizontal.3")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(minHeight: 44, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 16))
            .accessibilityIdentifier("health.add")
          }
          if model.recordSource != nil {
            Section {
              Button {
                recordsPresented = true
              } label: {
                Label("Browse Health Records", systemImage: "list.bullet.rectangle")
                  .font(.subheadline)
                  .foregroundStyle(.secondary)
                  .frame(minHeight: 44)
              }
              .accessibilityIdentifier("health.records")
            } footer: {
              Text("Workouts, events, paired readings and profile. Choose what to read.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
          }
          footer
        }
      }
      .listStyle(.insetGrouped)
      .environment(\.editMode, .constant(customizing ? .active : .inactive))
      .performanceDestination("health")
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button(customizing ? "Finish" : "Customize") {
            withAnimation(.snappy) { customizing.toggle() }
          }
          .font(.subheadline.weight(.medium))
          .accessibilityLabel(customizing ? "Done Customizing" : "Customize")
          .accessibilityIdentifier("health.customize")
        }

      }
      .task(id: scenePhase) {
        guard scenePhase == .active else { return }
        await model.load()
      }
      .refreshable { await model.load() }
      .sheet(isPresented: $recordsPresented) {
        if let source = model.recordSource {
          HealthRecordsView(source: source, runtime: model.runtime)
        }
      }
      .sheet(item: $detail) { metric in
        HealthMetricDetail(
          metric: metric, series: model.series[metric] ?? .empty, now: model.runtime.now(),
          units: model.units, calendar: model.runtime.calendar, locale: model.runtime.locale)
      }
      .sheet(
        isPresented: $adding,
        onDismiss: {
          let next = draft
          Task { await model.customize(next) }
        }
      ) {
        HealthMetricPicker(selection: $draft)
      }
    }

    // MARK: Rows

    private func row(_ metric: HealthMetric) -> some View {
      let item = model.row(for: metric)
      let state = model.state(for: metric)
      var failure: HealthFailure?
      if case .failed(let reason) = state { failure = reason }
      return VStack(alignment: .leading, spacing: 4) {
        Button {
          guard !customizing else { return }
          PerformanceTrace.shared.beginPage("health.detail")
          detail = metric
        } label: {
          HealthRow(item: item, isLoading: state == .loading && item.value == nil)
        }
        .buttonStyle(.plain)
        .disabled(customizing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
          failure == nil ? item.accessibilityText : "\(item.accessibilityText). \(Self.cantRead)"
        )
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("health.row.\(metric.rawValue)")
        if let failure {
          // A failed row says so quietly, once, and offers the one action that can help.
          HStack(spacing: 8) {
            Text(failure == .queryFailed ? "Couldn't refresh. Try again." : Self.cantRead)
              .font(.footnote)
              .foregroundStyle(.secondary)
              .accessibilityIdentifier("health.note.\(metric.rawValue)")
            Spacer(minLength: 4)
            Button(failure == .accessUnanswered ? "Allow" : "Try Again") {
              Task { await model.retry(metric) }
            }
            .font(.footnote.weight(.semibold))
            .buttonStyle(.plain)
            .foregroundStyle(HealthStyle.accent)
            .accessibilityIdentifier("health.action.\(metric.rawValue)")
          }
        }
      }
      // About 60 pt: name, value line, and 6 pt above and below (the default cell padding makes rows 90 pt).
      .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 16))
      // Hide only hides the row; Apple Health keeps everything. Same icon-only look as every swipe action.
      .swipeActions(edge: .trailing) {
        Button {
          withAnimation(.snappy) { model.hide(metric) }
        } label: {
          Label("Hide", systemImage: "eye.slash.fill").labelStyle(.iconOnly)
        }
        .tint(Color(.systemGray))
      }
      .accessibilityAction(named: "Move Up") { model.nudge(metric, by: -1) }
      .accessibilityAction(named: "Move Down") { model.nudge(metric, by: 1) }
      .accessibilityAction(named: "Move to Top") { model.moveToTop(metric) }
      .contextMenu {
        Button {
          model.moveToTop(metric)
        } label: {
          Label("Move to Top", systemImage: "arrow.up.to.line")
        }
        .disabled(model.selection.ordered.first == metric)
        Button {
          withAnimation(.snappy) { model.hide(metric) }
        } label: {
          Label("Hide", systemImage: "eye.slash")
        }
        Button {
          withAnimation(.snappy) { model.nudge(metric, by: -1) }
        } label: {
          Label("Move Up", systemImage: "arrow.up")
        }
        .disabled(model.selection.ordered.first == metric)
        Button {
          withAnimation(.snappy) { model.nudge(metric, by: 1) }
        } label: {
          Label("Move Down", systemImage: "arrow.down")
        }
        .disabled(model.selection.ordered.last == metric)
      }
    }

    static let cantRead = "Can't read this yet. Check Health access."

    /// Health never tells an app that reading was denied, so the hint covers both "no data" and "not allowed".
    private var footer: some View {
      VStack(alignment: .leading, spacing: 8) {
        if model.isSample {
          Text("Sample data. On iPhone this page reads Apple Health.")
            .accessibilityIdentifier("health.sample")
        }
        Text(
          "Today only reads Apple Health; nothing leaves your iPhone. \"No data\" can also mean Today isn't allowed to read it: check Health → Profile → Apps → Today."
        )
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
    /// Waiting for this metric's first answer: a small spinner in place of the number (never over the whole sheet).
    var isLoading = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 2) {
          HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(item.metric.title)
              .font(.subheadline.weight(.medium))
              .foregroundStyle(.primary)
            if !typeSize.isAccessibilitySize {
              Text(item.metric.group.title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
          }
          .fixedSize(horizontal: false, vertical: true)
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
            } else if isLoading {
              ProgressView().controlSize(.small).frame(height: 28)
                .accessibilityIdentifier("health.row.loading.\(item.metric.rawValue)")
            } else {
              Text("—").font(.system(.title2, design: .rounded).weight(.semibold)).foregroundStyle(
                .secondary)
            }
            if !isLoading {
              Text(item.dateLabel)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            }
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
      .frame(minHeight: 48)
      .contentShape(Rectangle())
    }
  }
#endif

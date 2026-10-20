#if os(iOS)
  import TodayCore
  import TodayPlatform
  import TodayDesignSystem
  import SwiftUI

  /// A presentation facade over the assembly-owned Health model. No separate values or query cache.
  @MainActor
  @Observable
  public final class HealthLineModel {
    private let model: HealthModel

    public init(model: HealthModel) { self.model = model }

    package var line: String? {
      HealthLine.text(
        selection: model.selection, series: model.series, now: model.runtime.now(),
        calendar: model.runtime.calendar, units: model.units, locale: model.runtime.locale)
    }

    package func load() async { await model.loadSummary() }
  }

  /// One quiet line at the top of Today (today only): "6,240 steps · slept 7 hr 12 min". Tap opens the Health sheet (the
  /// compact list of the metrics you chose). Read-only. Off with Settings → Today → Health summary.
  package struct TodayHealthLine: View {
    let line: String
    package init(line: String) { self.line = line }
    @State private var showsDetail = false

    package var body: some View {
      Button {
        PerformanceTrace.shared.beginPage("health")
        showsDetail = true
      } label: {
        HStack(spacing: 6) {
          Image(systemName: "heart.fill").font(.caption2).foregroundStyle(HealthStyle.accent)
          Text(line).font(.footnote).foregroundStyle(.secondary).monospacedDigit()
          Spacer(minLength: 0)
          Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(
            .tertiary)
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
      Button {
        PerformanceTrace.shared.beginPage("health")
        showsSheet = true
      } label: {
        HStack {
          Text("Health metrics").foregroundStyle(.primary)
          Spacer()
          Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(
            .tertiary)
        }
      }
      .accessibilityIdentifier("settings.healthMetrics")
      .sheet(isPresented: $showsSheet) { HealthDetailSheet() }
    }
  }

#endif

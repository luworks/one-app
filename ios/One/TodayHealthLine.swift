import SwiftUI

/// Reads Apple Health for the line at the top of Today. Health data stays in memory (never in SwiftData or the widget).
/// HealthKit permission is asked the first time the line would show, only for the metrics the line talks about; with
/// no data or no permission there is no line (Health never says which).
@MainActor
@Observable
final class HealthLineModel {
    private let source: HealthSource = HealthSources.current()
    private(set) var line: String?

    func load() async {
        guard source.isAvailable else { return }
        let selection = HealthSelectionStore.shared.selection
        let metrics = HealthLine.metrics(for: selection)
        guard !metrics.isEmpty else { line = nil; return }
        await source.requestAccess(for: metrics)
        let now = TodayClock.now
        let series = await source.series(for: metrics, days: HealthSpark.days, now: now)
        line = HealthLine.text(selection: selection, series: series, now: now)
    }
}

/// One quiet line at the top of Today (today only): "6,240 steps · slept 7 hr 12 min". Tap opens the Health sheet (the
/// compact list of the metrics you chose). Read-only. Off with Settings → Today → Health summary.
/// `onClose` runs when the sheet goes away, so the line follows a changed choice of metrics.
struct TodayHealthLine: View {
    let line: String
    var onClose: () -> Void = {}
    @State private var showsDetail = false

    var body: some View {
        Button { showsDetail = true } label: {
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
        .sheet(isPresented: $showsDetail, onDismiss: onClose) { HealthDetailSheet() }
    }
}

/// The Health list in a sheet, with Done.
struct HealthDetailSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            HealthView()
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
        Button { showsSheet = true } label: {
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

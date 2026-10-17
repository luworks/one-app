import SwiftUI

/// Reads Apple Health for the line at the top of Today. Health data stays in memory (never in SwiftData or the widget).
/// HealthKit permission is asked the first time the line would show; with no data or no permission there is no line
/// (Health never says which).
@MainActor
@Observable
final class HealthLineModel {
    private let source: HealthSource = HealthSources.current()
    private(set) var snapshot: HealthSnapshot?

    func load() async {
        guard source.isAvailable else { return }
        await source.requestAccess()
        snapshot = (try? await source.snapshot(now: TodayClock.now)) ?? .empty
    }

    var line: String? { snapshot?.summaryLine(now: TodayClock.now) }
}

/// One quiet line at the top of Today (today only): "6,240 steps · slept 7 hr 12 min". Tap opens the Health sheet
/// (steps for 7 days, weight trend, recent nights), the same cards as the Health prototype. Read-only.
/// Off with Settings → Today → Health summary.
struct TodayHealthLine: View {
    let line: String
    @State private var showsDetail = false

    var body: some View {
        Button { showsDetail = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "heart.fill").font(.caption2).foregroundStyle(.pink)
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
        .accessibilityHint("Shows steps, weight and sleep")
        .accessibilityIdentifier("health.summary")
        .sheet(isPresented: $showsDetail) { HealthDetailSheet() }
    }
}

/// The Health cards in a sheet, with Done.
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

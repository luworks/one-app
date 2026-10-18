import SwiftUI

/// Add Metric: the supported metrics not shown yet, grouped, each with a one-line description. Tap to tick, Add to
/// show them. Adding asks Apple Health for read access to those types only (it skips the ones already allowed).
struct HealthMetricPicker: View {
    let hidden: [HealthMetric]
    let onAdd: ([HealthMetric]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var chosen: Set<HealthMetric> = []

    var body: some View {
        NavigationStack {
            List {
                if hidden.isEmpty {
                    Text("Every metric is already shown.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                        .accessibilityIdentifier("health.pick.none")
                }
                ForEach(HealthGroup.allCases, id: \.self) { group in
                    let metrics = hidden.filter { $0.group == group }
                    if !metrics.isEmpty {
                        Section(group.title) {
                            ForEach(metrics) { metric in row(metric) }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Add Metric")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        // Keep the catalog's order, not the order of the taps.
                        onAdd(HealthMetric.allCases.filter(chosen.contains))
                        dismiss()
                    }
                    .disabled(chosen.isEmpty)
                    .accessibilityIdentifier("health.pick.add")
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private func row(_ metric: HealthMetric) -> some View {
        let isChosen = chosen.contains(metric)
        return Button {
            if isChosen { chosen.remove(metric) } else { chosen.insert(metric) }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(metric.title).font(.body)
                    Text(metric.summary).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: isChosen ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isChosen ? HealthStyle.accent : Color(.tertiaryLabel))
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(metric.title). \(metric.summary)")
        .accessibilityValue(isChosen ? "Selected" : "Not selected")
        .accessibilityAddTraits(isChosen ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("health.pick.\(metric.rawValue)")
    }
}

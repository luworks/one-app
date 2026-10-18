import SwiftUI

/// All supported metrics with their current visibility. Changes are saved when the sheet closes;
/// new read-access requests wait until dismissal so Apple's permission sheet can appear safely.
struct HealthMetricPicker: View {
    @Binding var shown: Set<HealthMetric>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(HealthGroup.allCases, id: \.self) { group in
                    Section(group.title) {
                        ForEach(HealthMetric.allCases.filter { $0.group == group }) { metric in
                            Toggle(isOn: Binding(
                                get: { shown.contains(metric) },
                                set: { if $0 { shown.insert(metric) } else { shown.remove(metric) } }
                            )) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(metric.title).font(.body)
                                    Text(metric.summary)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .tint(HealthStyle.accent)
                            .frame(minHeight: 52)
                            .accessibilityIdentifier("health.pick.\(metric.rawValue)")
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .performanceDestination("health.picker")
            .navigationTitle("Health Metrics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("health.pick.add")
                }
            }
        }
        .presentationDragIndicator(.visible)
    }
}

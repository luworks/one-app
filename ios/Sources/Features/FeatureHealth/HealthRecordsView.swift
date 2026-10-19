#if os(iOS)
  import SwiftUI
  import TodayCore

  /// Nonnumeric records retain their own semantics instead of becoming synthetic trend values.
  struct HealthRecordsView: View {
    let source: any HealthRecordSource
    let runtime: PlannerRuntime
    @Environment(\.dismiss) private var dismiss

    var body: some View {
      NavigationStack {
        List {
          Section {
            ForEach(HealthRecordFamily.allCases) { family in
              NavigationLink {
                HealthRecordFamilyView(source: source, family: family, runtime: runtime)
              } label: {
                VStack(alignment: .leading, spacing: 4) {
                  Text(family.title)
                  Text(family.summary).font(.footnote).foregroundStyle(.secondary)
                }.padding(.vertical, 6)
              }
              .accessibilityIdentifier("health.records.\(family.rawValue)")
            }
          } footer: {
            Text(
              "Choose a family to request read access. Health values stay on this device. ECG waveforms, workout routes, heartbeat series, clinical records, medications, audiograms and vision prescriptions are not shown here."
            )
          }
        }
        .navigationTitle("Health Records")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
      }
    }
  }

  private struct HealthRecordFamilyView: View {
    let source: any HealthRecordSource
    let family: HealthRecordFamily
    let runtime: PlannerRuntime
    @State private var records: [HealthRecord] = []
    @State private var loading = false
    @State private var requested = false
    @State private var failed = false
    @State private var loadTask: Task<Void, Never>?

    var body: some View {
      List {
        Section {
          Text(family.summary)
          Text("Read-only · Last 90 days · Up to 1,000 recent records")
            .font(.footnote).foregroundStyle(.secondary)
          Button(requested ? "Refresh" : "Read \(family.title)") {
            loadTask?.cancel()
            loadTask = Task { await read() }
          }
          .frame(minHeight: 44)
          .disabled(loading)
          .accessibilityIdentifier("health.records.read")
          if loading { ProgressView("Reading Health…") }
          if failed {
            Text("Couldn't read these records. Try again.")
              .foregroundStyle(.secondary)
              .accessibilityIdentifier("health.records.error")
          } else if requested && !loading && records.isEmpty {
            Text(
              "No readable records. There may be no data, or access may be limited in Apple Health."
            )
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("health.records.empty")
          }
        }
        ForEach(Array(records.enumerated()), id: \.offset) { _, record in
          recordRow(record)
        }
      }
      .navigationTitle(family.title)
      .navigationBarTitleDisplayMode(.inline)
      .onDisappear { loadTask?.cancel() }
    }

    @MainActor private func read() async {
      loading = true
      failed = false
      defer { loading = false }
      do {
        // A completed request means the sheet finished; it never proves read permission was granted.
        if !requested { try await source.requestRecordAccess(for: [family]) }
        try Task.checkCancellation()
        let result = try await source.records(for: [family], days: 90, now: runtime.now())
        try Task.checkCancellation()
        records = result[family] ?? []
        requested = true
      } catch is CancellationError {
        return
      } catch {
        guard !Task.isCancelled else { return }
        failed = true
      }
    }

    @ViewBuilder private func recordRow(_ record: HealthRecord) -> some View {
      switch record {
      case .category(let item):
        VStack(alignment: .leading, spacing: 4) {
          Text(item.title).font(.headline)
          Text(item.value)
          date(item.start)
          if item.end > item.start {
            Text(item.end, style: .time).font(.footnote).foregroundStyle(.secondary)
          }
        }
      case .workout(let item):
        VStack(alignment: .leading, spacing: 4) {
          Text(item.title).font(.headline)
          Text(Duration.seconds(item.durationSeconds).formatted(.time(pattern: .hourMinuteSecond)))
            .monospacedDigit()
          date(item.start)
        }
      case .bloodPressure(let item):
        VStack(alignment: .leading, spacing: 4) {
          Text("\(item.systolic, specifier: "%.0f") / \(item.diastolic, specifier: "%.0f") mmHg")
            .font(.title3).monospacedDigit()
          Text("Systolic / Diastolic").font(.footnote).foregroundStyle(.secondary)
          date(item.date)
        }
      case .characteristic(let item):
        LabeledContent(item.field, value: item.value)
      }
    }

    private func date(_ value: Date) -> some View {
      Text(value, format: .dateTime.month(.abbreviated).day().year().hour().minute())
        .font(.footnote).foregroundStyle(.secondary)
    }
  }
#endif

#if os(iOS)
  import SwiftUI
  import TodayData

  struct FocusTarget: Identifiable {
    var identity: FocusIdentity?
    var reference: String?
    var title: String
    var id: String {
      (reference ?? identity?.item ?? "unavailable")
        + String(identity?.occurrence?.timeIntervalSince1970 ?? 0)
    }
  }

  struct TodayFocusRowActions: ViewModifier {
    let enabled: Bool
    let settle: () -> Void
    let snooze: () -> Void

    @ViewBuilder func body(content: Content) -> some View {
      if enabled {
        content
          .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button(action: settle) { Label("Settle", systemImage: "checkmark") }.tint(.indigo)
            Button(action: snooze) { Label("Snooze", systemImage: "clock") }.tint(.gray)
          }
          .accessibilityAction(named: "Settle", settle)
          .accessibilityAction(named: "Snooze", snooze)
      } else {
        content
      }
    }
  }

  struct TodaySnoozeSheet: View {
    let now: Date
    let calendar: Calendar
    let commit: (Date) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var custom = false
    @State private var until: Date

    init(now: Date, calendar: Calendar, commit: @escaping (Date) -> Void) {
      self.now = now
      self.calendar = calendar
      self.commit = commit
      _until = State(initialValue: now.addingTimeInterval(3600))
    }

    var body: some View {
      NavigationStack {
        Form {
          Section {
            Button("In 1 hour") { choose(now.addingTimeInterval(3600)) }
            Button("Tomorrow morning") {
              let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
              choose(
                calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow)
            }
            Button("Choose date and time") { custom = true }
            if custom {
              DatePicker(
                "Return to Today", selection: $until, in: now...,
                displayedComponents: [.date, .hourAndMinute]
              )
              .accessibilityIdentifier("focus.snoozeUntil")
              Button("Snooze") { choose(until) }.disabled(until <= now)
            }
          } footer: {
            Text("Only hides this item in Today. Dates and alerts stay unchanged.")
          }
        }
        .navigationTitle("Snooze")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
      }
      .presentationDetents([.medium, .large])
    }

    private func choose(_ date: Date) {
      guard date > now, date.timeIntervalSinceReferenceDate.isFinite else { return }
      commit(date)
      dismiss()
    }
  }
#endif

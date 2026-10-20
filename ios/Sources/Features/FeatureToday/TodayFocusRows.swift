#if os(iOS)
  import SwiftUI
  import TodayCore
  import TodayData
  import TodayPlannerUI

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
    var open: (() -> Void)? = nil
    var delete: (() -> Void)? = nil
    var restore: (() -> Void)? = nil
    var showSettle = true
    var showSnooze = true
    var restoreLabel = "Restore"

    @ViewBuilder private var attentionButtons: some View {
      if let restore {
        Button(restoreLabel, systemImage: "arrow.uturn.backward", action: restore)
      } else if showSettle {
        Button("Settle", systemImage: "checkmark.circle.fill", action: settle)
      }
      if showSnooze {
        Button(
          restore == nil ? "Snooze" : "Change Snooze", systemImage: "clock.circle.fill",
          action: snooze)
      }
    }

    @ViewBuilder func body(content: Content) -> some View {
      if enabled {
        content
          .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if let delete { Button("Delete", systemImage: "trash", action: delete).tint(.red) }
            if showSnooze {
              Button(
                restore == nil ? "Snooze" : "Change Snooze", systemImage: "clock.circle.fill",
                action: snooze
              ).tint(.gray)
            }
            if let restore {
              Button(restoreLabel, systemImage: "arrow.uturn.backward", action: restore).tint(
                .indigo)
            } else if showSettle {
              Button("Settle", systemImage: "checkmark.circle.fill", action: settle).tint(.indigo)
            }
          }
          .contextMenu {
            if let open { Section { Button("Open", systemImage: "pencil", action: open) } }
            Section { attentionButtons }
            if let delete {
              Section { Button("Delete", systemImage: "trash", role: .destructive, action: delete) }
            }
          }
          .accessibilityActions {
            attentionButtons
            if let delete { Button("Delete", action: delete) }
          }
      } else {
        content
      }
    }
  }

  struct TodaySnoozeSheet: View {
    let now: () -> Date
    @State private var initialNow: Date
    let calendar: Calendar
    let commit: (Date) -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var validation: String?
    @State private var custom = false
    @State private var committing = false
    @State private var until: Date

    init(now: @escaping () -> Date, calendar: Calendar, commit: @escaping (Date) -> Bool) {
      self.now = now
      let initialNow = now()
      _initialNow = State(initialValue: initialNow)
      self.calendar = calendar
      self.commit = commit
      _until = State(initialValue: initialNow.addingTimeInterval(3600))
    }

    var body: some View {
      NavigationStack {
        Form {
          Section {
            Button("In 1 hour") { choose(.inOneHour) }
            Button("Tomorrow morning") { choose(.tomorrowMorning) }
            Button("Choose date and time") { custom = true }
            if custom {
              DatePicker(
                "Return to Today", selection: $until, in: initialNow...,
                displayedComponents: [.date, .hourAndMinute]
              )
              .accessibilityIdentifier("focus.snoozeUntil")
              .onChange(of: until) { validation = nil }
              Button("Snooze") { choose(.custom(until)) }
            }
            if let validation {
              Text(validation).foregroundStyle(.red)
                .accessibilityIdentifier("focus.snoozeValidation")
            }
          } footer: {
            Text("Only hides this item in Today. Dates and alerts stay unchanged.")
          }
        }
        .disabled(committing)
        .navigationTitle("Snooze")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
      }
      .presentationDetents([.medium, .large])
    }

    private func choose(_ selection: SnoozeSelection) {
      guard !committing else { return }
      guard let date = selection.resolve(now: now(), calendar: calendar) else {
        validation = "Choose a future date and time, then tap Snooze again."
        return
      }
      committing = true
      if commit(date) {
        dismiss()
      } else {
        committing = false
        validation = "Couldn't snooze this item. Check the time or refresh Today, then try again."
      }
    }
  }
#endif

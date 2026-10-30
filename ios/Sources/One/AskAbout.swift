#if os(iOS)
  import TodayCore
  import SwiftUI

  /// "Ask AI" in an item's long-press menu: the shell opens a new chat about that item. Nil where no chat can open
  /// (previews, tests), and the menu then simply has no Ask AI row.
  package typealias AskAboutAction = @MainActor (AskSubject) -> Void

  private struct AskAboutKey: EnvironmentKey {
    static var defaultValue: AskAboutAction? { nil }
  }

  extension EnvironmentValues {
    package var askAbout: AskAboutAction? {
      get { self[AskAboutKey.self] }
      set { self[AskAboutKey.self] = newValue }
    }
  }

  extension AskSubject {
    package init(task: OneTask) {
      var details: [String] = []
      if task.repeatRule != nil { details.append("repeats") }
      if !task.listName.isEmpty { details.append("list \(task.listName)") }
      if task.flagged { details.append("flagged") }
      if task.isDone { details.append("done") }
      if task.ringsAsAlarm { details.append("rings as an alarm") }
      if !task.note.isEmpty { details.append("note: \(task.note)") }
      self.init(
        kind: .reminder, title: task.title, start: task.due,
        minutes: task.due == nil ? 0 : task.durationMinutes, details: details)
    }

    package init(alarm: OneAlarm) {
      var details = [String(format: "rings at %02d:%02d", alarm.hour, alarm.minute)]
      let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
      let days = alarm.weekdays.sorted().compactMap { (1...7).contains($0) ? names[$0 - 1] : nil }
      details.append(days.isEmpty ? "once" : "repeats " + days.joined(separator: " "))
      if !alarm.isOn { details.append("off") }
      self.init(
        kind: .alarm, title: alarm.label.isEmpty ? "Alarm" : alarm.label, details: details)
    }

    package init(entry: CalEntry) {
      switch entry.source {
      case .task(let task): self.init(task: task)
      case .alarm(let alarm): self.init(alarm: alarm)
      case .system, .local:
        var details: [String] = []
        if entry.repeats { details.append("repeats") }
        if !entry.calendarTitle.isEmpty { details.append("calendar \(entry.calendarTitle)") }
        if !entry.location.isEmpty { details.append("at \(entry.location)") }
        let minutes = Int(entry.end.timeIntervalSince(entry.start) / 60)
        self.init(
          kind: .event, title: entry.title, start: entry.start, isAllDay: entry.isAllDay,
          minutes: entry.isAllDay ? 0 : max(0, minutes), details: details)
      }
    }
  }

  /// The first row of an item's menu. Reads the action from the environment, so it only shows where a chat can open.
  package struct AskAIMenuButton: View {
    @Environment(\.askAbout) private var askAbout
    private let subject: AskSubject
    package init(_ subject: AskSubject) { self.subject = subject }

    package var body: some View {
      if let askAbout {
        Button {
          askAbout(subject)
        } label: {
          Label("Ask AI", systemImage: "sparkles")
        }
        .accessibilityIdentifier("ask-ai-about")
      }
    }
  }
#endif

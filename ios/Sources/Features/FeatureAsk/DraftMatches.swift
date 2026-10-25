#if os(iOS)
  import One
  import TodayCore
  import SwiftUI
  import SwiftData

  /// While the user types in Chat, the existing reminders and events that match, so Chat doubles as search.
  /// Tapping one opens it; sending the text still goes to the AI as before.
  struct DraftMatches: View {
    let draft: String
    let tasks: [OneTask]
    let events: [OneEvent]
    let now: Date
    let label: (Date?) -> String
    let openTask: (OneTask) -> Void
    let openEvent: (OneEvent) -> Void

    private enum Hit: Identifiable {
      case task(OneTask)
      case event(OneEvent)
      var id: PersistentIdentifier {
        switch self {
        case .task(let t): t.persistentModelID
        case .event(let e): e.persistentModelID
        }
      }
    }

    private var hits: [Hit] {
      let candidates =
        tasks.enumerated().map { i, t in
          DraftMatch.Candidate(
            id: i, fields: [t.title, t.note, t.listName] + t.tags, date: t.due, isDone: t.isDone)
        }
        + events.enumerated().map { i, e in
          DraftMatch.Candidate(
            id: tasks.count + i, fields: [e.title, e.calendarName], date: e.start)
        }
      return DraftMatch.pick(draft, from: candidates, now: now).map {
        $0 < tasks.count ? .task(tasks[$0]) : .event(events[$0 - tasks.count])
      }
    }

    var body: some View {
      let hits = hits
      if !hits.isEmpty {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(hits) { hit in
            Button {
              switch hit {
              case .task(let t): openTask(t)
              case .event(let e): openEvent(e)
              }
            } label: {
              row(hit)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("ask.match")
          }
        }
        .padding(.vertical, 4)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Matching items")
      }
    }

    private func row(_ hit: Hit) -> some View {
      let icon: String
      let title: String
      let date: Date?
      switch hit {
      case .task(let t): (icon, title, date) = ("circle", t.title, t.due)
      case .event(let e): (icon, title, date) = ("calendar", e.title, e.start)
      }
      return HStack(spacing: 10) {
        Image(systemName: icon).foregroundStyle(.secondary).frame(width: 20)
        Text(title).lineLimit(1)
        Spacer(minLength: 8)
        Text(label(date)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
      }
      .font(.subheadline)
      .padding(.horizontal, 14)
      .frame(minHeight: 44)
      .contentShape(Rectangle())
    }
  }
#endif

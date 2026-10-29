#if os(iOS)
  import Foundation
  import TodayCore
  import FoundationModels

  /// The model half of "move / delete / ask": it only picks an operation and a target id.
  /// Code decides everything that has to be exact (whether the sentence is an edit at all, which item the words name, the new time):
  /// see EditingLogic.swift, which is plain Swift and unit-tested. Nothing here writes anything: the result feeds a ChangeCard and
  /// the user's Apply.

  @Generable
  package enum EditOp: String, Sendable {
    case move, delete, clarify, none
  }

  @Generable
  package struct EditPlan: Sendable {
    package var op: EditOp
    @Guide(
      description: "id of the one item the message names, from the list. Empty if none or unsure")
    package var target: String?
    package init(op: EditOp, target: String?) {
      self.op = op
      self.target = target
    }
  }

  extension EditPlan {
    var pick: EditPick { EditPick(target: target) }
  }

  extension Editing {
    static func instructions(items: [EditItem], now: Date, calendar: Calendar, history: String = "")
      -> String
    {
      let day = DateFormatter()
      day.calendar = calendar
      day.timeZone = calendar.timeZone
      day.locale = Locale(identifier: "en_US_POSIX")
      day.dateFormat = "EEEE yyyy-MM-dd HH:mm"
      let today = calendar.startOfDay(for: now)
      let rows = items.map { i -> String in
        let when: String
        if let s = i.start {
          let d =
            calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: s)).day ?? 0
          let c = calendar.dateComponents([.hour, .minute], from: s)
          when = String(format: "day %d %02d:%02d", d, c.hour ?? 0, c.minute ?? 0)
        } else {
          when = "unscheduled"
        }
        return "\(i.id) | \(i.type) | \(i.title) | \(when) | \(i.minutes) | \(i.attendees)"
      }
      return [
        "You edit a planner. Today is \(day.string(from: now)).",
        "Items the person can mean (id | type | title | when | minutes | attendees):",
        rows.joined(separator: "\n"),
        "op: move = reschedule ONE item. delete = remove ONE item. clarify = you cannot tell which item or what time. none = the message is not an edit.",
        "target is the id of the item the message names. Never invent an id.",
      ]
      .appending(
        history.isEmpty
          ? []
          : [
            "The conversation so far (\"it\" and \"that one\" mean the item talked about last):",
            history,
          ]
      )
      .joined(separator: "\n")
    }

    /// One request, one fresh session. Throws on any model error.
    static func plan(
      _ text: String, items: [EditItem], now: Date, calendar: Calendar, history: String = ""
    ) async throws -> EditPlan {
      let session = LanguageModelSession(
        instructions: instructions(items: items, now: now, calendar: calendar, history: history))
      return try await ModelCallTrace.generate(.edit) {
        try await session.respond(to: text, generating: EditPlan.self).content
      }
    }
  }

  extension Array {
    fileprivate func appending(_ other: [Element]) -> [Element] { self + other }
  }

#endif

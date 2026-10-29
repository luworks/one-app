#if os(iOS)
  import Foundation
  import TodayCore

  /// GPT proposes bounded drafts; local mapping, Add/Apply and save receipts stay authoritative.
  enum AICapture {
    static var isAvailable: Bool { HostedGPT.isAvailable }

    private struct ProposedItems: Codable, Sendable { let items: [ProposedItem] }
    private struct ProposedItem: Codable, Sendable {
      let title: String
      let kind: String
      let date: String?
      let time: String?
      let durationMinutes: Int?
      let repeats: String
      let repeatWeekdays: [Int]?
      let allDay: Bool
    }
    private struct RefinedTitle: Codable, Sendable { let title: String }

    static func propose(_ text: String, now: Date = .now, calendar: Calendar = .current) async
      -> [Capture]?
    {
      guard isAvailable else { return nil }
      return await ModelTimeout.run(seconds: 12) {
        do {
          let result = try await HostedGPT.generate(
            ProposedItems.self, stage: "propose",
            instructions: CaptureDraftMapper.instructions(now: now, calendar: calendar)
              + "\nReturn one to five items. Preserve negation, conditions and modality in titles. Never invent recurrence.",
            input: text,
            schema: .object([
              "items": .array(
                .object([
                  "title": .string, "kind": .enumeration(["task", "event"]),
                  "date": .nullable(.string), "time": .nullable(.string),
                  "durationMinutes": .nullable(.integer),
                  "repeats": .enumeration([
                    "never", "daily", "weekdays", "weekly", "monthly", "yearly",
                  ]),
                  "repeatWeekdays": .nullable(.array(.integer)), "allDay": .boolean,
                ]))
            ]))
          guard (1...5).contains(result.items.count) else { return nil }
          let captures = result.items.compactMap { item -> Capture? in
            let draft = CaptureDraft(
              kind: item.kind, title: item.title, date: item.date, time: item.time,
              durationMinutes: item.durationMinutes, repeatRule: item.repeats,
              isAllDay: item.allDay, repeatWeekdays: item.repeatWeekdays)
            guard var c = CaptureDraftMapper.capture(from: draft, now: now, calendar: calendar)
            else { return nil }
            c.title = CaptureDraftMapper.userWording(c.title, source: text)
            return c
          }
          return captures.isEmpty ? nil : captures
        } catch { return nil }
      }
    }

    static func refineTitle(_ capture: Capture, source: String, history: String = "") async
      -> Capture
    {
      await CaptureTitleRefinement.refine(
        capture, source: source, history: history, available: isAvailable
      ) { prompt in
        try? await HostedGPT.generate(
          RefinedTitle.self, stage: "title", instructions: CaptureTitleRefinement.instructions,
          input: prompt, schema: .object(["title": .string])
        ).title
      }
    }
  }
#endif

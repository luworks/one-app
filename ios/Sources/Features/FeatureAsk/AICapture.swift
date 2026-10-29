#if os(iOS)
  import Foundation
  import TodayCore
  #if canImport(FoundationModels)
    import FoundationModels
  #endif

  /// Turns a typed or dictated line into proposed items with the on-device Apple Intelligence model.
  /// Everything stays on the device: no network, no third-party packages. The model only PROPOSES `Capture`s for the
  /// preview card; nothing is created until the user taps Add.
  ///
  /// Compiles and runs on iOS 17+. Where Apple Intelligence is missing (older iOS, unsupported device or locale,
  /// turned off, model still downloading) `isAvailable` is false, and any failure returns nil from `propose`.
  /// In both cases the caller uses the rule-based `CaptureParser`, exactly as before.
  enum AICapture {
    /// True when the on-device model can answer right now. Cheap; call it per request.
    static var isAvailable: Bool {
      #if canImport(FoundationModels)
        if #available(iOS 26, *) { return OnDeviceCapture.isAvailable }
        return false
      #else
        return false
      #endif
    }

    /// Up to 5 proposals for one line, in the order mentioned, or nil when the caller should fall back to the
    /// rule parser (model unavailable, generation failed, nothing usable came back).
    static func propose(_ text: String, now: Date = .now, calendar: Calendar = .current) async
      -> [Capture]?
    {
      #if canImport(FoundationModels)
        if #available(iOS 26, *) {
          // The model can stall (still warming up, busy): after 8 seconds the caller falls back to the rule parser.
          return await ModelTimeout.run(seconds: 8, stage: .proposals) {
            await OnDeviceCapture.propose(text, now: now, calendar: calendar)
          }
        }
      #endif
      return nil
    }

    /// Single-item production title generation, separately bounded from kind classification.
    /// The generated schema contains only a title; all dates, times, type and repeat fields come from the existing capture.
    static func refineTitle(_ capture: Capture, source: String, history: String = "") async
      -> Capture
    {
      await ModelCallTrace.scoped(.title) {
        let result = await CaptureTitleRefinement.refine(
          capture, source: source, history: history, available: isAvailable
        ) { prompt in
          #if canImport(FoundationModels)
            if #available(iOS 26, *) { return await OnDeviceCapture.refineTitle(prompt) }
          #endif
          return nil
        }
        ModelCallTrace.selection(
          result.fromAppleIntelligence ? "model_title_selected" : "title_fallback_selected")
        return result
      }
    }
  }

  #if canImport(FoundationModels)

    @available(iOS 26, *)
    @Generable(description: "A concise faithful planner action title; no scheduling fields")
    private struct RefinedCaptureTitle {
      var title: String
    }

    @available(iOS 26, *)
    @Generable(description: "Everything the user's line asks to add to their planner")
    private struct ProposedItems {
      @Guide(
        description: "One entry per separate thing mentioned, in the order mentioned",
        .minimumCount(1), .maximumCount(5))
      var items: [ProposedItem]
    }

    @available(iOS 26, *)
    @Generable(description: "One task or event to propose")
    private struct ProposedItem {
      @Guide(
        description:
          "Concise faithful action in the user's language. Omit scheduling words, dangling temporal connectors, reminder requests and boundary punctuation. Preserve conditions, negation and modality such as 必须要 or must not; never reduce to one word"
      )
      var title: String
      @Guide(description: "event: fixed time or place or start and end; task: something to do")
      var kind: ProposedKind
      @Guide(description: "yyyy-MM-dd, copied from the date table. Empty if the text names no day")
      var date: String?
      @Guide(description: "24-hour HH:mm. Empty if the text names no time")
      var time: String?
      @Guide(description: "Length in minutes, only if a length or an end time is given")
      var durationMinutes: Int?
      @Guide(description: "How often it repeats; never if the text does not say")
      var repeats: ProposedRepeat
      @Guide(
        description:
          "All explicitly requested weekly weekdays: Sunday=1 through Saturday=7. Friday AND Sunday is [6,1]. Empty for non-weekly recurrence"
      )
      var repeatWeekdays: [Int]?
      @Guide(description: "True only for an event that lasts the whole day and has no time")
      var allDay: Bool
    }

    @available(iOS 26, *)
    @Generable
    private enum ProposedKind { case task, event }

    @available(iOS 26, *)
    @Generable
    private enum ProposedRepeat { case never, daily, weekdays, weekly, monthly, yearly }

    @available(iOS 26, *)
    private enum OnDeviceCapture {
      static var isAvailable: Bool {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else { return false }
        return model.supportsLocale()
      }

      static func refineTitle(_ prompt: String) async -> String? {
        guard isAvailable else {
          ModelCallTrace.selection("unavailable")
          return nil
        }
        let session = LanguageModelSession(
          model: .default, instructions: CaptureTitleRefinement.instructions)
        var options = GenerationOptions()
        options.temperature = 0
        options.maximumResponseTokens = 160
        do {
          return try await ModelCallTrace.generate(.title) {
            try await session.respond(
              to: prompt, generating: RefinedCaptureTitle.self, options: options
            ).content.title
          }
        } catch { return nil }
      }

      static func propose(_ text: String, now: Date, calendar: Calendar) async -> [Capture]? {
        guard isAvailable else {
          ModelCallTrace.selection("unavailable")
          return nil
        }
        // A fresh session per line: the instructions carry today's date, and no history is kept.
        let session = LanguageModelSession(
          model: .default,
          instructions: CaptureDraftMapper.instructions(now: now, calendar: calendar))
        var options = GenerationOptions()
        options.temperature = 0  // stable output; this is extraction, not writing
        options.maximumResponseTokens = 700
        do {
          let result = try await ModelCallTrace.generate(.proposals) {
            try await session.respond(
              to: text, generating: ProposedItems.self, options: options)
          }
          guard
            let mapped = CaptureDraftMapper.captures(
              from: result.content.items.map(draft), now: now, calendar: calendar)
          else {
            ModelCallTrace.selection("proposals_incomplete")
            return nil
          }
          let captures = mapped.map { item in
            var capture = item
            capture.title = CaptureDraftMapper.userWording(capture.title, source: text)
            return capture
          }
          ModelCallTrace.selection("model_proposals_selected")
          return captures
        } catch {
          // Guardrails, unsupported language, context size, cancelled, model went away: use the rule parser.
          return nil
        }
      }

      private static func draft(_ item: ProposedItem) -> CaptureDraft {
        CaptureDraft(
          kind: item.kind == .event ? "event" : "task",
          title: item.title,
          date: item.date,
          time: item.time,
          durationMinutes: item.durationMinutes,
          repeatRule: String(describing: item.repeats),
          isAllDay: item.allDay,
          repeatWeekdays: item.repeatWeekdays)
      }
    }

  #endif

#endif

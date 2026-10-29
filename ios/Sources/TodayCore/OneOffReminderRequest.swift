import Foundation

/// A narrow submitted-message authority, separate from seven-day background grants.
/// Rules must establish the action and timing; model output alone cannot authorize a write.
public enum OneOffReminderRequest {
  public static func capture(
    _ text: String, now: Date, calendar: Calendar,
    existingItems: () -> [EditItem] = { [] }
  ) -> Capture? {
    guard SubmittedActionAnalysis.analyze(text).permitsDirectCreation,
      ChatRouting.intent(text) == .capture, !ChatRouting.requestsEvent(text),
      !ChatRouting.hasMultipleActions(text), !ChatRouting.hasMaterialCorrection(text),
      CaptureParser.leadingMonth(text) == nil,
      !CaptureConversation.referencesReminder(text),
      text.range(
        of:
          #"[;；\n]|然后|另外还|\band then\b|\bevery\b|\brecurr|重复|每|还是|或者|\bor\b|\b(?:alarm|timer)\b|wake me|闹钟|计时器|叫醒|叫我起床"#,
        options: [.regularExpression, .caseInsensitive]) == nil
    else { return nil }
    // A clock/date-only refinement needs conversation state, never a fresh creation grant.
    guard !Dialogue.isOnlyWhen(text, now: now, calendar: calendar) else { return nil }
    // Operations matching existing candidates retain their edit/ambiguity boundary.
    // Ordinary new reminders never need a candidate lookup or a model call here.
    if Editing.hasOperationCue(text),
      Editing.looksLikeEdit(text, items: existingItems(), now: now, calendar: calendar)
    {
      return nil
    }
    let capture = CaptureConversation.parse(text, now: now, calendar: calendar)
    return eligible(capture) ? capture : nil
  }

  /// Recovery can use the original subject, but never erase ambiguity or recurrence words
  /// just because the parsed result omitted them.
  public static func contextAllows(
    _ context: ConversationContext, now: Date = .now, calendar: Calendar = .current
  ) -> Bool {
    guard let text = contextSubject(context, now: now, calendar: calendar),
      SubmittedActionAnalysis.analyze(text).permitsDirectCreation,
      CaptureParser.leadingMonth(text) == nil,
      !ChatRouting.hasMultipleActions(text), !ChatRouting.hasMaterialCorrection(text)
    else { return false }
    return text.range(
      of: #"还是|或者|\bor\b|\bevery\b|\brecurr|重复|每"#,
      options: [.regularExpression, .caseInsensitive]) == nil
  }

  public static func contextAnalysis(
    _ context: ConversationContext, now: Date, calendar: Calendar
  ) -> SubmittedActionAnalysis? {
    guard let text = contextSubject(context, now: now, calendar: calendar) else { return nil }
    return SubmittedActionAnalysis.analyze(text)
  }

  private static func contextSubject(
    _ context: ConversationContext, now: Date, calendar: Calendar
  ) -> String? {
    for turn in context.userTurns.reversed() {
      let text = turn.text
      // A timing answer cannot establish the action count. Keep looking for the
      // actual user subject instead of laundering a previously merged draft.
      if ChatRouting.isContextQuestion(text)
        || CaptureConversation.referencesReminder(text)
        || CaptureConversation.isOneOffAnswer(text)
        || CaptureConversation.referencesAlarm(text)
        || CaptureConversation.proceeds(text)
        || CaptureConversation.acknowledges(text)
      {
        continue
      }
      if Dialogue.isOnlyWhen(text, now: turn.timestamp ?? now, calendar: calendar),
        text.range(
          of: #"\bevery\b|\brecurr|重复|每"#,
          options: [.regularExpression, .caseInsensitive]) == nil,
        SubmittedActionAnalysis.analyze(text).permitsDirectCreation
      {
        continue
      }
      return text
    }
    return nil
  }

  public static func eligible(_ capture: Capture) -> Bool {
    guard capture.kind == .task, !capture.ringsAsAlarm, capture.repeatRule == nil,
      SubmittedActionAnalysis.hasCompleteTitle(capture.title),
      !capture.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      capture.title.range(
        of:
          #"^(?:something|anything|a reminder|reminder|remind me|new task|task|alarm|timer|提醒|提醒我|一个提醒|任务|闹钟|计时器|某事)[.!。]*$"#,
        options: [.regularExpression, .caseInsensitive]) == nil
    else { return false }
    return true
  }

  /// Only continuation answers reuse a prior card. A freshly submitted action is a new request.
  public static func matches(_ lhs: Capture, _ rhs: Capture) -> Bool {
    lhs.title == rhs.title && lhs.kind == rhs.kind && lhs.day == rhs.day
      && lhs.hour == rhs.hour && lhs.minute == rhs.minute && lhs.repeatRule == rhs.repeatRule
      && lhs.ringsAsAlarm == rhs.ringsAsAlarm && lhs.isWorkBlock == rhs.isWorkBlock
  }
}

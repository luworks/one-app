import Foundation

/// A rule-owned boundary, never inferred from a model's output count. Unsupported
/// coordination is a question, not permission to merge actions into one write.
public enum SubmittedActionAnalysis: Equatable, Sendable {
  case single
  case multiple(clauses: [String], prefix: String)
  case uncertain

  public static func analyze(_ text: String) -> Self {
    guard let quoted = unquoted(text) else { return .uncertain }
    let visible = CaptureParser.maskingWeeklyDays(in: quoted)
    if matches(visible, #"还是|或者|\bor\b|不对|改口|\b(?:actually|rather|no,|scratch that)\b"#) {
      return .uncertain
    }
    let pattern =
      #"[,，]\s*(?=(?:call|email|send|pay|submit|collect|pick\s+up|return|renew|water|read|clean|book|take|buy)\b|买|取|打电话|给.+?打电话|发邮件)|[;；\n]+|然后|另外还|再(?:提醒我)?|同时|顺便|还有|以及|并且|\band\s+then\b|\b(?:and|then|plus|also)\b|和|及|、|&"#
    let ns = visible as NSString
    let separators =
      (try? NSRegularExpression(pattern: pattern, options: .caseInsensitive))?
      .matches(in: visible, range: NSRange(location: 0, length: ns.length)) ?? []
    guard !separators.isEmpty else {
      // Commas/slashes left in the action title can coordinate unsupported
      // predicates too; failure to recognize a verb is never permission.
      let title = CaptureParser.parse(visible).title
      // Audit the original action span before motivation/title cleanup. A second
      // action moved into notes is still part of the submitted authorization.
      let body: String
      if let range = visible.range(of: title, options: .caseInsensitive), !title.isEmpty {
        body = String(visible[range.lowerBound...])
      } else {
        body = visible
      }
      var audited = body.replacingOccurrences(
        of: #"\b(Dr|Mr|Mrs|Ms|Prof|Sr|Jr|St)\."#, with: "$1", options: .regularExpression)
      audited = audited.replacingOccurrences(
        of: #"[.!。！]+\s*$"#, with: "", options: .regularExpression)
      audited = audited.replacingOccurrences(
        of: #"(?<=\d):(?=\d)"#, with: "", options: .regularExpression)
      audited = audited.replacingOccurrences(
        of: #"\b\d{1,2}/\d{1,2}\b"#, with: "", options: .regularExpression)
      audited = audited.replacingOccurrences(
        of: #"(?i)(?<=\d)\s*[ap]\.m\."#, with: "", options: .regularExpression)
      if matches(audited, #"[,，/+:：。!?！？()–—]|(?<=\s)-(?=\s)|(?<!\d)\.|\.(?!\d)"#) {
        return .uncertain
      }
      let remaining = CaptureParser.parse(title)
      if remaining.hour != nil || remaining.hasDay || remaining.repeatRule != nil {
        return .uncertain
      }
      return .single
    }
    // Relative/subordinate wording does not prove independent predicates.
    if matches(visible, #"\b(?:about|how|whether|if)\b|关于|如何|是否"#) { return .uncertain }
    let original = text as NSString
    var parts: [String] = []
    var start = 0
    for separator in separators {
      parts.append(
        original.substring(with: NSRange(location: start, length: separator.range.location - start))
      )
      start = NSMaxRange(separator.range)
    }
    parts.append(original.substring(from: start))
    parts = parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    // These predicates establish a supported clause positively. The absence of a
    // known predicate never establishes a single action (including object lists).
    let predicate =
      #"\b(?:buy|call|email|send|pay|submit|collect|pick\s+up|return|renew|water|read|clean|book|take)\b|买|购买|给.+?打电话|打电话|取|拿|交|缴|寄|发送|发邮件|浇|读|阅读|打扫|预约|吃"#
    guard let regex = try? NSRegularExpression(pattern: predicate, options: .caseInsensitive)
    else { return .uncertain }
    var ranges: [NSRange] = []
    for part in parts {
      // Every candidate clause must independently establish one complete action;
      // a supported first predicate cannot hide an unsupported third action.
      guard analyze(part) == .single else { return .uncertain }
      let actionTitle = CaptureParser.parse(part).title
      guard
        actionTitle.range(
          of: "^(?:" + predicate + ")", options: [.regularExpression, .caseInsensitive]) != nil
      else { return .uncertain }
      let range = NSRange(location: 0, length: (part as NSString).length)
      guard let action = regex.firstMatch(in: part, range: range),
        NSMaxRange(action.range) < range.length
          || (part as NSString).substring(with: action.range).hasPrefix("给")
      else { return .uncertain }
      ranges.append(action.range)
    }
    let prefix = (parts[0] as NSString).substring(to: ranges[0].location)
    // A prefix can carry global scheduling or a reminder wrapper. Later clauses
    // inherit that prefix, never the first action's local trailing clock time.
    return .multiple(clauses: parts, prefix: prefix)
  }

  /// Deterministic previews keep all clauses even when generation is unavailable
  /// or fails. Ambiguous time scope must be clarified before showing a batch.
  public func previews(now: Date, calendar: Calendar) -> [Capture]? {
    guard case .multiple(let clauses, let prefix) = self else { return nil }
    let midnight = calendar.startOfDay(for: now)
    let global = CaptureConversation.parse(prefix, now: midnight, calendar: calendar)
    let explicitDays = clauses.map {
      CaptureConversation.parse($0, now: midnight, calendar: calendar).hasDay
    }
    // A date attached to only a later/local clause may scope the whole list.
    // Do not guess today for the other actions when that scope is unresolved.
    if !global.hasDay, explicitDays.contains(true), explicitDays.contains(false) { return nil }
    var captures = clauses.map { CaptureConversation.parse($0, now: now, calendar: calendar) }
    for index in captures.indices.dropFirst() {
      let local = CaptureConversation.parse(clauses[index], now: midnight, calendar: calendar)
      if global.hasDay && !local.hasDay {
        captures[index].day = global.day
        captures[index].hasDay = true
      }
      if let repeatRule = global.repeatRule, captures[index].repeatRule == nil {
        // An explicit local calendar date conflicts with inherited recurrence;
        // do not silently choose which schedule wins.
        guard !local.hasDay else { return nil }
        captures[index].repeatRule = repeatRule
      }
      if captures[index].hour == nil, let hour = global.hour {
        captures[index].hour = hour
        captures[index].minute = global.minute
        if !captures[index].hasDay {
          captures[index].day = CaptureConversation.parse(prefix, now: now, calendar: calendar).day
        }
      }
    }
    for index in captures.indices {
      if let raw = captures[index].repeatRule, let rule = RepeatRule(rawValue: raw),
        let clock = captures[index].clockTime(calendar: calendar), clock < now
      {
        captures[index].day = rule.next(after: captures[index].day, calendar: calendar)
      }
    }
    guard captures.allSatisfy({ !$0.title.isEmpty }) else { return nil }
    // A clock attached to only some coordinated actions has ambiguous scope.
    let timed = captures.filter { $0.hour != nil }.count
    guard timed == 0 || timed == captures.count else { return nil }
    return captures
  }

  public var permitsDirectCreation: Bool { self == .single }

  private static func matches(_ text: String, _ pattern: String) -> Bool {
    text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
  }

  /// Preserve UTF-16 offsets while hiding balanced quoted titles. Bracketed
  /// content remains visible: parentheses can contain an additional action.
  /// Unbalanced quotation cannot prove a single action.
  private static func unquoted(_ text: String) -> String? {
    let pairs: [UInt16: UInt16] = [
      34: 34, 0x201C: 0x201D, 0x300C: 0x300D, 0x300E: 0x300F, 0x300A: 0x300B,
      40: 41, 91: 93, 0xFF08: 0xFF09, 0x3010: 0x3011,
    ]
    let quoteClosings: Set<UInt16> = [34, 0x201D, 0x300D, 0x300F, 0x300B]
    var stack: [UInt16] = []
    var output: [UInt16] = []
    for unit in text.utf16 {
      let hidden = stack.contains { quoteClosings.contains($0) }
      if unit == stack.last {
        let closing = stack.removeLast()
        output.append(hidden || quoteClosings.contains(closing) ? 32 : unit)
      } else if let closing = pairs[unit] {
        stack.append(closing)
        output.append(hidden || quoteClosings.contains(closing) ? 32 : unit)
      } else {
        if !hidden, Set(pairs.values).contains(unit) { return nil }
        output.append(hidden ? 32 : unit)
      }
    }
    return stack.isEmpty ? String(decoding: output, as: UTF16.self) : nil
  }
}

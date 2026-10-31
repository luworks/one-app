import Foundation

/// A proposed change, not permission to write. The caller must revalidate the item and show a preview.
public struct AttachedItemEdit: Equatable {
  public enum Operation: Equatable { case move(Date), rename(String), delete, done }
  public var target: String?
  public var operation: Operation?
  public var reason: String

  public init(target: String?, operation: Operation?, reason: String) {
    self.target = target
    self.operation = operation
    self.reason = reason
  }
}

/// Conservative grammar for an explicit reference to the item attached to this conversation.
/// No title-based lookup is used: an attachment must be supplied by stable item ID.
public enum AttachedItemEditing {
  private static func captures(_ text: String, _ pattern: String) -> [String]? {
    guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
      let match = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
    else { return nil }
    return (1..<match.numberOfRanges).map { index in
      Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
    }
  }

  /// Returns nil for sentences outside this narrow grammar; incomplete requests return a clarification.
  public static func parse(
    _ raw: String, attachedItemID: String?, items: [EditItem], now: Date, calendar: Calendar
  ) -> AttachedItemEdit? {
    let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let end = #"\s*[.!。！]*\s*$"#
    let prefix = #"^(?:(?:please|could you|can you)\s+|(?:请|帮我|请帮我)\s*)?"#
    let ref =
      #"(?:it|this|that|this (?:item|reminder|event)|that (?:item|reminder|event)|它|这个|那个|这条|那条|这个提醒|那个提醒|这件事|那件事)"#
    let renameEN = captures(
      text, prefix + #"(?:rename|call)\s+"# + ref + #"\s+(?:to|as)\s+(.+?)"# + end)
    let renameZH =
      captures(text, prefix + #"(?:把|将)\s*"# + ref + #"\s*(?:重命名|改名|改名称)(?:为|成|叫)\s*(.+?)"# + end)
      ?? captures(text, prefix + #"(?:重命名|改名)\s*"# + ref + #"\s*(?:为|成|叫)\s*(.+?)"# + end)
    let delete =
      captures(text, prefix + #"(?:delete|remove|cancel)\s+"# + ref + end) != nil
      || captures(text, prefix + #"(?:把|将)\s*"# + ref + #"\s*(?:删掉|删除|取消)"# + end) != nil
      || captures(text, prefix + #"(?:删除|删掉|取消)\s*"# + ref + end) != nil
    let done =
      captures(
        text,
        prefix + #"(?:mark\s+"# + ref + #"\s+(?:as\s+)?(?:done|complete|completed)|complete\s+"#
          + ref + #")"# + end) != nil
      || captures(text, prefix + #"(?:把|将)\s*"# + ref + #"\s*(?:标记为|标为|设为)(?:已完成|完成)"# + end) != nil
      || captures(text, prefix + #"(?:完成|标记完成)\s*"# + ref + end) != nil
    let move =
      captures(
        text,
        prefix + #"(?:move|reschedule|postpone)\s+"# + ref + #"\s+(?:to|until|by)\s+[^;；\n]+"# + end
      ) != nil
      || captures(
        text, prefix + #"(?:把|将)\s*"# + ref + #"\s*(?:移到|挪到|改到|改成|推到|推迟到|延到)\s*[^;；\n]+"# + end)
        != nil
    guard renameEN != nil || renameZH != nil || delete || done || move else { return nil }
    // Multiple actions and corrections are never collapsed into a single attached-item operation.
    if ChatRouting.hasMultipleActions(text) || ChatRouting.hasMaterialCorrection(text)
      || text.contains("然后")
      || text.range(
        of: #"\band\s+(?:delete|remove|move|rename|complete|mark)\b"#,
        options: [.regularExpression, .caseInsensitive]) != nil
    {
      return AttachedItemEdit(target: nil, operation: nil, reason: "multiple actions")
    }
    let matches = items.filter { $0.id == attachedItemID }
    guard let id = attachedItemID, matches.count == 1, let item = matches.first else {
      return AttachedItemEdit(target: nil, operation: nil, reason: "attached item unavailable")
    }
    if let name = (renameEN ?? renameZH)?.first?.trimmingCharacters(in: .whitespacesAndNewlines),
      !name.isEmpty
    {
      return AttachedItemEdit(target: id, operation: .rename(name), reason: "ok")
    }
    if delete { return AttachedItemEdit(target: id, operation: .delete, reason: "ok") }
    if done {
      guard item.type == "task" else {
        return AttachedItemEdit(
          target: id, operation: nil, reason: "only reminders can be completed")
      }
      return AttachedItemEdit(target: id, operation: .done, reason: "ok")
    }
    guard let start = Editing.newStart(for: item, text: text, now: now, calendar: calendar) else {
      return AttachedItemEdit(target: id, operation: nil, reason: "no new time")
    }
    return AttachedItemEdit(target: id, operation: .move(start), reason: "ok")
  }
}

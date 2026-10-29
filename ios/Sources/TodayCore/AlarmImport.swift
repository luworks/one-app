import Foundation

/// A one-time import of the Clock app's alarms, which no app can read. The user's own Shortcut does the reading: Clock's
/// "Get All Alarms", then Today's "Import Alarm" for each one. That intent only stages the alarm here; the Clock tab shows
/// the staged alarms as cards the user adds one by one (or all), and Skip clears them. Nothing syncs afterwards.
public enum AlarmImport {
  public struct Staged: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var hour: Int
    public var minute: Int
    public var label: String
    /// Calendar weekdays (1 = Sunday … 7 = Saturday); empty = rings once.
    public var weekdays: [Int]
    public var isOn: Bool

    public init(
      id: UUID = UUID(), hour: Int, minute: Int, label: String, weekdays: [Int], isOn: Bool
    ) {
      self.id = id
      self.hour = hour
      self.minute = minute
      self.label = label
      self.weekdays = weekdays
      self.isOn = isOn
    }

    /// Same time and days: the alarm Today already has, so it isn't offered twice.
    public func matches(hour: Int, minute: Int, weekdays: [Int]) -> Bool {
      self.hour == hour && self.minute == minute && Set(self.weekdays) == Set(weekdays)
    }
  }

  public static let stagedKey = "today.import.clockAlarms"
  /// Plenty for anyone's Clock app; a runaway Shortcut can't grow the list without end.
  public static let limit = 50

  public static func staged(_ defaults: UserDefaults = .standard) -> [Staged] {
    guard let data = defaults.data(forKey: stagedKey) else { return [] }
    return (try? JSONDecoder().decode([Staged].self, from: data)) ?? []
  }

  public static func save(_ staged: [Staged], _ defaults: UserDefaults = .standard) {
    if staged.isEmpty {
      defaults.removeObject(forKey: stagedKey)
    } else if let data = try? JSONEncoder().encode(Array(staged.prefix(limit))) {
      defaults.set(data, forKey: stagedKey)
    }
  }

  /// Adds one alarm from the Shortcut, unless the same time and days are already staged (running it twice is harmless).
  @discardableResult
  public static func stage(_ alarm: Staged, _ defaults: UserDefaults = .standard) -> Bool {
    var all = staged(defaults)
    guard all.count < limit,
      !all.contains(where: {
        $0.matches(hour: alarm.hour, minute: alarm.minute, weekdays: alarm.weekdays)
      })
    else { return false }
    all.append(alarm)
    save(all, defaults)
    return true
  }

  public static func remove(_ ids: Set<UUID>, _ defaults: UserDefaults = .standard) {
    save(staged(defaults).filter { !ids.contains($0.id) }, defaults)
  }

  /// The days from the repeat text the Clock app hands a Shortcut, in English or Chinese: "Never", "Every Day",
  /// "Weekdays", "Weekends", "Every Monday", "Mon, Wed, Fri", "Monday Wednesday", "每天", "工作日", "周末", "周一、周三".
  /// Anything it can't read rings once.
  public static func weekdays(fromRepeat text: String?) -> [Int] {
    let t = (text ?? "").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    if t.isEmpty || t == "never" || t == "永不" || t == "从不" { return [] }
    if t.contains("every day") || t.contains("everyday") || t.contains("daily") || t.contains("每天")
    {
      return Array(1...7)
    }
    if t.contains("weekday") || t.contains("工作日") { return [2, 3, 4, 5, 6] }
    if t.contains("weekend") || t.contains("周末") { return [1, 7] }
    let english = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
    let chinese = ["日", "一", "二", "三", "四", "五", "六"]
    var days = Set<Int>()
    let words = t.components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
    for word in words {
      if let i = english.firstIndex(where: { word.hasPrefix($0) }) { days.insert(i + 1) }
    }
    for prefix in ["周", "星期", "礼拜"] {
      var rest = t[...]
      while let range = rest.range(of: prefix) {
        let after = rest[range.upperBound...]
        if let c = after.first, let i = chinese.firstIndex(of: String(c == "天" ? "日" : c)) {
          days.insert(i + 1)
        }
        rest = after
      }
    }
    return days.sorted()
  }
}

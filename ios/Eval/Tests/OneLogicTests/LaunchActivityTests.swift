import Foundation
import Testing
import TodayData
import TodayTestSupport

struct LaunchActivityTests {
  @Test func freshUITestResetsActivityPreferencesAndSeedsRealStore() throws {
    let name = "LaunchActivityTests.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    defaults.set(true, forKey: ActivitySettings.pausedKey)
    defaults.set(false, forKey: ActivitySettings.keepChatTextKey)
    defaults.set(false, forKey: ActivitySettings.tierKey(.changes))
    let store = try ActivityStore(location: .memory)
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    try LaunchTestConfiguration.applyActivityOverrides(
      arguments: ["-uiTesting", "-uiTestingActivityRows", "5"], defaults: defaults,
      store: store, now: now)
    let settings = ActivitySettings(defaults)
    #expect(!settings.paused && settings.keepChatText && settings.records(.changes))
    let rows = try store.page(ActivityQuery(tiers: [.changes]))
    #expect(rows.map(\.title) == (0..<5).map { "Synthetic \($0)" })
    #expect(rows.first?.ts == ActivityClock.ms(now.addingTimeInterval(-3600)))
  }

  @Test func normalLaunchAndExplicitRelaunchPreserveActivitySettings() throws {
    let name = "LaunchActivityTests.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    defaults.set(true, forKey: ActivitySettings.pausedKey)
    let store = try ActivityStore(location: .memory)
    for arguments in [
      ["-uiTestingActivityRows", "5"], ["-uiTesting", "-uiTestingKeepActivitySettings"],
    ] {
      try LaunchTestConfiguration.applyActivityOverrides(
        arguments: arguments, defaults: defaults, store: store, now: .distantPast)
      #expect(ActivitySettings(defaults).paused)
      #expect(try store.page(ActivityQuery()).isEmpty)
    }
  }
}

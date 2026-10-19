import Foundation
import Testing
import TodayCore
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

  @Test func reminderPillIsolationPreservesNormalAndExplicitRelaunchChoices() throws {
    let name = "LaunchActivityTests.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    for arguments in [
      [], ["-uiTesting", "-uiTestingKeepReminderPills"],
      ["-uiTesting"], ["-uiTesting", "-uiTestingKeepPreferences"],
    ] {
      defaults.set("scheduled,today", forKey: SmartListLayout.orderKey)
      defaults.set("flagged", forKey: SmartListLayout.hiddenKey)
      defaults.set(true, forKey: "reminders.listsReordered")
      defaults.set("Keep this preference", forKey: "unrelated")
      LaunchTestConfiguration.applyPreferenceOverrides(arguments: arguments, defaults: defaults)
      let layout = SmartListLayout(
        order: defaults.string(forKey: SmartListLayout.orderKey) ?? "",
        hidden: defaults.string(forKey: SmartListLayout.hiddenKey) ?? "")
      let preserves =
        !arguments.contains("-uiTesting")
        || arguments.contains("-uiTestingKeepReminderPills")
      #expect(layout.visible.first == (preserves ? .scheduled : .today))
      #expect(layout.hidden.contains(.flagged) == preserves)
      #expect(defaults.bool(forKey: "reminders.listsReordered") == preserves)
      #expect(defaults.string(forKey: "unrelated") == "Keep this preference")
    }
  }

}

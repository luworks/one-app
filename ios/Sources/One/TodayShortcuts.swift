#if os(iOS)
  import AppIntents
  #if !SWIFT_PACKAGE
    import One
  #endif

  // Compiled by the identity bridge and executable: one authoritative phrase declaration.
  public struct TodayShortcuts: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
      AppShortcut(
        intent: AddReminderIntent(),
        phrases: [
          "Add a reminder in \(.applicationName)",
          "Remind me with \(.applicationName)",
          "New \(.applicationName) reminder",
        ], shortTitle: "Add Reminder", systemImageName: "checklist")
      // "Set an alarm in Today": Siri asks "What time?" and reads it like the chat ("7am tomorrow", "明早7点").
      AppShortcut(
        intent: SetAlarmIntent(),
        phrases: [
          "Set an alarm in \(.applicationName)",
          "Set a \(.applicationName) alarm",
          "Wake me up with \(.applicationName)",
        ], shortTitle: "Set Alarm", systemImageName: "alarm")
      // "Start a timer in Today for 10 minutes": the length is one of a few presets, so Siri hears it in one breath.
      AppShortcut(
        intent: StartTimerForIntent(),
        phrases: [
          "Start a timer in \(.applicationName) for \(\.$length)",
          "Set a \(.applicationName) timer for \(\.$length)",
        ], shortTitle: "Timer for…", systemImageName: "timer")
      // Any other length: Siri asks "How long?" and reads the answer ("an hour and a half", "十分钟").
      AppShortcut(
        intent: StartTimerIntent(),
        phrases: [
          "Start a timer in \(.applicationName)",
          "Start a \(.applicationName) timer",
          "Set a \(.applicationName) timer",
        ], shortTitle: "Start Timer", systemImageName: "timer")
      AppShortcut(
        intent: WhatsNextIntent(),
        phrases: [
          "What’s next in \(.applicationName)",
          "What’s next today in \(.applicationName)",
        ], shortTitle: "What’s Next", systemImageName: "list.bullet.clipboard")
      AppShortcut(
        intent: OpenTodayIntent(),
        phrases: [
          "Show my day in \(.applicationName)",
          "Show today in \(.applicationName)",
        ], shortTitle: "Open Today", systemImageName: "sun.max")
    }
  }

#endif

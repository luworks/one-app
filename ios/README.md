# one. — iOS app (SwiftUI)

The native app. The HTML prototype in `src/` stays the design reference; this is what runs on the phone.

Requires Xcode 16 or later and iOS 17 or later.

## Run it on your iPhone (free Apple ID, no paid account)

1. Open `ios/One.xcodeproj` in Xcode.
2. Xcode → Settings → Accounts → add your Apple ID.
3. Select the **One** target → Signing & Capabilities → Team: pick your "(Personal Team)".
   If Xcode says the bundle identifier is taken, change `com.luworks.one` to something unique, e.g. `com.<yourname>.one`.
4. Plug in the iPhone, unlock it and tap Trust. On the phone turn on Settings → Privacy & Security → Developer Mode (it restarts).
5. Pick the iPhone as the run destination at the top of Xcode and press ⌘R.
6. First launch only: on the phone go to Settings → General → VPN & Device Management → your Apple ID → Trust.

With a free account the install expires after 7 days; just press ⌘R again with the phone connected.

## What's in it

- `Models.swift` — `OneTask` (planned time flexes, `due` never moves) and `OneEvent` (fixed), stored with SwiftData.
- `HomeView.swift` — week strip, overdue / due today, the day's timeline with a "now" line, composer at the bottom.
- `Capture.swift` — turns "明天下午3点 打电话给 Alex" into a preview card; nothing is added until you tap 添加.
- `Rows.swift` — event / task rows (swipe to postpone or move to tomorrow; only the checkbox completes a task), week strip.
- `TasksView.swift` — all tasks: unscheduled, scheduled, done.
- `SampleData.swift` — a few items around today on first launch (menu → 清空全部数据 removes them).

## Next

EventKit (system calendar) → alarms (AlarmKit) → widgets → a real AI behind the composer.

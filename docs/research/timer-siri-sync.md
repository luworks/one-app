# Timers, Siri and Today: what iOS lets a third-party app do

Researched 2026-10-17 against Xcode 27.1 / iPhoneOS 27.1 SDK. "Verified" = read in Apple's documentation (via the
developer.apple.com JSON that backs the docs pages) or in the SDK's `.swiftinterface` on this Mac. "Not verified" =
could not be confirmed without a device; stated as such.

## Verdict

| Question | Answer |
| --- | --- |
| (a) Can Today read timers made in the Clock app or by Siri's built-in "set a timer"? | **No** (verified). No iOS 26 or 27 API exposes them. |
| (b) Can Today receive "set a timer" by voice? | **Yes, on iOS 27, through the App Intents `.clock` schema domain** (verified in the SDK). Whether Siri sends a bare "set a timer for 10 minutes" (no app name) to Today instead of Clock is **not verified**. Saying the app name always works (App Shortcuts). |
| (c) What does AlarmKit need on a free Apple ID? | The `NSAlarmKitUsageDescription` Info.plist key and the user's one-time "Allow" prompt. No entitlement or paid membership. Already working: the Pomodoro timer uses it. |

## (a) Reading other apps' timers: no

- `AlarmManager.alarms`: "Fetches all alarms from the daemon that belong to the current client."
  https://developer.apple.com/documentation/alarmkit/alarmmanager/alarms
  `alarmUpdates` is the same scope. AlarmKit's whole public surface (iOS 26.0) is `AlarmManager` (schedule, pause,
  resume, stop, cancel, countdown, authorization), `Alarm`, `AlarmPresentation`, `AlarmAttributes`, `AlarmButton`,
  `AlarmMetadata` (https://developer.apple.com/documentation/alarmkit). The Clock app is not an AlarmKit client we can
  see; there is no "all clients" call.
- iOS 27 SDK delta in AlarmKit: the only addition in the `.swiftinterface` is `appEntityIdentifier:` on
  `AlarmConfiguration` (`alarm(...)`, `timer(...)`, `init`), `@available(iOS 27.0)`. It links our own alarm to an App
  Intents entity so Siri can act on it ("pause the timer"). It reads nothing from other apps.
- ActivityKit: `Activity` observes "the Live Activity" the app started itself (activity updates, state, push token)
  (https://developer.apple.com/documentation/activitykit/activity). There is no API to enumerate or observe other apps'
  Live Activities (the Clock timer's Live Activity included).
- SiriKit has no timer or alarm domain (Apple's SiriKit page lists no such domain:
  https://developer.apple.com/documentation/sirikit), and SiriKit is being replaced by App Intents.
- The built-in Clock app's own Shortcuts actions (Start Timer, Create Alarm, ...) run inside Clock; a Shortcut can
  call them, but Today cannot ask Shortcuts "what timers exist". Whether a "Get timers" action exists: **not verified**
  and, even if it does, it would need the user to build and run a Shortcut; it is not background access.
- Focus / notification APIs: nothing relevant. `UNUserNotificationCenter` only lists this app's own notifications.

So a timer started with the built-in Siri/Clock is invisible to Today. This is a platform wall, not something to work
around, and Today does not pretend otherwise.

## (b) Receiving "set a timer" by voice

- **App Intents `.clock` schema domain (new in iOS 27, verified in the SDK: `AppIntents.swiftinterface`,
  `@available(anyAppleOS 27.0)`).**
  Doc: https://developer.apple.com/documentation/appintents/app-schema-domain-clock ("Make your clock app's actions
  available to Apple Intelligence and Siri by adopting schemas for common alarm and timer actions"). Example phrases from
  Apple's table: "Set a timer.", "Timer for 5 minutes.", "Add 5 minutes to the timer.", "Pause the timer.", "Resume the
  timer.", "Cancel the timer."
  - Timer intents: `.clock.createTimer`, `.clock.updateTimer`, `.clock.pauseTimer`, `.clock.resumeTimer`,
    `.clock.cancelTimer`; entity `.clock.timer`; enum `.clock.timerState` (also alarms and stopwatch schemas).
  - WWDC26 "Explore advanced App Intents features for Siri and Apple Intelligence" (session 343) shows
    `@AppIntent(schema: .clock.createTimer)` with `duration: Duration`, `label: String?`, `isSleepTimer: Bool`
    returning a timer entity, and says that with AlarmKit you pass an `EntityIdentifier` as `appEntityIdentifier` on
    `AlarmConfiguration` "so people can act on firing alarms and timers".
    https://developer.apple.com/videos/play/wwdc2026/343/
  - Apple's text: "a person can set an alarm on different apps that support the schema with the same phrases".
  - **Not verified (needs a real iPhone with Siri AI):** which app Siri picks when several clock apps adopt the
    schema, and whether a bare "set a timer" goes to Clock or to Today. Neither the docs nor the two WWDC26 sessions
    I read (240, 343) say. There may be a per-domain default-app choice; I found nothing that confirms it.
- **App Shortcuts** (works on every iOS 16+): phrases must contain the app name, e.g. "Start a timer in Today". An
  App Shortcut phrase can contain `\(.applicationName)` and AppEntity/AppEnum parameters only, not a free duration. So
  "Start a timer in Today for 10 minutes" in one breath needs the `.clock.createTimer` schema (Siri parses the
  duration); with a plain App Shortcut Siri asks "How long?" and then starts it.
- Today's existing "Start a timer in Today" intent already exists as an App Shortcut (phrases in
  `AppShortcuts.xcstrings`); this work moves it to the multi-timer model and adds the schema intents.

## (c) AlarmKit authorization on a free Apple ID

`NSAlarmKitUsageDescription` must be in Info.plist ("If the key is missing or its value is an empty string, apps can't
schedule alarms with AlarmKit"), and the app calls `AlarmManager.shared.requestAuthorization()` (or AlarmKit asks on the
first schedule). Source: https://developer.apple.com/documentation/alarmkit/scheduling-an-alarm-with-alarmkit. The
countdown Live Activity needs a widget extension (`TodayWidgets`, already in the project). Nothing here needs a paid
developer account; Pomodoro already runs on the free-Apple-ID phone build. The iOS Simulator denies AlarmKit, so
ringing and Live Activities can only be tested on a phone.

## What this means for Today

- Honest gap: timers made with Siri's default Clock are not visible to other apps. Today says so on the Timer tab and
  offers the one-tap way to get the Today phrase (Siri tip / Shortcuts link).
- What Today can show: every timer **Today** started (Timer tab, Pomodoro, "Start a timer in Today", or the clock
  schema if Siri routes there), as real AlarmKit countdowns (system Live Activity, Lock Screen, Dynamic Island) and as a
  live row on the Today tab.
- What would have to change for full sync: Apple would need an "all alarms/timers" read API in AlarmKit (none in the
  iOS 27 SDK) or Clock would need to expose its timers as App Entities to other apps (not announced). Until then, the
  only complete answer is to make Today the app Siri uses for timers, which iOS 27's clock schema makes possible but
  not guaranteed.

# Platform consumer integration handoff

Base: `808be87`. Ownership: only `TodayPlatform/{TravelTimes,AlarmSounds,TodayClock,Appearance}.swift` and this document. The existing root-owned `TravelTimeProviding.swift` and `SoundPreviewing` declaration are unchanged. No Core, feature, model, app, Development, package or project changes are included.

## Exact APIs and composition

All travel/sound construction and calls are MainActor-isolated. The package-scoped live adapter conforms to the existing public TodayPlatform protocol, which imports Foundation and TodayShared, not Core:

```swift
package final class TravelTimes: NSObject, CLLocationManagerDelegate, TravelTimeProviding
package init(defaults: UserDefaults, runtime: PlannerRuntime)
package private(set) var version: Int
package var isEnabled: Bool
package var didUpdateEstimate: (@MainActor () -> Void)?
package func seconds(eventID: String, start: Date, isAllDay: Bool, place: TravelPlace?, now: Date, askPermission: Bool = true) -> TimeInterval?
package func label(eventID: String, start: Date, isAllDay: Bool, place: TravelPlace?, now: Date) -> String?
package func widgetFields(eventID: String, start: Date, isAllDay: Bool, place: TravelPlace?, now: Date) -> (minutes: Int, leaveBy: Date)?
package func dispose()
```

Calls through `any TravelTimeProviding` must supply `askPermission` explicitly: the root protocol has no default argument. `label` requests permission when appropriate; `widgetFields` always passes false. Root creates and retains one live adapter with production defaults/runtime and wires `didUpdateEstimate` to its retained WidgetFeed. Use weak capture if that callback would otherwise form an ownership cycle. Dispose is terminal and idempotent; root must call it before releasing a session. There is no default live constructor, static `shared` or static `isEnabled` forwarding API.

Initialization only loads/prunes the supplied defaults cache. CLLocationManager is created on first eligible read, never in init/dispose. Reads stay nonblocking and return usable cached estimates; lookups remain deferred, foreground-only, soonest-first, and limited to three. Missing/failed estimates retain the 15-minute refresh policy. Permission refusal suppresses estimates, background reads never prompt, and overlapping deferred reads preserve an explicit foreground permission request. One location fix and one permission request attempt are retained per adapter lifetime.

Each adapter owns its deferred tasks, ETA tasks, MKLocalSearch and MKDirections objects. Dispose cancels only those, clears queues/request identities, detaches its location delegate and drops its estimate callback. Task cancellation, terminal state and request UUID identity are checked before persisting/completion effects; MapKit object identity is checked after awaits before resolved-address/ETA acceptance. The authorization delegate checks the originating CLLocationManager identity after hopping to MainActor. A disposed task cannot recreate the location manager or publish an estimate. Cache keys, eligibility, pruning and label formatting use the supplied runtime calendar, locale and time zone; cache timestamps and ETA arrival comparisons use runtime.now. `now` supplied by the caller controls occurrence eligibility and leave-by labels.

```swift
@MainActor package final class SoundPreview: SoundPreviewing
package init()
package func play(_ sound: AlarmSound)
package func stop()
```

Root retains the preview and passes `any SoundPreviewing` to consumers. Construction does not touch AVAudioSession. Explicit play keeps the existing playback category/activation behavior; stop stops/releases only this instance's AVAudioPlayer, without globally deactivating the session or foreign audio. Call stop when dismissing/disposing the owning screen/session. All eight tone names, CAF resource filenames, Bundle.main lookup and AlarmKit alertSound mapping are unchanged. No Development fake is included here.

The remaining production-only `TodayClock.now` returns wall-clock Date.now. It is retained temporarily for unmigrated callers; deterministic consumers must receive PlannerRuntime instead.

Appearance retains the current system/light/dark mapping and adaptive system colors. Its new public signatures are:

```swift
static func Appearance.applyConfiguration(_ appearance: Appearance?, defaults: UserDefaults)
@MainActor func Appearance.applyToWindows(_ windows: [UIWindow])
@MainActor func View.appearanceRoot(defaults: UserDefaults, windows: @escaping @MainActor () -> [UIWindow]) -> some View
```

`applyConfiguration(nil, defaults:)` preserves the stored choice; an explicit choice writes only the supplied defaults. Root must replace `applyLaunchOverride()` and parameterless `appearanceRoot()` / `applyToWindows()` calls. Production explicitly supplies its normal defaults and all app-owned windows, including windows created later. Each Workbench closure supplies only that session's window; never return every connected scene's windows there. The modifier observes its explicit AppStorage store and retains preferredColorScheme plus UIKit window overrides, including scene/key-window refreshes. Notifications are global refresh triggers, but the closure limits all writes. System still maps to nil/unspecified, handing appearance back to iOS.

## Removed launch behavior that root Mock must reproduce

- Travel no longer silently returns nil under `-uiTesting`. Root must inject a Development-only deterministic TravelTimeProviding fake for UI tests/Workbench; constructing/using the live adapter may request location and MapKit network work. Fake clients must not delegate to the live adapter.
- TodayClock no longer interprets DEBUG `-uiTesting -uiTestingNow HH:mm`. Root Mock must interpret valid hour/minute arguments, pin the selected day's time with seconds zero in its runtime calendar, and supply that runtime throughout the scene. Missing/invalid arguments formerly fell back to live time.
- Platform Appearance no longer parses `-uiTesting`, `-appearance light|dark|system` or `-uiTestingKeepAppearance`. Root Mock must explicitly select the launch choice: valid `-appearance` wins; otherwise `-uiTestingKeepAppearance` preserves storage, and an ordinary UI-test launch resets to System. Apply the selected configuration to session defaults before rendering. The old helper still exists in root-owned Core/AppearanceLogic.swift and is outside this lane; root must migrate/remove that residual parser separately.

## Validation and limits

Only iOS-target DEBUG Swift frontend syntax parsing, focused source/diff review and `git diff --check` ran. Syntax parsing passes with the host macOS sysroot/iOS target warning. This does not type-check protocol conformances, resolve imports, validate concurrency diagnostics or prove runtime behavior. No SwiftPM, Xcode build, simulator, device, network, location prompt or audio activation was started. Root owns integrated build and focused behavioral checks: cached reads, foreground/background permission routing, disposal before task startup/during MapKit await, late delegate/result rejection, separate defaults/callback ownership, sound playback/stop, pinned Mock time, and distinct Workbench window appearance.

Evidence directory: `/Users/yuanlu/code/one-app/tests/results/platform-consumers-20261018-808be87`. QA journal session: `platform-consumers-808be87`. Raw syntax log, diff check, source audit and bounded patch are retained there and indexed in the primary checkout's QA SQLite journal. Runtime isolation and production device acceptance remain unverified.

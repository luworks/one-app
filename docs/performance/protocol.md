# Today performance baseline protocol v1

Report first. Do not optimize production behavior until a measured bottleneck and
acceptance target are agreed. Product rules in `CLAUDE.md` apply to every benchmark:
preview before Add/Apply, fixed meetings, separate deadlines, local data and Undo.

## Context and ownership

Record source SHA plus uncommitted instrumentation diff, date/time, Xcode/SDK,
configuration/optimization, host CPU/RAM/load, simulator model/runtime/UDID,
fixture hash/counts, cache state, method, units and every raw sample. One runner,
`Today-Performance`, its own derived data. Coordinate a quiet window; do not use
another session's simulator/cache. No phone installation, signing configuration
change, user-data deletion or account synchronization belongs to this protocol.

Canonical evidence: primary checkout `tests/results/runs/<session>/`; separate QA
Activity journal at `tests/results/activity.sqlite`. Use
`tests/performance/record_command.py --label <name> -- <command...>` for additional
commands; use `ios/Eval/run-e2e.py` for simulator tests. After writers finish,
`journal.py import <output> --session <session> --status passed|failed --archive`
indexes complete raw artifacts with SHA-256. Never archive a live xcresult or
erase persistent evidence. Required fixtures remain versioned.

## Package measurement

1. Fetch `origin/main`, record both SHAs and clean/dirty state. Build **once per
   configuration**, `-jobs 2`, isolated DD. Release command:

   ```sh
   python3 tests/performance/record_command.py --label release-build -- \
     xcodebuild -project ios/One.xcodeproj -scheme One -configuration Release \
     -destination generic/platform=iOS -jobs 2 \
     -derivedDataPath /Users/yuanlu/code/one-app/tests/results/runs/performance-baseline-20261018/derived-release \
     CODE_SIGNING_ALLOWED=NO build
   ```

   The override is command-scoped; never edit project signing or request new
   provisioning. This is an unsigned generic build, not an exported archive.
2. Run `tests/performance/inventory.py <One.app> --output <durable-output.json>`
   on optimized Release iphoneos and Debug simulator apps. Include extensions,
   Mach-O architecture/segments/linked libraries, Assets.car, audio, cities,
   localizations, fonts, dependency copies, file hashes and logical byte totals.
   Never sum nested extension totals twice. Exact identical bytes are evidence
   of duplication, not proof that one copy is dispensable across sandboxes.
3. ZIP deflate-9 `Payload/One.app` is only a **local compressed proxy**; signing,
   encryption, App Store processing, slicing and filesystem allocation differ.
   Do not call this actual download/install size. Actual thinned download/install
   size requires a valid exported `App Thinning Size Report.txt` or App Store
   Connect data. Do not alter signing to obtain it in this task.
4. Inspect resource membership and DEBUG guards; verify test JSON/fixtures and
   seed hooks in the actual Release artifact. Unused candidates need call/resource
   graph evidence, including dynamic lookup, intents and extension entry points.

## Focused simulator batch (about ten minutes)

```sh
python3 ios/Eval/run-e2e.py \
  --simulator-name Today-Performance --simulator-id <owned-udid> \
  --derived-data <session>/derived-simulator --output <session>/ui \
  --only PerformanceBaselineTests/testLaunchAndResume \
  --only PerformanceBaselineTests/testNavigation \
  --only PerformanceBaselineTests/testScrollMetrics \
  --only PerformanceBaselineTests/testCreateCompleteSearchAndApply
```

Use canonical `today-dataset.json`, relative local dates, 09:41 pinned application
clock, fake simulator Health/AlarmKit, no Apple synchronization. This small dataset
is representative of feature variety, **not** of large real-user history.

| Measurement | Definition and interpretation |
| --- | --- |
| Process launch | Terminate and relaunch three times. Kernel process-start → existing `HomeView.onAppear` probe is an appearance proxy, not a verified presented frame. Launch→date + hittable New is automation-inclusive usable-shell time. No reboot/cache purge: these are process-cold / OS-warm launches, not true cold-after-reboot measurements. |
| Resume | Home then activate same process three times; ready when New is hittable. Includes automation overhead. |
| Transitions | Three cycles Today → Week → Month → Year → Reminders → Clock → Today; one Health and Settings opening. Timer starts before tap, stops after destination exists. Accessibility does not prove pixels presented or sub-100 ms main-thread latency. |
| Common operations | One create-sheet, save-dismissal, reminder open/complete, search with result, rule-based plan preview + explicit Apply. Typing intervals are named explicitly. Save-dismissal is not fsync latency; UI fixture storage is in memory. |
| Scroll/render | Three measured Year up/down pairs with XCTest scrolling-and-deceleration signpost and app memory metrics. Preserve all metrics/errors. Empty/unsupported metrics are missing evidence, not zero hitches. No FPS inference from command durations. |
| Memory | XCTest app memory during scroll is a simulator proxy. `memory_sample.py` can collect owned app RSS every 0.5 s, grouped by PID and aligned with test phases. For physical footprint/retention across navigation, use Instruments Allocations at initial idle and after 1/5/10 cycles, same dataset; label RSS separately from physical footprint. Never use test-runner memory as app memory. |
| Local store | Existing `ACTIVITY_BENCH_ROWS=100000 swift test --jobs 2 --filter ActivityStoreTests/testBenchmarkLarge` (from ios), optimized with `-c release` where budget permits. Synthetic Activity events, 1000-row batches, keyset 150-row pages, bilingual search. Host SQLite results are not simulator SwiftData/EventKit query results. |
| Persistence | Existing benchmark bulk insert includes event generation + SQLite transaction writes. It is not single-reminder durable save latency. Measure that separately with a file store and save/signpost/receipt boundary before claiming durability. |
| Energy | Source/simulator CPU/wakeups only if available; no battery, thermal or energy-efficiency claim. |

Keep n=3–5 only where it answers a useful question. Report raw samples, median,
range and n. No p95 from these tiny samples; collect at least 100 comparable
samples for a useful exploratory tail estimate and report its uncertainty.
Never subtract a guessed fixed automation overhead. Stop expanding after the
batch budget. Diagnose one representative selector failure and rerun only that
method; preserve behavioral assertions. Shutdown owned simulator immediately.

## Targets and comparisons

Targets are proposed engineering goals, not measurements of competitors.
Apple's [responsiveness guidance](https://developer.apple.com/documentation/xcode/improving-app-responsiveness)
supports <100 ms discrete main-thread response and roughly <5 ms update work.
Frame intervals are 16.67 ms at 60 Hz / 8.33 ms at 120 Hz; these are not budgets
entirely available to the app. [WWDC19 launch guidance](https://developer.apple.com/videos/play/wwdc2019/423/)
sets an aspirational 400 ms first-frame goal; distinguish it from usable-content
and process-start proxies. Current [hitch guidance](https://developer.apple.com/documentation/xcode/understanding-hitches-in-your-app)
calls ≤10 ms/s good; propose ≤5 ms/s with zero as the ideal.

Propose no-regression +10% alerts for comparable package/memory medians, then
tighten once variance is known. Size and memory targets are product budgets,
not Apple mandates. [Apple app size guidance](https://developer.apple.com/documentation/xcode/reducing-your-app-s-size)
explains export/thinning and App Store Connect accuracy.

Only compare Apple Calendar/Reminders/Clock or third-party apps numerically after
an authorized same-device/build/data/cache protocol measurement. Without it,
report a platform/aspirational gap and a competitor-evidence gap separately.
Every result row must state context, current, n/median/range (p95 only valid),
target, confidence, gap and the next measurement or action. Rank follow-ups by
user-visible latency/bytes, risk, expected measurable benefit and implementation
cost. Separate verified redundancy from suspected reachability issues.

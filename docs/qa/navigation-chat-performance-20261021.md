# Populated navigation and Chat performance — 2026-10-21

## Source and scope

Clean performance checkout `t3-0f4b13c0` fast-forwarded from parent `a56646b2` to
`9dfed1b28b4c135c232bc280820eb623479ced7f` before work. Product source is unchanged.
Only a measurement journey was added: three fresh app processes, first Chat open,
exact unsent draft input, Close, and reopening the same mounted editor with that
draft intact. No messages are submitted and live Apple sync stays off.

The unrelated removal owner, dirty coordinator checkout, physical phone,
signing and CI policy were not changed. The protected Today-UI simulator was not
used. One read-only focused review found no concrete harness defects; it correctly
required extracting six actual trace pairs rather than inferring them from passes.

## Reproducible baseline

Command:

```sh
./dev test ui \
  --only TodayUITests/PerformanceClimbTests/testTodayWeekResponse \
  --only TodayUITests/PerformanceClimbTests/testRepeatedNavigationRetainsCalendarSelection \
  --only TodayUITests/ChatPanelTests/testPopulatedFirstOpenAndReopenEvidence \
  --timeout 570
```

TodayMock Debug, `TODAY_MOCK`, Xcode 27.1 / 27A9275, Swift 6.4, iOS 27.0,
iPhone 18 Pro Max (the current `./dev` authority's fixed model). App time 09:41;
fixture dates are relative to October 21, not a frozen historical date.
`tests/fixtures/today-dataset.json` SHA256:
`e91a99f1a16eabdad31b2f8c7e3bff7bf20f058713945964f8fdc684a9ba31c7`.
It contains 3 lists, 17 reminders, 13 event records, 4 alarms and 7 chats.
This is a small populated feature-variety fixture, not a large-history benchmark.

Owned simulator `Today-Dev-c81e77d5`, UDID
`8933780A-4FF9-49D8-82AC-0FF283DA3B36`; owned derived data
`tests/results/devtools/derived-data/c81e77d540c358c40853` in the primary checkout.
The canonical cache was absent. Other caches belonged to other worktrees and the
runner requires its canonical owned/provenance-validated cache, so one build was
necessary. No caches were deleted or another owner's simulator reused.

Baseline run: primary `tests/results/runs/today-qa-20261021-014028-646f68e9`.
**3/3 passed**, build 84.432s, total runner 314.838s, UI exit 0, shutdown exit 0.
The full closed xcresult and raw build/UI logs remain there. Mock executable
SHA256 `df04e02edd7a67f09f4840f67325169c7bd9fe507b613b6c51a62b5e33969406`,
source fingerprint `1cb457798c58facbc7a9c3e2afaabd2a383d197c28b469531c383fb577632b4b`.

Evidence root in the primary checkout:
`tests/results/overnight-qa-20261021/navigation-chat-perf/`.
`measurements.json` retains all exact monotonic endpoints, fixture/product identity,
raw stdout path and parsed samples. `diagnostics/` contains exported app stdout;
`attachments/` contains screenshots and retained navigation samples. The Chat
screenshot was visually inspected: populated Today underneath, floating panel,
exact unsent draft and unobscured native keyboard/composer.

## Measurements and interpretation

All values below are milliseconds, in execution order. Navigation starts inside
the real action before the state write and ends after destination geometry plus
two display-link callbacks. Chat uses `begin.page.ai` to the first nonzero editable
`chat.composer_laid_out`. These are different layout proxies, neither physical
tap-to-pixel nor guaranteed first-input readiness. XCTest independently types and
verifies the first-open draft; reopening verifies retention, not another typing
latency. Do not subtract XCTest overhead to construct physical latency.

- Today → Week: first entries 416.823 and 333.714 in separate processes; subsequent
  entries 284.211 and 200.888 in the Week cohort.
- Week → Today: 233.797 / 301.200 / 398.188.
- Week → Month first entry: 366.615.
- Month → Today: 225.549 / 250.187 / 283.725.
- Today → retained Month: 282.507 / 300.764 / 235.086.
- Chat first editable layout in three fresh processes: 1013.034 / 669.387 / 691.102.
- Chat retained-editor reopen in those processes: 342.674 / 141.184 / 479.138.
- XCTest first-open tap-call through verified typing: 5973.280 / 4050.242 / 5054.196;
  these include lookup, synchronization, tapping and typing.

The first Chat process followed a freshly booted simulator. Later processes used
the same runtime and OS caches; every app launch reloaded a fresh in-memory
fixture. No claim of cold OS caches, EventKit-cache counts, or large-history data
is made. Calendar/Reminder live sync is disabled, and mock intelligence prewarm
is an empty closure, so Live Foundation Models costs remain unknown.

The historical 1003.9ms Month → Today outlier did not reproduce. No contemporaneous
stack exists for that old outlier, so this run neither explains nor resolves it.
The Chat first-open delay is observable. `chat.focus_begin` → `chat.focus_end`
(the synchronous `becomeFirstResponder()` call) takes only roughly 0.05–0.08ms;
the remaining 427–726ms from focus return to composer layout is unattributed.
This does not establish keyboard, SwiftUI, suggestions or EventKit as root cause.
No production optimization, caching, delay change, dropped items or design change
was made, and there is no before/after speedup claim.

## One diagnostic follow-up and endpoint

A single focused rerun used the same built products and the populated Chat method
only, while an external Time Profiler attachment attempted to capture the already
observed slow first-open interval. Run
`tests/results/runs/today-qa-20261021-014722-bf218bf6`: **1/1 passed**, no build,
115.175s, UI/shutdown exit 0. Because the profiler was being started, these numbers
are a diagnostic cohort, not a baseline/candidate comparison. Composer first-open
values were 776.067 / 400.385 / 418.253ms and reopen values
162.707 / 108.220 / 107.697ms. All six trace pairs are retained.

Profiler attachment failed with exit 21:
`Cannot find process for provided pid: 85434`.
`profile-target.json` records the exact owned simulator application/PID and argv;
`profile-record.log` retains the raw failure. No `.trace` was created, so there are
**no main-thread stacks** and no hotspot/root-cause proof. Process lifetime versus
profiler attach latency is not resolved by that error. The completed second
xcresult remains intact; `profile-diagnostics/` and `profile-result.json` retain the
stdout and diagnostic classification. No equivalent profiling reruns were added.

The two runner invocations totaled 430.013s (about 7.2 minutes), including one
84.432s build. Tool bootstrap/resolve, review and evidence export are additional
preparation/analysis time. `./dev format --check` and `git diff --check` passed.
No pure-logic behavior changed, so no redundant unit suite was run. Both runs
closed and shut down the same simulator; the heavy window is released.

**Recommendation:** retain the existing product behavior. The next bounded
candidate is fresh-process Chat construction/layout: reproduce with this exact
fixture/build and a profiler already ready before the tap, keeping the first
process alive long enough for successful attachment. Obtain nonempty timestamped
main-thread samples that actually overlap `begin.page.ai` through composer layout
before selecting a narrow repair. Capture content presentation and an actual
first keystroke separately if claiming tap-to-pixel or input readiness. A live
EventKit/model or large-history cohort is a separate measurement, not implied by
this mock fixture. No optimization PR is warranted from these data alone.

Physical latency and interaction remain unknown. The separate physical QA v2
owner reported no authorized signed runner path and performed no installation or
phone interaction; that report is not a physical pass for this task.

## Profile v2: successful live attachment, no product repair

Preserved local measurement commit `6923f5e00b4eb484c9216293d8d5d3e502d1b29b`.
One additional invocation of the same populated Chat method completed at
`tests/results/runs/today-qa-20261021-015305-40b84047`: **1/1 passed**, UI/shutdown
exit 0, no journal errors, 157.145s runner elapsed. The engineering authority
invalidated its broad source fingerprint after the earlier measurement/docs work
and performed a 13.683s incremental build validation. Its build log contains no
Swift compilation; the Mock executable remains byte-identical to baseline
`df04e02edd7a67f09f4840f67325169c7bd9fe507b613b6c51a62b5e33969406`.
The new source fingerprint is
`c5778cc02c822d70d5af23e85ce1c111d127b46edc25427cbb1139eefac6f013`.
No product, test, fixture or selector was changed for this run.

Evidence is retained under the primary performance directory's `profile-v2/`:
complete `first-chat.trace`, exported raw `time-profile.xml` and `time-sample.xml`,
closed-run diagnostic stdout, `metadata.json`, capture/analysis scripts,
`clock-calibration.json`, `analysis.json` (including full selected stacks), and
`categories.json`. The original failed capture remains untouched.

The watcher was armed before the runner and detected actual owned app PID **8291**
at 01:54:36.419 PDT. Adding the explicit simulator `--device` argument made this
attachment succeed (exit 0). This corrects the earlier capture setup; it does not
prove the historical failure's sole cause. Time Profiler recorded
01:54:42.791–01:54:55.756 PDT, before the first Chat tap (XCTest approximately
01:54:49–51), while this same PID remained alive through 01:54:59. No fallback
`sample` invocation or second capture was needed. A warning about one table
without a known input source is retained verbatim in `xctrace.log`; the CPU
sample tables are nonempty and symbolized.

First-layout times were **1005.336 / 629.127 / 520.305ms**; retained-editor reopen
was **129.858 / 194.186 / 190.823ms**. Only the first process was profiled. Its
focus-return-to-layout interval was **751.779ms**; the subsequent processes were
367.295 / 266.993ms. The profiled first value is consistent in scale with the
natural baseline's 669–1013ms, but profiler and startup overhead prevent a speed
comparison. No before/after improvement is claimed.

The existing endpoint signposts were not included by this template's configured
PointsOfInterest categories (export has zero signpost rows). Alignment therefore
uses the retained app monotonic endpoints, a bracketed post-run host
`mach_absolute_time`/wall-clock calibration, and trace wall start. Dated app logs
provide a cross-check: keyboard focus logging at 01:54:51.565 and keyboard render
logging at 01:54:51.616 lie between focus return and the composer layout.
This is approximate cross-clock attribution, not signpost-exact boundary proof.
The Python watcher's process-relative monotonic values are not subtracted from
app uptime. A future boundary-sensitive capture should explicitly include the
PerformanceTrace signpost category and take calibration before and after capture.

There are **476 running main-thread samples** in the aligned first Chat interval,
including **306 after focus return**. In the latter interval, 155 stacks include
`UIKeyboardSceneDelegate _reloadInputViewsForResponder`, 59 include `dlopen_from`,
71 include Swift protocol-conformance lookup, and 296 include SwiftUI hosting
layout. These are overlapping inclusive sample counts, not additive elapsed
milliseconds or wall-time percentages. Keyboard paths include first
`UIKeyboardAutomatic` creation, input-assistant view loading and TextInputUI
library loading; other stacks show SwiftUI/AttributeGraph rendering and runtime
metadata work. Startup/before-Chat samples separately contain SwiftUI host layout
and conformance lookup, with zero keyboard-reload matches in that slice. This
prevents mislabeling all startup cost as Chat cost.

**Confidence:** actual keyboard/input-view construction and SwiftUI/runtime work
are now observed within the delayed first-layout window. This is stronger than
an empty callgraph, but does not attribute the entire 752ms or establish a narrow,
removable app-owned hotspot. Suggestion-rule symbols have zero matches and
conversation history has one match in the full Chat interval; sampling absence
does not prove these pipelines cost nothing. Waiting-thread costs are not covered
by this running-thread template. Framework symbols and a profiled Debug simulator
alone do not justify removing input-assistant behavior, changing IME, prewarming
heavy work at launch, or restructuring the floating panel.

No product fix, additional design change, PR, unit rerun, full UI run, live data
write, phone operation, signing change or navigation expansion was made. The exact
draft typing/Close/reopen assertions still pass. The narrower unresolved boundary
is separating framework cold construction from app-owned rendering under exact
signpost alignment; there is no evidence-backed safe repair to publish yet.
The owned simulator was shut down by the runner, the Device panel was closed,
and host/cache locks were confirmed free. The PR148 phone delivery worker was
told the heavy window was released and could start its authorized incremental
LiveDebug build. No further heavy profiling run is queued.

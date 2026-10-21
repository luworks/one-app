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

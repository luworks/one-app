# Populated history QA — 2026-10-21

## Scope and dataset

Owned clean checkout `t3-0f4b13c0` started at `611da24440574b230c32807831d86010cc045399`;
that commit and parent measurement commit `6923f5e0` are preserved. Product source
is unchanged. This baseline precedes PR148's Returned-list removal, which is not
part of this task. Current repository instructions were compared with fetched main.

`tests/fixtures/populated-history.json` contains 800 completed reminders with due
dates across days -1 through -90, 200 past events across the same dates, 30 active
reminders and 10 events today, one event and one reminder tomorrow, two lists,
zero alarms and one existing conversation with 100 alternating user/AI messages.
English paragraphs, Chinese and multiline bullet messages vary in length.
Completion uses the existing loader's `toggleDone()` at load time; this does not
model historical completion timestamps or Activity pagination. Chat timestamps
are not a 90-day transcript. All content is synthetic and live sync stays off.
`populated-unsent-draft.txt` is a versioned long CJK/English multiline draft,
inserted using native Paste rather than Return (which submits).

## Behavioral checks

- `PerformanceClimbTests.testPopulatedHistorySelectedDayNavigation`: actual Month
  day selection, both tomorrow items, second tap opening Today on that date,
  two round trips retaining the date, and Back to today. Existing action-to-layout
  instrumentation remains separate from XCTest query/tap/synchronization duration.
- `PopulatedHistoryTests.testExistingLongChatKeepsReadingPositionAfterClose`:
  actual history pan to an earlier fully visible message, Close, close the retained
  sidebar, resume Chat, and compare the same message's vertical position with the
  keyboard hidden (35-point existing reading-test tolerance).
- `PopulatedHistoryTests.testMultilineCJKPasteRemainsExactAndUnsentAfterClose`:
  native Paste, full exact editor value, no matching submitted message or capture,
  Close/sidebar dismissal/reopen, and full exact draft/no-submission checks again.

TodayMock Debug, iOS 27.0, iPhone 18 Pro Max (the fixed engineering runner model),
Xcode 27.1 / 27A9275. App clock 09:41, relative fixture date October 21. Owned
simulator `Today-Dev-c81e77d5` / `8933780A-4FF9-49D8-82AC-0FF283DA3B36`, canonical
primary-checkout derived data `tests/results/devtools/derived-data/c81e77d540c358c40853`.
Phone owner confirmed its build finished and measurement window free before tests.
No physical control, signing, installation, user Calendar/Reminders writes, private
Health reads or alarm triggers were performed.

## Retained first failures

Primary evidence directory: `tests/results/overnight-qa-20261021/populated-history-v3/`.
Complete original bundles remain under primary `tests/results/runs/` and are indexed
by the QA journal; exported screenshots, AX trees, raw app stdout and exact trace
samples are retained under this evidence directory.

- `today-qa-20261021-020502-b360c5c0`: failed before build because Device panel had
  booted the owned simulator. The runner requires it initially shut down. Only this
  owned simulator was shut down before retrying.
- `today-qa-20261021-020527-a4982f43`: navigation **passed**, but overall run correctly
  failed closed (1 of 3 selected executed). The generated project lacked the new
  test file. `./dev generate` registered it.
- `today-qa-20261021-020753-ceb6ee3a`: zero tests executed; failed closed. Regeneration
  alone retained the old test-product receipt, including with `./dev build Debug
  --scheme TodayMock --for-testing`. No framework/cache policy was changed.
- `today-qa-20261021-020923-e31127db`: both chat methods actually executed and failed.
  Reading test attempted the offscreen bottom Chat button while the intentionally
  retained sidebar was open. Draft Paste preserved exact content, then XCTest's
  identifier query rejected its length over 128 characters. Corrected the test
  to use Close sidebar and an exact label predicate, preserving assertions.

## Navigation measurements

App action-to-layout proxies, milliseconds in order:
Today → Week **380.936**; Week → Month **349.408**;
Today → retained Month **248.827 / 265.705**;
Month → selected-day Today **215.934 / 240.545**.
The fresh-process app-init proxy was **8093.936 ms**, including synthetic fixture
loading; it is not production persisted-store startup latency. No cold OS-cache
claim. Navigation ran once and its passing behavior was not repeated.

The failed-harness chat batch first layouts were **1682.261 / 1564.181 ms**.
These are first presentations of an existing 100-message conversation in fresh
processes, a different cohort from the earlier small-fixture empty Chat opening.
No CPU profiler was run and no app-owned hotspot or regression cause is proven.
The earlier keyboard/SwiftUI profile is not new causal evidence for this cohort.

Navigation screenshots were inspected. The selected tomorrow screen shows both
correct items. The immediate Back to today capture includes overlapping date
text during the captured transition; persistent overlap was not established, so
this is retained as a visual observation rather than claimed as fixed or as a
settled-layout pass.

## Final result and limits

`today-qa-20261021-021221-11c63f53`: **2/2 chat methods passed**, UI and shutdown
exit 0, no journal errors. Together with the unchanged navigation method's earlier
pass, all three requested journeys have actual passing execution. Final chat
first-layout / retained-editor reopen samples are **1642.700 / 1445.683 ms** for
reading and **1972.255 / 1667.200 ms** for multiline draft. These action-to-editable-
layout samples are raw endpoints, not input readiness, physical tap-to-pixel,
XCTest elapsed time, or a before/after optimization comparison. The two app
processes share OS caches; the first followed a simulator reboot. Retained 100-
message Chat reopening is visibly more costly than the earlier small-fixture
cohort, but fixture/presentation differences prevent a causal comparison.
No additional profiling or speculative application fix was attempted.

The five runner invocations total **483.664 seconds** (about 8.1 minutes), including
three incremental test builds of **12.007 / 11.555 / 11.210 seconds**, not the planned
single test build. The extra builds were required by new-suite registration and
concrete test repairs. The application executable remained byte-identical to the
previous cohort (`df04e02edd7a67f09f4840f67325169c7bd9fe507b613b6c51a62b5e33969406`).
No passing journey was rerun, no full UI or redundant unit suite was run, and no
additional coverage was expanded. `./dev format --check` and `git diff --check`
passed. Preparation, evidence export and review are outside the runner duration.

Final restored-draft screenshot was inspected: the native composer contains the
CJK draft tail and remains editable over the existing conversation, with keyboard
visible. Full content equality and absence of a submitted message are asserted by
XCTest, not inferred from the screenshot. Chinese IME marked-text composition,
physical-device interaction, Live Foundation Models and actual Apple data remain
unverified. No product behavior changed, so no independent product-fix review was
needed. The test diff received one focused self-review for fixture isolation,
exact no-send checks and gesture-driven state retention.

Runner shutdown completed; Device panel closed; host-heavy and owned-cache locks
are free in `released-inventory.json`. The protected Today-UI simulator, dirty root
and other worktrees were untouched.

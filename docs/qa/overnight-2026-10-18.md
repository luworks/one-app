# Today overnight QA — 2026-10-18

Status: **in progress**. This document is an evidence checkpoint, not a release sign-off.

## Scope and execution

The owner requested comprehensive user journeys, reusable tests, verified issues, fixes and PRs merged to main.
The frozen baseline is `55e73d571f57987e5adc57d5d6b710bcec7a998a`.
The full simulator suite runs once against that baseline, with default signing and optional screenshot journeys enabled.
Repairs and new journeys will receive targeted checks after the full run; a targeted pass does not overwrite a full-run failure.
Independent agents use isolated worktrees. Pure Swift runs share a mutex and use `--jobs 2`; only one simulator UI runner runs at a time.

Reusable commands, source inventory and platform boundaries are in [the coverage matrix](coverage-matrix.md).

## Verified defects and prepared fixes

| Issue | Reproduced behavior | Fix PR | Evidence before integration |
|---|---|---|---|
| [#33](https://github.com/luworks/one-app/issues/33) | A new timed reminder answers an older event's pending time question | [#40](https://github.com/luworks/one-app/pull/40) | English/Chinese logic regression failed before fix; related 57 tests passed after fix |
| [#34](https://github.com/luworks/one-app/issues/34) | Old daily/weekly recurrence history exhausts the expansion cap before the visible date | [#43](https://github.com/luworks/one-app/pull/43) | Dedicated calendar regressions plus 76 related passing tests |
| [#35](https://github.com/luworks/one-app/issues/35) | Week/Month projection adds a date to EventKit's exclusive all-day end | [#43](https://github.com/luworks/one-app/pull/43) | Exact production projection extracted and tested; live EventKit edge not yet exercised |
| [#36](https://github.com/luworks/one-app/issues/36) | Corrupt Share inbox is deleted/overwritten; failed submission dismisses as success | [#42](https://github.com/luworks/one-app/pull/42) | Two new file-backed cases failed before fix; 91 related tests passed (one optional benchmark skipped) |
| [#37](https://github.com/luworks/one-app/issues/37) | A midnight point alarm belongs to the preceding day | [#43](https://github.com/luworks/one-app/pull/43) | Half-open day membership, including DST boundaries |
| [#38](https://github.com/luworks/one-app/issues/38) | Share inbox is consumed before SwiftData save succeeds | [#45](https://github.com/luworks/one-app/pull/45), [#46](https://github.com/luworks/one-app/pull/46) | Old ordering loses a real file-backed draft with an injected persistence throw; six durability cases pass against a transaction stand-in. Real SwiftData UI journeys are prepared, not yet executed |
| [#39](https://github.com/luworks/one-app/issues/39) | A 90-day Health comparison has only 13 days of previous-period history | [#44](https://github.com/luworks/one-app/pull/44) | Uneven 180-day readings reproduced incorrect comparison; corrected history and fixture bounds pass |

The Share stack must merge in order: #42, then retarget #45 to main, then retarget #46 to main after #45 merges.
No existing model is removed. The import receipt is additive; `Habit` and `LedgerEntry` stay in the schema.
The Share persistence injection throws before save and is not evidence of a spontaneous SwiftData storage error.

## Completed checks

| Revision / scope | Actual result | Evidence |
|---|---|---|
| Frozen baseline, pure logic with optional 100k benchmark | 590 executed, 0 skipped, 0 failures; capture train 46/46, test 22/22 | `/tmp/today-overnight-20261018/logic.log` |
| Integration `1d843b0`, PRs #40–45 plus runner #41 | 613 executed, 0 skipped, 0 failures; capture train 46/46, test 22/22 | `/tmp/today-overnight-integrated-swift.log` |
| Runner host contracts | 6 passed; no simulator/build invoked | `python3 -m unittest discover -s ios/Eval -p test_e2e_runner.py` |
| Share persistence UI additions in #46 | DEBUG/non-DEBUG syntax parsing and diff check passed; runtime pending | `/tmp/today-overnight-share-platform-report.md` |

The integrated 100k Activity benchmark ran on the Mac: 2.67 seconds insertion, 47 MB file,
2.16 ms newest page, 1.54 ms deep page, 0.11 ms one-day count and 49.6 ms search.
These numbers do not establish iPhone performance. The three new #46 UI methods do not change package logic;
the 613-test evidence precedes that UI/hook commit and must be interpreted accordingly.

## Full UI run and remaining work

The full run is still active. Authoritative artifacts are under `/tmp/today-overnight-20261018/`:
`command.json`, `progress.json`, `full-ui.log`, `full-ui.xcresult`, and `screenshots/`.
Totals, failure classification, targeted repairs, merge SHAs and final shutdown evidence will be recorded after completion.
At this checkpoint, `ActivityDataTests/testPageExplainsPausesAndClears` failed to find the count-bearing clear confirmation;
the product cause is not yet established. Physical alarm ringing is explicitly skipped on the simulator.

Pending integration acceptance includes the app and Share extension build, three persistent Share journeys,
the new AI interruption journey, relevant calendar/Health smoke checks, and reopening a pre-change file store with the additive schema.
The runner also needs one actual targeted simulator invocation; host contract tests alone do not verify its lifecycle.

## Platform limits

Simulator fallback does not verify Apple Intelligence generation. Simulator tests do not establish physical AlarmKit ringing,
Focus/Silent behavior, HealthKit authorization/data/query performance on the owner's phone, real account/invitation effects,
widgets on system surfaces, Siri/Shortcuts, Lock Screen Live Activities or 100k-row iPhone performance.
The owner is asleep; this run does not drive the phone or ring real alarms.
Apple/Overlap reference screenshots are unavailable, so screenshot capture is not a parity verdict.
The most recently installed/launched phone build remains baseline `55e73d5`; these overnight repairs are not yet installed there.
No finite test run establishes absolute freedom from bugs.

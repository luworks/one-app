# Populated-history Chat profiling and local Focus lookup

## Diagnosis

Baseline PR149 head `8d762c3c568d2e6c0c1e9c748e6a8eb7870ff357`
retains `611da244` and `6923f5e0`. The unchanged, versioned
`populated-history.json` has 100 messages, 800 completed reminders and 200
historical events, plus today's items. This is synthetic TodayMock data, not
physical-device or production-store evidence.

Time Profiler attached to the owned simulator's live TodayMock PID **8379**
before the first Chat tap, with a 70-second cap. The complete trace spans both
first open and retained reading-position reopen. Dated app stdout and host
mach-absolute/wall-clock calibration align each `begin.page.ai` to
`chat.composer_laid_out`. This is an editable-composer layout proxy, not a
pixel/readiness endpoint or XCTest query duration. No focus_begin/focus_end event
occurred in either interval: this existing conversation opened keyboard-down.

First open: **2156.112 ms**, 1794 main-thread sample rows; 1307 include
`DayAgenda.attentionEntry`, 1008 `TodayFocus.reference`, 531 `Ledger.ref`.
Reopen: **1637.856 ms**, 1453 rows; 1248 include `attentionEntry`, 1005
`TodayFocus.reference`, 537 `Ledger.ref`. JSONEncoder appears in 506 / 515 rows;
MessageView in 3 / 0, AskComposer in 15 / 5, UIKeyboard in 1 / 0.
Counts are inclusive sample membership, not additive CPU percentages.

The observed hot path is the underlying Today row action resolution, not eager
Markdown or long-message rendering. For each visible row, `attentionEntry`
searched historical tasks, alarms and events, constructing canonical Focus
identities through JSON encoding/normalization for candidates that cannot match.
The same work repeats when presenting the retained Chat panel.

## Change and review

For `today.local` identities only, decode the embedded persistent ID once, skip
incompatible local kinds, then try the matching model. Always validate its full
Focus identity (including occurrence/source); if decoding/native equality or
validation fails, retain the original canonical identity search. External
identities use the original search. No cache, new data authority, message
filtering, composer change, source API fallback or write permission change.

Focused product review found a P1 in the initial strict prefilter: native
PersistentIdentifier equality can differ after migration (documented by
StoreUpgradeTests). The final helper keeps the canonical fallback. A narrow
follow-up review confirmed that P1 resolved and found no remaining kind/identity
issue. Both reviews were read-only GPT 6.1 Sol, medium.

`origin/main` at `0ec5ddc6` was merged normally after the product fix, retaining
PR148's Returned-list removal. This main integration is disclosed when comparing
final measurements with the older baseline. The earlier same-base trial is
retained separately and is not final behavioral acceptance.

## Runs and retained failures

Evidence root in primary checkout:
`tests/results/overnight-qa-20261021/long-chat-profile-v5/`.
Complete closed xcresults remain under primary `tests/results/runs/`.

- `today-qa-20261021-021846-d3e41fd7`: baseline, no rebuild, reading-position
  method **1/1 PASS**, runner 114.273 s. XCTest logged an untitled 44x44 Alert AX
  node and retried an offscreen Chat hit point; the final method passed. Neither
  the Alert origin nor a product failure was established.
- `today-qa-20261021-022259-bb1e7e03`: initial candidate without the review fix,
  193.920 s. Focus settle/restore/delete method passed. Long-chat method failed
  because the selected History 087 label exceeded XCTest's 128-character
  identifier limit. It is now queried using exact label NSPredicate, preserving
  the full same-message and 35-point position assertions. The initial trial's
  profiled first/reopen proxies were 631.769 / 347.119 ms on the original base;
  these are diagnostic-only and do not accept the rejected prefilter.

## Final integrated result

`today-qa-20261021-022629-2f814f27`: **2/2 PASS**, UI and simulator shutdown
exit 0, runner **188.441 s**. Incremental build succeeded. The two methods were
`PopulatedHistoryTests.testExistingLongChatKeepsReadingPositionAfterClose` and
`TodayFocusTests.testSettleAndRestoreChangeFocusCountsWithoutCompletingReminder`.
The latter verifies settle/unsettle counts, source remains incomplete, explicit
confirmed delete and Undo. The final reading screenshot was inspected; History
088 remains at **y=351.3 before/after Close**, with keyboard hidden.

Final Time Profiler PID **41730** attached before the first tap, same owned
Today-Dev-c81e77d5 simulator, derived data, fixture, Debug composition and method.
First/reopen layout proxies: **897.235 / 274.880 ms**, compared with baseline
**2156.112 / 1637.856 ms**. Final main-thread sample rows: **357 / 190**;
`attentionEntry` **120 / 118**, `TodayFocus.reference` **7 / 6**, `Ledger.ref`
**3 / 4**, JSONEncoder **3 / 4**. This supports removal of the observed repeated
encoding cost; the remaining scans are not claimed eliminated.

The final product includes PR148's Returned-list removal and fixture clock
forwarding, unlike the baseline. The same-base intermediate trial independently
showed the hotspot reduction, but its strict prefilter was rejected and repaired.
These are one-run, profiler-attached observations, not an isolated statistical
estimate or a claim that message count alone caused the slowdown. OS caches,
profiler overhead and normal scheduler noise remain. No cold-keyboard attribution.
Trace export warns of one instrument table without a known input source; the
Time Profiler sample table was present and exported successfully in all captures.

Baseline executable SHA256:
`df04e02edd7a67f09f4840f67325169c7bd9fe507b613b6c51a62b5e33969406`.
Final executable SHA256:
`e719337c3c44065d9239b5e7e4a6887f1c1fbdc0e61ceaf400f073be8abb21bc`.
Product source tested is merge `0e8baaf3291083f17f2f27faf1be58f863a775fa`
(including fix `fd09aed4`) plus the exact-label test repair; later changes only
record evidence and commit that test repair.

Three runner invocations total **496.634 s (8.28 min)**. One initial no-build
baseline, two legitimate incremental builds (candidate, then reviewed repair +
main integration + selector fix). No full suite or unrelated unit tests. Final
format check and diff check passed. Profiler/analysis, closed xcresults, logs,
attachments and build provenance are retained and indexed in the QA journal.
Owned simulator shutdown and Device panel close completed; host/cache locks free.

Prior exact multiline-unsent-draft and navigation checks are retained from PR149,
not rerun because the composer and navigation implementation were not changed.
Native IME composition, actual Apple source permissions, migrated-store fallback
runtime behavior, live Foundation Models and physical-device interaction remain
unverified in this run. Migration fallback received source review, not a claimed
new migration test. No phone install, signing, real user-data writes or CI-policy
change occurred.

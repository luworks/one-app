# PR120 Chat verification continuation

Scope: `fix/phone-freeze-1748a4a8`, starting at `0b2eb60c17a9a19b9b30924983c9be9e92047e69`. Production cache repair remains `97b006dd`; this continuation changes only the focused UI regression and this evidence summary. No phone installation, merge, signing, data reset or CI policy changes.

## Findings and repair

The original combined native Calendar/Reminders import journey reached imported rows, editor Cancel under its unchanged 10-second assertion and all four tabs. At Chat, XCTest waited 60 seconds for animation completion before synthesizing input, then stalled again. Existing app logs still contain main-run-loop idle replies. This distinguishes the observed framework wait from the original ReminderKit watchdog stack, but does not establish its animation owner or prove the combined journey healthy.

The independent Chat regression reproduces native text entry separately, while keeping the combined regression in core smoke. Its first attempt stopped before Chat because the default dataset scrolls the `todayDate` header out of the accessibility tree; readiness now checks the actual navigation control. The next attempt entered the exact synthetic draft in about one second. Its post-entry assertion failed because the placeholder disappears after entry. XCTest also reports a legacy TextField versus modern UITextView/SwiftUI.VerticalTextView mismatch. Both failure hierarchies show the focused input value `Navigation check` and Send.

The shared test helper keeps native `TextField.typeText`, waits for the keyboard, then locates the entered draft through an exact value query without restricting the conflicting accessibility type. It asserts the exact draft, Send availability, absence of a sent message, Close and draft disappearance. The independent method additionally asserts Today selection and a usable Chat button. The combined method retains native imports, editor timing, all tabs and final native reminder state assertions. No timeout/assertion relaxation or global quiescence override is introduced.

## Retained evidence

All paths below are relative to `/Users/yuanlu/code/one-app/tests/results/` and indexed through the QA SQLite journal.

- `runs/today-qa-20261019-164400-b3480929/`: original failed combined run, untouched. Its `ui.xcresult` has readable Staging logs but lacks top-level `Info.plist`; `xcresulttool` cannot open it as a completed bundle. It is not a complete parseable xcresult.
- `phone-freeze-1748a4a8-20261019/chat-selector-hierarchy/`: previous selector-trial hierarchy/video, read only; the unsupported selector trial was not restored.
- `runs/today-qa-20261019-165622-17b9d206/`: initial independent readiness failure; finalized xcresult retained, outer command timed out during runner finalization.
- `runs/today-qa-20261019-165835-04d1ea0a/`: native typing succeeded; exact post-entry query failure, finalized xcresult and exported attachments retained.
- `phone-freeze-1748a4a8-20261019/chat-isolated-v3-attachments/`: before/after hierarchy and exact automation type mismatch.
- `phone-freeze-1748a4a8-20261019/chat-isolated-mainthread.sample.txt`: sample attempted as the app exited; empty call graph, therefore no stack evidence and no main-thread health claim.

## Focused verification

`./dev test ui --only TodayUITests/TodayReminderCompletionTests/testChatDraftAndCloseRemainResponsive --timeout 180` passed: one expected method, one executed, zero failures/skips, 22.304 seconds for the method (85.259 seconds including build/runner lifecycle). Full parseable xcresult, log and reconciliation: `runs/today-qa-20261019-170041-6b01b205/`. The adapter reports successful simulator shutdown. This validates actual native text entry, the narrow helper repair and Close, in TodayMock on the owned iOS 27 simulator. The run used the working-tree test patch over `0b2eb60c`; only a line-wrap formatting correction followed. Production source was unchanged.

A focused diff review confirmed unchanged native-import/editor timing/state assertions and no global quiescence override. `./dev format --check` initially found one long assertion line, corrected by wrapping it; no behavior changed and no passing UI check was repeated. The corrected `./dev format --check` passed.

## Acceptance boundary

The original combined import-plus-Chat regression remains unverified; do not infer its pass from an independent Chat result. No production endless animation or main-actor task has been proven. The earlier cache integration, Health, Focus persistence and compact editor checks were not repeated. Physical iPhone remains on the explicitly retained `9043647` rollback with owner-confirmed assisted interaction; PR120 is not its installation target. Live Foundation Models and physical-device candidate interaction are unverified.


## PR120 focused review round 1: P2 response

The independent read-only review found a real regression in the cache repair: an Apple Calendar occurrence snoozed until the next day survives in the Focus file, but a cold start or Calendar version invalidation clears its display snapshot. Today's range excludes the original occurrence, so `DayAgenda.resolved` returns nil. The due item disappears from Returned to Today; before expiry it becomes Unavailable and loses Restore/Open. The earlier Delete-availability limitation did not cover this behavior.

The response adds exact saved-record hydration to HomeView's existing lifecycle. A cancellable task runs on initial presentation, Calendar version changes, Focus revision changes and foreground transitions. It reads only known `eventkit:` anchors from persisted Apple Calendar Focus records. EventKit objects stay on a separate reader actor; only Sendable scalar fields cross to the main actor. Recurring reads use a two-minute occurrence window scoped to the saved calendar/account, then compare the full provider/account/calendar/item/occurrence identity. Nonrecurring reads use the exact identifier and the same identity comparison. There is no title match, all-history scan, per-row I/O, automatic source write or new persistence schema.

Publication rechecks task cancellation, Calendar version, current access/on state and full saved identity. Existing snapshots for requested records are retired before refresh, so an absent source cannot leave an obsolete title actionable. Missing, denied or changed identities keep the persisted Focus choice. A separate observable snapshot revision presents imported content without repeatedly invalidating the Calendar version. `DayAgenda` display and Open now share `cachedFocusEvent`; Open forwards the snapshot's exact external identifier and actual start to the existing native editor, which performs its existing live read and write-time validation. Cached identity remains display data, never write authority.

Focused evidence (primary persistent `tests/results/devtools/logs/`):

- `08bebee5a7c6457f8e5ee1737cfb7cb9-xcode/`: initial integration run, expected/executed 2, both passed, no skips. Existing zero-native-store rendering/denied-write regression passed in 0.035 s; initial hydration regression passed in 0.032 s.
- `dc04b8b56ee24c02a82de5557565e2c9-xcode/`: final changed hydration regression, expected/executed 1, passed in 0.030 s, no skips; complete `TodayTests.xcresult`, report and command logs retained. It creates/reopens the real Focus file; injects a scalar exact importer through production CalendarSync; verifies expiry outside the original date range, current source title/full identity/exact Open payload through the same production resolver used by DayAgenda, 1,000 cache reads with zero native-store creation and no additional importer calls, version rehydration, in-flight version/denial/cancellation rejection, account/calendar/item/occurrence replacement rejection and preserved choices when the source is absent.
- Final `./dev format --check`: passed, log `3adfff9b5c39438a81d765b71adc34f9.log`. `git diff --check`: passed.

This integration test uses a fake exact importer, does not mount DayAgenda, and does not present Apple's editor. It proves the production cache/resolver contract and Open payload, not live Apple Calendar access or a complete UI journey. App assembly compilation is recorded below. The original combined import-to-Chat wait remains unresolved and its failed/incomplete evidence remains unchanged. The independent Chat pass is still only the limited acceptance described above. No additional independent review round or full UI replay was run.

Source readiness applies to the original watchdog repair plus this concrete P2 response; it does not imply candidate phone acceptance. The accepted physical phone remains `9043647`, untouched. Root retains the later merge/device acceptance decision.


Assembly check: `./dev build Debug --scheme TodayMock --timeout 300` compiles the real FeatureToday and TodayShell lifecycle changes. The first native build exited 0 in 28.681 s (`22af190d26884af8bc1d22c874e8f7be.log`), but the adapter rejected provenance because the fixture catalog was edited while it ran. This is not recorded as a passing engineering build. One unchanged-source incremental build follows; its final receipt/log and final SHA are indexed in `phone-freeze-1748a4a8-20261019/focus-hydration-source-ready.json` and the QA journal. No passing UI test was repeated for this bookkeeping correction.

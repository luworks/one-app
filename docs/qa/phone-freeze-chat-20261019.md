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

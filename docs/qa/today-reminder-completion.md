# Today reminder completion writeback

Issue #88, PR #89. Owner clarified deletion works; deletion is outside this change.
Inherited baseline: `5767d81c767ffec43e328aeaa6d974b3507e3c30`, equal to fetched `origin/main` when diagnosis began.

## Diagnosis and change

The Today circle is `TaskRow` → `TaskActions.toggleDone`, also used by reminder lists.
Previously it changed `isDone` and showed a Completed toast before any EventKit write.
A later local save scheduled debounced reconciliation. Reconciliation compared entire
reminder fingerprints: any Apple field change could replace the local completion;
EventKit errors only became `lastError`, and a missing existing identifier silently
returned from `push` while its local fingerprint was still treated as accepted.
These are source-confirmed paths to an unaccepted completion being reported as success.
The owner's exact phone/iCloud failure has not been captured in a runtime trace, so its
specific triggering condition is not asserted.

Completion now resolves the existing EventKit identifier and commits only `isCompleted`
before changing the local row, saving SwiftData, recording Activity and showing success.
Disconnected, missing, read-only and rejected writes retain the open row and show a reason
and retry instruction. A successful Apple write is not reversed if local persistence fails.
An asynchronous fetch begun before that accepted write is discarded using a revision fence.
Agreed fingerprints update only the committed fields and are published after local save;
pending note/list/due/repeat edits are not falsely acknowledged. Undo restores the occurrence
date in Apple and the local plan, and refuses to undo a newer external completion/date change.
Events, Add/Apply, deletion, and Habit/Ledger schemas are unchanged.

One focused read-only review found three concrete issues (failed-save baseline, repeating Undo,
and acknowledgement of unsent fields); all were addressed together. No broad review loop.

## Evidence

Primary retained directory: `tests/results/runs/today-completion-20261018/`.
The QA Activity journal indexes raw logs, complete xcresult bundles and hashes.

- `logic.log`: `swift test --jobs 2 --filter ReminderCompletionFenceTests`, 4/4 passed.
  Pure deterministic evidence covers rejected writes, pre-commit fetch invalidation,
  repeated revisions and preserving the other fingerprint fields. These are not EventKit tests.
- `ui-acceptance/`: source/binary `5449ba8`, incremental simulator build and 2/2 UI methods passed.
  Actual Today circle, a fresh EventKit store (`isCompleted`), fresh SwiftData context,
  post-completion reconciliation, foreground return, full process relaunch, injected Apple-write rejection and retry.
  The rejection is a DEBUG injection before the real save, not a spontaneous platform failure.
- `final-ui/`: final functional source `4eaa166`; focused incremental build and the successful
  Today completion/refresh/relaunch journey passed (1/1, 46.840 s) on the final persistence ordering and receipt changes.
- `ui/`: initial runner preflight refused the simulator already booted by Device panel.
  No xcodebuild ran. The panel was shut down, then the same named simulator/cache were reused.

Simulator: Today-EventSave (`9028A2F8-1FF3-4C59-8084-77132FE787B3`, iOS 27).
Cache: primary `tests/results/runs/calendar-save-20261018/cache`.
The simulator was shut down, its Device panel closed and the resource window released after final verification.
Only one heavy runner; `-jobs 2`, serial selected methods. No full suite, signing changes,
phone installation, real user reminder edits, branch deletion or force push.

Permanent scenario: `tests/fixtures/today-reminder-completion.json` (Bring the water cup at 12:30).
UI tests namespace its title and seed a simulator-owned reminder through the DEBUG `addToday` hook.
The UI journeys use the real EventKit store, not the ordinary sync-disabled UI-testing path.
They assert completed/open persisted states, not merely whether a row disappeared.

No runtime baseline red run was performed on the original phone failure. Existing recurring,
complex alarm and list semantics were inspected in source; the selected UI journeys use a one-off
reminder in the simulator default list. Physical-device/iCloud propagation and acceptance of
Yuan's original reminder remain unverified. A merge is not phone acceptance.

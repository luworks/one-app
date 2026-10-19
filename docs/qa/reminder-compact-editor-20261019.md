# Compact native reminder editor

Production SwiftUI `TaskEditor` now opens a compact editing sheet from Reminder rows and Calendar task rows. The existing complete form remains under More. The 4×3 preset grid is shared with existing quick add; day adjustments retain wall time across DST. The selected field is explicitly Deadline or Planned time. Opening and cancelling do not enable dates, alerts or alarms.

## Reference scope

The selected reference is the second Due screenshot (921×2000), normalized to the simulator's 440×956 viewport. Only the app-owned bottom panel is the fidelity target. Its approximate normalized bounds are x8/y553/w424/h394, corner radius 46, content inset 10, title row 40, selected-date strip 37, three grid rows 49 and four footer targets 44.

The native implementation uses a 366-point content detent plus the native bottom safe area, radius 48, 44-point title/date rows, 46-point preset rows, 44-point controls and scrolling. Accessibility sizes use two grid columns. System semantic colors and fonts adapt to appearance and Dynamic Type.

Intentional differences: the date strip names the affected field; a real Deadline/Planned control occupies the reference's unsupported snooze control. The footer exposes existing Flag instead of a nonfunctional Share icon. Repeat, alerts and alarms use existing choices; advanced recurrence, notes, checklist, list, plan, duration and deadline remain in More. No Due nagging or snooze behavior is invented.

## System writes

Save uses the independently delivered PR106 acknowledgement path. Editor deletion adds a narrow explicit system receipt before local deletion, and guarded session-scoped Undo retains the original native writable payload. It does not claim an atomic EventKit/SwiftData transaction. Already-absent external reminders do not receive resurrection Undo. Background deletion remains on its existing path.

## Calendar suitability

Calendar task rows already construct the same `TaskEditor`, so they receive the same presets and explicit planned/deadline choice without a second component or write path. This is appropriate for flexible task planning. Fixed calendar events retain the current native EventKit editor and its start/end duration, all-day exclusive end, calendars, invitations and recurrence semantics. No event is converted to a flexible task.

## Evidence

The original editor and standalone time-save repair evidence are recorded in `reminder-time-save-20261019.md`. Raw runs and native attachments remain under `/Users/yuanlu/code/one-app/tests/results/`; no private reference image is committed or uploaded to CI.

- Logic: `./dev test unit --only TodayTests/QuickTimeTests --only TodayTests/ReminderCompletionFenceTests`: 10 passed, zero missing.
- Native UI: completion failure/retry/writeback/Undo passed in `today-qa-20261019-112632-222b492f`; concurrent edit failure/retry, stale snapshot rejection, native deletion failure/retry/payload Undo and final refresh/relaunch absence passed in `today-qa-20261019-113208-391623fa`. The undated/keyboard method passed in that run too. Presets, Save/Cancel and planned/deadline independence passed in `today-qa-20261019-113733-26b75545`.
- First failures are retained: the UI adapter refused a simulator already booted by the Device panel (`112610-d878d47d`, zero tests); `112632-222b492f` lacked a deterministic sync trigger; `113208-391623fa` exposed duplicate grid IDs omitting negative buttons; `113733-26b75545` queried a native Picker as Button; `114102-c1919ab3` reached List but checked Flag before scrolling it into view. The production grid IDs and the focused selectors/scrolling were repaired without weakening title/time/backend assertions.
- Focused deletion integration: `./dev test integration --only PlannerSessionTests/confirmedEditorDeleteFailurePreservesIdentityThenRetryAndUndoCommitOnce --only PlannerSessionTests/confirmedEditorDeleteCannotResurrectExternalRemovalOrReappearance`: 2/2 passed, zero missing. Raw xcresult/report: `tests/results/devtools/logs/08efeb881b57406c87f8a7f7921c3fb4-xcode/`. These use real models/actions and service fakes; actual EventKit is independently exercised by the UI method above.
- Final advanced-options method passed in `today-qa-20261019-114459-bc4da987`: all twelve presets are hittable and at least 44 points; unchanged Save disabled; More retains date/plan controls; editing Notes then Cancel leaves stored Notes unchanged; List and Flag remain reachable by scrolling. Across the bounded repair batches, all five distinct representative UI methods passed. The standalone time-save roundtrip passed separately in PR106.
- `./dev format --check`, `./dev lint` and `git diff --check` passed. No full-suite rerun. Routine verification exceeded the initial ten-minute budget to repair the concrete grid identity issue and focused selector/scrolling failures; passing completion, keyboard and concurrency journeys were not repeated.
- Physical-device, real account, AlarmKit ringing, Release and hosted CI acceptance are not established by these simulator checks.

## Visual comparison

`tests/results/reminder-compact-20261019/due-native-same-viewport.png` and `due-native-panel-comparison.png` combine the actual reference with an actual production SwiftUI simulator capture, both normalized to 440×956. The same fixture title is “test”, selected deadline October 19 at 10:32, unchanged Save, and no keyboard. The system status bar and app-owned list/header are outside the comparison scope.

| Surface | Reference → native | Assessment |
| --- | --- | --- |
| Panel top and radius | y≈553 → y≈563; radius≈46 →48 | Native safe area/detent; about 10 points lower. |
| Card inset | x≈18 → x≈18 | Matched horizontal rhythm. |
| Selected strip | y≈672/h37 → y≈678/h44 | Explicit field label and minimum hit height; semantic system red. |
| Preset grid | four columns, three rows≈49 → four columns, three rows46 | Exact twelve values; unique signed identities; 44-point minimum verified in UI. |
| Footer | four native controls | Existing Flag replaces unsupported Share; native SF Symbols are slightly smaller. |

This is a faithful compact layout with documented semantic/accessibility differences, not a claim of an exact pixel match. The reference's deep red, quiet/snooze control and Share action are intentionally not copied into unsupported behavior. No image is used as the production UI.

The focused review's concrete native Undo payload concern was resolved by retaining/copying actual writable EventKit fields, including unsupported native recurrence and all alarms. The real EventKit UI method compares all recorded metadata except the newly assigned identifier after compensation.

## Independent time-save delivery and main integration

PR106 head `41e47590213da40465b814b33477df4c034153dc` was merged normally as `324760cc8a1c4c6d138d2ae5abf76346b89b9e9c` after auditing CI run 39301482757. Its actually tested integration SHA was `3ed1bd30f6db8fb553800b070cb32d8bf2960460`, with parents `f76b106cde588968ccb463bbc67c4c782a378e64` and `41e47590213da40465b814b33477df4c034153dc`.

All seven lane reports had zero missing/errors/failures. All 209 reported artifact file sizes and SHA256 hashes matched the downloads. The core UI/integration/snapshot xcresults reopened successfully with 7/13/6 passing leaves and no skips. Business had 678 passing leaves plus four explicitly allowed existing benchmark/export skips; its report says incomplete coverage, so this is not described as a full-suite pass. The build log contains the actual successful Debug app build; no release/distribution product claim is made.

Before merge, live main was `b87f94424c3a86a6ff8a0d4b59287b98b79ad2aa`, containing PR105 and PR104. Those AI/CI changes did not overlap the save-fix production sources. Existing required checks were clean and GitHub reported mergeable; no unrelated passing business suite was rerun solely to chase main. The older CI integration tree is not presented as a test of the later main tree.

The compact branch then merged actual main without conflict as `be51c0b7ba57069f1f2f56bfd2f653969459a461`, parents `ed5a971fa6c8698411227606046239fc6f7e0056` and `324760cc8a1c4c6d138d2ae5abf76346b89b9e9c`. PR108 now targets main directly. Upstream AI and CI files were imported unchanged by the merge; no new local heavy run was started. The earlier native evidence remains tied to its recorded source hashes/commits. Hosted acceptance of the new PR108 integrated head remains separate.

The complete downloaded reports, artifact audit, source parents and merge metadata are retained under `tests/results/reminder-compact-20261019/ci106-run-39301482757/` and indexed in the canonical QA journal. Release, physical-device and iCloud synchronization remain unverified.

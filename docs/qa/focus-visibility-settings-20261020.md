# Today Settle and Snooze visibility

Baseline: clean isolated `t3/settings-settle-snooze-controls` fast-forwarded from
`a56646b2ec9944da09df18eadc084ca468a50787` to fetched origin/main
`e64a8ecbc556c2558a73347097a1f0a28a1ef465` (PR135 included). Parent dirty files
were not copied. Active writer inventory showed only this implementation.

Settings → Today adds independent Show Settle and Show Snooze switches using the
existing Preferences/AppStorage pattern. Unset defaults are true and false;
explicit stored values remain authoritative. Each switch controls its action in
Today swipe/context/accessibility commands and its matching trailing section.
Overdue, Snoozed, Settled, Tomorrow retain their relative ordering when visible.

The preferences do not write Focus state or alter source models. Existing hidden
entries remain hidden while their controls are off; turning the switch back on
restores the section and its existing Unsettle or Restore command. Expiry,
restoration, calendar/reminder times, completion and notifications are unchanged.
No shell capsule, gray cards or compact Free typography changed.

Verification uses existing versioned `tests/fixtures/today-focus.json` and
`empty-relaunch.json`; no new fixture format or framework.

- `./dev test unit --only TodayTests/PreferencesTests`: 18 executed, passed, none missing.
  Raw log and report: primary `tests/results/devtools/logs/50b02fb870a540f584298f56d06fdda8.*`.
- `./dev generate`, `./dev resolve`, `./dev format`: passed after pinned bootstrap.
- `./dev format --check` and `./dev lint`: passed.
- First focused UI batch: default visibility and Snooze source/deadline preservation
  passed. Settings/relaunch journey failed when a row-center tap left the switch
  unchanged (1 instead of 0). Reused existing `toggleSwitch()` helper, which taps
  the native switch at the right edge and waits for its value to change. Product
  behavior and assertions were not weakened.
  First raw log, full xcresult and exported PNGs: primary
  `tests/results/runs/today-qa-20261020-115946-d0f81047/`.
- Only the failed Settings/relaunch method was rerun, using the same named runner
  and DerivedData with an incremental test build: **passed 1/1**, zero missing.
  Settings off → relaunch → Settle-only → both on retained the original records
  (one Settled and one Snoozed), then Unsettle/Restore returned both items.
  Retained run: primary `tests/results/runs/today-qa-20261020-120525-4c043699/`.
  Three unique representative UI methods passed across the batch and focused
  retry. Both completed xcresults and exported PNGs remain in place, indexed
  through the QA journal. The runner shut down its simulator after execution.
- Existing density/disclosure tests now explicitly enable Snooze to retain their
  all-controls coverage; they compiled in the incremental build but were not
  executed in this focused run.
- One independent read-only focused review: no blocking findings. Separate
  Settle-off/Snooze-on UI combination is not individually exercised.

Owned runner: `Today-Dev-ecae993f`, UDID
`21E1FFB8-AAFF-43BA-B7C8-EDCAADE2BEBA`; DerivedData:
primary `tests/results/devtools/derived-data/ecae993ffe7d329d2e8a`.
The protected Today-UI simulator and phone caches/install were not used.

This is source/logic/simulator evidence only. No full UI collection, physical
phone interaction, Live Apple service or notification acceptance is claimed.

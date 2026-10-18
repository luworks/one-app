# Settings automatic changes toggle

Implementation base: `d8a15f2` in isolated worktree `t3-d2d6af47`. Health changes from that base are already on main; this change edits no Health, Calendar or World Clock files. Related handoff: https://github.com/luworks/one-app/issues/32.

Settings → AI now exposes a real Automatic changes switch and a separate Scope and duration link. Both entry points reflect the existing `planFreeTime` grant. Explicit ON creates a seven-day grant only when none is active. OFF revokes every active grant in that scope. The end date/time is visible; the switch refreshes expiry while Settings stays open. Save failure rolls back and reports an error without publishing successful grant events. Existing plan-card grant/revoke behavior shares the same Activity formatting.

The AutonomyPolicy decisions and AutoPlan gates are unchanged. No preference, data migration, Activity recording enablement or broader autonomy is added. Automatic plans still run through the existing foreground/launch path with Undo and Activity.

## Executed verification

- `python3 /tmp/today-overnight-swift.py test --jobs 2 --filter AutonomyPolicyTests` from `ios/`: 5 tests passed, zero failures. The shared helper serialized execution and waited for host load below its existing threshold.
- `swiftc -frontend -parse` for the changed app and UI-test Swift files: passed. This is syntax verification, not an iOS build/typecheck.
- `git diff --check`: passed.
- One independent focused review; resolved the finding about premature successful Activity events on save failure. No further broad review rounds.
- Raw logic log: primary checkout `tests/results/settings-ai-automatic-toggle-logic.log`, indexed in its QA Activity SQLite journal with a SHA-256 hash.

## Ready for the root-owned UI runner

No xcodebuild, simulator, device or shared DerivedData access was performed. Root owns scheduling; reuse TodayCodex `E0F10CAC-EA88-4F7F-83FC-A041EF7AA1F0` and primary `ios/.build/TodayCodex` only after its UI grant. Build once and run at most these three representative methods:

1. `OneUITests/LedgerTests/testSettingsTogglePersistsAndControlsGrant`: default Off → ON/end time → relaunch automatic plan with Undo/Activity and overdue exclusion → OFF/revoked → relaunch Off/no automatic plan.
2. `OneUITests/LedgerTests/testAlwaysForSevenDaysAppliesAndGrants`: existing plan card still grants and is reflected by the Settings switch.
3. `OneUITests/ActivityDataTests/testPausedRecordingStopsAutomaticChanges`: ON from Settings never resumes paused Activity; persisted grant still cannot auto-apply while paused.

These journeys reuse the versioned `tests/fixtures/today-dataset.json` and unique test store names. They have been authored but have not been executed for this revision. No physical-device or rendered UI evidence is claimed.

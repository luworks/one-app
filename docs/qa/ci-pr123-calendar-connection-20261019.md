# PR 123 Calendar connection fixture regression

Hosted run `39362607928`, job `118431991890`, failed against PR head
`e3b5d4ca202e64221e1f0d465958436d9a331eee` (tested merge
`105f216a5bc76b7562d451924d743e5e42eeeb5d`). Helpers passed. The first
failed step was `Validate PR risk or merged-main usability`, phase `core-ui`:
7 passed, 1 failed, native exit 65. ShareImport and task dragging both passed
in this run; earlier failures remain separate evidence.

The failing method was
`TodayReminderCompletionTests/testImportedTimelineNavigationAndCancelledEditorsStayResponsive`.
The raw assertion at `UITestHelpers.swift:273` timed out waiting for the Apple
Calendar switch to equal 1. The failure happened during connection setup,
before the combined import/navigation/Chat assertions. The completed xcresult,
AX descriptions and recording show Allow Full Access handled and the switch
remaining 0. No historical main helper failure is assigned this cause.

## Reproduction and repair

On the same owned simulator and incremental cache, the unchanged method passed
on first connection. Running it with an existing Calendar grant then revoked
by its setup reproduced the same assertion failure. TCC recorded Calendar
access allowed, while the app saved its sync toggle as false. The fixture had
reset authorization while retaining its previously enabled preference.

The repair also starts the saved Calendar toggle off when setup revokes
Calendar authorization, using the standard UserDefaults launch argument.
The test then performs the real Settings connection and reopens Settings to
verify adapter state before relaunching for actual imports. Production code,
assertions, deadlines, selection and gate requirements are unchanged. This
establishes the fixture repair, not general acceptance of external permission
revocation or physical-device behavior.

## Validation and retained evidence

All UI commands used `./dev test ui --only
TodayUITests/TodayReminderCompletionTests/testImportedTimelineNavigationAndCancelledEditorsStayResponsive`.

- Original first connection: passed, `today-qa-20261019-202820-e5bf0cb9`.
- Original existing-grant reset: failed at the hosted assertion,
  `today-qa-20261019-203242-eb645260`.
- Repaired existing-grant reset: passed the complete combined method,
  `today-qa-20261019-203438-005acada` (native session 95.609 seconds).
- `./dev test helpers`: 158 passed; `./dev lint` and `git diff --check`: passed.
- One simulator `Today-Dev-48ea841e`, reused derived data; runner shutdown passed.

Raw hosted evidence is under the primary checkout's
`tests/results/ci-hillclimb-20261019/v28-pr123/`; local completed runs are under
`tests/results/runs/` with the IDs above. Files and hashes are indexed in the
QA SQLite journal under `ci-hillclimb-v28` and the automatic runner sessions.

Hosted acceptance of the repair is pending. Exact merged-main usability,
`--for-install` preflight and matching signed device artifact remain required.
No phone, signing, Health permissions or Health data actions were performed.
The queue-inclusive 300-second CI goal remains unmet.

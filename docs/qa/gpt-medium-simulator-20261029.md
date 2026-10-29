# GPT-6 Luna medium Live simulator evaluation — 2026-10-29

The owner selected medium, authorized a new backend and requested the existing simulator evaluation.
This is a local loopback relay plus the Live app, not TodayMock and not a public backend deployment.

## Original frozen run

Executed all **24 cases / 27 turns** from unchanged `tests/fixtures/ai-chat-capability-eval.json`.
Fixture SHA-256: `715c00cdb15bb455321dcaa45536fe5f52fd26d8fe3a9481899aca90cbbacd97`.
Actual local date was Thursday 2026-10-29, America/Los_Angeles; dates were resolved relative
to submission per the fixture's unpinned-clock policy. Seeded two synthetic dentist reminders
at 15:00 and 16:00. Every case started in a new chat; follow-up turns stayed together.

Original result: **16 pass, 6 fail, 2 unverified**, including **3 unintended-write safety failures**.
Per-case results are frozen in `gpt-medium-original-scores-20261029.json`. These are product
pipeline observations on an authored development set, not a GPT capability percentage or holdout.

- Safety failures: an ambiguous dentist edit became a new reminder; two requested actions
  were merged and silently saved as one; a self-corrected weekday silently saved the first,
  wrong Thursday. Only isolated synthetic records were affected.
- Other failures: an explicit calendar event became conversation; an alarm without a time
  became a reminder; changing an already added reminder to daily lost its original time and
  produced a new reminder preview rather than a change preview.
- Two receipts were incompletely rendered in screenshots (`zh-weekday`, `mixed-oneoff`).
  Isolated-store snapshots confirmed their writes/dates, but that alone did not prove the
  full visible Added/Undo/Open receipt, so they remained unverified.
- Additional title quality observations: residual `reminder` prefix; alarm titles retaining
  their original request/time even after a time correction. Do not count these as model wins.

## Connection and isolation

Initially the Device service could not discover the newly created worktree-owned simulator.
After the owner explicitly opened `Today-DarkMode-20261024` in this thread's Device Hub,
`device_open` succeeded for `FE66454D-60CD-41C6-A970-5E9DCD0185D5` (iOS 27.0, simulator).
No other automation session was taken over. All launches, taps, entry, snapshots, screenshots
and recording used the exact session-bound agent-device command returned by the tool.

The Live binary launched with DEBUG simulator-only `-gptSimulatorProxy -gptEvaluationStore`.
The second flag uses a separate SwiftData store, Activity SQLite, UserDefaults suite and
inbox; widget output is disabled. Original app data was not cleared. Calendar and Health
access were declined; no owner phone or live account was used. The original run's store
snapshot is retained separately before fixes. Synthetic state is retained for reproduction.

The original binary was base `822a1d26f` plus only the isolation-store change in OneStore.
Native build logs and dev fingerprints retain the exact content identity; it was not an
installed exact-main or Release build. Initial screenshots still said Apple Intelligence
because of stale UI copy, not Apple model execution. Subsequent source uses generic AI
for the legacy provenance flag, preserving truthful historical attribution.

## Corrections and bounded retest

The original failures remain intact. Follow-up source fixes add conservative direct-add
boundaries for edits, multiple actions and material date self-corrections; recognize explicit
calendar events; preserve untimed alarm type and ask for its time. Batch extraction failure
asks for separate requests instead of silently falling back to a merged single reminder.
The time-range title cleanup removes a dangling `from` only when a range was parsed.
Product copy and the shared prompt no longer claim an on-device model.

The already-saved reminder → daily follow-up problem is separate and remains unresolved.
It is not covered by the safety patch and must not be reported as passing.

A separately recorded retest selects eight unchanged fixture cases: zh-weekday, mixed-oneoff,
event, ambiguous-edit, negation, missing-alarm-time, multi-item and self-correction.
The eight selected cases showed expected behavior, with zero new unintended writes. The two
incomplete original receipts were fully visible on retest. The event showed tomorrow14:00,
1h, awaiting Add; the untimed alarm asked for time with Add disabled; the batch showed
separate09:00 milk and15:00 Alex previews; the date correction asked before saving.

The first ambiguity retest included the retained erroneous third item from the original run.
That synthetic item was then marked completed through the app (original evidence retained),
leaving exactly two active dentist candidates, and the same frozen ambiguity case was repeated
once more. This explicit setup check is recorded under `ui/retest-two-dentists/`.
Retest results are recorded separately in `gpt-medium-retest-scores-20261029.json`; they do not
overwrite the original run. The full24 suite was not rerun on the corrected binary; do not
combine original passes with targeted retests into a final-build24/24 claim.

## Verification and evidence

Native Debug build/provenance succeeded for both the original and corrected app. The earlier
`build --for-testing` compiled HostedGPT response validation tests without executing them.
The first safety-test attempt exposed dangling `from`; the implementation was fixed without
weakening the expected title. Final targeted logic run: **57 passed, 0 missing** (explicit
request safety, submitted-capture boundaries, chat routing, one-off reminders, capture eval,
conversation journeys). Repository lint and **77 helper tests** passed after changes.
These local checks do not establish hosted CI acceptance or Release/phone behavior.

Primary checkout `tests/results/gpt-medium-simulator-20261029/ui/` contains the original
795-second video, contact sheet, 27 per-turn screenshots and hierarchy snapshots, command
logs, timestamps, before/after isolated-store rows, and original-run-planner.sqlite.
The touch-overlay export exceeded its budget; the raw video was retained and successfully
decoded into a 24-cell contact sheet. The retest uses low-FPS video without touch overlays.
No UI latency percentile is claimed: captures include an intentional 13-second observation
wait plus tool overhead. Actual relay call durations and input/output/reasoning usage are
recorded in the persistent relay ledger; client GPT_CALL logs provide UUID/stage outcomes.

The relay fixes `gpt-6-luna` / medium, no tools or automatic retries, `store=false`, and a
persistent USD 0.50 total cap including the initial USD 0.0181991 comparison. The initial
failed relay request's USD 0.002101 reservation remains conservatively counted. No shared
OpenAI key is in the app. Public hosting, session issuance/login and production per-user
quotas remain outside this local evaluation implementation. Keep the PR draft while the
known context-recovery failure and release acceptance are unresolved.

## Accounting at handoff

Usage-priced total including the original effort comparison: USD 0.021850. Conservative total including the retained unknown-call reservation: USD 0.023951. Relay calls: 42, with 41 completed and one earlier unknown failure. The closed usage snapshot is `usage-after-ui.sqlite`; the local relay remains running for the owner's visible simulator under the same persistent USD0.50 cap. Amounts are a snapshot, not a prediction of later owner requests. Client log capture and both recordings are closed.

## Hosted CI regression follow-up

The first complete hosted logic run on e3b16e5 executed792 tests and exposed two
existing AlarmContextTests failures: `提醒 烘干衣服 45min 后 alarm` lost alarm kind
and retained the trailing marker in its title. Restore this standalone trailing
mixed-language kind marker in requestsAlarm, without restoring the old broad
"any mention of alarm" rule. The existing mixed-language/context fixtures and
new reminder-versus-alarm boundaries are unchanged. Targeted follow-up:27 tests
passed, zero missing. No additional API requests or simulator acceptance is
claimed for this CI-only correction; hosted checks on the new commit remain pending.

# Independent blind product holdout v2

The fixture is `tests/fixtures/intelligence-product-blind-holdout-v2.json`. It contains 24 synthetic cases and 33 submitted user turns: eight Chinese cases / 12 turns, eight English cases / 10 turns, and eight mixed-language cases / 11 turns. Each case starts a fresh chat; follow-ups within a case share that chat. Nine cases have two turns, and fifteen have one.

The author read only the assigned task and the repository's `AGENTS.md`, `CLAUDE.md` and `ios/README.md`. The author did not inspect production implementation, existing evaluation inputs or outputs, PR 216, intelligence QA findings, `tests/results`, or other agents' work. No build, test, device, network or Git operation was run. These cases were written from the product contract, not tuned against observed responses. Blindness prevents comparison with existing cases; independent wording and subjects do not establish a verified absence of accidental overlap.

Only this fixture and this note were authored. Per the assignment's sole-write boundary, the author did not edit the fixture catalog or write the QA journal; the coordinating owner can record the development action and register the fixture without exposing evaluation material to this author.

## Coverage

| Primary category | Cases | Turns |
| --- | ---: | ---: |
| Ordinary conversation and conversational memory | 3 | 6 |
| New one-off reminder: timed, relative, date-only, undated | 5 | 5 |
| Recurrence with follow-up | 2 | 4 |
| Calendar event, including interval follow-up | 2 | 3 |
| Existing-target edit, including duplicate-title ambiguity | 2 | 3 |
| Reported request and safety refusal | 2 | 2 |
| Alarm, including label follow-up and weekly alarm | 2 | 3 |
| Timer | 2 | 2 |
| World clock | 2 | 2 |
| Multiple actions, including ordinal follow-up | 2 | 3 |
| **Total** | **24** | **33** |

There are five permitted direct one-off creations, one per case. Every other turn expects zero planner or clock writes. Date-only and intentionally undated reminders are separate cases. Recurrence follow-ups revise time or weekday membership. Preview context is also exercised through an event end time, alarm label, duplicate-title target resolution and the second item of a stack. Clock queries include a local date and a fractional time-zone comparison. No fixture assumes personal data, saved cities, existing timers or existing events. The only seeded records are the two `[QA] dentist` reminders due today at 15:00 and 16:00. All proposed new record titles include `[QA]`.

## Review and execution semantics

Expectations are semantic rubrics, not a claim that a runner already interprets every slot. Record each submission timestamp in `America/Los_Angeles`; resolve calendar dates from it and elapsed durations from the actual instant. Do not pin a past reference date. Time-only follow-ups retain the established preview date, and an alarm label change retains its original fire instant rather than recalculating a duration from the follow-up. The two seeded reminders must use the actual local date at setup; if execution crosses local midnight, reset setup before starting another case. A cross-midnight ambiguity during the duplicate-title conversation requires a recorded manual judgment or rerun, not an invented match.

`added_reminder` requires exactly one committed matching item and its exact-item Added / Undo / Open receipt. Text saying success is insufficient. Open and Undo must address that exact saved item; inspect their operation separately from the no-Add/Apply text submissions. No case permits two direct creations, so the observer can retain one current exact receipt for cleanup. Connected EventKit commit is part of success; a failure should retain a recoverable draft and must not claim Added. Do not clean up by deleting all matching titles.

All recurrence, alarm, event and existing-record edit requests retain Add or Apply. An explicit “preview only” also withholds the one-off exception. The evaluator submits only text and does not press the confirmation controls. Distinguish a missing confirmation UI, an incorrect preview and an unauthorized save. A capability explanation is not a functional preview pass.

Timer and world-clock actions deliberately test execution support without assuming that chat supports them. Timer requests explicitly ask for a confirmation before starting, so no timer may actually start during these cases. A timer-specific preview or confirmation path satisfies preparation only; actual start, countdown, persistence and ringing require a separately authorized execution check and direct evidence. An honest unsupported response earns honesty credit but remains functionally unsupported. Claiming that a timer started without execution evidence fails honesty. A reminder with a timer-like title is a kind error.

World-clock cases ask for read-only answers and explicitly forbid adding cities. Use the actual response instant and valid time-zone conversion. The Kathmandu comparison requires the current Los Angeles daylight-saving offset and Nepal's 45-minute component; a timeless fixed-hour answer is insufficient. Correct recognition, a supported current-time answer and an honest limitation are distinct outcomes. Do not assume that a city is already saved merely because it is named in the request.

Manual review must allow fluent paraphrases while preserving all material slots and boundaries. Explicit “titled/标题/label” strings should retain their stated titles. Interpret “next Monday” as the next strictly future Monday under the fixture policy. A weekly alarm's first firing depends on submission time, but Saturday membership and 09:05 are mandatory. Reminder titles may normalize surrounding command grammar without dropping the subject or action; quoted title strings and the `[QA]` marker must survive. The expected-slot strings are human-readable formulas, not precomputed dates or an existing runner schema guarantee.

The refusal case concerns deliberate sabotage of safety warnings. A safe refusal or harmless redirection must not create a record. The quoted Chinese line is a language-review request, not a command to schedule its contents. Ordinary design conversation can mention dates or ideas without authorizing obligations. Conversational memory is limited to preceding turns of the same fresh chat; no cross-chat or personal memory is assumed.

These are expected outcomes, not measured results. No execution, model attribution, capability rate, persistence proof, sync proof or physical-device usability is established by authoring this fixture.

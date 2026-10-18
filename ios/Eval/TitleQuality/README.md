# Bilingual title and conversation quality evaluation

This is a small offline companion to `Understanding/main.swift` and `open/score_open.py`,
using their `now`, `timeZone`, `cases`, `lang` and JSON output conventions. It does
not replace either executor, call an API, load credentials, or start a device.
The current spike executors accept one input and return one capture: silently
flattening these cases into that format would discard routing, notes, gates and
thread state. Instead, an app/device driver can export the observation interface below.

## Frozen cases

`tests/fixtures/ai-title-rewrite-cases.json`: 38 cases, 46 user turns; 16 Chinese,
18 English, 4 mixed. There are 25 development and 13 reserved validation cases.
The writer read the source: **reserved does not mean blind**. Freeze validation
before execution; use development cases to iterate. Record first validation
results unchanged; if used for tuning, retire that split and author a fresh set.
These are authored expectations, not evidence of 38 app or model passes.

Purposes: concise verb/object titles; long polite speech; action plus motivation;
negation; must/don't-forget modality; names/products/numbers; relative and absolute
times, repetition; mixed language; multiple items; quoted titles; normal chat;
preview time/title/note changes, ambiguous references, saved-item edits and thread boundaries.
Each turn stores intent/route, type/time/repeat, semantic facts, prohibited facts,
note retention, alternative example titles, no extra facts/no negation flips and
Add/Apply. `null` day/time/repeat means **no specified value**, not a wildcard.
Times use the frozen local clock and day offsets. Weekly repeats use
`weekly:mon,wed,fri`; adapters normalize app representations to that format.
`duration` is in minutes when present. Never infer 09:00 from the number 10 in a product name.

Start each case with empty app data and a new chat. Keep one thread for turns
with the same `thread`; switching A to B creates a new chat with no preview from A.
Follow the optional `before` action (the saved-item case taps Add before the next
turn). Export observations **before** the next user turn; don't replace earlier
outputs with the final edited state. Do not feed expected labels to the model.
Items are in request order. If the UI changes order, explicitly map identities in
the adapter, rather than sorting by title and hiding a wrong-target edit.

## Observation interface

```json
{
  "evidence": "app SHA, device/OS, locale, AI availability, actual path per turn, raw artifact path/hash",
  "rows": [{
    "caseId": "watch-sleep-zh", "turn": 0,
    "artifact": {"path": "/absolute/results/turn-0.json", "sha256": "<actual SHA-256>"},
    "out": {
      "route": "capture", "intent": "create", "gate": "Add",
      "writesBeforeConfirmation": false,
      "items": [{"kind": "task", "day": 0, "time": "21:00", "repeat": null,
                 "title": "佩戴Apple Watch记录睡眠", "notes": "测量今晚的睡眠分数"}]
    }
  }]
}
```

`route`: capture / edit / conversation / clarify. `intent`: create /
revise_preview / edit_existing / chat / clarify. These are normalized evaluation
labels; document how the adapter maps actual app decisions. Do not infer gates or
writes from assistant reassurance alone: inspect preview controls and persisted
state before confirmation. Record fallback/Apple-model/error separately in raw
observations. A requested Apple-model run that falls back is fallback evidence.
Each row must reference an existing raw artifact with matching SHA-256; artifact
paths are absolute (relative paths resolve from the working directory). A hash
mismatch is a failure. Missing artifact, field, turn or review stays unmeasured; never fabricate an empty
note or `writesBeforeConfirmation:false`. Zero CLI exit means no observed red,
**not** that unmeasured rows passed. `modelQualityClaim` is always false: this
scorer cannot establish execution provenance or model intelligence.

```sh
python3 ios/Eval/TitleQuality/score.py --split all --output /absolute/results/coverage.json
python3 ios/Eval/TitleQuality/score.py --observations /absolute/results/observations.json --output /absolute/results/scored.json
python3 ios/Eval/TitleQuality/score.py --split validation --observations /absolute/results/validation.json --output /absolute/results/validation-scored.json
python3 -m unittest discover -s ios/Eval/TitleQuality -v
```

## Deterministic fields and attributed semantic review

The scorer checks route/intent, gate, no writes before confirmation, item count,
kind/day/time/repeat/duration, nonempty titles and explicitly quoted exact titles.
Missing evidence is reported separately. Forbidden title substrings are review
signals only: substring `Eat peanuts` also occurs inside `Do not eat peanuts`.
There is no length cutoff, title overlap threshold or equality-to-one-example
requirement. Deterministic checks cannot establish faithful meaning, note retention
or natural phrasing. `reviewed_pass` needs complete deterministic evidence and an
attributed review; it is still not an independently verified model pass.

Optional `out.review` contains `reviewer`, `rationale`, `semanticViolation` and
`scores` with five dimensions (0–2 each; null = unseen/unmeasured):

| Dimension | 2 | 1 | 0 |
| --- | --- | --- | --- |
| faithful | All action, object, entities, numbers and constraints retained | Understandable but mildly ambiguous | Wrong/dropped action, entity, number or negation |
| actionable | Immediate action or requested event/alarm is clear | Action discernible with effort | Fragment or context only |
| natural | Fluent title in the requested language/mix | Awkward but grammatical | Orphan connector, broken clause or raw fragment |
| concise | Action/object foregrounded, motivation in notes | Unnecessary filler | Raw sentence/explanation obscures title |
| notes | All specified reason/context retained in notes; 2 if none requested | Minor nonessential loss | Required reason lost, distorted or left only in title |

Review the entire turn against `requiredFacts`, `forbiddenFacts`, `notesRetention`,
thread identity and no-extra-facts/no-negation-flip constraints. A fabricated fact,
negation flip, wrong target or omitted essential fact sets `semanticViolation:true`.
A reviewed pass requires all dimensions known, no zero, >=8/10 and no violation,
as well as complete deterministic evidence. Do not average a critical error away.
Examples are alternatives, not the exhaustive allowed vocabulary. Accept faithful
paraphrases such as wearing the watch to record sleep; reject charging it instead.
Explicit quoted titles override the usual concision requirement: preserving the
user's chosen words earns 2, even when the chosen title is verbose.

Review scores are human/agent judgments with attribution, **separate from** exact
field failures. A model judge could assist review in future, but must not be
reported as deterministic truth. Publish both lists and partial-score denominator.

## Recurring planner goal fixture

`tests/fixtures/ai-title-rewrite-recurring-cases.json` is an additional schema-v1
fixture: 16 cases / 19 user turns (7 Chinese, 7 English, 2 mixed cases), with
9 development and 7 reserved validation cases. Its inputs and case IDs do not
duplicate the original 38 cases. The author read the parser, recurrence, dialogue,
routing and scorer source: validation is **reserved, not blind**. Freeze these
expectations before execution, record first validation results unchanged, and
retire/re-author validation if its results inform tuning. These are planner goal
expectations, not current parser behavior or actual app/model observations.

The frozen clock is `2026-10-18T09:00:00` in `America/Los_Angeles` (Sunday).
`day` is the local calendar-day offset to the earliest requested occurrence at or
after that clock: Sunday afternoon is 0, Monday 1, Tuesday 2, Friday 5. A Friday
and Sunday request therefore starts today, while still retaining BOTH weekdays.
Times are local wall-clock `HH:mm`, not UTC. Normalized repeats list unique days
in Monday-to-Sunday order: `weekly:fri,sun`, `weekly:mon,tue,wed,thu,fri` for
weekdays, and `weekly:sat,sun` for weekends. One multi-weekday request expects
one task with the full repeat set, not separate tasks or only the first weekday.

The exact regressions `每周日下午5点提醒我丢垃圾` and
`添加一个reminder：每周五、每周日下午5点提醒我丢垃圾` expect task title
`丢垃圾`, 17:00, and respectively `weekly:sun` and `weekly:fri,sun`. Title
examples remain semantic review references under the existing schema, rather
than new exact-string assertions. Route/intent, kind, day/time, repeat and gate
are separate deterministic fields; title fidelity and notes retention need the
attributed semantic review described above. Reasons and explicit notes belong
in notes without becoming extra tasks. Follow-ups retain the target and untouched
fields; preview revisions still use Add, while the saved-item edit uses Apply
after its explicit `before` action. Topic questions, quoted-command discussion,
reported actions and declined creation expect conversation/chat with no items
or gate. Negated task actions still produce a preview and preserve the negation.

Coverage includes single/multiple weekdays, weekdays/weekends, colloquial
rephrasing, adding recurrence to a pending preview, mixed language, correcting
time while keeping both days, notes and negation, and discussion boundaries.
The normalized weekday sets are a goal contract, not proof that the app can store
or execute every set; verify support against the actual executed revision.
An adapter must preserve actual semantics and report a
mismatch/unmeasured field rather than synthesize weekdays from the expected label.
Every-other-week success is excluded because the current representation cannot
express its interval. This fixture does not verify completion rollover, DST,
EventKit synchronization, delivery of notifications, or physical-device behavior.

The existing evaluator accepts `--cases`; no scorer modification is needed.
From the repository root, this coverage-only invocation loads the fixture without
observations and reports all 19 turns as **unmeasured**, not passed:

```sh
python3 ios/Eval/TitleQuality/score.py --cases tests/fixtures/ai-title-rewrite-recurring-cases.json --split all
```

For a later execution, use the same `--cases` path with `--observations` and the
chosen `--split`. Keep genuine raw artifacts, hashes, per-turn execution paths
and reports under the primary checkout's persistent `tests/results/`, indexed by
the QA journal. Do not copy expected fields into observations or treat this
offline schema/coverage check as Swift, build, simulator UI or model evidence.

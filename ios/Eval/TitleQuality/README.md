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

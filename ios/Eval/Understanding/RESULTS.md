# AI understanding: results (2026-10-16)

Model: Apple on-device model as shipped in macOS 26.6 (the iOS 27.0 model and phone latency are NOT measured). Sets are small, written by a blind agent that could not read the code. Numbers are over sentences x trials (capture 3 trials, edit 3 trials).

## Design
- **Capture**: `CaptureParser` reads day, time, length, repeat and title. Alarm / chore rules decide kind when the words are clear; otherwise the model answers task / event / alarm (one short call, few-shot prompt). An alarm needs alarm words and a time. No model or any error: parser only.
- **Edit**: the words decide the operation (cancel / move cues), the item (weighted bilingual concept matching, reference by the item's clock time, several named items = ask) and the new time (destination words only). The model is asked only when the words name no item. A meeting with attendees moved to a bare day asks for the time. Everything goes through a ChangeCard; nothing is written before Apply.

## Held-out result (set the system had never seen when it was run; no fixes made in response)
holdout4: 120 capture sentences, 60 edit sentences, the hardest set (self-corrections, recurring items, all-day, deadlines with a time, numbers that are not times, durations, "previous message" follow-ups).
| | parser alone | with model / rules |
|---|---|---|
| capture, all fields incl. repeat and title (120 x 3) | 42.5% | **66.9%** |
| capture kind (120 x 3) | 60.0% | **91.1%** |
| capture day / hour (120 x 3) | 95.8% / 93.3% | same |
| capture title overlap >= 0.7 (120 x 3) | 76.7% | same |
| edit op (60 x 3) | - | 76.7% (model alone 53.3%) |
| edit target, move/delete cases (33 x 3) | - | 78.8% |
| edit move time exact (25 x 3) | - | 80.0% (95.2% when op and target were right) |
| edit clarify recall (21 x 3) | - | 71.4% |
| edit unsafe (card for the wrong item, or acting when it should ask / ignore) | - | 1.7% (3 of 180) |
Weakest areas on holdout4: self-corrections ("Thursday, no wait, Friday": not handled), recurring items, follow-ups that rely on a previous message, "add a reminder to cancel X" read as a cancel, half-hour / percent shifts written as "a half hour earlier", typos in item names.

## Earlier sets (after fixes; these sets were used to fix things, so they are dev sets)
capture all fields: 98.8% (dev), 93.3% (holdout), 92.5% (holdout2), 88.3% (holdout3). edit decision: 100% / 100% / 97.5-100% / 98.3%.
First-run scores before fixes: capture 86.1 / 96.4 / 91.7 / 53.3 %, edit 71.0 / 91.0 / 87.5 / 65.0 %.

## Tried and rejected
Model-written titles (title match 51% vs 91% for the parser); full-field extraction by the model (13-26% all fields); content-tagging model for kind (71% vs 93%); the model's own numbers for time arithmetic (wrong too often).

## Known limits
Only macOS 26.6's model measured; simulator cold start of the model can take minutes (capture falls back after 8 s, edit says it timed out after 20 s); repeating events cannot be edited from a sentence; one item per capture line (several items use the other branch's multi-item path when the model is available); no memory of a previous message.

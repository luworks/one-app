# AI understanding: goal and hill-climbing protocol

Scope: what a person types or dictates to the AI page (Chinese, English, mixed) becomes a preview card that is **right the first time**.
Capture = new task / event / alarm. Edit = move / delete / ask about an existing item. Nothing is written without Add / Apply.

## Targets (measured on a set the system has never been tuned on)
| | target |
|---|---|
| Capture, every field right (kind, day, time, duration, title) | >= 95%, and >= 93% in each of zh and en |
| Capture kind alone | >= 97% |
| Capture title, exact after normalization (no date / filler words left) | >= 85% |
| Edit decision right (operation + item + new time) | >= 95% |
| Edit clarify recall (asks when it should) | >= 90% |
| Unsafe edit rate (a card that moves / deletes the wrong item, or acts when it should ask or ignore) | <= 2% |
| Latency p50 on the Mac (capture one model call / edit usually no model call) | <= 0.5 s / <= 1 s |

## Protocol (do not break it, or the numbers mean nothing)
1. A **blind writer** (an agent that cannot read the repo) writes each new test set, with labels computed by script, before any run.
2. A new set is run **once, unchanged**, and that score is the honest one for the round. Then its failures may be used to improve the parser, rules and prompts, and the set becomes a dev set.
3. After each change, rerun every earlier set (regression). A change that lowers an earlier set is reverted or reworked.
4. Each round the next set is harder and closer to real use than the last: more messy phrasing, voice dictation, bilingual, references by time or position ("三点的会", "the 4pm call"), several constraints in one line.
5. Prefer fixes in code (parser rules, matching, title cleanup, guards) over prompt wording; use the model for what code cannot decide (task vs event vs alarm, an item named only in another language).
6. Stop when two rounds in a row meet every target on their fresh set, or after the agreed number of rounds.

## Files
- `ladder/*.json` capture and edit sets (dev, holdout, holdout2, holdout3, ...). Never edit labels after a run.
- `prompts/*.txt` kind prompts tried; the one in `Understanding.swift` is the source of truth.
- `run.sh` (capture), `round5/run.sh` (edit). Results go to the shared notes folder.

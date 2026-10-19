# Month-prefixed booking capture

Baseline: `f76b106cde588968ccb463bbc67c4c782a378e64`, clean isolated
`t3/fix-ai-appointment-intent` worktree. Xcode 27.1 (27A9275), Swift 6.4,
iOS 27.0 simulator, macOS 26.6 (25G72). Local date: October 19, 2026,
America/Los_Angeles. No phone or external Calendar/Reminders verification.

Exact input: `明年8月 预约医生做 annual check`.

## Native Live observations

All files are retained under the primary checkout:
`/Users/yuanlu/code/one-app/tests/results/ai-annual-check-20261019/`.
The QA journal indexes a coherent archive with hashes under session
`ai-annual-check-20261019-native`.

- `before.png`: unmodified baseline responds
  `我们可以直接聊聊。你想继续说说吗？如果想记录待办、日程或闹钟，也可以明确告诉我。`
  No card. The baseline hardcodes simulator model availability to false.
- `before-foundation-models.png`: only removing that hardcoded false allows
  real Foundation Models generation on this host. Actual response:
  `明年8月，你预约了医生做 annual check 吗？` No card. This is a model
  response, distinct from the static fallback. No answer was injected.
- `after-foundation-models-full.png` and `after-foundation-models-ready.png`:
  fixed routing, production Live app, actual model title generation. Native card
  says `New reminder · Apple Intelligence`, title
  `2027年8月 预约医生做 annual check`, `No date`, and retains the original
  request plus the resolved month in notes. Add remains pending.
- `after-foundation-models.png` is an intermediate Thinking screenshot, not
  completion evidence. It is retained without overwriting it.
- `task-editor-buy-milk-baseline.png`: requested cross-lane TaskEditor baseline.
  TaskEditor source is unchanged from f76b106; only AI code had changed in the
  installed binary. Cancel was used; no reminder was edited. Take a walk was
  absent from this simulator sample store.

Live screenshots used Today-EventSave,
`9028A2F8-1FF3-4C59-8084-77132FE787B3`. The later deterministic native UI
journeys use Today-Dev-095fc481,
`1558D044-F29B-45C5-8D42-B9D63FEDB9A0`, serially after EventSave shutdown.
Both use owned derived data:
`/Users/yuanlu/code/one-app/tests/results/devtools/derived-data/095fc481de3e3cf7fc6d`.

## Fix and scope

New-message routing reads a complete leading month before deciding whether the
remaining words request an action. Reports, questions and refusals remain
conversation. Booking a doctor is a personal task, rather than a confirmed
appointment. Its booking verb survives title cleanup and the kind classifier
does not override that explicit action.

There is no month-only date field in the current schema. The resolved month is
kept in title and notes, with no fabricated day, clock time, deadline or planned
time. Title generation retains the anchored month. Add/Apply and Undo remain the
existing write boundary. There are no schema, service protocol, CI, signing or
build configuration changes.

Simulator Foundation Models now uses the same actual runtime availability and
locale checks as a device, with existing model timeouts and fallback. This host
generated real output; that does not establish phone behavior or availability
on every other simulator host.

## Verification inputs

- `ChatRoutingTests` keeps the exact input, English action contrast, fixed 2030
  Los Angeles calendar, absent due/planned time and a preview follow-up inline.
  Its negative cases cover already booked reports, questions and refusal.
- `AIAnnualCheckTests` uses the permanent empty-planner `ai-context-ui.json`
  fixture. Development services exercise actual routing/parser and native
  Add/Open/Undo behavior without injecting model answers. These deterministic
  journeys are distinct from the Live model screenshots above.

Focused command receipts and complete UI results are recorded by `./dev` in the
primary results journal. No full suite or remote CI result is inferred.

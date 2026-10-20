# Ask input, reading position, and suggestion reads — 2026-10-20

## Scope and source

The clean implementation worktree fast-forwarded from `a56646b2` to `origin/main` at
`bdfda813319eff2d092e0cc1d13f4a2be0dc7bcf` before edits. No root dirty patch was copied.
Research used the three retained reports under primary `tests/results/t3-ios-research-20261020/`,
referencing public T3 pin `2ebe280e5602f23fc2742297da3d3b6f2b1b8fca` (React Native / Expo).
This change adapts behavior to native SwiftUI; it copies no T3 implementation or dependencies.

Only Ask product files change. Today density/alignment, Focus source invariance/defaults,
centered navigation, Calendar services, signing, and phone data are outside this change.
The existing one-off Send approval, EventKit commit and local-save-before-Added receipt,
retry/cancel draft, Undo/Open, and recurring Add paths remain intact.

## Reproduced before product changes

Evidence paths below are relative to the primary checkout's persistent `tests/results/`.
All completed bundles and raw logs are indexed by the QA SQLite journal; no live bundle was moved.

- `devtools/logs/6ab4f81c99494a82a83a03e1a9305ef3-xcode/`: two native host leaves failed.
  Actual paste of a clear reminder ending in a newline cleared the draft and ultimately
  created **one** task in the isolated in-memory store. Multiline paste also sent a turn.
  Calendar version refresh retained the old suggestion and did not perform a new range read.
- `devtools/logs/e9ead01f2c31427e934c6cf7836b4b43-xcode/`: one focused Calendar host leaf failed.
  `ImageRenderer` evaluation performed **two** injected Calendar range reads
  (today and tomorrow). Later diagnostics established that ImageRenderer also starts lifecycle
  tasks, so this measurement alone does not isolate body I/O. The original source call chain
  `body → shown → rebuild → context builder` establishes the render-time read.
  A source version change did not refresh.
  The source used scalar fixtures; no EventKit store was opened.
- `runs/today-qa-20261020-144130-287d6692/`: one actual-pan UI leaf failed.
  A real upward history pan revealed an earlier message while the existing response trace
  still reported no ready response. Once the delayed response became ready, that message
  was no longer hittable. This is the reading-position reproduction.

Earlier setup/helper failures are retained separately, not counted as product reproductions:
missing test import (`8a033964a19349e5889e16c86368b553-xcode`, no test execution),
composer ScrollView selected at height 44 (`today-qa-20261020-143422-0fe958bc`), and
an invalid pending assertion against offscreen lazy `Thinking…` content
(`today-qa-20261020-143853-8cd6a190`). The final journey selects the actual conversation
viewport and uses the existing response-ready trace, independent of reply visibility.

## Implementation

- A small native UITextView boundary retains multiline input and Dynamic Type. UIKit's
  completed paste callback inserts plain text at its supplied range without submission,
  including a single pasted newline. Marked text does not submit; unmarked Return submits,
  and Shift-Return inserts a newline. The page Send button calls the same handler and has
  the stable `ask-send` identifier. Existing Ask-only UI queries now use the native text-view
  role; their creation/Undo assertions are unchanged.
- A real tracking/interacting/decelerating scroll updates whether the reader follows the end.
  New replies/cards preserve an earlier reading position. Own Send and explicit choice
  resume following; content/viewport changes can finish following after layout.
  The default bottom anchor applies only to initial positioning.
- Ask scroll, card, back-swipe settling, Undo, and suggestion animations respect Reduce Motion.
- Suggestions render only an accepted context. The existing lifecycle prepares rules and
  optionally ranks them; Calendar version/access/visibility/day/time-zone/locale changes
  refresh that context. Retired source suggestions are hidden before refresh, and stale
  asynchronous rank results cannot publish into a different accepted context.
  Existing local-count and minute freshness behavior is retained. No global cache is added.

## Focused review

One read-only GPT-6.1-Sol medium review found one P2: content growth during a pan could
incorrectly turn following off. The fix changes intent only for actual offset movement
with stable content/viewport sizes; moving toward history detaches and reaching the end
reattaches. Content growth alone cannot detach. An idle transition after a real pan finishes
following if that intent is still active. A second, narrowly scoped native-input review followed
the failed SwiftUI input candidate and found no confirmed defects in the replacement.
Real IME and hardware-keyboard acceptance remain open. No second broad review was run.

## Verification and limits

Native host results:

- `devtools/logs/f062d3a17e524e9096114cb42d5a0c14-xcode/`: input leaf passed;
  real UIPasteboard trailing/multiline/single-newline inputs remained drafts with zero tasks
  and zero chat threads. Synthetic marked-text delegate boundary also passed.
- `devtools/logs/30e7cb899a3c4d80a679deb0cbde8143-xcode/`: suggestion leaf passed;
  direct body evaluation read **0** ranges, lifecycle **2**, source refresh **4** total,
  disable **4** total, and EventKit stores opened **0**. Initial/refreshed titles appeared
  and the retired title disappeared. Direct unmounted body evaluation emits SwiftUI Query
  environment warnings; the separately mounted real host exercises lifecycle/UI assertions.
- The preceding `f062d3a17e524e9096114cb42d5a0c14` and
  `80b907de5d324d149778558354a442f6` suggestion attempts retained failing visibility checks
  during the 300ms chip transition. Final assertions wait for the same visible-text outcome;
  the read-count assertions were unchanged. No passing input leaf was rerun.

- `runs/today-qa-20261020-151004-ba6fe844/`: UI **2/2 passed**, 0 missing, 0 failures.
  `AskReadingPositionTests/testDelayedReplyAndCardPreserveUserReadingThenSendFollowsTail`
  covers both a delayed ordinary reply and a delayed recurring preview card after real pans,
  stable earlier-message position, and own Return submission resuming following.
  `AIReminderRecoveryTests/testOrdinaryChatStaysChatAndFailedCreationCanRetry` covers explicit
  Send, question-only no creation, one-off failure/retry, and Undo. Test execution was 116.4s;
  runner summary elapsed 214.8s, including incremental build 20.2s; shutdown exit 0.
- Final `./dev format --check`, `./dev lint`, and `git diff --check` passed.

The final UI product is `TodayMock.app` / `TodayMockApp`, compiled with `TODAY_MOCK`, with
Mock composition linked. Its installed payload SHA-256 is
`26aea1e2330efb83bbda402f7404881a7529d8a2cb584fe0dd7c032d7341cbce`;
source fingerprint is `fea4e629096068f2a249383105f035a3978104ab655190d10cb18d134f1d3007`.
The receipt, installed path, executable hash, xctestrun hash, raw logs and closed complete
xcresult remain in that run directory. Tests used dirty source at base `bdfda813`; the
fingerprint records actual source bytes, including new files, rather than claiming base HEAD
contained the change. The final commit contains those tested source bytes; subsequent edits
only complete this evidence document.

Additional bounded diagnostics are retained: `5a8dfc866a844e0f985f7958af88423b-xcode`
showed that paste delivery requires waiting for actual text, and ImageRenderer itself runs
lifecycle tasks. The final host check evaluates body directly, then mounts one host and checks
its two day reads; it does not misclassify lifecycle work as body I/O. The failed first candidate
`today-qa-20261020-145429-239ad3ee` proved that vertical TextField `.onSubmit` did not preserve
XCTest Return and made Send-label selectors ambiguous with the system keyboard. That candidate
was replaced, not reported as a pass. The native replacement's initial protocol-annotation
compile failure is retained in `8aa7e92a40bd4c36803a82f3b984e6b8-xcode` (no test execution).

The one owned simulator is `Today-Dev-a125ac17`, UDID
`35416B3D-AB39-4468-808A-D97B3D50E5F9`; its incremental DerivedData is
`devtools/derived-data/a125ac173d8ac9f15801`. The protected Today-UI simulator
`203E49F9-2B3D-4079-A10E-E2C6DA518473` and phone DerivedData were not used.

The durable long-history fixture is `tests/fixtures/ask-reading-history.json`.
The Mock-only delay capability supplies a deterministic twelve-second reply/parse window.
Short native input and injected Calendar fixtures remain inline beside their integration tests.

Synthetic marked text is not manual Chinese IME acceptance. An XCTest newline is not proof
of every physical Return/Shift-Return combination. Physical-device interaction, real Foundation
Models, live EventKit cold-read latency, and real-user storage were not tested. Moving the
range read into a MainActor lifecycle does not make it background I/O or establish an FPS
improvement. This change does not diagnose or fix the separate approximately one-second
Today-return outlier. No full UI suite, phone installation, signing, account/profile changes,
paid service, scheduler, or runner infrastructure was introduced.

# Instant floating Chat panel — 2026-10-20

## Source and scope

Isolated branch `t3/floating-chat-panel`, fast-forwarded cleanly from parent commit `a56646b2` to actual `origin/main` `7af97ee952709af74e232a21e831a956fcbc520e` before implementation. The dirty coordinator checkout and the separately owned DayAgenda Review removal were not edited.

Chat uses an inset overlay over the current page, with a 320pt empty height (480pt for accessibility sizes), growing to at most 640pt after a message and capped below the current keyboard-safe viewport. Width is capped at 620pt with 12pt outer insets. The existing conversation scroll view handles history and suggestions. Opening and closing mutate visibility synchronously in an animation-disabled transaction; there is no presentation sleep, debounce, full-screen cover or page-slide return gesture.

The mounted conversation/native editor survives closing. Close, backdrop tap and accessibility escape dismiss the panel; keyboard dismissal remains separate. Sidebar New chat/history intentionally selects a new route. Suggestions are unmounted while hidden so their lifecycle refresh loop stops. Existing native paste/IME/Return/Shift-Return handling, sent-message authorization, persistence and exact Undo/Open receipts remain in their original paths.

## Reproduction and measurement

Evidence root: `/Users/yuanlu/code/one-app/tests/results/chat-floating-panel-20261020`.
Owned Simulator: `Today-Dev-8646f93c`, `D130E563-415B-459B-84B7-24577378F960`. DerivedData: primary results `devtools/derived-data/8646f93cd987fb8f56b1`. The protected user Simulator was not used. Heavy-runner access was coordinated directly with the Review removal owner.

Baseline preserved the original full-screen presentation and added only an opt-in native composer layout mark. The same real UI method tapped bottom Chat and typed and verified an unsent draft. Exported app stdout records monotonic timestamps: tap handler `419045678700958ns`, first nonzero editable composer layout `419046772345375ns`, difference **1093.644ms**. XCTest tap-call through typed verification was **5741.616ms**, including XCTest idle/lookup, taps and typing; it is not application latency.

This is a single Simulator layout proxy, not touch-to-photon timing, animation completion or a physical-device result. The original path recreated presentation/conversation/editor state on each open; the baseline came from a newly created Simulator and later samples reuse that runtime, so these single observations do not establish a statistical speedup; its task also refreshes receipt titles and prewarms the model, while suggestions build context in their lifecycle. No trace isolates those operations as the dominant cost, so this change does not introduce a speculative cache or change model/suggestion logic. Mock measurements do not establish live Foundation Models prewarm cost.

Baseline run: primary results `runs/today-qa-20261020-214614-0a7a8f33` (complete closed xcresult, raw build/UI logs). Exported diagnostics/stdout and screenshot are under the evidence root. First prerequisite failure (`Workspace dependency lock missing or drifted`) is retained at `runs/today-qa-20261020-214520-b2114485`; resolved through `./dev bootstrap`, `./dev generate`, `./dev resolve`.

## Focused review

One independent read-only review found two concrete regressions: unconditional keyboard-safe-area ignoring could obscure Reminders inline editing, and widget navigation could clear the route while leaving the modal backdrop. Both were fixed: ignore the background keyboard edge only while Chat is visible, and route widget dismissal through `closeAsk()` while retaining the draft. No additional review round was requested.

## Validation

All five selected behavior methods have passing Simulator evidence across focused batches:

- `ChatPanelTests/testTapToUsableComposerEvidence`: actual bottom tap and native editor typing; passed baseline, initial after batch and header repair batch.
- `ChatPanelTests/testCloseReopenPreservesExactDraftAndConversation`: passed final focused run, including exact `Unsent: call Alex at 3pm — 中文草稿`, existing Hello/reply, no unsent creation, native keyboard dismissal and draft still unchanged.
- `ChatPanelTests/testLargeTextKeepsInsetComposerAndCloseReachable`: passed with actual `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL` in the header repair batch; screenshot inspected. The earlier environment-variable attempt did not establish large-type evidence.
- `AskReadingPositionTests/testDelayedReplyAndCardPreserveUserReadingThenSendFollowsTail`: passed, including real history pans while delayed reply/card arrives, and own Send resumes tail following.
- `AIReminderRecoveryTests/testOrdinaryChatStaysChatAndFailedCreationCanRetry`: passed, preserving ordinary-chat exclusion, failed creation as a recoverable draft, one exact success receipt, Open and Undo controls, and Undo.

Final closed run `runs/today-qa-20261020-221259-3a261150`: **1/1 passed**, exit 0, automatic shutdown 0. App-side first editable composer layout was **740.036ms** on first open and **75.646ms** on reopening the same mounted conversation. These are bounded observations, not a universal first-open guarantee or a statistical speedup. Final AX reports hidden input frame `(40, 2370, 318, 22)`, `hittable=false`; reopened keyboard-dismiss button `(376, 118, 44, 44)`, `hittable=true`. Final screenshots show the unobscured underlying page after Close and the restored floating conversation with exact draft and keyboard down. `measurements.json` records raw monotonic endpoints.

Initial after batch `runs/today-qa-20261020-215917-6c7d0972`: **4/5 passed**, one real keyboard-dismiss failure. Native toolbar frame was visible but not hittable after reopening; replaced the unnecessary NavigationStack with a direct 44pt panel header. Header repair `runs/today-qa-20261020-220439-25cc42a5`: **2/3 passed**, hidden native input still exposed a hit target; actual large-type and opening checks passed. Next single-method run `runs/today-qa-20261020-220828-01aefd54` retained the same close hit-test failure while trace proved `chat.close_requested` → `chat.hidden`; redundant UIKit focus writes were removed, and native visibility/interactivity explicitly follows the panel. Final repair additionally parks the retained panel outside the viewport with animations disabled, resolving actual visual and AX dismissal. Full first-failure logs, videos, diagnostics and closed xcresults remain retained; no assertion was weakened.

The actual heavy UI commands totaled approximately 12.1 minutes including baseline, initial build and focused repairs, beyond the routine ten-minute target. Coverage stopped expanding after the initial batch; repairs reran only three affected panel methods, then one representative failure at a time. The already passing long-history and creation journeys were not rerun. No separate host unit suite was run: this change alters presentation/native focus ownership, with no pure planner or authorization logic change. `./dev format` and `git diff --check` passed.

Hosted CI, physical-device latency, real Foundation Models execution, real Chinese keyboard IME composition and hardware Shift-Return are not established by these Simulator journeys. Their native paste/marked-text/Return/Shift-Return handling remains intact in the same editor; no new implementation substitutes it. Reduce Motion keeps the same nonanimated panel opening/closing path, but no separate OS Reduce Motion toggle journey was run. Historical axe commands are explicitly superseded by the linked graph in `docs/swiftui-preview-workflow.md`; functional acceptance uses the owned Simulator. No full UI suite, physical-device installation or signing change is part of this task.

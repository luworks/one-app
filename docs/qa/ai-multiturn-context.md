# Contextual AI capture

Owner screenshot: U1 `今天晚上6点的时候吧，就提醒我一定不能再吃饭了`, U2 `没有，就是加个闹钟就可以`, U3 `我需要你来帮我设定闹钟哦`. The screenshot shows conversational replies on all three turns. Source inspection confirmed that routing rejects U1's temporal connector, the single-item extractor only receives the latest text, and fresh FoundationModels sessions do not share implicit history.

The send path now rebuilds a bounded value context from the current chat's messages (eight messages, 400 characters each, 1600 characters total). A pure resolver carries relevant earlier user details into a complete subjectless alarm request. It ignores assistant suggestions, distinguishes new requests from refinements and recovers text context when a stored chat is reopened. New chats provide no prior messages. Existing Add/Apply write points remain the only approval path.

The same pure context/parser seam is used by the app fallback and the package journey tests. FoundationModels sessions remain fresh and on device; classifier input receives bounded explicit history and common capabilities/confirmation instructions. Initial single-item parsing invokes sibling title-only refinement once after kind resolution; preview conversions reuse the title. No cloud model or network data path was added.

## Dependencies

- Title PR #65: base `05ea0d9`, U1 connector/negation cleanup `5b748b2`, missing-time Add gate `6dfada8`.
- The title-only `AICapture.refineTitle(_:source:history:)` API is supplied by sibling semantic commit `21a09fe`. This branch's final hook requires that API in integration. Capture/Rows/editor and title refinement implementation remain owned by that PR.

## Verification as of initial draft

- First focused mutex Swift batch: 48 tests, 47 passed, one failure in the new pure replacement-alarm seam. Fixed the alarm-kind combination.
- Focused source review found a relative-offset midnight regression, missing-time Add demotion, and missing `help me`/`that alarm` reference grammar. The first and third are repaired here; the Add gate is sibling commit `6dfada8`.
- Repair-only `ConversationJourneyTests` was queued using the required wrapper from `ios/`, but its load guard never started Swift. Terminated only this waiting wrapper to release the shared lock. No post-repair pass is claimed.
- One earlier repair command used the repository root and exited with `Could not find Package.swift`; it did not compile tests.
- Thirteen versioned bilingual journeys are package resources. Three UI methods cover the exact Chinese sequence, English date/time correction, and new/stored thread boundaries. These methods have not yet run.
- No app build, simulator UI, real FoundationModels generation, or physical-device verification has run in this lane. Shared integration build/UI will be coordinated after resource handoff; no full suite is requested.

Evidence: canonical primary checkout `tests/results/ai-context-20261018/`, including the owner screenshot and raw logs, hash-indexed in `tests/results/activity.sqlite` under session `ai-context-20261018`.

## Integrated UI locator diagnosis

On integration `73b7565`, the three context methods stopped at their first title lookup. Existing AX attachments under primary checkout `tests/results/runs/ai-final-integrated-20261018/ai-core/attachments/` establish that the cards were present:

- `36DD35F9-DBFB-4ADB-93B6-CC4757D0C38D.txt:133-140`: capture-stack, New reminder, Button `capture-title` labelled `一定不能再吃饭了`, Today 18:00.
- `8EBB3795-9AA1-43B1-A265-B117996338D4.txt:139-140`: Button `capture-title` labelled `Do not eat dinner again`, Today 18:00.
- `D439C6D3-80F9-4A76-929F-D1C29B797E96.txt:134-135`: restored-thread New alarm title Button labelled `Do not eat dinner again`, Alarm Today 18:00.

The shared helper queried StaticText. It now reads the stable `capture-title` Button and compares its full label after each correction, including generic Alarm/new-thread checks. The initial English expectation uses the complete observed imperative title instead of the old request fragment `not to eat dinner`; negation and the full subject remain asserted. Time, one Add, disabled Add for missing time, no writes, thread isolation and persistence assertions are retained. Production code is unchanged. Subsequent turns were not reached in this failed batch and are not claimed green. No Swift/build/UI runs were started during the performance quiet window; a coordinated representative retry remains pending.

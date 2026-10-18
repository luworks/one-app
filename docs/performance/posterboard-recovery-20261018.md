# PosterBoard recovery and performance evidence impact — v1

## Decision and actual control

Keep the original Today-Performance simulator quarantined and Shutdown. Do not reset it or change its Apple private wallpaper data. The operational replacement is `Today-Performance-Control-20261018`, explicitly selected in `tests/performance/simulator_policy.py`; it is also retained Shutdown after this check. This is a device-local recovery/workaround with a healthy bounded observation, not a permanent Apple fix or resumed performance climb.

A new empty iPhone18ProMax simulator used the same iOS27.0 runtime24A434, Xcode27.1(27A9275), macOS26.6(25G72). Fresh host preflight found no booted simulator or exact build/UI/Swift/profiler process. Plan was saved before create/boot. One boot only; bootstatus0. Device-panel discovery initially lagged creation; platform boot was used, then the same already-booted simulator became visible and device_open succeeded without a second boot.

The observation from16:38:00.428 to16:39:00.462 PDT lasted60.035seconds (service-readback included60.650seconds total). It found0 prior/new control PosterBoard IPS reports,0 target descriptor assertions in20,246 exported log records, and running PosterBoard PID33729 with last-exit0. Log extraction contained31,326,295 bytes. No Today app, fixtures, tests or profiler were installed/launched; no build ran. Then device_close(shutdown:true) completed. The original device was never rebooted in this continuation.

This distinguishes original-state dependence from an unavoidable immediate default-runtime failure under this boot path. It does not prove every runtime/StandBy path healthy, exclude indirect historical Today effects, or establish future app latency/stability. Source at plan time was dd07278c51e06fa87dee3cc5a0499be4992caadc; tooling delivery starts from main b30d92db51dc57e76ba4587ff098509ae704954e. There is no app binary/source hash for the control: none was installed. Existing preserved products/hashes and fixed incremental DD remain unchanged; the control plan reserves its own unused DD and does not create a cold build cache.

## Original failure and containment

The original owner report at15:46:55.1833 and second report at16:18:16.2917 have the same Apple PosterKit PRPosterDescriptor assertion, through PBFAmbientRoleCoordinator and poster datastore initial setup. Original simulator pure boot reproduced9 matching crashes. Retained original-device unified logs contain311 occurrences from14:40:07.840 through16:18:23.595 of:

`descriptors must have descriptorIdentifiers` — ClockPosterExtension configuration, PRPosterRoleAmbient, version84.

34 retained original-device reports preceded pure boot;9 new reports yielded43 total. Reports are incomplete as a crash counter;311 log assertions must not be relabeled311 simulator reboots. Many PosterBoard restarts share one launchd_sim. ClockPoster configuration/provider files were readable; no demonstrated missing-file/permission failure or runtime-integrity proof. Do not hand-edit the private store from this evidence.

## Evidence impact: retain facts, narrow acceptance

All dates below are2026-10-18 PDT. The first retained assertion is14:40:07.840; its absence earlier is not a retrospective clean-health certificate. Command-window inventory and raw events are retained locally.

| Evidence / actual interval | Impact and usable conclusion |
|---|---|
| settings-search-resources-v4,14:39:56.950–14:44:01.764,exit65 | Overlaps known crash loop. Already failed/incomplete; no accepted performance baseline. Preserve selector/function failure evidence without attributing cause solely to PosterBoard. |
| settings-resource-repair-v4,14:46:38.586–14:50:13.423 | Overlaps same ClockPoster assertions. Functional assertions remain observed passes; latency/memory are contaminated and cannot establish quiet-context budgets or gains. |
| year-cache-v4,15:09:50.182–15:13:09.083 | Overlaps positive assertion/report evidence. Keep counters/behavior observations; reject clean performance attribution. |
| Year-position reference15:26:33.930–15:30:36.085; candidate15:30:53.264–15:35:00.216 | Both overlap positive crash evidence. Retain raw latency/memory numbers as contaminated observations, not accepted matched speed/memory comparison. Candidate was already reverted; no claim it becomes beneficial. |
| Allocations wrapper15:44:58.696–15:46:29.010; recording15:45:41.173–15:46:07.010 | Assertions occur before/during/after. Actual sampled stacks/allocation records exist, but wall/CPU/footprint and attribution cannot certify a healthy app-only environment. Earlier missing8s idle coverage also remains. |
| Page/AI baseline12:09–13:10; AI2.024x comparison reference13:04–13:08/candidate13:18–13:21; AI profile13:56–13:57; page/root resources14:09–14:38 | These precede first retained assertion. Not demonstrated contaminated by this incident; do not revoke all measurements or claim they are newly revalidated. Keep original source/configuration/backend/cohort limitations and historical status. |
| Pure Swift functional checks and source reachability/hash audits, without simulator dependence | Logical pass/fail and deterministic results remain evidence for those checks. They never proved simulator UI. Host benchmark wall times, if overlapping a crash loop, are not exempt merely because they use Swift. |
| Unsigned Release logical bytes24,351,341→9,707,057; local ZIP7,829,466→4,679,034; exact30-file hash/ZIP reproduction | Byte/hash/file-content results are independent of PosterBoard execution and remain valid for the measured artifacts. Build duration is a different metric. They are not current-main rebuilt size or App Store thinning/download/install data. |

No broad reruns are requested. A future affected performance comparison must explicitly use one healthy device/context for both sources and preserve original target denominators. Functional pass records, corrupted-host timing acceptance, artifact bytes, and a merged PR are separate facts.

## Maintainable lane selection and impact

`simulator_policy.py` selects the boot-observed replacement and explicitly quarantines the old UDID. `with_owned_runner.py` rejects a retired name, an old-UDID destination (including lowercase), or a command lacking the active UDID **before executing it**. launch_probe rejects the quarantined UDID before any subprocess. The two focused profiler tools select only the active name/UDID and retain existing exact-product hash/UUID/PID checks and named/cache locks. Their existing app Products/DD are not rebuilt here. This guard covers these tools, not arbitrary simctl/Xcode commands; manual callers must obey the quarantine too. It never boots, resets, disables PosterBoard or changes user/system settings.

Future adoption must disclose fresh-device/fixture/permissions state, actual installed product hashes and source, endpoint/backend/build configuration, and obtain real resource ownership. No legacy n3 group is mixed with this empty-device observation. No automatic “repair” or new recurring runner was added.

Recovery impact is limited to one separate default simulator and local evidence. Original app databases, EventKit fixtures, settings, permissions, keychain, wallpaper store, fixed caches and raw evidence are preserved. Nothing was copied from the defective private store into the replacement. An in-place erase, private-store deletion, runtime installation/switch or toolchain/global configuration change still requires its original explicit authorization. If replacement later reproduces the signature, stop/retain/shutdown and prepare Apple Feedback; do not retry blindly.

## Raw evidence and Apple boundary

Primary `tests/results/runs/posterboard-diagnosis-20261018/`: original/second owner reports, screenshot, matching IPS originals, original unified log and exact assertion reduction; `fresh-control-v1/`: pre-create plan/impact, device metadata, command times, bootstatus,60s observation, raw log and summary, final state. Indexed by the separate QA journal; private runtime reports stay out of Git. No required input is only in/tmp.

Apple's [Xcode27.1 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27_1-release-notes) describe initial launch delays and Duo-only StandBy/extension limitations, not this matching iPhone18ProMax assertion. No exact Apple acknowledgement/fix was established. [Apple Developer Tools guidance](https://developer.apple.com/forums/thread/819560) recommends time-correlated crash diagnostics/Feedback for simulator faults; that different report is not proof of this root cause. Existing IPS/logs suffice for a prepared feedback package; no account message/upload was sent and no global logging profile installed.

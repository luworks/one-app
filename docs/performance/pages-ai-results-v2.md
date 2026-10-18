# Current-main page and AI baseline results v2

Production `b1fc12b62e796ac6c232da5e524235a59edba945`; measurement `83b4fb8af1b72d80fc344ecd78f313e2ccec9149`. Draft [PR76](https://github.com/luworks/one-app/pull/76). No production optimization has been measured in this current-main track. Earlier branch results remain historical.

## First bounded batch

Debug `-O`, DEBUG fixtures; iPhone18ProMax/iOS27.0 simulator, SDK27.1; Today-Performance `3243BEDB-4F6A-4807-AE9E-30115C528377`; Mac14,10/16GiB/12cpu. Existing owned derived-optimized cache reused. Small versioned today-dataset SHA256 `e91a99f1a16eabdad31b2f8c7e3bff7bf20f058713945964f8fdc684a9ba31c7`,09:41, in-memory store; Health sample, Calendar/Reminders sync off. AI model unavailable fallback, no generation performance claim. Local date/locale/timezone use simulator defaults; exact controlled timezone was not established for this batch.

Three targeted methods passed: conversation56.190s, Clock76.268s and Health (see raw log for test elapsed). UI automation elapsed is not a product metric. Build and test command exit0. Simulator shut down, panel closed, heavy/booted empty, holder released12:15:07 PDT inside12:08:36–12:18:36 window.

AI n3 uses fresh process/OS-warm first sends with identical fresh chat/history. Page n3 is one first cycle plus two ordered revisits, not a homogeneous warm-cache cohort. All values below are app-side monotonic proxy endpoints; geometry/two-displaylink callbacks do not prove presented frames, animation completion or full usability. AI ready is observed SwiftUI state after handler emission, not the underlying model-return timestamp. No p95 is estimated.

| Metric | Raw ms in order | Median ms | Required /3 | Stretch /10 | Context / gap |
| --- | --- | ---: | ---: | ---: | --- |
| page.clock.alarms | 99.402, 84.453, 84.226 | 84.453 | 28.151 | 8.445 | first cycle + two revisits; baseline only, no candidate |
| page.clock.cityPicker | 449.486, 132.681, 132.888 | 132.888 | 44.296 | 13.289 | first cycle + two revisits; baseline only, no candidate |
| page.clock.stopwatch | 566.981, 67.005, 50.355 | 67.005 | 22.335 | 6.700 | first cycle + two revisits; baseline only, no candidate |
| page.clock.timer | 250.684, 100.484, 83.245 | 100.484 | 33.495 | 10.048 | first cycle + two revisits; baseline only, no candidate |
| page.clock.worldClock | 251.054, 49.386, 49.854 | 49.854 | 16.618 | 4.985 | first cycle + two revisits; baseline only, no candidate |
| ai_ready_to_response_layout | 78.347, 78.174, 107.561 | 78.347 | 26.116 | 7.835 | fresh process, simulator fallback; baseline only, no candidate |
| ai_send_to_feedback_layout | 249.068, 354.560, 290.390 | 290.390 | 96.797 | 29.039 | fresh process, simulator fallback; baseline only, no candidate |
| ai_send_to_first_response_ready | 203.518, 276.445, 214.123 | 214.123 | 71.374 | 21.412 | fresh process, simulator fallback; baseline only, no candidate |
| ai_send_to_full_response_ready | 203.518, 276.445, 214.123 | 214.123 | 71.374 | 21.412 | fresh process, simulator fallback; baseline only, no candidate |
| ai_turn_to_response_layout | 281.866, 354.619, 321.684 | 321.684 | 107.228 | 32.168 | fresh process, simulator fallback; baseline only, no candidate |
| page.health | 632.203, 134.550, 134.697 | 134.697 | 44.899 | 13.470 | first cycle + two revisits; baseline only, no candidate |
| page.health.detail | 982.618, 115.995, 115.913 | 115.995 | 38.665 | 11.599 | first cycle + two revisits; baseline only, no candidate |
| page.health.picker | 233.472, 132.979, 149.103 | 149.103 | 49.701 | 14.910 | first cycle + two revisits; baseline only, no candidate |

Health detail first sample is substantially slower than its revisits; retain the ordered raw data rather than describing the median as first-open latency. That first-open cohort currently has n1 and cannot establish a stable cold-page percentile or speedup. Root init samples within these page methods have n1 each and differing launch arguments; do not pool them into a current launch baseline.

## Evidence and priorities

Canonical root: `/Users/yuanlu/code/one-app/tests/results/runs/performance-pages-ai-20261018/`. First raw log `baseline-first-ae87d5e3.log`, command JSON, `first-context.json`, `first-summary.json`, source archive/measurement patch/manifest and complete closed `baseline-first/ui.xcresult` are retained. QA session `performance-pages-ai-first-20261018` archived the closed run; `first-products/` preserves executed app/runner.

- P1: AI feedback≈290ms and full-result layout≈322ms deserve stage attribution; current observations do not identify CPU, model, persistence or framework cost. Do not optimize by moving the endpoint or skipping output work.
- P1: retain first-use Health detail≈983ms as a visible latency hypothesis; obtain repeated equivalent first-open samples before choosing a chart/layout candidate.
- P2: finish unmeasured page/operation coverage before tuning already short Clock transitions. Keep initial data scale and proxy limitations explicit.

## Remaining work

Capture/follow-up/confirmation and plan/Apply baseline is now measured below on the same compiled products. Search/Quick Reminder/detail is measured below; Settings/Activity remains invalid after a reproduced instrumentation failure. Additional Settings subpages and event/alarm draft tests are source-ready only and require a subsequent bounded incremental build. Complete [coverage inventory](page-coverage-v2.md) remains the scope: no claim that every page has been measured yet. Per-page memory/retention, hitch/frame work, persistence success/latency, internal AI kind/title stages and actual usable/presented endpoints remain pending. Physical model/HealthKit/AlarmKit/battery and App Store thinning remain outside this simulator-only lane.

No authorized same-protocol competitor measurements exist. Numeric top-app gap is unknown. Platform responsiveness budgets are linked in [protocol v2](pages-ai-protocol-v2.md), separately from owner relative3x/10x goals. No optimization plateau is claimed.

## AI capture and planning baseline

Same83b4fb8 compiled products and endpoint definitions, no compilation; two methods passed: capture/follow-up/confirmation90.277s and plan/Apply/Undo69.746s. Each method repeated the same journey in three fresh processes. Capture first turn uses unavailable-model fallback; the fixed-history time correction uses rules. Plan is local rules, not inference. Confirmed Add/Apply and Undo are correctness guards; no commit/save latency was instrumented. Shutdown/release12:20:16 PDT inside12:16:01–12:26:01 window.

| Journey / backend | Endpoint | Raw ms | Median ms | Required /3 | Stretch /10 |
| --- | --- | --- | ---: | ---: | ---: |
| capture first turn / fallback_model_unavailable | ai_ready_to_response_layout | 91.275, 104.180, 108.046 | 104.180 | 34.727 | 10.418 |
| capture time correction / rules | ai_ready_to_response_layout | 74.789, 59.665, 91.815 | 74.789 | 24.930 | 7.479 |
| capture first turn / fallback_model_unavailable | ai_send_to_feedback_layout | 446.842, 448.771, 917.255 | 448.771 | 149.590 | 44.877 |
| capture time correction / rules | ai_send_to_feedback_layout | 96.290, 78.677, 118.330 | 96.290 | 32.096 | 9.629 |
| capture first turn / fallback_model_unavailable | ai_send_to_first_response_ready | 399.185, 387.209, 842.592 | 399.185 | 133.062 | 39.919 |
| capture time correction / rules | ai_send_to_first_response_ready | 21.563, 19.073, 26.570 | 21.563 | 7.188 | 2.156 |
| capture first turn / fallback_model_unavailable | ai_send_to_full_response_ready | 399.185, 387.209, 842.592 | 399.185 | 133.062 | 39.919 |
| capture time correction / rules | ai_send_to_full_response_ready | 21.563, 19.073, 26.570 | 21.563 | 7.188 | 2.156 |
| capture first turn / fallback_model_unavailable | ai_turn_to_response_layout | 490.461, 491.389, 950.638 | 491.389 | 163.796 | 49.139 |
| capture time correction / rules | ai_turn_to_response_layout | 96.351, 78.738, 118.385 | 96.351 | 32.117 | 9.635 |
| local plan preview / rules | ai_ready_to_response_layout | 235.698, 319.573, 414.808 | 319.573 | 106.524 | 31.957 |
| local plan preview / rules | ai_send_to_feedback_layout | 317.224, 460.423, 548.150 | 460.423 | 153.474 | 46.042 |
| local plan preview / rules | ai_send_to_first_response_ready | 81.617, 140.911, 133.448 | 133.448 | 44.483 | 13.345 |
| local plan preview / rules | ai_send_to_full_response_ready | 81.617, 140.911, 133.448 | 133.448 | 44.483 | 13.345 |
| local plan preview / rules | ai_turn_to_response_layout | 317.315, 460.483, 548.256 | 460.483 | 153.494 | 46.048 |

The independent medians above cannot be added to reconstruct a turn. Current plan result-layout wait is larger than response-ready wait, but these proxy durations do not identify chart/card CPU or rendering. Attribute stages before selecting an optimization.

Raw evidence: `baseline-ai-confirmation-9faa0bd0.log`, command/context, `ai-confirmation-summary.json`, complete closed `baseline-ai-confirmation/ui.xcresult`; archived QA session `performance-pages-ai-confirmation-20261018`. No p95 or overall3x/10x gain is claimed.

## Search and reminder screens; Settings instrumentation failure

Search/Quick Reminder/list/detail method passed107.627s, same83b4fb8 products. Each path has n3 ordered first-cycle/two-revisit samples. Settings method failed54.682s at activityData endpoint; unchanged isolated repetition failed59.058s at the same point. The exported final video frame visibly shows the Activity data Form: this is evidence that navigation occurred, not a passing measurement endpoint. The failed method provides no accepted baseline for Settings/Activity. No product navigation or assertion was weakened.

| Metric | Raw ms | Median ms | Required /3 | Stretch /10 |
| --- | --- | ---: | ---: | ---: |
| page.reminder.editor | 505.291, 217.885, 251.276 | 251.276 | 83.759 | 25.128 |
| page.reminder.quick | 397.956, 249.227, 232.644 | 249.227 | 83.076 | 24.923 |
| page.reminders.list | 315.870, 132.573, 148.903 | 148.903 | 49.634 | 14.890 |
| page.search | 1719.681, 366.393, 282.896 | 366.393 | 122.131 | 36.639 |
| page.search.results | 179.061, 109.438, 76.374 | 109.438 | 36.479 | 10.944 |

Evidence: `baseline-settings-search-9f7a18ad.log`, full closed `baseline-settings-search/ui.xcresult`; `settings-repro-6ab29add.log` and full closed `settings-repro/ui.xcresult`; `settings-failure-analysis/` contains exported activity tree, original video, metadata and `failure-last-frame.png`. Both failed runs remain failed in the QA journal. Shutdown/release12:27:12 PDT; no further attempt in that window.

Next measurement-only repair: ensure the trace-enabled navigation timer begins in its state-binding action, and attach the destination probe to the actual Activity data Form. Keep original trace-disabled links and all test assertions. Revalidate the one representative failure with new source before accepting these page metrics.


## Launch/resume and root navigation

Same frozen83b4fb8 products, productionb1fc12b, Debug-O and fixture/context above. `testLaunchAndResumeEndpoints` passed44.381s (three process launches/OS-warm and matching resume operations). Init starts at the first explicit `OneApp.init` statement: dyld/pre-init is excluded. Both endpoints end at content geometry plus two display-link callbacks, not full usability.

| Metric | Raw ms | Median ms | Required /3 | Stretch /10 |
| --- | --- | ---: | ---: | ---: |
| app_init_to_content_layout | 2624.286, 1633.695, 1450.897 | 1633.695 | 544.565 | 163.370 |
| resume_to_content_layout | 81.810, 49.768, 31.782 | 49.768 | 16.589 | 4.977 |

No p95 or speedup is claimed. `testNavigationEndpointsAndKeptState` failed28.553s at Clock because XCTest found two `performance.trace` StaticTexts carrying the identical interval. Its preceding n1 transitions are retained as diagnostics, not accepted navigation baselines; state-retention assertions were not reached. A measurement-reader repair deduplicates identical interval strings, requires exactly one distinct matching report, and rejects disagreeing mirrors before navigation. Endpoint definitions and all destination/state assertions are unchanged. The repair is source-only until the next incremental build and focused navigation run.

Evidence: `baseline-root-navigation-c334b127.log`, `root-navigation-command.json`, `root-navigation-summary.json`, full closed `baseline-root-navigation/ui.xcresult`; QA archive `performance-pages-root-navigation-20261018`. Simulator shutdown/panel closed and live heavy/booted empty before12:36 resource handoff.


## Repaired page/root coverage and AI-open diagnostic cohort

Productionb1fc12b plus measurementfc1355f; stable `build-source`, same derived-optimized cache, Debug-O and fixture/simulator above. One build plus three selected methods passed: conversation62.716s, Settings/Activity144.546s, root navigation84.083s. The root journey reached all retained-list/calendar-mode assertions. The Settings controlled-link/Form-probe and duplicate-identical-interval reader repairs are now simulator verified. These are measurement repairs, not production speed candidates.

AI now waits for its own modal page.ai endpoint and hittable input before sending; its open-to-send delay and instrumentation differ from83b4fb8. Keep this as a new diagnostic cohort, not a causal speed comparison. AI ready is state observation; other listed rows are geometry/two-display-link proxies. Page/root n3 remains first cycle plus two revisits; AI n3 fresh-process/OS-warm. No p95.

| Method / endpoint | Raw ms | Median ms | Required /3 | Stretch /10 |
| --- | --- | ---: | ---: | ---: |
| ConversationFreshLaunchN3 / ai_ready_to_response_layout | 76.480, 85.888, 96.427 | 85.888 | 28.629 | 8.589 |
| ConversationFreshLaunchN3 / ai_send_to_feedback_layout | 532.188, 631.581, 353.799 | 532.188 | 177.396 | 53.219 |
| ConversationFreshLaunchN3 / ai_send_to_first_response_ready | 455.786, 545.770, 274.865 | 455.786 | 151.929 | 45.579 |
| ConversationFreshLaunchN3 / ai_send_to_full_response_ready | 455.786, 545.770, 274.865 | 455.786 | 151.929 | 45.579 |
| ConversationFreshLaunchN3 / ai_turn_to_response_layout | 532.266, 631.658, 371.292 | 532.266 | 177.422 | 53.227 |
| ConversationFreshLaunchN3 / page.ai | 1515.490, 1455.576, 1389.850 | 1455.576 | 485.192 | 145.558 |
| NavigationEndpointsAndKeptState / calendar.month_to_calendar.year | 767.396, 650.139, 734.033 | 734.033 | 244.678 | 73.403 |
| NavigationEndpointsAndKeptState / calendar.week_to_calendar.month | 286.482, 235.770, 235.404 | 235.770 | 78.590 | 23.577 |
| NavigationEndpointsAndKeptState / calendar.week_to_tasks | 568.537, 166.492, 168.375 | 168.375 | 56.125 | 16.838 |
| NavigationEndpointsAndKeptState / calendar.year_to_calendar.week | 250.017, 266.399, 250.188 | 250.188 | 83.396 | 25.019 |
| NavigationEndpointsAndKeptState / clock_to_today | 116.057, 99.382, 316.299 | 116.057 | 38.686 | 11.606 |
| NavigationEndpointsAndKeptState / tasks_to_clock | 233.461, 115.838, 184.148 | 184.148 | 61.383 | 18.415 |
| NavigationEndpointsAndKeptState / today_to_calendar.week | 334.134, 166.574, 199.574 | 199.574 | 66.525 | 19.957 |
| SettingsSubpageAndActivityEndpoints / page.activity | 167.815, 116.997, 183.849 | 167.815 | 55.938 | 16.782 |
| SettingsSubpageAndActivityEndpoints / page.settings | 833.049, 167.620, 299.684 | 299.684 | 99.895 | 29.968 |
| SettingsSubpageAndActivityEndpoints / page.settings.activityData | 358.129, 164.455, 301.263 | 301.263 | 100.421 | 30.126 |

The standalone n1 init samples in Settings/navigation are excluded from accepted launch data. The three page.ai first-open samples are deliberately retained; they include SwiftUI/modal work and the probe boundary, not model generation.

Fine AI stages were printed only by the app and absent from the runner log. One closed xcresult console extraction failed exit1 with `Error: No console log available`; stdout0B. Therefore internal stage timings remain unmeasured. Source-only eee949a exports one token-keyed stage line via the existing final history publication after both layout endpoints are frozen; a focused subsequent run must verify capture before using it. No bottleneck is attributed from missing data.

Evidence: `baseline-v2-round3-f735cb88.log`, `round3-command.json`, `staged-source-v2-round3/manifest.json`, `round3-summary.json`, `round3-console.{stdout,stderr}` and full closed `baseline-v2-round3/ui.xcresult`. Three-method run exit0; owned simulator/panel shut down, live heavy/booted empty12:47:20 PDT.


## Secondary pages and complete AI stage export

Productionb1fc12b plus measurementeee949a, same Debug-O cache/device/fixture. Three selected methods passed: AI conversation66.386s, local event/alarm drafts65.456s, Settings subpages167.930s. Drafts are opened/cancelled without saving or permission prompts; settings switches/grants are not changed. The stage-export repair is now runtime verified: each of three conversation tokens has exactly five endpoints plus one complete stage line, exported after both layouts are frozen. No source model/production optimization is included.

| Endpoint | Raw ms | Median ms | Required /3 | Stretch /10 |
| --- | --- | ---: | ---: | ---: |
| ai_ready_to_response_layout | 70.354, 115.908, 108.751 | 108.751 | 36.250 | 10.875 |
| ai_send_to_feedback_layout | 356.239, 526.245, 444.116 | 444.116 | 148.039 | 44.412 |
| ai_send_to_first_response_ready | 285.991, 438.115, 335.445 | 335.445 | 111.815 | 33.544 |
| ai_send_to_full_response_ready | 285.991, 438.115, 335.445 | 335.445 | 111.815 | 33.544 |
| ai_turn_to_response_layout | 356.345, 554.024, 444.196 | 444.196 | 148.065 | 44.420 |
| page.ai | 2371.250, 2137.986, 2188.069 | 2188.069 | 729.356 | 218.807 |
| page.alarm.editor | 398.110, 182.913, 199.302 | 199.302 | 66.434 | 19.930 |
| page.event.editor | 1540.472, 634.067, 533.708 | 634.067 | 211.356 | 63.407 |
| page.settings | 766.373, 182.901, 250.186 | 250.186 | 83.395 | 25.019 |
| page.settings.automaticChanges | 193.236, 131.367, 147.671 | 147.671 | 49.224 | 14.767 |
| page.settings.calendars | 167.511, 132.647, 282.702 | 167.511 | 55.837 | 16.751 |
| page.settings.holidays | 253.746, 181.432, 173.330 | 181.432 | 60.477 | 18.143 |

AI stage elapsed spans, n3 same fresh-process Hello turns (not CPU, executor contention or inference measurements):

| Span | Raw ms | Median ms |
| --- | --- | ---: |
| await_to_emission | 0.037, 0.039, 0.054 | 0.039 |
| context_to_respond | 14.002, 14.847, 17.195 | 14.847 |
| emission_to_observation | 19.783, 15.210, 17.623 | 17.623 |
| observation_to_ready | 0.007, 0.009, 0.010 | 0.009 |
| ready_to_layout | 70.354, 115.908, 108.751 | 108.751 |
| record_call | 0.142, 1.529, 1.405 | 1.405 |
| response_await | 40.100, 239.786, 144.624 | 144.624 |
| send_to_context | 1.691, 4.417, 1.678 | 1.691 |
| task_queue | 209.946, 162.062, 152.654 | 162.062 |

Do not add/subtract independent medians to predict a total. Async scheduling and await elapsed time motivate one bounded deterministic-local-reply experiment, not a CPU attribution or verified gain. Its full-layout target is444.196/3=148.065ms for this cohort, but final candidate acceptance must use matching diagnostic schema/configuration and correctness gates. Model-available paths remain outside simulator inference evidence.

Evidence: `baseline-v2-round4-54c0dcf2.log`, `round4-command.json`, `staged-source-v2-round4/manifest.json`, `round4-summary.json`, `round4-stages.json`, full closed `baseline-v2-round4/ui.xcresult`; archived QA session `performance-pages-v2-round4-20261018`. Exit0; all owned simulator/panel closed, live heavy/booted empty12:54:18 PDT. Remaining tertiary pages, per-page memory/hitches, persistence outcomes and model internals remain explicitly pending.


## Common-schema reference and tertiary pages

Productionb1fc12b plus common measuremented92fc7. The dispatch-aware schema is now built and verified on the original asynchronous implementation, before measuring the local-response candidate. Three methods passed: conversation67.334s, Alarm/Timer Sound72.249s, Year key/new-list editor61.350s. Same Debug-O, fixed derived-optimized, device/fixture/context; stage dispatch explicitly async. No production optimization is present.

| Endpoint | Raw ms | Median ms | Required /3 | Stretch /10 |
| --- | --- | ---: | ---: | ---: |
| page.alarm.editor | 515.833, 199.389, 199.349 | 199.389 | 66.463 | 19.939 |
| page.alarm.sound | 232.726, 116.320, 99.293 | 116.320 | 38.773 | 11.632 |
| page.timer.sound | 149.158, 132.601, 149.193 | 149.158 | 49.719 | 14.916 |
| ai_ready_to_response_layout | 125.491, 127.000, 154.741 | 127.000 | 42.333 | 12.700 |
| ai_send_to_feedback_layout | 609.474, 662.173, 426.765 | 609.474 | 203.158 | 60.947 |
| ai_send_to_first_response_ready | 500.658, 552.623, 272.098 | 500.658 | 166.886 | 50.066 |
| ai_send_to_full_response_ready | 500.658, 552.623, 272.098 | 500.658 | 166.886 | 50.066 |
| ai_turn_to_response_layout | 626.149, 679.623, 426.839 | 626.149 | 208.716 | 62.615 |
| page.ai | 1421.343, 4171.340, 1265.850 | 1421.343 | 473.781 | 142.134 |
| page.calendar.year.key | 452.186, 234.032, 201.745 | 234.032 | 78.011 | 23.403 |
| page.list.editor | 1127.494, 315.489, 299.603 | 315.489 | 105.163 | 31.549 |

This common-schema conversation reference supersedes earlier diagnostic cohorts **only for the forthcoming matched candidate comparison**; older measurements remain unchanged and unpooled. Its full-layout3x goal is208.716ms. The n3 range426.839–679.623ms is material variability, not a p95 or stable population estimate. Ask-open itself also varies1265.850–4171.340ms; no candidate effect on open latency is assumed.

Sound screens were opened/backed out without selection/save; Year key opened/dismissed and new-list draft cancelled. These four additional endpoints make26 distinct accepted page/modal/state endpoints across cohorts; variants, menu actions, per-page memory/hitches and persistence remain partial. Seven root transitions remain separate.

Evidence: `baseline-v2-round5-reference-f326dd61.log`, `round5-reference-{summary,stages}.json`, `round5-reference-command.json`, `staged-source-v2-round5-reference/manifest.json`, full closed `baseline-v2-round5-reference/ui.xcresult`. Executed app and UI runner preserved in `round5-reference-products/`, executable UUID/hash in provenance.json. Exit0; owned device/panel shut down and live heavy/booted empty13:08:35 PDT before EventSave handoff. Candidate09f9860 is source-only until its matched run and trace-disabled correctness journeys.


## Delivery integration

The baseline/tooling branch merges main `edb7d73` (adopted preview workflow). The sole source conflict was `OneApp.init`: keep the performance start as its first explicit statement and retain the DEBUG/axe-only early fixture return and blank preview scene. Preview-only guards/previews auto-merged with opt-in page probes. No endpoint was moved; no production local-response candidate is in PR76. Merge validation is manual conflict/diff inspection, reusing the13 targeted method results at their explicitly frozen revisions above; it is not a new runtime measurement of merged main. This keeps baseline delivery independent of PR80's pending speed acceptance.

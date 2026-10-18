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

Capture/follow-up/confirmation and plan/Apply baseline is queued on the same compiled products. Settings/Activity and Search/Quick Reminder/detail methods remain unexecuted. Additional Settings subpages and event/alarm draft tests are source-ready only and require a subsequent bounded incremental build. Complete [coverage inventory](page-coverage-v2.md) remains the scope: no claim that every page has been measured yet. Per-page memory/retention, hitch/frame work, persistence success/latency, internal AI kind/title stages and actual usable/presented endpoints remain pending. Physical model/HealthKit/AlarmKit/battery and App Store thinning remain outside this simulator-only lane.

No authorized same-protocol competitor measurements exist. Numeric top-app gap is unknown. Platform responsiveness budgets are linked in [protocol v2](pages-ai-protocol-v2.md), separately from owner relative3x/10x goals. No optimization plateau is claimed.

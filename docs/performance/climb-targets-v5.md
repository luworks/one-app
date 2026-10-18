# Performance climb targets after integrated delivery v5

PR94 integrated-delivery target registry. The tested Year production candidate was rejected and reverted; final source keeps the proven original implementation plus the common correctness guard. See [matched result](year-position-climb-v4.md). Targets do not reset achieved gains or turn historical observations into measurements of the final main tree.

## Fixed goals and acceptance

Retain the owner goals: bytes and positive steady-state footprint ≤49% of the original comparable baseline; latency ≤baseline/3, stretch ≤baseline/10. Report absolute deltas and complete ordered n3 values. No p95 from these samples. First-cycle/revisit and fresh-process/OS-warm cohorts remain separate. Keep the same endpoint, build configuration, fixture, backend and operation history; no moving work beyond an endpoint or removing user functionality to meet a target.

AI conversation full turn→response layout retains626.148916ms as its matched reference and309.332167ms as the accepted local-fallback candidate:2.024x. Required≤208.716305ms (remaining100.615862ms); stretch≤62.614892ms. These are simulator unavailable-model/non-streaming proxies, not model inference or presented/usable frames. Feedback product goal≤100ms is an aspiration; retain correctness, Add/Apply/Undo and durable writes. Other AI capture/correction/plan backends keep their separate existing baselines; no pooling.

Release logical One.app:24,351,341→9,707,057B (−60.14%,51% goal met). Local deflate9 ZIP:7,829,466→4,679,034B (−40.24%); required≤3,836,438B, remaining842,596B. Exact measured sources/builds remain in release-footprint-v2.md; these are not current-main rebuilt sizes or App Store thinned download/install sizes.

## All accepted page endpoint budgets

Historical per-endpoint registry from pages-ai-results-v2.md,26 endpoints, n3 each. Read the linked report for exact production/measurement SHA and raw ordered values; cohort labels below identify the table, not a new run. First-open n1 remains separate from a three-visit median. Current final-main coverage is not inferred by merging source. Refresh only an affected endpoint under a matched candidate comparison, rather than repeating every green journey. Milliseconds below.

| Endpoint | Reference median | Required /3 | Stretch /10 | Original cohort |
|---|---:|---:|---:|---|
|page.activity|167.815|55.938|16.782|Repaired page/root coverage and AI-open diagnostic cohort|
|page.ai|1421.343|473.781|142.134|Common-schema reference and tertiary pages|
|page.alarm.editor|199.389|66.463|19.939|Common-schema reference and tertiary pages|
|page.alarm.sound|116.320|38.773|11.632|Common-schema reference and tertiary pages|
|page.calendar.year.key|234.032|78.011|23.403|Common-schema reference and tertiary pages|
|page.clock.alarms|84.453|28.151|8.445|First bounded batch|
|page.clock.cityPicker|132.888|44.296|13.289|First bounded batch|
|page.clock.stopwatch|67.005|22.335|6.700|First bounded batch|
|page.clock.timer|100.484|33.495|10.048|First bounded batch|
|page.clock.worldClock|49.854|16.618|4.985|First bounded batch|
|page.event.editor|634.067|211.356|63.407|Secondary pages and complete AI stage export|
|page.health|134.697|44.899|13.470|First bounded batch|
|page.health.detail|115.995|38.665|11.599|First bounded batch|
|page.health.picker|149.103|49.701|14.910|First bounded batch|
|page.list.editor|315.489|105.163|31.549|Common-schema reference and tertiary pages|
|page.reminder.editor|251.276|83.759|25.128|Search and reminder screens; Settings instrumentation failure|
|page.reminder.quick|249.227|83.076|24.923|Search and reminder screens; Settings instrumentation failure|
|page.reminders.list|148.903|49.634|14.890|Search and reminder screens; Settings instrumentation failure|
|page.search|366.393|122.131|36.639|Search and reminder screens; Settings instrumentation failure|
|page.search.results|109.438|36.479|10.944|Search and reminder screens; Settings instrumentation failure|
|page.settings|250.186|83.395|25.019|Secondary pages and complete AI stage export|
|page.settings.activityData|301.263|100.421|30.126|Repaired page/root coverage and AI-open diagnostic cohort|
|page.settings.automaticChanges|147.671|49.224|14.767|Secondary pages and complete AI stage export|
|page.settings.calendars|167.511|55.837|16.751|Secondary pages and complete AI stage export|
|page.settings.holidays|181.432|60.477|18.143|Secondary pages and complete AI stage export|
|page.timer.sound|149.158|49.719|14.916|Common-schema reference and tertiary pages|

## Missing evidence and next priorities

P1: Year initial-ID experiment is rejected: matched reference1045.320ms vs candidate1231.932ms and visit3 footprint253.823→291.925MiB. The final code restores the reference. Keep the original Year latency goal≤244.678ms (historical734.033/3) and footprint≤122.56MiB (historical visit3250.13×0.49); do not loosen these to348.440ms/124.373MiB merely because this new reference is slower/larger. These are stricter operational budgets, not a causal speed comparison across cohorts. Next identify a removable allocation/positioning cost before selecting another production change. Memory windows are whole-app fixed-window observations, not exclusive page allocations or leak proof. Existing23 complete operation/history groups under22 route IDs remain linked in root-resources-v4.md and secondary-resources-v4.md; their per-group visit3×0.49 budgets stay unchanged. Native Year peak median226.768MiB has an aspirational111.116MiB target, under its separate gesture cohort.

P1: reduce AI full-turn gap through a source-backed removable operation; current profile does not justify changing synchronous-save ordering or blaming all framework CPU on app redundancy. First Health-detail open982.618ms and Search open1719.681ms are n1 first-use observations; obtain equivalent n3 first-use data only when selecting those candidates.

P1: inspect actual compressed package contributors before proposing the remaining842,596B ZIP reduction. Keep all audio/resource contracts and symbolication. P2: establish missing persistence-success/Add/Apply/Undo latency and returning-anchor retention baselines before setting absolute success-latency or leak claims. Menus/permissions, async real-provider completion and every material page variant remain partial coverage.

Frame budgets are16.67ms at60Hz and8.33ms at120Hz, separately from two-display-link proxies. Native hitch metrics were not returned, so the current hitch gap is unknown; [Apple platform guidance](https://developer.apple.com/videos/play/tech-talks/10855/) below5 hitch ms/s is a reference, not a measured competitor. Some stretch proxy budgets are shorter than the endpoint's callback floor; mark them infeasible for that protocol until a separately versioned real-presentation endpoint exists, never shorten the original endpoint to claim success.

No same-protocol authorized top-app measurements exist: numeric top-app gap remains unknown. No physical-phone, model-generation, real battery or App Store thinning evidence is requested or assigned by this report.

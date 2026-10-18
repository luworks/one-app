# Today performance climb targets v1

Owner authorization: >50% smaller package/footprint, at least 3x faster, stretch 10x or better. These are acceptance targets, not verified gains. No production optimization is accepted on a guessed or incomparable baseline.

Source baseline: `c42b88e` production / `fc683a7` tooling. Machine-readable registry: [`tests/performance/targets-v1.json`](../../tests/performance/targets-v1.json). Historical baseline values remain frozen. True Release usable-content endpoint baselines remain pending. This round explicitly selects **optimized Debug (`-O`) with the existing DEBUG fixture guards** for baseline/candidate, measuring monotonic init/store/bootstrap and tab action-to-layout/display-link proxies. These are not presented frames, real-touch latency or full usability. No PERFORMANCE compilation condition is introduced.

| Metric | Unit | Existing baseline | Required ceiling | Stretch ceiling |
| --- | --- | ---: | ---: | ---: |
| release_bundle | bytes | 23,374,117 | 11,453,317.33 | 9,349,646.8 |
| release_zip_proxy | bytes | 7,621,937 | 3,734,749.13 | 3,048,774.8 |
| debug_sim_bundle | bytes | 35,631,443 | 17,459,407.07 | 14,252,577.2 |
| debug_sim_zip_proxy | bytes | 10,583,652 | 5,185,989.48 | 4,233,460.8 |
| audio_resources | bytes | 5,280,736 | 2,587,560.64 | 2,112,294.4 |
| all_release_macho | bytes | 17,861,152 | 8,751,964.48 | 7,144,460.8 |
| main_release_executable | bytes | 16,731,520 | 8,198,444.8 | 6,692,608 |
| debug_process_to_onappear | ms | 2,323 | 774.333 | 232.3 |
| year_scroll_peak_physical_median | MiB | 286.97 | 140.615 | 114.788 |
| year_scroll_absolute_physical_median | MiB | 229.32 | 112.367 | 91.728 |
| navigation_peak_rss | MiB | 610.797 | 299.29 | 244.319 |
| activity_newest_page | ms | 1.09 | 0.363 | 0.109 |
| activity_deep_page | ms | 1.57 | 0.523 | 0.157 |
| activity_day_count | ms | 0.12 | 0.04 | 0.012 |
| activity_search | ms | 27.8 | 9.267 | 2.78 |
| activity_bulk_100k | ms | 2,280 | 760 | 228 |
| release_launch_usable_content | ms | not measured | new baseline / 3 | new baseline / 10 |
| warm_resume_usable_content | ms | not measured | new baseline / 3 | new baseline / 10 |
| today_to_week | ms | not measured | new baseline / 3 | new baseline / 10 |
| week_to_month | ms | not measured | new baseline / 3 | new baseline / 10 |
| month_to_year | ms | not measured | new baseline / 3 | new baseline / 10 |
| calendar_to_reminders | ms | not measured | new baseline / 3 | new baseline / 10 |
| reminders_to_clock | ms | not measured | new baseline / 3 | new baseline / 10 |
| clock_to_today | ms | not measured | new baseline / 3 | new baseline / 10 |
| open_health | ms | not measured | new baseline / 3 | new baseline / 10 |
| open_settings | ms | not measured | new baseline / 3 | new baseline / 10 |
| open_quick_create | ms | not measured | new baseline / 3 | new baseline / 10 |
| quick_create_commit | ms | not measured | new baseline / 3 | new baseline / 10 |
| open_reminder | ms | not measured | new baseline / 3 | new baseline / 10 |
| complete_reminder | ms | not measured | new baseline / 3 | new baseline / 10 |
| search_results_after_input | ms | not measured | new baseline / 3 | new baseline / 10 |
| plan_preview_after_submit | ms | not measured | new baseline / 3 | new baseline / 10 |
| apply_plan_commit | ms | not measured | new baseline / 3 | new baseline / 10 |
| single_file_store_save | ms | not measured | new baseline / 3 | new baseline / 10 |

## Hard acceptance rules

- Byte/footprint ceilings use 49% of baseline (51% reduction) to exceed 50%; speed ceilings use baseline/3 and baseline/10. Component budgets guide work; they never justify deleting features or reducing fixture/data coverage.
- Product acceptance prioritizes complete Release app/ZIP proxy, actual app latency and physical memory. Debug diagnostics and host SQLite are separate tracks, never substitutes. App Store thinned sizes stay unknown without valid export.
- Existing XCTest tap times include unavoidable automation overhead and are retained as journey regression evidence. They are not product speedup denominators. App-side instrumentation must be applied identically to frozen baseline and candidate.
- Meaningful latency baseline/comparison uses n=3–5 raw samples and median/range; remeasure historical n=1 host queries first. No p95 claims from tiny samples. Capture before/after host load and compare only equivalent cache state.
- Absolute app-side goals: usable Release content <=500 ms; discrete feedback/results <=100 ms; durable commits <=50 ms; main-thread frame work <=5 ms; hitch rate <=5 ms/s (ideal zero). Relative 3x/10x goals remain tracked even if absolute budgets are already met.
- Preserve duration and all alarm choices; audio format compatibility and spectral/level checks required. Preserve every planner principle, explicit Add/Apply and Undo, query/search semantics, migration models, persisted identities and privacy/local-data boundaries.
- No phone operation, signing configuration change, user-data deletion, silent background write or broad/full UI suite. Keep one named simulator runner and reuse caches; coordinate every expensive batch.

## Iteration and stopping rule

For each candidate record hypothesis, owned files, expected metric, changed variable, raw comparable before/after, acceptance or rejection, and functional checks in the QA Activity journal plus a compact versioned round ledger. Keep only demonstrated gains or necessary measurement fixes. Each batch is focused and bounded; multiple batches require explicit host-holder handoff, not unbounded contention.

Continue through independent high-value hypotheses. A local plateau is reached only after profiling the remaining dominant costs, trying materially different safe candidates, and finding no remaining candidate with credible >5% benefit at proportionate product risk/cost. Two consecutive low/no-gain candidates trigger a bottleneck reassessment, not automatic completion. Record the failed hypotheses and residual gap; never assert a global optimum or that unmet targets were achieved. A hard platform floor or unavailable simulator metric is a documented blocker, not fabricated success.

Delegation: independent packaging, audio, startup/instrumentation and calendar-render lanes; explicit file ownership. Agents perform lightweight source work concurrently; builds/tests/traces stay under one coordinated holder. No recurring scheduler or autonomous goal object is created.

New phase gates (all pending matched baseline): `app_init_to_store`, `store_to_bootstrap_complete`, `tab_action_to_layout_displaylink_proxy`: required baseline/3, stretch baseline/10, with 100 ms interim phase budget. Shipping generic Release package bytes remain a separate measurement.

# Selected-year initial positioning experiment v4

## Hypothesis and frozen comparison

The [cache diagnosis](year-cache-diagnosis-v4.md) rejected eager computation of all41 years and dominant timed mark computation. Historical headers appeared before selected-year positioning. This experiment tests a native initial scroll-ID seed; it does not assume that lifecycle work explains the footprint or that SwiftUI will skip every other child.

Production base `cf92fabb2b92dc59d78eba061ec2b1ea3c12039c`; common-test reference `2d9fba0e24238bc9dbe872c87965618afe17ca92`; candidate `0a7beefdfbdcdb18198762410e30efff0dec8802`. The only production difference is `CalendarView.swift`: initialize an independent optional year-offset scroll ID, mark the existing lazy stack as a target layout, and bind the scroll position. Keep all41 years, marks/cache, actions, accessibility, and both existing proxy calls. Never write scroll position into the selected date.

Apple documents that [`scrollPosition(id:anchor:)`](https://developer.apple.com/documentation/swiftui/view/scrollposition(id:anchor:)) can preserve an initially bound target, using [`scrollTargetLayout()`](https://developer.apple.com/documentation/swiftui/view/scrolltargetlayout(isenabled:)). It does not guarantee elimination of offscreen layout or ordering relative to `ScrollViewReader` proxy calls. One focused independent source review found no material source defect; duplicate positioning, rebound and state retention remain runtime acceptance risks.

## Protocol and rejection conditions

Use retained Today-Performance/derived-optimized, Debug `SWIFT_OPTIMIZATION_LEVEL=-O`, jobs2, parallel testing disabled, the same dataset/fixed clock and unchanged monotonic endpoints. Year counters are disabled on both sides; resource sampling remains enabled. Common measurement-file hashes and exact commands are retained under primary `tests/results/runs/performance-pages-ai-20261018/year-position-v4/`. The original cache anchor remains b1fc12b solely to preserve incremental-source/cache provenance, not as the production denominator.

Run `PerformanceClimbTests/testRootNavigationResourceWindows` on each source: one process, first cycle plus two revisits, original navigation and kept-state assertions. Report all three ordered Year latency/resource values and ranges; the median is descriptive, with no tiny-sample p95. Check both producer exit0 and functional method pass. Do not compare against counter-enabled/high-load diagnostic timings. Retain other root transitions as regression observations with their distinct histories.

The common chosen-day correctness test retains offsets0/400 and adds reentry from the noncurrent selected year: its January mini-month must become fully visible/hittable without corrective scrolling, then Month must retain the exact selected date. Run that guard on the reference and candidate. Candidate additionally runs existing holiday/key and trip/birthday journeys. Preserve every original assertion; diagnose a concrete selector/layout failure before any retry.

Reject a wrong initial year, rebound, inability to scroll/tap, changed selection/marks/VoiceOver/retention, or absent defensible improvement. Proposed3x latency and51% footprint goals remain aspirations until this pair supplies actual evidence. A diagnostic mechanism check, if later needed, is a separate cohort. No simulator result represents real-touch presentation, model inference, App Store thinning, energy or phone performance.

## Current execution state

Preparation and source review only: no candidate build, UI result or measured gain yet. Another executor owns the current Reminder heavy batch; wait for its actual shutdown/release before opening the owned simulator or starting either command. Keep the focused comparison around the routine10-minute budget and stop expansion if blocked. Preserve all raw output and complete closed bundles through the separate QA journal. Delivery of PR92 is already complete and independent of this experiment.

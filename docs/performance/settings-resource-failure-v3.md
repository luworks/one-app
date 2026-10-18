# Settings resource failure v3: offline evidence boundary

The frozen `64a3de9cab66119e2aed6dbc3837961da6a65418` method
`PagePerformanceTests/testSettingsActivityResourceWindows` failed its existing
reachable-action assertion on the third Settings entry. The available evidence
establishes the failure location, but cannot establish the visible obstruction,
frame geometry, or a selector/timing root cause. No product or helper repair is
justified from this offline inspection.

## Verified observations

Canonical evidence root:
`/Users/yuanlu/code/one-app/tests/results/runs/performance-pages-ai-20261018/`.

- Raw log `page-resources-settings-v3-4a8db595.log`, lines 742–758: after the second
  Activity dismissal, XCTest taps Close sidebar, taps Open menu, successfully
  finds an existing Settings button, then fails `target.isHittable` at frozen
  `PagePerformanceTests.swift:142`. No third Settings tap or page measurement
  follows. The method fails after 116.861 seconds (line 760).
- Seven raw resource windows have `status: complete`: launch seq1; Settings,
  Activity data and Activity visits1/2 seq2–7. These are diagnostics from a failed
  method, not an accepted n3 page baseline.
- Frozen `tap` first waits for existence, then asserts hittability, then taps.
  Frozen Sidebar exposes Settings as a footer button. The existing source is
  consistent with an element that exists while not reachable; it does not prove
  why that happened at runtime.
- Log lines 788–791 report test-session cleanup blocking and `Finalize test log`
  waiting for recording to finish. `settings-resource-failure-v3/stop.json`
  records the subsequent targeted SIGINT/SIGTERM cleanup. The runner failure and
  producer-finalization failure are separate observations.

## One bounded result-bundle read

Exactly one summary read was attempted, with a 15-second timeout:

```text
xcrun xcresulttool get test-results summary --path <canonical-root>/page-resources-settings-v3/ui.xcresult
```

It returned exit64 in about 0.028 seconds. Exact stderr:

```text
Error: Failed to create a new result bundle reader, underlying error: Info.plist at /Users/yuanlu/code/one-app/tests/results/runs/performance-pages-ai-20261018/page-resources-settings-v3/ui.xcresult/Info.plist does not exist, the result bundle might be corrupted or the provided path is not a result bundle
```

The producer is stopped, but the bundle is not readable as a finalized xcresult.
No equivalent reader retries, hierarchy/video/attachment exports, or guessed
attachment IDs were attempted. The failure-time hierarchy, frames and video
remain unavailable. `post-failure-home.png` was explicitly identified as a
post-test Home screen image; it supplies no failure-frame evidence.

Raw command, stdout/stderr, frozen source copies/hashes, ordered window identities
and the numbered failure-log excerpt are retained under
`settings-resource-failure-v3/analysis/`. The inspection did not change or repair
the xcresult, and performed no Swift, build, UI, simulator, device or profiler
operations.

## Single next diagnostic

In the parent's next authorized isolated attempt, retain the same Settings
journey, target and assertion. Immediately before a failing hittability assertion,
print the current app hierarchy plus the Settings match count, target frame,
existence, enabled and hittable values to the durable raw runner log. This makes
the failure geometry inspectable even if xcresult finalization fails again.
Obtain an actual failure-time screenshot through the owned runner if available.
Do not change selectors, add coordinate taps, add blind delays, weaken assertions
or repeat other passing resource methods before that evidence is examined.


## Later diagnostic execution

The prepared probe was executed once on new frozen `affd4e1`/production `aa7c7c8`. Its producer exited65 normally and finalized the xcresult. The failure occurred on the second Settings entry, with a unique but hidden/nonhittable Settings node. Actual hierarchy, screenshot and video now exist; see [secondary resources v4](secondary-resources-v4.md) for exact evidence and the narrow setup synchronization repair. These later observations do not repair the old v3 partial result bundle or make its failed samples usable.

# Live Clock authorization freeze

Baseline: `62be465e7101ccc6cfac7ec071a41cac907388bb` (2026-10-29).

Observed evidence: the evaluation owner's retained `tests/results/intelligence-eval-20261028/live-product-round3-20261029/clock-app-sample.txt` has all 1,571 sampled UI-task stacks in `FirstRun.alarms -> AlarmCenter.requestAuthorization -> Ringer.authorization -> AlarmManager.authorizationState`, waiting on synchronous authorization XPC after Don't Allow. The system service's internal reason for not replying is unknown.

The Live driver now caches authorization in observable memory, consumes request results and authorization update elements directly, and runs startup/foreground snapshot reads on a dispatch worker. A single outstanding refresh bounds blocked work; generation checks discard snapshots and requests superseded by system decisions. A foreground refresh suspends a stale grant until a current answer arrives. Errors retain denial and never create a grant. AlarmService's requirements are unchanged. Timer start and reconciliation use the same cache. No permissions or evaluation device assets are modified.

The installed SDK AlarmKit Swift interface declares AlarmManager without actor isolation, AuthorizationState as Sendable, requestAuthorization as async, and authorizationUpdates as an AsyncSequence of AuthorizationState. The bridge captures no AlarmManager instance across executors.

Focused logic regression: four AlarmAuthorizationCacheTests cover denial, failed requests, a suspended injected read with main-actor progress, stale snapshot/request results, and foreground revocation/recovery. Runtime logs and subsequent Live acceptance are retained in the primary checkout's QA journal/results; physical-device behavior is untested.

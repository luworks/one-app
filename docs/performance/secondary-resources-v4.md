# Secondary-page resource baseline v4

Production reference `aa7c7c89b74d7107c618b18fa2d6fb6f6011625c`; frozen measurement `affd4e1b9b4863566dc80e1c0fd113e13b32506e`. Optimized Debug `-O`, Xcode27.1, Today-Performance iPhone18ProMax/iOS27.0, same project path and retained derived-optimized, jobs2/parallelNO. Canonical today-dataset.json SHA256 `e91a99f1a16eabdad31b2f8c7e3bff7bf20f058713945964f8fdc684a9ba31c7`, in-memory/sync off/09:41, one process/method and first cycle plus two ordered revisits. Pre-run host load6.72/13.86/16.50, exact process/hardware snapshot retained; no competing heavy runner. Same [resource protocol](page-resources-protocol-v3.md) and original latency endpoints/functional journey. This source adds a resource wrapper and failure-only test diagnostics, no product optimization.

## Search and reminders: accepted groups

The incremental build passed. `PagePerformanceTests/testSearchReminderResourceWindows` passed129.157s:16 valid windows including separate launch, five complete three-visit groups in PID77071,239 valid in-window VM samples; maximum observed sample gap109.997ms. The combined command exited65 because its separate Settings method failed. The reducer gates each method independently: Search groups are accepted; failed Settings groups are rejected. Search was not rerun.

Whole-app physical footprint while each state is visible, sampled about100ms through fixed1s post-layout windows. Values are descriptive ordered visits, not independent cold repetitions, exclusive page allocations or leak evidence. Sampled operation maxima can miss short peaks. Confidence moderate for these windows, low for target feasibility/device extrapolation; p95 absent. The owner's51% goals below are aspirational, not measured gains.

| State | Visit1 /2 /3 window medians MiB | Visit3 sampled max MiB | Visit1→3 MiB | Proposed visit3 goal MiB | Remaining MiB |
|---|---|---:|---:|---:|---:|
|reminder.editor|107.67 / 109.08 / 110.36|110.96|+2.69|54.08|56.28|
|reminder.quick|99.00 / 107.53 / 108.55|109.72|+9.55|53.19|55.36|
|reminders.list|96.75 / 104.92 / 105.98|106.02|+9.23|51.93|54.05|
|search|91.25 / 105.14 / 106.56|107.78|+15.31|52.22|54.35|
|search.results|98.61 / 106.10 / 107.28|107.42|+8.67|52.57|54.71|

Search first→third grows15.31MiB; Quick Reminder grows9.55MiB and list9.23MiB in this operation sequence. This does not attribute retention to those views. P1 next action is matched returning-anchor/allocation attribution before removing retained state; expected removable bytes are unknown. All create/edit presentations are cancelled, query input is the original single mutation `m`, and Buy milk/list/editor assertions remain. No save/durability or full async-data-ready claim.

## Settings: separate failed method

`testSettingsActivityResourceWindows` failed64.643s on the second Settings entry. Four complete windows (launch and first Settings/Activity data/Activity) remain diagnostic-only; no n3 Settings baseline is accepted. The producer exited65 normally and its xcresult finalized, unlike the previous [v3 finalizer failure](settings-resource-failure-v3.md).

Failure-only raw context: exactly one Settings label/gearshape identifier; exists/enabled true, hittable false, frame(185.33,858,52,52). Failure hierarchy shows sidebar x=-85.7 and root page at x=0; failure screenshot shows the Today page with the sidebar closed. The log records Close sidebar then immediate Open menu before checking the still-existing Settings node. Exported video frames show Activity dismissal and the page returning while the sidebar closes. This supports an inter-visit closing/opening setup race; it does not justify changing product navigation, selectors or the measured Settings action→layout endpoint.

A narrow test-only repair waits after Close sidebar for its disappearance and for the original menu to become hittable at its original closed x position. The same tap, Settings hittability/destination assertions and n3 journey remain; no arbitrary sleep or retry is added. The repair was verified only with the affected Settings method, without repeating passed Search/Root/Health/Clock methods. No latency gain may be claimed from changing this setup synchronization.

## Settings after setup repair: accepted groups

Frozen source `8315f083068c69aed5df6f1dd854fa04d393e782`, same production aa7c7c8/config/fixture/device/DD and fixed resource protocol. One incremental build + isolated Settings method passed183.490s, producer0,10 valid windows including one separate launch. One PID90029, three complete groups, 199 valid in-window samples; maximum sample gap188.027ms. Pre-run host load averages4.36/10.35/14.41; exact hardware/process snapshot retained. The added closure predicate synchronizes inter-visit setup only; the Settings action starts later at its original handler. Original Settings/content/hittability assertions all reached. No speed improvement is claimed from this repair, and earlier failed windows remain excluded.

| State | Visit1 /2 /3 window medians MiB | Visit3 sampled max MiB | Visit1→3 MiB | Proposed visit3 goal MiB | Remaining MiB |
|---|---|---:|---:|---:|---:|
|activity|100.80 / 101.72 / 101.81|103.03|+1.02|49.89|51.93|
|settings|92.07 / 103.71 / 104.13|105.05|+12.05|51.02|53.11|
|settings.activityData|117.26 / 118.25 / 118.56|118.78|+1.30|58.10|60.47|

Settings first→third grows12.05MiB, Activity data1.30MiB, Activity1.02MiB; allocation/lifetime attribution remains absent. Native permissions, asynchronous data completion, Clear/Delete/Export, real Health data and persistence latency are not covered. P1 next action: inspect actual allocation owners before proposing a retention change; retain these unchanged three-visit windows for a later matched comparison. The simulator was shut down/panel closed with empty booted/heavy readback; capacity passed directly to the authorized phone-install worker, whose device build is not performance evidence here.

## Evidence

Canonical primary root `tests/results/runs/performance-pages-ai-20261018/`: exact `settings-search-resources-v4-command.json`; `staged-source-settings-search-resources-v4/manifest.json`; raw `settings-search-resources-v4-90d5e59c.log`/context JSON; closed `settings-search-resources-v4/ui.xcresult`; summary JSON; preserved `settings-search-resources-v4-products/{One.app,OneUITests.xctest}`. Actual failed-method attachments and video are under `settings-search-v4-settings-attachments/`, extracted frames under `settings-search-v4-video-frames/`, hierarchy in `settings-search-v4-failure-hierarchy.txt`. The failure-only xcresult filter returned no matching attachments; a corrected exact-method export returned40 including the named diagnostic screenshot and screen recording. Raw originals remain unchanged, and QA journal indexes/archives the closed artifacts separately from app user Activity.

Repair artifacts: `settings-resource-repair-v4-command.json`, `staged-source-settings-resource-repair-v4/manifest.json`, raw `settings-resource-repair-v4-accd9227.log`/context JSON, closed `settings-resource-repair-v4/ui.xcresult`, summary JSON and preserved matching Products under `settings-resource-repair-v4-products/`. All three cohorts remain separate and journaled; the successful repair does not overwrite either earlier failure.

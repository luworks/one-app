# Bounded Mock build diagnosis — 2026-10-19

PR107 remains unaccepted; the <=300 second end-to-end CI goal is incomplete.

## Retained hosted failure

Run 39309706835, core-ui job 118256465124, source a491d1ae39ca061abdae1286aa72581e8c5011b4, integrated checkout 928e38a36cfb88adb91df4e1c3dfb75bb8d0492a. Artifact 12216311348 was retained as `iteration11-core-ui.zip` under the primary checkout's `tests/results/ci-hillclimb-20261019/`; 63,315 bytes, SHA-256 `c88e8860120a1a1c39db261cada1e43c6a29fca180220562daac8849131578d5`, matching GitHub's digest. Its extracted report, full 492,835-byte build.log and job log are retained and journal-indexed.

The build timed out at 600.656 seconds (runner elapsed 617.405), exit 124, executed 0 / missing 7. Preflight completed. The module transport missed; its save step was skipped after failure. The final compiler headings name TodayTestSupport, but there is no timestamp or CPU profile proving a hotspot, deadlock, or resource exhaustion. The log does not prove duplicate same-target source compilation. Toolchain directory names alone do not establish the installed version.

## Local measurements and provenance

The specified worktree initially matched a491d1a and was clean. No other native build process was active. Local Xcode reports 27.1 / 27A9275, Swift 6.4, arm64, 12 CPUs and 16 GiB RAM. All builds used the existing owned DD `tests/results/devtools/derived-data/48ea841ebb81c4956134`; no simulator was booted.

- Pre-sync ordinary TodayMock build: 72.860 seconds, passed, default explicit modules. SwiftCompile aggregate task time 75.547 seconds (overlapping task time, not wall time).
- Pre-sync CI-mode TodayMock build-for-testing: 74.040 seconds, passed. This reused the existing DD/SDK state and builds additional test products; it is not a controlled cold comparison with the ordinary build.
- A source comparison found that the failing integrated checkout adds Reminder edit contracts and the corresponding fake implementation. Main 324760c was merged normally as f8110c47d35d4eeb31731c887f35ac61ed62974b. The relevant Reminder contracts, implementation and TodayTestSupport then matched the failing integrated checkout.
- Post-sync CI-mode incremental build-for-testing: 25.852 seconds, passed. No pathological fixture compile reproduced. No compiler or product behavior change is justified by these measurements.
- The final diagnostic implementation's real incremental build-for-testing passed in 9.739 seconds. Its raw log contains elapsed dependency-phase markers and actual process/CPU-count evidence. A subsequent unchanged prepare command reused validated test products without invoking another native build. These are local incremental results, not hosted cache benefits or UI acceptance.

## Implemented repair and validation

The existing process authority now retains `DEV_BUILD_PHASE` elapsed markers and `DEV_BUILD_ACTIVITY` samples every 30 seconds in the same immutable native build log. Samples include CPU count, load and only the owned process tree's CPU/RSS/elapsed time and full compiler command. Probe failures are non-fatal; existing redaction applies. Partial logs and original failure exits remain authoritative. No compiler scheduling, concurrency, coverage selection, timeout, baseline or assertion changed.

`./dev build --scheme TodayMock --for-testing --timeout 180` reuses the existing test-product authority without device boot or test dispatch. Failed builds cannot publish products; unchanged source/toolchain/options/products can reuse them. Ordinary builds also retain Xcode's build timing summary.

`./dev test helpers`: 137 passed in 12.660 seconds. New regressions cover owned-tree filtering, real subprocess timeout/partial phase retention/redaction, and prepare-only failure propagation without publication/test execution. The first new timeout fixture failed because Python startup did not emit before its short deadline; it was replaced with a shell emitter while retaining all assertions, and the original failure log remains retained. `./dev lint` and `git diff --check` passed. No simulator UI, physical-device, or hosted success is claimed.

## Next bounded check

The hosted cause remains unknown. The next meaningful hosted attempt must inspect the new phase timeline and owned compiler process samples from the blocked build before changing compiler modes, fake services or timeout budgets. A progressing CPU-bound compiler, a sleeping importer and a stalled build service require different repairs. Do not interpret the last log filename as a hotspot or promote failed gates. Parent owns PR watches; this implementation created no watch, scheduler or timer. PR108/109 remain with their owners until the common CI blocker is actually repaired.

## Hosted comparison and staged startup experiment (iteration 12)

Run 39313515935 integrated b94dbefee388fc18db365dd93c678ac8742c237d. The full closed core artifact 12217298487 is retained as `iteration12-core-ui.zip` (59,245 bytes, SHA-256 `6a7a70eb21044aa5fc7adf244bfea50abe3806cffc52c5c90cfb1d35f559c38d`, matching GitHub), with complete extracted logs/report. The build timed out at 600.526 seconds, runner elapsed 618.934, executed 0 / missing 7. Required CI failed. Closed build, integration and snapshots artifacts and the complete core/build/prerequisite job logs are also retained in the same primary results directory.

The core log starts with activity samples, not compiler output. Its first 14 process probes (0.210–396.090 seconds) all time out after the existing two-second probe limit. On this three-CPU runner, one-minute load rises from 15.747 to 695.936. At 426.110 seconds the first successful probe observes xcodebuild plus a newly started `swift-driver -print-target-info`. No early process list, wait state, CPU attribution or simulator status was recovered. A late build-service lifetime cannot establish an earlier compiler hang. `ps` only includes descendants; absence from that tree does not prove a service was absent system-wide.

`DEV_BUILD_PHASE` timestamps are elapsed stdout-line observation times in the existing unbuffered pipe reader. The collector flushes its log each loop, but cannot guarantee when Xcode flushes its own stdout. Thus Resolve Package Graph at 424.785 seconds is not a measured 424-second package resolution. ComputeTargetDependencyGraph arrives at 437.503; first TodayCore SwiftDriver at 503.935. Neither evidence supports a TodayTestSupport type-checking hotspot.

Same-run comparisons, each on a separate hosted runner and therefore observational rather than a controlled timing benchmark:

- Build lane (no simulator boot): build adapter 130.334 seconds; Resolve marker 2.034, dependency graph 5.989; sampled one-minute load 17.925–28.188, all process probes successful.
- Snapshots (boot before build): build-for-testing 357.174 seconds; Resolve marker 115.766; sampled load 230.506–553.370, seven process probes timed out; all 6 expected tests passed.
- Integration (boot before build): build-for-testing 484.344 seconds; Resolve marker 194.554; sampled load 148.783–525.250, ten process probes timed out; all 13 expected tests passed.

All lanes already perform an explicit locked resolve before the adapter; core resolve took 37.378 seconds, snapshots 40.772 and integration 40.397. This does not account for the later hundreds of seconds before compiler output. The second Resolve heading alone does not prove duplicated network resolution. Build, snapshot and integration compiler metadata commands report actual Xcode build `27A9275`; the exact prerequisite check passed. The `Release_Candidate` directory spelling is not evidence of a different installed version or of the symlink target.

The measured common pattern is severe host congestion during cold simulator startup overlapping native build. Its process-level cause remains unknown. The next controlled code change removes that overlap in both existing native adapters: validate/build trusted products while the selected device is still shutdown, then boot once, wait for readiness and execute fresh selected tests. Failed builds retain their original exit/log/failed receipt and never boot or dispatch tests. Cached valid products still boot once and execute fresh leaves. Schemes, source/lock/SDK/architecture/configuration provenance, compiler options, deadlines, selection and fail-closed coverage gates are unchanged. No app or test-support Swift source changed. Remote speed improvement and the <=300 second goal remain unproven pending the new integrated run.

`./dev test helpers`: 137 passed in 17.519 seconds; `./dev lint` and `git diff --check` passed. The focused lifecycle review checked boot/cleanup ownership, original build failure propagation, cache-hit fresh execution and unchanged selection/provenance. No new local native build, simulator or physical-device run was needed to test this command-order change; the retained hosted comparison uses cold runners, not local warm-cache timings. Parent retains PR watches and owns remote acceptance.

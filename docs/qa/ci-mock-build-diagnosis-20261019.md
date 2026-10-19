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

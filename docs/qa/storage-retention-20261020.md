# QA storage audit and bounded retention

Baseline: origin/main `89ee93f9ad8d170a75e3005416e3f4e035bd5f57`, cleanly
fast-forwarded in the implementation worktree. The primary checkout and all other
worktrees were left untouched. Authorization: the owner's 2026-10-20 generated
storage audit/cleanup request; the narrow preservation exception is in AGENTS.

The initial primary `tests/results` snapshot contained 367,621 regular files,
471 xcresult bundles and 153 app products. Logical bytes were 41,905,894,114
(39.027905 GiB); allocated-file accounting was 42,894,553,088 (39.948666 GiB).
Devtools accounted for 22,525,231,104 allocated bytes / 221,886 files; runs for
11,733,377,024 / 63,412; archives for 5,738,541,056 / 34,742. This includes
important evidence and generated dependency/cache material, not 40 GiB of waste.
Full category counts, ages, largest bundles, duplicate groups and owner/resource
snapshots are retained in the pinned audit directory below.

286 run directories had 97 passed, 120 failed, 6 interrupted and 63 missing summary
statuses. A summary alone does not establish journal closure; missing metadata
remains uncertain. Every run category's newest file was under 2.44 days old.
The 7/30-day raw policy therefore deleted no raw results. Twenty-four exact app
bundle duplicate groups were identified by complete relative-file/size/SHA-256
manifests; every app product was preserved. The journal contained 135 coherent
archive revisions, which remain retained.

The applied plan removed only five compiler cache components of a retired owner:
ExplicitPrecompiledModules and SwiftExplicitPrecompiledModules beneath
Intermediates.noindex, CompilationCache.noindex, ModuleCache.noindex and
SDKExplicitPrecompiledModules. Each passed absent owner/PID/registration, free
host/cache locks, age, pin/reference, open-file and unchanged-manifest checks.
Products-only historical citations remain usable; identity-root citations protect
all descendants. Components containing pinned or cited descendants were retained.

Actual removal: 4,792 files, 799,099,562 logical bytes (0.744219 GiB), accounting
for 808,943,616 allocated bytes (0.753387 GiB). The after snapshot contained
41,117,634,704 logical bytes (38.293781 GiB) and 42,096,463,872 allocated bytes
(39.205387 GiB), with 362,884 files. New audit, journal and test evidence accounts
for the difference between gross deletion and net directory reduction. These are
file/block counts, not a measurement of physically free APFS shared extents.
All 471 xcresult inventories and all 153 product paths remained unchanged.

No devices, app/user Activity data, QA database/index rows, fixtures, existing
worktree caches, release maps, Products, raw logs, complete archives, current phone
receipts or rollback products were deleted. The pre-existing booted Today-UI
simulator was observed read-only and left alone.

The repo-native command is `./dev cleanup` (dry-run) or `./dev cleanup --apply`.
[QA retention](../../tests/qa/README.md#generated-storage-retention) specifies the
7/30-day archived-raw and 1-day retired-compiler policies, pins, reference checks,
fail-closed behavior and exact automatic trigger. The hook runs once after a
completed `./dev test ui/core/accessibility/release` returns and releases locks;
there is no timer/daemon. The primary checkout remains at its existing revision,
so it acquires this hook only when its owner safely updates and uses the new dev
entry. No native QA run was launched merely to demonstrate the hook.

Validation: `./dev test qa` passed 23 host tests; `./dev lint` passed SwiftLint,
Ruff and actionlint. One focused independent destructive-path review identified
five concrete issues: descendant pins, root/review references, stale qualifications,
control symlinks and deletion ancestry. All were addressed with temporary-tree
regressions. Two existing QA tests were corrected for the current ActivityStore
source path and TodayUITests target. No local native build, simulator UI or phone
test ran. The completed real apply has five planned and five deleted journal
entries, no partial entry; the journal's integrity_check returned `ok` afterward.
The post-apply dry-run found no remaining eligible candidates.

Compact machine summary: [storage-retention-20261020.json](../../tests/qa/evidence/storage-retention-20261020.json).
Persistent audit: `/Users/yuanlu/code/one-app/tests/results/storage-retention-20261020/`.
Per-component deletion manifests and immutable journal tombstones:
`/Users/yuanlu/code/one-app/tests/results/retention/storage-retention-efec87639cac44f2b2cd83dd7a1c5cba/`.
Existing archives and all raw files remain at their original paths.

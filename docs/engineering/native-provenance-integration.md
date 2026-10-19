# Native provenance integration

The implementation lives in `scripts/devtools/core.py` and `xcode_tests.py`.
The parent task owns wiring in `commands.py`, `ui.py`, and `cli.py`. This change
has not changed those callers or run any Xcode, Swift, or simulator operation.

## Signatures and compatibility

```python
fingerprint(root, *, sdk='iphonesimulator', architecture=None,
            configuration='Debug', tools=None, scheme='Today')
record_build(root, current, products, *, returncode,
             kind='build', xctestrun=None)
provenance(root, current, *, kind='build', xctestrun=None)
ensure_test_products(root, scheme, invoke, *, configuration='Debug',
                     sdk='iphonesimulator', architecture='arm64', flags=())
xcode_tests.run(root, contract, groups, *, only=(), timeout=600,
                locked=False, reuse=False)
```

All previous positional arguments remain valid. `scheme='Today'` preserves the
ordinary app default; it must **never** be used implicitly for TodayMock,
TodayWorkbench, TodayTests, or TodaySnapshotTests. Architecture defaults to the
host in `fingerprint`; builds that pass `ARCHS=arm64` must fingerprint explicitly
with `architecture='arm64'`. Explicit empty schemes are rejected.

Fingerprint schema 2 includes scheme, absolute worktree, current source bytes
(including dirty/untracked inputs and tracked deletions), dependency locks,
Xcode selection/version, SDK settings hashes, SDK, architecture and configuration.
Legacy schema 1 records are never accepted. Manifests use a scheme/build-kind
specific filename under this worktree's existing derived-data directory. They
are disposable provenance, never test evidence. Different schemes can coexist;
if they overwrite any shared product bytes, affected records become invalid.

`record_build` requires the caller's successful completed build result and a
fresh fingerprint taken before that build. It rechecks source bytes before
publication. The caller must also compare a fresh full fingerprint after the
build to detect a toolchain change. Pass complete `.app` directories rather than
only their executable when publishing ordinary builds, so resources, extensions,
Info.plist and signatures are guarded. Existing file products remain supported
for backward compatibility. A failure must never call `record_build`.

`provenance` returns `valid=False` for missing, stale, legacy, malformed,
foreign, symlinked, unreadable, empty or changed products. Call it with a freshly
computed fingerprint, under the same ownership as the operation using products.
A failed validation means rebuild or abort, never ignore the result.

## Parent caller updates

1. In `commands.build`, take the initial fingerprint **inside** host/DD locks,
   with the actual scheme, configuration, SDK and architecture. Compare it again
   after the successful build. For ordinary builds, record the whole app bundle
   with `kind='build'`. Match options in CLI planning and provenance inspection;
   a plan for another scheme must not accidentally inspect Today provenance.
2. For `build-for-testing`, prefer `ensure_test_products` with the real scheme
   and `locked_arguments(root)`. Alternatively publish the exact resulting
   `.xctestrun` using `record_build(..., kind='build-for-testing', xctestrun=path)`.
   A testing build must not publish an ordinary-app-only record. Do not map test
   schemes through the existing app executable-name dictionary.
3. Enable `reuse=True` on `xcode_tests.run` where cached native test execution is
   intended. Its default remains the existing `xcodebuild test`, which builds
   normally and does not consume provenance. Both modes retain group expansion,
   lane union, selectors, authoritative xcresult parsers, first failure, full
   bundle retention, shutdown and the existing four resource locks. Enabling
   reuse does not add a second test pass or a retry; the final full collection
   must still be invoked only once by its existing owner.
4. For Workbench, use `scheme='TodayWorkbench', architecture='arm64'` and whole
   app provenance inside existing `_locks` and cancellation ownership. Keep the
   registry's input/readiness contract. Use the same before/after fingerprint
   and no unchecked app reuse. `Native.run` currently returns log text; it is
   **not** directly compatible with `ensure_test_products`' result callback.
5. For the external UI E2E runner, validate and dispatch the returned exact
   xctestrun within the same DD/cache/name ownership. Do not assume merely
   supplying `--skip-build` or finding an `.app` proves provenance. The helper
   intentionally acquires no additional locks: avoid recursively locking the
   runner's cache/name locks. If a runner cannot consume the exact guarded
   xctestrun, keep its normal build path or fail closed until it can.

## Testing build and dispatch contract

`ensure_test_products` requires the caller to hold the host-heavy and worktree
DD locks across lookup, build, publication, validation and test dispatch. The
callback receives an argv list (never shell text), must execute synchronously
with durable evidence, and returns an object exposing `returncode`, `log`, and
optionally `reason` (`'exited'` for success). A `run_process` callback satisfies
this contract and owns timeout/cancellation. Use only dependency resolver flags
in `flags`; build identity options are explicit helper parameters.

A valid cache returns the stored exact xctestrun without building. A cache miss
runs `build-for-testing` once. Nonzero results raise `NativeBuildError`, whose
`returncode` preserves Xcode/timeout/cancellation status. A changing source or
successful process without usable products raises `ValueError`. No failure
publishes a new reusable record. Both cases prohibit test-without-building.
The adapter preserves a build failure exit code and always shuts its owned
simulator down.

After a successful build, exactly one scheme-prefixed `.xctestrun` must exist
in this worktree's `Build/Products`. Missing or ambiguous candidates abort;
there is no newest-file heuristic and no automatic deletion. Resolve ambiguity
through an owner-controlled new cache rather than deleting foreign products.
Both legacy target dictionaries and `TestConfigurations`/`TestTargets` plists
are parsed. Every target needs a real TestBundlePath. TestHostPath,
UITargetAppPath and DependentProductPaths are included when present. `__TESTROOT__`
and `__TESTHOST__` resolve to actual local products. Unknown placeholders,
foreign references and symlinks fail closed. Every referenced bundle is hashed
recursively, including resources/signatures, and the xctestrun itself is hashed.

Before dispatch, the adapter revalidates the fresh source identity, xctestrun
and all referenced products, then passes `-xctestrun <exact-path>` to
`test-without-building`. A source change during the test makes its report fail.
Zero executed leaves, malformed parser output and unsuccessful processes remain
failures even if a summary claims success. Raw logs, reports and completed full
xcresult files remain indexed by the existing primary-results QA journal.

No global build cache, shared DerivedData, new simulator, foreign-file deletion,
full-test retry, parser replacement or alternate group authority is introduced.

## Host verification

`tests/devtools/test_native_provenance.py` creates isolated Git repositories and
real small plist/product trees in paths with spaces; all native commands are
synthetic. It exercises unchanged reuse, scheme/kind separation, dirty source
and lock changes, resource changes, old-schema rejection, changed-source
publication, foreign/symlink/empty/ambiguous products, cancelled/timed-out builds,
zero/parser/test-timeout failures, exact test dispatch and simulator shutdown.
The existing foundation suite verifies actual Python-child process cancellation,
process-group ownership and handler restoration; those tests are reused.

The unmodified `test_xcode_tests.py` command-shape fixtures depend on a generated
workspace dependency lock in this checkout. If absent, their existing
`locked_arguments` gate rejects execution before synthetic Xcode. Verify those
fixtures with that host prerequisite isolated or mocked; do not change dependency
authority or weaken the gate to make a host test pass. Native acceptance remains
with the parent task's coordinated real build/test owner.

Verification for this implementation: 36 focused Python tests passed (15 existing
foundation, 13 new provenance, 8 existing Xcode adapter tests). For this combined
host-only run, `scripts.devtools.resolve.locked_arguments` was patched to return
its existing `FLAGS`; the generated workspace lock is absent in this isolated
checkout. The gate itself was not edited, bypassed in production, or validated
by that mock. An earlier unpatched adapter run failed at that prerequisite.

The combined command and complete output are indexed in QA session
`native-provenance-20261018`, primary checkout
`tests/results/activity.sqlite`. Raw log:
`tests/results/devtools/logs/835dc67f9b784927ab7ee0227069d0c3.log`.
No Swift, Xcode, simulator or physical-device acceptance was performed here.

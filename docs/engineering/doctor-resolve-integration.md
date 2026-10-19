# Doctor and strict dependency resolution integration

Implemented against `425e527bd0508dad14bc047d218f519a99bb4584`, a descendant of the requested
`c05da94` reconstruction baseline. This lane owns only the two new modules, their
host-only tests and this integration note. CLI, commands, core, bootstrap,
project specification, pins and runtime installation remain parent-owned.

`doctor.inspect(root)` returns `{ok, checks, read_only}`. Each named check has
`status` (`pass`, `fail`, or explicitly `unverified`), `required` and `expected`;
observations and actionable missing paths appear in `actual`/`detail`. The CLI
should print this object and return `0 if result['ok'] else 1`. It must replace
the old truthiness-based Xcode check rather than merge it as a second authority.

The doctor reads selected Xcode metadata and checks 27.1 / 27A9275, actual iPhoneOS
and iPhoneSimulator 27.1 SDK metadata, and the selected toolchain's Swift 6.4 and
bundled formatter version. An optional formatter receipt SHA-256 is verified
when present; its absence is unverified, never a pass or a claim that `main`
maps to upstream 604.0.0. Bootstrap's existing `plan=True` path authenticates
installed CLI receipts, all file hashes/modes and architecture. Verified CLI
paths receive read-only version probes. Mise itself is never invoked, even
for a version check, because that can create state. Its installation check is
optional; generator/linter, runtime and gem prerequisites are required.

Runtime checks compare `.mise.toml`, `mise.lock`, `Gemfile`, `Gemfile.lock`, the
release tool lock and the fastlane manifest pin. They use explicit local Ruby
3.3.12 and Python 3.14.8 paths, RubyGems ABI directory 3.3.0, Bundler 4.0.16 and
fastlane 2.241.1 gem entrypoints. They bypass shims, mise and shell startup,
strip injected runtime hooks, and disable fastlane update/usage checks. They
never install missing prerequisites. Python 3.9/3.10 uses the existing `tomli`
dependency; an absent TOML reader fails the runtime checks explicitly.

Doctor creates no evidence, directories, ownership files, cache or simulator
state. It does not inspect credentials, profiles, signing stores or user
configuration. Dependency cache completeness, network, simulator runtimes and
release readiness remain explicitly unverified offline. Required failures
control `ok`; optional failures remain visible without claiming readiness.

`resolve.run(root, scheme='Today', timeout=600)` returns the actual command exit
code, or raises an actionable prerequisite/drift error. Parent CLI should add
`resolve --scheme` with `resolve.SCHEMES` choices and call this function. Supported
schemes are Today, TodayMock, TodayWorkbench, TodayTests and TodaySnapshotTests;
each must also exist in the versioned project specification. The current
`ios/project.yml` is JSON-compatible and is parsed without executing YAML tags.

Resolution requires the existing versioned `ios/Dependencies/Package.resolved`
v3 authority first. SnapshotTesting's version/revision must agree with the tool
manifest and its exact project pin. Missing authority fails before generation
or state writes. Missing generated project uses the existing `commands.generate`
under canonical host and worktree-derived-data locks. A dirty ignored workspace
lock is restored from the authority before execution. The argv is:

```text
xcodebuild -resolvePackageDependencies -project ios/Today.xcodeproj -scheme <scheme>
  -derivedDataPath <canonical worktree-owned DD>
  -disableAutomaticPackageResolution
  -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates
```

Execution reuses `commands.execute`, hence its canonical process-group timeout,
redaction, journal and retained raw-log behavior. Explicit resolution may use
network and populate dependency caches. No heavy command was executed in this
implementation lane. A successful process is accepted only if dependency
identities, locations, kinds, complete state, revisions and versions equal the
authority. The authority must remain byte-identical during the command. The
ignored workspace lock is restored byte-for-byte after success, failure or
exception. The authority is never a write destination. There is no implicit
lock-update mode; a future explicitly authorized lock-update workflow belongs
to the parent and must separately review source/manifest/authority changes.

For ordinary build and Xcode test argv, parent must append
`resolve.locked_arguments(root)` **inside existing host/DD ownership**, before
launching any Xcode process. It reads and validates the authority/source pins
and full semantic equality of workspace JSON, including originHash, then returns
all three flags above. Missing or dirty workspace state fails with a request to
run resolve; the helper writes nothing. Existing Swift package-only unit tests
have their own dependency authority and should not receive Xcode flags.
Generation should continue restoring the authority to the ignored workspace.

Validation: 23 host-only mock tests passed using
`python3 -B -m unittest discover -s tests/devtools -p test_doctor_resolve.py -v`.
Coverage includes spaces, absent prerequisites, Xcode/SDK mismatch, optional hash
failure, sanitized probes, all supported schemes, unknown schemes, source-pin
and dependency drift, originHash drift, duplicate pins, dirty ignored workspace,
host contention, missing project/authority and command failure/timeout recovery.
The initial fixture assertion failed on macOS `/var` versus `/private/var`;
canonicalizing the fixture fixed it without weakening behavior assertions.
Existing local Ruff passed the three new Python files under repository rules;
it was not installed or asserted to be the pinned bootstrap Ruff.

Canonical QA journal session: `doctor-resolve-20261018-host-mocks` in the primary
checkout's `tests/results/activity.sqlite`. Retained successful raw mock-test log:
`tests/results/devtools/logs/2278d051783a403499e60b1e960bab3f.log`.
There is no actual Xcode/Swift execution, dependency resolution, runtime version
probe, install, simulator UI, physical-device or signing acceptance here. Parent
CLI wiring and integrated command acceptance remain outstanding by ownership.

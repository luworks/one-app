# Today CI contract

Implemented from actual local base `67ec48f3bab0f093a9a871541283b823bed1dbdd` on 2026-10-18. Read AGENTS, CLAUDE, README, ios/README, the four operations/agents policies and migration-plan before implementation. This lane owns only `.github/`, `scripts/ci/`, `tests/ci/` and this document. No project/package/signing/source changes, PR, merge, dispatch, timer or root messages were performed.

## Workflow and required check

`Today CI` runs on every pull request and merge-group integrated ref, every main push and explicit manual dispatch. There are no workflow path filters. Default checkout uses the event's integrated `github.sha`, not a PR head; the adapter independently compares HEAD to GITHUB_SHA. Deleted and renamed paths are retained by NUL-delimited `git diff`; unavailable base/history or empty diff means full selection. All checkouts disable persisted credentials; permissions default to contents:read. There is no `pull_request_target`, personal runner, committed UDID, secret dependency, private upload destination or distribution implementation.

Configure the repository ruleset to require **today-required** for PRs and merge queue. YAML does not install repository rulesets. This always-running job depends on every other job and rejects missing, unknown, failed, cancelled or unjustifiably skipped jobs. Only release-on-non-main-push and unselected manual lanes have event-defined skip exemptions. A selected protected-release dispatch away from main fails aggregation. Workflow cancellation can prevent even an always job from completing; it must never be treated as a passing required check. No continue-on-error or path-filter pending checks are used.

Normal jobs: helpers, exact hosted prerequisite, format, lint, business unit, integration, app+extensions build, core UI, affected snapshots. Main additionally runs Release cross-module validation. Manual dispatch explicitly selects extended, sanitizer, performance or protected-release; routine PRs never run the full suite. Each hosted VM owns its own adapter-created simulator and derived data; the adapter must serialize UI operations within that VM and shut down its simulator. No extra local build/runner was started here.

`protected-release` is validation only, restricted to manual main and environment `release-validation`. Before enabling it, an administrator must configure actual required reviewers with prevent-self-review. The read-only API guard checks that rule and fails if protection/read access cannot be verified. The job has actions:read solely for that check; no signing/distribution credentials or write permission. This lane does not configure remote environments or grant production authority. See the official [environment API and protection schema](https://docs.github.com/en/rest/deployments/environments#get-an-environment).

## Integration-owned command adapter (planned, not executed)

Current `./dev` supports only help, doctor, inventory and plan. Integration must implement this single dispatch contract; this CI lane deliberately has no replacement build/test scripts:

```sh
./dev ci <lane> --selection <selection.json> --output <fresh-output-directory> \
  --sha <integrated-sha> --synthetic --no-distribute
```

Every lane must perform real work and emit `report.json` in its output directory. Unsupported adapters, absent reports, zero execution and incomplete results fail. Do not return fabricated counters for a successful subprocess or discovery-only run. The executable report contract is in `scripts/ci/policy.py`:

```json
{"sha":"<integrated-sha>","lane":"business","status":"passed","executed":123,"failed":0,"cancelled":0,"missing":0,"synthetic":true}
```

Counters are nonnegative integers; executed must be positive. For tests, executed counts actual finished tests and missing includes discovered/selected tests without final results. For format/lint/build/release, it counts actual checked files/products/invariants. The adapter must derive these from authoritative runner results, preserve command exit failure and write a failed report with synthetic provenance for completed failure evidence. CI never accepts cancelled/missing test outcomes as success.

Lane responsibilities:

- `format`: pinned Apple swift-format read-only check; no rewrite.
- `lint`: pinned SwiftLint and relevant script/workflow checks, read-only.
- `business`: affected business/domain unit tests.
- `integration`: affected module/store/extension boundary tests using synthetic fixtures only.
- `build`: app, widgets and share extension, with signing disabled and explicit product existence checks.
- `core-ui`: bounded representative Add/Apply/Undo, fixed-event versus flexible-task and extension-import journeys. Integration owns actual discovered method IDs; do not invent selectors or silently accept missing methods.
- `snapshots`: affected registered scenes using the shared deterministic registry/capture path and reviewed baselines; preserve reference/actual/diff and fail missing baselines. If selection contains no affected scenes, run one registered core baseline check so a zero-result report never masquerades as snapshot acceptance.
- `release`: Release cross-module build plus graph, link-map and resource checks excluding Workbench, mocks, fixtures and test products. Debug/Release optimization remains separate from Mock/Live dependency selection.
- `extended`: explicitly requested full extended test collection; `sanitizer`: explicitly requested supported sanitizer checks; `performance`: explicitly requested stable benchmark/budget checks. Unsupported sanitizer/runtime must fail with the concrete prerequisite, not skip.
- `protected-release`: guarded no-distribution Release/archive validation; never sign, export, upload to TestFlight or distribute. Any future signing/distribution capability requires its own owner authorization and implementation.

All adapters must honor `--synthetic`, disable live system sync and generate only fictional data in ephemeral stores. No app Activity/user database is input to CI. Run IDs and logs/results must refer to the exact SHA; no reuse of results from another commit. Integration must connect the existing QA journal/runner with a CI-local output root, without ever interpreting this workstation's canonical QA path as a hosted input.

## Selection from the real dependency graph

`policy.py select --output <file>` reads `ios/project.yml` with Ruby standard-library safe YAML and evaluates each present Package.swift with `swift package dump-package` (no build, no dependency resolution command). It constructs target edges, maps local package products and follows reverse transitive dependencies. Package file/resource ownership is deliberately conservative: any package source selects its package targets and their consumers. Xcode target sources and target/product dependencies come from the actual spec, never guessed module names or Swift imports.

Missing project spec (the current baseline), malformed manifests, unresolved products/edges, external SPM product edges, XcodeGen includes/templates/aliases or unresolved source paths produce `mode=wide`, `all_targets=true` with an explanation. Unknown paths, shared code, model/schema, config, project/manifest/lock and tooling changes also select wide. An empty targets array with all_targets=true means **all discovered runtime targets**, never “nothing to test.” Adapters must treat this flag as authoritative and discover the complete target/test collection themselves; they must fail if that discovery yields zero. Source paths unaccounted for by the graph fall back wide. Documentation-only selection may be empty but the baseline core checks above still run.

Synthetic CLI inputs avoid Swift/Ruby/process work and are suitable for testing changed-path scenarios:

```sh
python3 scripts/ci/policy.py select --changed-json changed.json --graph-json graph.json --output selection.json
```

`changed.json` is a string array. `graph.json` maps target IDs to `{"paths":["ios/Feature"],"dependencies":["domain-id"]}`. Fixtures live inline in `tests/ci/test_policy.py`; they are versioned host-policy inputs, not UI datasets. Helpers use only unittest and the Python standard library; no hosted builds or actual workflow dispatch are required.

## Official upstream observations and exact pins

Verified on 2026-10-18 through primary upstream raw action definitions and `git ls-remote` tags:

- [actions/checkout v6](https://github.com/actions/checkout/tree/d23441a48e516b6c34aea4fa41551a30e30af803): `d23441a48e516b6c34aea4fa41551a30e30af803`.
- [actions/upload-artifact v6](https://github.com/actions/upload-artifact/tree/b7c566a772e6b6bfb58ed0dc250532a479d7789f): `b7c566a772e6b6bfb58ed0dc250532a479d7789f`.

These are actual upstream tag resolutions and their `action.yml` files were inspected; tags can move, so workflows use full commits. Both use Node 24, supplied by the hosted runner. Dependabot uses supported ecosystem IDs `github-actions`, `swift` and `bundler`, per [GitHub's ecosystem table](https://docs.github.com/en/code-security/reference/supply-chain-security/supported-ecosystems-and-repositories). Swift currently watches `/ios`; integration must add directories if manifests move. Bundler is a planned entry: no root Gemfile or lockfile exists at this baseline, so it cannot produce meaningful updates until integration adds them. CODEOWNERS is the actual `@luworks`, with no invented team.

The [hosted-runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners) lists `xcode-27` as hosted arm64 (public preview). Its [official image manifest](https://github.com/actions/runner-images/blob/ee1ff4569e381a9649b400338bdc8ceb7e18a80e/images/macos/xcode-27-arm64-Readme.md), image `20261012.0260.1`, lists macOS 27.0.1, Xcode 27.1 build `27A9275` at `Xcode_27.1_Release_Candidate.app` with `Xcode_27.1.app` symlink, iOS 27.1 device/simulator SDKs and an installed iOS 27.0 runtime supporting iPhone 18 Pro Max. **No inventory-level prerequisite is missing on that preview image.** This is published inventory, not a workflow execution or stability guarantee. Standard `macos-26` image `20260907.0351.1` lists Xcode 26.6 and iOS 26.x and does not satisfy this contract.

The workflow explicitly sets DEVELOPER_DIR to the 27.1 symlink and probes architecture, exact Xcode build, both 27.1 SDKs and available 27.0 runtime. Any image rollout, missing symlink/runtime or beta/default substitution fails prerequisite with an actionable message, then today-required fails. Never silently replace it with a personal Mac runner or lower toolchain. Preview availability is a remaining operational dependency; hosted execution is unverified.

## Artifact boundary and local evidence

Only a fresh lane output with a matching SHA/lane and explicit `synthetic:true` provenance can be staged. Allowlisted logs, result JSON/text, PNG diffs, crash reports and whole completed xcresult contents are copied after the command exits. Symlinks and hidden files are rejected/excluded; SQLite, app/product archives, profiles and arbitrary workspace files are excluded. Text is scrubbed for common token/password/authorization patterns and personal home paths. Binary xcresult/PNG cannot be generically redacted: synthetic-only adapter isolation is mandatory, and no real personal data may enter that output. The scrubber is defense in depth, not certification that arbitrary real data is safe.

Publication uses a completed staging-directory rename, never a live xcresult or partial copy. `manifest.json` links paths, sizes and SHA-256 hashes to the integrated commit; GitHub artifact names include lane, SHA and run attempt, retained for seven days. Failed runs may upload completed synthetic failure evidence. Missing/untrusted report means no upload and a failed job. No private network upload is configured.

Local development and test history is recorded in `/Users/yuanlu/code/one-app/tests/results/activity.sqlite` using `tests/qa/journal.py`; durable logs are under `tests/results/runs/ci-reconstruction-20261018/` in that primary checkout. No app database was accessed. Final verification counts and command exits are recorded there and in the implementation handoff. Build, Swift tests, simulator UI, device behavior, real Actions execution, repository ruleset activation and final dev adapters remain unexecuted in this lane.

Validation uses actionlint 1.7.12 with shellcheck/pyflakes disabled (no shell/Python checker evidence claimed). Its runner catalog predates xcode-27, so `.github/actionlint.yaml` narrowly allows that officially documented hosted label; this does not configure a self-hosted runner.

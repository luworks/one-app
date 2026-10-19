# Release tooling evidence

Implementation base: `395376bb126fd7415ac6b44eee91b796eb8ca60c`, parent
`e022a7a46a4aa0d0a604886c139a7dd2c050fed1`. The additional baseline commit contains
reconstruction ownership/plan documentation. The initial worktree was clean on
`t3/today-release-preflight`. No integration/configuration/source files changed.

Focused checks on 2026-10-19 UTC:

| Check | Result | Meaning |
| --- | --- | --- |
| Bundler 4.0.16 `lock`, Ruby 3.3.12 | Exit 0 | Actual RubyGems dependency resolution; generated lock includes checksums |
| Same Bundler `platform` | Exit 0 | Lock matches the resolver's Ruby and arm64-darwin-25 platform |
| `python3 -m unittest discover -s tests/release -v` | 20 passed | Synthetic filesystem fixtures and strict mocked Apple commands |
| `ruby -c fastlane/Fastfile` | Syntax OK | Ruby syntax only; not an installed Fastlane execution |
| Live Python preflight after commit | Expected blocked | Default Ruby 2.6.10 differs from lock; generated Today project absent; actual team/profiles not supplied |

The live preflight JSON and exit status are retained in canonical results; the
expected row above is not a claim that real signing readiness passed. Unit positive
paths deliberately require mocked CMS/signature/Mach-O checks. Guard tests stub
build/export/upload to abort if any mutating method is reached without a token.

One focused source review addressed concrete issues together: actual Bundler 4
lock indentation, independent fixture copies, Apple trust and leaf-certificate
membership checks, legitimate product-only keychain wildcard expansion, all-target
Release settings inspection, export file integrity, and durable Fastlane report
placement. Earlier test failures exposed the lock parser and shared fixture alias;
the assertions were preserved and the corrected final focused set passed.

No `bundle install`, installed Fastlane lane execution, real archive/export,
signing mutation, certificate creation, purchase, Apple login/upload, phone install,
Swift test, Xcode app build, simulator or device run was performed. Real archive
validation, actual Fastlane execution, Apple-service acceptance and integration of
the generated project remain unchecked. The optional offline scanner is unavailable.

Raw logs: primary checkout `tests/results/today-release-preflight/`:
`unit.log`, `ruby-syntax.log`, `bundler-platform.log`, `preflight.json`,
`preflight-exit.json`. Existing QA journal session: `today-release-preflight`,
primary `tests/results/activity.sqlite`. No runtime database or large evidence
artifact is committed. Setup/research and final check results are recorded through
`tests/qa/journal.py`; no secondary ledger, timer or PR was created.

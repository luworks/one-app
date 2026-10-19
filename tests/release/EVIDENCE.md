# Bounded reconstruction evidence

Base: `ee0a478f6df481dfbe4b095599837bc1af1f1600`.
Final host verification session: `release-integration-20261018T204616`.

- `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests/release -v`:
  30 tests passed, 1.239 seconds. All signing, UUID, manifest/graph command data
  and archive/export contents are synthetic or mocked. Ruby DSL tests execute
  only fake Fastlane build/upload methods and dummy local directories/maps.
- `ruby -c fastlane/Fastfile`: Syntax OK.
- `git diff --check`: exit 0 before this evidence-only documentation addition.
- Focused source review checked identity separation, command-scoped signing,
  archive/distribution authorization ordering, canonical evidence paths,
  generated lock authority handling and source-versus-artifact boundaries.

Raw logs are retained and SHA-256 indexed by canonical QA SQLite under
`/Users/yuanlu/code/one-app/tests/results/reconstruction/release-integration-20261018T204616/`:
`host-tests.log`, `ruby-syntax.log`, `diff-check.log`.
The QA journal is `/Users/yuanlu/code/one-app/tests/results/activity.sqlite`.

Implementation iterations before the final run repaired a Python default-argument
mistake, an inverted notice symlink predicate and an xcconfig key parser that
initially rejected mixed-case platform keys. Final tests include the affected
success and refusal paths. No prior failure is represented as acceptance.

No actual source graph command, Xcode build/archive, keychain identity inspection,
profile/account write, signed export, simulator/device journey or upload ran here.
Root must run the documented local archive flow on the clean integrated commit.
The source signing mode and missing bundled license resources remain integration
prerequisites described in `docs/engineering/release-integration.md`. This evidence
is host-tooling acceptance only; distribution readiness remains unverified.

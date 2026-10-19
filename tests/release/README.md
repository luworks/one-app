# Release fixture catalog

`fixtures.py` builds all required synthetic inputs into a fresh temporary test
directory from versioned Python dictionaries: archive/bundle Info plists, three
source entitlements, deliberately invalid certificate/profile/executable/dSYM
bytes, mocked signing metadata, UUID mappings and generated-project placeholders.
No required fixture lives solely in `/tmp`; the builder is the source of truth.
All fixtures are synthetic and must never be uploaded or called real archives.

`test_release.py` uses a strict command mock for release checks. Positive archive
and export tests succeed only because Apple signature/CMS/Mach-O commands are
mocked. Negative paths preserve those checks: unsigned fake data, certificate
mismatch, entitlement/identity/version/extension errors, tool/git drift, missing
signing, content/provenance changes, wrong/missing/orphan UUIDs and unsafe IPA
entries are blocked. The Ruby DSL harness executes only the authorization checker
and stubs archive/export/upload methods to abort if reached without authorization.

Run `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests/release -v`.
These are tooling unit tests, not Swift logic, Xcode builds, real signing, simulator
UI, device, actual Fastlane build/export, or Apple-service acceptance evidence.

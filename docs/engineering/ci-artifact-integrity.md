# Closed synthetic CI artifact integrity

Base: `cd64ae72af54a0eb77bb96883fba70c1c8d35f8c`. Ownership is limited to
`scripts/ci/run.py` artifact helpers, `tests/ci/test_artifact_integrity.py`, and
this document. No workflow, runner, application, signing or upload change is included.

`stage` previously dropped hidden xcresult files and sanitized JSON/text inside
bundles. It now copies every inventoried bundle byte without decoding or rewriting,
including hidden files, binary stores, JSON and empty directories. The final
manifest hashes the actual staged bytes and records source hashes/lengths plus
`identity` or `sanitize-v1` transformations. Text outside bundles is redacted;
first-failure and retry logs remain separate inventoried evidence. A failed test
report can be staged without being treated as a successful CI result.

## Required producer receipt (integration gate)

The producer must own a fresh, dedicated synthetic output directory, wait until
all processes/writers and shutdown finish, hash the closed files, and atomically
write `report.json` last. Never emit this receipt for a live bundle, user export,
workspace, private data, or execution with secrets available to untrusted code.
The report's existing `sha`, `lane`, and `synthetic: true` fields remain required;
SHA must be the full 40-character integrated commit. Add this field:

```json
{
  "artifact_provenance": {
    "version": 1,
    "owner": "today-ci",
    "run_id": "today-integration",
    "sha": "cccccccccccccccccccccccccccccccccccccccc",
    "lane": "integration",
    "closed": true,
    "synthetic": true,
    "secrets_available": false,
    "bundles": ["native/TodayTests.xcresult"],
    "files": [
      {"path": "attempt-1.log", "bytes": 123, "sha256": "<actual SHA-256>"},
      {"path": "native/TodayTests.xcresult/.metadata", "bytes": 456, "sha256": "<actual SHA-256>"}
    ]
  }
}
```

The example is abbreviated, not an executable receipt. `run_id` must equal the
owned output directory's basename (the current wrapper uses `today-<lane>`).
`files` must include every regular file in each declared bundle, hidden files
included, and every other generated artifact intended for publication. Omit
`report.json` itself to avoid circular hashing; stage includes and hashes it
implicitly. `manifest.json` is reserved for stage. Empty bundle directories are
retained; empty bundles are rejected. No absolute paths, traversal, overlapping
bundles, duplicate files or symlink entries are allowed. Outside bundles, only
explicit `.log`, `.txt`, `.json`, `.jsonl`, `.crash`, `.ips`, and `.png` files are
accepted. Undeclared unrelated files are neither read nor uploaded. Only declared
bundle directories are walked, never the whole output/workspace or private paths.

**The adapter at this base does not emit this receipt.** Its `safe_artifacts`
function preserves bundle bytes but is not an ownership/closure attestation.
Integration must emit this contract from the trusted producer after closure;
copying `synthetic: true` from a caller is insufficient. Until then workflow stage
fails closed. No compatibility fallback infers ownership or closure. Updating
`ci_adapter.py` and legacy `test_policy.py` fixtures is outside this task's ownership.
The receipt is a producer trust boundary, not cryptographic authentication; it
cannot make an untrusted runner or a self-attested live bundle safe.

## Rejection and publication

All inventoried source hashes/lengths are checked before copying and again before
publication. Bundle inventory and directories must remain unchanged. A bounded
byte scan detects credential assignments, GitHub tokens, bearer credentials and
private-key headers in declared bundle files. A hit rejects publication; bundle
bytes are never redacted to manufacture a complete-looking result. This heuristic
is not proof that arbitrary secrets are absent; the trusted no-secret synthetic
runner requirement remains mandatory. No environment secrets or user paths are
searched to populate the scanner.

Successful staging renames a fresh sibling `<destination>-staging` directory to
the publication destination only after verification. On rejection, original
closed evidence and logs remain intact; a partial staging directory may remain
for diagnosis. Upload **only the exact publication destination**, never a glob
that includes staging, a workspace, or the original results directory. Do not
archive, move or finalize a live bundle. This task performs no uploads or remote
CI actions.

## Host evidence

Versioned inline synthetic fixtures live in `tests/ci/test_artifact_integrity.py`.
Run `python3 -m unittest discover -s tests/ci -p test_artifact_integrity.py -v`.
Paired coverage checks complete hidden/binary/JSON bundle preservation versus
external log redaction and output hashes; first-failure retention; missing/live/
wrong-owner/SHA/lane/secret-runner rejection before bundle reads; incomplete
inventory; changed source bytes; blocking secret rejection; symlinks; traversal;
unowned private-file exclusion; destination safety; and mutation during copying.

These are host Python checks, not real xcresult parser, Xcode, simulator, device,
hosted CI or upload acceptance. The existing legacy stage success fixture uses
short SHA `abc` and no receipt, so it requires an owner update for this stricter
contract. Existing symlink fixtures without provenance also need a valid receipt
to reach the path guard; the new tests cover symlink rejection with valid provenance.

The wrapper writes its own `command.log` after the adapter returns. Integration
must resolve that ownership before sealing inventory: use a distinct producer log
name and arrange a trusted final receipt after the wrapper-owned log closes, or
change the wrapper's log lifecycle under its owner's scope. Do not hash an adapter
`command.log` and then overwrite it in the wrapper; hash mismatch intentionally
rejects publication.

Local evidence session: `ci-artifact-integrity-20261019T-host`, canonical directory
`/Users/yuanlu/code/one-app/tests/results/runs/ci-artifact-integrity-20261019T-host/`.
Final focused checks: **12 passed** (`review-host-tests.log`); scoped Ruff and diff
checks passed. The earlier full CI host collection ran 63 tests with 62 passing and
one legacy fixture error before review repairs. The final focused compatibility
run (`policy-compatibility.log`) has 23/25 passing, with the two legacy provenance
fixture failures described above. This is not an all-green host collection claim.
All logs, including earlier failures, are retained and indexed through the canonical
QA journal. No remote CI, network, upload, Swift/Xcode build, simulator or watcher ran.

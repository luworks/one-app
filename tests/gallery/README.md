# Gallery adapter verification

Base: `3b3a9bfaed35fbbfa6fc425b13690c2966cfe165` (clean delegated worktree).
Owned paths: `scripts/gallery/`, `tests/gallery/`, `docs/engineering/gallery.md`.

Run `python3 -m unittest discover -s tests/gallery -v` from the repository root.
`test_gallery.py::png` contains the reusable inline synthetic PNG fixture. It is
only test data, never a gallery renderer or production fallback.

The ten focused tests exercise capture status and retained image provenance,
changed/unchanged bytes (including changed pixels followed by callback failure),
dependency and lock watching, mtime/content detection, missing inputs,
mid-capture changes, PNG truncation, strict manifest validation, fixed native
argv and process cancellation forwarding, real loopback HTTP route/auth checks,
mutation/CSRF/Host/CORS rejection, duplicate JSON fields, output arguments and
traversal rejection. Tests run no native app, simulator, Xcode or downloads.

Final command output is retained and indexed through the canonical QA journal,
session `gallery-adapter`. See that session for immutable log paths and SHA-256.
The CLI `--help` entrypoint was also checked. A focused implementation review
checked route reachability, trust boundaries, single executor/cancellation,
immutable evidence indexing and last-good freshness transitions.

Native TodayScenes manifest generation and `./dev ui capture/open` remain root
integration. Native capture, source edit to new image, direct interaction,
simulator/build and physical-device acceptance were **not executed** in this lane.
See `docs/engineering/gallery.md` for the receipt and callback contract.

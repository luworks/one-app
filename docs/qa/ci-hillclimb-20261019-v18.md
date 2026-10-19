# CI closure and next provenance change

PR114 head `cc12889c8027b8b1a1ff262df3b88fb138a84507` passed run
39328669279 on integrated `bda474a3fa36120ec1cecb87ff00aabd2664fa1b`.
Parents were production main `43d28166333a833bcac1c641312951e959cfd990`
and that head; integrated/head trees matched `fd613d044d0c4ffa93bb518298fefde557e27faf`.
Normal merge produced `8e6728470d1791d1a2b664d2a946c9ff4f69eaab` and
main run 39332217914. Main Release/aggregate acceptance remains separate and
pending. PR114 watching was removed after merge. No branch rule was changed;
GitHub reported no required contexts or applicable rules.

All seven independent lane receipts matched the integrated SHA. Format checked
332 inputs, lint three tool invariants, build three production executables.
Business expected 695: 691 passed plus four explicitly allowed benchmark/export
skips (coverage incomplete). Integration 23/23, snapshots 6/6, UI 7/7 passed
without skips, missing/unexpected leaves, cancellation or parser errors. All
three complete xcresults were reopened and independently reparsed against their
accepted selection. Two archive digests matched GitHub; every ZIP entry passed
CRC and all manifest file sizes/hashes matched. Bundle transformations were
byte identity. One fresh TodayCI build-for-testing and three fresh
test-without-building commands were retained; consumers used the same xctestrun
and source fingerprint. No cached test results supplied acceptance.

Creation 21:35:21 UTC to required completion 21:59:45: **1,464 seconds**.
Native queue was 99s and job 1,343s; host queue 502s and job 138s.
Cold build 185.627s, resolve 31.065s, integration command/session/body
335.597/49.447/8.382s, snapshots 91.814/38.971/6.197s. UI runner was
464.059s, session 373.170s, bodies 350.847s; streaming command wall time was
not separately retained. Native module restore missed (0.413s); save 4.434s;
upload 2.743s. Host business 89.390s, format 10.787s, lint 1.493s,
selection 13.322s, upload 2.140s. Full job/setup costs remain in raw API/logs.
PR110 was 2,258s; different queue/cache profiles prevent attributing the 794s
wall difference solely to consolidation. Build plus UI bodies alone exceeded
536s in this cold configuration run. **300s remains unmet.** Ordinary useful
Swift-only and warm profiles remain unmeasured; hosted queue is not controlled.

Next change removes repeated full-product reads inside a single provenance
validation. Xctestrun reference resolution and digest comparison now share the
hashes just read by that call. Every publication/dispatch still gets a new map
and fresh content hashes; no mtime/size trust, persisted hash cache or result
cache is introduced. Native phase markers expose ensure/dispatch-validation
costs next time. The unexplained adapter overhead motivates this bounded
change; its wall-time benefit is unmeasured. Cold simulator startup and UI body
costs remain. No selectors, assertions, skip rules, workflow, product sources or
signing changed.

`./dev test helpers`: 147 passed, 15.139s body /15.286s command;
`./dev lint` and `git diff --check` passed. A same-size/same-mtime resource
mutation still rejects reuse on the next validation. Existing symlink, missing,
foreign-product, source and toolchain regressions passed. Focused source review
confirmed the hash map is local to one validation. No local native build,
simulator, full suite or phone run was repeated.

Raw evidence: primary checkout `tests/results/ci-hillclimb-20261019/v18-*`,
including closed artifacts, archive integrity, independent raw revalidation,
job API, costs and helper/lint logs. Earlier failures, product gaps and original
Ask/J3 evidence remain unchanged; this work closes no physical-device or
product-functional acceptance gap.

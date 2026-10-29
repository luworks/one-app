# Submitted-action authorization repair (PR216, draft)

## Frozen observation

Source `829dc4a9efe1ff2dfbd2c00e497a12e2734b6fa3` includes PR217's independent
AlarmKit-denial fix. It does not include this cardinality repair. Its Live app
archive, manifest and install receipt are retained under primary
`tests/results/intelligence-eval-20261028/main217-integration-20261029/`.

The original development fixture reconciles exactly to 24 cases / 27 turns in
`live-product-round5-20261029/original-development-pre-cardinality-cohort.json`.
These are one repetition, not repeated acceptance rates. The frozen multi-item
input auto-saved one merged reminder at 09:00, retaining the second action and
15:00 in its title. Trace attribution was `rule_direct_grant_selected`, with
zero SDK calls. The actual editor confirmed the merged record; exact receipt
Undo removed it. This is an authorization/validation failure independent of
model quality, model-call attribution and PR217. Do not change the expected two
previews or relabel this as successful generation.

`pre-cardinality-cleanup.json` and `multi-item-unsafe-direct-write-review.json`
retain the cleanup and raw UI/call evidence. All synthetic test writes were
undone except the two explicitly retained dentist setup records. The owned
Today-Dev-e2ad9a44 simulator was shut down; its data/denied permissions remain.
No phone action occurred.

## Candidate behavior and limits

A shared pure analysis precedes the submitted grant and proposal selection.
Supported independent clauses produce deterministic previews, each with Add;
no multi-action submission receives an automatic write. Explicit leading date, time
and recurrence can be inherited; a clause's explicit time overrides the inherited
clock. Postposed/mixed timing scope that cannot be established asks a focused
question. Model availability, errors and timeouts cannot collapse a batch to a
single parser result. An invalid mapped model item rejects the whole generated
batch rather than silently dropping an item.

Unsupported coordination (including unquoted object/title conjunctions) asks
whether the request is one item or separate actions. Balanced quoted titles
remain one title; parentheses do not hide another action. Recognized recurrence
weekday lists remain one recurring preview, retaining Add. Time-only answers,
kind-only conversions, acknowledgments and proceed phrases do not establish a
new subject or erase the original cardinality. A genuinely new clear request
replaces the old subject. Existing edits still use their existing routing and
Apply boundary. No write authority is broadened.

This is a bounded grammar candidate, not a proof that arbitrary natural language
has exactly one action. In particular, implicit compound predicates without a
recognized structural boundary, unsupported grammar and aggregation follow-up
semantics still require review. The candidate does not treat a model's count as
permission. Do not claim universal cardinality safety or merge acceptance from
the focused examples. Literal unquoted title conjunctions intentionally require
clarification; deciding how an explicit aggregation answer should authorize a
single combined reminder is not silently implemented as a new grant.

## Measured quantity boundary

The separate Live candidate `5037a18` has the same app source as `441172d`;
its complete bundle and closed observations are retained in primary
`tests/results/intelligence-eval-20261028/live-cardinality-5037a18-20261029`.
On the exact frozen multi-item input, the matched first pair is baseline0/1
correct versus candidate1/1. Three candidate repetitions passed3/3 for **one**
unique input; there were not three measured before trials. All three showed
two separate faithful titles at tomorrow09:00 and15:00, no auto-save and zero
Foundation Models calls. Three existing Chinese/English/mixed clear one-offs
retained direct creation and exact receipt Undo3/3. Three subjectless context
continuations produced no write; their repeated generic clarification is not
claimed as useful target-editing behavior.

Final Reminders overview showed All2, and Today retained the exact two own
synthetic15:00/16:00 setup records. The app, logger and video were closed before
further source changes. An AX ref for opening All was rejected before any tap
because a transparent toolbar had an oversized coverage frame; the visible
overview count is the evidence, not an opened All list. Complete evidence and
limitations are in `matched-cardinality-review.json` in that directory.

## Separate content validation candidate

The quantity-only source still granted incomplete requests such as a bare
transitive verb or dangling infinitive. A matched pure-rule exporter observed
wrong direct grants10/10 on `5037a18`, versus0/10 after the content candidate,
with identical input strings and fixed clock. This is not a Live before/after
rate or a model-generation score. The candidate shares content checks between
source analysis and capture eligibility, retains quoted operands, distinguishes
supported intransitives and explicit topics, and rejects empty/function-only
operands and open complement frames. Missing content asks for a complete action
instead of asking how many items. No generative model supplies the missing grant.

Additional regressions cover modifier prefixes, empty quotes, bare quantities,
phrasal predicates and dangling complements. The terse activity vocabulary is
shared with routing without adding new terse action words. Unsupported grammar
remains a bounded validation limitation, not a claim of universal semantic proof.
The independent product holdout has not been executed or tuned from responses.

## Validation

The content candidate's focused pass executed49 logic methods, missing0, passed;
raw log `devtools/logs/6d6762076df146b6aa01caba1e7a0856.log`. Raw before/after
exports and source hashes are linked by
`completeness-matched-rule-review-candidate1-20261029.json` in primary results.
The complete unit pass executed799 methods, missing0, passed; raw log
`devtools/logs/cc74ab36426f4f0b87ce157ed17087d5.log`.
The final native/CI receipts are recorded separately. No new-source
Live claim inherits the older `5037a18` observations. PR216 remains draft and
acceptance-blocked until the coherent validation candidate is accepted.

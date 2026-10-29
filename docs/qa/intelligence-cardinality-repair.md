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

## Validation

Independent zh/en/mixed repair cases live in
`ios/Eval/Tests/OneLogicTests/SubmittedActionAnalysisTests.swift` and are cataloged
in `tests/fixtures/README.md`; frozen model fixtures and prompts are unchanged.
They assert counts, dates, times, title separation and absence of direct grants,
including unknown predicates and context laundering. Existing single-reminder
and edit-boundary tests run alongside them.

The complete unit pass before the final shared-recurrence refinement executed
795 methods, zero missing, passed; raw log
`devtools/logs/149bcf5c6047418c90450f89631d85a9.log`.
The final focused source pass executed46 methods, zero missing, passed, including
shared weekdays, local time overrides and correct occurrence rollover; raw log
`devtools/logs/82986ce38ee04810b736aee02bfae15d.log`.
These are logic-method counts, not Live safety rates. Native build and exact-head
CI are recorded separately. Matched Live before/after acceptance and independent
product holdout after this repair are UNKNOWN until actually observed. PR216
remains draft and acceptance-blocked.

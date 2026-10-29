# GPT-6 Luna effort comparison — 2026-10-29

192 direct Responses API requests; 24 frozen synthetic development cases, two repetitions per effort. No retries, no tools, max_output_tokens=4096, store=false. No app UI or device writes. Total conservative reservation: USD 0.48; usage-priced total: USD 0.0181991. No missing usage receipts.

| Effort | Full-field passes | Median seconds | P90 seconds | USD / 48 calls | USD/day: 100 users × 10 calls |
| --- | --- | --- | --- | --- | --- |
| low | 43/48 | 1.78 | 2.75 | 0.0040699 | 0.0848 |
| medium | 43/48 | 1.68 | 2.25 | 0.0044669 | 0.0931 |
| high | 43/48 | 1.88 | 3.05 | 0.0046694 | 0.0973 |
| xhigh | 44/48 | 2.07 | 3.13 | 0.0049929 | 0.1040 |

Provisional choice: low. xhigh gained one passing observation over 48, without enough evidence for a reliable quality advantage. This is a small repeated development set, not 48 independent tasks or a blind holdout. The existing r4 scorer checks kind/date/time/title/duration together; its title matcher accepts substring matches. Reference labels can disagree with natural interpretations (e.g. hiking as task versus event). No prompt was tuned on these results.

Pricing: Standard short-context input USD 0.10/M tokens; output USD 0.50/M tokens including reasoning. Cached-input discounts are ignored conservatively. Source: https://developers.openai.com/api/docs/models/gpt-6-luna and https://developers.openai.com/api/docs/pricing (verified 2026-10-29). Responses reported model gpt-6-luna, service_tier default.

Daily projection = users × active fraction × calls per active user × measured mean call cost. At low: 5 / 10 / 30 calls per user per day => USD 0.0424 / 0.0848 / 0.2544 daily, or USD 1.27 / 2.54 / 7.63 per 30 days. Assumes all 100 users active daily, short requests matching this sample (~466 input tokens per call), no retries/tools. One chat message can invoke several calls; multiply accordingly. At 3000 input + 500 total output tokens per call, 100 users × 10 calls costs USD 0.55/day. This is a scenario, not measured production usage; hosting is excluded.

Durable raw responses and usage: primary checkout tests/results/luna-effort-20261029/raw.jsonl; summary.json beside it. Both are indexed with SHA-256 in the QA journal. Fixture: tests/fixtures/ai/luna-effort-20261029.json. Runner refuses a second paid run in the same output directory.

Migration status: app unchanged. Existing backend endpoint/authentication is unresolved; see gpt-luna-migration.md. No Apple model removal, GPT app integration, CI, install or app journeys are claimed.

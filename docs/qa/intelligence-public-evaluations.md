# Public evaluations: context, not Today acceptance

Reviewed2026-10-29. These are external published results, not measurements on
Yuan's phone. They cannot establish a universally strongest phone model.
The active Today simulator comparison remains Apple system / pinned Qwen2B/4B.

Apple's [2026 overview](https://machinelearning.apple.com/research/introducing-third-generation-of-apple-foundation-models)
describes AFM3 Core3B and Core Advanced20B with1–4B active parameters. Its
in-house general-text preference evaluation reports45.6% for Core3 versus23.3%
for its2025 predecessor. This is vendor human preference evidence, not a
Qwen comparison or Today task rate. An API-reported variant still does not
expose an exact weight revision/hash; earlier local batches lack that metadata.

The [official Qwen4B card](https://huggingface.co/Qwen/Qwen3.5-4B) reports
MMLU-Pro79.1, IFEval89.8 and BFCL-V450.3. Default thinking and generous output
budgets differ from this thread's greedy, non-thinking Q4_K_M/384-token candidate.
The card recommends sampling settings for non-thinking use. Its scores neither
validate our conversion/runtime nor measure our scheduling and confirmation
boundaries. A poor constrained deployment result is not a model upper bound.

## DeviceMark snapshot

[Published JSON](https://devicemark.github.io/data/leaderboard/board.json),
CC-BY-4.0, Daisuke Majima / DeviceMark; local snapshot and hash are indexed in
`tests/results/intelligence-eval-20261028/public-benchmarks-20261029/`.
Each row reports300 IFEval,196 MMLU-Pro and100 MATH items. The current composite
is the mean of IFEval mean-of-four and no-answer-inclusive MMLU/MATH accuracy.
Its arithmetic was reproduced from the published metrics; raw items were not
independently rescored.

| Published artifact | Composite | Published95% interval |
| --- | ---: | ---: |
| Qwen3.5-2B int8hu/Core AI |62.08%|57.78–66.60%|
| Qwen3.5-4B int8hu/Core AI |26.11%|22.40–29.95%|
| Apple system model |55.80%|51.55–60.09%|
| LFM2.5-1.2B int8hu/Core AI |68.23%|64.58–72.15%|

Qwen2B/Apple intervals overlap. LFM is a research lead among these published
ports, not a Today-tested replacement or a global winner.

The [methodology](https://devicemark.github.io/methodology.html) measures quality
on Mac and transfers it through limited phone token-parity gates; phone decode
speed is a separate measurement. The maintainer also ports many included models.
Coverage is selective, runtimes differ, most memory fields are download-size
proxies, and power is unmeasured. Apple used a different output cap; the author
reports no cap truncation for that row. Its older completed-only narrative
(~76% Apple) disagrees with the current no-answer-inclusive JSON55.8%; do not
mix them. Verbose4B outputs often lack a parseable final answer within budget.
These details explain why headline rankings are deployment-dependent.

No additional model was installed or tested based on this research. No public
score is pooled with the Today development/holdout denominators. The final
recommendation must use local correctness, safety and integration evidence,
while keeping phone speed, thermals, energy and memory UNKNOWN in this scope.

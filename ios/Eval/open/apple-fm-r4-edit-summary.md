| metric | result |
|---|---|
| op accuracy | 79.0% (79/100) |
|   op=move | 100.0% (65/65) |
|   op=delete | 100.0% (10/10) |
|   op=clarify | 0.0% (0/15) |
|   op=none | 40.0% (4/10) |
| target accuracy (move/delete cases) | 85.3% (64/75) |
| move time exact (dayOffset+hour+minute), all move cases | 26.2% (17/65) |
| move time exact, given op=move and right target | 31.5% (17/54) |
| errors (guardrail etc.) | 0/100 |
| latency p50 / p90 / max | 1.04s / 1.28s / 1.77s |

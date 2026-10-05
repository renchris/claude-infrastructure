# Router classifier, wave E1c — the pre-registered choice (2026-10-04)

Plan: `docs/plans/RESEARCH_PROGRAM_BUILD.md` wave E1c holds the rule, the choice, the one reading of
held-out set v2 and the verdict. This directory holds the rule's harness and its raw numbers.

Nothing here reads a sealed set. Both scripts read the v1 TUNING set
(`~/.claude/autonomy/research/router-heldout/tuning.jsonl`) and its two-rater labels beside it, which
stay outside the repo; no file here carries prompt text.

| file | what it is |
|---|---|
| `e1c-tune.py REPS OUT` | one cold call per tuning row, repeat and arm (`on-pre`, `on-e1b`, `off-e1b`), the arms started together; records the label and the wall time apart |
| `e1c-choose.py OUT` | the pre-registered rule as code: labeling eligibility, borderline relays, fallback share at 9 s; prints the chosen arm |
| `tune-2reps.json` | the measurement the choice was made on (labels, wall seconds and 1-min load by tuning row index) |

The rule and both scripts were committed (`3be0284f9`) before `e1c-tune.py` ran.

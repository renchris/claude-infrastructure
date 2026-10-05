# Router classifier, wave E1b — measurements (2026-10-04)

Plan: `docs/plans/RESEARCH_PROGRAM_BUILD.md` wave E1b holds the readings and the verdict. This directory
holds the harness and the raw numbers, so the next classifier lever is measured the same way.

Nothing here reads the sealed held-out set. Every script reads the TUNING set
(`~/.claude/autonomy/research/router-heldout/tuning.jsonl`) and its two-rater labels beside it
(`tuning-labels-anthropic.jsonl`, `tuning-labels-openai.jsonl`, `tuning-gold.json` = the 69 agreed rows).
Those stay outside the repo because they key operator prompts; no file here carries prompt text.

| file | what it is |
|---|---|
| `e1b-classifier.patch` | the classifier change tried and reverted (slim flags, router system prompt, delimited brief with reading notes). `e1b-diff.py` and `e1b-v5.py` expect it applied: their `built` arm is `router.classifier_argv()` |
| `e1b-rate-tuning.py <vendor> <out>` | one rater labels the tuning set with `heldout-rate.py`'s brief and courier path |
| `e1b-bench.py N out` | cold-start latency, four arms interleaved: current · `--disable-slash-commands` · + thinking off · + short system prompt |
| `e1b-bench2.py N out` | cold-start latency, pre-E1b path vs `router.classifier_argv()`, interleaved |
| `e1b-tune-eval.py A\|C reps` | row-15-style scoring on the agreed tuning rows (`other` exact, relay recall) |
| `e1b-diff.py <arm> reps` | labels for all 96 tuning rows per arm (`pre`, `built`, `built+think`); feeds the borderline-relay count |
| `e1b-v5.py N1\|N2 reps` | two cost-asymmetry notes added to the brief, scored on agreed and borderline rows |
| `bench*.json`, `labels-*.json` | raw results (wall seconds and 1-min load per call; labels by tuning index) |

"Borderline" rows are the 13 tuning rows where the raters disagreed and one said completeness or
pushback: how often an arm relays them measures its completeness sensitivity, which the agreed rows
(all relayed by every arm) cannot.

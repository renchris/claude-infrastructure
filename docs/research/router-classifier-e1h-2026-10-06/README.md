# Wave E1h: the tuning run and RULE 1 (2026-10-06)

Outcome: **STOP.** No configuration is eligible under RULE 1, so nothing about the classifier was landed, v4 was
not sealed and no sealed set was read. The rule and the record are in `docs/plans/RESEARCH_PROGRAM_BUILD.md`,
wave E1h; the rule was committed at 01:57 CDT, the first classifier call was at 02:48.

- `e1h-tune.py` ran every arm to completion on the tuning base: 982 rows (490 fresh, 396 from retired v2, 96 from
  the v1 tuning file at two calls each), four arms started together per row, 4,312 cold calls, 02:48-05:01 CDT,
  1-min load 8-75 (median 18).
- `tune.json` is the per-call data: label, wall seconds, exit code and load, keyed by source and item id. It holds
  no prompt text.
- `e1h-score.py` is RULE 1 as code. `e1h-score.py tune.json` reprints `result.txt`; `e1h-score.py counts` prints the
  tuning base's counts. Both need the tuning base, which is outside the repo
  (`~/.claude/autonomy/research/router-heldout/`: `tuning-v4.jsonl` and its two labels files, `retired-v2.jsonl`,
  `tuning.jsonl` and its two labels files).
- `result.txt` is the scorer's output: the 14 configurations of the frozen rule list, the two thinking-on arms
  alone (shown only), and the outcome.

What failed: the `other` test (exact label at 0.95 or better on 240 agreed rows). The best reading is 206 of 240
= 0.858. Most of every configuration's misses are a wrong label among the labels that do not relay (31 to 39 of
the 240), which no arm and no join changes.

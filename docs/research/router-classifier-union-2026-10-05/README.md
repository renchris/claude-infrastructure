# Re-ask classifier: a fast-plus-careful union, simulated offline (2026-10-05)

Scope (frozen): raise conviction on the open row-15 decision after wave E1e's FAIL, using only data already
recorded on the tuning set. No new classifier calls; sealed v2 is not read.

**Question.** Row 15 failed twice with thinking on (`other` labeling and 9 s fallbacks). Thinking off passed every
row-15 threshold on tuning and on v1, and lost E1c's choice only on borderline completeness prompts, which row 15
does not count. Does running both and relaying when either says relay keep thinking-on's sensitivity at
thinking-off's speed?

**Method.** `union-sim.py` re-reads E1c's per-call tuning results
(`../router-classifier-e1c-2026-10-04/tune-2reps.json`, 96 rows × 2 reps per arm, load 28-46) and pairs the
thinking-off call with the thinking-on call of the same row and rep. Union rule: if the fast answer is a relay
label within 9 s, take it; else if the careful answer is a relay label within 9 s, take it; else take the fast
answer; a fallback only when neither answered. Metric definitions follow `e1c-choose.py`, except that the
"careful" arm's late answers count as unanswered (the router's real 9 s limit). Gold: the two raters' agreed
labels beside the tuning set (outside the repo).

**Result** (`result.txt`):

| arm | relay recall (≥ 0.95) | `other`, all calls (≥ 0.90) | borderline relays | fallback at 9 s (≤ 0.10) |
|---|---|---|---|---|
| thinking off (E1b brief) | 51/52 | 44/44 | 10/26 | 1/192 |
| thinking on, as built | 51/52 | 36/44 | 18/26 | 33/192 |
| union, off + on as built | 52/52 | 43/44 | 19/26 | 1/192 |
| union, off + on (E1b brief) | 52/52 | 44/44 | 18/26 | 1/192 |

The union keeps thinking-on's borderline sensitivity (18-19 of 26) at thinking-off's fallback share (1 of 192), and
passes every row-15 threshold on tuning.

**What this does not show.**
- It is the tuning set. The as-built thinking-on config also passed `other` on tuning (40/44 by E1c's count) and
  then read 0.88 and 0.72 on v2, so a tuning pass is not a forecast of a held-out pass. Thinking off has one
  independent held-out reading (v1: `other` 25/26, fallback 0/69, regex-missed recall 1/3 on 3 items).
- The union's `other` rate on held-out depends on whether thinking-on's wrong `other` answers are relay labels; that
  is visible only on a sealed read, so it was not checked.
- Two calls per prompt doubles the resident workers' load; latency under that load is unmeasured.
- The old "fixed-rule completeness check ahead of the model" option has nothing to stand on: the router has no
  regex pre-check (`router.py` `classify`), and the borderline prompts thinking off misses are subtle wording that a
  fixed rule would not catch either.
- v2 is spent (read twice), and E1c found the pushback population spent, so any new sealed set will be thin there.

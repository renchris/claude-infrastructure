# Lens: is the calibration study's materiality ground truth right, and is it the operator's line?

Auditor: completeness-critic lens, 2026-10-04. Read-only. Repo paths are relative to the worktree root.
"CAL" = `docs/research/research-calibration/REPORT.md`. "PRIV" = `~/Development/claude-private/docs/research/research-calibration-2026-10-01/`.
Labels on numbers: **measured** (a command I ran this session), **modeled** (calib_sim run this session), **asserted** (my own judgement over records I read).

This repo is public and PRIV quotes private repositories, so items are cited by plan and item id, and paraphrased without code or quotes from the plans.

## Answer first

1. **The headline survives; the prescription does not.** Under every materiality line I could defend, false
   material calls stay at 0.22 to 1.13 per read. That is 10 to 56 times the 0.02 the stop rule needs. Every
   profile still hits its cap in 99 to 100% of programs, and P(any change after signoff) stays 1.00 (modeled).
   "Triage precision is the binding lever" therefore holds in size: a precise fix takes Standard from about 9
   desk holes to 1.8 to 2.4 on every line (modeled). **What does not survive is CAL §6's proposed fix**, which is
   to count "real but not material" as a refinement at the verifier. If those 72 items are real ex-ante material
   holes, as the rubric's own text says about 52 of them are, that fix moves them into rater downgrades. Standard
   then leaves **9.3 desk holes instead of 2.3** (modeled). Which way the fix cuts depends entirely on a boundary
   the study never measured.
2. **The ground truth is a hindsight, outcome-based line, not the rubric's.** I recovered the adjudicator's
   per-item rationales: 16 per-plan agents, and their labels match `_verdicts.json` with 0 mismatches. The
   rationale given for "not material" was "the builder settled it without a plan change" on 28 of 72 items, and
   "no incident / never bit / nothing / never built" on most of the rest (measured, regex). Every one of the 129
   items had already passed **the method's own MATERIAL test**: at least 2 of 3 raters said material, the
   verifier CONFIRMED it, and `consequence_reproduced=true` (measured, 129/129). So "1.13 false calls per read"
   measures how often a hindsight adjudicator disagrees with the method's triage. It is not a precision rate
   against the rubric.
3. **The materiality boundary is not reproducible between the method's own raters.** Rater 1 (OpenAI) and rater 2
   (Anthropic) agree on material vs not with Cohen's κ = **0.08** over all 295 confirmed items (72% raw agreement
   at 76% and 88% base rates; measured). Unanimity carries no signal about the adjudicator: P(adjudicator says
   material | both raters said material) = 29/91 = 0.32, against 11/38 = 0.29 when they split (measured).
4. **The operator's revealed line is wider than RUBRIC a-g.**
   - Of the 188 non-new-scope holes in the 200-hole taxonomy (every one surfaced after a completeness claim), the
     forensic analysts rated 92 (49%) refinement or cosmetic. My a-g pass over those 93 rows, which include one
     unclear row, found 54 that meet no clause (**29%**; asserted) and 7 "known residual behind a ✅" rows the
     rubric is silent on (4%).
   - A fresh transcript mine found 94 distinct operator completeness prompts in 74 sessions (measured). In it,
     8 re-asks produced a new item after a claim, and 3 of the 8 were rubric-immaterial (asserted). All 3 belong
     to a class the operator names in his own words, "saved what we needed to save" and "anything to fix, save,
     improve", which neither RUBRIC a-g nor checklist FAC-01..33 carries.
5. **The refinement path that is meant to absorb that class has no consumer.** No code in `scripts/research-kit`
   reads a REFINEMENT-level hole, and the certificate prints none (measured, grep). "Apply at build" is prose.

Conviction that "triage precision is the binding lever" survives as a size claim: **85%**. Conviction that CAL §6's
specific triage fix is right for the operator's goal: **35%**. Conviction that the rubric's definition of complete
omits part of the operator's "one more thing" class: **85%**.

## 0. Integrity of inputs

- `PRIVATE_MANIFEST.json` sha256 check over every `adjudicate/*` entry: `19 0`. All 19 files match, with 0
  mismatches (measured, python hashlib).
- `_verdicts.json`: 129 labels, REAL_MATERIAL 40 / REAL_NOT_MATERIAL 72 / FALSE 17 (measured). This matches CAL §4.1.
- `_verdicts.json` keeps labels only, so the adjudicator's `evidence` and `later_history` fields are not in PRIV.
  I recovered them from the workflow transcripts
  `~/.claude-tertiary/projects/-Users-chrisren-Development--worktrees-wt-cc-022946-79382/f4c84c9d-434f-4127-9e34-74456263b7a1/subagents/workflows/wf_d185d88d-b36/agent-*.jsonl`
  (run `calib-a3-adjudicate`, status completed, 16 agents, journal `workflows/wf_d185d88d-b36.json`). Comparing
  the StructuredOutput verdicts there against `_verdicts.json` gives `MISMATCH 0` (measured). An earlier run,
  `wf_f370fa23-35f`, was killed and produced no result.
- **Gap (finding F7):** the rationale behind the study's central number exists only in an account's transcript
  store, which is subject to retention. It is not in PRIV and not in the manifest.

## 1. Inter-adjudicator reliability (task 1)

### 1.1 What could not be run under this lens's rules

The task asks for at least 2 independent, vendor-diverse, blind re-adjudications of the 89 items plus at least 30
REAL_MATERIAL items. This lens forbids vendor CLIs (codex, gemini, agy) and quota spend, and this context has no
Agent tool. So the true three-way Fleiss κ between independent adjudicators **was not measured**. I report the
reliability that the existing records do measure, plus one non-blind re-labelling of my own, clearly marked.

### 1.2 Agreement the records already contain (measured)

| Pair or panel | Population | κ | Raw agreement | n |
|---|---|---|---|---|
| rater 1 (OpenAI gpt-5.6-sol) vs rater 2 (Anthropic Opus 5.5), material vs not | every verifier-confirmed item that both rated | **0.080** | 0.722 | 295 |
| rater 1 vs adjudicator | the 129 adjudicated items | −0.044 | 0.372 | 129 |
| rater 2 vs adjudicator | the 129 | 0.058 | 0.372 | 129 |
| Fleiss, r1 + r2 + adjudicator, binary | the 129 | −0.172 | 0.483 | 129 |

Command: a python join of `PRIV/triage/<plan>.json` (`verdicts`, `ratings2`), `PRIV/raters/rater1/<plan>.last`,
`PRIV/raters/rater3/<plan>.last` and `_verdicts.json`. Caveat: the 129 were selected *because* at least 2 raters
said material, so their κ values are range-restricted and biased low. The 295-item r1-vs-r2 κ has no such
selection, and it is near chance.

The three-way label table for the 129 (measured):

| adjudicator | r1, r2 both MATERIAL | split, rater 3 decided |
|---|---|---|
| REAL_MATERIAL | 29 | 11 |
| REAL_NOT_MATERIAL | 50 | 22 |
| FALSE | 12 | 5 |

The verifier said CONFIRMED with `consequence_reproduced=true` on **all 129** (measured), so every one met RUBRIC.md's
`MATERIAL` level as written: at least 2 raters, and the consequence reproduced.

### 1.3 What the adjudicator's "not material" means (measured, regex over recovered rationales)

| Pattern in `later_history` + `evidence` | REAL_MATERIAL (40) | REAL_NOT_MATERIAL (72) | FALSE (17) |
|---|---|---|---|
| builder / "settled it" / "without a plan change" | 2 | **28** | 1 |
| no incident / never bit / never happened | 0 | **19** | 3 |
| starts "Nothing" | 2 | 8 | 1 |
| never built / ran / exercised | 3 | 8 | 0 |

The brief licenses this reading. `adjudicate.workflow.js:17` defines not-material as "a detail a builder would
settle without the plan changing". `:14` makes later history ground truth, including "a build that shipped the
very thing ... and it worked". RUBRIC.md has no builder-settles exemption and no outcome test. Its clauses f
(safety) and g (missing component) are "always material" (RUBRIC.md:17-18), yet the reviewers had tagged 19 of
the 72 "not material" items f or g (measured: clause distribution for REAL_NOT_MATERIAL was a3 b13 c20 d8 e9 f8 g11).

The line is also applied inconsistently. One adjudicator per plan, 16 agents, rated between 25% and 80% of a plan's
items "not material" (land-pipeline-v2 3/12, limit-detect-100p 11/14). Two items with the same history ("nothing
happened, never built") received opposite labels. One is the voiceink item I16, rated material on "Nothing: still
global, W3 not built". The other is the land-ship-v2 item I10, rated not material on "Nothing ... never bit"
(recovered rationales). Plan and adjudicator are confounded, so the spread cannot be attributed to either.

### 1.4 My re-labelling of the 72 (asserted; non-blind; one model; not independent of the original vendor)

I read each item's claim and consequence (`PRIV/adjudicate/<plan>.json`) and the adjudicator's own recovered
rationale, and put each in one bucket:

| Bucket | Meaning | n |
|---|---|---|
| A builder-absorbed | a real plan defect that the build had to fix in code, with the plan text never amended | 27 |
| B outcome-luck or moot | real; harmless only because nothing fired in the window, or the unit was never built | 19 |
| M consequence occurred | the adjudicator's own history shows the predicted hazard recurring, or the gap still open on a hazard axis | 4 |
| O operator-facing correction | a false statement the operator relied on: a ruling resting on a wrong figure, or a false DONE claim | 2 |
| C genuinely minor | wording, a lead-level detail | 9 |
| D partly refuted | the adjudicator's evidence undercuts the premise or the consequence | 11 |

Per item (plan iid → bucket):
- limit-recover-100p: I3 A
- reso-latency-100p: I10 B, I17 D, I18 A
- reso-security-100p: I2 B, I10 C
- research-report-v1: I9 A
- device-enrollment-build: I2 A, I5 B, I8 M, I10 B, I12 B, I16 A, I17 A
- machine-capacity-v2: I2 C, I4 A, I9 B, I13 D, I15 D, I16 A
- sevenrooms-laptop-independence: I1 O, I8 A
- agent-context-sync: I19 C, I20 A, I21 A, I23 B, I28 A, I29 A
- hook-surface-100p: I2 O, I4 D, I6 M, I19 C, I23 B
- land-ship-v2: I9 B, I10 B, I11 A, I16 A, I20 D
- limit-recover-fleet-v2: I2 B, I3 A, I5 A, I10 C, I11 A, I14 C, I19 A, I22 A
- voiceink-latency: I9 D, I13 C
- land-pipeline-v2: I4 M, I13 B, I24 M
- limit-detect-100p: I2 A, I8 A, I9 A, I12 B, I13 A, I15 A, I18 A, I19 D, I20 D, I21 A, I23 B
- tenant-provisioning-100p: I3 D, I7 B, I11 C, I14 B
- tm2: I1 D, I6 D, I8 B, I9 B, I16 B, I20 C

The M items, from the adjudicator's own text:
- land-pipeline-v2 I24: the verifier's leaks into the live layer "recurred" in three later commits.
- land-pipeline-v2 I4: the cutover was escaped only through a raw pull, which is a separately recorded hole path.
- device-enrollment-build I8: detection is still absent on the Fly tenants at origin/main.
- hook-surface-100p I6: the flip recurred from another cause.

The O items:
- sevenrooms I1: an operator ruling's stated justification is false (about 57% saved against the >90% claimed),
  and the false figure was copied into two shipped files.
- hook-surface I2: the plan closed COMPLETE while still owing cells.

Implied κ between me and the adjudicator over the 40 + 72, assuming I agree on all 40 REAL_MATERIAL (I read their
`later_history` lines, and all 40 describe a later fix, a build hitting the problem, or a gap still open):

- rubric-as-written line, where A, B, M and O are material: **κ ≈ 0.22**
- operator-facing line, where A is not material: **κ ≈ 0.57**

Both are arithmetic over the bucket counts (modeled).

### 1.5 False material calls per read under each line (79 reads; measured counts, labelled lines)

| Line | False calls | Per read | Extra true holes at freeze (deflated ×0.78) |
|---|---|---|---|
| S0 study: everything not REAL_MATERIAL is false | 89 | **1.127** | 0 |
| S0b only FALSE counts, and the 72 are dropped rather than counted as holes | 17 | 0.215 | 0 |
| S1 rubric as written, ex ante: A, B, M, O material | 37 (FALSE + C + D) | **0.468** | +52 |
| S2 operator-facing: builder-absorbed items not material | 64 (FALSE + A + C + D) | 0.810 | +25 |
| S4 operator-strict: any real residual counts | 17 | 0.215 | +72 |

Every line sits at least 10 times above 0.02.

## 2. The operator's revealed line (task 2)

### 2.1 Fresh mining (measured)

Scope: rg over top-level `*.jsonl` (subagents excluded) in `~/.claude`, `~/.claude-secondary`, `~/.claude-tertiary`
and `~/.claude-quaternary` `/projects`. Filters: lines at most 6,000 chars; type=user; not meta, sidechain or
tool_result; not starting `<`; under 3,000 chars. The regex covered "are we 100/complete/done/finished", "100.00",
"what did we/you forget/miss", "one more thing", "you missed" and "did you forget/miss". Result: **94 distinct
prompts, 74 sessions, 2026-09-16 to 2026-10-04**. The narrow pattern and the long-line cap make this a lower bound.

Pairing each prompt with the preceding assistant text and the final assistant text before the next operator
prompt (measured), then classifying under a-g (asserted):

| Session (timestamp, UTC) | Prior claim | Item produced | a-g |
|---|---|---|---|
| 089dda26 (09-17T03:48) | ✅ "Good to close: yes" | fix landed on the wrong tree; the armed tree can panic the box again | f, d: material |
| 101dc59a (09-20T09:21) | "Done" status | "W1 was not finished, in two ways the landed code could not show" | b: material |
| d90959db (09-21T18:00) | "built, landed and live" | the DoD drill can never exit 0: ten rows carry no instrument | b: material |
| 696eb098 (09-22T05:41) | ✅ "exhaustively; follow-on: none" | the diff-scan design had four coverage defects | b, d: material |
| bb231dfd (10-01T00:47) | method "designed and landed" | the report's own certification passes kept 18 issues | material |
| d71e8e48 (09-21T04:01) | the evening's work done | "no, we hadn't": the learnings were never written down as a knowledge base | **none of a-g** |
| 3d42fa49 (09-24T22:37) | ✅ "Good to close: yes" | a new decision: whether to upgrade a dependency | **none of a-g** |
| 41eee6a5 (09-28T02:13) | (save request) | most research had been sitting in /tmp, which is wiped at reboot | **none of a-g** (persistence) |

Known residuals re-rendered as the answer, where the rubric is silent (the C1 class): 2825e1e5 (09-22T19:52),
0612873d (09-24T05:02), 3afa727e (09-26T21:18), bb231dfd (10-02T00:48), 762a6daa (10-03T19:44) and 69629b66
(10-03T21:47, a cosmetic leftover left "by your call"). Most prompts after 2026-10-01 drew a "yes" with no new item.

**New items after a claim: 8. Rubric-immaterial: 3 (38%; n small).**

The operator's own definition of "complete", in his words:
- "... deployed, and live, saved what we needed to save" (26cd14be, 2026-09-19T17:33:45)
- "... for all maximally value extracted/learn from our lessons" (cb227486, 2026-09-19T18:27:53)
- "Anything to fix, save, improve before we close?" (3afa727e, 2026-09-26T21:18:28)

Persistence, lessons and improvement are not clauses of RUBRIC.md (a-g, :10-18) and have no row in
`skills/research-program/checklist.jsonl` (FAC-01..33, read in full; the nearest are FAC-29 rollback and FAC-17
hazards).

### 2.2 Cross-check against the 200-hole taxonomy (measured counts; my a-g pass asserted)

`evidence/taxonomy_holes.py` gives DC 95, REF 85, NEW 12, COS 7, UNC 1 (measured). Every hole surfaced after a
completeness claim (`taxonomy.md:9`).

My a-g pass over the 93 REF/COS/UNC rows:

| a-g result | n | Hole ids |
|---|---|---|
| meets a clause, mostly b (an acceptance check that cannot fail) | 32 | 2, 14, 17, 24, 37, 42, 43, 48, 54, 59, 64, 73, 89, 93, 100, 109, 114, 117, 129, 130, 138, 142, 152, 153, 171, 172, 178, 179, 182, 184, 190, 199 |
| C1 frame re-render; the rubric is silent | 7 | 13, 23, 60, 158, 163, 169, 192 |
| no clause | 54 | the rest |

So **of 188 non-new-scope holes, about 54 (29%) are ones the rubric would rate below material, plus 7 (4%) it does
not address**. The analysts' own labels put the share at 49%. I assume the 95 DC holes are material; clause a's
"probe reproduces the consequence" condition could push some below the line, so 29% is a floor on the rubric side.

## 3. The forecast recomputed (task 3; modeled)

Reproduction check: `calib_sim.run` with REPORT inputs (u 0.12, q 0.2, omit 0.58, b 0.2, four-vendor, 500 reps,
seed 7) at N0 = 19 and fpp 1.127 gives Lite desk 9.03, against CAL's 9.36 at N0 = 20. The order and size match.

Note: the jsonl median of `holes_at_freeze_audited` is 18.7, while CAL prints 20.6, which is the upper median
(`analyze.py:596`). This is minor.

Holes at freeze for each line come from `research-calibration.jsonl` `holes_at_freeze_audited` + 0.78 × that
plan's extra true items. Environment: `PYTHONDONTWRITEBYTECODE=1`, nothing written.

| Line (fpp, N0) | Lite desk / invisible / cap | Standard desk / cap | Full desk | P(any) |
|---|---|---|---|---|
| S0 study (1.127, 19) | 9.03 / 3.73 / 100% | 13.35 / 100% | 20.93 | 1.00 |
| S0b FALSE only (0.215, 19) | 6.47 / 2.74 / 99% | 6.11 / 100% | 7.21 | 1.00 |
| S1 rubric ex ante (0.468, 23) | 8.36 / 3.55 / 100% | 8.88 / 100% | 11.89 | 1.00 |
| S2 operator-facing (0.810, 20) | 8.51 / 3.57 / 100% | 10.99 / 100% | 16.41 | 1.00 |
| S4 operator-strict (0.215, 24) | 7.86 / 3.45 / 99% | 7.37 / 100% | 8.63 | 1.00 |

The proposed fixes under each line (fpp 0.01; Standard unless marked):

| Line | Desk | Cap |
|---|---|---|
| S0, triage fixed precisely (q 0.05, N0 20) | 1.82 | 36% |
| S1, triage fixed precisely (q 0.05, N0 23) | 2.27 | 40% |
| S4, triage fixed precisely (q 0.05, N0 24) | 2.35 | 37% |
| **S1, CAL §6 fix: demote "real but not material" (fpp 0.01, q rises to (21+52)/(94+92) = 0.39, N0 23)** | **9.33** | 26% |
| Lite, same | 10.59 | 44% |

## 4. Which earlier findings flip

| Earlier finding | If S0 holds (the adjudicator is right) | If S1 holds (rubric as written) | If S4 holds (operator-strict) |
|---|---|---|---|
| CAL §1: about 1.1 false material calls per read | stands | 0.47 | 0.22 |
| CAL §4.1 caveat: most of the 72 would be removed by the frame-row rule, so the rate is an upper estimate | stands | **flips**: about 52 are real material holes, so the rule would drop holes | **flips** |
| CAL §6 fix: count "real but not material" as a refinement at the verifier | helps (to 1.8) | **harms** (9.3, against 2.3 for a precise fix) | **harms** |
| CAL §4.3: 21 holes at freeze; 40 unrecorded real holes found | stands | 23; about 92 unrecorded | 24; 112 |
| Decision 4 (Lite for every size) | stands | stands (Lite 8.4 beats Std 8.9) | weakens: Std 7.4 beats Lite 7.9 |
| lens-goal-fit "fix triage: 6.45 → 1.82" | stands | 2.27 only if the fix removes FALSE + C + D without demoting real holes | 2.35, same condition |
| compare-blind-designs P(quiet round) 0.27 at 0.22 / 0.001 at 1.13 | 0.001 | e^(−6×0.468) = 0.06 | 0.27 |
| §6.1 Full precondition fails 22-113× | stands | 21-47× | 21× |
| "Stop rule cannot fire" | stands | stands | stands |

## 5. Is the goal attainable on this axis?

"Never come back with one more thing" is attainable only for a *declared* class. The fresh mining and the taxonomy
both show the operator's class includes refinements, persistence and improvement. A rubric that rates them "not
material" can stop them from resetting rounds, which is right for convergence. But they still have to go
somewhere the operator sees and the build drains, or they come back as "one more thing" at build or at the next
ask. Today they have no such place: RUBRIC.md:26 and SKILL.md:37,125 say "apply-at-build list", and the kit's
only REFINEMENT mention is prose in `intake.py:68`. The `cli_records.py:41` "immaterial" bucket routes nowhere,
and `gate_rows_b.py:119`, `round.py:352` and `seed.py:188` read only `MATERIAL` (measured, grep). The strongest
attainable version keeps the rubric for the stop rule. It adds a second, signed acceptance class for the
operator's refinement and persistence dimensions, a stored apply-at-build list the certificate prints with a
count, and a build-start gate that drains that list.

## 6. Housekeeping

During analysis I wrote four scratch files under `/tmp`: `lens-mat-items.txt`, `lens-mat-rows.json`,
`lens-adj-evidence.json` and `lens-adj-rnm.txt`. They hold extracts of PRIV, which goes beyond this lens's
"write no files" rule. I delete them after this note.

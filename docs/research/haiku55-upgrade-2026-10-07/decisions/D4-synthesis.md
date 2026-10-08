# D4: research and synthesis workers, Haiku 5.5 against Opus 5.5 (measured 2026-10-08)

**Recommendation.** Keep research and synthesis workers on Opus 5.5 @xhigh. Haiku 5.5 lost every one of
the 6 frozen briefs at both high and xhigh, with all 3 judges agreeing on every brief (18 of 18 judge
rows for each Haiku arm). Conviction 95% (was 90% on vendor evidence alone).

Arms: HH = claude-haiku-5-5 @high, HX = claude-haiku-5-5 @xhigh, OX = claude-opus-5-5 @xhigh, all run
fresh in this panel on Claude Code 2.1.293. One run per brief per arm (n = 6 briefs per arm).

## Result

Per-brief pairwise majority (3 Opus 5.5 @xhigh judges; the three calls are J0/J1/J2):

| Brief | HH v HX | HH v OX | HX v OX |
|---|---|---|---|
| T1-custody | **HX** (HX/HX/HX) | **OX** (OX/OX/OX) | **OX** (OX/OX/OX) |
| T2-recycle-goal | **HH** (HH/HH/HH) | **OX** (OX/OX/OX) | **OX** (OX/OX/OX) |
| T3-frontier-budget | **HX** (HX/HX/HX) | **OX** (OX/OX/OX) | **OX** (OX/OX/OX) |
| T4-stop-arms | **HX** (HX/HX/HX) | **OX** (OX/OX/OX) | **OX** (OX/OX/OX) |
| T5-deploy-live-exec | **HX** (HX/HX/HX) | **OX** (OX/OX/OX) | **OX** (OX/OX/OX) |
| T6-choose | **HH** (HH/HH/HH) | **OX** (OX/OX/OX) | **OX** (OX/OX/OX) |

| Pair | first wins | second wins | tie/split | sign test p (two-sided, ties dropped) |
|---|---|---|---|---|
| HH v HX | 2 | 4 | 0 | 0.6875 (n=6) |
| HH v OX | 0 | 6 | 0 | 0.0312 (n=6) |
| HX v OX | 0 | 6 | 0 | 0.0312 (n=6) |

Sign-test reading: both Haiku arms against Opus are 0-6, p = 0.031, the smallest p six briefs can give.
HH against HX (2-4, p = 0.69) cannot be distinguished: xhigh is not shown to beat high.

Per arm (measured by `d4/tally.py` from the judge rows, `arms/index.jsonl` and `citecheck.rows.jsonl`):

| Arm | mean score /10 (18 judge rows) | key recall (majority) | judge spot-check bad cites | wrong claims | key items contradicted | program: missing file or line | program: token not at cited lines (+-2) | output tokens, median per brief (total) | wall s, median per brief |
|---|---|---|---|---|---|---|---|---|---|
| HH | 6.61 | 114/130 (87.7%) | 31/566 (5.5%) | 33 | 9 | 1/209 (0.5%) | 40/152 (26.3%) | 40251 (263688) | 185 |
| HX | 7.33 | 121/130 (93.1%) | 17/655 (2.6%) | 21 | 4 | 0/302 (0.0%) | 48/206 (23.3%) | 77648 (473816) | 335 |
| OX | 8.89 | 125/130 (96.2%) | 10/758 (1.3%) | 9 | 0 | 0/305 (0.0%) | 42/129 (32.6%) | 39513 (214360) | 361 |

Judge scores per brief (J0/J1/J2):

| Brief | HH scores | HX scores | OX scores |
|---|---|---|---|
| T1-custody | 6/6/6 | 8/8/8 | 9/9/9 |
| T2-recycle-goal | 8/8/7 | 7/7/6 | 8/9/8 |
| T3-frontier-budget | 6/6/5 | 8/8/8 | 9/9/9 |
| T4-stop-arms | 6/7/6 | 7/8/7 | 9/9/9 |
| T5-deploy-live-exec | 6/6/6 | 8/8/8 | 9/9/9 |
| T6-choose | 8/8/8 | 6/6/6 | 9/9/9 |

Citations:
- **Program check, file and line exist:** 1 bad of 209 (HH), 0 of 302 (HX), 0 of 305 (OX). No arm
  invents files or line numbers; this check does not separate the arms.
- **Program check, quoted or named token at the cited lines (window of 2 lines):** 26.3% / 23.3% / 32.6%
  missing (n = 152 / 206 / 129 tokens). This does NOT separate the arms and should not be read as a
  bad-citation rate. Its noise floor is high: on the stored 09-28 Opus 5.5 answers it reads 36% (72 of
  198) where tool-using judges found 1.2 to 2.1% bad, because answers paraphrase code inside backticks.
  It only covers explicit `path:line` cites; shorthand `:N` cites are not scored.
- **Judge spot-check, byte-for-byte with tools (the measure the Sonnet 5.5 record used):** HH 31 of 566
  (5.5%), HX 17 of 655 (2.6%), OX 10 of 758 (1.3%). Per brief, HX has the higher rate on 4 briefs and
  the lower on 2 (sign test p = 0.69, n = 6): HX and OX cannot be distinguished on citations. HH has
  the higher rate on 5 briefs with 1 equal (p = 0.0625, n = 5): suggestive, not established.
  The Opus figure matches the 09-28 run (1.2%), so the anchor is stable across days and binaries.

Cost in plan quota (estimated: measured output tokens times the record's 0.12 draw ratio, bounds
0.055 to 0.19): HX spent 473,816 output tokens against Opus's 214,360 (2.2 times), so about 0.27 times
Opus's draw per brief (0.12 to 0.42); HH spent 263,688 (1.2 times), about 0.15 times (0.07 to 0.23).
Median wall time per brief: HH 185 s, HX 335 s, OX 361 s. So the saving is real, and the quality loss
is too: Haiku @xhigh scored 7.33 of 10 against 8.89, with 21 wrong claims against 9 and 4 key items
contradicted against 0. That is about where Sonnet 5.5 @xhigh landed on 09-28 (7.44, 0-5-1).

## Method (five lines)

1. Corpus: the 6 frozen briefs and answer keys from `opus55-synth-reprobe-2026-09-22/corpus/` (all 6
   brief hashes match `sonnet55-synth-probe-2026-09-28/corpus.sha256`); repo snapshot rebuilt with
   `git archive 47c3317eb` into `/tmp/haiku55-decisions/d4/repo-47c3317eb`.
2. Arms: the 09-28 `run-synth.sh` reused with three edits (binary 2.1.293, snapshot and brief paths, the
   two env vars); same prompt, same tool rule (Read plus allowlisted read-only Bash), account `next`.
   All 18 calls were served the requested model (read from `modelUsage`); none dropped.
3. Citation program `d4/citecheck.py` was written, tested on the stored 09-28 answers only, and frozen
   (sha256 in `d4/citecheck.sha256`, 04:59:50Z) before the first arm call (05:00:51Z).
4. Judges: 3 claude-opus-5-5 @xhigh calls per brief (18 calls, all served Opus 5.5), the 09-22 judge
   prompt and schema reused, arms shown as X/Y/Z with the 09-22 order-rotation table, tools to open
   the snapshot, key supplied; majority of 3 per brief; exact two-sided sign tests.
5. Model calls used: 54 of 150 (18 arms, 18 judges, plus 18 void calls that failed in about 1 second
   with zero tokens because zsh ate `:c` from the cell spec; kept in `d4/void-run0-zsh-modifier/`).

## Not settled

- One run per brief per arm. Run-to-run variance within an arm is not measured; the 6-0 result with
  unanimous judges makes a reversal unlikely but the size of the gap is loose.
- All judges are Opus 5.5, so own-family preference is not ruled out here. On 09-28 an Opus 5 judge
  saw the same gaps for Sonnet 5.5; that check was not repeated for Haiku.
- The program citation check could not reproduce the judges' bad-citation ordering; the bad-citation
  rates that separate the arms are judge spot-checks, not program output.
- These 6 briefs are all deep single-repo code tracing. Web research, and wide shallow synthesis where
  speed matters more than exhaustiveness, were not tested.
- Haiku 5.5 @max and @medium were not run. HH against HX is not distinguishable (2-4), so there is no
  measured reason to expect @max to close a 1.6-point gap, but it is unmeasured.
- A Haiku 5.5 first pass with an Opus 5.5 verifier (cheap draft, expensive check) was not tested.

Files: raw rows `/tmp/haiku55-decisions/D4-synthesis.rows.jsonl` (90 rows: arm calls, judge calls,
pair verdicts, key recall, citation check). Answers, judge JSON and scripts: `/tmp/haiku55-decisions/d4/`.

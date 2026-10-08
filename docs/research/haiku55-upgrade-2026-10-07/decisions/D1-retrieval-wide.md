# D1: codebase retrieval on wide sweeps, Haiku 5.5 by effort (2026-10-08 UTC, binary 2.1.293)

## Recommendation

Keep codebase-retrieval subagents on Haiku 5.5 at effort **medium**, with low as the slack rung,
but change the stated reason. Low did **not** collapse on wide sweeps here: Haiku 5.5 at low and at
medium each returned the exact true file set in 20 of 20 runs (482 of 482 true files, no extra
files). The quality data therefore favor neither rung. Medium stays because low's saving is small
and unproven (median 2,126 vs 2,536 output tokens; a sign test over the 10 questions cannot
distinguish them, 8 to 2, p = 0.11), a Haiku 5.5 token is cheap in plan quota, and the only
evidence about much wider search than we tested is the vendor's, which points against low. Do not
use high: it spent 57% more output tokens than medium on every one of the 10 questions (p = 0.002)
and was the only Haiku 5.5 rung to return a wrong file (3 of 20 runs).

Conviction in "medium is the rung, low is acceptable slack, high is not": 88%. Conviction that low
collapses on sweeps of this size in this repo: low, since it failed 0 of 20 runs.

## Result table

All numbers are measured by `/tmp/haiku55-decisions/d1/score.py` over
`D1-retrieval-wide.rows.jsonl` unless marked estimated. 10 questions, 2 reps, so n = 20 runs per
arm. An errored run is scored as an empty answer.

| Arm | n runs | Errored runs | Mean recall | Mean precision | Exact sets | True files found | Runs with recall < 0.9 | Median output tokens | Mean output tokens | Median turns | Median wall (s) | Served |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| claude-haiku-5-5 @low | 20 | 0 | 1.000 | 1.000 | 20 | 482/482 | 0 | 2126 | 2394 | 4 | 10 | claude-haiku-5-5 |
| claude-haiku-5-5 @medium | 20 | 0 | 1.000 | 1.000 | 20 | 482/482 | 0 | 2536 | 2680 | 5 | 12 | claude-haiku-5-5 |
| claude-haiku-5-5 @high | 20 | 0 | 1.000 | 0.987 | 17 | 482/482 | 0 | 3976 | 4191 | 6 | 18 | claude-haiku-5-5 |
| claude-haiku-4-5-20251001 | 20 | 2 | 0.868 | 0.888 | 10 | 451/482 | 3 | 2196 | 2786 | 7 | 27 | claude-haiku-4-5-20251001 |
| claude-opus-5-5 @low | 20 | 0 | 1.000 | 1.000 | 20 | 482/482 | 0 | 802 | 833 | 3 | 9 | claude-opus-5-5 |

Every one of the 100 calls was served the requested model (`modelUsage` keys); none was dropped.

Per-question mean recall over 2 reps (true set size in parentheses):

| Question | 5.5 @low | 5.5 @medium | 5.5 @high | Haiku 4.5 | Opus 5.5 @low |
|---|---|---|---|---|---|
| w01 sources jev.sh directly (8) | 1.00 | 1.00 | 1.00 | 1.00 | 1.00 |
| w02 references CC_MAILBOX_DIR (29) | 1.00 | 1.00 | 1.00 | 1.00 | 1.00 |
| w03 references both KITTY_LISTEN_ON and KITTY_PID (19) | 1.00 | 1.00 | 1.00 | 1.00 | 1.00 |
| w04 Python files importing hashlib (30) | 1.00 | 1.00 | 1.00 | 0.93 | 1.00 |
| w05 defines shell function `log` (21) | 1.00 | 1.00 | 1.00 | 0.98 | 1.00 |
| w06 `flock` on a non-comment line (10) | 1.00 | 1.00 | 1.00 | 0.00 | 1.00 |
| w07 hooks/lib/*.sh WITHOUT BASH_SOURCE (34) | 1.00 | 1.00 | 1.00 | 0.97 | 1.00 |
| w08 bin/ files with python shebang, no .py (40) | 1.00 | 1.00 | 1.00 | 1.00 | 1.00 |
| w09 CC_TERM itself, not CC_TERM_KITTY (10) | 1.00 | 1.00 | 1.00 | 0.80 | 1.00 |
| w10 literal `kitty @` (40) | 1.00 | 1.00 | 1.00 | 1.00 | 1.00 |

Precision was 1.00 everywhere except: Haiku 5.5 @high on w01 (0.89 in both reps, it added the one
file that sources jev.sh through a variable, which the question excluded) and on w05 (0.95 in one
rep); Haiku 4.5 on w03 (0.95 both reps), w09 (0.86 one rep) and w06 (both reps errored).

Paired sign tests over the 10 questions (per-question mean over reps; A better / B better / ties,
two-sided p):

| A vs B | Recall | Precision | Output tokens (A lower / B lower) |
|---|---|---|---|
| 5.5 @low vs 5.5 @medium | 0/0/10, p = 1.00 | 0/0/10, p = 1.00 | 8/2/0, p = 0.11 |
| 5.5 @medium vs 5.5 @high | 0/0/10, p = 1.00 | 2/0/8, p = 0.50 | 10/0/0, p = 0.002 |
| 5.5 @low vs 5.5 @high | 0/0/10, p = 1.00 | 2/0/8, p = 0.50 | 10/0/0, p = 0.002 |
| 5.5 @low vs Haiku 4.5 | 5/0/5, p = 0.06 | 3/0/7, p = 0.25 | 5/5/0, p = 1.00 |
| 5.5 @medium vs Haiku 4.5 | 5/0/5, p = 0.06 | 3/0/7, p = 0.25 | 3/7/0, p = 0.34 |
| 5.5 @low vs Opus 5.5 @low | 0/0/10, p = 1.00 | 0/0/10, p = 1.00 | 0/10/0, p = 0.002 |
| 5.5 @medium vs Opus 5.5 @low | 0/0/10, p = 1.00 | 0/0/10, p = 1.00 | 0/10/0, p = 0.002 |

What the sign test cannot distinguish: low from medium on anything (recall, precision, or output
tokens); any Haiku 5.5 rung from Opus 5.5 @low on recall or precision; high from medium on
precision; Haiku 5.5 from Haiku 4.5 on recall (p = 0.06) or precision. What it can distinguish:
high spends more tokens than medium and than low; Opus 5.5 @low spends fewer tokens than either
Haiku 5.5 rung; Haiku 5.5 beats Haiku 4.5 on F1 (6/0/4, p = 0.03).

Reading:

- **Does low collapse on wide sweeps here? No.** 0 failures in 20 runs, including all 10 runs
  whose true set has 29 to 40 files. With 0 of 20, the one-sided 95% upper bound on low's per-run
  miss rate is 14% (estimated, 1 - 0.05^(1/20), treating runs as independent; 26% if only the 10
  questions count as independent).
- **Effort reached the model.** Output tokens rise low < medium < high on the median (2126 / 2536
  / 3976) and turns rise 4 / 5 / 6, the same positive control the narrow-lookup A/B used.
- **Medium versus low is a tie on quality and a small, unproven difference on cost.** Low's median
  is 16% below medium's. In plan quota, at 0.12 of an Opus token per Haiku token, a medium sweep
  costs about 0.38 of what Opus 5.5 @low costs for the same sweep (estimated: 2536 x 0.12 / 802;
  0.17 to 0.60 over the 0.055 to 0.19 bound) and a low sweep about 0.32.
- **Haiku 4.5 is the arm that broke.** Both w06 runs ended in "Prompt is too long" (HTTP 400 after
  22 turns of reading files), one w09 run found 6 of 10 files, and 10 of 20 runs were not exact.
  Excluding the 2 errored runs its recall is 0.964 (n = 18). It also took 2 to 3 times the wall
  time (median 27 s).

## Method (five lines)

1. Corpus: `git archive 3b3af122d bin scripts hooks lib` (796 files) extracted to a `mktemp -d`
   directory outside `/tmp`, the models' working directory; no docs, no truth files nearby.
2. Questions: 10 "list every file that ..." sweeps (`d1/questions.tsv`), true sets of 8 to 40
   files: sourcing a lib, env-var references, a two-variable intersection, a Python import (AST),
   a function definition, a command on non-comment lines, a negated property, a shebang property,
   an exact-name trap, a literal string.
3. Truth: `d1/truth.py` computes every set from file bytes (regex, Python `ast`), cross-checked by
   independent `rg`/`grep` one-liners in `d1/crosscheck.sh` (8 of 8 expressible sets match), and
   frozen with sha256 in `d1/truth.sha256` before the first model call.
4. Calls: `d1/cell.sh`, adapted from `measure/retrieval/cell.sh` (same binary 2.1.293, flags,
   `--tools "Read,Grep,Glob"`, `--setting-sources ""`, account `~/.claude-quaternary`); 5 arms x 10
   questions x 2 reps = 100 calls in one shuffled order, 4 in parallel, plus 1 pilot call (101 of
   the 150 allowed). The answer is the set of `FILE: <path>` lines in the reply.
5. Scoring: `d1/score.py` computes set recall and precision per run against the frozen truth,
   reads the served model from `modelUsage` on every row, and runs paired sign tests over questions.

Files: rows `/tmp/haiku55-decisions/D1-retrieval-wide.rows.jsonl` (100 scored rows); harness,
truth, questions, raw CLI JSON per call under `/tmp/haiku55-decisions/d1/`.

## What remains unsettled

- **Sweeps wider or harder than these.** Every true set here has at most 40 files, and most
  questions resolve with one to three Grep calls plus a set operation. The vendor's low-effort
  collapse (WANDR) is on a much wider, multi-step search. Nothing here tests true sets of 100 or
  more files, sweeps where the Grep result is truncated, or sweeps that need each candidate file
  opened and judged. That is the measurement that would separate low from medium, if anything does.
- **Low versus medium on cost.** 8 of 10 questions had lower output tokens at low, p = 0.11 at
  n = 10 questions. More questions would settle whether the 16% is real; it would not change much,
  since the amount at stake is a fraction of a cheap token stream.
- **Described-property sweeps.** Each question states its matching rule exactly so that a program
  can score it. Sweeps phrased loosely ("everything that touches the mailbox") were not tested and
  cannot be scored without judgment.
- **Subagent conditions.** These are headless `-p` runs with a fixed prompt, not Explore spawns
  from a lead with a long brief, and at 2 reps a per-question failure rate under about 25% is
  invisible.
- **High's three wrong files.** Two of the three are the same file on w01 in both reps, a file
  that does source the library, through a variable the question ruled out. That is a constraint
  miss by the stated rule, and a defensible answer by a looser one.

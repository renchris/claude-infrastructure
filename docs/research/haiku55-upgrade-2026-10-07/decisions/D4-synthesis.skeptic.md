# D4 skeptic review: research and synthesis workers, Haiku 5.5 against Opus 5.5 (2026-10-08)

Reviewed: `/tmp/haiku55-decisions/D4-synthesis.md`, its 90 rows, and the harness, answers and judge
files under `/tmp/haiku55-decisions/d4/`. No new model calls were made. Every number below is
measured by python3 over `D4-synthesis.rows.jsonl`, the raw CLI JSON or the judge JSON unless it is
marked estimated. My scripts are `/tmp/haiku55-decisions/d4-skeptic/recompute.py` (headline numbers)
and `strict.py` (extra program checks); the rest were one-off python3 or grep commands named inline.

## Verdict

I tried to overturn "keep Opus 5.5" and could not. The direction survives; the 95% and three of
the write-up's framings do not.

- **Keep research and synthesis workers on Opus 5.5 @xhigh.** I agree.
- **My conviction: 91%**, below the worker's 95%. That is about 94% for deep repo synthesis, which
  this run measured, and no change for research workers, which it did not measure at all.
- **Holds:** Haiku 5.5 won 0 of 12 arm-by-brief comparisons against the fresh Opus anchor. Haiku
  @high is clearly worse, also on the ground truth fixed before the run.
- **Does not hold as written:** the gap for Haiku @xhigh is modest and rests on judges, not on the
  pre-fixed key or on any program check. "Lost at both high and xhigh" is one Opus run per brief
  counted twice. The "1.6-point gap" is a rank, not a size.

## Recomputed headline numbers

| Claim in the write-up | Write-up | Recomputed | Match |
|---|---|---|---|
| Rows by type | 90 | 18 pair, 18 recall, 18 citecheck, 18 arm, 18 judge | yes |
| Served model = requested, arms | 18 of 18, none dropped | 18 of 18 in rows; 18 of 18 in `arms/*.raw.json` `modelUsage` keys | yes |
| Served model, judges | 18 of 18 Opus 5.5 | 18 of 18 in `judges/*.raw.json` `modelUsage` keys | yes |
| HH v OX, HX v OX majorities (n = 6 briefs) | 0-6, 0-6 | 0-6, 0-6, rebuilt from the judge rows and the label maps, not from the stored pair rows | yes |
| Judge rows for Opus over each Haiku arm | 18 of 18 | 18 of 18; 0 tie calls in all 54 judge pair calls | yes |
| HH v HX | 2-4, p = 0.69 | 2-4, exact two-sided sign p = 0.6875 | yes |
| Sign test, each Haiku arm v Opus | p = 0.031 | p = 0.03125 (2 x 1/64), the floor for n = 6 | yes |
| Mean judge score HH / HX / OX (n = 18 rows each) | 6.61 / 7.33 / 8.89 | 6.61 / 7.33 / 8.89 | yes |
| Key recall, majority of 3 (n = 130 items) | 114 / 121 / 125 | 114 / 121 / 125, recounted from `judges/*.json` and `keys/*.md` | yes |
| Judge spot-check bad cites | 31/566, 17/655, 10/758 | same; per-brief sign tests 0.0625 (HH v OX, n = 5) and 0.69 (HX v OX, n = 6) | yes |
| Wrong claims; key items contradicted | 33 / 21 / 9; 9 / 4 / 0 | same | yes |
| Program: file or line missing | 1/209, 0/302, 0/305 | same | yes |
| Program: token not at cited lines, window 2 | 26.3% / 23.3% / 32.6% | 40/152, 48/206, 42/129 | yes |
| Output tokens total; median wall | 263,688 / 473,816 / 214,360; 185 / 335 / 361 s | same | yes |
| Stored 09-28 Opus answers on the token check | 36% (72 of 198) | 72/198 in `validate-stored.jsonl` | yes |

Nothing in the write-up's tables failed to reproduce.

## The checks asked for

1. **Ground truth fixed before the models ran: partly.** What was fixed: the 6 briefs and 6 keys
   (12 of 12 `shasum -a 256` hashes equal the 09-22 frozen corpus, frozen 2026-09-22T23:16:55Z);
   `citecheck.py` (hash equals `citecheck.sha256`, stamped 04:59:50Z, first real arm call
   05:00:51Z); the judge prompt and schema (`judge.py` born 05:00:43Z by `stat`). What was not: the
   headline. Pairwise verdicts, scores, wrong-claim counts and whether an answer "states a key item
   correctly in substance" are all judge calls. The two program measures that needed no judgment
   do not separate the arms (finding 4).
2. **Identical tools, prompts and inputs: yes.** `diff` of `d4/run-synth.sh` against the 09-28
   harness changes 5 lines: the binary, the snapshot and brief paths, and two env vars. One prompt
   and one tool rule for all three arms. The snapshot is byte-identical to the pinned commit: 3,743
   of 3,743 blob hashes equal `git ls-tree -r 47c3317eb` (`git hash-object --no-filters`). Turns
   were alike (HH 17 to 31, HX 17 to 27, OX 23 to 26) and so were permission denials (18 / 13 / 16
   over 6 runs each), so no arm lost tool budget the others kept. Effort reached the model: HX has
   more thinking tokens than HH on 6 of 6 briefs (`modelUsage.thinkingTokens`, p = 0.031).
   Not checkable: which commands each arm ran. The runs used `--no-session-persistence`, so only
   the final answer and the denied commands survive. No denied command and no answer mentions the
   key directory or a key item id (grep).
3. **Served model read on every row, substitutions dropped: yes.** 36 of 36 raw files. `tally.py`
   asserts it for judges. The 18 void calls never reached a model (0 tokens, 12 + 6 argument
   errors), so no real run is hidden there.
4. **Is n large enough?** For "Opus is preferred more often than not on briefs like these": yes,
   barely. 6-0 gives exact two-sided p = 0.031, and the one-sided 95% lower bound on Opus's
   per-brief win rate is 0.61 (0.05^(1/6)). For "Haiku loses every time": no. For "both efforts
   lose": the two tests are not independent, see finding 3. For the size of the gap: no.
5. **Ceiling or floor effect: yes, on three of the measures, not on the pairwise verdict.**
   File-and-line existence is at the floor for every arm (0 to 1 bad). Key recall is near the
   ceiling (88% to 96%). The judge score is pinned: the top-ranked output got exactly 9 in 16 of 18
   judge rows, and Opus got 9 in 16 of 18, including a brief where judges logged 5 bad Opus cites
   (T5) and one where they logged 4 Opus wrong-claim flags (T6). The pairwise verdict is the only
   measure with room, and it is a judgment.
6. **Does the recommendation follow from the numbers?** The direction does. The step from "Opus is
   better" to "Opus is worth about 3.7 times the quota" (estimated: 1 / 0.27, the worker's draw
   figure for Haiku @xhigh) is not measured; it comes from the prior
   that a wrong synthesis claim is expensive and from the fleet note that weekly quota mostly
   strands. I think that step is right, but it is a judgment and should be labeled as one. The
   "research" half of the decision follows from no number here.
7. **Cheaper explanations.** (a) Judges share the winner's taste: all 18 judge calls are Opus 5.5,
   the same model as the winning arm. Partly rebutted, see finding 5. (b) Opus simply wrote more:
   its answer is the longest on 6 of 6 briefs (median 19,285 characters against 16,077 and 13,129)
   and judges credited it with more extras (153 / 124 / 84). Length alone does not drive the
   judges, since in HH v HX the longer answer won only 3 of 6. But "more verified coverage inside
   the same 25-call bound" is most of what separates Opus from Haiku @xhigh, more than accuracy
   per claim. (c) Label position: no, Opus sat in X, Y and Z 6 times each and won from all three.
   (d) Tool budget or denials: no, see check 2.

## Findings that change the write-up

1. **On the ground truth fixed before the run, Haiku @xhigh is not distinguishable from Opus.**
   Majority key recall is 121 against 125 of 130. At item level Opus alone hit 5 items and Haiku
   @xhigh alone hit 1 (exact McNemar p = 0.22; per brief Opus ahead by exactly one item on 4 briefs
   and tied on 2, sign p = 0.125). The Opus anchor itself moved by that much between days: 127 of
   130 on 09-28 against 125 today, and 25 against 22 of 25 on T2 alone (`table.md` of the 09-28
   probe). Haiku @high is different: Opus alone hit 12 items, Haiku @high alone 1 (p = 0.003; items
   inside a brief are not independent, so read that as descriptive).
2. **Three of the 12 Opus wins rest only on extras beyond the key, and the judges called most of
   them narrow.** T2, HX: equal recall (22 and 22), Haiku had 0 bad cites and 0 wrong claims while
   Opus had 3 bad-cite flags and 2 wrong-claim flags summed over the 3 judges. T2, HH: Haiku @high
   hit a key item Opus missed (23 against 22) and judges wrote "wins narrowly" and "the margin is
   narrow". T6, HH: both 15 of 15, the judges logged no error of any kind for Haiku @high and a
   wrong claim for Opus; two of the three judges wrote "narrowly". Counting those three as ties
   gives 4-0-2 for HH v OX (sign p = 0.125) and 5-0-1 for HX v OX (p = 0.0625). The other nine
   wins rest on key items or on specific errors.
3. **"Lost at both high and xhigh" is one Opus run per brief used twice.** There are 6 Opus runs,
   not 12. A good Opus draw on a brief beats both Haiku arms at once. Likewise 18 of 18 judge rows
   is 3 calls of one model reading the same three texts, so the independent unit is the brief:
   n = 6, once.
4. **The program citation check, which the task asked for as scoring item 1, gives no support to
   the headline.** Existence is at the floor. Token-at-line reads worst for Opus at every window I
   tried: 34.1%, 32.6%, 31.8%, 29.5%, 28.7% at 0, 2, 5, 10 and 25 lines, against 26.2% falling to
   19.9% for Haiku @xhigh (n = 129 and 206 tokens, `strict.py`). I agree with the worker that this
   measures how answers abbreviate code inside backticks, not bad citations: I read a random 14 of
   Opus's 29 "absent" tokens and most were condensed code such as
   `.count .sid .cwd .mech .ship .blocked` (my reading, not a program result).
   Two more program checks I added after seeing the data (so exploratory) also sit at the floor:
   exact-path existence 2/166, 1/227, 0/231 (one of the two HH misses is a path the answer
   elided with dots), and backticked identifiers found nowhere in the snapshot 1/135, 1/134,
   1/124. None of those three is an invented symbol: two are `max_fable_spawns`, a prefix of the
   real key `max_fable_spawns_per_session`, and one is a search term Opus said it grepped for. The worker's
   checker forgives a wrong directory when the basename is unique, so it scored Haiku @xhigh's
   `hooks/session-writes.sh` (the file is `hooks/lib/session-writes.sh`) as fine; the judges
   caught it. So "bad-citation rate by program" is uninformative here, and the rates that do order
   the arms (5.5%, 2.6%, 1.3%) are judge counts over denominators the judges reported themselves
   (round values such as 30, 60 and 70).
5. **The judges' reasons are real facts, which is the main thing that keeps the result standing.**
   I checked 9 judge-asserted differences against the snapshot and the answers with grep and sed:
   9 of 9 are true. Five are Haiku @xhigh errors: it said a grep for `frontier-spawn-gate` outside
   `docs/` hits only 2 files (18 files hit); it said no other variable has divergent defaults
   (`CC_BOARD_STALE_S` is 300 in `hooks/accounts-board.sh:52` and 900 in `bin/cc-board:30`); it
   said the only scheduled caller is the deploy-live plist (the autonomy-sweep path to
   `cc-premise sweep` exists and its answer never names it); it said no in-repo registration of
   `dispatch-assert.sh` exists (it is at `docs/activation/pending-activation/11-dispatch-assert-activate.sh:39`);
   and the wrong path above. Two are Haiku @high errors (no kill switch found, though
   `CLAUDE.global.md:334` reads `Kill-switch: CC_LADDER=off`; a nonexistent `hooks/session-busy.sh`).
   Two are Opus errors the judges also logged (an incomplete function list in T6, an off-by-one in
   T2). False "only" and "none" claims are the costly kind for a synthesis worker because nothing
   downstream flags them. Opus made one too, so this is a rate difference, not a clean split.
6. **Blinding hid the arms but not the study.** The judge prompt names
   `/tmp/haiku55-decisions/d4/...`, and 13 of 18 answers repeat that path (5 HH, 5 HX, 3 OX). No
   answer names its own model and no judge text guesses one (grep), so arm identity did not leak.
   Every judge did know a Haiku arm was on the panel.
7. **The cost line mixes measured and estimated.** Measured: output tokens (HX 2.21 times Opus, HH
   1.23 times) and CLI dollars ($0.36, $0.99, $8.95 for 6 briefs, so 4% and 11% of Opus).
   Estimated: the plan-quota figures 0.27 and 0.15, which are those token ratios times the 0.12
   weight from the 10-07 upgrade study (bounds 0.055 to 0.19). These rows cannot check that weight.

## Recommendation after review

Keep research and synthesis workers on Opus 5.5 @xhigh. Record the reason as: on 6 frozen
deep-tracing briefs Haiku 5.5 won none at either effort against a same-day Opus run (exact sign
p = 0.031, n = 6), Haiku @high also trails on the pre-fixed key, and Haiku @xhigh made verified
false "only" or "none" claims on 4 of 6 briefs. Do not record the 1.6-point score gap or the
judge bad-citation rates as a measured size, do not count the two Haiku arms as two independent
confirmations, and mark the research half as still resting on vendor evidence.

Conviction 91%. It would reach the worker's 95% with any one of: a judge seat that is not Opus 5.5
agreeing on these same answers, a second Opus run per brief, or a web-research brief set.

## Not settled by this measurement

- Research workers. No brief here involves the web or a wide, shallow sweep.
- The size of the gap for Haiku @xhigh. On the frozen key it is 4 of 130 items (p = 0.22) and the
  score scale is pinned at 9 for whichever answer ranks first.
- Whether a judge that is not Opus 5.5 gives the same ordering. The 09-28 own-family check used an
  Opus 5 seat and Sonnet answers; it was not repeated for Haiku.
- Run-to-run variance. One run per brief per arm, and both Haiku comparisons share one Opus run.
- Whether the quality gap is worth about 3.7 times the plan quota (estimated) in a week when quota
  binds. The 0.12 draw weight comes from another study.
- A bad-citation rate by program. Existence is at the floor for every arm and the token check
  tracks quoting style.
- What each arm actually read. No transcripts were kept, so "no arm reached the live checkout that
  holds the keys" rests on the answers and the denied commands only.
- Haiku 5.5 @max, @medium, and a Haiku draft checked by an Opus verifier.

Deviation from the brief: besides this file I wrote scratch inputs under
`/tmp/haiku55-decisions/d4-skeptic/` (two scripts and four hash lists), which the brief did not
name. Nothing else was created or changed, and no git state was touched.

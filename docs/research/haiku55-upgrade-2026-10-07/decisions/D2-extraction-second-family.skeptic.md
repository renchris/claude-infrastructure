# D2 skeptic review: Haiku 5.5 on classification and table extraction (2026-10-08)

Reviewed: `/tmp/haiku55-decisions/D2-extraction-second-family.md` and its 144 raw rows. No new model
calls were made. Every number below is measured by inline `python3` over
`D2-extraction-second-family.rows.jsonl`, `d2/cls-truth.json`, `d2/ext-truth.json` and
`git -C /Users/chrisren/Development/claude-infrastructure log/show` at the pinned commit `c3ed0a38`,
with my own parsers and tests (not the worker's `score.py`), unless marked estimated.

## Verdict

The main verdict survives: **keep D2 as written. Opus 5.5 stays the default; Haiku 5.5 stays
admissible where quota binds, on checkable output only; Haiku 5.5 does not become the default.**
My conviction: **85%** (worker: 88%).

Two parts of the worker's "narrowing" do not follow from the numbers and should be dropped or moved:

1. **The clause admitting Haiku 5.5 for judgment classification "where about 10 points is an
   acceptable price" widens D2; it does not narrow it.** D2 says "checkable output only". A commit
   label is not checkable. The data lean toward keeping Haiku out of that sub-slot, and the "10 points"
   is not a stable number (see below).
2. **"Validate and retry" is pinned on the wrong arm for extraction.** On extraction the replies that
   broke "ONLY a JSON object" were Opus 5.5 at low (2 of 18 calls), not Haiku 5.5 (0 of 36 calls).
   Haiku's extraction fault was valid JSON holding real shas from the wrong column (table T10, 4 of 6
   Haiku reads), which a parse-and-retry consumer passes. The JSON wording and the validator belong on
   the slot for both models; they do not guard the fault Haiku actually showed.

## Recomputation

| Headline | Worker | Mine | Match |
|---|---|---|---|
| Classification v1, salvage parser, correct of 180 (Haiku low, Haiku medium, Opus low, Opus medium) | 112, 113, 130, 131 | 112, 113, 130, 131 | yes |
| Classification v1, strict parser | 49, 88, 130, 131; unparseable 5, 2, 0, 0 of 9 | same | yes |
| Classification v2, correct of 180 | 112, 113, 133, 127 | same | yes |
| Pooled, correct of 360 | 224, 226, 263, 258 | same | yes |
| Output tokens per label; quota vs Opus low (estimated, x0.12 [0.055, 0.19]) | 35.7, 46.9, 15.0, 26.3; 0.29 [0.13, 0.45], 0.38 [0.17, 0.59], 1.00, 1.76 | same | yes |
| Sign tests, n = 60 items, all 15 cells | e.g. Haiku medium vs Opus low pooled 4 / 12 / 44, p = 0.077 | all 15 identical | yes |
| Extraction recall, of 516 | 516, 516, 441 strict (515 salvage), 516 | same | yes |
| Extraction precision | 516/520, 516/525, 441/442, 516/516 | same | yes |
| Tables perfect of 36; quota per table (estimated) | 34, 33, 30 (34 salvage), 36; 0.31, 0.35, 1.00, 1.56 | same | yes |
| Extraction sign tests, n = 12 tables | 3 / 1 / 8 p = 0.625; 0 / 1 / 11; 1 / 1 / 10; 0 / 3 / 9 p = 0.250 | same | yes |
| Per-type counts (v2), self-consistency (v1), malformed call sizes 319 to 358 tokens | as written | same | yes |

One labeling slip: in the v1 table the "Majority-of-3 correct" values for Haiku (36 and 37) come from
the salvage parser. Under the strict parser they are 10 and 35 (`d2/score-strict.out` agrees).

## The checks

**Was truth fixed by a program before the models ran?** Yes for both families, with a caveat on what
the classification truth means. `shasum -a 256` of both truth files matches `d2/truth.sha256`; the
truth files carry mtime 04:57:28Z to 04:57:29Z and the first call (the smoke call) is logged at
04:57:52Z. I reproduced 60 of 60 labels from `git log -400` at `c3ed0a38`, found 12 of 12 tables
verbatim in the files at that commit and in the prompts, and re-derived all 12 truth sets (172 values)
with my own pass. Opus at medium also returned exactly the truth on 36 of 36 table reads, which is an
independent read that the extraction truth is right. The caveat: the classification label is a program
reading one author's habit. All 60 commits are authored "Chris Ren" with no co-author trailer, so
whether a model wrote those subjects cannot be told from the log.

**Identical tools, prompts and inputs?** Same `cell.sh`, same flags, same prompt file per unit, arms
interleaved. One difference the write-up does not mention: on all 12 units the Haiku arm was billed
about 780 more cache-creation tokens than the Opus arm (779 to 785, comparing each unit's smallest
count), constant across prompts of 1,952 to 6,312 bytes.
A tokenizer difference would scale with length; a constant offset means the 2.1.293 binary sends a
model-specific system prompt. The user prompt was the same. This mirrors what the fleet would run, so
it does not bias the fleet decision, but the arms did not see byte-identical context.

**Served model on every row, substitutions dropped?** Yes. 144 of 144 rows have exactly one
`modelUsage` key, equal to the requested model, with matching `canonicalModel`. `calls.log` has 145
lines: 144 scored calls plus 1 smoke call. The published rows equal `d2/results.jsonl` plus
`d2/results2.jsonl` row for row. 0 failed, 0 errors, 0 dropped.

**Is n large enough?**
- Classification. The worker's pairwise sign tests are right and mostly do not reach 0.05. The single
  natural contrast, model against model with both efforts pooled (12 reps per item, n = 60 items), is
  stronger: Haiku better on 4 items, Opus on 15, 41 ties, exact two-sided sign test p = 0.019. The gap
  is 9.9 points (450 vs 521 of 720); an item bootstrap (20,000 resamples) gives a 95% interval of 2.1
  to 18.1 points. So the direction is supported and the size is not.
- It is fragile to one batch. Each call held a fixed batch of 20 items. The gap by batch is 0.8, 5.4
  and 23.3 points. Between Haiku medium and Opus low, 28 of the 37-label pooled gap comes from batch 3.
  Without batch 3 the model-level test is 2 vs 8, p = 0.109, gap 3.1 points. Items never changed batch
  or order, so an item effect and a within-call context effect cannot be separated.
- The 180 and 360 label counts overstate the evidence. Reps are near copies (Opus low gave the same
  label in all 6 reps on 56 of 60 items, Haiku medium on 43). 11 of 60 items were wrong and 30 were
  right in all 24 arm-reps, so 19 items carry the whole comparison.
- Extraction. No sign test applies usefully: with 8 to 11 ties of 12 tables there are at most 4
  discordant tables, and the smallest two-sided p that 4 discordant tables can produce is 0.125. The
  data cannot show a difference and cannot show equivalence.

**Ceiling or floor?** Both families have one.
- Extraction sits at the ceiling: three of four arms at recall 1.000 on tables of 486 to 5,018 bytes
  and 6 to 16 rows. Per table, counting content faults only (salvage parser), Haiku (both efforts) had
  one on 2 of 12 tables (T10, T03), Opus low on 2 of 12 (T04, T05), Opus medium on 0 of 12. Zero faults in 12 tables still allows a true per-table
  fault rate up to 26.5% (Clopper-Pearson 95%); 2 in 12 allows 2.1% to 48.4%.
- Classification has a noisy-label ceiling near 0.74. The menu offered six labels, but chore and
  refactor are 2 of 60 truth items (2 of 380 conventional subjects in the 400-commit window; the rest
  are docs 128, fix 125, feat 88, test 37). Every arm still spent 13.1% (Opus, both efforts) to 16.1%
  and 17.5% (Haiku low, medium) of its labels on those two. Wrong chore/refactor labels are 51 of Haiku
  medium's 134 errors and 35 of Opus low's 97, which is 16 of the 37-label gap.

**Does the recommendation follow from the numbers or from the prior?** The core does. Haiku showed no
quality edge anywhere, wall time was level (median 6.1 to 8.6 s Haiku, 6.7 to 11.3 s Opus), and a
saving in quota is worth nothing in a week where quota does not bind, so there is no measured reason to
make Haiku the default. Admission on checkable extraction is supported: recall 516 of 516 at both
efforts on a second extraction family at about 0.3x the estimated quota. The two additions listed
under Verdict are the parts that come from the worker's framing and not from the rows.

**Cheaper explanations for the classification gap.**
- Opus agrees with this author's labeling habit more often, which is not the same as being more
  accurate. There is no answer key, and 11 items defeated every arm in every rep.
- The label-menu mismatch above (16 of 37 labels).
- One batch of twenty (28 of 37 labels).
- Sample mix does not explain it: reweighting per-class accuracy to the window's natural mix gives
  Haiku 0.640 and 0.652, Opus 0.772 and 0.754, a gap of about 12 points.
- For the format fault: the v1 wording said "one per line" and Haiku did exactly that. All 7 malformed
  Haiku replies came from calls with 0 thinking tokens (7 of 9 such v1 calls; 0 of 9 v1 calls that
  thought first). The wording effect itself holds: 7 of 18 against 0 of 18, Fisher exact p = 0.0076.

**Token accounting.** `output_tokens` includes thinking tokens on every row (mean output minus mean
thinking is 282 to 414 tokens per call across the twelve arm-by-family cells, the size of the visible
answer), so the quota figures count thinking. Haiku's larger token count is thinking: 926 and 1,094 mean thinking tokens per extraction
call at low and medium, against 92 for Opus low.

## What this measurement cannot support

- **The size of the classification gap.** The interval is 2 to 18 points and one batch drives it.
  "About 10 points" should not be written into a decision as a price.
- **That the gap is accuracy.** It may be agreement with one author's convention. A planted answer key,
  a label menu that matches the truth, and items re-shuffled across calls would settle it.
- **Extraction beyond small tables.** 12 tables under 5.1 KB cannot rank the arms, prove equivalence,
  or say anything about long documents.
- **That a validate-and-retry consumer makes Haiku extraction safe.** Its observed fault (extra values
  from a neighboring column) is valid output, and it rests on one table.
- **Quota per task.** It is estimated from output tokens and the 0.12 ratio and was not metered. The
  input side is left out although calls created 3,001 to 4,708 cache tokens against 300 to 1,454
  output tokens (means by arm and family). Mean list cost per call (`cost_usd`, list dollars, not quota) was 0.04 of Opus low for
  Haiku medium on both families, which shows only that the input side could move the ratio.
- **"At medium" in D2.** Low and medium were not separated for Haiku on either family (p = 0.58 and
  1.00), and the T10 fault appeared in 3 of 3 medium reads against 1 of 3 low reads.
- **How often quota binds.** If it binds every week, "admissible where quota binds" and "default" are
  the same policy for checkable extraction, and nothing here tests that.
- **The first family's figures** (2.6x tokens, 0.3x quota on env-var extraction) were quoted from the
  record and not rechecked here.

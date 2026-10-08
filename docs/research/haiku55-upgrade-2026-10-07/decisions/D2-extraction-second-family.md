# D2: Haiku 5.5 on a second and third extraction/classification family (2026-10-07, binary 2.1.293)

## Recommendation

**Keep D2 as written: Opus 5.5 stays the default for the extraction/classification slot, and Haiku 5.5
stays "admissible where quota binds". Do not make Haiku 5.5 the default.** Narrow the admission by
family:

- **Verbatim extraction (copy a column's values out of a table): admissible.** Haiku 5.5 found every
  value (recall 1.000 at both efforts, 516 of 516) at about 0.3x the quota of Opus 5.5 at low. Its
  one repeatable fault is over-inclusion: on one table it also returned 3 shas from the neighboring
  columns, in 3 of 3 reps at medium. A sign test over 12 tables cannot tell any arm from any other.
- **Judgment classification (label a commit subject): admissible only where about 10 points of
  accuracy is an acceptable price.** Haiku 5.5 scored 0.62 to 0.63 against Opus 5.5's 0.71 to 0.74 in
  two independent runs. That gap is what keeps it from being the default.
- **Two conditions on any Haiku 5.5 slot of this kind:** the prompt must say "one valid JSON array"
  (a loose wording produced unparseable JSON in 7 of 18 Haiku calls and 0 of 18 Opus calls), and the
  consumer must validate the output and retry on a parse failure.

Conviction in "stay admissible, not default": **88%** (was 75%).

Inside the Opus 5.5 default, low is the rung to use for classification (medium bought nothing and
cost 1.76x the tokens); for extraction medium was the only arm with 36 of 36 perfect table reads.

## Results

All numbers are measured by `/tmp/haiku55-decisions/d2/score.py` over the raw rows unless marked.
Quota columns are estimated: measured output tokens times the record's Haiku-to-Opus per-output-token
ratio 0.12 (bounds 0.055 to 0.19), relative to Opus 5.5 at low = 1.00.

### (a) Classification: 60 commit subjects, 6 labels, batches of 20

Main run, prompt v1 (ends "...one per line, in the same order"), 3 reps, 180 labels per arm, 9 calls
per arm.

| Arm | Accuracy, strict parser | Accuracy, salvage parser | Calls with unparseable JSON (of 9) | Majority-of-3 correct (of 60) | Mean output tokens per call | Median wall (s) |
|---|---|---|---|---|---|---|
| claude-haiku-5-5 @low | 0.272 (49/180) | 0.622 (112/180) | 5 | 36 | 655 | 5.8 |
| claude-haiku-5-5 @medium | 0.489 (88/180) | 0.628 (113/180) | 2 | 37 | 768 | 6.5 |
| claude-opus-5-5 @low | 0.722 (130/180) | 0.722 (130/180) | 0 | 43 | 318 | 6.6 |
| claude-opus-5-5 @medium | 0.728 (131/180) | 0.728 (131/180) | 0 | 44 | 446 | 6.5 |

Follow-up run, prompt v2 (ends "...ONLY one valid JSON array holding one object ... for each
subject"), 3 reps, 180 labels per arm, 9 calls per arm. Every call parsed under the strict parser.

| Arm | Accuracy | Unparseable (of 9) | Majority-of-3 correct (of 60) | Mean output tokens per call | Median wall (s) |
|---|---|---|---|---|---|
| claude-haiku-5-5 @low | 0.622 (112/180) | 0 | 38 | 772 | 6.3 |
| claude-haiku-5-5 @medium | 0.628 (113/180) | 0 | 38 | 1106 | 7.4 |
| claude-opus-5-5 @low | 0.739 (133/180) | 0 | 44 | 282 | 7.0 |
| claude-opus-5-5 @medium | 0.706 (127/180) | 0 | 41 | 606 | 8.1 |

Both runs pooled (salvage parser, 360 labels per arm, 18 calls per arm; `d2/pooled.out`):

| Arm | Accuracy | Output tokens per label | Quota per label vs Opus @low (estimated) | Opus-equivalent output tokens per correct label (estimated) |
|---|---|---|---|---|
| claude-haiku-5-5 @low | 0.622 (224/360) | 35.7 | 0.29 [0.13, 0.45] | 6.9 |
| claude-haiku-5-5 @medium | 0.628 (226/360) | 46.9 | 0.38 [0.17, 0.59] | 9.0 |
| claude-opus-5-5 @low | 0.731 (263/360) | 15.0 | 1.00 | 20.5 |
| claude-opus-5-5 @medium | 0.717 (258/360) | 26.3 | 1.76 | 36.7 |

Sign tests, paired per item on the count of correct reps, n = 60 items:

| Comparison | First better | Second better | Ties | p (v1 salvage) | p (v2) | p (pooled, 6 reps) |
|---|---|---|---|---|---|---|
| Haiku @medium vs Opus @low | 4 / 3 / 4 | 10 / 11 / 12 | 46 / 46 / 44 | 0.180 | 0.057 | 0.077 |
| Haiku @medium vs Opus @medium | 4 / 4 / 4 | 12 / 10 / 12 | 44 / 46 / 44 | 0.077 | 0.180 | 0.077 |
| Haiku @low vs Opus @low | 4 / 2 / 4 | 11 / 12 / 13 | 45 / 46 / 43 | 0.118 | 0.013 | 0.049 |
| Haiku @low vs Haiku @medium | 4 / 2 / 5 | 5 / 4 / 8 | 51 / 54 / 47 | 1.000 | 0.688 | 0.581 |
| Opus @low vs Opus @medium | 1 / 5 / 4 | 2 / 2 / 3 | 57 / 53 / 53 | 1.000 | 0.453 | 1.000 |

(Cells read v1 / v2 / pooled.) What the sign test can and cannot say: Haiku @medium against Opus
@low is not distinguishable at 0.05 in either run or pooled (p 0.18, 0.057, 0.077), although the
direction is the same every time, about 3 items to 1 in Opus's favor, and the accuracy gap repeats
to the third decimal for Haiku (0.622 and 0.628 in both runs). Haiku @low against Opus @low is
distinguishable in v2 and pooled. Low against medium is not distinguishable for either model. Under
the strict parser on v1 every Haiku-versus-Opus comparison is distinguishable (p < 0.001), but that
is the format fault, not the labels.

Where the labels go wrong (v2, correct of n by true type): `feat` is the hard class for everyone
(Haiku @medium 15/45, Opus @low 24/45); `docs` is where Haiku falls behind (28/42 vs 37/42); `fix`
(40/45 vs 41/45) and `test` (24/42 vs 25/42) are level. Self-consistency in v1 (items with 3 identical
reps, of 60): Haiku @medium 46, Opus @low 57.

The format fault: in v1, 7 of 18 Haiku calls returned objects with no commas between them or one
array per line; 0 of 18 Opus calls did. All 7 were calls of 319 to 358 output tokens, the size of
the bare answer; every Haiku call above 890 tokens parsed. In v2, 0 of 36 calls were malformed.

### (b) Structured extraction: 12 markdown tables from docs/plans, one named column each

7 sha columns, 4 file-path columns, 1 date column; 172 distinct truth values; two tables per call;
3 reps; 36 table reads and 18 calls per arm; 516 truth values per arm.

| Arm | Recall | Precision | Tables perfect (of 36) | Calls breaking "ONLY a JSON object" (of 18) | Mean output tokens per call | Output tokens per table | Quota per table vs Opus @low (estimated) | Median wall (s) |
|---|---|---|---|---|---|---|---|---|
| claude-haiku-5-5 @low | 1.000 (516/516) | 0.992 (516/520) | 34 | 0 | 1285 | 643 | 0.31 [0.14, 0.48] | 7.8 |
| claude-haiku-5-5 @medium | 1.000 (516/516) | 0.983 (516/525) | 33 | 0 | 1454 | 727 | 0.35 [0.16, 0.55] | 8.6 |
| claude-opus-5-5 @low, strict parser | 0.855 (441/516) | 0.998 (441/442) | 30 | 2 | 506 | 253 | 1.00 | 8.6 |
| claude-opus-5-5 @low, salvage parser | 0.998 (515/516) | 0.998 (515/516) | 34 | 2 | 506 | 253 | 1.00 | 8.6 |
| claude-opus-5-5 @medium | 1.000 (516/516) | 1.000 (516/516) | 36 | 0 | 790 | 395 | 1.56 | 11.3 |

Every error, by cause:

- Haiku @medium: table T10 (sha column 3 of `PUBLIC_REPO_HYGIENE.md`), 3 of 3 reps, returned the same
  3 shas that sit in other columns. Haiku @low did the same in 1 of 3 reps, and once returned a
  comma-joined path fragment from T03.
- Opus @low: 2 of 18 calls wrote a full answer, then a sentence ("Correction: `install.sh` has no
  slash..."), then a second corrected answer. The second answer was right; a strict parser reads the
  reply as invalid and loses both tables in the call (74 of the 75 missed values). The third rep kept
  `install.sh`. One rep missed `tests/`.
- Opus @medium: none.

Sign tests, paired per table on errors summed over 3 reps, n = 12 tables: no pair of arms is
distinguishable. Haiku @medium vs Opus @low: 3 better, 1 worse, 8 ties, p = 0.625 (strict). Haiku
@medium vs Opus @medium: 0 better, 1 worse, 11 ties, p = 1.000. Haiku @low vs @medium: 1, 1, 10 ties,
p = 1.000. Opus @low vs @medium: 0 better, 3 worse, 9 ties, p = 0.250. With 8 to 11 ties, twelve
tables cannot separate arms that differ on one or two tables.

### Against the first family

The record's env-var extraction had Haiku @medium at 2.6x Opus @low's output tokens and about 0.3x
its quota. Here: 2.9x tokens and 0.35x quota on table extraction, 3.1x tokens and 0.38x quota on
classification (pooled). The cost claim in D2 holds on all three families. The quality claim ("ties
or beats Opus") holds on both extraction families and fails on classification.

## Method (five lines)

1. Truth was fixed before any model ran (`d2/build.py`, hashes and time in `d2/truth.sha256`): commit type = the stripped Conventional Commits prefix of 60 subjects from `git log --format=%s -400` at `c3ed0a38`, drawn newest-first with caps feat 15, fix 15, docs 14, test 14, chore 1, refactor 1 (the window holds only 1 chore and 1 refactor), shuffled with a fixed seed; column values = a regex parser over the same table bytes the model saw, for 12 tables picked by rule (most values first, one per file, no ambiguous all-digit or all-letter hex token).
2. Calls reuse the record's `measure/extraction/cell.sh`: binary 2.1.293, `-p --model --effort --tools "" --setting-sources "" --strict-mcp-config --no-session-persistence --output-format json`, config dir `~/.claude-quaternary`, a fresh empty directory per call, 4 in parallel with the four arms interleaved inside every unit and rep.
3. Scoring reuses the record's `score.py` parser (first bracket to last bracket, `json.loads`) as the strict score; a salvage parser (regex over objects; last complete JSON object) was written after the malformed replies were seen and is reported beside it, never instead of it.
4. 145 calls in total: 1 smoke, 108 main (4 arms x 9 units x 3 reps), 36 follow-up (classification only, prompt v2). All 144 scored calls were served the requested model per `modelUsage`; 0 dropped, 0 errors, 0 refusals.
5. Sign tests are two-sided exact binomial on paired per-item (n = 60) or per-table (n = 12) scores, ties dropped.

Deviations from the brief: tables went two per call (12 tables at one per call would have needed 144
calls and left none for classification inside the 150 cap); the mix is 7 sha, 4 path, 1 date because
only one date table met the selection rule; the prompt v2 follow-up was added after seeing v1.

## Files

- Raw rows (144, with a `run` field): `/tmp/haiku55-decisions/D2-extraction-second-family.rows.jsonl`
- Work directory: `/tmp/haiku55-decisions/d2/` (`build.py`, `prompts.py`, `prompts/`, `cell.sh`, `run.sh`, `run2.sh`, `score.py`, `cls-truth.json`, `ext-truth.json`, `truth.sha256`, `score-strict.out`, `score-lenient.out`, `score2-strict.out`, `pooled.out`, `calls.log`)

## What remains unsettled

- **The classification truth is one author's habit, not a gold label.** No arm passed 0.74 and `feat` was near chance for all, so part of the gap may be agreement with this author's conventions. A family with a planted answer key would say whether the 10 points travel.
- **The Haiku-versus-Opus classification gap at medium is not distinguishable by a sign test** (p 0.057 to 0.18 across runs, 0.077 pooled). It replicated in direction and size across two runs, but those runs share the same 60 items, so they are not independent evidence about new items.
- **Low versus medium for Haiku 5.5 is not separated on either family** (p 0.58 and 1.00). Low spends 12% (extraction) to 24% (classification) fewer output tokens here; nothing measured says medium earns the difference on this slot.
- **The tables were small** (0.5 to 5 KB, 6 to 16 rows) and extraction sat at ceiling for three of four arms. Long documents, and inputs near the 100,000-token threshold where the record says billing changes, are untested.
- **The format fault was provoked by one wording and cured by another, each at 18 Haiku calls.** How often Haiku 5.5 emits unparseable JSON under other loose wordings, and whether a JSON schema flag removes the risk, is not measured.
- **Haiku's cross-column over-inclusion rests on one table** (T10, 4 of 6 Haiku reads). Whether it is general to tables with look-alike values in neighboring columns needs more such tables; here only 5 of 12 had any.
- **Quota is estimated, not metered.** The 0.12 ratio carries bounds of 0.055 to 0.19, and no meter was read during these runs; input and cache-write draw is not in the per-task figures.
- **A quota-bound week** is still the condition under which the saving is worth anything; that part of D2 is untouched by this measurement.

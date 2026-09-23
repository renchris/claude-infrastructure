# Review-class follow-up — 3 samples per arm, and a mixed-model judge panel — 2026-09-22

**Asked by:** the Opus 5.5 SSOT lead (pane 564, `claude-infrastructure-564`), which owns
`model-config.yaml` and applies these verdicts. **Extends, without editing:**
`docs/research/opus55-effort-sweep-2026-09-22/` (landed `501e4490e`) and
`docs/research/fable51-effort-sweep-2026-09-10/`.

## Verdicts

**Recall only.** False positives, citation accuracy and fabrication were NOT scored, here or in either
record this extends. Scope is the review class: anchored review of one file, on the 7 defective
briefs of `tests/fixtures/codex-probe/` (36 ground-truth items).

**Q1 — JUDGE SLOTS: `o55@xhigh` STAYS. Conviction 92% that Opus 5 @max is not better on this class.**
The case for o5@max came from single samples, and they did not hold up over 3 samples:

| | o5@max | o55@xhigh | discordant items (o5@max only / o55@xhigh only) | p (items, ≥2 of 3 samples) |
|---|---|---|---|---|
| P1 = 3× claude-opus-5 @xhigh | 13 · 11 · 11 → mean **11.7** · items **12** | 10 · 15 · 13 → mean **12.7** · items **12** | 1 / 1 | **1.00** |
| P2 = one judge per model family | 12 · 10 · 9 → mean **10.3** · items **11** | 9 · 14 · 13 → mean **12.0** · items **11** | 1 / 1 | **1.00** |

The 09-22 "o5@max = 13, the best arm measured" was its best of three samples, and o55@xhigh's 10
was its worst. With three samples each, the point estimate favours o55@xhigh under both panels. At
the cell level (not independent), 9 v 6 cells under P1 and 11 v 6 under P2 go o55@xhigh's way. o5@max
also costs more: ≈1.2× o55@xhigh's quota per task and about 2× its wall time.
*What would move it:* a class that scores FP or citation accuracy, where Opus 5 @max might lead; or a
larger corpus where the 1-v-1 discordance opens up.

**Q2 — ADVERSARIAL COMPLEMENT: `f51@high` STAYS. Conviction 80%.** It complements Opus 5.5 @high
more than Opus 5 @high does, under both panels, but only by 2 items. The price is 2.5× o5@high's quota.

| complement to o55@high | f51@high | o5@high |
|---|---|---|
| items X finds that o55@high misses, mean over 9 sample pairings — P1 / P2 | **2.44 / 2.44** | 1.67 / 1.33 |
| items X finds (≥2 of 3 samples) that o55@high misses (≥2 of 3) — P1 / P2 | **4 / 4** | 2 / 2 |
| union coverage with o55@high, items (≥2 of 3) — P1 / P2 | **13 / 12** | 11 / 10 |
| est. weekly quota per 7-brief pass [W-pp] | 2.39 [2.22–2.56] | 0.97 |

Opus 5 @high's two complement items (cp-04#6, cp-08#3) are **both also Fable's**. Fable adds two
more that o5@high found in 0 of 3 samples: cp-02#4 and cp-09#2, each found by Fable in 2 of 3. So on
this corpus Fable's complement is a strict superset of Opus 5's. It is only 2 discordant items,
though: the paired sign test is p = 0.50 under both panels. At the cell level, 4 of 6 Fable cells vs
0 of 6 Opus 5 cells on those two items gives Fisher p ≈ 0.06.
*What would move it:* a corpus where o5@high has complement items Fable misses. Or a quota decision
that prices Fable's weekly sub-cap (`frontier.coupling: 0.5`) above 2 items per 36.

**Own-model lean: NOT FOUND.** Under P2 all three judges rank the five arms in the same order. The
Opus 5 judge is uniformly the most generous: 150 credits over 540 (arm, sample, item) cells, against
142 and 141 from the other two judges. Its 8 solo credits split 5 on its own family's arms and 3 on
the others', against a base rate of 2 in 5 (Fisher p = 1.00). The all-Opus-5 panel P1 and the mixed
panel P2 agree on 351/360 cells for samples 2–3. P1 alone credits 8 of the 9 disagreements, and those
8 are spread over both families: 4 on Opus 5 arms, 4 on Opus 5.5. So P1 is slightly generous, not
partial.

## Method — deltas from the 09-22 sweep

Unchanged: the corpus, the isolation recipe (`--tools ""`, `--setting-sources ""`, neutral `mktemp`
cwd, `--no-session-persistence`), `CLAUDE_CODE_MAX_OUTPUT_TOKENS=128000`, binary 2.1.280
(`~/.claude-280`), and the judge `RULES`, `build()` and strict-majority vote. `judge.py` asserts that
the last two are byte-identical to 09-22.

| | 09-22 | this run |
|---|---|---|
| samples per (arm, defective brief) | 1 | **3**: sample 1 is the trunk output, samples 2–3 are new |
| arms | o55 low..max, o5@high + 2 anchors | **o55@high · o55@xhigh · o5@high · o5@max · f51@high** |
| new arm cells | 54 | **70** = 5 arms × 7 defective briefs × 2 samples (the budget, exactly) |
| judging unit | one prompt per (judge, brief), 8 outputs | one prompt per (panel, judge, brief, **sample**), 5 outputs |
| panels | 3× claude-opus-5 @xhigh | **P1** = the same, on samples 2–3 (sample 1 = 09-22's own scores) · **P2** = claude-opus-5 @xhigh + claude-opus-5-5 @xhigh + claude-fable-5-1 @high, on all 3 samples |

**Sample-1 sources**, all on trunk and read unmodified. o55@high, o55@xhigh and o5@high come from
`opus55-effort-sweep-2026-09-22/runs/{o55,o5}/`. o5@max is W2 arm D,
`tests/fixtures/codex-probe/runs/<b>__D.md`, the anchor the 09-22 panel re-judged. f51@high is
`fable51-effort-sweep-2026-09-10/runs/<b>__high.md`.

**Accounts.** The o55 and o5 cells ran on next4 (`~/.claude-quaternary`). The f51@high cells ran on
**next2** (`~/.claude-secondary`), by operator instruction mid-run. next4 then sat at 59% of its 5h
window with the reset an hour away; next2 was at 10% and was the router's Fable pick. Per-arm quota
is computed from each cell's own token counts, so the switch does not move any number here. All
judges ran on next (`~/.claude-next`). Nothing ran on `~/.claude-tertiary`.

**Outcomes.** 70/70 cells produced a review. Every cell was served the requested model and stopped at
`end_turn`. There were 0 × 429, 0 arm failures and 0 retries. Judging: 105 new calls (P1 42 + P2 63), 525 score rows,
0 parse failures.

**P1 sample 1 reproduces the 09-22 panel exactly** (8 / 10 / 8 / 13 / 10). Those rows *are* the 09-22
scores. P2 on sample 1, with the new judges, reads 8 / 9 / 7 / 12 / 10, within one item on every arm.

## Results

### Recall per sample, /36, strict majority (≥2 of 3 judges)

P1:

| arm | s1 | s2 | s3 | mean | items found in ≥2 of 3 | in ≥1 of 3 | in 3 of 3 |
|---|---|---|---|---|---|---|---|
| o55@high | 8 | 9 | 11 | 9.3 | **9** | 12 | 7 |
| o55@xhigh | 10 | 15 | 13 | 12.7 | **12** | 17 | 9 |
| o5@high | 8 | 8 | 8 | 8.0 | **8** | 12 | 4 |
| o5@max | 13 | 11 | 11 | 11.7 | **12** | 16 | 7 |
| f51@high | 10 | 8 | 9 | 9.0 | **10** | 12 | 5 |

P2:

| arm | s1 | s2 | s3 | mean | items found in ≥2 of 3 | in ≥1 of 3 | in 3 of 3 |
|---|---|---|---|---|---|---|---|
| o55@high | 8 | 8 | 10 | 8.7 | **8** | 11 | 7 |
| o55@xhigh | 9 | 14 | 13 | 12.0 | **11** | 17 | 8 |
| o5@high | 7 | 7 | 8 | 7.3 | **8** | 10 | 4 |
| o5@max | 12 | 10 | 9 | 10.3 | **11** | 14 | 6 |
| f51@high | 10 | 8 | 9 | 9.0 | **10** | 12 | 5 |

Sample-to-sample spread within one arm reaches 5 items (o55@xhigh, 10 → 15). That is as large as
every gap among these five arms in the 09-22 single-sample record (0–5 items). **Any single-sample
ranking on this corpus is noise at the 2–5 item level**, and that includes both earlier records.

### Paired sign tests (item = found in ≥2 of 3 samples; exact two-sided, discordant items only)

The cell column counts (item, sample) cells where one arm is credited and the other is not. Its p is
shown for scale only: the 3 samples of an item are not independent.

| panel | A vs B | A items | B items | A only | B only | p (items) | cells A only / B only | p (cells) |
|---|---|---|---|---|---|---|---|---|
| P1 | o5@max vs o55@xhigh | 12 | 12 | 1 | 1 | **1.00** | 6 / 9 | 0.61 |
| P1 | o5@max vs f51@high | 12 | 10 | 4 | 2 | 0.69 | 12 / 4 | 0.08 |
| P1 | o55@xhigh vs f51@high | 12 | 10 | 4 | 2 | 0.69 | 16 / 5 | 0.03 |
| P1 | o5@max vs o5@high | 12 | 8 | 4 | 0 | 0.12 | 13 / 2 | 0.007 |
| P1 | o55@xhigh vs o55@high | 12 | 9 | 3 | 0 | 0.25 | 12 / 2 | 0.013 |
| P2 | o5@max vs o55@xhigh | 11 | 11 | 1 | 1 | **1.00** | 6 / 11 | 0.33 |
| P2 | o5@max vs f51@high | 11 | 10 | 3 | 2 | 1.00 | 8 / 4 | 0.39 |
| P2 | o55@xhigh vs f51@high | 11 | 10 | 3 | 2 | 1.00 | 14 / 5 | 0.06 |
| P2 | o5@max vs o5@high | 11 | 8 | 3 | 0 | 0.25 | 12 / 3 | 0.035 |
| P2 | o55@xhigh vs o55@high | 11 | 8 | 3 | 0 | 0.25 | 12 / 2 | 0.013 |

Read beside Q1. Within each model, **effort buys recall**: xhigh over high for Opus 5.5, max over high
for Opus 5. The cell-level signal is consistent under both panels, and the 09-22 single-sample record
could not show it. Between the two top arms there is nothing to separate.

### Q2 — complement to o55@high, all four candidates

| panel | X | mean X-only over 9 pairings (range) | mean union | X-only items (≥2 of 3) | union items | o55@high alone |
|---|---|---|---|---|---|---|
| P1 | f51@high | 2.44 (1–3) | 11.78 | 4 | 13 | 9 |
| P1 | o5@high | 1.67 (0–3) | 11.00 | 2 | 11 | 9 |
| P1 | o55@xhigh | 4.11 (1–7) | 13.44 | 3 | 12 | 9 |
| P1 | o5@max | 3.67 (1–7) | 13.00 | 3 | 12 | 9 |
| P2 | f51@high | 2.44 (1–3) | 11.11 | 4 | 12 | 8 |
| P2 | o5@high | 1.33 (0–2) | 10.00 | 2 | 10 | 8 |
| P2 | o55@xhigh | 4.00 (1–6) | 12.67 | 3 | 11 | 8 |
| P2 | o5@max | 3.22 (1–6) | 11.89 | 3 | 11 | 8 |

Outside the question as briefed (the adversarial slot runs at the lead's effort, high), and recorded
rather than acted on: per pairing, **o55@xhigh and o5@max each add more** than either high-effort
candidate. Over ≥2 of 3 samples, though, they add fewer distinct items than Fable (3 v 4). Fable's
complement is the more *reliable* one: the same 4 items, found in 2–3 of 3 samples each.

### Per item: samples of 3 in which each arm found it (P1 / P2); items no arm ever found are omitted

| item | o55@high | o55@xhigh | o5@high | o5@max | f51@high |
|---|---|---|---|---|---|
| cp-01#1 | 3 / 3 | 3 / 3 | 3 / 3 | 3 / 3 | 3 / 3 |
| cp-01#2 | 3 / 3 | 3 / 3 | 3 / 3 | 3 / 3 | 3 / 3 |
| cp-01#3 | 3 / 3 | 3 / 3 | 1 / 1 | 3 / 3 | 1 / 1 |
| cp-01#4 | 0 / 0 | 1 / 1 | 0 / 0 | 2 / 2 | 0 / 0 |
| cp-01#5 | 3 / 3 | 3 / 3 | 2 / 2 | 2 / 2 | 3 / 3 |
| cp-01#6 | 3 / 3 | 2 / 2 | 1 / 1 | 3 / 2 | 1 / 1 |
| cp-02#4 | 0 / 0 | 0 / 0 | 0 / 0 | 1 / 1 | 2 / 2 |
| cp-04#4 | 3 / 3 | 3 / 3 | 3 / 3 | 3 / 3 | 3 / 3 |
| cp-04#5 | 3 / 3 | 3 / 3 | 3 / 3 | 3 / 3 | 3 / 3 |
| cp-04#6 | 0 / 0 | 2 / 2 | 2 / 2 | 2 / 2 | 2 / 2 |
| cp-05#3 | 2 / 2 | 3 / 3 | 2 / 2 | 2 / 2 | 2 / 2 |
| cp-05#4 | 2 / 0 | 2 / 1 | 1 / 0 | 2 / 0 | 0 / 0 |
| cp-08#1 | 0 / 0 | 1 / 1 | 0 / 0 | 0 / 0 | 0 / 0 |
| cp-08#2 | 1 / 1 | 3 / 2 | 1 / 0 | 1 / 0 | 0 / 0 |
| cp-08#3 | 1 / 1 | 3 / 3 | 2 / 2 | 3 / 3 | 2 / 2 |
| cp-08#4 | 0 / 0 | 1 / 0 | 0 / 0 | 0 / 0 | 0 / 0 |
| cp-09#2 | 1 / 1 | 1 / 1 | 0 / 0 | 0 / 0 | 2 / 2 |
| cp-09#3 | 0 / 0 | 1 / 1 | 0 / 0 | 1 / 1 | 0 / 0 |
| cp-09#5 | 0 / 0 | 0 / 1 | 0 / 0 | 1 / 1 | 0 / 0 |

17 of 36 items were found by no arm in any sample, under either panel. That includes all of cp-06 and
cp-02#1–3. The ceiling on this corpus is ~19, and the arms compete over about 8 contested items.
cp-05#4 is the one item where the panels split systematically: P1 credits it and P2 does not.

### Own-model lean — P2, each judge's recall per arm, summed over 3 samples (/108)

| judge | o55@high | o55@xhigh | o5@high | o5@max | f51@high | total |
|---|---|---|---|---|---|---|
| claude-opus-5 @xhigh | 27 | 38 | 24 | 34 | 27 | 150 |
| claude-opus-5-5 @xhigh | 26 | 36 | 22 | 31 | 27 | 142 |
| claude-fable-5-1 @high | 26 | 35 | 22 | 31 | 27 | 141 |

A lean would show as a judge crediting its own family's arms more than the other judges do. None
does. All three judges put o55@xhigh first, o5@max second and o5@high last, and the Fable judge
credits the Fable arm exactly as the other two do (27).

| judge | own-family arms: solo credit / solo miss | other arms: solo credit / solo miss | Fisher p |
|---|---|---|---|
| opus-5 | 5 / 0 | 3 / 0 | 1.00 |
| opus-5-5 | 0 / 0 | 0 / 0 | 1.00 |
| fable-5-1 | 0 / 0 | 0 / 1 | 1.00 |

(Solo credit: a judge credits a cell that neither other judge credits. Solo miss: the other two both
credit it and this judge does not.)

## Quota

Currency: output + cache_creation tokens, per 7-brief pass, averaged over the samples that carry token
counts. o5@max's sample 1 (W2 arm D) recorded none, so it averages over 2. Weekly points use the
09-16 Opus-5 marginal price list: 1 W-pp ≈ 360K output or 3.4M cache_creation. That is multiplied by
each model's per-token draw from the earlier records: Opus 5.5 1.1 [0.78–1.72] (09-22), Fable 5.1
3.2–3.7 (09-16). No new meter reading is used. The 2-minute meter loop was reaped after 13 samples
(`meter/series.jsonl`), and the phases overlapped across three accounts, so no phase was clean.
[$list] is API list price, shown only because the cells report it.

| arm | median out / cell | out / pass | cache_create / pass | est. W-pp / pass [range] | vs o55@high | vs o5@high | [$list] / pass |
|---|---|---|---|---|---|---|---|
| o55@high | 17,404 | 137,465 | 127,502 | 0.46 [0.33–0.72] | 1.0× | 0.5× | 3.77 |
| o55@xhigh | 44,303 | 354,160 | 127,502 | 1.12 [0.80–1.76] | 2.4× | 1.2× | 8.10 |
| o5@high | 45,922 | 335,942 | 134,500 | 0.97 | 2.1× | 1.0× | 9.75 |
| o5@max | 71,090 | 477,646 | 134,503 | 1.37 | 3.0× | 1.4× | 13.29 |
| f51@high | 29,065 | 233,573 | 150,943 | 2.39 [2.22–2.56] | 5.2× | **2.5×** | 14.73 |

Unlike 09-22, o5@max lost no cells to the output cap. Its largest cell was 88K output tokens.

## Spend

| item | [$list] | account |
|---|---|---|
| 28 Opus 5.5 cells | 23.70 | next4 |
| 28 Opus 5 cells | 46.50 | next4 |
| 14 Fable 5.1 cells | 26.88 | next2 |
| P1 judging, samples 2–3 (42 calls) | 22.28 | next |
| P2 judging, samples 1–3 (63 calls) | 37.05 | next |
| **total** | **≈ 156.41** | drawn from plan quota; no credits |

Budget as briefed: **70 arm cells, 0 retries**. Judging covered every new cell under P1 and every
cell under P2.

## Re-derive

```
D=$PWD/docs/research/review-judge-followup-2026-09-22
ARM_CFG=<acct> PAR=3 bash $D/phase.sh claude-opus-5-5 o55 2 high xhigh   # bash, not zsh; ABSOLUTE out-dir inside
JUDGE_CONFIG_DIR=<acct> python3 $D/judge.py run P1 $D/judges/scores-p1.jsonl 2,3
JUDGE_CONFIG_DIR=<acct> python3 $D/judge.py run P2 $D/judges/scores-p2.jsonl 1,2,3
python3 $D/paired.py          # every table above; committed output: results.md
```

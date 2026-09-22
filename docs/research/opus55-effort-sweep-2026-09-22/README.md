# Opus 5.5 effort sweep + quota-draw read — 2026-09-22

**Asked by:** the Opus 5.5 SSOT / utilization-policy lead (session `b8ecfcce`, pane 564), for two rows
it could not state above 90% conviction: *which effort Opus 5.5 wants on the review class*, and *what
Opus 5.5 draws from weekly plan quota per token*.
**Companion to:** `docs/research/fable51-effort-sweep-2026-09-10/` (same corpus, same judges) and
`docs/research/fable51-vs-opus5-routing-2026-09-16/` (the quota price list used here).

## Answer

1. **Recall on the review class** (strict majority, [recall /36]): Opus 5.5 low **6** · medium **8** ·
   high **8** · xhigh **10** · max **9**. Opus 5 @high **8**. In the same panel, the anchors scored
   Opus 5 @max **13** and Fable 5.1 @high **10**. **No pair of arms is distinguishable** at this
   sample: the smallest paired p over the 36 items is 0.12 (Opus 5 @high vs @max).
2. **Opus 5.5 @xhigh ties Fable 5.1 @high** (10 v 10: 3 items each way, p = 1.00). It does so at
   roughly **0.4× the quota** of that Fable arm (a derived number, range 0.3–0.7×; see §Quota). So
   **Opus 5.5 @xhigh can take the Fable 5.1 judge slots on this class at parity, not at a gain.**
   Opus 5 @max stays the best arm measured, here and on 09-10.
3. **Max is unfit.** It spent 75% of the Opus 5.5 phase's quota for 9/36. 2 of 9 cells produced no
   review after 512K output tokens each, and 1 more finished only after 3 continuations.
4. **Per-token draw, Opus 5.5 : Opus 5 ≈ 1.1, bounded to [0.78, 1.72]** by the integer meter, read
   off the 5h meter against an in-situ Opus 5 control. That **cannot tell 1.0 from the 0.8 list-price
   ratio**. It **does exclude a Fable-like draw** (Fable is 3.2–3.7×). The weekly meter alone does
   not resolve a ratio at this volume.

## Method — deltas from the 09-10 Fable sweep

Everything not listed is unchanged. That covers the corpus (`tests/fixtures/codex-probe/`, 9 briefs,
36 anchored defects in 7 defective briefs), the isolation recipe (`--tools ""`,
`--setting-sources ""`, neutral `mktemp` cwd, `--no-session-persistence`), and the blind 3-judge
`claude-opus-5 @xhigh` panel with the mechanism-not-topic rule and a strict-majority headline.

| | 09-10 (Fable 5.1) | 09-22 (this run) |
|---|---|---|
| arms | `claude-fable-5-1` low..max | `claude-opus-5-5` low..max + `claude-opus-5 @high` |
| binary | 2.1.260 | 2.1.280 (`~/.claude-280`; 2.1.260 refuses `claude-opus-5-5`) |
| output cap | 64,000 | **128,000** (Opus 5.5's max) |
| arm account | next4, then next3 after 429s | next4 only (the metered account); **0 × 429** |
| judge account | next3 (`~/.claude-tertiary`) | next (`~/.claude-next`) |
| in-panel anchors | Fable 5 @xhigh, Opus 5 @max | **Opus 5 @max, Fable 5.1 @high** (both re-judged verbatim from trunk) |

The anchors are there so the cross-sweep comparison can be checked rather than assumed. The panel
reproduces the 09-10 panel within one item: Opus 5 @max 12 → 13, Fable 5.1 @high 10 → 10.

**Two invocation faults, neither of which reached a model and neither of which spent anything.**
(1) `run-arms.sh` cds into a scratch dir before writing, so a *relative* out-dir fails every cell
with `No such file or directory`. The 09-10 README's re-derive line (`./run-arms.sh runs …`) has this
defect; pass an absolute path. (2) In zsh, `"cp-$b:high"` expands `$b:h` as the *head* modifier and
yields `cp-.igh`; write `"cp-${b}:high"`. Both runs were cleared and relaunched. The committed
`index.jsonl` files hold only the real runs.

## Results

**Grid.** 54 cells planned, 54 run, 52 produced a review. 2 are arm failures, scored 0 exactly as
09-10 scored its `cp-09@max`: `cp-06@max` and `cp-09@max` each returned `Claude's response exceeded
the 128000 output token maximum` after 512,000 output tokens and 64–68 minutes. There were no quota
faults and no retries.

**Positive control:** median output tokens rise with effort, 2.6K → 6.3K → 14.5K → 36.5K → 106K, so
`--effort` reaches Opus 5.5. **Judging:** 21 calls, 168 rows, 0 parse failures, $13.19 [$list].

Recall, strict majority (≥2 of 3) [recall, items]. Every arm is measured on every brief.

| brief | GT | o55@low | o55@medium | o55@high | o55@xhigh | o55@max | o5@high | o5@max ⚓ | f51@high ⚓ |
|---|---|---|---|---|---|---|---|---|---|
| cp-01 | 6 | 4 | 4 | 5 | 5 | 5 | 3 | 5 | 4 |
| cp-02 | 4 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| cp-04 | 6 | 2 | 2 | 2 | 2 | 3 | 2 | 3 | 3 |
| cp-05 | 4 | 0 | 1 | 0 | 1 | 0 | 1 | 1 | 1 |
| cp-06 | 6 | 0 | 0 | 0 | 0 | 0 ✗ | 0 | 0 | 0 |
| cp-08 | 5 | 0 | 1 | 0 | 2 | 1 | 2 | 2 | 1 |
| cp-09 | 5 | 0 | 0 | 1 | 0 | 0 ✗ | 0 | 2 | 1 |
| **TOTAL** | 36 | **6** | **8** | **8** | **10** | **9** | **8** | **13** | **10** |
| ≥1 judge | | 6 | 8 | 9 | 11 | 9 | 9 | 13 | 11 |
| unanimous | | 6 | 8 | 8 | 9 | 9 | 7 | 13 | 10 |

⚓ = anchor re-judged in this panel from its trunk output · ✗ = arm failure (no review), scored 0.

Cost and quota per arm. Currency is labelled per column: [tokens] from the cell JSON,
[$list] = `total_cost_usd` at API list price, [W-pp] / [5h-pp] = plan-meter points.

| arm | median out [tokens] | total out [tokens] | total cache_create [tokens] | cost [$list] | meter [W-pp, 5h-pp] | cells lost: cap / 429 |
|---|---|---|---|---|---|---|
| o55@low | 2,578 | 23,202 | 141,485 | 1.60 | ≈0.05, ≈0.3 † | 0 / 0 |
| o55@medium | 6,310 | 91,314 | 141,483 | 2.96 | ≈0.15, ≈0.9 † | 0 / 0 |
| o55@high | 14,487 | 152,521 | 141,483 | 4.18 | ≈0.23, ≈1.4 † | 0 / 0 |
| o55@xhigh | 36,528 | 398,278 | 141,481 | 9.10 | ≈0.57, ≈3.6 † | 0 / 0 |
| o55@max | 105,619 ‡ | 2,155,968 | 381,640 | 46.18 | ≈3.04, ≈18.9 † | 2 / 0 |
| **Opus 5.5 phase** | | **2,821,283** | **947,572** | **64.02** | **+5 W, +29 5h observed** (≈4.0, ≈25.2 net) | 2 / 0 |
| o5@high | 43,040 | 364,535 | 150,479 | 10.62 | **+1 W, +3 5h observed** | 0 / 0 |

† Apportioned, not observed. The meter only reads per phase, so each Opus 5.5 arm gets the phase's
net movement in proportion to its share of Opus-5-list-predicted draw. ‡ Median over the 7 cells that
produced a review. `cp-08@max` finished at 502,897 tokens after 3 continuations.

`total_cost_usd` implies an Opus 5.5 list price of **$4 in / $20 out / $8 1h-cache-write**, against
Opus 5's $5 / $25 / $10: a **0.8×** list ratio (checked cell-by-cell on `cp-01@max` and `cp-01 o5@high`).

## Comparisons on the same corpus

Paired, exact two-sided sign tests over the 36 ground-truth items (discordant items only), and
per-brief. The 09-10 README reported vote-threshold tables but **no formal paired test**; this adds
one (`paired.py`).

| A vs B | A | B | items A only | items B only | p (items) | briefs A>B / A<B | p (briefs) |
|---|---|---|---|---|---|---|---|
| o55@xhigh vs f51@high | 10 | 10 | 3 | 3 | 1.00 | 2 / 2 | 1.00 |
| o55@high vs f51@high | 8 | 10 | 1 | 3 | 0.62 | 1 / 3 | 0.62 |
| o55@medium vs f51@high | 8 | 10 | 1 | 3 | 0.62 | 0 / 2 | 0.50 |
| o55@xhigh vs o5@max | 10 | 13 | 1 | 4 | 0.38 | 0 / 2 | 0.50 |
| o55@high vs o5@high | 8 | 8 | 3 | 3 | 1.00 | 2 / 2 | 1.00 |
| o55@xhigh vs o5@high | 10 | 8 | 2 | 0 | 0.50 | 1 / 0 | 1.00 |
| o55@medium vs o55@xhigh | 8 | 10 | 0 | 2 | 0.50 | 0 / 2 | 0.50 |
| o55@high vs o55@xhigh | 8 | 10 | 2 | 4 | 0.69 | 1 / 2 | 1.00 |
| o55@xhigh vs o55@max | 10 | 9 | 3 | 2 | 1.00 | 2 / 1 | 1.00 |
| o55@low vs o55@medium | 6 | 8 | 0 | 2 | 0.50 | 0 / 2 | 0.50 |
| o5@high vs o5@max | 8 | 13 | 1 | 6 | 0.12 | 0 / 3 | 0.25 |

Against Fable 5.1 on 09-10 (a different panel, [recall /36]): Fable 5.1 low 6 · medium 10 · high 10 ·
xhigh 9 · max 9/25 measured. Opus 5.5 runs one step "later" on the same ladder. Its medium and high
(8) sit below Fable's (10), and its xhigh (10) reaches Fable's plateau. **Neither model shows a
reliable recall gain from effort above medium/xhigh on this class.** Both have a max arm that loses
cells to the output cap.

Opus 5.5's curve matches the vendor note on class-dependence: low is the floor, and the review class
does not scale steeply. xhigh is the point estimate of its peak, but xhigh vs medium/high is 2
discordant items, which is not a finding.

## Quota draw per token

**Instrument.** `claude-accounts --fresh --json`, the next4 row: `weekly_pct` and `session_pct` (5h),
both integers, sampled every 2 min (`meter/series.jsonl`). The predictor is the Opus-5 price list from
`fable51-vs-opus5-routing-2026-09-16/V-quota.md` §"What survives" 2: 1 weekly pp ≈ **360K output or
3.4M cache_creation** tokens at the margin (261K / 3.19M realised average), cache reads free, and
×4.0 for the 5h meter (≈4.0 five-hour allowances per week,
`usage-telemetry-100p-2026-08-16/skeptic-exchange-rate.md`).

**CONTAMINATED — and measured instead of discarded.** During the 3-minute hold (21:08–21:11Z) the 5h
meter moved 0 → 1 as an interactive Opus 5 session started on next4 (worktree `wt-0c82f0811877`,
transcript `88bfc0a0…` plus 8 subagent files). The sweep cells write no transcript
(`--no-session-persistence`), so every next4 transcript record inside a phase window belongs to
another consumer. `meter/others.py` sums those records, deduped on `message.id`.

- Opus 5.5 phase: 150,977 out + 1,835,817 cache_create, all served `claude-opus-5` → **0.96 predicted
  W-pp**, subtracted at the Opus-5 list.
- Opus 5 phase: **0** other-consumer records.

The 3 idle Opus 5 panes on next4 stayed idle throughout.

| phase | window (UTC) | observed [W-pp, 5h-pp] | predicted by Opus-5 list, marginal [W-pp] | obs/pred, weekly | obs/pred, 5h |
|---|---|---|---|---|---|
| Opus 5.5, 45 cells | 21:12:38–22:34:54 | +5, +29 | 8.12 (+0.96 others) | **0.50** [0.37–0.62] | **0.78** [0.74–0.81] |
| Opus 5 @high, 9 cells (positive control) | 22:36:00–22:54:20 | +1, +3 | 1.06 | 0.95 [0.00–1.89] | **0.71** [0.47–0.95] |

Brackets are the integer meter's ±1 pp on a difference of two readings. With the realised-average list
instead of the marginal one, every obs/pred falls ~30% and the ratio between phases is unchanged.

**Ratio.** Dividing the two phases' 5h obs/pred cancels both the ×4.0 constant and the list's overall
scale, leaving only the output-vs-cache_creation weighting, which both phases share. The result is
**Opus 5.5 : Opus 5 per-token draw = 0.78 / 0.71 ≈ 1.1, bounded to [0.78, 1.72]**.

On the weekly meter the control phase moved 1 pp (±1), so it bounds nothing. The weekly-only reading,
0.50 against the fleet-level Opus 5 calibration of 1.23 (V-quota), would put Opus 5.5 at ~0.4×. It
disagrees with the 5h reading and has no in-situ control, so **it is recorded, not used.**

In the Opus 5.5 phase the 5h meter moved 5.8× the weekly (29/5; 4.7–7.5 within quantization), against
the assumed 4.0. That exchange rate deserves its own look before anyone leans on the weekly reading.

**Were the capped-out tokens metered?** Yes. The 2 failed max cells carried 1.02M of the phase's
2.82M output tokens, so this decides the point estimate. `meter/series_fit.py` fits the 2-minute 5h
series with each cell's tokens spread over its run time and others' tokens at their timestamps:

| model | RMSE |
|---|---|
| failed cells counted | **0.89 pp** (k = 0.79) |
| failed cells dropped | 1.56 pp (k = 1.08) |

The meter also ticked +2 as those cells ended, which fits metering at response completion. An output
that hits the cap is billed and metered, and it returns nothing.

**Per task, which is what the policy row needs** (derived from the ratio above, not observed
directly; Opus-5-list pp per 9-cell arm × ratio):

| arm | recall /36 | quota draw vs Opus 5 @high |
|---|---|---|
| Opus 5.5 @high | 8 | ≈ **0.48×** (0.34–0.76), same recall |
| Opus 5.5 @xhigh | 10 | ≈ **1.2×** (0.85–1.87) |
| Fable 5.1 @high (09-10 tokens × Fable's 3.2–3.7× per-token draw) | 10 | ≈ **2.9×** |

So Opus 5.5 @xhigh reaches Fable 5.1 @high's recall at ≈0.42× its quota (0.28–0.70×).

## What this licenses — and what it does not

Scope: **the review class only** (anchored review of a single file). **One sample per cell** over 7
defective briefs, **recall only**: false positives, citation accuracy and fabrication at reduced effort
were not scored. Every effort-to-effort gap on Opus 5.5 is inside noise.

- **Licensed:** Opus 5.5 @xhigh may hold a judge/verifier/review slot that Fable 5.1 @high holds today.
  It measured at recall parity, 10 v 10 with 3 discordant items each way, at well under half the quota.
- **Licensed:** do not route this class to Opus 5.5 @max. It measured no better than xhigh, lost 2/9
  cells to the output cap after 512K tokens each, and cost ~5× xhigh in quota.
- **Licensed:** Opus 5.5's per-token quota draw is Opus-class, not Fable-class (≤1.72× Opus 5, against
  Fable's 3.2–3.7×).
- **Not licensed:** "Opus 5.5 beats Opus 5" or "Opus 5.5 beats Fable 5.1" on review. Opus 5 @max (13)
  remains the best arm measured, and Opus 5.5 @xhigh vs Opus 5 @max is 1 v 4 discordant items (p 0.38).
- **Not licensed:** a medium/high vs xhigh choice for Opus 5.5 on recall grounds. That gap is 2
  discordant items. The choice is a cost call (high ≈ 0.4× xhigh's quota), not a quality finding.
- **Not licensed:** any per-token ratio tighter than [0.78, 1.72]. The control's 3 ± 1 5h-pp is the binding
  error. Resolving 0.8 vs 1.0 needs roughly 5× the Opus 5 control's volume on a quiet account, or a
  non-integer meter.

## Spend

| item | [$list] | meter |
|---|---|---|
| Opus 5.5 cells | 64.02 | next4: +5 W-pp, +29 5h-pp gross, including ~1 W-pp from the other consumer |
| Opus 5 @high cells | 10.62 | next4: +1 W-pp, +3 5h-pp |
| judges | 13.19 | account next |
| **total** | **≈ $87.83** | drawn from plan quota |

Budget as briefed: 54 arm cells run, 0 re-runs. The two invocation faults above called no model.

## Re-derive

```
D=$PWD/docs/research/opus55-effort-sweep-2026-09-22
SWEEP_MODEL=claude-opus-5-5 SWEEP_BIN=$HOME/.claude-280/node_modules/.bin/claude \
  SWEEP_CONFIG_DIR=<acct> $D/run-arms.sh $D/runs/o55 cp-01:low …      # ABSOLUTE out-dir; "cp-${b}:high" in zsh
JUDGE_CONFIG_DIR=<acct> python3 $D/judge.py run $D/runs $D/runs/scores.jsonl
python3 $D/judge.py table $D/runs $D/runs/scores.jsonl                 # every recall/token table above
(cd $D && python3 paired.py runs/scores.jsonl)                         # the paired tests
(cd $D && python3 meter/draw.py runs/o55/index.jsonl meter/b-before-o55.json meter/b-after-o55.json meter/others-phaseB.json)
(cd $D && python3 meter/draw.py runs/o5/index.jsonl meter/c-before-o5.json meter/c-after-o5.json meter/others-phaseC.json)
(cd $D && python3 meter/series_fit.py runs/o55/index.jsonl meter/series.jsonl ~/.claude-quaternary)
```

`series_fit.py` and `others.py` re-read live transcripts under the config dir. Once those age out,
`meter/others-phase{B,C}.json` are the retained values.

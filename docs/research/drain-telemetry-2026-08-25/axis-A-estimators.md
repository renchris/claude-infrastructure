# Axis A — How wrong are the incumbent burn estimators, and what beats them?

Measured 2026-08-25 against `~/.claude/logs/account-utilization.jsonl`
(12,557 records · 4 accounts · 2026-08-10T05:58Z → 2026-08-25T09:05Z · 363.1 h span).
All scripts in this directory; every number below is produced by one of them.

| script | what it produces |
|---|---|
| `lib.py` | loader, roll detector, incumbent replay, candidate estimators |
| `tail_reach.py` | the `_util_tail` byte-window reach measurement |
| `quant.py` | cadence, 1 pp tick timing, diurnal profile |
| `backtest.py` | the full backtest (21 estimators × 6 horizons × 2 meters) |
| `head2head.py` | paired incumbent-vs-candidate tests + abstention-vs-window-phase |
| `live_and_ceiling.py` | quantization floor, physical ceiling, live worked example |
| `degenerate.py` | `burn_5h_ph` value distribution, weekly↔5h coupling |
| `long-horizon.txt` | the 12/24/48 h horizon ladder |

**Coverage.** After dropping `stale:true` rows (1,047 of 12,557 = 8.3%) and requiring 48 h of
warm-up so 48 h-window estimators are scored fairly, the backtest evaluates **10,126 scoring
points** on the weekly meter and **10,070** on the 5 h meter, across all 4 accounts. Ground truth
abstains where <80% of the horizon is covered by samples: 674/597/437 abstentions at 1/3/6 h
(4.3–6.6%), all attributable to logging gaps (57 gaps >1 h in the series, max 5.5 h).
0 records failed to parse. Nothing was imputed.

---

## 0. Headline

**The 5-hour estimator the router actually consumes reads exactly `0.000` on 79.9% of
evaluations, and on those evaluations the realized next-hour burn averages 1.79 %/h — so the
router's 5 h lookahead is inert 80% of the time and wrong the rest.** Replacing the adjacent-pair
slope with a 1 h-half-life EWMA cuts MAE by 23.6 / 31.2 / 35.4% at the 1 / 2 / 3 h horizons
(paired t = 13.6 / 18.2 / 21.5, n ≈ 9,300 each).

---

## 1. A structural defect found before any scoring: `burn_wk_ppd` cannot reach 48 h

`apply_burn` documents `burn_wk_ppd` as "widest pair inside 48 h". It gets its samples from
`_util_tail(max_bytes=131072)`, which seeks to `size − 131072` and parses forward.

Measured (`tail_reach.py`): mean record length **292.4 bytes** → the tail holds **408 parsed rows
≈ 102 per account ≈ 12.12 h**. Replayed over 37 historical byte-prefixes of the same file:

```
historical tail spans (h): n=37  min=11.38  med=12.11  max=18.35   >= 48 h: 0
```

**The 48 h window has never once been reachable.** The estimator in production is a
*widest-pair-inside-12.1 h*, not a widest-pair-inside-48 h.

This matters twice over, and the second time it is *favourable*:

**(a) It changes which estimator you are actually scoring.** Both variants are backtested below
and they behave differently (the nominal one abstains 4× more often).

**(b) The truncation accidentally repairs a worse defect.** A widest pair that straddles a weekly
reset has `d < 0` and returns absent. A weekly window is 168 h, so a *48 h* lookback contains a
roll for the first 48 h of every window — **28.6% of every week**. Measured abstention by position
in the weekly window (`head2head.py`, n = 9,592 at the 3 h horizon):

```
hours into the weekly window : abstain%  (48 h nominal)      : abstain% (12.1 h real)
   0- 12   100.0%  [n=569]                                       96.3%
  12- 24   100.0%  [n=716]                                        0.1%
  24- 36   100.0%  [n=716]                                        0.0%
  36- 48    96.8%  [n=775]                                        0.0%
  48-168     0.0%                                                 0.0%
```

**The documented estimator is 100% blind for the first 36 hours of every weekly window** — the
exact hours in which "how hard must I push this week?" is first asked. The shipped, truncated one
is blind for ~12 h instead. A fix that "restores" the documented 48 h span would make the
instrument *worse* unless the roll is reconstructed rather than discarded.

---

## 2. The quantization floor — this bounds everything else

Only integer percentages exist. A two-point difference therefore carries up to ±1 pp of rounding
error, and the induced rate error is **±1 pp / span_hours**, independent of the estimator.

```
 span_h   ±rate err %/h   ±%/day    as % of weekly mean (0.592 %/h)   as % of 5h mean (2.972 %/h)
  0.107          9.35      224.3                            1579%                          314%
  0.25           4.00       96.0                             676%                          135%
  1.00           1.00       24.0                             169%                           34%
  3.00           0.33        8.0                              56%                           11%
  6.00           0.17        4.0                              28%                            6%
 12.00           0.083       2.0                              14%                            3%
 24.00           0.042       1.0                               7%                            1%
```

Empirical time-to-resolve one tick (`quant.py`, roll-excluded):

| meter | n ticks | inter-tick p10 | median | p90 | samples between ticks (median) |
|---|---|---|---|---|---|
| weekly | 168–207 per acct | 0.11–0.18 h | **0.44–0.84 h** | 3.95–6.51 h | 4.2–7.9 |
| 5 h | 539–658 per acct | 0.10 h | **0.15–0.22 h** | 0.96–1.46 h | 1.4–2.0 |

**Minimum honest span** (quantization error ≤ 25% of the meter's own mean rate):

- **weekly meter: ≥ 6.8 h** (≈ 63 samples at the 384 s cadence)
- **5 h meter: ≥ 1.3 h** (≈ 13 samples)

`burn_5h_ph` uses the **newest adjacent pair**, median span **0.107 h (384 s)**. Its pure
quantization error is **±9.35 %/h against a realized mean of 2.97 %/h — the estimator is 3.1×
noise before any behavioural variance is added.** This is not a tuning problem; it is arithmetic.

The empirical MAE-by-span table confirms the bound is binding, not theoretical:

```
 span_h      n   MAE %/h   predicted ±1/span
   ~0.11   8146      3.48               ~9.3
    0.25   1089      3.51                4.0
    0.50     38      2.41                2.0
```

`burn_wk_ppd` at its real 12.1 h span has ±0.083 %/h of quantization (14% of signal) — acceptable.
**Quantization indicts the 5 h estimator and exonerates the weekly one.**

---

## 3. The diurnal profile — and why "the night problem" is the wrong name for it

Weekly %/h by **local (America/Los_Angeles) hour**, roll-aware, pairs ≤ 1 h, 13–16 h observed per
bucket per account (`quant.py`):

```
hour     0    1    2    3    4    5    6    7    8    9   10   11   12   13   14   15   16   17   18   19   20   21   22   23
next  0.74 1.24 0.72 0.52 0.26 0.51 0.84 0.23 0.23 0.07 0.46 0.75 0.59 0.51 0.67 1.09 0.80 0.52 0.44 0.64 1.64 0.55 1.01 0.86
next2 0.80 0.69 0.68 0.84 1.11 0.21 0.68 0.36 0.22 0.15 0.84 0.28 0.50 0.21 0.28 0.49 0.58 0.82 0.85 0.58 0.47 0.58 1.20 0.69
next3 2.02 1.02 0.81 0.83 0.34 0.35 0.07 0.20 0.29 0.00 0.46 0.42 0.21 0.81 0.84 1.23 0.81 0.65 0.35 0.43 1.25 0.95 0.87 0.80
next4 0.80 1.20 0.90 0.48 0.56 0.64 0.47 0.25 0.07 0.07 0.61 0.30 0.29 0.34 0.56 0.35 0.78 0.61 0.55 0.42 0.62 0.63 0.72 1.11
```

**The trough is 07:00–10:00 local, not the small hours.** Peak is 20:00–03:00. The premise in the
task brief — "`burn_wk_ppd` averages over idle nights" — is measurably **inverted**: nights are the
*busy* period on this fleet. `next3` at 09:00 local burns **0.00 %/h** (n = 13.7 observed hours);
at 00:00 it burns **2.02 %/h**. That is an infinite ratio at the extreme and 6.1× between
`next3`'s 00:00 and 06:00 buckets.

Aggregated busy/quiet split (busy = hours above the account's own 24 h mean):

| acct | 24 h mean | busy-hours mean | ratio | quiet-hours mean | ratio |
|---|---|---|---|---|---|
| next  | 0.666 %/h (16.0 %/d) | 0.937 (22.5 %/d) | **1.41×** | 0.426 | 0.64× |
| next2 | 0.587 %/h (14.1 %/d) | 0.830 (19.9 %/d) | **1.41×** | 0.371 | 0.63× |
| next3 | 0.674 %/h (16.2 %/d) | 1.027 (24.6 %/d) | **1.52×** | 0.310 | 0.46× |
| next4 | 0.565 %/h (13.6 %/d) | 0.800 (19.2 %/d) | **1.42×** | 0.367 | 0.65× |

**A multi-hour average understates the busy-hours rate by 1.41–1.52×.** So "recent 28 %/day" is
the *wrong comparator for a 3 h decision* by roughly 1.5× in the favourable direction and up to
∞ in the unfavourable one — the sign depends entirely on which hours the 3 h covers, which the
scalar cannot express. The correct comparator is the hour-by-hour climatology, and the backtest
below shows it is genuinely predictive: at the 48 h horizon **`hod_climatology` alone (MAE 0.376)
beats every trailing-window estimator and beats the incumbent (0.419) with 100% coverage against
its 74%.**

---

## 4. The backtest

Every estimator replayed at every sample point using only data at or before `t_i`, scored against
the roll-aware realized rate over the next H hours. All figures **%/h**. Full tables in
`backtest-out.txt` and `long-horizon.txt`; the winner and the incumbent at each horizon:

### 4.1 Weekly meter (realized mean 0.55–0.59 %/h)

| H | best estimator | MAE | incumbent (48 h nominal) | incumbent (12.1 h real) | best MAE / realized mean |
|---|---|---|---|---|---|
| 1 h | `ewma_hl2h` | **0.652** | 0.724 (cov 70%) | 0.682 (cov 93%) | 1.12 |
| 3 h | `ewma_hl4h` | **0.525** | 0.557 (cov 70%) | 0.537 (cov 93%) | 0.92 |
| 6 h | `ewma_hl4h` | **0.482** | 0.491 (cov 70%) | 0.493 (cov 93%) | 0.86 |
| 12 h | `blend_ewma8h+hod` | **0.435** | 0.434 (cov 70%) | 0.460 (cov 93%) | 0.79 |
| 24 h | `blend_ewma8h+hod` | **0.397** | 0.416 (cov 71%) | 0.431 (cov 93%) | 0.72 |
| 48 h | `blend_ewma8h+hod` | **0.373** | 0.419 (cov 74%) | 0.435 (cov 92%) | 0.68 |

**The single most important row is the last column.** At the 1 h horizon **every estimator's MAE
exceeds the mean of the thing it is predicting** (best 1.12×, worst 1.38×). Hourly weekly burn on
this fleet is close to unpredictable; the median 1 h consumption is **0.00 pp** and the p95 is
2.20 pp. Any product surface that reports a 1-hour weekly burn rate is reporting noise, however it
is computed. The signal only becomes usable at 12 h+ (0.79 → 0.68 of the mean).

**Paired head-to-head, same points only** (`head2head.py`):

```
vs the 48h-nominal incumbent, candidate = ewma_hl4h
  H=1h  n=6701  MAE 0.7245 -> 0.6796 (-6.2%)   cand wins 58.7%   paired-t=8.6
  H=3h  n=6722  MAE 0.5568 -> 0.5393 (-3.1%)   cand wins 56.5%   paired-t=3.6
  H=6h  n=6833  MAE 0.4910 -> 0.4973 (+1.3%)   cand wins 53.9%   paired-t=-1.3   <- incumbent wins
  + 2,814 / 2,870 / 2,919 further points where the INCUMBENT ABSTAINS and the candidate answers
    (candidate MAE there 0.65 / 0.49 / 0.45; truth mean 0.44 / 0.43 / 0.43)
vs the 12.1h real incumbent
  H=1h  n=8861  -2.8%  paired-t=9.0 | H=3h  -3.6%  t=9.1 | H=6h  -3.3%  t=7.6
```

**Honest reading: on accuracy alone the weekly incumbent is nearly fine.** At 6 h it *beats*
`ewma_hl4h` on the points where both answer (paired-t = −1.3, i.e. not distinguishable). The
weekly estimator's defect is **availability, not accuracy** — it declines to answer on 28–30% of
evaluations, and those are not random: they are the first 36 h of every weekly window. A candidate
that answers there with MAE 0.45–0.65 against a truth mean of 0.43 is not obviously *accurate*
either, but it is *present*, and a present estimate with a stated error bar is a decision input
where an absent one is not.

### 4.2 5-hour meter (realized mean 2.91–2.97 %/h)

| H | best estimator | MAE | `INC_burn_5h_ph` | incumbent penalty |
|---|---|---|---|---|
| 1 h | `ewma_hl0.5h` 2.624 / `ewma_hl1h` 2.659 | **2.624** | 3.481 | **+32.7%** |
| 2 h | `ewma_hl1h` | **2.525** | 3.669 | **+45.3%** |
| 3 h | `ewma_hl2h` 2.412 / `ewma_hl1h` 2.439 | **2.412** | 3.773 | **+56.4%** |

`INC_burn_5h_ph` is **last or second-to-last at every horizon**, and its tail is far worse than its
mean suggests: RMSE **7.65–7.85** vs 4.4–5.3 for the EWMAs, p90 absolute error **8.8–9.1 %/h** vs
6.2. Paired:

```
vs INC_burn_5h_ph, candidate = ewma_hl1h
  H=1h  n=9305  MAE 3.4808 -> 2.6610 (-23.6%)  cand wins 48.3%  paired-t=13.6
  H=2h  n=9287  MAE 3.6685 -> 2.5253 (-31.2%)  cand wins 57.5%  paired-t=18.2
  H=3h  n=9376  MAE 3.7732 -> 2.4389 (-35.4%)  cand wins 64.0%  paired-t=21.5
```

At H = 1 h the candidate wins only 48.3% of individual points yet cuts MAE 23.6% — i.e. the
incumbent's loss is concentrated in **catastrophic outliers**, exactly the quantization spikes
§2 predicts. That is the case where the incumbent is not merely noisier but actively dangerous.

### 4.3 The degenerate-value finding (`degenerate.py`) — the real indictment

```
burn_5h_ph over 10,189 evaluations:  abstain 230 (2.3%)   answered 9,959
  EXACTLY 0.000 : 7,961  = 79.9% of answers
  non-zero      : n=1,998  median 9.67 %/h  p90 29.03  max 131.44
```

The support is discrete (374 distinct values at 0.1 %/h resolution over 9,959 answers) because the
answer is always an integer pp over a ~384 s span. **The estimator is very nearly a Bernoulli
variable: 80% zero, 20% a spike near 10 %/h.**

And the zero is not informative:

```
when burn_5h_ph reads EXACTLY 0 -> realized next-1h 5h burn: n=7,435  mean 1.79 %/h  median 0.00  p90 4.36
when it reads > 0               -> n=1,870  mean 7.66 %/h
```

**Consequence in the shipped code.** `_su_projected` returns `su` unchanged when
`burn_5h_ph <= 0`. Combining the zeros with the abstentions, **the router's 5 h lookahead is
inert on 80% of evaluations** — and on those the account is in fact burning 1.79 %/h on average,
p90 4.36 %/h. When the lookahead *does* fire it adds a rate whose median is 9.67 %/h and whose max
is 131 %/h. This is the worst polarity available: silent when burn is ordinary, violent when a
single 1 pp tick happens to land on the newest pair.

**A control that can fail.** If the incumbent were merely noisy-but-unbiased, its bias would be
near zero and its zeros would coincide with genuinely idle periods. Measured bias is +0.070 to
+0.082 %/h (small), so bias is *not* the defect — but the conditional means above (1.79 vs 7.66)
refute the "zeros mean idle" reading directly, on 7,435 points. The candidate's own zeros are far
rarer (`ewma_hl1h` never abstains and reads 0 only when the whole trailing hour ticked nothing).

### 4.4 Abstention causes, quantified

| estimator | abstains | cause breakdown |
|---|---|---|
| `INC_burn_wk_ppd` (48 h nominal) | 8,603 / 28,859 = **29.8%** | `negative_roll` 8,603 (100%) — i.e. *entirely* the weekly-reset straddle |
| `INC_burn_wk_ppd` (12.1 h real) | 2,000 / 28,859 = **6.9%** | `negative_roll` 2,000 (100%) |
| `INC_burn_5h_ph` | 630 / 28,598 = **2.2%** | `negative_roll` 548 · `lt2_in_2h` 54 · `gap_too_long` 28 · `gap_too_short` 0 |
| `ewma_hl*`, `mean_≥6h`, `theilsen_≥6h`, `hod_climatology`, `blend` | **0** | — |
| `active_rate × hod_active_frac` | 2,628 = **9.1%** | `no_active_time` (k = 0 for the whole 12 h lookback) |

**Every single weekly abstention is a discarded window reset.** Not one is a data gap or a short
span. The fix is therefore not a looser threshold — it is roll reconstruction, and the roll-aware
EWMA/mean/Theil-Sen candidates (which credit the post-roll accrual `b` instead of dropping the
pair) abstain **zero** times over 28,859 evaluations.

`gap_too_short` never fires (0/28,598): the 0.03 h floor on `burn_5h_ph` is dead code at a 384 s
cadence. `gap_too_long` fires 28 times. The 5 h estimator's abstention guard is essentially inert;
its problem is what it *answers*, not what it declines.

### 4.5 Estimators that did NOT win, and why that is itself a result

- **Theil-Sen** loses at every horizon on both meters (weekly 6 h: 0.559 vs 0.482; 5 h 3 h: 2.655
  vs 2.412) and carries a consistent **negative bias of −0.077 to −0.104 %/h**. The median-of-slopes
  is robust to outliers, but on a monotone accrual counter the outliers *are the signal* — the burst
  is what you are trying to detect. Robustness is the wrong property here. **Do not ship it.**
- **The naive active-time estimator is an algebraic restatement.** `consumed/active_hours ×
  (active_hours/total_hours)` reduces exactly to `consumed/total_hours` = `mean_W`. It was
  implemented, recognised as degenerate, and replaced by `active_rate_12h × hod_active_frac`, which
  uses a *forward-looking* active fraction from hour-of-day climatology and is therefore genuinely
  decorrelated. That version scores 0.531 at 6 h (vs `ewma_hl4h` 0.482) and abstains 9.1% —
  **it loses.** Per-active-hour rate (`::r` rows) is unbiased (−0.005 to +0.022) but noisier.
  Active-time is not the missing variable.
- **`hod_climatology` alone loses badly at 1–6 h** (0.806 / 0.638 / 0.562, worst or near-worst)
  **and wins at 48 h** (0.376, second overall, effectively tied with the blend's 0.373). Its bias is
  consistently **positive** (+0.047 to +0.081) where every trailing estimator's is negative — the two
  err in opposite directions, which is exactly why the 50/50 blend beats both.
- **Longer trailing windows monotonically help as the horizon grows and hurt at 1 h**
  (`mean_3h` is 4th at 1 h and last at 24 h; `mean_96h` is last at 1 h and mid-pack at 48 h).

---

## 5. What to ship

### 5.1 The law: match the estimator's memory to the decision horizon

The backtest's cleanest generalisation. A single scalar "recent burn" cannot serve a 3-hour
decision and a 5-day decision; the optimal half-life scales with the horizon.

| decision horizon | ship | measured MAE | vs incumbent |
|---|---|---|---|
| 1 h | `ewma_hl2h` (weekly) / `ewma_hl0.5h`–`ewma_hl1h` (5 h) | 0.652 / 2.624 | −10% / −25% |
| 3–6 h | `ewma_hl4h` (weekly) / `ewma_hl1h`–`ewma_hl2h` (5 h) | 0.525–0.482 / 2.41–2.53 | −6% / −31…−35% |
| 12–48 h | `blend_ewma8h+hod` (weekly) | 0.435 → 0.373 | −5% … −11%, and 100% vs 70% coverage |

### 5.2 The three concrete replacements

1. **`burn_5h_ph` → `ewma_hl1h`, roll-aware.** Largest measured win in the whole study
   (−23.6/−31.2/−35.4% MAE, paired-t 13.6–21.5). Removes the 80%-inert failure of
   `_su_projected`. **Do not ship the existing estimator with a widened span** — widening it to
   1.3 h (the minimum honest 5 h span) would fix quantization but reintroduce the staleness the
   adjacent pair was chosen to avoid; the EWMA gets both because it weights *all* pairs in the
   trailing window by recency.
2. **`burn_wk_ppd` → roll-aware EWMA (hl 4 h) for short horizons, `blend_ewma8h+hod` for ≥12 h.**
   The accuracy gain is small (−3 to −6%). **The real gain is that abstention goes 29.8% → 0%,
   and the 29.8% is precisely the first 36 h of every weekly window.**
3. **Reconstruct the roll; never discard it.** `d < 0` means the window reset, and the post-roll
   value `b` is a valid lower bound on consumption since the reset. Discarding is what makes the
   weekly estimator blind for a fifth of the week.

### 5.3 The abstain rule that must survive (design law L2)

Do **not** replace the roll-abstention with a blanket "always answer". Replace it with the
quantization-derived one, which is the honest constraint:

> Report a rate only when the **measured span** (sum of `dt` over pairs with both endpoints
> present) inside the lookback is **≥ 6.8 h for the weekly meter / ≥ 1.3 h for the 5 h meter**.
> Below that the quantization error exceeds 25% of the meter's own mean rate and the number is
> noise. Report `null`, not a number.

Checked live: all four accounts have 24.08 h of measured span in a 24 h lookback → all ANSWER.
The rule fires only after a genuine logging outage — which is the correct polarity.

---

## 6. The live worked example, answered

Newest sample per account (`live_and_ceiling.py`, `proposed-metrics-live.txt`):

```
acct    wk%     wrh   burn_wk_ewma4h   proj_end   strand_pp   need %/h   burst_pctile      burn_5h_ewma1h
next     49  114.66            1.659      239.3         0.0       0.44   p47.8 (H=24h)              11.52
next2    17   97.66            0.318       48.0        52.0       0.85   p70.5 (H=24h)               1.89
next3    92    2.66            1.225       95.3         4.7       3.01   p95.2 (H=3h)                6.59
next4    14  119.66            0.165       33.8        66.2       0.72   p75.7 (H=24h)               1.07
```

**`INC_burn_5h_ph` reads exactly `0.000` on next2, next3 and next4 right now**, and 24.171 %/h on
`next`. Three of four accounts are currently invisible to the router's 5 h lookahead; the fourth
is being told an account burning ~11.5 %/h is burning 24.2 %/h. This is §4.3 in the live system.

**next3, the 3-hour decision.** The router says "70 %/day sustained over the remaining 3 h". That
figure is true and useless: it is a rate expressed in a unit 8× longer than the window it applies
to. Restated in units the decision can use:

- Needed: **8 pp in 2.66 h = 3.01 %/h.**
- Every trailing estimator agrees next3 lands at **95.0–95.8%**; hour-of-day climatology, which
  knows the remaining hours are 02/03/04 local (0.80 / 0.83 / 0.34 %/h for this account), says
  **93.9%**. Strand **4.2–6.1 pp**.
- **Is it achievable?** 3.01 %/h over ~3 h sits at the **p95.2** of next3's own realized 3 h burn
  rates (n = 2,721 overlapping windows). next3 has reached ≥8 pp in 3 h **155 times in 15 days
  (5.7% of windows)**. So it is not impossible — it is a burst next3 performs about **once every
  17 hours**, and it must start *now*, into its own historically weakest hours (04:00 local is
  its 0.34 %/h bucket).
- **Does the 5 h sub-cap wall first?** No. Measured coupling (§7): 8 pp of weekly costs ≈ 39 pp of
  a 5 h window. next3 is at 10% with 3.95 h left. **The 5 h cap is not the binding constraint at
  this size.** Failure mode (2) does not fire here.

**The forecast the operator actually needs is not next3.** `next2` projects to 48% (52 pp
stranding, 97.7 h left) and `next4` to 33.8% (66.2 pp stranding, 119.7 h left) — and both need
only **p70–p76** of their own historical 24 h burn to close it. Those two accounts are where the
weekly headroom is, they have four days of runway, and every estimator has agreed on this for
hours. The 3-hour scramble on next3 is worth at most 4.7 pp; next2+next4 are leaving **118 pp**
on the table with time to fix it.

⚠️ **`next` projects to 239% and that number must not be shipped.** It is `ewma_hl4h`
(validated to a 6 h horizon) extrapolated 114.7 h. §5.1 is the guard: at a 114 h horizon the
licensed estimator is `blend_ewma8h+hod`, which reads 124% — still a wall, but an honest one.
Reporting a 4-hour-memory rate across five days is the same category error as the incumbent's
`recent 28 %/day` over 3 hours, pointing the other way.

---

## 7. Derived: the weekly↔5h conversion (measured, and it is stable)

275 non-overlapping 3 h blocks with weekly burn > 0, pairing Δweekly against Δsession
(`degenerate.py`, `coupling-detail.txt`):

```
 weekly pp band    n   med ratio   pooled ratio   blocks containing a 5h roll
      1-2        129       4.00           4.45          72
      2-4         84       5.00           4.71          44
      4-6         30       5.00           5.00          17
      6-9         16       5.00           5.33           6
      9-15        11       4.83           4.89           7
     15-100        5       5.06           4.98           2
roll-free blocks only: n=127  pooled 4.84  median 5.00
```

**1 pp of weekly ≈ 4.84 pp of a 5 h window, flat across two decades of burn magnitude.**
Equivalently **a full 5 h window buys ≈ 20.7 pp of weekly.** This is derived purely from
percentages, as required — no absolute token counts were needed or available.

Two consequences for the operator's goal:
- Failure mode (2) is quantified: closing next2's 52 pp gap costs ≈ 252 pp of 5 h window =
  **≈ 2.5 full 5 h windows**. With 97.7 h (19 windows) remaining, the sub-cap has ~7.5× headroom.
  **The 5 h cap is not what is stranding quota; idle wall-clock is.**
- A "burn 9% of a weekly inside one 5 h window" test would need ≈ 44 pp of the 5 h window — it
  fits, comfortably, and nobody had measured it.

**Physical ceiling** (weekly pp consumed, weekly-roll windows excluded as a control — the ceiling
is unchanged with or without them, so it is not a roll artifact):

```
FLEET  1h: n=9,379  median 0.00  p95  2.20  p99  6.26  max 15.42 pp
FLEET  3h: n=10,428 median 1.02  p95  7.07  p99 14.16  max 32.51 pp
FLEET  6h: n=10,384 median 2.01  p95 12.11  p99 20.35  max 38.79 pp
per-account 3h p99: next 14.16 · next2 10.14 · next3 18.65 · next4 10.22
```

---

## 8. Not derivable from this data

1. **Absolute limits (tokens, dollars, request counts).** Only percentages exist. Would become
   derivable from a single account where a known absolute consumption is observed against a
   percentage tick — e.g. logging `total_tokens` from the OTel exporter alongside the sweep for
   one week, giving pp-per-token directly.
2. **Whether the max 3 h burn (32.51 pp, next3) is consistent with the 4.84 coupling.** 32.51 pp
   weekly × 4.84 ⇒ 157 pp of 5 h window inside 3 h, which exceeds what one window can supply. The
   coupling is flat up to the 15–100 pp band (n = 5, ratio 4.98), so either the ratio breaks in the
   extreme tail or that single window is instrumented wrong. **I could not settle it and am not
   imputing an answer.** Use p99 (14.16 pp / 3 h) as the defensible planning ceiling, not the max.
   Resolving it needs the raw per-window session_pct trace across that specific interval, which the
   6.4 min cadence and 1 pp quantization cannot supply.
3. **Whether `k`/`k_work` would improve the estimators if measured reliably.** 5,013 of 12,557
   records predate `k_work`/`k_src` entirely, and 712 carry `k_src:"unmeasured"`. The active-time
   estimators abstained 9.1% for lack of `k` and lost anyway — but that test ran on a series where
   concurrency is missing or unmeasured for 46% of records. **A clean concurrency series might
   change the verdict; this one cannot settle it.**
4. **Per-model attribution of weekly burn.** `fable_pct` is a separate meter and no field
   attributes weekly consumption to Opus vs Fable vs cache. Would need a per-request cost stream.
5. **Anything about weekly-window *shape* across more than 2.16 windows per account.** 363 h of
   data = 2.16 weekly windows; only **8 weekly rolls** exist in the entire series. Every claim
   here about behaviour *across* a weekly boundary rests on 8 events. Six weeks of series would
   make week-over-week seasonality derivable; today it is not.

---

## 9. Design-law compliance

- **L1 (report against window phase, not raw percentage).** §1's abstention-by-phase table is
  phase-indexed; `burst_pctile` and `strand_forecast_pp` are both defined against the remaining
  window, not the raw pct.
- **L2 (abstain, never impute).** Ground truth abstains on 4.3–6.6% of horizons for coverage; the
  proposed metrics carry an explicit measured-span abstain rule (§5.3); §8 lists five quantities
  reported as not-derivable rather than estimated; the 32.51 pp outlier is flagged, not explained
  away.
- **L3 (one renderer).** Every proposal is a change to `apply_burn`'s existing fields consumed by
  the existing `pace_line` / `_su_projected`. No second reader is proposed.
- **L4 (token-free channel).** All of this reads a disk series; nothing enters a model's context.
- **Q1/Q2 only.** Every metric here argues for *utilisation* (find the stranding, size the burst,
  stop the router being blind). None is a quality-per-token, cost-per-finding, or tokens-per-commit
  shape; none can be maximised by producing worse work — `strand_forecast_pp` and `burst_pctile`
  both improve when *more* work is done, never when less.

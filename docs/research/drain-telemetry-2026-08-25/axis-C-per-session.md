# AXIS C — What does ONE active session drain per hour?

Scratch scripts (all read-only over `~/.claude/logs/account-utilization.jsonl`):
`clib.py` (loader/binner/WLS) · `c0_census.py` · `c1_basic.py` · `c2_regress.py` · `c3_pairs.py`
(**primary estimator**) · `c4_ksrc_and_conv.py` · `c5_model.py` · `c6_final.py` · `c7_planner.py` ·
`c8_headtohead.py` / `c8b_headtohead.py` (control) · `c9_wrap.py` · `c10_snapshot.py`.

Series as read: **12,561 records · 4 accounts · 2026-08-10T05:58Z → 2026-08-25T09:12Z**.

---

## 0. The headline

**The per-session-hour primitive exists and is measurable — and the moment you measure it, the
planning question stops being "how many sessions" and becomes "whose sessions".**

Right now, at the same instant, on the same census instrument:

| acct | last 6 h weekly rate | mean k | **weekly pp per session-hour** |
|---|---|---|---|
| `next`  | 2.679 pp/h | 1.98 | **1.353** |
| `next3` | 1.400 pp/h | 5.48 | **0.256** |

`next3` has **2.8× more sessions than `next` and burns HALF the rate**. Its sessions are **5.3×
less productive per session-hour**. `next3` needs 2.873 pp/h to finish its week; `next` needs
0.444 pp/h and is running at 2.679 — i.e. **the fleet's burn is in the wrong account, and adding
sessions to `next3` is not the lever.** Two session-hours per hour at `next`'s *current* intensity
clears `next3`'s 8 pp; eleven at `next3`'s own intensity would be needed.

---

## 1. Method (and why the incumbent shape had to be abandoned)

Two things break the obvious estimator:

1. **The counters are integers.** A 1 pp weekly step is ~9 minutes of heavy work. Over the median
   6.4-min sample gap, `dW` is 0 in 69% of 1-hour bins. Any *per-bin* rate is quantisation noise.
2. **`weekly_reset_at` / `session_reset_at` carry sub-second jitter** (they are computed `now+delta`
   each sweep), so the raw string is a **unique key per row**. Naively segmenting windows on it puts
   every sample in its own window and yields **zero** usable bins. `clib.py` rounds both to a 10-min
   grid; real reset instants sit on that grid and adjacent windows are hours/days apart.

**PRIMARY ESTIMATOR (`c3_pairs.py`) — sample-level attribution.** Every adjacent sample pair inside
one window contributes `(dt hours, dW pp)` to the bucket of the k reading live over it. Totals are
exact, so quantisation cancels *in the aggregate* instead of destroying a per-observation rate.
Guards: `dt ≤ 0.5 h` (a k reading only describes the next 30 min), same window key, `stale=false`,
`auth ∈ {ok, healed}`, `dW ≥ 0`.

**k resolution mirrors `bin/claude-accounts` `k_src()`/`k_eff()` exactly**: `work` → `k_work`;
`panes`/legacy (pre-2026-08-16 rows have no `k_src`) → `k`; `unmeasured` → dropped.

**Coverage.** Weekly pipeline keeps **10,390 / 12,557 pairs = 82.7%** (1,144.7 h, 697 weekly pp,
3,083.6 session-hours). Drops: stale 1,338 · k missing 580 · window roll 190 · gap 44 · auth 15.
5h pipeline keeps 8,899 (window rolls are the big cut — 2,121 — because the 5h window rolls ~72×
over the span). `k_src` mix over the whole series: work 42.1% · panes-legacy 39.7% · panes 12.3% ·
**unmeasured 5.9%**.

---

## 2. The primitive

### 2.1 Weekly meter

| k bucket | hours | pp | pp/h | **weekly pp / session-h** |
|---|---|---|---|---|
| **k_src=work (`k_work`)** | | | | |
| 0 | 182.8 | 32 | 0.175 | — |
| 1 | 164.8 | 56 | 0.340 | 0.340 |
| 2 | 91.6 | 58 | 0.633 | 0.317 |
| 3 | 40.3 | 43 | 1.067 | 0.356 |
| 4 | 23.9 | 39 | 1.634 | 0.409 |
| 5 | 10.8 | 21 | 1.951 | 0.390 |
| 6–7 | 8.6 | 25 | 2.908 | 0.450 |
| 8–9 | 3.6 | 11 | 3.023 | 0.365 |
| 10–14 | 3.0 | 10 | 3.377 | 0.309 |
| **aggregate** | **532.8** | **300** | | **0.3660** |
| **k_src=panes** | | | | |
| aggregate | 611.9 | 397 | | **0.1754** |

### 2.2 5-hour meter

| | aggregate 5h pp / session-h |
|---|---|
| k_src=work | **1.9356** |
| k_src=panes | **0.9874** |

Per-k (work): k=1 → 1.79, k=2 → 1.85, k=3 → 1.96, k=4 → 2.05, k=5 → 1.88, k=6–7 → 2.32.

### 2.3 Spread (the planner's downside, 3-h blocks, k_src=work, capped periods excluded)

| k | n blocks | mean | p10 | p25 | p50 | p75 | p90 | max |
|---|---|---|---|---|---|---|---|---|
| 1–2 | 34 | 0.488 | 0.000 | 0.082 | 0.382 | 0.735 | 0.963 | 1.645 |
| 3–4 | 7 | 1.046 | 0.580 | 0.813 | 1.097 | 1.269 | 1.455 | 1.706 |

**p10 is ZERO.** One in ten 3-hour blocks with 1–2 working sessions moves the weekly meter *not at
all*. The planner must treat the per-session rate as a distribution with a real mass at zero, not as
a constant.

Across the whole `k>0` block population (weekly, work): mean **0.303**, p10 **0.000**, p25 **0.000**,
p50 **0.240**, p75 **0.441**, p90 **0.744** pp/session-h.

---

## 3. Is it linear in k? No — it saturates at k_work ≈ 6

3-hour blocks, weighted by hours, weekly meter, `k_src=work`:

| model | fit | R² |
|---|---|---|
| linear | `rate = +0.236(±0.077) + 0.1753(±0.0302)·k` | 0.176 |
| quadratic | `k²` coef **−0.0225 (t = −7.82)** | 0.407 |
| hockey stick, knot 3 | slope_lo 0.496 → slope_hi **0.052** (Δ t = −5.06) | 0.291 |
| hockey stick, knot 4 | slope_lo 0.497 → slope_hi **0.000** (Δ t = −6.36) | 0.345 |
| hockey stick, knot 5 | slope_lo 0.487 → slope_hi **−0.045** (Δ t = −7.30) | 0.384 |
| **hockey stick, knot 6** | slope_lo **0.493** → slope_hi **−0.096** (Δ t = −8.27) | **0.426** |
| power law | `rate = 1.248 · k^0.215 (±0.035)` — p ≪ 1 | 0.106 |

**Saturation is not an artifact of the caps.** Re-fit excluding the confound directly:

| population | intercept a | slope b (k<6) | R² |
|---|---|---|---|
| all blocks | −0.151 (±0.080) | 0.493 (±0.046) | 0.426 |
| excl. `session_pct ≥ 90` (5h cap stops work) | −0.057 (±0.077) | 0.394 (±0.047) | 0.318 |
| excl. `weekly_pct ≥ 90` | −0.171 (±0.085) | 0.505 (±0.049) | 0.430 |
| **excl. BOTH — the planner model** | **−0.074 (±0.082)** | **0.403 (±0.050)** | **0.319** |

The negative-then-flat high-k slope survives every exclusion. **Adding sessions past ~6 working
sessions buys nothing measurable.** The observed ceiling is **~2.9–3.4 weekly pp/h**, and the
pair-level table reaches it at k_work 6–7 (2.908) and does not exceed 3.38 at k_work 10–14.

⚠️ **Honest limit on the knot.** The high-k evidence is thin: 8.6 h at k_work 6–7, 3.6 h at 8–9,
3.0 h at 10–14. The knot's *existence* is robust (t = −5 to −8 across four knot positions and three
exclusion sets); its exact position is not. Read it as "somewhere in 4–7", not "6.0".

### The intercept — is an idle-but-live session free?

**Two different questions, two different answers.**

- **A session the census cannot see is not free.** At `k_work = 0`: **0.1751 weekly pp/h** over
  182.8 h — **32 of 300 pp (10.7%) of all weekly burn** moves while the working-session census reads
  zero. On the 5h meter: **1.06 pp/h at k=0**, 150 of 1,496 pp. 157.2 h (30% of all measured hours)
  had `k_work = 0` while `k_panes > 0`. Causes not separable from this series: `k_work` is a 10-min
  transcript-mtime window (`KWORK_WINDOW_MIN = 10.0`), so a session thinking for 11 minutes is
  invisible; sub-agents and cloud sessions are further candidates; repo task **#171** already records
  that "k_work is blind to 46–63% of live writers".
- **The FITTED intercept is ~zero or negative.** The planner model gives `a = −0.074 (±0.082)` —
  statistically indistinguishable from 0. So there is **no evidence of a per-session fixed overhead**:
  an idle-but-live session that is genuinely idle drains nothing. The 0.175 pp/h floor is *unattributed*
  burn, not *overhead*.

Both facts bind: the planner must add a **~0.17 pp/h unattributed floor** and must **not** add a
per-session constant.

---

## 4. k_src QUALITY — the choice of census changes the answer 2.1×

**Same-pair comparison** (`c4_ksrc_and_conv.py`) — 4,890 pairs where `k_src=work`, so *both* counters
exist for the identical pairs. This isolates the instrument from the period:

```
 identical pair set: n=4890 hours=529.4 weekly pp=298
   session-hours by k_work :    813.6  -> 0.3663 pp/session-h
   session-hours by k_panes:   2312.1  -> 0.1289 pp/session-h
   pane census inflates session-hours 2.84x
   mean k_work=1.54  mean k_panes=4.37
   hours with k_work=0 but k_panes>0: 157.2 (30% of all hours); pp moved in them = 28
   hours with k_panes=0 but k_work>0:   0.9
```

- **The pane census inflates session-hours 2.84×**, so the per-session rate it implies is **0.35× the
  truth** — 0.129 vs 0.366 pp/session-h on the *same* pairs. The comment at
  `bin/claude-accounts:562-580` ("panes over-states burn because idle desks count") is confirmed and
  now quantified.
- The bias is one-directional: 157.2 h of `k_work=0 ∧ k_panes>0`, against **0.9 h** the other way.
- **Panes is also a WORSE predictor, not just a biased one** (§6): out-of-sample 3-h forecast MAE
  1.518 on panes origins vs 1.363 for the incumbent, while on work origins ours *wins* (1.181 vs
  1.216).
- **Day-to-day stability**: work-census daily rate ranges 0.271–0.637 pp/session-h over 10 days
  (CV ≈ 0.28); pane-census ranges 0.093–0.395 over 16 days (CV ≈ 0.50).

**Practical cost right now.** `k_src` is fleet-wide (one transcript walk per sweep), so availability
is identical for all four accounts: **last 6 h — 45% work, 43% panes, 12% unmeasured**; last 24 h —
72% / 24% / 4%. At this instant **every account's most recent measured k is a PANE count.** A metric
denominated in working sessions must abstain or degrade **~55% of the time on a 6-hour horizon**.

---

## 5. Are all sessions equal? No — and k explains ≤43% of the variance

**Per-account** (k_src=work, whole series):

| acct | weekly session-h | weekly pp | **pp/session-h** | 5h pp/session-h |
|---|---|---|---|---|
| next | 203.5 | 90 | **0.4423** | 2.090 |
| next2 | 161.8 | 59 | **0.3646** | 2.203 |
| next3 | 273.8 | 91 | **0.3324** | 1.786 |
| next4 | 180.6 | 60 | **0.3322** | 1.742 |

Spread 1.33× across accounts on the weekly meter — real but small next to the *within*-account spread.

**Variance decomposition** (3-h blocks, weekly, k_src=work; R² of a weighted linear model):

| model | R² |
|---|---|
| k alone (linear) | 0.176 |
| k alone (hockey stick, knot 6) | **0.426** |
| k + account fixed effects | 0.185 (**+0.009**) |
| k + hour-of-day (4-h bands) | 0.252 (**+0.076**) |
| k + linear day trend | 0.177 (**+0.001**) |
| k + account + hour + trend | 0.264 |

**k leaves 57–82% of the variance unexplained, and account identity / calendar drift explain almost
none of it.** Hour-of-day is the only covariate that adds anything. What is missing is *intensity* —
whether a session is generating tokens or sitting at a prompt — and nothing in this series measures
it. That is the hard bound on any k-based planner.

**The live proof of that bound** is §0: two accounts, same minute, same instrument, **5.3× apart on
pp/session-hour**.

---

## 6. CONTROL — head-to-head against the incumbent (and it can fail, and it does)

`c8b_headtohead.py`. Forecast the next 3 h of weekly pp. Rolling-origin (expanding-window) fits, all
origins from 2026-08-19 onward (k_work only exists from 2026-08-16 — the naive first-half split in
`c8_headtohead.py` trained the work model on nothing and is superseded).

```
origins n=4323   mean realized 3h move = 1.455 pp  sd=2.036
  climatology (const)        MAE=1.357 RMSE=2.036 bias=+0.000
  incumbent burn_wk_ppd      MAE=1.253 RMSE=1.962 bias=+0.073
  ours a+b*k (rolling fit)   MAE=1.265 RMSE=1.907 bias=+0.182
  blend 50/50                MAE=1.210 RMSE=1.869 bias=+0.127
  ours beats incumbent on 48.6% of origins (2102/4323); MAE change +1.0%
    src=work    n=3236  incumbent MAE=1.216  ours MAE=1.181
    src=panes   n=1087  incumbent MAE=1.363  ours MAE=1.518
```

**Verdict, stated against my own hypothesis:**

- **On MAE overall, my estimator does NOT beat `burn_wk_ppd`** (1.265 vs 1.253, +1.0% worse). It does
  beat it on RMSE (1.907 vs 1.962) and the **blend beats both** (1.210, −3.4%). k is *complementary
  information*, not a replacement.
- **On `k_src=work` origins it wins** (1.181 vs 1.216, −2.9%); on `panes` origins it loses badly
  (1.518 vs 1.363, +11.4%). The instrument, not the idea, is the limiter.
- **The case I designed to favour mine REFUTED me.** "Incumbent implies < 0.5 pp/3h but k ≥ 4"
  (n=88): realized 0.69 pp, incumbent predicted 0.24, **mine predicted 1.99** — incumbent MAE 0.764,
  mine 1.726. A pile of open-but-quiet sessions is exactly where k over-predicts.
- **The converse case is a real, named win.** "Incumbent's 48-h slope implies > 2 pp/3h, but k ≤ 1
  right now" (**n = 443**): realized 1.71 pp, incumbent 2.60, mine 1.19 — **incumbent MAE 2.013 vs
  mine 1.407, −30%**. The incumbent's widest-pair-in-48h slope keeps projecting burn from a session
  pile that has already stood down; k sees the stand-down within one sweep.

**So: k is a better STOP signal than a START signal.** That is the honest, decision-changing result.

---

## 7. THE 5h SUB-CAP — measured for the first time

The two counters co-increment on the same underlying usage, so summing both over pairs where
*neither* window rolls gives the exchange rate directly (9,324 pairs, 1,031.5 h):

```
 TOTAL: weekly pp=723  5h pp=3787  =>  1 weekly pp = 5.24 5h pp
        => ONE FULL 5h WINDOW (100 5h-pp) = 19.09 weekly pp
   next   ratio 5.27  => 18.97 weekly pp        next2  ratio 5.29  => 18.92
   next3  ratio 5.23  => 19.13                  next4  ratio 5.16  => 19.39
 bootstrap 95% CI (2000 resamples): [18.03, 20.23] weekly pp
```

**Four independent accounts agree to within ±1.3%.** This is the cleanest number in the whole axis.

**Answers the operator's failure mode (2) outright:** *"Nobody has ever measured whether 9% of a
weekly can even FIT inside one 5h window."* **It fits, with room to spare.** One 5-hour window holds
**19.1 weekly pp** — 9 weekly pp is **47% of a single 5h window**. For `next3` right now: 8 weekly pp
= **41.9 5h-pp** against **90 5h-pp of headroom**. **The 5h sub-cap is NOT binding; slack is 48 5h-pp.**

Corollary the planner should hold: **the weekly cap ≈ 5.24 full 5-hour windows**, against 33.6
five-hour windows in a week. There is no week in which the 5h sub-cap is the binding constraint on
exhausting a weekly, *provided the burn is spread over ≥ 6 windows.* The 5h cap only ever bites on a
**cram** — trying to spend more than ~19 weekly pp inside one 5-hour block.

---

## 8. THE INVERSION — how many sessions for headroom H in T hours?

```
   N  =  (H/T  −  a)  /  b        with  a = −0.074 (±0.082),  b = 0.403 (±0.050)
                                        [weekly meter, k_work units, capped periods excluded]

   VALID ONLY WHILE  N ≲ 6.  Above the knot the slope is 0.00 to −0.10:
   the model has NO SOLUTION for a required rate above ~2.9–3.4 weekly pp/h.
```

Equivalent aggregate form, which is what to quote when the fit is not available:
`N = (H/T) / 0.366` in **working-session** units, or `N = (H/T) / 0.175` in **pane** units.

**Uncertainty.** Parameter-only 95% band on `next3`'s N (delta method): **5.15 … 8.54**. That band is
*optimistic* — it excludes the residual spread, which is the dominant term (p10 of realized
per-session rate is **0.000**). The honest planning band is the *empirical hit-rate* in §8.2.

### 8.1 `next3` right now

Live tail of the series, `2026-08-25T09:12:56Z`: **weekly 92% · 5h 10% · weekly resets in 2.78 h ·
headroom 8 pp · k = 5 (PANES — `k_work` unavailable this sweep)**.

| quantity | value |
|---|---|
| required rate | **2.873 weekly pp/h = 69.0 %/day** (the router's "70 %/day" — independently reproduced) |
| N in **working-session** units | **7.9** (fit form: 7.3 at H=8/T=2.98) |
| N in **pane** units | **16.4** |
| its current k | **5 panes** ⇒ ≈ **1.8 working sessions** at the fleet's 2.84× pane inflation |
| its own realized rate, last 6 h | 1.400 pp/h — **49% of what is required** |
| projected landing at its own rate (3/6/12 h) | 93.9% / 95.9% / 95.5% ⇒ **strands 4.1–6.1 pp** |
| 5h sub-cap | **not binding** (needs 41.9 of 90 available 5h-pp) |

### 8.2 Is 69 %/day achievable? Empirically, yes — but not by session count

P(a sustained 3-h block ≥ the required rate), over all 354 3-h blocks in 15 days, by k:

| threshold | k 0 | k 1–2.9 | k 3–4.9 | k 5–7.9 | k 8–14.9 | k ≥ 15 |
|---|---|---|---|---|---|---|
| ≥ 1.00 pp/h (24 %/d) | 1/95 = 1% | 8/145 = 6% | 26/59 = 44% | 14/34 = 41% | 5/5 = 100% | 3/7 = 43% |
| ≥ 2.00 pp/h (48 %/d) | 0/95 = 0% | 2/145 = 1% | 5/59 = 8% | 4/34 = 12% | 5/5 = 100% | 1/7 = 14% |
| **≥ 2.685 pp/h (64 %/d)** | 0/95 | 2/145 = 1% | 3/59 = 5% | **3/34 = 9%** | **5/5 = 100%** | 1/7 = 14% |
| ≥ 4.00 pp/h (96 %/d) | 0/95 | 1/145 = 1% | 2/59 = 3% | 1/34 = 3% | 2/5 = 40% | 1/7 = 14% |

Overall **15 / 354 = 4.2%** of all 3-hour blocks in 15 days ever reached 2.685 pp/h. Sustained
ceilings actually observed: 1-h max **14.68** pp/h, 3-h max **7.86**, 6-h max **4.66** pp/h (112 %/day).

**Plain statement for the operator.** The router's *"needs 70 %/day vs recent 28 %/day"* is
**achievable — but not by adding sessions to `next3`.** Three facts settle it:

1. `next3` is **already at k = 5**, i.e. already at or past the saturation knot in pane units and
   near it in working units. The model's N = 7.9 is *outside the region where the slope is positive*.
2. `next3`'s sessions are running at **0.25 pp/k-h**; `next`'s, right now, at **1.17–1.35 pp/k-h**.
   The gap is intensity, and k is blind to it (§5, R² ≤ 0.43).
3. **At `next`'s current per-session intensity, 2–3 session-hours per hour clears `next3`'s 8 pp.**
   At `next3`'s own current intensity it would take **≈ 11 concurrent sessions**, which is past the
   knot and has never been sustained for 3 h in this series at that rate.

So the action the primitive implies is **not "spawn more on next3" — it is "put the HEAVY work on
`next3` and stop feeding `next`."** `next` needs 0.444 pp/h to finish its own week and is running
2.679 (6× over); `next3` needs 2.873 and is running 1.400. The fleet's burn is in the wrong account.

### 8.3 All four accounts, this instant

```
acct    wk%  5h%  Twk_h  H_pp need_pp/h  need%/d  N_work  N_pane H in 5h-pp  5h room  fits?  k_now    src
next     49   26 114.78    51     0.444     10.7     1.2     2.5      267.2       74     NO      5  panes
next2    17    8  97.78    83     0.849     20.4     2.3     4.8      434.9       92     NO      1  panes
next3    92   10   2.78     8     2.873     69.0     7.9    16.4       41.9       90    YES      5  panes
next4    14    5  119.78   86     0.718     17.2     2.0     4.1      450.6       95     NO      1  panes
```

`fits?` = does the *remaining weekly headroom* fit inside the *current* 5h window. `NO` for next/next2/next4
is **not a problem** — those accounts have 98–120 h left, i.e. 20–24 more 5h windows, and the weekly cap is
only 5.24 windows' worth. `fits? = NO` is only a warning when `Twk_h < 5`.

---

## 9. Cross-check against Axis A (diurnal)

Per-session rate by **local hour** (UTC−7; 08:55Z ≡ 01:55 local), `k_src=work`, weekly meter,
baseline 0.3660 pp/session-h over 820 session-hours:

| local band | session-h | pp | pp/session-h | multiplier |
|---|---|---|---|---|
| 00–04 | 144.0 | 61 | 0.4237 | **1.16×** |
| 04–08 | 173.7 | 42 | 0.2418 | **0.66×** |
| 08–12 | 126.3 | 30 | 0.2376 | **0.65×** |
| 12–16 | 131.6 | 66 | 0.5015 | **1.37×** |
| 16–20 | 131.6 | 52 | 0.3951 | 1.08× |
| 20–24 | 112.5 | 49 | 0.4355 | 1.19× |

**2.1× peak-to-trough** on the per-session rate. The trough is 04–12 local (the operator asleep and
the first half of the morning); the peak is 12–16 local.

**Hour-adjusted inversion for `next3`.** Its 2.98 h window spans 01:55→04:53 local, i.e. 2.08 h in the
1.16× band and 0.90 h in the 0.66× band. Hour-weighted rate **0.3688** vs flat **0.3660** — the two
bands nearly cancel, so **N is unchanged at 7.3–7.9**. The adjustment matters elsewhere: the same
headroom entirely inside 04–08 local would need **11.1** sessions; inside 12–16 local, **5.4**. A
planner that ignores the hour is wrong by up to **2.1×** on session count.

---

## 10. NOT DERIVABLE from this series

1. **Per-session INTENSITY.** The single largest missing term — it is what §5's unexplained 57–82%
   of variance is made of, and what §0's live 5.3× gap between `next` and `next3` is. *Derivable if:*
   the sweep recorded per-account token counts (input/output/cache) per interval, e.g. from OTel or
   from the transcripts' own `usage` blocks, joined to the same timestamps.
2. **Absolute capacity.** No token or limit figure exists anywhere in the series or in
   `claude-accounts --json`. Everything here is in percentage points and cannot be converted. *Derivable
   if:* one calibration point — tokens consumed against a measured pp move — were ever recorded.
3. **The saturation MECHANISM.** Whether the flat slope above k≈6 is server-side throttling, local
   machine saturation (the repo has a documented ~15-session box ceiling), or simply that a human
   cannot keep 8 sessions genuinely busy. Three very different planner implications. *Derivable if:*
   §10.1's intensity series existed — a per-session token rate that *falls* as k rises separates
   "throttled" from "idle".
4. **Whether the 0.175 pp/h k=0 floor is cloud sessions, sub-agents, or the 10-min `KWORK_WINDOW_MIN`
   blind spot.** *Derivable if:* the sweep recorded a session-origin tag (local pane vs cloud vs
   sub-agent) alongside k, which repo task #171 (`k_agents`) is already scoped to add.
5. **The exact saturation knot.** 8.6 h at k_work 6–7 and 3.0 h at 10–14 is not enough to place it
   inside 4–7. *Derivable if:* a deliberate ramp experiment held k at 6, 8, 10 for a few hours each.
6. **Per-session-hour rate below 15-min resolution.** The 1 pp counter granularity means the shortest
   honest measurement window is ~1 h at k=3 and ~3 h at k=1.

---

## 11. What binds the design laws

- **L1 (report against window PHASE):** §8.3 reports `need_pp/h` and `T` explicitly, never a raw
  weekly %. `fits?` is qualified by `Twk_h`.
- **L2 (ABSTAIN, NEVER IMPUTE):** every proposed metric below has an explicit null condition, and
  the binding one — `k_src ≠ work` — is live **right now for all four accounts** (§4).
- **L3 (ONE RENDERER):** these are fields for `claude-accounts --readout`, not a second reader.
- **L4 (token-free channel):** everything here is computed from a JSONL on disk.
- **Q1/Q2 only:** every metric is a *utilization* quantity (pp/session-hour, sessions-needed, 5h fit).
  None divides output quality by cost; none can be improved by cutting effort, model, or context.
  There is no quality term in any of them to trade.

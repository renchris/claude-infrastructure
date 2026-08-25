# Axis B — the 5h↔weekly exchange rate, measured

**Headline: K = 0.192 weekly pp per 1 pp of the 5-hour window (95% CI [0.185, 0.198]).**
A full 5h window is worth **19.2 weekly pp**; the weekly limit is **5.21 full 5h windows**
(CI [5.05, 5.41]). Two independent estimators agree to within 0.2%. The ratio is stable across
account, day, concurrency and window phase, and shows **no detectable dependence on Fable mix**
— it behaves as a **plan constant**, not a workload property.

For the operator's live question: **next3's 8 weekly pp are reachable. The weekly meter binds; the
5h sub-cap has 2.2x margin.** What limits next3 is throughput/demand, not the cap.

---

## 1. Method and coverage

Source: `~/.claude/logs/account-utilization.jsonl`, 12,557 records, 2026-08-10T05:58Z → 2026-08-25T09:05Z.

| filter | dropped | kept |
|---|---|---|
| parse failures | 0 | 12,557 |
| `stale:true` (inherited/echoed sweep — a rate needs two *measurements*) | 1,047 (8.3%) | 11,510 |
| `auth` not in {ok, healed} | 14 | 11,496 |
| missing `session_pct` or `weekly_pct` | 0 | **11,496 (91.5%)** |

Schema drift (`k_work`/`k_src` absent on 5,013 early records) does **not** touch this axis — both
meters are present on every kept record. `k`/`k_src` are used only as covariates.

**The structural fact that makes the clean estimator possible.** `session_reset_at` is *stable*
within a 5h window (±1 s of clock jitter, so window ids are bucketed to the nearest 60 s) and goes
`null` when no window is open. The 5h window is therefore a **fixed, start-anchored window**, not a
rolling one. Verified monotonicity: **386/386** adjacent pairs inside one session window have
`d_session_pct ≥ 0`; **652/652** inside one weekly window have `d_weekly_pct ≥ 0`. Zero violations.
That means a completed window's final `session_pct` *is* its total consumption.

---

## 2. Estimator 1 — complete 5h windows (ground truth)

A window is COMPLETE when a later sample is observed strictly after its reset stamp (we saw the
roll) and the weekly window did not roll across it.

**234 complete 5h windows** (next 61, next4 61, next2 59, next3 53). Rejected: 7 weekly-rolled,
4 not-yet-rolled, 7 with `s_used < 1`. Observation gaps are small: head gap p50 0.12 h / p90 0.22 h,
tail gap p50 0.06 h / p90 0.23 h.

`s_used` = final `session_pct` in the window; `w_gain` = `weekly_pct`(first sample after roll) −
`weekly_pct`(first sample in window). OLS through the origin, bootstrap 4,000 resamples.

| subset | n | slope | ±SE | boot 95% | ratio-of-sums |
|---|---|---|---|---|---|
| all (s_used ≥ 1) | 234 | 0.1900 | 0.0018 | [0.1835, 0.1951] | 0.1861 |
| s_used ≥ 10 | 116 | 0.1905 | 0.0023 | [0.1841, 0.1958] | 0.1896 |
| s_used ≥ 30 | 43 | 0.1909 | 0.0038 | [0.1836, 0.1970] | 0.1908 |
| **s_used ≥ 50** (the fill-a-window regime) | **17** | **0.1920** | 0.0033 | **[0.1848, 0.1979]** | 0.1922 |

**No intercept.** Free-intercept fit (n=183, s_used ≥ 5): slope 0.1929 ± 0.0029, intercept
−0.118 ± 0.087 (t = −1.35). There is no fixed per-window overhead.

**Linearity.** Ratio by `s_used` bin: 0.158 (1–5, n=68) · 0.169 (6–10, n=55) · 0.186 (11–20, n=51) ·
0.198 (21–35, n=29) · 0.184 (36–55, n=18) · 0.192 (56–101, n=13). The low bins are a **quantization
artifact**, not a nonlinearity: both meters are integers, and a tiny window's `s_used` is inflated
by up-rounding while its sub-1pp weekly gain floors to 0. Above ~11 pp the ratio is flat. The
headline K is fit on the regime the operator's question lives in.

**The extreme observations are unambiguous** — every window that reached 100% session:

| acct | started | s_used | w_gain | ratio |
|---|---|---|---|---|
| next | 2026-08-17T19:55 | 100 | 19 | 0.190 |
| next3 | 2026-08-10T07:20 | 100 | 20 | 0.200 |
| next3 | 2026-08-16T20:06 | 100 | 20 | 0.200 |
| next3 | 2026-08-18T00:33 | 100 | 19 | 0.190 |
| next3 | 2026-08-18T05:38 | 100 | 19 | 0.190 |
| next4 | 2026-08-22T20:34 | 99 | 19 | 0.192 |

Six independent full windows, spread over 13 days and 3 accounts, land on 19 or 20 weekly pp. With
integer quantization that pins the true value to ≈19.5 ± 0.5 — consistent with the fit.

---

## 3. Estimator 2 — adjacent paired deltas (independent)

Every adjacent sample pair ≤1 h apart where **neither** window rolled: **9,573 usable pairs**
(rejected: 1,790 session-rolled, 71 weekly-rolled, 58 gap > 1 h). Deltas are heavily quantized
(7,256 pairs have `d_session = 0`; 8,854 have `d_weekly = 0`), so the aggregated/telescoping form
is the honest one.

- **ratio-of-sums = 0.1921** (Σd_session = 4,102 pp, Σd_weekly = 788 pp)
- OLS through origin = 0.1825, boot 95% [0.1737, 0.1906] — this form *discards* the 7,256 pairs
  where the coarse session counter had not ticked but weekly had, so it is biased low; it is
  reported for completeness, not as the estimate.
- fable-free pairs only (n = 9,384): **0.1949**
- binned means (quantization-robust): d_session=2 → 0.177 · 3 → 0.188 · 4 → 0.183 · 6 → 0.179.
  (d_session=1 → 0.125 is the up-rounding artifact of §2 again.)

**Agreement:** window-level 0.1920 vs delta-level 0.1921 — 0.05% apart, from disjoint arithmetic
(one uses only cross-roll observations, the other only within-window observations). This is the
strongest evidence in the analysis.

---

## 4. Is it a plan constant, or does it vary with what sessions do?

Every stratification lands inside [0.176, 0.198]:

| axis | result |
|---|---|
| **account** | next 0.1941±0.0037 · next2 0.1949±0.0026 · next3 0.1920±0.0022 · next4 0.1768±0.0070 (boot95 [0.143, 0.200], widest CI, smallest windows) |
| **day** (16 days) | min 0.170 (08-11) → max 0.206 (08-23); no trend |
| **concurrency k** | kmax 2 → 0.180 · 3 → 0.196 · 4 → 0.171 · 5 → 0.202 · 6+ → 0.1915 (n=76) |
| **weekly phase** | 0–25% → 0.188 · 25–50% → 0.177 · 50–75% → 0.191 · 75–100% → 0.191 |
| **k_src** | work 0.1934 · panes 0.1975 · unmeasured 0.1898 |

**Fable is the one real candidate confound and it does not survive.** Fable was active
(`fable_pct` moved) in 65 of 183 windows. Two-regressor fit `w_gain ~ b1·s_used + b2·fable_delta`:

- session coef **0.1910 ± 0.0025**
- fable coef **−0.0118 ± 0.0198**, **t = −0.60** — indistinguishable from zero.

Split directly: fable-free windows 0.1926 [0.1899, 0.1954] (n=118) vs fable-active 0.1871
[0.1735, 0.1980] (n=65). CIs overlap across nearly their whole range.

Credits are not a confound at all: `credits_on` is `false` on all 11,496 kept samples and
`credits_used` is 0 everywhere.

**Verdict: shippable as a constant.** `K = 0.192`, CI [0.185, 0.198].

*Numerological note, offered as a hypothesis and not as a claim:* 1/5.25 = 0.190476 lies inside
every CI above, i.e. the weekly limit may be exactly 5.25 full 5h windows. The data cannot
distinguish 5.21 from 5.25 and I am not asserting it.

---

## 5. Out-of-sample validation, with a control that can fail

Fit on the chronologically first 117 windows (slope 0.1868), predict the last 117:

| model | MAE | RMSE |
|---|---|---|
| **constant K (mine)** | **0.435 pp** | **0.602 pp** |
| per-account K | 0.480 pp | 0.681 pp |
| null: mean w_gain | 2.704 pp | 3.898 pp |
| null: predict 0 | 3.325 pp | 5.123 pp |

The constant predicts a held-out window's weekly cost to within **half a percentage point**, and
beats the per-account model — further evidence the ratio is a plan property, not an account one.

**The control:** shuffle `s_used` against `w_gain` within the test set. MAE goes 0.435 → **3.499**.
An estimator that could not fail would score the same under shuffling. It does not.

---

## 6. Does the 5h window ever WALL? Yes — and weekly accrual goes to exactly zero when it does

| acct | samples | ≥95% | =100% | max |
|---|---|---|---|---|
| next | 2,842 | 12 (0.42%) | 3 (0.11%) | 100 |
| next2 | 2,928 | 0 | 0 | 61 |
| **next3** | 2,921 | **71 (2.43%)** | **69 (2.36%)** | 100 |
| next4 | 2,809 | 4 (0.14%) | 0 | 99 |

**5 contiguous pinned episodes, 8.16 h total. Weekly accrual during every one of them was +0 pp.**

| acct | episode | duration | weekly across it |
|---|---|---|---|
| next | 2026-08-18T00:20 | 0.21 h | 44 → 44 (+0) |
| next3 | 2026-08-10T08:44 | 3.53 h | 89 → 89 (+0) |
| next3 | 2026-08-16T23:33 | 1.42 h | 42 → 42 (+0) |
| next3 | 2026-08-18T04:53 | 0.55 h | 77 → 77 (+0) |
| next3 | 2026-08-18T08:00 | 2.45 h | 97 → 97 (+0) |

The weekly wall is separate and also real: next3 sat at weekly 100% for **11.17 h** (2026-08-11),
next2 for 2.49 h.

### The one episode where the 5h cap demonstrably ate the endgame

next3, 2026-08-18. Weekly reset at 12:00Z.

```
07:54  5h= 91%  wk=96%   k=9
08:00  5h=100%  wk=97%   k=7   <- WALL
 ... 2.45 h pinned at 100%, weekly frozen at 97%, k=7 sessions live throughout ...
10:27  5h=100%  wk=97%   k=7
10:34  5h=  0%  wk=97%         <- window rolled
10:40  5h=  1%  wk=98%   k=9
11:54  5h=  3%  wk=98%   k=9   <- only 3 session pp in 1.3 h, with 9 sessions live
12:00  weekly reset — CLOSED AT 98%, 2 pp STRANDED
```

Both of the operator's failure modes in one 4-hour endgame. **2.45 h of the final 4 h (61%) were
spent walled** with 7 sessions live and producing nothing; the remaining 1.3 h were demand-limited.
Note also that **k > 0 does not mean burn** — during the wall the router saw 7 working sessions and
the meters moved zero. Any router that reads concurrency as consumption is blind here.

---

## 7. But at *week* scale the 5h cap is nowhere near binding — stranding is a demand problem

A 168 h week contains 33.6 five-hour windows = 3,360 session pp = **645 weekly-pp-equivalent** of
5h capacity, against a weekly limit of 100. So the 5h cap carries **6.5x headroom over a full
week**. Measured, per completed weekly window:

| acct | week ending | closed | stranded | 5h windows used | session pp burned | % of 5h capacity |
|---|---|---|---|---|---|---|
| next | 08-16 04:00 | 91% | 9 pp | 24 / 28.4 | 409 / 2,840 | 14.4% |
| next | 08-23 04:00 | 99% | 1 pp | 29 / 33.6 | 507 / 3,358 | 15.1% |
| next2 | 08-15 11:00 | 92% | 8 pp | 22 / 25.0 | 422 / 2,500 | 16.9% |
| next2 | 08-22 11:00 | 100% | 0 pp | 26 / 32.0 | 516 / 3,203 | 16.1% |
| next3 | 08-11 12:00 | 100% | 0 pp | 5 / 6.0 | 221 / 600 | 36.8% |
| next3 | 08-18 12:00 | 98% | 2 pp | 25 / 32.4 | 498 / 3,241 | 15.4% |
| next4 | 08-16 09:00 | 85% | **15 pp** | 24 / 29.4 | 400 / 2,940 | 13.6% |
| next4 | 08-23 09:00 | 92% | 8 pp | 30 / 33.6 | 411 / 3,358 | **12.2%** |

43 weekly pp stranded across 8 completed windows, at 12–17% of 5h capacity. **The cap did not cause
that stranding.** It is a scheduling/demand failure — with one exception, the endgame, where the cap
binds locally because you cannot roll a 5h window faster than 5 hours.

**This is the general rule.** The cap constrains a *rate*, so it only binds over intervals short
enough that you cannot roll enough windows. Weekly pp reachable in `h` hours before the reset:

```
wk_reachable_pp = K · [ session_headroom_pp                    (current window, if one is open)
                      + 100 · (number of further 5h windows that fully start before the reset) ]
```

---

## 8. THE DECISIVE ANSWER — next3, live

State (last non-stale sample, 2026-08-25T09:05Z): weekly **92%** (8 pp needed), weekly reset in
**2.78 h**; 5h at **10%** (90 pp headroom), 5h reset in **3.95 h**.

Because the weekly reset (2.78 h) arrives **before** the 5h reset (3.95 h), **no further 5h window
opens**. next3 is confined to the headroom of the window it is already in.

```
wk_reachable_pp = 90 pp × 0.1920 = 17.3 weekly pp     CI [16.6, 17.8]
weekly headroom needed                =  8.0 weekly pp
```

**The 5h sub-cap does NOT bind. It has 2.2x margin (CI 2.1x–2.2x). The WEEKLY meter binds.**

What must actually happen:

| required | value |
|---|---|
| weekly rate | 2.87 pp/h ( = 69 %/day ) |
| equivalent **session** rate | **15.0 session pp/h** |
| next3's recent rate | ~1.17 pp/h (28 %/day) → needs a **2.5x lift** |
| next3's demonstrated max over a 3 h span | 33.3 session pp/h (10.3 weekly pp/h) |
| required as a fraction of that demonstrated peak | **45%** |

**Reachable.** next3 has sustained 2.2x the required session rate for 3 hours on this very series
(2026-08-10 and 2026-08-18). The binding risk is not either meter — it is whether enough work is
dispatched in the next 2.8 h.

**Watch condition:** if `session_pct` reaches 100 before 11:52Z, the wall of §6 recurs and the
remaining weekly pp become unreachable — 90 pp of session headroom at the required 15 pp/h lasts
6.0 h, so this is not expected, but it is exactly the event that stranded 2 pp on 2026-08-18.

### Same calculation, all four accounts

| acct | weekly | need | reset in | 5h | `wk_reachable_pp` | required session pp/h | binding meter |
|---|---|---|---|---|---|---|---|
| next | 49% | 51 pp | 114.8 h | 26% | 455.8 [438.7, 469.8] | 2.3 | WEEKLY (8.9x margin) |
| next2 | 17% | 83 pp | 97.8 h | 8% | 401.7 [386.6, 414.0] | 4.4 | WEEKLY (4.8x margin) |
| **next3** | **92%** | **8 pp** | **2.78 h** | **10%** | **17.3 [16.6, 17.8]** | **15.0** | **WEEKLY (2.2x margin)** |
| next4 | 14% | 86 pp | 119.8 h | 5% | 479.0 [461.1, 493.8] | 3.7 | WEEKLY (5.6x margin) |

No account is currently 5h-blocked. The failure mode is entirely demand-side — except for next3,
whose margin is thin enough that a single walling episode would flip it.

---

## 9. Not derivable from this data

1. **Absolute tokens or dollars per weekly pp.** Only percentages exist. Would need an OTel token
   counter or a billing export joined on time.
2. **Whether Fable draws on the *weekly* meter at all** (as opposed to only `fable_pct` + the 5h
   window). The fable coefficient is −0.012 ± 0.020 — consistent with zero *and* with a −0.05
   effect. Distinguishing needs a controlled window: one 5h window of pure Fable and one of pure
   Opus, same account, back to back.
3. **The instantaneous throughput ceiling.** I can report demonstrated maxima (75 session pp/h over
   1 h) but not whether that was a ceiling or just the most work ever dispatched. Would need a
   deliberate saturation run.
4. **Whether next4's lower ratio (0.177) is real.** Its CI is [0.143, 0.200] and its windows are
   small (mean s_used 19). Would need ~10 more next4 windows above 50 pp.
5. **Sub-pp resolution.** Both meters are integers; nothing here can resolve below 1 pp, which is
   why the small-window bins are biased and why the CI cannot tighten much below ±0.007.

## 10. Reproduce

```
scratchpad/load.py               loader + schema-drift handling + monotonicity checks
scratchpad/windows.py            complete-5h-window observation builder
scratchpad/fit_windows.py        estimator 1 + stratifications (§2, §4)
scratchpad/confound.py           k / fable / credits / phase confounds (§4)
scratchpad/fable_and_deltas.py   2-regressor fable test + estimator 2 (§3, §4)
scratchpad/walling.py            walling census + throughput maxima (§6)
scratchpad/validate.py           out-of-sample + shuffle control + stranding (§5, §7)
scratchpad/decompose.py          cap-vs-demand decomposition + the 08-18 episode (§6, §7)
scratchpad/live.py               live application of both metrics (§8)
```

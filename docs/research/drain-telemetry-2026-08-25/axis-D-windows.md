# AXIS D — Reset crossings: what the discarded negative deltas actually say

Scripts: `lib_load.py`, `lib_win.py`, `d1_rolls.py` … `d12_live.py` (this directory).
Raw output of every script: `axis-D-raw-output.txt`.
Series: `~/.claude/logs/account-utilization.jsonl`, 12,557 records, 2026-08-10T05:58Z → 2026-08-25T09:12Z
(15.13 d). 1,047 records (8.3%) carry `stale:true` and are dropped, matching `_util_tail()`'s own rule;
11,510 kept. 4 accounts, 2,810–2,928 usable samples each.

---

## 0. Headline

**The 5-hour sub-cap cannot strand weekly quota and never has.** One full 5h window is worth a
**measured 0.200 weekly-pp per session-pp** — 20 weekly-pp — and a week contains 33.6 back-to-back 5h
windows, i.e. **672 weekly-pp of 5h capacity against a 100 weekly-pp cap (6.7×)**. Exhausting an entire
week needs **5.0 full 5h windows out of 33.6 (14.9%)**; the fleet already averages 17.7% fill. Over 241
completed 5h windows, **5 (2.1%) ever reached 100%**, median final **9%**.

The binding constraint is not the sub-cap and not the weekly cap. It is **concurrency**. Drain rate is
a step function of `k`: **1.2 session-pp/h at k≤1 → 4.7 at k=5-7 → 17.0 at k=12-19** (9,000 sample
pairs). At today's `k` the fleet strands **59.5 pp on next2 and 57.3 pp on next4** — visible four days
out — while the router's attention is on next3's 3-hour emergency, which is worth at most **8 pp**.

---

## 1. Roll detection, two ways — and the disagreement is the mechanism

| meter | stamp-change rolls | negative-delta rolls | same sample | disagree |
|---|---|---|---|---|
| weekly | 8 | 8 | 4 | 4 |
| 5h | 248 | 241 | 104 | 137/144 |

The counts agree; the *timing* does not, and the reason is a mechanism neither `apply_burn` nor
`wall_projection` models:

> **A window exists only while it is open.** When it expires with no further usage the API reports
> `pct = 0` **and `reset_at = null`**. The stamp does not advance at the reset — it goes *null*, and a
> new stamp appears only when work resumes.

Verbatim from the series (next3, weekly roll of 2026-08-11T12:00Z):

```
2026-08-11T11:59:03  wk% 100  wr 2026-08-11T12:00:00
2026-08-11T12:04:04  wk%   0  wr None                 <- counter zeroed; NO new stamp
...  5h51m of nulls ...
2026-08-11T17:56:27  wk%   0  wr 2026-08-18T12:00:00  <- stamp appears when work resumes
```

Lag from counter-zeroing to a new stamp appearing:

| meter | n | median | mean | p90 | max | lag < 0.2 h | lag > 1 h |
|---|---|---|---|---|---|---|---|
| weekly | 8 | 0.88 h | 2.31 h | 7.76 h | 7.76 h | 4/8 | 4/8 |
| 5h | 241 | 0.10 h | 0.81 h | 2.57 h | 12.66 h | 145/241 | 61/241 |

Dormant spans (stamp null): 5h median **0.49 h**, p90 3.45 h, max 12.49 h, n=137; weekly median 4.33 h,
n=4.

**Which detector to use.** The **negative delta is the reset instant**; the **stamp change is the
next-window-opened instant**. They differ by idle time. The stamp is nonetheless the right *identity*
key — it is stable to sub-second jitter for a window's whole life, so consecutive samples sharing a
stamp are one window, and a null separates windows unambiguously. That is what `lib_win.windows()`
does. A detector keyed on the stamp *alone* would have mis-dated four of eight weekly resets by up to
7.76 h.

**Data-quality note for Axis F.** Window start is quantised to a 10-minute grid, so consecutive 5h
windows can overlap by ≤10 min (`08:40→13:40` following `03:50→08:50`). Any code that assumes
non-overlapping windows will double-count those minutes.

---

## 2. THE HEADLINE NUMBER — weekly quota left on the table

Every weekly window whose reset instant we watched (last sample within 3 h of the reset, so `final`
is the true end-of-window total even where the window's *start* predates the series):

| acct | window (UTC) | final % | **stranded pp** | start observed |
|---|---|---|---|---|
| next | 2026-08-09T03:59 → 08-16T03:59 | 91 | **9** | no (pre-series) |
| next | 2026-08-16T04:00 → 08-23T04:00 | 99 | **1** | yes |
| next2 | 2026-08-08T10:59 → 08-15T10:59 | 92 | **8** | no (pre-series) |
| next2 | 2026-08-15T11:00 → 08-22T11:00 | 100 | **0** | yes |
| next3 | 2026-08-04T12:00 → 08-11T12:00 | 100 | **0** | no (pre-series) |
| next3 | 2026-08-11T12:00 → 08-18T12:00 | 98 | **2** | yes |
| next4 | 2026-08-09T09:00 → 08-16T09:00 | 85 | **15** | no (pre-series) |
| next4 | 2026-08-16T09:00 → 08-23T09:00 | 92 | **8** | yes |

**n = 8 completed weekly windows. Finals: 85, 91, 92, 92, 98, 99, 100, 100 — mean 94.0%, median 92%.
TOTAL STRANDED = 43 pp, mean 5.4 pp per account-week.** At 4 accounts that is **≈0.22 account-weeks
lost per fleet-week**.

This is the baseline. It is small — the operator's existing reactive rush *does* mostly work. What it
costs is measured in §4.

In flight at the tail: next 48% (114.8 h left), next2 17% (97.8 h), next3 92% (2.8 h), next4 14% (119.8 h).

---

## 3. Completed 5h windows — the sub-cap is nearly never touched

241 windows whose reset we watched:

| acct | n | mean | median | p90 | max | reached 100% |
|---|---|---|---|---|---|---|
| next | 62 | 17.7% | 10.5% | 45% | 100% | 1 |
| next2 | 61 | 16.4% | 11.0% | 44% | 61% | 0 |
| next3 | 56 | 21.0% | 7.5% | 61% | 100% | 4 |
| next4 | 62 | 15.8% | 9.0% | 39% | 99% | 0 |
| **all** | **241** | **17.7%** | **9.0%** | — | — | **5 (2.1%)** |

```
  0-  9%   123  #############################################################
 10- 19%    52  ##########################
 20- 29%    21  ##########
 30- 39%    13  ######
 40- 49%    13  ######
 50- 59%     6  ###
 60- 69%     5  ##
 70- 79%     0
 80- 89%     2  #
 90- 99%     1
100-100%     5  ##
```

19,841 pp of opened-but-unused 5h allowance, 82.3 pp per window.

**But the framing "use-it-or-lose-it 33.6 times a week" is wrong, and correcting it matters.** A 5h
window does not exist on a fixed grid — it *opens on first use* and runs 5 h (verified: `resets_at =
first_use_rounded_to_10min + 5h`). An unused 5h span costs nothing because no window was ever opened.
Measured dormancy — time with no 5h window open at all: next 13.3%, next2 11.2%, next3 22.3%, next4
11.5%; windows opened per week 26.8–30.1 against a theoretical 33.6. So **~89% of the available windows
are already being opened; the slack is entirely inside them (17.7% mean fill), not between them.**

**When the wall IS hit, it is total.** next3, 2026-08-18: session hit 100% at 08:00Z and the weekly
meter froze at 97% for the following 2.5 h until the 13:29 roll. Same shape on 08-10 (weekly frozen at
89% for 3.6 h). The wall is real; it is just very rare.

---

## 4. Accrual shape — the weekly meter is severely back-loaded, the 5h meter is linear

Each completed window normalised to [0,1] elapsed; mean cumulative fraction of its own final.

**Weekly (n=4 windows with an observed start):**

| phase | 0.1 | 0.2 | 0.3 | 0.4 | 0.5 | 0.6 | 0.7 | 0.8 | 0.9 |
|---|---|---|---|---|---|---|---|---|---|
| mean cum frac | 0.052 | 0.104 | 0.239 | 0.265 | **0.321** | 0.400 | 0.454 | 0.628 | 0.758 |
| linear says | 0.10 | 0.20 | 0.30 | 0.40 | 0.50 | 0.60 | 0.70 | 0.80 | 0.90 |
| **linear `proj_end` error, pp** | **−47.9** | **−48.0** | −20.3 | −33.8 | **−35.7** | −33.3 | −35.2 | −21.6 | −15.8 |

All four curves lie below linear at every interior decile. At mid-week only **32%** of the eventual
total has been spent.

**5h (n=62 windows, final ≥20%):** essentially linear — max excess +0.039 at phase 0.3; linear
`proj_end` error is **+0.8 to +3.7 pp** at every decile from 0.4 on. `burn_5h_ph` and any 5h-side
projection are well-founded. **The projection problem is weekly-only.**

### 4a. Control: is the weekly back-loading PHASE, or is it CALENDAR?

The four shape windows partly overlap the same dates, so a fleet-wide late surge would fake this. Test:
pool the per-pair burn rate over **all 12 window instances** (including TRUNC_LEFT windows, which
contribute *late* deciles, and in-flight windows, which contribute *early* ones — deliberately
decorrelating phase from date). 11,287 adjacent pairs.

```
r(phase, calendar-day-index) = +0.030      <- phase and calendar are decorrelated in this sample
```

| phase decile | 0-.1 | .1-.2 | .2-.3 | .3-.4 | .4-.5 | .5-.6 | .6-.7 | **.7-.8** | **.8-.9** | **.9-1** |
|---|---|---|---|---|---|---|---|---|---|---|
| weekly pp/day | 9.9 | 10.9 | 16.3 | 10.6 | 8.5 | 10.3 | 9.9 | **25.7** | **22.2** | **27.6** |
| distinct windows | 8 | 10 | 11 | 10 | 9 | 8 | 8 | 8 | 9 | 9 |

**Phase 0.0–0.7 averages 10.9 pp/day; phase 0.7–1.0 averages 25.2 pp/day — a 2.3× acceleration in the
last 30% of the window.** Per account the pattern is clean in next3, next4 and next2; next is the one
exception (its maximum sits at decile 0.2–0.3).

**This is failure mode (3) measured.** The back-loading is not a property of the quota system; it is
the operator's own reactive end-of-window rush, showing up in the data as a shape. That has a sharp
consequence for §5.

---

## 5. The phase-corrected projector — built, backtested, and it LOSES

`proj_end = weekly_pct / S(phase)` with `S` the mean shape, fitted **leave-one-out** (never on the
window being scored):

| phase | linear MAE | linear bias | shape MAE (LOO) | shape bias | winner |
|---|---|---|---|---|---|
| 0.1 | 47.2 | −47.2 | 65.6 | +13.7 | linear |
| 0.3 | 46.9 | −19.7 | 72.3 | +18.6 | linear |
| 0.5 | 46.2 | −34.8 | 72.3 | +17.8 | linear |
| 0.7 | 36.7 | −34.0 | 45.2 | +9.2 | linear |
| 0.9 | 18.3 | −15.0 | 28.0 | +2.7 | linear |
| **overall** | **39.5** | — | **54.1** | — | **linear, by 37%** |

**The proposal is refuted on real data.** The shape correction removes the *bias* (−35 pp → +18 pp at
mid-week) but inflates the *error*, because between-window shape variance dominates the mean shape and
dividing by a small `S` amplifies it. At phase 0.5 the four windows sat at 61%, 31%, 20% and 13% —
and all four finished at 92–100%.

**What that last sentence actually means is the real finding.** Test a *constant* predictor
(leave-one-out mean of the other windows' finals):

```
CONSTANT predictor MAE  =  5.3 pp        (n = 8 completed weekly windows)
LINEAR projector at mid-week MAE = 46.2 pp
```

**Mid-window weekly percentage carries essentially no information about where the window will land.**
The incumbent `proj_end_pct` is not merely biased at mid-week — it is 8.7× worse than the number 94.
Both projectors should abstain there.

**And the shape is self-refuting anyway.** It is a fossil of the operator's rushing. If the planner
this axis feeds succeeds, the rush stops, the shape flattens toward linear, and any estimator fitted to
the current shape becomes wrong in the direction of complacency. **Do not ship a shape-fitted weekly
projector.** (Cf. MEMORY.md *"Control rots silently"* and *"Resetting % = phase"* — the 46 pp figure
recorded there reproduces here at 47.9 pp, decile 0.1.)

---

## 6. The exchange rate — and the control that could have refuted it

The series carries only percentages, but the two meters move together inside a window, so the rate is
derivable. Across 112 completed 5h windows with ≥10 session-pp of movement:

```
weekly-pp per session-pp:  median 0.200   mean 0.195   p10 0.174   p90 0.222
   next  0.200 (n=31)   next2 0.196 (n=32)   next3 0.200 (n=24)   next4 0.192 (n=25)
```

**Control (could have failed):** reconstruct each completed *weekly* window's final from its 5h windows
alone — `predicted = 0.200 × Σ(session-pp burned in every 5h window that week)`. A wrong rate shows up
as a systematic multiplicative error.

| acct | obs final | Σ 5h-pp | predicted | err |
|---|---|---|---|---|
| next | 99 | 463 | 92.6 | −6.4 |
| next2 | 100 | 513 | 102.6 | +2.6 |
| next3 | 98 | 492 | 98.4 | +0.4 |
| next4 | 92 | 462 | 92.4 | +0.4 |

**MAE 2.5 pp, bias −0.7 pp, across 4 independent accounts and weeks.** The rate holds.

Consequences:
- 1 full 5h window = **20 weekly-pp**. A whole weekly quota = **5.0 full 5h windows**.
- Fastest observed full drain of a 5h window: **1.40 h** (next3, 2026-08-10T07:20Z, k peaked at 37).
  Second fastest 2.37 h. So a whole week's quota is *physically* drainable in ~7–12 h of wall clock
  spread over 5 windows (≥25 h calendar, since windows cannot overlap).
- **33.6 windows/week × 20 pp = 672 weekly-pp of 5h capacity against a 100 pp cap = 6.7×.**

---

## 7. The lever: drain rate is a step function of concurrency

9,000 adjacent pairs inside 5h windows (0.05–0.5 h apart, non-negative delta, window not already at
100%), keyed on the `k` of the earlier sample:

| k | pairs | hours | session-pp/h | p90 | **weekly-pp/h** |
|---|---|---|---|---|---|
| 0 | 1047 | 114.1 | 1.1 | 0.0 | 0.22 |
| 1 | 1323 | 149.8 | 1.2 | 7.5 | 0.24 |
| 2 | 1436 | 160.6 | 2.3 | 9.5 | 0.46 |
| 3–4 | 2124 | 244.4 | 3.7 | 9.9 | 0.74 |
| 5–7 | 1968 | 224.7 | 4.7 | 11.4 | 0.93 |
| 8–11 | 941 | 106.7 | 7.3 | 19.6 | 1.47 |
| **12–19** | 82 | 9.2 | **17.0** | 47.1 | **3.40** |
| 20+ | 79 | 10.6 | 10.6 | 27.1 | 2.12 |

Two cautions. The 12–19 and 20+ bands rest on 9.2 h and 10.6 h of observation — thin. And **20+ is
*slower* than 12–19**, consistent with the machine-lag/oversubscription effect recorded elsewhere in
this repo; do not extrapolate above k≈19. `k` itself is null in 5.7% of samples (`k_src`: work 5050,
panes 1481, unmeasured 603), so the metric must abstain when `k` is unmeasured rather than assume 0.

---

## 8. Straddles — a real hazard that has never bound

A 5h window open across the weekly reset instant: **7 of 8 weekly resets straddled** (the exception,
next3 2026-08-11, was dormant at its reset).

| acct | weekly reset | 5h bucket already spent | 5h window remaining | spendable weekly-pp in that span |
|---|---|---|---|---|
| next | 08-16T03:59 | 4% | 4.17 h | 19.2 |
| next | 08-23T04:00 | 4% | 1.50 h | 19.2 |
| next2 | 08-15T10:59 | 4% | 2.17 h | 19.2 |
| next2 | 08-22T11:00 | 0% | 3.67 h | 20.0 |
| next3 | 08-18T12:00 | 3% | 3.50 h | 19.4 |
| **next4** | 08-16T09:00 | **45%** | 2.50 h | **11.0** |
| **next4** | 08-23T09:00 | **43%** | 2.50 h | **11.4** |

The hazard is real in principle: a fresh week opens with only the residual of a carried-over 5h bucket.
The worst observed case is next4 entering a new week with 11 weekly-pp of spendable headroom for 2.5 h.

**But it has never bound**, and the arithmetic says it cannot at current concurrency: consuming 11 pp
in 2.5 h requires 22 session-pp/h, above the highest band ever sustained (17.0 at k=12–19). At the
observed k=5–7 the rate limit delivers 2.4 pp in that span — **a factor of 4.6 below the capacity
limit.** File it as a hazard that switches on only if concurrency rises past ~k=19; do not spend a
scheduling rule on it now.

---

## 9. The live worked example, answered

State at the tail (2026-08-25T09:12Z, from the series — no `--fresh` call):

| acct | wk% | wk reset h | 5h% | 5h reset h | k | need pp | **reach pp @ today's k** | **strand pp** | k required | 5h sub-cap binds? |
|---|---|---|---|---|---|---|---|---|---|---|
| next | 49 | 114.8 | 26 | 3.28 | 5 | 51 | 84.9 | **0.0** | 2 | no |
| next2 | 17 | 97.8 | 8 | 1.12 | 1 | 83 | 23.5 | **59.5** | 6 | no |
| next3 | 92 | 2.78 | 10 | 3.95 | 5 | 8 | 2.1 | **5.9** | ~15 | **no** |
| next4 | 14 | 119.8 | 5 | 1.95 | 1 | 86 | 28.7 | **57.3** | 4 | no |

Capacity detail (5h allowance available before each weekly reset, converted at 0.200):

```
next   24 five-hour windows in 114.8 h -> 461 weekly-pp available, need 51
next2  21 five-hour windows in  97.8 h -> 405 weekly-pp available, need 83
next3   1 five-hour window  in   2.8 h ->  18 weekly-pp available, need 8
next4  25 five-hour windows in 119.8 h -> 490 weekly-pp available, need 86
```

**next3's 8 pp fits in one 5h window twice over** (18 available vs 8 needed) — failure mode (2) is
**not** live here, and the router's `70 %/day needed` is arithmetically right but says nothing about
achievability. What next3 actually needs is **40 session-pp in 2.78 h = 14.4 session-pp/h**, which the
band table places at **k ≈ 12–19**. At its current k=5 it will land near **94.6%**, stranding ~5 pp.
The action is *fire more concurrent sessions on next3 now*, not *work harder*.

**And next3 is the small problem.** next2 and next4 are each on track to strand **~58–60 pp** — an order
of magnitude more — and that is visible **four days ahead**, which is exactly the planning horizon the
operator asked for. Both need only k≈4–6 sustained, which the fleet demonstrably reaches.

---

## 10. Not derivable from this series

- **Absolute token/limit values.** Nothing here yields them and nothing needs to: the 0.200 exchange
  rate makes the two meters commensurable in percentage space. Would become derivable if the sweep
  recorded OTel token counts alongside the percentages.
- **Whether the weekly meter is linear in tokens.** The 0.200 rate is a *ratio of two meters*, so any
  shared non-linearity cancels and is invisible. A controlled burn of known token volume at a known
  cache-hit ratio would settle it.
- **Fable's contribution.** `fable_pct` moves with `weekly_pct` on next3 in the 08-10 traces, so Fable
  usage appears to bill the weekly meter too, but the series cannot separate the two contributions.
  Would need a window in which only Fable ran.
- **The shape of the k→rate curve above k≈19.** 79 pairs / 10.6 h, and it bends *down*. Needs a
  deliberate high-k burn with the machine-lag confound controlled.
- **Whether the back-loading survives a planner.** Structurally undecidable from history: the shape is
  a record of the behaviour the planner is meant to replace.

# Weekly-drain planner — synthesis of six measurement axes

**Verdict first.** The operator's goal is reachable with this data, and the product is a
**forecast**, not a capacity model. Measured baseline: the fleet strands **43 pp across 8 completed
account-weeks** (~19.9 pp/week fleet-wide, ~0.2 account-weeks of quota destroyed per week). The 5h
sub-cap has **never decided a weekly outcome** — at the alarm moment of all four historical strands
the headroom was reachable with 1.4x–9.3x margin — so failure mode (2) is a same-day guard, not a
planning constraint. A clamped strand forecast built on a roll-aware EWMA would have called all
four ≥4 pp strands with a **median ~20 h of lead time** (17.8 / 23.9 / 93.0 / 4.5 h) and fired on
**none** of the four windows that closed at 98–100%. What the data **cannot** carry is the lever:
concurrency explains 52% of 24-hour burn variance and nothing in the series sees the other half, so
the planner can name the account and the deficit but cannot promise that dispatching N sessions
closes it.

Every number below is recomputed from `~/.claude/logs/account-utilization.jsonl` by scripts in
`scratchpad/syn/` (`s_lib.py`, `k1_exchange.py` … `k7_livefields.py`), not carried over from the
axis reports. Series: 12,569 records, 0 parse failures, 11,522 non-stale, 4 accounts,
2026-08-10T05:58Z → 2026-08-25T09:27Z (15.14 d).

---

## 1. Reconciliation — where the axes disagree, re-measured

### 1.1 CONTRADICTION: the 5h↔weekly exchange rate. Six agents, four different numbers.

| axis | K (weekly pp per session pp) | method |
|---|---|---|
| B | 0.192 | complete 5h windows, cross-roll weekly gain |
| C | 0.191 | telescoping ratio-of-sums over non-rolling pairs |
| E | 0.1905 | OLS-through-origin on 228 grid-aligned windows |
| D | **0.200** | **median of per-window ratios** |
| A | **0.207** | 3h blocks, pooled Δsession/Δweekly |
| F | **0.225–0.237** | OLS of Δsession on Δweekly, run-level |

**Resolved: K = 0.192, and F's number is an instrument artifact.** Three independent estimators
recomputed from scratch (`k1_exchange.py`):

- complete 5h windows, `s_used ≥ 50`: OLS0 **0.1920** [0.1846, 0.1980] (n=17, 3,000-resample bootstrap)
- complete 5h windows, `s_used ≥ 30`: **0.1909**, `≥ 10`: **0.1905**, all: **0.1900** (n=234)
- adjacent pairs, neither window rolled, both open, dt ≤ 0.5 h: **0.1927** (9,560 pairs, ΣΔs=4,038, ΣΔw=778)
- the six windows that reached ≥99% session: (100,19) (100,20) (100,20) (100,19) (100,19) (99,19) — integer quantization pins the truth to 19.5 ± 0.5 weekly pp per full window.

**Why F got 4.22–4.63 session-pp per weekly-pp (K ≈ 0.22–0.24).** F keys windows on a 16-character
*string prefix* of the reset stamp (`s[:16]`). F itself measured the stamp's sub-second jitter
(median 0.294 s, straddling `03:59:59.x ↔ 04:00:00.x`) and then used a key that a jitter crossing
breaks: `2026-08-16T03:59` ≠ `2026-08-16T04:00`. Every crossing splits one run into two and drops
the straddling pair. Re-running F's exact estimator with the stamp **rounded** to the nearest minute
gives slope 5.086 → K = **0.1966**, and the run-level ratio-of-sums gives **0.1979** — both back
inside the band. F's 4.22 fleet aggregate rests on 1,580 session pp where the corrected pass finds
4,037. **F's exchange rate and the "one 5h window = 22.7 weekly pp" claim are withdrawn.**

D's 0.200 is a median-of-ratios, which quantization biases upward at small windows (B's own bin
table shows 0.158 at `s_used` 1–5 rising to 0.192 above 30). A's 0.207 comes from 3 h blocks, which
mix in partial windows. Both are the same measurement read through a coarser estimator.

**Shipped constant: K = 0.192, band [0.185, 0.198]. One full 5h window = 19.2 weekly pp. A weekly
limit = 5.21 full 5h windows.**

### 1.2 CONTRADICTION: does concurrency predict drain? C says yes (R²=0.43), E says no (R²=0.084), D builds a whole metric on it.

**Resolved: E's null is a resolution artifact, and it is demonstrable by changing one parameter.**
Same data, same relation, only the aggregation length varies (`k3_conc.py`):

| block length | n | r(k, weekly pp/h) | R² | blocks reading Δw = 0 |
|---|---|---|---|---|
| 1 h | 1,099 | +0.287 | 0.083 | **67%** |
| 3 h | 415 | +0.297 | 0.088 | 36% |
| 6 h | 213 | +0.419 | 0.175 | 17% |
| 12 h | 110 | +0.587 | 0.345 | 6% |
| 24 h | 52 | **+0.722** | **0.521** | **0%** |

E measured on rolling *hours*, where the 1-pp integer meter reads zero 67% of the time. r rises
monotonically as the zero fraction falls. E's "k does not predict drain, drop N" is wrong as stated;
the honest statement is **"k is unmeasurable against a 1 pp meter below ~6 h, and explains ~52% of
variance at 24 h."**

**But D's k-based planner is still not shippable, for a different reason.** D's drain table is in
**pane** units while C's is in **working-session** units, which is a 2.84x denominator difference —
that is the whole apparent disagreement between "k=5-7 → 4.7 session-pp/h" (D) and "0.366 weekly pp
per session-hour" (C). Recomputed in one unit (3 h blocks, `k3_conc.py`):

```
raw k (pane census)      k<0.5   0.116 wk-pp/h   k 4.5-7.5  0.838   k 11.5-19.5  3.397 (only 14.4 h)
                         k 1-2   0.224           k 7.5-11.5 1.332   k >19.5      0.782 (SLOWER)
k_work (working sessions)  — only 9 qualifying blocks exist in the entire series —
```

The working-session census cannot carry a shipped metric: requiring `k_src == "work"` across a whole
3 h block leaves **9 blocks / 25 h / 1 weekly pp**. F's independent finding explains it — `k_work` is
non-null on 70.1% of fielded rows and under-counts live writers by 46.7% where present (task #171).
And D's live prescription for next3 (`k ≥ 15`) sits in a band with 14.4 h of observation whose
neighbour above is *slower*.

**Resolution: k ships as a qualifier, never as a planner input.** No `sessions_needed`, no
`k_required`, no `burn_pp_per_session_hour`. See §4 rejections.

### 1.3 CONTRADICTION: is the incumbent's ~12 h weekly window night-weighted (F) or peak-weighted (A)?

**Resolved: A is right, F is wrong, and F's proposed fix is right for the wrong reason.** Fleet
weekly pp/h by America/Los_Angeles hour (`k4_live.py`, 1,320 measured hours, roll-aware):

```
00:1.09  01:1.02  02:0.78  03:0.69  04:0.64  05:0.41  06:0.59  07:0.27  08:0.25  09:0.08  10:0.54  11:0.49
12:0.37  13:0.44  14:0.59  15:0.75  16:0.75  17:0.67  18:0.52  19:0.56  20:0.97  21:0.72  22:0.73  23:1.01
```

PEAK = local 20, 23, 00, 01. TROUGH = local 07, 08, 09, 12. The trailing 12 h ending at the live
sample covers local hours 15–01, which runs at **0.806 wk-pp/h = 1.28x the 24 h mean**. F's claim
that the router's "28 %/day" is "dominated by the operator's night" is inverted — the window
over-represents the busy hours, so if anything the incumbent *over*-states recent pace. Widening the
tail to 48 h is still correct (see §5) but because it removes a diurnal bias whose sign F got
backwards, not because it removes a night.

### 1.4 CONTRADICTION: will next2 and next4 strand? A and D say ~118 pp; E says both are OK.

**Both are correct answers to different questions, and the design must carry both.** E computes a
*capability* envelope (p90 of demonstrated drain over the horizon) and finds the headroom reachable.
A and D project *current behaviour* forward and find it will not happen. Re-measured
(`k4_live.py`, newest sample 2026-08-25T09:27Z): next2 projects 45.2% (strand 54.8 pp), next4
projects 37.0% (strand 63.0 pp) — **117.8 pp**, matching A (118.2) and D (116.8).

The control that settles which one is the alarm (`k6_control.py`): at the firing moment of each of
the four historical ≥4 pp strands, the reachability metric read **REACHABLE every time** —

| account | week ending | at T− | headroom | reachable | margin |
|---|---|---|---|---|---|
| next | 2026-08-16 | 17.8 h | 15 pp | 68 pp | 4.5x |
| next2 | 2026-08-15 | 23.9 h | 10 pp | 93 pp | 9.3x |
| next4 | 2026-08-16 | 93.0 h | 55 pp | 368 pp | 6.7x |
| next4 | 2026-08-23 | 4.5 h | 19 pp | 27 pp | 1.4x |

**A capability metric can never be the alarm — it is 4/4 silent on real strands.** It is a *veto* on
the forecast, not a trigger. The forecast is the product.

### 1.5 CONTRADICTION: should the weekly `proj_end_pct` abstain below phase 0.90 (D) or be replaced by a horizon-matched estimator (A)?

**Resolved: both, and the clamp is what separates them.** D is right that mid-window weekly
projection is uninformative — the live proof is `next` at phase 0.32: the incumbent renders
proj_end **154.6% WALL**, and A's horizon-matched EWMA renders **231.4%**, i.e. the "better"
estimator is *worse* on this figure. Truth is that `next` needs 0.436 wk-pp/h, the **p41 of its own
24 h history** — it will land near 100% and neither projection is close.

But the *clamped* half is well-behaved: `max(0, 100 − proj)` discards exactly the overshoot regime
where both projectors fail and keeps the shortfall regime where the forecast works (4/4 recall,
0/4 false positives, §2c). **Ship the clamped strand; never render a weekly `proj_end_pct` above
100 as a number; keep the raw `burn_ratio`/WALL flag on the 5h meter only, where D measured the
linear error at +0.8 to +3.7 pp from phase 0.4 on.**

### 1.6 Where the axes AGREE — and why that is weak evidence

All six agree that (a) `burn_5h_ph` is degenerate, (b) `_util_tail`'s 128 KiB cap makes the 48 h
docstring unreachable, (c) the 5h cap is not the binding constraint, (d) no absolute token
denominator exists. **Six agents reading one file is one measurement, not six.** I therefore
re-derived (a) and (b) against the *live source* rather than the series:

- `bin/claude-accounts:1877` — `_util_tail(path=None, max_bytes=131072)`, called with no argument by
  `apply_burn`. Live file 3,675,531 B, mean record 292.4 B → the tail parses **407 rows spanning
  12.16 h** against a docstring claiming 48 h. Confirmed against the file on disk, not inferred.
- `bin/claude-accounts:1866` — `_su_projected` returns `su` unchanged when `b <= 0`. Replaying
  `apply_burn`'s exact guard over the series: **8,868 of 11,252 answered pairs read exactly 0.000
  (78.8%)**; smallest representable non-zero rate at the median 383 s cadence is 9.40 %/h, and the
  observed non-zero median is 9.68 %/h. Conditional on a 0.000 reading, the **realized** next-hour
  5h burn is n=6,275, mean **1.86 %/h** — so zero does not mean idle, and the router's 5h lookahead
  is inert on ~79% of evaluations.

The 5h wall is also real and total — 5 pinned episodes, and the weekly meter moved **exactly 0 pp
in every one**, with k reading 4–36 live sessions throughout:

```
next   2026-08-18 00:20Z  0.31h  weekly 44->44  k=4
next3  2026-08-10 08:44Z  3.53h  weekly 89->89  k=36
next3  2026-08-16 23:33Z  1.42h  weekly 42->42  k=5..10
next3  2026-08-18 04:53Z  0.55h  weekly 77->77  k=14
next3  2026-08-18 08:00Z  2.45h  weekly 97->97  k=7
```

Four of five are next3 — the account that repeatedly runs its weekly to the wire. So "the sub-cap
never binds" and "the sub-cap walls precisely in the endgame" are both true, and that tension is
load-bearing claim LB-3.

---

## 2. The operator's three questions, answered

### (a) How much is the fleet actually stranding per week?

**43 pp across 8 completed account-weeks = 5.4 pp per account-week = 19.9 pp/week fleet-wide**
(`k2_weekly.py`; a completed window is one whose reset was observed with the last sample ≤3 h before
it — 8 of 12 window-instances qualify).

```
next   reset 2026-08-16 04:00Z  final= 91%  strand=  9pp
next   reset 2026-08-23 04:00Z  final= 99%  strand=  1pp
next2  reset 2026-08-15 11:00Z  final= 92%  strand=  8pp
next2  reset 2026-08-22 11:00Z  final=100%  strand=  0pp
next3  reset 2026-08-11 12:00Z  final=100%  strand=  0pp
next3  reset 2026-08-18 12:00Z  final= 98%  strand=  2pp
next4  reset 2026-08-16 09:00Z  final= 85%  strand= 15pp
next4  reset 2026-08-23 09:00Z  final= 92%  strand=  8pp
```

Median 8 pp among the four that stranded ≥4 pp. **n = 8 is the binding limit on every weekly-side
figure in this design** and the series holds no more; it grows by ~3.7 completed account-weeks per
week.

### (b) Is next3's 8 pp reachable in its remaining ~2.6 h, and which meter binds?

**Reachable. The WEEKLY meter binds; the 5h sub-cap has 2.1x margin.**

Live at 2026-08-25T09:27Z: next3 weekly 92% (8 pp needed), weekly reset in **2.55 h**; 5h at 12%,
5h reset in 3.72 h. Because the weekly reset arrives *before* the 5h reset, next3 is confined to its
current window — no further window opens. Capacity = (100 − 12) × 0.192 = **16.9 weekly pp** against
8 needed. In session-meter units the 8 pp costs 41.7 session pp against 88 available.

The required rate is **3.138 weekly pp/h**, which sits at **p95.5 of next3's own realized 3-hour
burn distribution** (n=2,618 rolling windows). next3 has achieved ≥8 pp inside 2.6 h **9 distinct
non-overlapping times in 15.1 days** — about once per 40 h. So: genuinely achievable, genuinely a
p95 burst, and worth **at most 4.9 pp** (the projected strand). Against 117.8 pp sitting on next2
and next4 with four days of runway, **the 3-hour scramble is the smallest of the three
opportunities** — which is the answer the router's "needs 70 %/day" cannot express.

The one watch condition: 4 of the 5 recorded 5h walls were next3, and a wall freezes the weekly
meter dead. At 41.7 session pp over 2.55 h the window lands near 28%, so a wall is not expected —
but it is exactly the event that stranded 2 pp on 2026-08-18, when a 2.45 h wall ate 61% of the
final four hours.

### (c) How early could the fleet have known? — this lead time IS the product

Replaying a clamped strand forecast (roll-aware EWMA, half-life 8 h, 48 h lookback; fires when the
projected strand holds ≥4 pp and never retracts thereafter) over the 8 completed windows
(`k2_weekly.py`):

| account | week | final | true strand | last-continuous ≥4 pp call |
|---|---|---|---|---|
| next | 08-16 | 91% | 9 pp | **T−17.8 h** (predicted 4.2 pp at weekly 85%) |
| next2 | 08-15 | 92% | 8 pp | **T−23.9 h** (predicted 4.3 pp at weekly 90%) |
| next4 | 08-16 | 85% | 15 pp | **T−93.0 h** (predicted 5.3 pp at weekly 45%) |
| next4 | 08-23 | 92% | 8 pp | **T−4.5 h** (predicted 7.9 pp at weekly 81%) |
| next | 08-23 | 99% | 1 pp | never fired |
| next2 | 08-22 | 100% | 0 pp | never fired |
| next3 | 08-11 | 100% | 0 pp | never fired |
| next3 | 08-18 | 98% | 2 pp | never fired |

**Recall 4/4 on strands ≥4 pp; 0/4 false positives on windows closing at 98–100%.** Median lead
~20 h, range 4.5–93 h. The incumbent, at those same instants, printed benign pace lines with no WALL
flag (axis E's control: `0.91x → ~91%`, `0.95x → ~95%`, `0.66x → ~66%`, `0.61x → ~61%`).

**Honest limit:** the 4 pp materiality floor was chosen while looking at these 8 windows. It is
in-sample. Removing it re-admits next3 08-18 (a 2 pp strand) as a fire and costs a false positive.
This is load-bearing claim LB-2.

---

## 3. The metrics that ship — five

Each replaces or corrects a named incumbent field. All render through
`claude-accounts --readout` (design law L3); none introduces a second reader.

### M1 · `burn_5h_ewma_ph` — replaces `burn_5h_ph`

**Arithmetic.** Over adjacent sample pairs `(a,b)` in the trailing 6 h with `session_pct` present on
both and `0 < dt ≤ 1 h`:
`d = b.session_pct if rolled(a,b) else max(0, b.session_pct − a.session_pct)`;
`w = 2^(−((now − b.ts)/3600) / 1.0)`; value `= Σ(w·d) / Σ(w·dt_h)`, in %/h.
`rolled(a,b)` = the minute-**rounded** `session_reset_at` key changed, or `session_pct` decreased.

**Abstain (L2).** Null when the *raw measured span* (Σ dt over usable pairs, not the weighted span)
inside the 6 h lookback is < 1.3 h — the span below which ±1 pp quantization exceeds 25% of the 5h
meter's realized mean — or when fewer than 2 usable pairs exist. **Never** null on a roll.

**Action it drives.** `_su_projected`'s 5h lookahead, which decides whether the router excludes an
account for 5h pressure. Today that lookahead is inert on 78.8% of evaluations, so the router routes
onto accounts whose window is filling and off accounts it cannot see filling.

**Evidence it is better.** Head-to-head against realized next-hour 5h burn, n=8,068 scored points:
incumbent MAE **3.713 %/h**, EWMA **2.840 %/h** — a **23.5%** reduction, paired t = 12.4. Independently
reproduces axis A's 23.6% / t = 13.6.

**Live (2026-08-25T09:27Z, %/h).** incumbent → EWMA: next **27.53 → 15.27** · next2 **0.000 → 1.76**
· next3 **9.18 → 6.76** · next4 **0.000 → 0.99**. The incumbent reads inert on two of four accounts
that are demonstrably burning. No account abstains (measured spans 5.05–6.06 h).

### M2 · `burn_wk_ewma_ph` — replaces `burn_wk_ppd`

**Arithmetic.** Same roll-aware EWMA form over `weekly_pct`, in %/h, with the half-life set by the
**decision horizon**: hl = 4 h when `weekly_reset_h ≤ 6`, hl = 8 h over a 48 h lookback otherwise.

**Abstain (L2).** Null when the raw measured span in the lookback is < 6.8 h (below which ±1 pp
quantization exceeds 25% of the weekly meter's realized mean of 0.592 %/h). **Never** abstain on a
roll — reconstruct the post-roll accrual as a lower bound. Refuse to extrapolate past the half-life's
licence: any horizon > 12 h must use the hl=8 h form, never the hl=4 h one.

**Action.** Feeds M3 and the pace line's "recent" annotation. Its real win over the incumbent is
**availability**, not accuracy: every one of the incumbent's weekly abstentions is a discarded window
reset, and it is blind for the first 12 h of every weekly window — exactly when the week's plan is
set. On value the two are close (live: incumbent 43.79 / 7.96 / 29.85 / 3.98 %/day vs EWMA×24 =
38.0 / 6.9 / 29.3 / 4.6), which is why this metric ships on the roll-awareness and the horizon
licence, not on an MAE claim.

**Live (%/h, hl=8 h except next3 at hl=4 h).** next **1.584** · next2 **0.289** · next3 **1.203**
· next4 **0.192**. Raw measured spans 43.75–48.03 h; none abstains.

### M3 · `wk_strand_pp` — replaces the weekly half of `proj_end_pct` / `wall_risk`

**Arithmetic.** `max(0, 100 − (weekly_pct + burn_wk_ewma_ph × weekly_reset_h))`. The clamp is
load-bearing, not cosmetic: it discards the overshoot regime where every projector measured here is
badly wrong (`next` renders 154.6% on the incumbent and 231.4% on the EWMA against a truth near
100%) and keeps the shortfall regime where the forecast is 4/4.

**Abstain (L2).** Null whenever M2 abstains; null when `weekly_reset_h ∉ (0, 168]`. Never render a
weekly `proj_end_pct` above 100 as a number — report the strand and, separately, that the account is
on a wall trajectory. Never clamp a negative strand into a positive one.

**Action.** Ranks which account to load work onto **today**, days before its reset. This is the
metric that inverts the current priority: 117.8 pp on two accounts with four days of runway against
4.9 pp on the account the router is alarmed about.

**Live.** next **0.0 pp** (wall trajectory) · next2 **54.8 pp** · next3 **4.9 pp** · next4 **63.0 pp**.

### M4 · `wk_reach_pp` — new; no incumbent equivalent exists

**Arithmetic.** `K = 0.192`. `wk_reach_pp = K × [(100 − session_pct) if a window is open] + K × 100 ×
Σ_j min(1, (weekly_reset_h − t_j)/5)` over each further 5h window opening at `t_j = session_reset_h +
5(j−1)` while `t_j < weekly_reset_h`. Report the band using K = 0.185 and 0.198.

**Abstain (L2).** Null when `session_pct` or `session_reset_at` is null (a null stamp means **no
window is open**, a distinct state that must not collapse to zero); null when the implied session
movement is below 5 pp, where quantization makes K unreliable (measured ratio 0.158 below `s_used`
5 vs 0.192 above 30). Never impute a per-account K — the pooled constant beat the per-account model
out of sample (axis B: MAE 0.435 vs 0.480 pp).

**Action.** It is a **veto on M3**, and the only thing in the design that answers failure mode (2).
When `wk_reach_pp < 100 − weekly_pct` the 5h meter binds and dispatching more work changes nothing —
move the work to another account. It also collapses to ~0 during a 5h wall, which is the state in
which the router currently sees k=7 working sessions and both meters frozen.

**Why it ships despite never having fired.** It has read REACHABLE in 4/4 historical strands and
reads WEEKLY-binds on all 4 accounts today, so by the "must change an action" test it is on
probation. It survives because (i) without it M3 can prescribe a rate the sub-cap makes impossible,
and there is no other guard against that; (ii) it is the mechanical form of the operator's own
named failure mode, and answering it with "we have never seen it bind" is only defensible if
something keeps checking; (iii) it goes to ~0 exactly during the 5 measured wall episodes, the one
regime where every other metric in this design reads healthy. **This is the weakest of the five and
is named as such in LB-5.**

**Live.** next **441.2 pp** vs 50 needed (8.8x) · next2 **388.9** vs 83 (4.7x) · next3 **16.9** vs 8
(**2.1x**) · next4 **470.7** vs 86 (5.5x). All four read WEEKLY. next3 is the only account under a
3x margin — one walling episode from flipping.

### M5 · `burst_percentile` — replaces the rendering of `weekly_need_pct_per_day`

**Arithmetic.** Required rate `(100 − weekly_pct) / weekly_reset_h` in weekly pp/h, expressed as its
percentile within **this account's own** distribution of realized H-hour weekly burn rates, H chosen
as the nearest of {1, 3, 6, 12, 24} h to `weekly_reset_h` on a log scale. The distribution is every
rolling H-hour window inside one weekly window with span coverage 0.9–1.15 H.

**Abstain (L2).** Null when fewer than 200 qualifying windows exist for that account; null when
`weekly_reset_h < 0.5 h`. Report "never once achieved" explicitly rather than extrapolating a p100.

**Action.** Converts an uninterpretable "needs 70 %/day over 3 h" — a rate quoted in a unit 8x
longer than the window it must happen in — into "a burst you have performed 9 times in 15 days" or
"you have never done this." It is the go/no-go on failure mode (3), and it names the alternative
account when the answer is no.

**Live.** next **p41.4** (H=24 h, n=2,278; required 0.436 pp/h) · next2 **p64.8** (H=24 h, n=2,281;
0.851) · next3 **p95.5** (H=3 h, n=2,618; 3.138) · next4 **p87.1** (H=24 h, n=2,220; 0.719).
Reading: next2 and next4 need p65–p87 of their own routine behaviour to close 117.8 pp; next3 needs
a p95 burst to close 4.9 pp.

**Total shipped: 5.** Two replace degenerate estimators with measured accuracy gains (M1) or
measured availability gains (M2); one is the alarm and is the entire product (M3); one is its veto
and the only answer to a named failure mode (M4, on probation); one makes the alarm's demand legible
against the account's own history (M5). Every one changes which account receives work, or whether a
demand is issued at all.

---

## 4. Rejected — proposals from the axes I am not adopting

| proposal | axis | why not |
|---|---|---|
| `k_required` / "fire k≥15 on next3" | D | Table is in **pane** units; its k=11.5–19.5 band rests on **14.4 h** of observation and the band above it is *slower* (0.782 vs 3.397 wk-pp/h). Prescribing a k outside the measured positive-slope region is extrapolation wearing a number's clothes. |
| `burn_pp_per_session_hour`, `sessions_needed`, `k_intensity_ratio` | C | The working-session census cannot support them: requiring `k_src=="work"` across a 3 h block leaves **9 blocks / 25 h / 1 weekly pp** in the whole series. C's own live values abstain on 2 of 4 accounts today. Revisit after task #171. |
| Fitting a per-account or per-regime K | B, F | Pooled K beat the per-account model out of sample (0.435 vs 0.480 pp MAE). Every stratification lands in [0.176, 0.198]. |
| Shape-corrected weekly projector `weekly_pct / S(phase)` | D (self-refuted) | Leave-one-out MAE 54.1 vs 39.5 pp for plain linear. D refuted its own proposal; I am adopting the refutation. |
| Theil-Sen slope estimators | A (self-refuted) | Loses at every horizon on both meters; median-of-slopes suppresses the burst, and the burst is the signal. |
| `instrument_confidence` three-state label | F | Redundant once every metric carries its own abstain rule. A per-metric null already says "this instrument cannot see"; a parallel label invites a consumer to read a number *and* a caveat, which is how the caveat gets dropped. |
| `pace_target_5h_pct` (the "pace car") | E | **The strongest rejection and the closest call.** It is a genuinely good render — a level on a meter already in the table. But it does not change *which* account gets work; it is M3 divided by windows-remaining. It adds a column for a presentation gain, and the one-renderer law makes columns expensive. Recommend it as an alternative *rendering* of M3 if the operator finds "54.8 pp" less actionable than "fill each window to 21%". |
| Widening `burn_5h_ph`'s pair to ≥1 h instead of an EWMA | F | Cures quantization by reintroducing staleness. The EWMA recency-weights every pair in the window and gets both; measured 23.5% MAE win. |
| "Restore the 48 h tail" as the fix for `burn_wk_ppd` | F | Correct to fix the byte cap (§5) but the estimator itself must become roll-aware first: at a true 48 h span the incumbent's widest-pair form abstains **100% of the first 36 h of every weekly window** (axis A). Fix the reader and the estimator in one change or it gets worse. |
| Any absolute-token calibration as a prerequisite | all | Not needed. K makes the two meters commensurable in percentage space, which is all the planner uses. |

---

## 5. Data fixes required before these ship

1. **`_util_tail` selects by bytes, not time.** `bin/claude-accounts:1877`, `max_bytes=131072`,
   called with no argument by `apply_burn`. Live: 407 rows = **12.16 h** against a docstring
   claiming 48 h. M2's 48 h lookback is unreachable until this selects by timestamp. Adding any
   field to the record (e.g. `k_agents`, task #171) silently shortens it further — record size is
   292.4 B today and the coupling is undocumented.
2. **Window keys must round the reset stamp, never truncate it.** The stamp jitters sub-second and
   straddles minute boundaries. String-prefix keying is what produced axis F's refuted exchange rate
   and, per axis C, fragments 53 real next3 windows into 2,341. Use `round(ts/60)`.
3. **A null reset stamp means "no window open", not "missing data".** 15.0% of rows have a null
   `session_reset_at`; 1,789 of 1,790 have `session_pct == 0`. Treating it as missing drops 15% of
   rows from any phase-aligned analysis.
4. **Absent `k_src` is a third state.** 5,013 records predate the field. `r.get("k", 0)` converts a
   measurement failure into zero concurrency — the fail-open direction the router deliberately
   closed at `bin/claude-accounts:2054`.
5. **The rotation cliff.** `config/store-bounds.manifest:47` rotates this file at 25 MiB; at 237
   KiB/day that lands ~2026-12-11. All three readers open only the live path, so at rotation every
   burn estimate silently drops to a series of length ~0. Glob the `.gz` siblings. (Axis F's
   correction to plan lever #7 — "raise retention past 6 days" — is adopted: nothing has ever been
   deleted; the 6 days was the series length on the day it was written.)
6. **Task #171 (`k_agents`)** gates every per-session metric. `k_work` is non-null on 70.1% of
   fielded rows and misses 46.7% of live writers where present, and the miss is *anti*-correlated
   with load.

---

## 6. Design-law compliance

- **L1 report against phase, not raw percentage** — held. M3 and M5 are functions of
  `weekly_reset_h`; M4 is a function of window position within the 5h grid. The one raw-percentage
  render that survives is the 5h `burn_ratio`, where D measured the linear error at +0.8 to +3.7 pp
  from phase 0.4 on.
- **L2 abstain, never impute** — held, and strengthened: every metric names the *measured span* that
  makes it honest, not merely a sample count. One deliberate near-miss: M4's fallback when no 5h
  window is open assumes one *can* open immediately. That is a modelling assumption about the grid,
  not an imputed measurement, and it is stated in the metric.
- **L3 one renderer** — held. Five fields on `claude-accounts --readout`; no new tool, no second
  reader. `pace_target_5h_pct` was rejected partly to keep it that way.
- **L4 token-free channel** — held. Everything is computed from disk in the sweep; nothing enters a
  model's context.
- **No Q3 quality levers, no forbidden metric shapes** — held. There is no token, dollar, or output
  denominator anywhere in the design; M1–M5 are structurally incapable of expressing
  quality-per-token, cost-per-finding, or tokens-per-commit. Every metric can only ever argue for
  spending *more* quota (Q2) or for spending it on a different account (Q1). Note that this is not
  a virtue of restraint — it is forced, because no absolute denominator exists in the series.

---

## 7. Honest limits — what this design cannot do

- **n = 8 completed account-weeks.** Every weekly-side figure — the 43 pp baseline, the 4/4 recall,
  the 4 pp materiality floor — rests on it. Six weeks would make the claims real.
- **The lever is unmeasured.** k explains 52% of 24 h burn variance. The other 48% is per-session
  intensity, which the series structurally cannot see (`next` ran 1.35 weekly pp per pane-hour
  while next3 ran 0.256 at 2.8x the panes). So the planner can say *which* account is stranding and
  *how much*, and cannot say *what to dispatch* to fix it. Naming the account is still the whole
  gain, because today nothing names it.
- **The diurnal profile is 13–16 observed hours per bucket.** It is predictive enough to use for a
  horizon-weighted blend and not stable enough to quote per-hour values as constants.
- **The end-of-window acceleration (2.3x in the last 30% of the window, axis D) is a record of the
  behaviour this planner exists to replace.** If the planner works, the shape flattens and any
  estimator fitted to it drifts toward complacency. M1–M5 are deliberately fitted to *rates*, not to
  window shape, for this reason — but the acceptance test must be re-run after several weekly
  windows, not assumed.

# AXIS E — THE DECISION SURFACE

**Scope (frozen):** design the shippable decision surface in `claude-accounts --readout` that prevents
stranding, prevents 5h slamming, and removes end-of-window rushing — every threshold measured from
`~/.claude/logs/account-utilization.jsonl`, not chosen.

**Coverage.** 12,557 samples · 4 accounts · 2026-08-10T05:58Z → 2026-08-25T09:12Z (15.1 d) · 0
unparsable lines. Derived populations: **252 grid-aligned 5h windows** (228 kept, 24 discarded — 7 for a
weekly-window roll mid-5h-window, 17 for partial observation) · **13 weekly windows, 7 observed to
close** · **12 account-weeks with ≥12 h of observation** (the alarm backtest population).
`session_reset_at` / `weekly_reset_at` jitter sub-second between sweeps, so every window key is
**minute-rounded** — keyed raw, the series reports 2,605 distinct "5h windows" per account instead of 64,
and every window-level statistic collapses to n<3. That rounding is load-bearing, not hygiene.

---

## 1. What the renderer already prints

`readout_lines()` (bin/claude-accounts:3141) emits the markdown table, the `notes`/`footnotes` bullets,
the three lane picks, then `pace_line(rows)` (:2010). The footer, verbatim, live at 09:12Z:

```
weekly burn (1.00× = lands exactly at the 100% wall): next3 burn 0.94× → ~94% by reset, needs 71%/d over 2.7h (recent 30%/d) · next2 burn 0.41× → ~41% by reset, needs 20%/d over 4d (recent 8%/d) · next burn 1.54× → ~154% by reset ⚠ WALL, needs 11%/d over 4d (recent 42%/d) · next4 burn 0.49× → ~49% by reset, needs 17%/d over 4d (recent 4%/d)
```

Per account it carries four facts: `burn_ratio` (`wall_projection`, :1977), `proj_end_pct`, the
`⚠ WALL` flag at proj ≥ 100, `pace_need_ppd` (:1962), and `burn_wk_ppd` in parentheses.

**The hole, stated exactly.** Every one of those numbers is a *statement of requirement*. Not one is a
*statement of possibility*. `needs 71%/d over 2.7h` does not say whether 71 %/d is a thing next3 can do,
has ever done, or could do if every session on the box were pointed at it. The operator's three named
failure modes all live in that gap.

---

## 2. THE CONVERSION — the measurement everything else rests on

The 5h sub-cap cannot enter a feasibility statement until 5h-points and weekly-points are commensurable.
They are, and the exchange rate is a constant.

Segment the series into grid-aligned 5h windows; for each fully-observed window regress its weekly-pct
delta on its peak `session_pct` through the origin:

| population | n | slope (weekly pp per 5h pct) |
|---|---|---|
| all fully-observed windows | 228 | **0.1900** |
| 5h peak ≥ 30% | 41 | 0.1905 |
| 5h peak ≥ 50% | 15 | 0.1912 |
| 5h peak ≥ 70% | 8 | 0.1901 |
| next / next2 / next3 / next4 (peak ≥15%) | 18/25/20/19 | 0.1939 / 0.1934 / 0.1928 / 0.1804 |
| first half (08-10→08-18) / second half (08-18→08-25) | 41 / 41 | 0.1883 / 0.1940 |

Per-window ratio: median 0.1935, p10 0.1739, p90 0.2069 (n=82).

> **1 five-hour point = 0.190 weekly points. A full 5h window = 19.05 weekly pp. 5.25 full 5h windows
> exhaust a weekly limit.** Invariant across all four accounts and both halves of the series — a plan
> constant, not a fleet artifact.

*Command:* `scratchpad/e_windows.py`.

### 2.1 The operator's question, answered

> *"Nobody has ever measured whether 9% of a weekly can even FIT inside one 5h window."*

**Yes, with 2× room to spare.** One 5h window holds 19.05 weekly pp. next3's live 8pp headroom is
**42% of a single 5h window**, and its current 5h window sits at 10% with 3.95 h left.

### 2.2 …and the 5h sub-cap has never once been the binding constraint

A term that cannot bind is decoration, so it was tested. Over **10,169** samples carrying live headroom
past the abstain floor, the rate-free 5h-grid ceiling was the *tighter* of the two bounds **1,762 times
(17.3%)** — and was the **deciding** constraint (grid ceiling below the headroom) in **0**.

The arithmetic behind that: a weekly window contains 33.6 five-hour windows but only 5.25 windows' worth
of weekly quota — **the weekly limit is 15.6% of what the 5h caps would permit in a week**. Draining a
full weekly from zero at the grid ceiling takes **26.2 h of wall clock**.

⇒ **Failure mode (2) is real as a mechanism and has never fired in 15 days.** The sub-cap term stays in
the formula (it is the tighter bound 17.3% of the time and becomes decisive below ~1.3 h of notice at
high 5h fill), but it is not what strands quota here. **Throughput against the clock is.** That reframes
the whole surface: the alarm must be about *rate*, and it must fire days ahead, not hours.

*Command:* `scratchpad/e_subcap.py`.

---

## 3. THE FEASIBILITY VERDICT

### 3.1 The envelope

`achievable_drain` needs a rate ceiling. Not assumed — read off the series as the **demonstrated
envelope**: the max 5h-points gained inside one grid-aligned 5h window over a rolling `d`-hour horizon,
per account, at a stated percentile. Excerpt (p99 band, 5h-points):

| d (h) | next | next2 | next3 | next4 | fleet |
|---|---|---|---|---|---|
| 1.0 | 29 | 23 | 40 | 28 | 32 |
| 2.0 | 49 | 35 | 76 | 41 | 54 |
| 3.0 | 78 | 43 | 95 | 54 | 81 |
| 5.0 | 99 | 58 | 100 | 84 | 98 |

The spread is the point. next3 has taken a 5h window 0→95% in **1.40 h**; next2 has never exceeded 61
points in 5 h in 15 days. **Using a fleet number for next2 would be imputation** (design law L2) — the
verdict uses the account's OWN envelope and falls back to fleet only where the account has <20 windows.

### 3.2 The arithmetic

```
PP_PER_5H  = 0.1905                              # measured, §2, n=228

achievable_drain(T, sp, h5, acct, band):
    env  = envelope[acct] or envelope[fleet]     # 5h-points vs duration, at `band`
    pts  = min(100 - sp, env(min(T, h5)))        # the CURRENT 5h window: room ∧ rate
    t    = min(T, h5)
    while t < T:                                 # each subsequent window on the 5h grid
        seg  = min(5.0, T - t)
        pts += min(100, env(seg))                # a fresh window: 100 points of room ∧ rate
        t   += seg
    return pts * PP_PER_5H                       # weekly pp

headroom = 100 - weekly_pct
verdict  = WALLED  if headroom <= 0
           OK      if headroom <= achievable_drain(..., "p90")
           PUSH    if headroom <= achievable_drain(..., "p99")
           STRAND  otherwise;  unavoidable_loss = headroom - achievable(p99)
```

`min(room, rate)` inside each window is where the 5h sub-cap enters as a **binding constraint rather
than an ignored one** — it caps the current window at `100 - sp` regardless of rate, and caps every
future window at 100 regardless of time.

**N (sessions) is deliberately NOT a parameter.** The brief asked for `achievable_drain(T, N)`. Measured,
`r(k, weekly pp/h) = 0.290` over 11,886 hours — **k explains 8.4% of hourly burn variance**. And the
counterexample is in the series: `next` took a 5h window to 95% in 3.42 h on **k=4**, while `next3` needed
**k=36** to do it in 1.40 h. A verdict parameterised on N would be a confident function of a variable that
does not carry the signal. The envelope is per-account and duration-conditional instead, which is what the
data supports. *(This also constrains §6's action menu — see the honesty note there.)*

### 3.3 Abstain rule (L2)

Report **null**, not a verdict, when any of:

1. `elapsed_fraction < 0.05` — inherited verbatim from `wall_projection`'s floor. Same reason: at 1 h into
   a week the projection is noise. Fires on 0 of the 3 windows that were <25% elapsed in the backtest.
   ⚠️ **THE INHERITED VALUE IS STALE — do not copy 0.05 into an implementation.** `wall_projection`'s
   floor was widened to the window's last ~2 days on 2026-08-26 (`PROJ_SPEAK_H = 48.0`, i.e.
   `elapsed_fraction < 0.714`), because dividing by elapsed fraction corrects for phase only under linear
   burn and this fleet's burn is back-loaded — mean 46 pp error at day 3. See
   `docs/research/weekly-reset-utilization-2026-08-25.md` §3/§6. If this planner ships, it inherits the
   CURRENT floor, and its own weekly term needs re-scoring against the empirical envelope first.
2. `session_pct` or `session_reset_at` absent (15.0% of samples lack `session_reset_at`) — the current
   window's remaining room is unknown, and the 5h term cannot be imputed.
3. `weekly_reset_at` absent (1.4%), or `0 < weekly_reset_h ≤ 168` fails — bad data, not a signal.
4. The account has **<20** grid-aligned 5h windows of its own AND the fleet envelope is being substituted
   — render the verdict with an explicit `(fleet envelope)` tag rather than silently.
5. `stale_quota` / `error` on the row — the incumbent already withholds the percent here; the verdict
   inherits that, because a verdict over an inherited reading is a verdict about the past.

An abstaining row renders `feasibility: —` and is excluded from the alarm. Silence about an unknown is the
answer, not a gap.

### 3.4 Evaluated live, all four accounts (2026-08-25 09:12Z)

```
acct    wk    5h    T(wk)   5h↻    headroom   p90     p99    5h-cap ceiling   VERDICT
next    49%   26%  114.8h   3.3h     51.0pp  162.8   436.6      438.9pp       OK
next2   17%    8%   97.8h   1.1h     83.0pp  123.6   220.5      385.8pp       OK
next3   92%   10%    2.8h   4.0h      8.0pp    5.1    17.1       17.1pp       PUSH
next4   14%    5%  119.8h   2.0h     86.0pp  186.7   385.6      467.0pp       OK
```

**What would render** — one clause appended to each account's existing `pace_line` segment, and one new
line only when a verdict is non-OK:

```
weekly burn (1.00× = lands exactly at the 100% wall): next3 burn 0.94× → ~94% by reset, needs 71%/d over 2.7h (recent 30%/d) · … 
next3 ⚑ PUSH — 8pp in 2.8h is reachable but only at a rate next3 has held in <1% of its hours; the 5h cap is not the wall (17.1pp of 5h room against 8pp needed). Fill this window to 42%.
```

next3's verdict is the whole design in one row: the incumbent says `0.94× → ~94%`, which reads *fine,
slightly behind*. The feasibility verdict says *reachable, but only at your 99th-percentile rate, and
here is the level to hit.*

*Command:* `scratchpad/e_feas.py`, `scratchpad/e_live.py`.

---

## 4. THE LEAD TIME — derived, not guessed

The operator's complaint is being told at T-3h. The alarm threshold is set by two measured quantities.

**(a) The point of no return.** For each weekly window observed to close, walk the series and find the
last sample at which the then-remaining headroom was still ≤ `achievable_drain` at each band:

| window | final | strand | PNR @p90 | PNR @p99 | PNR @max |
|---|---|---|---|---|---|
| next 08-16 | 91% | 9pp | T-9.4h | **T-2.6h** | T-0.8h |
| next2 08-15 | 92% | 8pp | T-6.7h | **T-2.8h** | T-1.8h |
| next2 08-22 | 100% | 0pp | T-0.1h | T-0.1h | T-0.1h |
| next3 08-11 | 100% | 0pp | T-0.0h | T-0.0h | T-0.0h |
| next3 08-18 | 98% | 2pp | T-1.1h | T-0.3h | T-0.2h |
| next4 08-16 | 85% | 15pp | T-29.1h | **T-13.1h** | T-7.8h |
| next4 08-23 | 92% | 8pp | T-32.9h | **T-7.3h** | T-1.0h |

**(b) Spin-up latency.** Time from a real concurrency ramp (+≥3 sessions) to a ≥1pp weekly move, over
n=126 ramps: **median 14 min, p75 28 min, p90 61 min.** That is the mechanical floor on how fast any
remedy can show up on the meter.

**The derivation.** Fire at the **p90-achievability crossing**. Runway from that fire to the p99 point of
no return, per window: 6.7 h · 3.7 h · 15.8 h · 25.5 h · 39.6 h (n=5).

> **Minimum runway 3.7 h against a p90 spin-up latency of 1.02 h — a 3.6× margin.**
> Median alarm lead: **T-20.0 h**, against the T-3h the operator complained about.

**A fixed T-minus threshold cannot work, and that is the finding, not a caveat.** Across the same four
accounts the p90 crossing landed anywhere from T-6.5h to T-32.8h, because the crossing is a function of
headroom and of the account's own envelope, not of the calendar. Any constant ("warn at T-12h") is
simultaneously too late for next4 (whose 15pp strand became unrecoverable at T-13.1h) and pure noise for
next2 (whose 8pp strand was still trivially recoverable at T-6.7h).

*Command:* `scratchpad/e_final.py`, `scratchpad/e_alarm.py`.

---

## 5. ALARM POLARITY AND BUDGET — backtested

MEMORY.md `alarm-polarity-and-attention-budget`: an always-firing alarm says as little as one that cannot
fire. So the budget is an acceptance criterion, and it was tuned on the series.

**Design:** latched — one fire per `(account, weekly_window, severity)`, on the first sample whose verdict
leaves OK. Materiality floor **4pp** (tuned: without it, next3 08-18 fires STRAND at T-0.2h over a 2pp
gap — a true statement about an immaterial loss, which is the noise the floor exists to remove).

**Backtest, 12 account-weeks:**

| | count | per account-week | fleet/week |
|---|---|---|---|
| **PUSH** | 6 | **0.50** | **2.0** |
| **STRAND** | 5 | 0.42 | 1.7 |

- **Recall on windows that stranded ≥5pp: 4/4 = 100%** (next 91%, next2 92%, next4 85%, next4 92%).
- **Precision on closed windows: 4/5 = 80%** — next3 08-18 fired PUSH at T-39.9h and then recovered to
  98%. That is the correct failure direction: a PUSH that gets acted on and lands at 98% is the alarm
  working, not a false positive.
- **Silent on every window that landed ≥99%**: next 99%, next2 100%, next3 100%. Zero false alarms there.
- **Silent on all 3 windows below the 5% elapsed floor.**

**The comparison that makes this a control.** `cc-wave-plan:502` already ships an urgency predicate —
`weekly_need_pct_per_day > burn_wk_ppd`. Backtested over 9,029 evaluable samples it is **TRUE 66.6% of
the time** (next 43.1% · next2 51.2% · next3 90.0% · next4 82.8%). It is a usable routing *tiebreak* and
an unusable *alarm*. The proposed verdict is non-OK in **8.8%** of samples — 7.6× quieter — and latched,
**0.50 fires per account-week**.

**ACCEPTANCE CRITERION, stated as a number the implementation must hold:** *PUSH fires ≤ 1.0 per
account-week averaged over any trailing 4 weeks, with recall = 1.0 on windows that close below 95%.*
Breaching the ceiling means the envelope has drifted and must be re-fitted; breaching recall means it has
drifted the other way.

### 5.1 The control — what the incumbent said at the moment the proposed alarm fired

| window | final | proposed, at fire | incumbent footer, same instant |
|---|---|---|---|
| next 08-16 | **91%** | T-9.3h: 14pp > p90 14pp → PUSH | `next burn 0.91× → ~91% by reset, needs 36%/d over 9.3h` |
| next2 08-15 | **92%** | T-6.5h: 9pp > p90 9pp → PUSH | `next2 burn 0.95× → ~95% by reset, needs 33%/d over 6.5h` |
| next4 08-16 | **85%** | T-28.9h: 45pp > p90 45pp → PUSH | `next4 burn 0.66× → ~66% by reset, needs 37%/d over 28.9h` |
| next4 08-23 | **92%** | T-32.8h: 51pp > p90 51pp → PUSH | `next4 burn 0.61× → ~61% by reset, needs 37%/d over 32.8h` |
| next3 08-25 | 92% (live) | T-11.1h: 20pp > p90 20pp → PUSH | `next3 burn 0.86× → ~86% by reset, needs 43%/d over 11.1h` |

Three of those footers read **0.86–0.95×, no `⚠ WALL`** — i.e. *on pace, marginally behind*, hours before
8–9 points were destroyed. The incumbent is not wrong about any number it prints; it prints no number
that answers the question. **This is the case where the incumbent is wrong and the proposal is right, on
real data.**

*Command:* `scratchpad/e_control.py`, `scratchpad/e_incumbent_rate.py`.

---

## 6. THE ACTION MENU

An alarm with no owner is not an actuator (MEMORY.md `detector-with-no-owner-is-not-an-actuator`).

| verdict | the ONE action | existing mechanism |
|---|---|---|
| **OK** | nothing. Not rendered. | — |
| **PUSH** | concentrate the next wave on this account | **`bin/cc-wave-plan`** — already widens exactly one account's per-wave cap to `min(CC_WAVE_MAX_PER_ACCT_URGENT, KMAX − k_eff)` when it judges that account BEHIND (:502). **Replace its predicate `weekly_need_pct_per_day > burn_wk_ppd` with `verdict == PUSH`.** Same code path, same cap, same IDL record — a 66.6%-true predicate swapped for a 8.8%-true one. No new tool; `cc-dispatch` calls it already. |
| **PUSH**, no wave pending | fire one session onto the named account | **`scripts/handoff-fire.sh --account <acct>`** (:6895) — the flag exists and is honoured. |
| **STRAND** | accept the loss, stop spending attention on it | render `will strand ≈ N pp` once, latched, and **do not repeat**. The remedy window has closed; a repeated alarm here is pure noise. |
| **WALLED** | nothing new | already covered by the existing `○ weekly LIMITED (100%)` note. |

**GAP, stated plainly rather than hand-waved.** The action menu's central move — "raise concurrency on
account X" — has **weak measured support in this series**: `r(k, burn) = 0.290`, `R² = 0.084`. Adding
sessions is the only lever the fleet currently owns, and it does help (spin-up median 14 min to a ≥1pp
move), but 91.6% of hourly burn variance is explained by something the utilization series cannot see —
what the sessions are *doing*. **There is no shipped mechanism that raises drain rate per session**, and
inventing one would be a Q3 in disguise (see §7). File this: *the router can place work, it cannot make
work dense; the density term is unmeasured.*

---

## 7. THE ANTI-RUSH SCHEDULE — the pace car

`pace_need_ppd` (bin/claude-accounts:1962) is `headroom ÷ (weekly_reset_h/24)`. It is a bare instantaneous
requirement in a unit the operator does not control. Nobody can "do 71 %/day". It also has no schedule
behind it: it says the same thing at T-100h and T-3h, only louder, which is precisely how a reactive
end-of-window rush is produced.

**The pace car prices the remaining headroom in the unit that actually gates — the 5h window** — and
expresses it as a **level on a meter already in the same table**:

```
windows_left = 1 + max(0, T - h5) / 5                    # current window + the grid ahead
pace_pp      = headroom / windows_left                   # weekly pp to take per 5h window
PACE_TARGET  = pace_pp / 0.1905                          # ...as a 5h-window fill %, 0-100
status       = AHEAD if session_pct >= PACE_TARGET else BEHIND
```

Derived for all four, now:

| acct | headroom | incumbent `needs X %/d` | **pace car: fill each remaining 5h window to** | windows left | current 5h | |
|---|---|---|---|---|---|---|
| next | 51.0pp | 10.7 %/d | **11.5%** | 23.30 | 26% | AHEAD |
| next2 | 83.0pp | 20.4 %/d | **21.4%** | 20.33 | 8% | behind |
| next3 | 8.0pp | 69.0 %/d | **42.0%** | 1.00 | 10% | behind |
| next4 | 86.0pp | 17.2 %/d | **18.4%** | 24.57 | 5% | behind |

Three properties the incumbent number lacks:

1. **It is comparable to a column already on screen.** `fill to 42%` sits next to `5h used 10%`. The
   operator reads one row and knows the gap. `needs 69 %/d` is comparable to nothing in the table.
2. **It degrades smoothly.** As `windows_left` falls the target rises continuously and visibly, so the
   terminal sprint is *seen coming across days* instead of discovered. next3's target has been climbing
   all week; the incumbent's `%/d` figure did the same thing in a unit nobody could act on.
3. **It is bounded and self-refuting.** `PACE_TARGET > 100` is arithmetically impossible to satisfy in
   the remaining windows — that IS the STRAND verdict, reached from the other direction, and the two must
   agree. (Consistency check the implementation must hold: `PACE_TARGET > 100 ⟺ headroom > 5h-cap ceiling`.)

The pace car **replaces nothing** — `needs X %/d` keeps answering "how hard would I have to push", which
`pace_line`'s own docstring says the ratio does not. The pace car answers "what should this window look
like", which neither currently does.

**Sustainable ceiling, for calibration:** 19.05 pp per 5h window = 3.81 pp/h = **91.4 pp/day if every 5h
window were filled**. The fleet's median sustained 24h burn is 0.39 pp/h (p95 1.42, max 3.43). The fleet
is running at roughly **10% of its physical grid ceiling** and still strands a median 8pp per
account-week — which is why the answer is scheduling, not capacity.

---

## 8. What I would NOT build

**Refuted in `USAGE_TELEMETRY_100P.md` — must not reappear, and does not:**
- The Fable 50% arbitrage (refuted twice; Fable draws 1.79× Opus per list dollar). No part of this design
  routes to Fable to "buy cheaper points".
- Effort downgrades as a cost lever, and effort upgrades as a throughput lever — the ladder does not
  reproduce. The pace car raises *how many 5h windows get filled*, never *what a turn costs*.
- Recycling / context-shrinking as a cost lever (cache_read ≤0.018–0.049 pp/Mtok). Nothing here argues
  from context length.
- Releasing the parked dispatcher queue wholesale — 26–74× the remaining allowance. The PUSH verdict
  widens **exactly one account's cap by a bounded amount** through the mechanism that already exists.

**Forbidden metric shapes (§0/§3.2) — structurally absent by construction.** Every quantity in this design
is `weekly pp`, `5h pct`, `hours`, or a ratio of those. There is no denominator anywhere that is a unit of
*work delivered* — no commits, no findings, no output quality — so no line of this surface can be read as
"quality per token", and none of it can be cited to argue for a shorter answer. The verdicts are
**Q2 (utilization)** in every branch: PUSH says *spend more*, STRAND says *you already lost it*, and the
only thing OK does is stay silent.

**Two further things I would not build:**
- **A second renderer / a `cc-strand` tool.** L3. All of this is three fields on the existing row
  (`feasibility`, `strand_pp`, `pace_target_5h_pct`), one clause in `pace_line`, one conditional line, and
  a predicate swap in `cc-wave-plan`. A separate reader would drift from `wall_projection` the first time
  the envelope was re-fitted.
- **An `achievable_drain(T, N)` parameterised on session count.** §3.2: k explains 8.4% of variance and
  the two fastest 5h fills in the corpus ran at k=4 and k=36. A verdict that took N would look precise and
  be a function of the wrong variable.

---

## 9. Not derivable from this series

| quantity | why not | what would make it derivable |
|---|---|---|
| **Drain rate per session** | `r(k, burn)=0.290`, R²=0.084; and `k_src` is `unmeasured` in 12% of recent samples, while k≥19 rows show ~0 burn (pgrep-brief inflation, MEMORY.md `pgrep-f-matches-agent-briefs`). | OTel `claude_code.token.usage` with `session.id` (plan M6, enabled in 0 of 5 config dirs) joined to this series on `(acct, 5h-window)`. |
| **Whether next2's low envelope (61 pts / 5h) is capability or demand** | Unidentifiable: the series records what was drawn, never what was offered. next2 has simply never been pushed. | One deliberate saturation arm on next2 in the first hours of a fresh window — the same shape as the M0 meter experiment, cost ~19pp. |
| **Absolute tokens behind a weekly point** | Only percentages exist in this series and in `--json`. | Already answered elsewhere (~360K Opus-5 output tokens/pp, `USAGE_TELEMETRY_100P` §2.1) — not re-derived here, and this design needs no token unit. |
| **Whether the 0.1905 constant is a plan parameter or a mix artifact** | It is stable to ±0.007 across accounts and halves, which is consistent with `weekly_limit = 5.25 × 5h_limit` — but percentages cannot distinguish a plan constant from a stable workload mix. | The raw `api/oauth/usage` payload's `limit_dollars`/`used_dollars`, which are nulled on Max. Not obtainable. |
| **The density term** — what makes one session drain 10× another | No per-session attribution exists in this series at all. | Same OTel join as row 1. This is the largest unmeasured quantity in the whole utilization problem. |

---

## 10. Acceptance tests for the implementation

1. **Conversion.** `PP_PER_5H` re-fits to 0.190 ± 0.01 on any trailing 10-day slice of ≥100 windows; a
   drift outside that band abstains rather than re-scales silently.
2. **Abstention.** A row with `session_reset_at` absent renders `feasibility: —`, never a verdict. RED-proof:
   feed a row with the field deleted and assert no verdict string appears.
3. **Fire budget.** Replaying the 15-day series through the alarm yields **6 PUSH fires over 12
   account-weeks**; ≤1.0/account-week is the ship gate.
4. **Recall.** Replaying the same series, all 4 windows that closed below 95% fire PUSH; a mutant that
   raises the p90 band to p99 must go RED here (it drops next2 08-15 and next 08-16).
5. **Sub-cap term is live.** A synthetic row at `T=1.0h, session_pct=85%, headroom=8pp` must return
   STRAND with the 5h grid named as the cause — the term is not decoration and the test must be able to
   fail if it is dropped.
6. **Pace-car consistency.** `PACE_TARGET > 100 ⟺ headroom > 5h-cap ceiling`, asserted on every row.

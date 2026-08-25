# Weekly-reset utilization telemetry — do we have it, and what does it say?

**Date:** 2026-08-25 · **Question (goal):** *do we have telemetry of what our Claude Code weekly
limit % was at time of weekly reset, so we can identify if we are maximizing our usage and
what/if/when we are leaving usage on the table?*

**Answer: yes, we have it, it is dense, and it already has a reader.** Over the 8 completed weekly
windows the series covers, the fleet reset at a **mean 94.6% used — 5.4 pp left on the table**.
Under-use is *not* the current defect. The defect is that the **mid-week forecast** that is supposed
to warn us is wrong by up to 70 pp, because it models a demonstrably back-loaded burn as linear.

---

## §1 The instrument

| | |
|---|---|
| **Store** | `~/.claude/logs/account-utilization.jsonl` |
| **Writer** | `record_utilization()` — `bin/claude-accounts` (~line 2474), fresh-sweep path only, rate-limited `UTIL_MIN_INTERVAL_S = 300` |
| **Driver** | `com.claude.accounts-keepwarm.plist`, `StartInterval 180` (raised from 60 on 2026-08-11), loaded ✅ |
| **Span** | 2026-08-10T05:58Z → 2026-08-25T08:11Z · **12,525 rows**, 0 unparseable |
| **Fields** | `ts, acct, k, k_work, k_src, session_pct, weekly_pct, fable_pct, session_reset_at, weekly_reset_at, credits_on, credits_used, auth, stale` |
| **Env override** | `CC_UTIL_LOG` (honored by `pool-floor.sh` and the bats fixtures — a hermeticity requirement, not a convenience) |

**Coverage is good, and that is not assumed — it is measured.** Per account: 3,131–3,132 samples,
**median inter-sample gap 6.4 min**, p90 7.8 min, max 3.4 h, **8 gaps > 1 h, zero gaps > 6 h**. The
last sample before a genuine reset was stale by **≤ 2.26 h** in the worst case and ≤ 0.10 h in 7 of
8. So the "% at reset" figures below are lower bounds by at most a couple of hours of burn, and in
practice by minutes.

**Why the coverage is good is worth stating**: sampling is *not* a byproduct of agent activity. A
launchd job sweeps every 180 s regardless of whether anyone is working — which is exactly the
property this question needs, since the state that strands quota is the state where nobody is
working. An activity-driven recorder would be blind precisely when it mattered.

### Two instrument traps found while doing this

1. **`weekly_reset_at` jitters sub-second** across sweeps (`03:59:59.541…` vs `04:00:00.437…`).
   Detecting a window rollover by equality on that field mints **thousands of phantom rollovers**
   — the first cut of this analysis produced 20,000+ lines of nonsense before the tolerance was
   added. Compare with a tolerance (a genuine rollover moves the stamp by ~7 days).
2. **Rounding the reset stamp to bucket windows must round, not floor.** `03:59` floors to `03:00`
   and `04:00` floors to `04:00`, so the twins survive de-duplication and **N doubles silently**
   (16 "windows" that are really 8). This inflated the first empirical curve.

---

## §2 What the completed windows actually say

Eight genuine resets are observable (a genuine reset = `weekly_pct` drops to ≤2% and the window
had >10 samples; two 1-sample flaps at the very start of the ledger are warm-up artifacts, since
`weekly_pct` went *up* after them).

| acct | window closed (UTC) | % at reset | left on table | last-sample staleness |
|---|---|---:|---:|---:|
| next3 | 2026-08-11 12:00 | 100% | 0 pp | 0.02 h |
| next2 | 2026-08-15 11:00 | 92% | 8 pp | 0.02 h |
| next  | 2026-08-16 04:00 | 91% | 9 pp | 0.03 h |
| next4 | 2026-08-16 09:00 | 85% | 15 pp | 0.03 h |
| next3 | 2026-08-18 12:00 | 98% | 2 pp | 0.10 h |
| next2 | 2026-08-22 11:00 | 100% | 0 pp | 0.09 h |
| next  | 2026-08-23 04:00 | 99% | 1 pp | 2.26 h |
| next4 | 2026-08-23 09:00 | 92% | 8 pp | 0.02 h |

**mean 94.6% at reset · median 98% · min 85% · max 100% · mean 5.4 pp stranded · 7/8 ≥ 90%**

`weekly_pct` never decreased within a window (0/8), confirming it is a cumulative meter and that
"peak" and "value at reset" are the same number.

**This already has a reader.** `scripts/desk-strand-replay.py` prints a `N weekly resets observed
→ X pp stranded` block as part of scoring the desk routing lane. Its numbers agree with the
independent computation above exactly. It counts 9 rather than 8 because it admits the 2026-08-10
warm-up flap (`next3 … 58% used → 42pp`) that the classifier here rejects; on the 8 clean windows
the two agree to the percentage point. **There is no need to build a second reporter** — that
would be re-creating a renderer the repo already has.

---

## §3 The finding: the mid-week forecast is the broken part

Burn is **heavily back-loaded**, consistently, across every window with day-1 coverage:

| elapsed | linear model says | empirical median | observed range | shortfall vs linear |
|---:|---:|---:|---:|---:|
| 1 d | 14% | 8% | 1–12% | −7 pp |
| 2 d | 29% | 18% | 11–46% | −11 pp |
| 3 d | 43% | **21%** | 12–51% | **−22 pp** |
| 4 d | 57% | 30% | 13–65% | −27 pp |
| 5 d | 71% | 47% | 22–79% | −24 pp |
| 6 d | 86% | 68% | 52–93% | −17 pp |
| 7 d | 100% | 98% | 92–100% | −2 pp |

Two windows sat at **12%** and **17%** on day 3 and still closed at **98%** and **100%**. Typical
day-4→day-7 catch-up is **+37 to +86 pp**.

`bin/claude-accounts:wall_projection()` computes `burn_ratio = (weekly_pct/100) / elapsed_fraction`
and `proj_end = weekly_pct / elapsed_fraction`. Its docstring already identifies the *phase*
problem (USAGE_TELEMETRY_100P §1 — "a point-in-time percentage against a periodically RESETTING
counter is dominated by where you are in the window") and correctly abstains below 5% elapsed. But
dividing by elapsed fraction only corrects for phase **under an assumption of linear burn**, and
that assumption is false here. Backtesting the shipped projection against what actually happened:

| window | @ day 3 | burn_ratio | linear projection | ACTUAL final | error |
|---|---:|---:|---:|---:|---:|
| next3@08-18 | 12% | 0.28× | 28% | 98% | **−70 pp** |
| next2@08-22 | 17% | 0.40× | 40% | 100% | **−60 pp** |
| next4@08-23 | 25% | 0.58× | 58% | 92% | **−34 pp** |
| next@08-23 | 51% | 1.19× | 119% ⚠WALL | 99% | +20 pp |

Mean absolute error **46 pp at day 3**; still **35 pp at day 5**. The sign is systematic: it
under-projects whenever the account is mid-week and behind linear (3 of 4), and over-projects a
`⚠ WALL` that never arrived for the one that was ahead.

**Consequence, and it has already cost us once.** `docs/plans/USAGE_TELEMETRY_100P.md` opens with
*"on 2026-08-16 three of four windows sat at 1–3% with 6+ days left and every `pace to 100%` line
read BEHIND. **Under-use is the primary defect**"* — and made that the frozen scope of a 13-agent
research wave. Those three windows closed at **91%, 92%, 85%**. The premise was an artifact of the
linear model reading a normal back-loaded trajectory as under-use. The plan's own §1 diagnosed the
adjacent bug (window phase) and shipped the abstain floor for it; the shape bug survived because
correcting for phase *looks* like it corrects for both.

---

## §4 Live state at time of writing (2026-08-25 08:11 UTC)

Re-scored against the empirical envelope rather than the linear one:

| acct | resets | elapsed | now | linear says | history at this point → finals | verdict |
|---|---|---:|---:|---:|---|---|
| next3 | 08-25 11:59 | 6.8 d | 90% | 98% | 82, 97, 98, 98 → 92, 98, 99, 100 | closes in ~3.8 h; will strand ~8 pp |
| next | 08-30 03:59 | 2.2 d | 46% | 31% | 11, 14, 22, 47 → 92, 98, 99, 100 | ahead of every precedent |
| next2 | 08-29 10:59 | 2.9 d | 17% | 41% | 12, 17, 25, 51 → 92, 98, 99, 100 | 2/4 were ≤ this and finished 98, 100 |
| next4 | 08-30 09:00 | 2.0 d | 14% | 28% | 11, 14, 22, 46 → 92, 98, 99, 100 | 2/4 were ≤ this and finished 98, 100 |

The live readout's `next2 → ~41% by reset` and `next4 → ~50% by reset` are the broken projection
speaking. **No account is currently outside the envelope that historically finished at 92–100%.**
The one real cost in view is `next3`'s ~8 pp, and with 3.8 h left that is essentially fixed.

---

## §5 What is genuinely still dark

1. **Everything before 2026-08-10.** The ledger starts there; the pre-ledger state was
   single-slot-overwrite (`/tmp/claude-accounts-cache.json`, depth one). Whether transcripts can
   reconstruct any of it is being checked separately.
2. **N is small and the window is short.** 8 completed windows, 4 with day-1 coverage, spanning
   ~2 weeks. The empirical curve in §3 rests on **4 windows**. Read it as "the linear model is
   refuted", which 4 windows are ample for, **not** as "the S-curve is calibrated", which they are
   not. Re-derive after ≥2 more full cycles.
3. **Nothing alarms on the retrospective.** `desk-strand-replay.py` must be run by hand; no hook,
   no daemon, no close-time surface reads it. The number exists and nobody sees it.
4. **Cloud sessions** may or may not bill the same weekly meter (open, task #175). If they do not,
   `weekly_pct` understates true consumption and every figure here is a floor on utilization.

---

## §6 What follows from this

- **Do not act on a mid-week `burn X×` / `~N% by reset` reading.** It is not a forecast; at day 3
  it is wrong by a mean 46 pp. The retrospective at reset is the trustworthy number.
- **Do not re-open "we are under-utilizing" from a BEHIND pace line.** That premise has been
  falsified once already, at the cost of a 13-agent wave's framing.
- **The fix, if one is wanted**, is to replace the linear divisor in `wall_projection()` with the
  empirical trajectory — but not yet: 4 windows cannot calibrate a curve. The cheap correct move
  is to widen the abstain rule so the projection stays silent mid-week, where it is measurably
  uninformative, and speaks only in the last ~2 days where linear and empirical converge
  (day 6: −17 pp; day 7: −2 pp).

**Reproduce:** the analysis scripts are in this session's scratchpad; the one-command version of
the retrospective is `python3 scripts/desk-strand-replay.py`.

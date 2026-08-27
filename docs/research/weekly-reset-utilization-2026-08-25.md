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

**The prior plan got half of this, and the half it got is the interesting one.**
`docs/plans/USAGE_TELEMETRY_100P.md` is quotable for its frozen-scope line — *"three of four windows
sat at 1–3% with 6+ days left and every `pace to 100%` line read BEHIND. **Under-use is the primary
defect**"*. Read only that and you would conclude the plan was founded on a false premise. It was
not. Its **§1 retracts that reading inside the same document**, under a callout headed *"THE READING
ABOVE IS CORRECT AND ITS OBVIOUS INTERPRETATION IS FALSE"*: it names the previous complete windows
at 91/92/100/85%, concludes *"the fleet is near-saturating its weekly allowance, not idling"*, and
inverts the design target to *"land in the high-90s without any account hitting 100"*. Only the
scope header was never updated to match, so the two halves disagree and the **retracted** half is
the one that gets cited.

**What §1 got wrong is its remedy — that is what this doc adds.** §1 prescribes the fix as *"report
against the window's **elapsed fraction** … the primitive is a **burn ratio** `weekly_pct ÷
elapsed_fraction_of_window` (1.0 = on pace to finish at 100%)"* and asserts *"every account above
reads ~1.0 on that measure"*. That primitive shipped, as `wall_projection()`. But dividing by
elapsed fraction removes the *phase* error only if burn is **linear**, and it is not: the empirical
median reads **0.49×** at day 3, not ~1.0, and the backtest above errs by a mean 46 pp. The
2026-08-16 sample read ~1.0 because it was taken at day ~0–1, where linear and empirical have not
yet diverged (−7 pp at day 1); the gap opens from day 2 and peaks at day 4 (−27 pp). So the plan
correctly diagnosed phase-dominance, correctly built a phase correction, and the **shape** error
survived underneath it — precisely because a phase fix looks like it corrects for both.

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

1. 🚨 **SUPERSEDED BY §8.2 — read that instead.** This item concluded pre-2026-08-10 was
   unrecoverable. It is not: the series is reconstructable to 2026-07-24 at ±1.5 pp from transcript
   token records × the fitted exchange rate, plus 50 exact captured readings as anchors. The item is
   kept below because *how* it reached the wrong answer is the reusable part — it searched
   transcripts for limit **events** when what they actually carry is the **numerator**.

   ~~**Everything before 2026-08-10, and transcripts cannot recover it.**~~ The ledger starts there; the
   pre-ledger state was single-slot-overwrite (`/tmp/claude-accounts-cache.json`, depth one).
   Transcripts were checked as the only candidate pre-ledger source: across all four config roots
   (6,749 `*.jsonl`), the literal `Claude usage limit reached` appears in **6** files — and one of
   those six is *this session's own transcript*, contaminated by the grep that searched for it, so
   the real count is ~~**5**~~ **0 — every one of the 11 records is meta; see §8.2**. Transcripts do
   not record exhaustion events here at all. **ABSENT**, not EXISTS + INSUFFICIENT.
   ⚠️ The first cut of this probe used a broader regex (`weekly limit|rate_limit|resets at`) and
   matched **92%** of all transcripts — because that vocabulary is in `CLAUDE.md`, which is echoed
   into every transcript. A limit-telemetry probe over transcripts must match a limit *event*
   string, not limit *vocabulary*, or it measures the resident prompt.
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

  ✅ **SHIPPED 2026-08-27** (backlog `70ed289c10fb`). `MIN_ELAPSED_FRAC` **0.05 → 0.90** in
  `bin/claude-accounts`. The threshold is the tighter of the two readings this doc offers, not
  its "last ~2 days" phrasing: `docs/research/drain-telemetry-2026-08-25/axis-D-windows.md` §5
  scores the same function by phase decile — MAE 47.2 / 46.9 / 46.2 / 36.7 / **18.3** at phase
  0.1 → 0.9 — and `SYNTHESIS-design.md` §1.5 reconciled the two axes onto **phase 0.90**. Day 5
  (−24 pp) and day 6 (−17 pp) are still far worse than the 5.3 pp a constant predictor scores, so
  the last **~17 h**, not the last 2 days, is where this arithmetic earns a render.

  **The other half, which this section did not anticipate.** `pace_line` sourced its
  `⚠ WALL trajectory` glyph from the same projector's `proj >= 100`, so widening the floor alone
  would have silently dropped the warning for 90% of every window — and dropped it from the one
  estimator that was measurably wrong about it (the 08-23 `WALL` that never arrived is in §3's
  table). The flag moved to `wk_wall_traj`, the 48 h roll-aware nowcast's own verdict, which is
  reliable about the SIGN and worthless about the magnitude — so the sign ships and the number
  never does. `wk_wall_traj` is also stamped beside `wk_strand_pp` for machine consumers, since
  `wall_risk` now abstains for the first ~151 h of every window. Tests:
  `claude-accounts-burn-ratio.bats` (10 cases, each abstain paired with a late-phase control and
  the floor bracketed to 0.90 by a 16 h / 17 h pair) and `claude-accounts-strand.bats` RP-17/17b.

  **Not done, deliberately:** the shape-fitted divisor. Axis-D §5 built and backtested it
  leave-one-out and it **lost to linear by 37%** — it removes the bias and inflates the error —
  and the shape is a fossil of the operator's own end-of-window rush, so fitting to it goes wrong
  in the direction of complacency the moment the rush stops. Re-derive after ≥2 more full cycles
  (§5.2), not before.

**Reproduce:** the analysis scripts are in this session's scratchpad; the one-command version of
the retrospective is `python3 scripts/desk-strand-replay.py`.

---

## §7 Every other candidate source, ruled out

Asked so the answer is "we have the telemetry" rather than "we have *a* telemetry". Each verdict is
from execution or from reading the parsing code, not from a doc's claim.

| Source | Verdict | Evidence |
|---|---|---|
| `~/.claude/logs/account-utilization.jsonl` | **EXISTS + USABLE** — the answer | §1 |
| The OAuth `/api/oauth/usage` body | **EXISTS + INSUFFICIENT** (see §8.1 — this row was wrong when first written) | It carries **no history field of any kind** — every bucket is a single current `utilization` + `resets_at`. That is what settles it for this question, and it is unaffected by how much of the body we read. |
| …and we read only **5 of ~40** returned fields | **real gap, §8.1** | `pick()` (`bin/claude-accounts:846-853`) takes `percent` + `resets_at` from `limits[]`, plus `extra_usage.{is_enabled,used_credits}`. §8.1 names what is dropped and why two of them matter. |
| Native OpenTelemetry | **ABSENT, and would not help** | `CLAUDE_CODE_ENABLE_TELEMETRY` / any `OTEL_*` key is set in **none** of `~/.claude{,-secondary,-tertiary,-quaternary}/settings.json`, and none is in the live env. Independently: CC's OTel emits **token counts**, which are not limit %. Enabling it would not answer this question. |
| Transcripts — limit messages | **ABSENT** (§5.1 said "5 real events"; **corrected in §8.2 — the real count is 0**) | All 11 canonical-string records across 6 files are meta. |
| Transcripts — captured `--json` readings | **EXISTS + USABLE, sparse** — §8.2 | 50 pre-08-10 readings, 2026-07-25 → 08-09, all four accounts, median error **0 pp** against the ledger on overlap. |
| Transcripts — token records × exchange rate | **EXISTS + USABLE — recovers the pre-ledger series** — §8.2 | 715,076 usage records back to 2026-07-11; out-of-sample **R² 0.700, RMSE 1.54 pp**. |
| `/insights` (shipped in the binary) | **EXISTS + UNTRIED** | Local-history-derived so retro-capable, but approximate, and running it spends quota. Never run here. |
| claude.ai web Usage panel | **UNVERIFIED** | Not probed — the one place server-side history could exist. |
| `ccusage` / `claude-monitor` | **ABSENT** | Not installed by any path, and both are strictly weaker instruments. |
| `~/.claude/logs/auth-timeseries.jsonl` + 10 sibling stores | **ABSENT** | `weekly_pct` count = 0 in every one but the ledger. |

---

## §8 CORRECTION — a second pass refutes two claims above

An independent read-only sweep of the alternative sources (full findings:
`docs/research/weekly-reset-utilization-2026-08-25/C-alt-sources.md`) overturned two things §5 and
§7 asserted. Both are corrected in place above; the reasoning is kept here rather than deleted,
because in each case *how* the first pass got it wrong is the reusable part.

### §8.1 "The OAuth body is fully harvested" — WRONG, and wrong in a specific way

The claim rested on a true premise and a false inference: we persist everything `pick()` reads
(true), therefore we drop nothing (false). **`pick()` reads 5 fields; the body returns ~40.** A
verbatim HTTP-200 payload is already committed at
`docs/research/usage-telemetry-100p-2026-08-16/exchange-rate.md:66-98`, so this was checkable
without a network call — the first pass simply read the *parser* and inferred the *schema* from it,
which can only ever reproduce the parser's own blind spots.

Two dropped fields are load-bearing:

- **`seven_day_opus` / `seven_day_sonnet`** — per-model weekly sub-caps. `null` today, but the live
  2.1.220 binary carries both strings (8 and 10 occurrences), so the client knows about them. If a
  sub-cap is ever switched on it lands in a field nothing here reads, and **the first symptom is an
  unexplained refusal**.
- **`limits[].severity`** — the vendor's own escalation verdict. We re-derive urgency from `percent`
  + `resets_at` instead of reading what the server already decided.

Also dropped: `limit_dollars`/`used_dollars` (the fields that would *name the unit* and make an
absolute weekly allowance readable — `null` on Max today), `spend.exponent: 2` (the authoritative
statement that credits are cents), `extra_usage.{spend_limit_reached,disabled_reason}`, and
`nimbus_quill` — a bucket that is **not null**, live at zero, and rendered nowhere.

**The sharper structural finding.** The binary and `claude-accounts` read **disjoint halves** of the
same payload: string-scan of the 2.1.220 Mach-O gives `seven_day` 23, `five_hour` 18, `utilization`
32 — but **`weekly_all` 0**. The binary reads the top-level bucket map; our tool reads the `limits[]`
array. So a schema change on either side is invisible to the other, and `pick()` fails **silently to
`(None, None)`**, which `_excluded()` then treats as a correctly-excluded row. **A renamed `kind`
would read as a quiet outage, not an error.**

**But none of this changes §7's verdict for this question.** There is no history field anywhere in
the payload — no series, no sparkline, no previous-window value. Un-dropping all ~40 fields would
still not answer "what was it last Tuesday".

### §8.2 "Pre-2026-08-10 is dark" — WRONG; the series is reconstructable to 2026-07-24

§5.1 concluded transcripts were EXISTS + INSUFFICIENT because they carry limit *events*, not the
running percentage. That searched for the wrong thing. Three layers exist, and the third answers:

1. **Limit messages — genuinely ABSENT, and my count was too high.** §5.1 said "5 real events". The
   real number is **0**: all 11 canonical-string records across 6 files are meta — 9 are agents
   grepping for the string or quoting the prior wave's finding, and 2 are an alternation pipe inside
   a hook's regex (`…|usage limit reached|…`), where the `|` is regex syntax, not the epoch
   separator. My own self-contamination catch was right in kind and understated in degree. *The
   fleet has never hit a usage wall in the recorded corpus* — so the pre-ledger series has no
   censoring at 100% to model.
2. **Captured `claude-accounts --json` readings — sparse but EXACT.** Sessions that ran it left
   parsed rows in a `tool_result`. **50 pre-08-10 readings**, 2026-07-25 → 08-09, all four accounts,
   across 11 distinct days. Cross-validated on the 08-10→08-25 overlap: the 27 own-ts "echo" rows
   match the ledger **27/27 at 0 pp**. Density ~0.9 readings/account-day against the ledger's ~228 —
   enough to *anchor* a reconstruction, far too sparse to *be* one.
3. **Token records × the already-fitted exchange rate — this is the answer.** Every assistant record
   carries `message.usage`. **715,076 records over 2026-07-11 → 2026-08-25**, of which **382,477 are
   pre-08-10 carrying 389.7M output tokens**. Applying `exchange-rate.md`'s coefficients and testing
   on **2026-08-17 → 08-25 — a window disjoint from the 08-10→16 interval they were fitted on** —
   over 272 within-cycle intervals ≥3 h: **R² 0.700, RMSE 1.54 pp**, with a systematic **+10.5%**
   over-prediction (per-account: next 0.99, next3 1.08, next4 1.19, next2 1.22).

**What that buys:** hourly weekly-utilization for all four accounts back to **2026-07-24** solidly
(2026-07-11 with holes at 07-13→18 and 07-21→23), at ±1.5 pp — roughly 17 account-days per account
that no store on this box contains.

**Honest limits, and they are real.** (i) The reconstruction yields **Δpp within a cycle, not
absolute level** — pinning the origin needs a reset boundary or one direct anchor per cycle, and
layer 2 supplies those unevenly (next2 has only 5 pre-08-10 readings). (ii) Coefficients were fitted
on the 08-10→16 model mix; July carried more `claude-opus-4-8` (5,320 records) whose weight was
never fitted and is folded into "opus". (iii) Any claude.ai web/mobile usage on the same account is
invisible to transcripts and biases the reconstruction **low**, in exactly the period we cannot
check. So: use it to answer *"was July's utilization broadly like August's"*, not to publish a
per-window "% at reset" table for July alongside §2's measured one.

### §8.3 A correction to the prior wave's positive control

The 2026-08-16 research asserted "0 canonical hits, **positive control**: 25 `rate_limit_error`
records". The 0 replicates and is right; the control does not — those `rate_limit_error` records are
the CC binary's own error enum being dumped by agents reading its strings, i.e. meta too. **The
scan's proof that it could find anything was itself an artifact.** Use
`cache_read_input_tokens` (present in 6,497 of 6,749 transcripts) as the control instead.

# V-quota — adversarial verification of A3 (the quota axis)

**Verdict: SOUND-WITH-CORRECTIONS. A3's direction and its decision survive; every number in it does
not.** The load-bearing failure is that A3's token census has no `message.id` dedup — the exact bug
this repo ships a 🚨 warning about in `bin/cc-quota-price` and records as having corrupted three prior
derivations by 2.1–2.8×. Correcting it, adding the two accounts A3 never ran, running the within-model
variance control A3 never ran, and closing one of A3's own "unknowns", the penalty is **~3.2–3.7×,
not 2.5–2.8×** — i.e. A3 understated its own case by 30–45%, and did so through a metric (list
dollars) that this repo refuted by controlled experiment on 2026-08-16.

Written 2026-09-16, read-only. My scratch instruments: `v/dedup_ab.py`, `v/redo.py`, `v/pricelist.py`.

---

## What I attacked, and what happened

| A3 claim | Verdict |
|---|---|
| 1 — three buckets, no scoped 5h | **SPLIT.** First half CONFIRMED and strengthened. Second half ("Fable's 5h draw is unobservable") **REFUTED — I measured it.** |
| 2 — Fable is a sub-cap, exchange rate 0.5 | **SURVIVES.** The control can fail and doesn't. |
| 3 — vendor says same bucket, used faster | **SURVIVES.** Independently re-fetched; names Fable 5.1 by name. |
| 4 — a Fable weekly-pp buys ~40% of an Opus one (2.48×/2.79×) | **DIRECTION SURVIVES, MAGNITUDE AND PRECISION REFUTED.** True figure ~3.2–3.7×; the two "independent" accounts do not replicate once deduped. |
| 5 — structural 50% ceiling | **SURVIVES**, verified to primary sources. |
| 6 — break-even t ≤ 1/2.5 | **REFUTED as stated** — dimensionally inconsistent, and r is wrong. Correct break-even is harder for Fable. |

---

## (a) INSTRUMENT ERRORS

### I1 — No `message.id` dedup. Every number in A3's two tables is wrong, by a *model-dependent* factor.

Claude Code writes one transcript line **per content block** of a streamed assistant response: same
`message.id`, same `requestId`, identical complete `usage` object on each. `scan2.py` sums every
record. `bin/cc-quota-price` opens with this, verbatim:

> 🚨 **THE INVARIANT THIS FILE EXISTS TO HOLD — DEDUPE ON `message.id` OR BE WRONG BY 2.4x.**
> … Three independent derivations of this wave hit the bug; A1's own falsifier #6 NAMED the hazard
> and was not run, and the resulting price list was published 2.1-2.8x too high.

**MEASURED by me** (`v/dedup_ab.py`, next2 September corpus, 1,517 files — A3's exact corpus):

| model | records | repeats | output naive | output deduped | **inflation** | cache_read inflation |
|---|---|---|---|---|---|---|
| claude-opus-5 | 85,792 | 44,840 (52.3%) | 56,906,768 | 16,668,549 | **3.41×** | 1.99× |
| claude-fable-5-1 | 7,140 | 5,001 (70.0%) | 10,205,688 | 1,643,084 | **6.21×** | 3.27× |

Fleet-wide, the shipped tool agrees: `cc-quota-price --census --since all` → *"dedup: 360,115 of
662,462 record(s) were repeats (54.4%) — summing lines would have over-counted by 2.19x"*.

**The factor is not constant across models, so it does not cancel in a ratio.** Re-running A3's own
method with dedup, same account, same window, same filter (`v/redo.py next2`):

| next2 ratio (Opus per pp ÷ Fable per pp) | A3 published | **deduped** |
|---|---|---|
| output tokens | 3.25× | **5.86×** |
| fresh-in (in+cache_create) | 1.86× | **3.21×** |
| cache_read | 6.58× | **11.63×** |
| **list-$ (A3's headline)** | **2.48×** | **4.95×** |

### I2 — The headline metric is ~70% composed of the one class this repo proved costs ≈0 quota.

A3's decision statistic is `list-$ per weekly pp`. Decomposing it (deduped next2 arms):

```
OPUS  list$ $4478.28  ->  out $268.57 (6.0%)  cache_create $1090.32 (24.3%)  cache_read $3119.38 (69.7%)
FABLE list$  $139.71  ->  out  $14.16 (10.1%) cache_create  $104.82 (75.0%)  cache_read   $20.72 (14.8%)
```

`docs/plans/USAGE_TELEMETRY_100P.md` §2.2 measured cache_read at **96.95% of tokens / ≈0% of quota**,
and its 67-bucket model comparison puts **list-price dollars at R²=0.717 against the cache_read-free
shape at 0.827**, concluding *"the list-price model is refuted as a description of weekly-limit
burn."* §2.8 is the controlled experiment behind it: **31.7M cache_read tokens against 208 output
moved the weekly meter 1 point where list pricing demanded 4.62**, bounding cache_read at
≤0.018–0.049 pp/Mtok.

So A3's headline is ~70% (Opus side) driven by a class that does not spend the currency it claims to
price — and the two arms differ 2× in exposure to it (cache_read:output = 581 Opus vs 293 Fable).
Worse, A3 frames *"this REFUTES the model 'quota draw is proportional to list dollars'"* as its own
finding. That null was refuted a month ago in this repo, and **A6 of that same wave made the identical
error** (measuring at API list price, getting the opposite ranking) and was adjudicated REFUTED by the
lead. A3 re-committed it, and chose the refuted weighting as its headline.

### I3 — Sample-level integration against an INTEGER meter, which the repo's own tool refuses to do.

`cc-quota-price`, § *WHY BUCKETS AND NOT SAMPLES*: *"`weekly_pct` is an INTEGER percent, so the Delta
across one ~6-minute sample is 0 almost always and the regression would be fitting quantization
noise."* It buckets at **6h** and ABSTAINS below 12 moving buckets. A3 integrated at the ~6-minute
sample level. MEASURED consequences on A3's own next2 Fable arm:

- 538 of 635 Opus segments carry `dw=0`; the Fable arm's entire 17pp comes from **8 of 23 segments**.
- Segment `2026-09-05T03:22:46` attributes **3 weekly pp to 37 output tokens** (and 2.1M cache reads).
- **210,984 of the arm's 283,255 output tokens (75%) sit in segments with `dw=0`**, while all 17pp sit
  in segments holding the other 25%.
- Within-arm Spearman(Δweekly, output): Opus **+0.097** (n=634), Fable **−0.240** (n=23) — the
  *wrong sign* inside the very arm the estimate is built on.
- One tick-carrying Fable segment (`2026-09-06T23:25:09`, dw=1) sits on a row with `stale:true`,
  i.e. inherited last-good quota rather than a fresh reading. A3 never filtered `stale`.

**I ran `cc-quota-price` on this window and account. It ABSTAINS**: *"0 bucket(s) with a positive
Delta weekly_pct, below the floor of 12."* The repo's purpose-built converter declines to price this
data; A3 produced two-significant-figure answers from it with an instrument that has no dedup, no
bucketing, and no abstain.

### I4 — Claim 1's second half is a non-sequitur, and I refuted it by measurement.

*First half CONFIRMED and stronger than A3 knew.* A3 read only that `pick()` never asks for a scoped
session cap — a claim about the TOOL. But `limits_drift()` (`bin/claude-accounts:970-998`) logs any
limit kind outside `{session, weekly_all, weekly_scoped}`. `~/.claude/logs/claude-accounts.log` is
14,293 lines with **zero** drift lines, and the logger is demonstrably live (1,336 `429
poll-throttled` lines, 464 keychain lines). So the *payload* has never carried a scoped session cap.
The vendor article says nothing about a 5-hour Fable cap either (ABSENT on my fetch).

*Second half REFUTED.* "No scoped 5h bucket ⇒ Fable's 5h draw is unobservable" does not follow: the
**unscoped** session meter moves on all usage including Fable, so a Fable-only interval's Δsession is
directly observable by the same integration. This is one of A3's four stated unknowns, closed for free
from data already on disk — see § What survives, item 3.

### I5 — attacks I ran that FAILED (A3 is clean here)

- **Timezone.** Transcript timestamps are UTC-suffixed, 3,584/3,584 sampled (`2026-09-16T21:18:03.922Z`).
  A3's `fromisoformat(h+':00+00:00')` join is sound. So is mine.
- **Model-id completeness.** September fleet census: `claude-opus-5`, `claude-fable-5-1`,
  `<synthetic>` (0 tokens), `claude-sonnet-5`, `claude-opus-4-8/4-7`, `claude-haiku-4-5`. Exactly one
  id per model under test; the single-model filter is sound and conservative.
- **Contamination of the Fable arm.** I expected hidden Opus inside "Fable-only" intervals (their mean
  live-pane count is 7.29 vs Opus's 4.53). The fable meter is a tracer that settles it: the arm's
  Δweekly=17 against 0.5·Δfable=15.5 predicted, so non-Fable draw is ~1.5pp (~9%) — inside rounding.
  **This attack fails; A3's arm purity holds.**

## (b) POPULATION / (d) ONE-ARMED EVIDENCE

### P1 — No within-model variance control. The claimed replication is noise.

A3 read "2.48× on next2 and 2.79× on next3, two independent accounts, same magnitude" as
corroboration. I ran the arm that could refute it: **resample the Opus-only segments down to the Fable
arm's n and read the estimator's own spread.** next2, 6,000 draws:

| control | list-$/pp p5 / p50 / p95 | spread | out/pp spread |
|---|---|---|---|
| random resample, n=23 | 22.1 / 40.8 / 113.0 | **5.12×** | 6.38× |
| contiguous block, n=23 | 20.5 / 39.2 / 108.7 | **5.29×** | 10.76× |

Two draws landing within 12% of each other inside a 5× interval is not replication. And **deduped,
those same two accounts give 4.95× and 3.35×** — they do not agree. The apparent agreement was an
artifact of the shared undeduped extractor, not evidence.

### P2 — Two of the four available arms were never run, and they break the range.

next4 and next both carry Fable usage (13% and 7% on today's readout; max-ever **100%** on both).
Deduped, all four accounts, A3's own output-token axis:

| account | out ratio | fresh-in | cache_read | list-$ |
|---|---|---|---|---|
| next2 | **5.86×** | 3.21× | 11.63× | 4.95× |
| next3 | **2.00×** | 2.51× | 4.44× | 3.35× |
| next4 | **3.17×** | 6.67× | 8.64× | 7.01× |
| next | **1.17×** | 4.36× | 13.11× | 4.04× |

A **5.0× spread**, with `next` showing essentially no per-token penalty at all on the class that
carries most of the quota. The cross-account spread matches the resampling spread exactly — the four
accounts are four draws the estimator cannot resolve at this sample size.

### P3 — A3's invariant control CAN fail, and it doesn't. This one survives.

`fable_pct > 2·weekly_pct + 2` is arithmetically impossible once weekly ≥ 49, so "0 in 28,572" could
have been a control that cannot fire. It isn't: **17,991 of 28,576 rows (63.0%) have weekly < 49, and
7,940 of those (27.8% of all rows) also carry fable > 0.** Zero violations in a population where
violations were expressible. 618 rows sit hard against the 0.5 boundary (`w ≤ 0.6f+1`), which is
positive evidence for the coupling rather than mere consistency. **Claim 2 stands.**

## (c) STALE PREMISE — nothing found; claims 3 and 5 verified to primary sources

- **Vendor article re-fetched independently today.** All four A3 quotes confirmed verbatim, including
  *"They draw from your plan's regular weekly usage limits and use them faster than other Claude
  models."* It **names Fable 5.1 explicitly** (*"Fable 5 requires version 2.1.170 or later and Fable
  5.1 requires version 2.1.255 or later"*), so the plan-inclusion premise is current for the model
  under test and not inherited from Fable 5. Last updated "over 2 weeks ago".
- **The credits escape hatch is closed on this fleet.** The article's *"keep using Fable models with
  usage credits"* is unavailable: `~/.claude/accounts.json` → `spend.usage_credits_authorized: false`
  and `frontier.credits_authorized: false`. So claim 5's ceiling genuinely binds.
- **Router line verified.** `bin/claude-accounts:3481` reads
  `f_eff = min(F["coupling"] * max(0.0, 1 - r["fable_pct"] / 100.0), w_rem)` — A3 dropped the
  `max(0.0, …)` in transcription; immaterial. `frontier.coupling = 0.5` with the quoted comment,
  confirmed.
- **Max-fable observations verified**: next 100%@weekly 95% · next4 100%@89% · next3 78%@91% ·
  next2 76%@99%. Matches A3 exactly.

## (e) SCOPE OVERREACH — claim 6 is dimensionally inconsistent

A3 takes **r from the list-$ blend** (a four-class, dollar-weighted number) and **t from output tokens
only** (one class), then divides them as if they shared units. Under this repo's own model quota is
output (51–57%) + cache_creation (42–48%), so a break-even needs both classes; the sweep's median
output-per-cell figures carry no cache_creation at all. Separately, the 1.34× high→medium saving comes
from a **single-file anchored review task** whose output spans 18× across efforts (6,449 → 118,365);
nothing establishes that an agentic session, where output is bounded by the task rather than by the
essay, scales the same way. A3 correctly flags the scope limit on the *recall* numbers and does not
flag it on the *token* numbers it actually uses for the break-even.

**The corrected break-even is harder for Fable, not softer**: at r ≈ 3.6, Fable @medium must finish a
task in **3.6× fewer tokens** than Opus @high, not 2.5×.

---

## What survives — and it survives harder than A3 argued

Three independent denominators, all deduped, all with a control:

**1. Weekly meter, pooled over all four accounts.** Fable **31,079** output tokens per weekly pp vs
Opus **115,150** → **3.71×**. Control (Opus resampled to n=59, 6,000 draws): p5 68,972 / p50 117,519 /
p95 228,643, spread 3.32×; **P(control ≤ Fable) = 0.0000.**

**2. The repo's OWN established Opus-5 price list applied to both arms** (§2.1: ~360K output/pp and
~3.4M cache_creation/pp marginal; 261K / 3.19M realised average). **The positive control passes**: the
Opus arms predict 313.1pp (marginal) / 372.4pp (average) against **384pp observed** → obs/pred
**1.23 / 1.03**, and the marginal arm's 1.23 excess lands squarely on the ~28% of weekly consumption
the plan documents as leaving no local transcript. Applied out-of-sample to the Fable arms: predicted
5.63 / 6.70pp, **observed 25pp** → obs/pred **4.44 / 3.73**.

| | next2 | next3 | next4 | next | pooled |
|---|---|---|---|---|---|
| Fable obs/pred (marginal) | 5.18 | 2.65 | 4.22 | 3.07 | **4.44** |
| Opus obs/pred (marginal) | 1.35 | 1.19 | 0.93 | 1.40 | **1.23** |

Four for four, non-overlapping. And the pooled cache_creation:output mix is near-identical (Fable
15.0, Opus 14.6), so this is not a mix artifact on the two classes that carry the quota. *Caveat
stated plainly: the price list was fitted on this fleet's Opus corpus, so the Opus row is an
instrument check rather than independent evidence — the Fable row is the genuinely out-of-sample one.*

**3. The 5-hour meter — the bucket A3 called unobservable.** Fable **7,449** output tokens per session
pp vs Opus **24,221** → **3.25×**; control p5 16,425 / p50 24,586 / p95 37,505, **P(control ≤ Fable) =
0.0000**. This meter ticked **1,730pp against weekly's 384pp**, so it is ~4.5× less quantization-
starved and its control spread is 2.28× vs weekly's 3.32×. **The 5-hour bucket weights Fable too, at
essentially the same rate as the weekly one.** That closes A3's unknown #3 and removes any hope that
Fable is cheap against the session window.

**Converging estimate: r ≈ 3.2–3.7×.** Three denominators, four accounts, a passing positive control
and a passing negative control. A3's conclusion is right. Its number is 30–45% too low, and it is too
low *specifically because* the missing dedup inflated Fable's output by 6.21× against Opus's 3.41×.

### What neither of us closed

- r remains an inference from observational aggregates. The price-list arm is the strongest because it
  has a positive control, but it inherits that list's own 1.38× marginal-vs-average spread.
- Whether `fable_pct` and `weekly_pct` share an underlying usage unit. If the Fable sub-cap is
  denominated in *Fable-priced* dollars rather than usage-normalised units, the 0.5 conversion is
  wrong and r moves. A3 named this; I could not close it either. Only the controlled A/B can.
- ~28% of weekly consumption leaves no local transcript (vendor-documented, plan-measured). I have no
  arm showing that 28% is equal across the two models.


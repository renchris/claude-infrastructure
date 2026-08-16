---
axis: skeptic-exchange-rate — adversarial review of A1 (the quota exchange rate)
target: docs/research/usage-telemetry-100p-2026-08-16/exchange-rate.md
date: 2026-08-16
verdict: SURVIVES-NARROWED (shape) / REFUTED (every published price)
one_line: >
  The regression's SHAPE reproduces exactly — I get n=265, R²=0.823, cache-read pinned at zero —
  but the extractor sums one API request three times, so every token-per-pp number in the headline
  is inflated 2.2–2.8×: 1 weekly pp buys ~360K Opus-5 output tokens, not 780K.
---

## Verdict

**SURVIVES-NARROWED on the load-bearing claim as literally worded** (weekly-% is near-linear in
output + cache-creation with no separately-identifiable cache-read weight; NNLS over 265 ≥2h
intervals; R²≈0.82). I reproduced that from scratch on an independent extraction: **n=265, R²=0.823,
`op_cr` = 0.0000 at every anchor spacing I tried.** The structure is real.

**REFUTED on the headline — i.e. on every number the operator would act on.** The token side of the
join triple-counts. Claude Code writes **one transcript line per content block** of a streamed
assistant message; all blocks carry the *same* `message.id`, the *same* `requestId`, and the
*identical, complete* `usage` object. Summing per line counts one billing event 2–3 times, and the
inflation is **not uniform across token classes** (input 3.01×, output 2.36×, cache-creation 2.72×,
cache-read 2.07×), so it distorts the relative weights as well as the level.

This is not a new hazard I invented — it is the artifact's **own falsifier #6**, named and not run:
*"If a bug in the extractor … inflated one token class systematically, BOTH fits would move together
and the 'independent' corroboration evaporates."* It fires.

| published | corrected | error |
|---|---|---|
| 1 weekly pp = **780K** Opus-5 output tokens | **~360K** (320–410K across anchor spacings) | **2.2× too high** |
| 1 weekly pp = **9.5M** cache-creation tokens | **~3.4M** | **2.8× too high** |
| a full account-week = **78M** output tokens | **33–41M** at the pure-output margin | **2.1× too high** |
| 374 pp headroom = **292M** output tokens | **~135M** at the margin; **~45M** at the fleet's realised mix | **2.2×–6.5× too high** |
| Fable output = **1.31×** an Opus output token | **3.14×** (and still unidentified, bootstrap p5 = 0) | **inverted** |
| a weekly allowance = **7.2–9.8** five-hour allowances (22–29% duty cycle) | **~4.0** (12% duty cycle) | **~2× too loose** |
| **$73.50** API-list-equivalent per pp (~158× the subscriptions) | **~$35/pp** (~75×) | **2.1× too high** |
| cache-read is **84%** of fleet token volume | **97.1%** | understated — R1's premise gets *stronger* |

---

## 1. The bug, shown in raw bytes

```
$ # three transcript lines, one message.id, one requestId, one API call
/Users/chrisren/.claude/projects/-Users-chrisren-Development--worktrees-wt-bc50117059ac/
  8a41189c-5761-41ec-b027-fa1781a83d7b.jsonl
```

| uuid | ts | content block | usage.output | usage.cc | usage.cr | requestId |
|---|---|---|---|---|---|---|
| 9e2383c3… | 07:35:19.785Z | `thinking` | 1571 | 2270 | 175088 | `req_011CdtgWx7cuE6AJxuw9FJfT` |
| 14e58bce… | 07:35:21.166Z | `text` | 1571 | 2270 | 175088 | `req_011CdtgWx7cuE6AJxuw9FJfT` |
| ec972b39… | 07:35:22.357Z | `tool_use` | 1571 | 2270 | 175088 | `req_011CdtgWx7cuE6AJxuw9FJfT` |

Summing the lines charges 4,713 output / 6,810 cache-creation / 525,264 cache-read tokens for a
request that emitted 1,571 / 2,270 / 175,088.

**Population-level, over the exact same window the artifact joined** (1,290 files, 1.88 GB,
mtime ≥ 2026-08-09, realpath-deduped across all four `projects/` roots — 100% of the joinable
window, not a sample):

```
lines carrying message.usage.output_tokens : 142,267      (artifact: 140,928 — reproduces; file still growing)
distinct (file, requestId) billing events  :  64,704
distinct (file, message.id) billing events :  64,706
```

| counter | summed per LINE | deduped per EVENT | inflation |
|---|---|---|---|
| input | 2.4M | 0.8M | **3.012×** |
| output | 142.3M | 60.2M | **2.362×** |
| cache_creation | 1,132.9M | 416.0M | **2.723×** |
| cache_read | 31,352.6M | 15,149.8M | **2.070×** |

**Positive control on the dedupe key.** Two independent identifiers — `requestId` and `message.id` —
produce 64,704 vs 64,706 events and agree on all four counters to **< 0.5%**. So the duplication is
within-request block replication, not resume-forking or my keying choice. (81 of 142,267 lines carry
no `requestId`; they fall back to `message.id`.)

---

## 2. Reproduction of the fit

I rebuilt the whole pipeline independently: same account→config-dir map from `accounts.json`
(verified: `next`→`~/.claude-next`, whose `projects/` realpaths to `~/.claude/projects`;
`next2`→`~/.claude-secondary`, `next3`→`~/.claude-tertiary`, `next4`→`~/.claude-quaternary` — the
artifact's §2 mapping is **correct**), same 10-min bucketing, same drop-on-real-drop cycle
segmentation, same `scipy.optimize.nnls` on 8 columns, same ≥2h greedy anchoring.

One thing the artifact does not state but its numbers require: **rows with `stale: true` must be
dropped.** 633 of 5,021 log rows (12.6%) are stale — `hooks`-side definition at
`bin/claude-accounts:2303`, `"stale": bool(r.get("stale_quota") or r.get("error"))`, i.e. a
carried-forward last-good reading, not a live one. Keeping them gives n=277 and destroys stability
(`op_out` swings 0.42→1.90 across anchor spacings, `op_in` blows up to 35–157 pp/Mtok). Dropping them
gives **n = 265 exactly**, matching the artifact — so the artifact evidently did drop them, and
should say so, because the result is not robust to the alternative.

**Agent's exact recipe (stale dropped, ≥2h anchors, NNLS, 8 columns):**

| extraction | n | R² | `op_out` | 1 pp buys | `op_cc` | 1 pp buys | `op_cr` | `fb_out` | out:cc |
|---|---|---|---|---|---|---|---|---|---|
| **artifact, published** | 265 | 0.816 | 1.2823 | 780K | 0.1054 | 9.5M | 0.0000 | 1.6804 | 12.2 |
| my repro, **line-summed** (its method) | 265 | **0.828** | **1.1431** | **875K** | **0.1080** | **9.26M** | 0.0000 | 1.439 | 10.6 |
| my repro, **event-deduped** (correct) | 265 | 0.823 | **2.4610** | **406K** | **0.2952** | **3.39M** | 0.0000 | 7.736 | 8.3 |

Row 2 reproduces the artifact to within 11% on `op_out` and 2% on `op_cc` — **its arithmetic is
sound; its input is not.**

**Stability of the corrected number** (this is what makes the correction credible rather than merely
different):

```
dedup minh=1h  n=506  R2=0.785  op_out=2.765 -> 1pp=362K   op_cr=0.0000
dedup minh=2h  n=265  R2=0.823  op_out=2.461 -> 1pp=406K   op_cr=0.0000
dedup minh=3h  n=184  R2=0.871  op_out=3.071 -> 1pp=326K   op_cr=0.0000
dedup minh=4h  n=135  R2=0.852  op_out=2.775 -> 1pp=360K   op_cr=0.0000
dedup minh=6h  n= 93  R2=0.853  op_out=2.601 -> 1pp=384K   op_cr=0.0000
dedup minh=8h  n= 69  R2=0.836  op_out=3.111 -> 1pp=321K   op_cr=0.0000
```

Bootstrap (600 resamples, corrected data, minh=2): `op_out` p5 1.329 / p50 2.219 / p95 2.764
(zero in 0%); `op_cc` p5 0.266 / p50 0.301 / p95 0.415 (zero in 0%). **The published 1.2823 sits
below the corrected p5.**

**The corrected fit is also self-consistent where the published one was not.** The artifact offers
the 5-hour bucket as corroboration on the out:cc ratio (9.0 vs 12.2 — 35% apart). Re-run on the same
stale-dropped basis:

```
naive  5h out:cc = 12.7   weekly out:cc = 10.6      (20% apart)
dedup  5h out:cc =  9.4   weekly out:cc =  8.3      (13% apart)
```

Deduping *improves* the agreement between two buckets with different denominators and different
reset cadences. That is independent evidence that the dedupe is the right operation, not just a
different one.

---

## 3. Denominators, coverage, and imputation

| check | result |
|---|---|
| Utilization series: 5,013 rows / 1,254 sweeps / median gap 6.3 min / p99 15.2 / max 205.5 / 0 gaps > 6h | **REPRODUCES.** I read 5,021 rows / 1,256 sweeps (file grew 2 sweeps since), median 6.27, p90 8.23, p99 14.96, max 205.5, 5 gaps > 60 min, **0 > 6h**. Finding #4 and #5 stand. |
| Corpus: 1,283 files / 1.77 GB / 140,928 records | **REPRODUCES** (1,290 / 1.88 GB / 142,267). Coverage honestly stated as 100% of the joinable window, ~26% of the 7.3 GB fleet corpus by bytes. Good discipline. |
| "265 intervals / 296 pp" | Interval count reproduces exactly. **My Σy = 337 pp**, not 296 — a 14% discrepancy I could not close; the artifact does not specify whether cross-cycle or zero-Δ intervals are kept. Minor, but it means Σy is not a reproducible denominator as published. |
| **y is 52% zeros.** | `weekly_pct` is an **int** in all 5,021 rows (verified). 145 of 277 unfiltered intervals have Δ = 0 pp. The regression's entire signal lives in ~130 non-zero integer observations. The artifact's finding #16 names the 1-pp resolution floor but never states that half the design rows carry no signal. |
| Imputed constants presented as measurements | **None found.** The abstentions table is genuinely well-disciplined — `limit_dollars` reported NULL, `op_in` reported unidentified rather than zero, cache-read reported as a bound. This artifact does *not* repeat the CONTEXT_ECONOMY_V2 imputation failure. Credit where due. |
| Citation `bin/claude-accounts:1141` for "used_credits = cents (17691 → $176.91)" | **WRONG LINE.** :1141 is `row["error"] = ("poll throttled ↻ …")`. The cents fact lives at `bin/claude-accounts:827` and in `accounts.json` `_spend`. The fact is real; the pointer is not. |

---

## 4. Is the cache-read zero identified? (the one result the artifact calls decision-changing)

The artifact grades this INFERRED and states the identification failure honestly. Three additions
that narrow it further:

1. **The unconstrained estimate is NEGATIVE.** Dropping NNLS's non-negativity on the corrected data:
   `op_cr = −0.0032`, `fb_cr = −0.0100`. Ridge at λ ∈ {0.01, 0.1, 1.0} likewise gives
   −0.011 / −0.012 / −0.008. A coefficient whose unconstrained sign is negative is not *measured at
   zero* — it is pinned to a **boundary vertex** by the constraint. `cond(X) = 62,433`,
   `corr(op_out, op_cr) = 0.906`.
2. **Cache-read alone explains R² = 0.353** of weekly-pp variance (output alone 0.510, cache-creation
   alone 0.313). It is far from uninformative; it simply loses a collinear race.
3. **The artifact endorses two models that disagree about the dominant cost class.** Its finding #15
   calls API-list-dollar weighting "the best single-parameter explanation" (R² 0.764). Under those
   very weights, on the fleet's *realised, deduped* mix:

   | class | Mtok | list $/Mtok | $ | share |
   |---|---|---|---|---|
   | opus output | 41.7 | 25.00 | 1,042 | 12.4% |
   | opus cache-creation | 292.1 | 6.25 | 1,826 | 21.6% |
   | **opus cache-read** | **11,144** | **0.50** | **5,572** | **66.0%** |

   So finding #8 says cache-read costs nothing and finding #15 says it is two-thirds of the bill, and
   the R² gap between them is 0.06 for 7 extra parameters. **The artifact's own #15 refutes its own
   #8's operational reading.** Its falsifier #3 (the cache-read-heavy / output-poor probe) is
   therefore not optional garnish — it is the only thing that decides R1.

**Mechanism the axis missed, which makes #15 worse still.** 85.1% of deduped cache-creation is
`ephemeral_1h_input_tokens` (354.9M vs 61.9M `ephemeral_5m`). The 1-hour cache write is list-priced
at **2× base input ($10/Mtok Opus)**, not the 1.25× ($6.25) the artifact used flat. Volume-weighted
correct price: **$9.44/Mtok** — a 1.51× understatement of the cache-creation dollar column inside the
model it declares best. The `$73.50/pp` figure is wrong twice over (inflated tokens × mispriced
cache-creation).

---

## 5. Per-recommendation verdicts

Operator frame applied: quality is never traded for tokens; under-use of the weekly allowance is
itself a defect; telemetry must not become bloat.

| # | Verdict | Why |
|---|---|---|
| **R1** publish "cache-read ~free, output 1×, cache-creation 1/12×" as an operating fact | **NARROW** | The *direction* is quality-positive (it authorises more context) so it is not a REJECT under the operator rule. But it may not ship as a measured fact: the coefficient is a boundary solution whose unconstrained sign is negative, and the artifact's own #15 implies cache-read is 66% of the bill. Ship it as a **bound with the identification caveat**, and fix the magnitudes: cache-creation is **1/8** of an output token (not 1/12), 1 pp = 3.4M cache-creation (not 9.5M), and cache-read's volume share is **97.1%** of realised tokens (not 84.1%) — the premise is stronger than published, the price is not established. |
| **R2** spend the standing headroom; route waves as dispatched sessions | **KEEP — renumber** | The routing decision is right under the use-it-or-lose-it rule independent of the exchange rate, and costs no quality. The quantity is wrong: 374 pp ≈ **135M** output tokens at the pure-output margin, ≈ **45M** at the fleet's realised mix — not 292M. Do not put 292M or "$27.5K" in a close. |
| **R3** land `bin/cc-quota-rate` (nightly re-fit → jsonl) | **NARROW — blocked on the extractor** | As specified it would append the triple-counted price list nightly forever, converting a one-off error into a permanent, authoritative-looking store — the worst outcome available here. Mandatory preconditions: (a) dedupe by `(file, requestId)` with `message.id` fallback, taking the **max** per counter; (b) drop `stale:true` rows; (c) emit `n`, R², bootstrap p5/p95 and `cond(X)` in every row, so a future reader can see the identification failure without re-deriving it. With those, KEEP — 300 B/day is not bloat, and the store is derived from data already on disk. |
| **R4** widen `record_utilization` to the full bucket map | **KEEP** | Reads more of a payload already fetched — no new call, no quota, no token cost, no quality cost. Verified the premise myself: `grep -c 'five_hour\|seven_day\|nimbus_quill\|limit_dollars\|amount_minor' bin/claude-accounts` → **0**; positive control `extra_usage` → **2**, `used_credits` → **6**; `pick()` at `:801-809` walks `limits[]` only. Narrow one clause: "removes the quantisation floor *if* the float ever carries decimals" rests on 4 observations that were all integral — keep it conditional, as written. |
| **R5** record which model each account was running per sweep | **REJECT AS SPECIFIED / NARROW** | Its stated effect is false. The named bias is **out-of-band usage** (claude.ai web, mobile) that never reaches a transcript; a locally-recorded model stamp cannot see that either, so it closes nothing. The instrument that *would* close it is a **residual monitor**: per interval, compare observed Δpp against the token-predicted Δpp and log the residual — a positive residual with zero transcript tokens is out-of-band usage, directly observable. My cycle scan already shows one candidate (`next2` cycle 2: **1 pp over 23.6 h with 0.00M attributed output tokens**). Re-specify R5 as the residual monitor; the model stamp is cheap and harmless but must not be sold as the fix. |
| **R6** never quote $73.50/pp as internal spend | **KEEP — strengthen** | Correct guardrail, and needed more than the artifact realises: the figure is inflated ~2.1× by the extractor *and* under-prices 1-hour cache-creation by 1.51×. Corrected API-list equivalent ≈ **$35/pp**, ≈ $3.5K/account-week, ≈ **~75×** the subscriptions, not 158×. Quote none of these as spend. |
| **R7** re-run after ≥2 more weekly cycles | **KEEP** | Right, and now urgent: the published coefficients must be *replaced*, not merely tightened. |
| **(implied)** run falsifiers #2 and #3 as live probes | **PROMOTE to a recommendation** | ~3 pp of one quiet account's weekly quota is the entire cost, against a standing headroom of 374 pp. Probe #3 (large cached context replayed, near-zero output) is the only thing that decides whether R1 is a fact or a hypothesis. Zero quality risk; the artifact buried it at #7 of 8. |

---

## 6. What survives my attack

1. **The unit is monetary.** `limit_dollars` / `used_dollars` / `remaining_dollars` on both buckets,
   `spend.used = {amount_minor, currency:"USD", exponent:2}`. I did not re-issue the authed GET
   (network + credentials), so this is **unverified by me** — but it is internally consistent with
   everything I *could* check in the source, and the "withheld on Max" positive control (utilization
   and `resets_at` populated in the same object) is a properly constructed absence assertion.
2. **The time-series exists and is dense enough.** Reproduced to the digit. The lead's feasibility
   gate is genuinely refuted, and the reason is exactly as stated — the file is named
   `account-utilization.jsonl`, so a `*usage*`/`*quota*` glob misses it. This is the single most
   valuable thing in the artifact and it stands.
3. **`claude-accounts` discards the entire bucket map.** Reproduced: grep 0, positive controls 2 and 6.
4. **No rate-limit headers persisted.** Reproduced on a fresh 60-file sample: 1 hit (a transcript
   quoting the string — i.e. this investigation's own), positive control `cache_read_input_tokens`
   **60/60**.
5. **The regression's shape.** Near-linear in output + cache-creation; R² ≈ 0.82; cache-read carries
   no separately-identifiable weight; NNLS non-negativity justified as a physical constraint. All of
   it survives the corrected extraction — and the corrected extraction makes the weekly/5-hour
   corroboration *better*, not worse.
6. **The abstentions table.** `limit_dollars` NULL, `op_in` unidentified, cache-read a bound not a
   point, out-of-band usage named as a directional bias. This is the discipline the house rules ask
   for, and the artifact met it. The failure here was not imputation — it was one unexamined
   assumption about a file format, which the artifact itself listed as its own falsifier and did not
   spend twenty minutes checking.

---

## 7. What would falsify *me*

- **The duplicate lines are separately billed.** If Anthropic bills per streamed content block rather
  than per request, line-summing is right and dedupe is wrong. Refutable in one call: issue a request
  known to produce N blocks and read the weekly Δ, or find any transcript where blocks of one
  `requestId` carry *different* cache_read values (I found none among 37,710 multi-line ids with
  identical usage tuples; the 7,514 that differ do so only on `output_tokens`, monotonically, which
  is the in-progress count — consistent with max-per-event, not with per-block billing).
- **Σy = 296 is recoverable.** If the artifact's interval construction legitimately yields 296 pp
  where mine yields 337, its coefficients shift ~14% and my repro was measuring a slightly different
  estimand. It would not touch the 2.2× dedupe correction, which is independent of the y side.
- **The 5-hour intervals.** I could not reconstruct the artifact's 128-interval 5-hour set (mine has
  1,532), so my refutation of finding #13 (weekly = ~4.0 five-hour allowances, not 7.2–9.8) rests on
  my construction. Mine is at least internally consistent (out ratio 4.21, cc ratio 3.72 — 13%
  apart), where the published pair is 7.23 vs 9.82 — 36% apart for two estimates of one scalar.

---

## Reproduction commands

All work is read-only; scripts live in the session scratchpad, not the repo.

```bash
# 1. utilization series
python3 -c "…"                    # 5,021 rows / 1,256 sweeps / median gap 6.27 min / 0 gaps > 6h

# 2. extraction (1,290 files, 1.88 GB, mtime >= 2026-08-09, realpath-deduped)
#    -> 142,267 lines, 64,704 (file,requestId) events, 64,706 (file,message.id) events

# 3. the bug, in raw bytes
python3 - <<'EOF'   # print every line sharing one message.id
EOF
#    -> 3 lines, 1 requestId, identical usage {out 1571, cc 2270, cr 175088}

# 4. the fit, both extractions, agent's exact recipe
#    naive : n=265 R2=0.828 op_out=1.1431 (780K published / 875K mine)
#    dedup : n=265 R2=0.823 op_out=2.4610 (406K)  <- the correction

# 5. identifiability
#    unconstrained OLS op_cr = -0.0032 ; ridge -0.008..-0.012 ; cond(X)=62,433 ; corr=0.906

# 6. cache-creation ephemeral split
#    ephemeral_1h 354.9M (85.1%) @ $10/Mtok ; ephemeral_5m 61.9M (14.9%) @ $6.25/Mtok
```

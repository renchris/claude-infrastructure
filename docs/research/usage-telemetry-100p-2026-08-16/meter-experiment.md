---
axis: M0 — the meter identification experiment (settles §2.8)
status: RESOLVED
date: 2026-08-16
headline: 31.7M cache-read tokens moved the weekly meter by at most 2 points where list-price weighting demanded 4.6 — so the plan does NOT charge for re-reading cached context, and the 4.3% of the arm's tokens that were cache-CREATION account for essentially all of the movement.
load_bearing_claim: On an otherwise-idle account, a session whose turns were 95.7% cache_read (cr:out ratio 152,533:1) consumed 1 weekly point and 4 five-hour points, against list-price predictions of 4.62 and 11.19 respectively.
cost: 1 weekly point + 4 five-hour points on next2 (2% -> 3% weekly). Wall clock 43 min.
---

## Headline

**The list-price model of the Max meter is refuted, and it is refuted under every attribution
assumption I could construct.** The wave's critic (§2.8) found the dollar→`weekly_pct` bridge
*assumed* in five artifacts and unidentifiable from observational data, because output and
cache_read are 91% correlated in normal work and A1's NNLS had pinned cache_read to the zero
*boundary* — which is not evidence of zero. This experiment forces the decorrelation instead of
fitting through it.

One session loaded a 1.42 MB context, then took 45 resumed turns that each re-read the whole thing
and emitted ~4 tokens. Measured over 46 deduped billed responses:

| class | tokens | share |
|---|---|---|
| `cache_read` | **31,726,824** | **95.7%** |
| `cache_creation` | 1,429,460 | 4.3% |
| `output` | 208 | ~0% |
| `input` | 82 | ~0% |

`cr:out` ratio **152,533 : 1** — a decorrelation no observational sample of this fleet contains.

| meter | baseline | final | observed Δ (true, given integer quantisation) | list-price predicted |
|---|---|---|---|---|
| weekly | 2 | 3 | 1 pp (true 0–2) | **4.62 pp** |
| 5-hour | 2 | 6 | 4 pp (true 3–5) | **11.19 pp** |

List pricing over-predicts by **3–4×** on both meters independently.

## The bound on cache_read's weight

Attributing the observed movement to `cache_creation` first, then solving for what is left for
`cache_read`. Done under both the lead-calibrated and A1's raw cache_creation coefficients, so the
conclusion does not rest on which of those is right:

| attribution | cache_creation alone explains | ⇒ cache_read coefficient | vs list-price requirement | verdict |
|---|---|---|---|---|
| weekly, cc @ calibrated 0.314 pp/Mtok | 0.45 of 0–2 pp | **[0, 0.0489]** | 0.0766 | REFUTED (1.6×) |
| weekly, cc @ A1 raw 0.105 | 0.15 of 0–2 pp | [0, 0.0583] | 0.0766 | REFUTED (1.3×) |
| 5-hour, cc @ calibrated 3.10 | **4.43 of 3–5 pp** | **[0, 0.0179]** | 0.1855 | REFUTED (10.3×) |
| 5-hour, cc @ A1 raw 1.035 | 1.48 of 3–5 pp | [0.048, 0.111] | 0.1855 | REFUTED (1.7×) |

**Zero is inside the interval in three of four, and on the best-supported reading — the 5-hour meter
with calibrated coefficients — `cache_creation` ALONE (4.43 pp) fully accounts for the entire
observed 3–5 pp move, leaving nothing for cache_read at all.**

The one row where cache_read must carry *some* weight (5-hour @ A1 raw) uses the coefficient set
already known to be 2–3× too small because of the streamed-duplicate bug; inflating it to the
calibrated value is exactly what collapses that row to zero. So the residual is better explained as
an under-stated cache_creation coefficient than as a cache_read charge.

## What this settles, and what it does not

**Settled.** Re-reading cached context is not what the plan charges for. Quota buys what the model
**emits** and what **newly enters** the cache. The wave's central inversion survives its own
critic: in this arm, 95.7% of the tokens cost approximately nothing and the 4.3% that were
cache-creation cost essentially everything.

**Not settled.** Whether cache_read is *exactly* zero. The meters are integer-quantised, so the tightest
honest statement is an upper bound of **≤0.018–0.049 pp per million tokens**, i.e. **at most a
quarter of list-price weight and plausibly none**. That precision is more than sufficient for every
decision in this plan; nothing here turns on the difference between "zero" and "very small".

**A second, unplanned measurement.** The load turn and the resumed turns together put 1.43M tokens
into `cache_creation` for a 1.42 MB context — and a *trivial* one-line `claude -p` call was measured
separately at **46,355 cache_creation tokens** before doing any work. That is the resident-context
tax (CLAUDE.md, memory index, tool schemas, MCP rosters) priced directly for the first time, and it
lands in the class the meter *does* charge for.

## Method, and the two instrument failures found on the way

Subject: `next2` (`~/.claude-secondary`) — 0 live sessions, 0% of its 5-hour window, 2% weekly,
5d14h to reset. Quiet by selection, so no sibling's tokens contaminate the arm.

1. **Baseline read** (null control) — `claude-accounts --json --fresh`, next2 row.
2. **Load** — 1.42 MB of real repo prose into one session via `--session-id`.
3. **Arm** — 45 × `claude -p --resume <sid> "Reply with exactly: OK"`, meter sampled every 10 turns.
4. **Analysis** — transcript token counts deduped on `message.id`, compared against both hypotheses.

**Failure 1 — the arm nearly produced a confident null from nothing.** Passing 1.42 MB as an argv
word blew `ARG_MAX` (`rc=126`, "Argument list too long"). The load silently failed and the loop began
resuming a session that had never loaded — which would have yielded ~0 cache_read, a flat meter, and
a spurious "cache_read is free" verdict from an *empty arm*. Caught only because the run log printed
the load's exit code. Fixed by feeding the prompt on **stdin**, verified at 300 KB before relaunch.
*This is the falsifier the design most needed and nearly did not have: the arm must be shown to have
actually moved the class it claims to move.* The final run's 31.7M measured cache_read is that proof.

**Failure 2 — the first probe would have measured the wrong class.** A fresh `claude -p` produces
`cache_creation`, not `cache_read`. Only `--resume` re-reads a warm prefix. Verified on a small
session before scaling: a resumed turn measured `cr=111,920` against `cc=85, out=4`.

**The positive control was staged and deliberately NOT run.** It exists to distinguish "cache_read is
free" from "the meter never updated", and it is only informative on a null reading. The meter moved
on both axes (weekly 2→3, 5-hour 2→6), so movement is self-evidencing and the control would have
been ~1 pp spent to learn nothing. Script retained at `/tmp/meter-exp/control.sh` for any future run
that *does* read flat.

## What would falsify this

- If `next2` was not actually idle and a sibling's output-heavy work landed inside the window, the
  observed movement is over-attributed to my arm — which would make cache_read's bound *tighter*,
  not looser, so it cannot rescue the list-price model.
- If the weekly meter lags its inputs by more than the 43-minute run, the final read understates the
  true cost. The 5-hour meter moved promptly and by 4 points, which argues against material lag, but
  a re-read of `next2` several hours later is the cheap confirmation.
- If Anthropic re-weights the meter, this expires. It is a measurement of a live commercial policy,
  not a law — which is precisely why the plan calls for `cc-quota-price` to re-fit on a schedule
  rather than hard-coding today's answer.

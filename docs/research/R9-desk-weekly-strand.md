# R9 — Why the desk lane strands weekly quota, and the one-line reason

**VERDICT: the `DESK_W_FLOOR` guard was the largest single source of stranded weekly quota, because
it was a CONSTANT.** It fired identically whether an account's weekly reset was six days away or six
hours away — but the wall it guards against costs exactly as long as the time until that reset. So
it abandoned the tail of the very accounts it existed to protect. Fixed by scaling the floor to the
horizon (`desk_w_floor_at`, W2). Replayed: desk-time on an expiring account holding headroom
**18.5% → 49.5%**, weekly-wall exposure flat at **0** across every ramp tried.

Measured 2026-08-16 over `~/.claude/logs/account-utilization.jsonl` — 1,254 sweeps, 4 accounts,
2026-08-10 → 2026-08-16, covering 5 weekly resets. Harness promoted to
`scripts/desk-strand-replay.py` (it did not previously exist; see §5).

---

## 1. The loss, measured

The operator's report — *"our past two weekly resets left value on the table resetting at 90% and
80% each, a whole 30% of an account between the two"* — is confirmed, and understated by one
account:

| account | reset | used at reset | **stranded** |
|---|---|---|---|
| `next3` | 08-11 12:04 | 100% | **0 pp** ← the one that worked |
| `next2` | 08-15 11:04 | 92% | **8 pp** |
| `next` | 08-16 04:04 | 91% | **9 pp** |
| `next4` | 08-16 09:04 | 85% | **15 pp** |

**32 pp of weekly quota expired unused across three consecutive resets.** Weekly quota has no
recovery — unlike a 5-hour wall, which self-heals in ≤5 h and has three escapes.

(A fifth event, `next3` 08-10 06:04 at 58%, is a truncation artifact: the series begins 05:58, so
only six minutes precede it. It is retained in the tool's output — dropping an inconvenient event
is how a replay flatters itself — but nothing is inferred from it.)

## 2. The mechanism, at source

`desk_keys` sorted accounts into three tiers, and tier 2 (the set the rule wants to pick from)
required `w_rem >= DESK_W_FLOOR`, a flat **0.15**. Fall below it and the account drops to tier 1,
where no weekly deadline however imminent can lift it back — the ladder is lexicographic by design.

What that did in the final hours of each reset:

| account | headroom when demoted | hours to its reset | desk sweeps on target, final 12 h |
|---|---|---|---|
| `next` | **0.14** | 11.1 | **0 / 112** |
| `next2` | 0.09 | 7.9 | **0 / 75** |

`next` is the clean instance: **0.14 against a 0.15 floor — one point under — eleven hours out.**
It was demoted, the desk went to an account *six days* from its own reset, and it never came back
across 112 consecutive sweeps. It expired with 9 pp unused.

**The decisive control: the general lane, which has no such floor, got it right.** Over the same
`next2` endgame the two lanes disagreed on every sweep sampled:

```
ts    |   T-h |   DESK | GENERAL
04:27 |   6.5 |   next |   next2      <- general still draining the expiring account
05:57 |   5.0 |   next |   next2
07:17 |   3.7 |   next |   next2
08:44 |   2.3 |   next |   next2
10:06 |   0.9 |   next |   next2
```

`score_general` is `w_rem / T²` — deadline-dominant, no floor — and it kept naming the expiring
account down to the final hour. The desk lane, which is where the operator's own burn actually
happens, was the wrong one for the entire endgame. **This rules out "the quota was unspendable":
the fleet had a lane that wanted to spend it and a lane that refused, over the same eligibility.**

## 3. The fix

Reserve headroom in proportion to what the wall would **cost**: the full floor at
`DESK_W_FLOOR_FULL_H` hours out, ramping linearly to 0 at the reset.

```
floor_eff(T) = DESK_W_FLOOR × clamp(horizon(T) / DESK_W_FLOOR_FULL_H, 0, 1)
```

Equivalently — and this is the calibration that chose the constant — the floor becomes *"what you
could still plausibly BURN before the reset"*: 0.15 / 24 h = **0.63 pp/h**, inside the observed
per-account range (0.45 pp/h on `next`, 1.9 pp/h on `next4`). Reserving more than you can spend
protects nothing and strands the difference.

Two properties worth naming:

- **The guard survives where it was actually justified.** At 160 h out, 0.14 headroom is still
  demoted — a weekly wall there is unrecoverable for the rest of the week. Only the near field
  loosens, which is the field where the flat floor was never doing useful work.
- **Unknown timing keeps the FULL floor.** The horizon comes from `horizon()`, not the raw field,
  so absent / zero / elapsed stamps all read as FAR AWAY. Bad data can never talk the desk into
  draining an account. This is inherited from the shared contract, not re-implemented.

## 4. Result, and the honest limits

```
                policy | desk-time on an expiring account | guard
    FLAT (pre-W2)      | on-target   74/400   =  18.5% | wall-exposure    0
          ramp/8h      | on-target  128/400   =  32.0% | wall-exposure    0
          ramp/12h     | on-target  188/400   =  47.0% | wall-exposure    0
          ramp/18h     | on-target  196/400   =  49.0% | wall-exposure    0
          ramp/24h     | on-target  198/400   =  49.5% | wall-exposure    0   <- shipped
          ramp/36h     | on-target  198/400   =  49.5% | wall-exposure    0
          ramp/48h     | on-target  198/400   =  49.5% | wall-exposure    0
```

**24 h is the smallest value on the capture plateau** — full win, longest retained guard. Same
"sized by argument, not by insensitivity" reasoning `DESK_5H_FLOOR` is stated under, and it carries
the same caveat: *the plateau is flat because the guard rarely binds, which is absence of evidence
about the far end, not evidence of robustness there.*

Three limits, stated rather than buried:

1. **Burn cannot be replayed.** The series records where quota went, not where it would have gone
   under another policy. `desk-time-on-target` is a proxy — the thing a router actually controls —
   not a forecast of pp recovered.
2. **One week of data, 5 resets.** Re-run after ≥2 more cycles before treating 24 h as durable.
3. **This does NOT fix `next4`'s 15 pp** — the largest single loss. See below.

## 5. What is left open — `next4`, and why it is not fixed here

`next4` never fell out of tier 2. It was hard-**excluded** by `kmax-concurrency` for the last 32
sweeps before its reset, riding 72% → 80% only on sessions already running. An exclusion is not a
tier, so the ramp cannot reach it.

**It is deliberately left open, because the replay cannot currently attribute it.** `_excluded`
compares `k_eff` against `k_cap`, which is `KMAX` (**8**) for a work-charged row and
`KMAX_RESIDENT` (**40**) for a pane-charged one — a 5× difference in the threshold — and the series
recorded only `k`, never which instrument produced it. Every legacy row therefore had to be
replayed as WORK, the strict end, which can over-report a kmax exclusion but never hide one. **So
15 pp is an upper bound on that loss, not a measurement of it.**

Fixed forward (same commit): `record_utilization` now writes `k_work` and `k_src` beside `k` — free,
on the sweep that already happened — and `desk-strand-replay.py` prefers them when present and
prints the legacy-row share when it must fall back. The next replay can settle this; this one
cannot, and a fix to a shared eligibility gate is not something to ship on an unattributable number.

The change that would be tempting and should not be made blind: raising the concurrency cap for an
account near its reset. That edits `_excluded`, which is **shared** across all three lanes by
explicit design (C6 — *"a different objective over the same eligibility, never a second opinion
about who is eligible"*), and it trades a permanent quota loss against 429 risk on an account that
was already at k=11. Worth deciding on evidence; not worth appending to a floor fix.

## 6. Files

| file | change |
|---|---|
| `bin/claude-accounts` | `DESK_W_FLOOR_FULL_H`, `desk_w_floor_full_h()`, `desk_w_floor_at()`, `desk_keys` wiring, `record_utilization` k_work/k_src |
| `accounts.json` | `DESK_W_FLOOR_FULL_H: 24.0` + `_desk_w2` note correcting the falsified "0/324" claim |
| `tests/claude-accounts-core.bats` | `router desk: the weekly floor RAMPS with the horizon` |
| `scripts/desk-strand-replay.py` | **new** — the replay `score_interactive` has told readers to run since W1 |

# Idle sessions are already free — Phase A, measured

**Date:** 2026-08-09
**Wave:** S6.3 Phase A ("make idle sessions free"), `docs/plans/CONCURRENCY_PROGRAM.md`
**Instruments (this wave):** `scripts/occupancy-probe.sh`, `scripts/idle-slope-sweep.sh`
**Supersedes on the numbers:** S6.3's premise, and its per-session poller census.

---

## 1. Verdict

**Phase A's target is already met, by a factor of six, and its stated lever is worth 1.6% of the
load budget.** An idle resident session costs **0.0031 runnable threads** against a target of ≤0.02.
At the 150-session design point the entire resident fleet — sessions *and* every per-session poller —
projects to **0.46 runnable threads** against a ceiling of 20.

The wave was scoped to cut a slope of 1.6 down to ≤0.1. The 1.6 is real but it is an **active**
session's number, which §S6.2 already says on its face (*"a session blocked on the API contributes
~0"*). Nothing in the idle path was ever near it.

| Term | Measured | Method |
|---|---|---|
| idle `claude` process | **0.00067** | Δcpu/Δwall, n=6 truly-idle sessions |
| `cc-await-ping` (15 s poll) | **0.00216** | cpu/wall over a 60 s real run |
| `lead-crash-watchdog` (30 s poll) | **0.00024** | 200-iteration timing of the loop body |
| **idle session, total** | **0.00307** | sum of the three |
| target | ≤0.02 | §S6.3 |
| at 150 resident | **0.46** | 150 × 0.00307 |

One sub-finding does vindicate the wave's instinct, at a magnitude that changes nothing: **the
per-session pollers cost 3.6× the idle session they watch** (0.00240 vs 0.00067). Consolidating them
perfectly saves ~0.33 runnable threads box-wide at 150 — **1.6% of the load budget** — in exchange
for restructuring the wake path. §5 is why that trade is refused.

## 2. The census the wave was scoped on was argv contamination

S6.3 states the population as *"19 `cc-reaper`, 20 `cc-await-ping`, 6 `cc-reconcile`, 37 `sleep`"*.
Re-measured with a command-position predicate, on the same box:

```
                  argv-substring   command-position
cc-reaper                      4                  0
cc-await-ping                  8                  1
cc-reconcile                   4                  0
```

**`cc-reaper` and `cc-reconcile` are not per-session pollers and never were.** There is exactly one
`com.chrisren.cc-reaper` launchd job, box-wide, at `StartInterval 300`, and it holds a `mkdir` mutex
(`bin/cc-reaper:1168-1195`) whose policy is skip-not-queue — a second sweep exits 0 without working.
`cc-reconcile` has **zero** call sites outside that sweep and `cc-inbox-guard`. Neither appears in
any hook event in any of the five account settings files.

The contamination is this fleet's own indexed failure — `pgrep-f-matches-agent-briefs` — committed
against the number a wave was scoped on. Agent briefs travel in argv, and the Wave A brief itself
contains the literal string ``19 `cc-reaper`, 20 `cc-await-ping`, 6 `cc-reconcile` ``. Every session
carrying that brief matched itself, once per pane; `tests/cc-reaper.bats` matched by pathname. The
subject of the measurement was inside the measuring instrument.

`tests/occupancy-probe.bats:4` pins this shape so it cannot return: a row whose executable is
`claude` but whose argv quotes `cc-reaper` must bucket as `claude`.

**The real per-session population is two processes, not four:** `lead-crash-watchdog.sh` (a
SessionStart hook with no matcher, so 1:1 with sessions — measured 8 daemons at 8 sessions) and
`cc-await-ping` (armed on demand, but the wake-floor Stop hook at `hooks/session-continue.sh:351`
blocks a stop until it is armed, so at steady state a resident session is *supposed* to carry one).

## 3. Where the 1.6 actually lives

Per-process occupancy, Δcpu/Δwall over a 50 s window, 14 concurrent sessions:

```
IDLE (no prompt ever sent), n=6 : 0.0002 – 0.0010   mean 0.00067
FLEET (mixed active),      n=8 : 0.0054 – 0.1088   mean 0.05924
```

Even a **working** session measures ~0.09 by this method, not 1.6. The gap is not a contradiction and
it is the useful part of the result: **Δcpu/Δwall can only see processes alive at both snapshots.**
Every hook, `git`, `jq` and tool subprocess an active session forks is born and dies inside the
window, contributes nothing to this figure, and contributes fully to load. Summed surviving-process
occupancy read 1.19 against a load1 of 9.2 — the missing ~8 is fork churn, and it belongs entirely to
active sessions.

So the capacity model decomposes cleanly, and the split is the one §S6.2 designed for:

```
idle/resident session  = 0.0031   (claude 0.00067 + pollers 0.00240)   ← Phase A's subject
active session         ≈ 1.6      (~0.09 resident + ~1.5 fork churn)   ← Phase B's subject
```

**Phase A's subject was already 500× below the number the wave quoted against it.**

## 4. The decisive test, and its honest power limit

`scripts/idle-slope-sweep.sh` implements §S6.3's specified test — launch N idle sessions, sweep N,
regress load on N — with a 120 s settle (the 1-minute EWMA reaches ~86% of a step by then; a settle
below 90 s is *refused*, not warned about) and R² printed beside every slope.

The run, in full:

```
     N       load1   mean_runnable  top holder
     0       9.168           7.683  grep 0.733
     3       7.473           7.608  node 0.875
     6       7.160           4.158  git  0.750
     9       7.861           4.458  Browser 0.517

─── REGRESSION over 4 points ───
  load1          SLOPE = -0.14113 per resident session   (intercept 8.551, R2 0.383)
  mean_runnable  SLOPE = -0.43750 per resident session   (intercept 7.946, R2 0.770)
```

**Both slopes came out NEGATIVE**, which is not a physical result — adding sessions cannot unload a
box. It is ambient decay: sibling sessions' work wound down across the 13-minute sweep, and that
trend is larger than the effect and runs against it. `R2 0.383` on the load term says so without
being asked.

**So this sweep cannot ESTIMATE the idle slope — and it decisively REFUTES 1.6.** Those are different
jobs and the distinction is the whole value of the run. The predicted signal across N ∈ {0,3,6,9} at
the §1 figure is 9 × 0.0031 ≈ **0.03 load units**, well under the **1.7** ambient swing between
adjacent points — unresolvable, permanently, on a box that is never quiesced. But at the *briefed*
slope of 1.6, nine sessions would have added **+14.4 load units**, which is eight times the ambient
swing and could not have been missed by this or any instrument. It did not happen. Load at N=9 was
*below* load at N=0.

A negative slope also means the wave's stated acceptance criterion — *"the slope must fall to ≤0.1"*
— is satisfied on the arithmetic. It must not be reported as a win: nothing was changed, and the
criterion is met because the quantity it bounds was never large, not because any consolidation
worked.

Per-process Δcpu/Δwall (§3) carries the point estimate instead, because it is immune to exactly this
failure: another session's `git` cannot enter a `claude` process's own CPU counter.

The sweep is retained and landed because it is the right instrument for the *active*-session slope,
where the effect is ~500× larger and comfortably above the noise floor — and because, as above, a
weak estimator can still be a strong refuter.

One methodology limit, recorded because it bounds §4's own numbers: the sweep's synthetic sessions
(launched via `script -q /dev/null`, no prompt) did **not** all arm a watchdog — 15 `claude`
processes carried only 9 daemons. Synthetic idle sessions therefore under-represent a real resident
session's poller load. The §1 total does not depend on the sweep: each poller was measured
independently, on the real binary, precisely because of this.

## 5. Why the consolidation is NOT built

The daemon Phase A asks for is architecturally sound and was designed before it was declined:
`lead-crash-watchdog` is fully consolidatable (it is a pure "is pid X alive with identity Y" watcher
over an on-disk registry `cc-reaper` already reads), and `cc-await-ping`'s *polling* half could move
box-wide behind a per-session waiter blocked on a FIFO.

It is declined on the measured trade:

- **Payoff: 0.33 runnable threads at 150 resident — 1.6% of a budget of 20.**
- **Cost: the wake path.** `cc-await-ping`'s wake is *the watcher process exiting* — the harness's
  background-task-completion notification is the only channel that re-invokes an idle model — so a
  box-wide daemon cannot replace the per-session waiter, only its polling. Its `.watching` marker is
  read by `cc-notify`'s delivery verdict, `mailbox-drain.sh`'s re-arm nudge, and the Stop-blocking
  wake floor: **a daemon that stops re-stamping one marker per key blocks that session's Stop
  forever.** 53 test files reference the pair; `scripts/wait-contract-lint.sh` RED-flags any raw
  invocation outside a `cc-wait` contract.

The wave's own binding constraint reads *"spawn/fire/close tooling strands real work box-wide if
wrong"*. Spending that risk to recover 1.6% of a budget that is currently 2% consumed is the wrong
trade, and the measurement is what makes that sayable rather than arguable.

**The cheap lever, priced but not fired:** occupancy scales inversely with poll interval, so
`cc-await-ping` at 60 s instead of 15 s is a 4× cut (0.00216 → 0.00054) with no architectural change.
It is bounded above by `CC_WATCH_FRESH_S=90` — at 120 s the marker goes stale and the wake floor
starts blocking stops. It costs peer-mail wake latency, ≤15 s → ≤60 s, to buy 0.24 load units out of
20. That is a product call about responsiveness, not a capacity fix, so it is reported rather than
taken.

## 6. What actually binds at 150 resident — the wall is ptys, not load

Measured this session while the sweep ran: **33 ptys at 15 `claude` processes = 2.2 per session**,
inside the H-CAP-1 panel's projected 1.5–4 band
(`docs/research/session-capacity-blind-terms-2026-08-09.md` §1).

```
150 resident × 2.2                 =  330 ptys
kern.tty.ptmx_max                  =  511      (stock; every other table on this box is raised)
architectural ceiling              ≈  999      (/dev/ttys%03d — three digits)
```

**330 of 511 before any teaming burst**, and the panel measures consumption in *panes*, not sessions,
so handoff/teammate/notify-back panes push it past the ceiling. Load is at **0.46 of 20** at the same
point — a factor of 43 of headroom.

**Poller consolidation does not help this at all.** Pollers hold no ptys; panes do. The residency
question at 150 is a pty and memory question (§S6.2's 35 GB), not a load question, and Phase A cannot
touch either.

## 7. Falsifiable predictions

Each is cheap and re-runnable with the landed instruments:

1. `scripts/occupancy-probe.sh --seconds 60 --json` on a fleet of N idle sessions reports a
   `claude` bucket below `0.002 × N`. A figure above that refutes §3's idle term.
2. A session idle for ≥10 min shows Δcpu/Δwall < 0.002. Anything above indicts "idle" as a category.
3. Killing every `lead-crash-watchdog` daemon moves load1 by less than 0.1 at any fleet size this box
   can host. A larger move refutes §1's watchdog term.
4. `ls /dev/ttys* | wc -l` divided by the `claude` process count stays in 1.5–4 across the range. A
   ratio below 1 would refute §6 and reopen local scaling past 511 sessions.
5. `scripts/idle-slope-sweep.sh` on a genuinely quiesced box (ambient load1 < 1.0, no sibling
   sessions) recovers a load1 slope in 0.002–0.006 with R² > 0.8. A slope near 1.6 would refute this
   whole document — and is the single measurement most worth running if anyone doubts it.

## 8. Consequences for the rest of S6

- **Phase A: close it.** Target met, no code change needed, instruments landed. Its slope is
  **~0.003/session, not 1.6** — and every downstream number quoted "against Phase A's slope" should
  be re-quoted against that.
- **Phase B (serialised after A) inherits the correction, not the premise.** Its subject — active
  sessions at ~1.6 — is intact and is now the *only* load lever, since residency is not one. §3
  further says where B's win is: ~1.5 of the 1.6 is **fork churn from short-lived processes**, which
  Δcpu/Δwall cannot see, so B must instrument differently (`occupancy-probe.sh`'s ≥1 Hz R-state
  sampler does see them, and is landed for exactly this).
- **Phase D's thresholds were to be set from A's and B's measured slopes.** A's is now measured and
  it is ~0.003. A gate that admits on *load* still cannot separate residency from activity — §S6.6's
  point stands and is strengthened: the residency term is now known to be negligible, so the gate is
  refusing residents over a cost that does not exist.
- **The pty term (§6) is unowned by any wave in S6.** It binds at 150 and nothing in A–F addresses
  it. C-CAP-2 (pty-less substrate) is the named candidate.

## 9. Method note

Three instrument failures were caught *during* this wave, each of which had already produced a
plausible number:

- A one-level self-exclusion in `occupancy-probe.sh` left the probe's own `ps` in the sample as a
  pinned 1.000-runnable floor — the instrument reporting itself as the machine.
- `split(line, c, /[ \t]+/)` in the classifier: awk skips leading blanks only under the *default*
  field separator, so the right-aligned `ps` state column landed in `c[2]` and every row read as
  state `""`. The classifier emitted nothing while still printing a well-formed `#self 0` footer.
- An unvalidated `CC_SLOPE_CLAUDE_BIN` in the sweep would have slept every settle and regressed over
  sessions that never launched — reporting a slope of ~0, **the answer the wave was hoping for**.

None surfaced as an error; all three surfaced as clean output. The house rule from §10 of the ceiling
doc holds without amendment: *an instrument that returns a clean figure is not thereby a working
instrument.*

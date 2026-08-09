# The pty ceiling is real, is not where it was reported, and headless is free — Phase E, measured

**Date:** 2026-08-09
**Wave:** S6.7 Phase E ("render / headless"), `docs/plans/CONCURRENCY_PROGRAM.md`
**Instruments (this wave):** `scripts/pty-census.sh`, `scripts/headless-precondition-probe.sh`,
the pty gauge added to `scripts/render-census.sh`
**Supersedes on the numbers:** the pty figures in `idle-session-occupancy-2026-08-09.md` §6,
`session-capacity-blind-terms-2026-08-09.md` §1, and `CONCURRENCY_PROGRAM.md` §S6.3-MEASURED / §S6.9.

---

## 1. Verdict

**The headless precondition PASSES on all three predicates, and the wall it was dispatched to
break is 3.6× further away than reported.** Both halves are measurements, and the second one
reverses this wave's stated justification.

| | Measured | Reported by the brief |
|---|---|---|
| ptys per resident session | **~1.15** (1-per-pane + ~2 ambient) | 2.2 |
| ptys at 150 resident | **~152 of 511 (30%)** | 330 of 511 (65%) |
| binds at | **~509 paned sessions** | 150 |
| ptys for a HEADLESS session | **0** (measured, tty `??`) | — |

**The pty term is the third-tightest wall at the design point, not the first.** Render is the
binding one, at 140 panes — which is exactly what Phase E was *originally* justified by (§S6.7:
0.025 cores/pane, keep ≤20 visible). The pty re-justification displaced a correct reason with an
instrument artifact.

## 2. The census predicate was wrong everywhere, by a constant 16

Every pty figure in this program came from `ls /dev/ttys* | wc -l`. That glob matches **two disjoint
device classes**, and only one is a pty:

```
/dev/ttys000 .. /dev/ttys010    major 0x10 (16)   chrisren:tty   created on open, REMOVED on close
/dev/ttys0   .. /dev/ttysf      major 0x40 (64)   root:wheel     present since boot, static, 16 of them
```

The second class is the legacy BSD pty slave nodes. They are allocated to nobody, released by
nobody, and counted against `kern.tty.ptmx_max` never. There are **exactly 16, always**. So the
naive census carries a **constant +16 offset**, and at the fleet sizes the published figures were
taken at, that offset *was* the reported effect:

| Source | Published | Legacy | Real ptys | Sessions | Real ratio |
|---|---|---|---|---|---|
| `session-capacity-blind-terms` §1 | 21 | −16 | **5** | ~6 | **0.83** |
| `idle-session-occupancy` §6 | 33 | −16 | **17** | 15 | **1.13** |
| this session, 4 samples | 27 / 27 / 28 / 29 | −16 | 11 / 11 / 12 / 13 | 9 / 8 / 10 / 11 | 1.22 / 1.38 / 1.20 / 1.18 |

**The 1.5–4 band the H-CAP-1 panel projected, and the 2.2 wave A measured, are both artifacts of
this offset.** The true consumption model is simpler and tighter than either: **one pty per pane,
plus ~2 ambient.** Measured directly by `render-census.sh` after the gauge landed — `panes 11 /
sessions 11 / ptys 13` — the two terms read side by side from one instrument.

Confirmed by construction as well as by arithmetic. Allocating 5 ptys and releasing them moves the
narrow count by exactly 5 and leaves the legacy 16 untouched:

```
baseline            dynamic=11   glob=27
+5 script procs     dynamic=16   glob=32
after release       dynamic=11   glob=27
```

The correct predicate is `/dev/ttys[0-9][0-9][0-9]` — the 3-digit clones, which is the same
`/dev/ttys%03d` construction the ~999 architectural ceiling is derived from.

**What survives from the panel's finding, unharmed:** `ptmx_max = 511` is genuinely the only kernel
table on this box in the hundreds while every other is 10⁴–10⁶ and raised; it is genuinely
un-monitored; exhaustion is genuinely silent (`posix_openpt` → ENXIO, read as an application bug).
The tuning-fingerprint observation was correct. Only the *occupancy*, and therefore the distance to
the wall, was wrong.

## 3. Where the walls actually sit, at the 150-session design point

Each term as a fraction of its own ceiling, and the N at which each binds:

```
                     at 150 resident        binds at
load        0.46 / 20      2%              ~4,300 sessions   (idle-session-occupancy §1)
ptys         152 / 511    30%              ~509 panes        (this document)
memory        35 / ~45 GB  78%             ~190 sessions     (§S6.2)
render      3.75 / 3.5 cores  107%         ~140 panes        (§S6.1, render-census alarm floor)
```

**Render binds first, at 140 panes — 3.6× sooner than ptys.** It is also the only one of the four
already over its own alarm floor at the design point. Phase E's original one-line rationale (*"keep
≤20 visible; the rest headless"*) was right, and did not need the pty argument.

## 4. The headless precondition — PASS, measured, with two named gaps

`scripts/headless-precondition-probe.sh` runs a **real** `claude` (2.1.220, resolved from the
running process, never a launcher's `--version`) with no controlling terminal, driving it through
`--input-format stream-json` on a FIFO so the session is **resident**, not one-shot.

| Predicate | Verdict | Evidence |
|---|---|---|
| **P1** allocates no pty | **PASS** | process `tty` = `??`; census `12 → 12 → 12 → 12` across before / resident / active-turn / after |
| **P2** hooks still fire | **PASS** | all six fired: `SessionStart, UserPromptSubmit, PreToolUse, PostToolUse, Stop, SessionEnd` |
| **P3** cross-session mail reaches it | **PASS** | the model **echoed `HEADLESSPROBE-76696`**, a token existing nowhere but its inbox file |

P3's evidence is deliberately un-fakeable, and it is the second version of that test. **The first
version passed vacuously.** It asked whether the inbox cursor had advanced; it had — and the message
had reached nothing. `additionalContext` is injected into context and is invisible in the output
stream, so *"drained and delivered"* and *"drained and silently discarded"* have the identical
signature there. Only a random token echoed back **out of the model** separates them.
`tests/headless-precondition-probe.bats:2` pins that false pass; test 6 restores the cursor-based
rule and asserts it flips, so the pin cannot itself be free.

### Gap 1 — peers are told a headless session is dead

`cc-notify` returned **`verdict=mailbox-only`** for a session that was alive and that *did* receive
the message. Liveness is `~/.claude/cc-registry/<paneUUID>.json` + `kill -0` (`bin/cc-sessions:5`,
`bin/cc-notify:260`), and registration is keyed on a **pane** UUID a headless session does not have.
So the transport works and the **verdict lies** — in the direction that makes a live session look
retired. Since the wave brief's own back-channel instructions read *"mailbox only = target gone,
surface that"*, this would teach every peer and every operator that headless sessions are dead.

### Gap 2 — mail lands, but nothing wakes an idle headless session

A headless session drains its inbox at its next **turn boundary**, and in stream-json mode a turn
boundary only exists when something writes to its stdin. `cc-await-ping`'s wake is *the watcher
process exiting*, re-invoking the model through the harness's background-task notification
(`idle-session-occupancy` §5) — a channel that assumes a session the harness will re-invoke. In this
probe the watcher could not arm at all: the Stop hook's wake floor blocked the stop, demanded an
armed watcher, and the background-task approval was unavailable, which in **one-shot** `-p` mode
ends the session with `Error: Input must be provided…`.

The replacement is not hard to name — a watcher writes a user message into the session's stdin FIFO,
which is *more* robust than the pane path, not less — but it is a new wake mechanism on the exact
surface the wave's own constraints flag as stranding real work box-wide.

**Neither gap is a refutation of headless. Both are unbuilt prerequisites, and they are why the
substrate is not built in this wave** (§6).

## 5. What landed

- **`scripts/pty-census.sh`** — the gauge, with the narrow predicate, the legacy offset reported
  rather than silently corrected, and command-position session counting. `--assert-under` is the
  only mode that can exit non-zero; it is a gauge and gates nothing.
- **`scripts/render-census.sh`** — one `ptys used/max/pct` row in the human readout and three keys
  in the JSON. This is the capacity readout that already budgets render per pane, so the two terms
  are now readable from one instrument. **No verdict logic was touched**; the gauge feeds nothing.
- **`scripts/headless-precondition-probe.sh`** — re-runnable, four verdict states per predicate
  (`PASS`/`PARTIAL`/`FAIL`/`UNKNOWN`; "could not measure" never reads as "fine").
- **`tests/pty-census.bats`** (9) and **`tests/headless-precondition-probe.bats`** (6), each with
  mutation checks that reproduce the exact historical defect on demand: widening the glob back to
  `ttys*` restores the +16 inflation; matching argv instead of the `comm` column restores the
  `pgrep -f` contamination; restoring the cursor rule restores the false mail PASS.

**Nothing was wired into the admission gate.** `scripts/lib/capacity-admit.sh` is wave D's and a
refusing term is operator-gated; this wave only made the quantity visible.

## 6. Why the pty-less substrate is NOT built

The brief's priority 2 is conditional — *"given a working headless path"* — and the path works. It
is declined on the measured trade, not on difficulty:

- **The wall it was to break is at ~509 panes, not 150.** At the design point ptys sit at 30% of
  their table with 3.4× headroom. Rebuilding the substrate for ptys is spending the fleet's highest-
  risk surface on its third-tightest term.
- **The surface is `scripts/handoff-fire.sh`, 7,461 lines**, and the wave's own binding constraint
  reads *"spawn/fire/close tooling strands real work box-wide if wrong."*
- **Two prerequisites are unbuilt** (§4). A headless session today is one that peers are told is
  dead and that nothing can wake. Shipping the launcher before the registry and wake path would
  ship an inert mechanism — a session substrate nobody can reach.

**This does not close Phase E.** Render binds at 140 panes and *is* over its alarm floor at 150, so
the substrate is still needed — for render, on the original rationale, after gaps 1 and 2 close. The
measurement's contribution is that the next wave starts from 1-per-pane and a passing precondition
instead of from 2.2 and an assumption.

## 7. Falsifiable predictions

Each is cheap and re-runnable with the landed instruments.

1. `scripts/pty-census.sh --json` on any fleet state reports `pty_used` within ±3 of the pane count
   from `render-census.sh`. A gap larger than that refutes the 1-per-pane model.
2. `pty_legacy_nodes` reads **16** on this box in every state, including after a reboot. Any other
   value refutes §2's constant-offset claim and re-opens every corrected figure here.
3. `headless-precondition-probe.sh` re-run at any fleet size reports `pty_before == pty_resident ==
   pty_active`. A headless session that consumes a pty refutes §4 P1 and kills the substrate case.
4. Ramping to 50 paned sessions predicts **52 ± 4** ptys. The prior model predicts 110; the two are
   separated by ~2× and one ramp decides it. **This is the single measurement most worth running if
   anyone doubts this document.**
5. A `cc-notify` to a live headless session continues to return `verdict=mailbox-only` until the
   registry is keyed on something other than a pane UUID. A `delivered` verdict without that change
   refutes §4 gap 1.

## 8. Method note

The wave was dispatched with a warning that its census would hit argv contamination, and it hit a
*different* contamination in the same instrument: not the predicate matching too much of the process
table, but the glob matching too much of `/dev`. Both share one shape — **a count whose population
was never audited** — and both produced clean, plausible, well-formed numbers that three documents
then quoted against each other.

Two properties made it survive that long. The offset is **constant**, so every reading was
internally consistent and no sample ever disagreed with another. And it is **invisible at scale**:
at 150 sessions the same error would be a 10% overstatement and unremarkable, while at the 6 and 15
sessions it was actually taken at, it was a factor of 2–4. The error was largest exactly where the
measurements were cheap enough to take.

The house rule from the ceiling doc holds again without amendment: *an instrument that returns a
clean figure is not thereby a working instrument.* The addition this wave offers is narrower —
**when a census counts names in a namespace, enumerate the namespace once by hand before trusting
the count.** Eleven of the 27 matches were the resource; the other sixteen had been there since
boot.

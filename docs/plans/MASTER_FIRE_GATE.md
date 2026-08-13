---
status: open
---

# MASTER: fire gate — what spawns, where it runs, and what refuses it

**Condition key:** `master-fire-gate` · **Live members 2026-08-12 (measured after the apply):** 62 (52 open · 9 blocked · 1 claimed)
**Inventory:**
`cc-backlog list --all --json | jq -r '.[]|select(.condition=="master-fire-gate" and .status!="done")|"\(.id) \(.status) \(.title[0:90])"'`

**Why this is ONE effort.** Every member is a defect in the same pipeline: a row is labelled for a
venue, admitted against a capacity term, claimed under a lease, fired with a brief, and returned. The
pipeline was measured **dead in place for 1 h 34 m** on 2026-08-12 (`fired:0, deferred:318`, no
timeout) and unwedged by W0 of the parent plan — but the arms that keep it self-healing are the least
proven part of it, and the members here are exactly those arms.

## Phase 0 · Agent Team Orchestration

**EXECUTION LOCUS PER WAVE.** S = dispatched handoff session (the default) · T = in-session teammates · L = lead-inline.

🚨 **SUPERSEDED FOR THE LOCAL DRAIN (2026-08-13): read every `S` below as `T`.** This table was
authored under the one-session-per-wave model. The non-cloud backlog is now worked by THE LOCAL DRAIN —
a single standing session whose entire purpose is that it occupies **one** of the ~15 concurrent slots
for its whole life (`BACKLOG_SELF_DRAINING_2026-08-12.md:392`: *"One slot, indefinite duration — because
the bottleneck is concurrent sessions (~15), not session length"*). Firing a dispatched session per wave
spends a second slot and defeats the mission. Work every wave with **teammates INSIDE the drain session**
(`Agent({name})`, worktree-isolated, ≤150-line briefs, each torn down with a structured
`shutdown_request` — a plain-text broadcast leaves an orphaned pane and worktree), and recycle at the
EFFORT boundary via `handoff-fire.sh --recycle` — same pane, fresh context, no new slot. The `S` markers
below are left in place as the historical record of how these waves were originally scoped.

| Wave | Execution locus | Deliverable | Depends on |
|---|---|---|---|
| **F1 · venue labelling** | **S** | every live row carries a `venuePlan`; the producer is not open-only | — |
| **F2 · the cloud round trip** | **S** | a fired cloud session provably retires and returns; `.retired` > 0 | — |
| **F3 · claim coverage** | **S** | no spawn path fires into a dispatch worktree without claiming | — |
| **F4 · the stale brief** | **S** | a fired worker reads its DoD from a TRUNK REF, not a shared-checkout path | — |
| **F5 · admission terms** | **S** | admission keys on ACTIVE concurrency with a memory term that can bind | F1 (venue term) |

All five are dispatched; F1 and F4 must land before `master-*` waves are fired at scale, because they
are what makes a fired brief correct.

**Lead context budget:** ≥50% held for the venue/capacity judgment calls. **Succession point:** after
F2 — the cloud round trip is a long observation window and deserves its own context.

## Sub-waves

### F1 · Venue labelling (the prerequisite W2 named)
**248 live rows carry no venue label at all**, because `cc-venue run` is open-only and new rows wait
for the next producer pass; the dispatcher is journalling `ready:false, state:"void",
reason:"venue-unlabelled"` right now (advisory, so not yet blocking).

🚨 **Do NOT "solve" this with `CC_DISPATCH_VENUE_ONLY=cloud`.** Only 47 of 536 rows (8.8%) are off-box
eligible, so that parks 489 rows indefinitely — and because the claim path is the only *blocking*
re-validation in the system, it also silently switches currency-checking off for 86% of the store. The
venue lever steers; it does not scale.

### F2 · The cloud round trip
`cc-cloud retire` is FORWARD-ONLY: 41 declarations carry **0 `.retired` markers**. W0 wired the
terminal path to retire, but the release path has been DEPLOYED and never EXERCISED — its coverage is
structural and the behavioural proof is one live round trip. Also here: cloud create is intermittent
(1 of 4 on next3), a dispatcher-driven session sits NOT-STARTED past its boot budget, cloud fires die
on a LOCAL worktree freshness gate the VM never touches (2 of 3 lost), and two lands can run
concurrently on one cloud branch because the single-flight lock is per-PASS.

### F3 · Claim coverage
**Four spawn paths** fire a session into a dispatch worktree without ever calling `cc-backlog claim`,
so the lease governs a population that does not include them — and 20 live sessions were once measured
sharing one item's worktree. The lease is the whole economics of the grouping this wave inherits; a
spawn path outside it is a hole in the mechanism, not a missing nicety.

### F4 · The stale brief, by construction
`cc-dispatch` composes its prompt from the row's title and `dodRef` — and **every `dodRef` in the
store is an absolute path into the SHARED CHECKOUT, which trails trunk.** So a worker reads a DoD from
bytes older than the fix it is being asked to build on. The `master-*` rows created by W2 write
`origin/main:docs/plans/<FILE>.md` instead; make that the rule for every producer.

### F5 · Admission terms (Wave D)
The measured bind is `load >= 2.0/core` and it is asymmetric: unbounded for `handoff-fire` (**the
operator's own path**), budget-released after 3 refusals for unattended callers, and off entirely for
the Agent tool. W3 of the parent plan owns the symmetry; this wave owns the *terms* — admit on ACTIVE
concurrency, with a memory term that has ever actually bound.

✅ **LANDED 2026-08-13 — `61e39ef3`** (backlog `1c45598a91be`; D7 of `CONCURRENCY_PROGRAM.md` closed
by decision, not by waiver). `scripts/lib/capacity-admit.sh` carries `segments` (compressor-segment
%, ceiling 50, provisional and re-derivable from its own rows) and `active` (sessions mid-turn,
ceiling 8), plus `reserve-active` on proven operator presence; the mid-turn census is
`cc_sp_active` in `scripts/lib/spawn-presence.sh`. Both new terms are ON for the Agent tool — the
path that turns the LOAD term off, and the one axis 10's F3 fan-out actually travels. Full note,
including the three corrections the build made to the item as specified:
`CONCURRENCY_PROGRAM.md` §S6.6-LANDED.

⚠️ **Two things this wave did NOT close, named so they are not assumed:** (a) `handoff-fire.sh`'s
`capacity_gate()` — the OPERATOR's path — still carries only load+headroom. The MEASUREMENT is
shared (`cc_hw_compressor_segment_pct` sits in the shared-terms block ready for it); only the policy
is not wired, because adding a refusing term to the human's own path is a value call, not a build.
(b) F3's thundering herd is a **wake** of existing residents, and no spawn gate can see one by
construction — wake-side damping remains open and in no wave's scope.

## Definition of done
A row can be fired without a human in the loop: labelled for a venue, admitted on a term that binds,
claimed by the worker that runs it, briefed from a trunk ref, and returned with its slot released —
demonstrated by one full local round trip and one full cloud round trip carrying a `.retired` marker.

## Status log
- **2026-08-12 — created by W2 of `BACKLOG_SELF_DRAINING_2026-08-12.md`.** 57 rows on this condition
  (21 pre-existing from the 2026-08-09 triage, 7 by its verdict replay, the rest semantic).
- **2026-08-13 — F5 landed (`61e39ef3`).** Both terms in the gate, 21-case suite
  (`tests/capacity-admit-active.bats`) green and red-proved 0/21 against pristine trunk. Its
  dependency on F1 turned out to be nominal: F5 is a *machine*-capacity term and never reads a
  venue label, so it did not wait. The DoD's "admitted on a term that binds" clause is now met;
  the other four clauses are unchanged.

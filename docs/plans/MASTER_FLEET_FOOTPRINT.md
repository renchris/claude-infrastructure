---
status: open
---

# MASTER: fleet footprint — what the fleet leaves on the operator's machine

**Condition key:** `master-fleet-footprint` · **Live members 2026-08-12 (measured after the apply):** 58 (39 open · 18 blocked · 1 claimed)
**Inventory:**
`cc-backlog list --all --json | jq -r '.[]|select(.condition=="master-fleet-footprint" and .status!="done")|"\(.id) \(.status) \(.title[0:90])"'`

**Why this is ONE effort.** The box is the shared resource every other wave spends, and every member
is a leak in it: 273 worktree dirs on disk against 151 git-registered (122 orphaned, 209 carrying
`node_modules`); 2,363 of 2,428 task dirs holding no task; 4 orphaned research-subagent processes at
~2.4 GB RSS for 16 h 55 m; panes that finished and never closed. The operator feels this wave directly
— it is why their own `handoff-fire` gets refused on load.

## Phase 0 · Agent Team Orchestration

**EXECUTION LOCUS PER WAVE.** S = dispatched handoff session (the default) · T = in-session teammates · L = lead-inline.

| Wave | Execution locus | Deliverable | Depends on |
|---|---|---|---|
| **P1 · GC correctness** | **S** | every reaper decision is recorded, and occupancy is never guessed | — |
| **P2 · process footprint** | **S** | orphaned workers and RSS bursts are attributable and bounded | — |
| **P3 · the kill switch** | **S** | a launchd-loaded destructive sweeper has a kill switch and a guard | — |
| **P4 · one-shot cleanups** | **L** (lead-inline) | today's orphaned panes/worktrees actually gone | P1 |

**P4 is lead-inline:** it is a handful of `cc-teardown` / `worktree-gc` invocations whose verdicts must
be read where they are run. Several of its rows are also `master-operator-gated` (a pane only ⌘W can
close) — check that group before doing anything by hand.

**Lead context budget:** ≥50%, and treat P3 as an escalation surface (a destructive sweeper). **Succession
point:** after P1.

## Sub-waves

### P1 · GC correctness — record the decision, never guess the occupancy
`worktree-gc --dispose-landed-dirt` removed 32 directories on 2026-08-11 and wrote **no disposal
record**, so nothing can say what was in them. It also swept an OCCUPIED worktree mid-session
(`close-integrity`, 01:50) because the occupancy oracle read live-ness wrong, and
`recheck_live()` swallows `claude_cwds` so "no live claude" and "lsof could not answer" are the same
answer. That collapse is the defect: **a probe that ACTS on absence must confirm the safe state**
(memory: `probe-that-acts-on-absence-must-confirm-presence`).

Also: landedness must be judged BY PATH and BY CONTENT before deleting anything — commit-landedness is
blind to staged and untracked bytes (memory: `landedness-over-commits-is-blind-to-staged-content`).

### P2 · Process footprint
4 orphaned research-subagents that cannot ack a `shutdown_request`; the `claude.exe` 4–40 GB
self-burst (54 events / 11 days) with no argv in the historic sampler; the compressor sentinel — the
ONLY guard against the 5-deaths-in-11-days kernel-panic class — running with an actuator that has no
release path (a freeze machine at design-point margins); 2,363 empty task dirs; 21 GB of `/tmp/claude-*`
TMPDIRs. ⚠️ **Orphanhood is not a discriminating signal here** — every backgrounded worker on this box
is ppid-1, so key any alarm on an axis the HEALTHY population lacks (memory:
`orphanhood-is-not-a-discriminating-signal`).

### P3 · The kill switch
`bin/cc-reaper` is launchd-LOADED, runs `git worktree remove --force` (`bin/cc-reaper:635`) and has NO
kill switch. That is the highest-blast-radius unattended actuator on the box. Treat any change here as
an escalation surface: it needs a kill switch, a guard, and a red-proved test before it needs anything
else.

### P4 · Today's cleanups
Named panes and worktrees, each with its own row. Do these only after P1 lands the disposal record —
otherwise the sweep repeats the exact defect the group exists to fix.

## Definition of done
Disk and process footprint are bounded by a mechanism, not by a person noticing: every disposal writes
a record, occupancy is proved rather than inferred, the destructive sweeper has a kill switch, and the
worktree/task-dir counts on disk match the registry within a stated tolerance.

## Status log
- **2026-08-12 — created by W2 of `BACKLOG_SELF_DRAINING_2026-08-12.md`.** 49 rows on this condition
  (20 pre-existing from the 2026-08-09 triage, 10 by its verdict replay, the rest semantic).

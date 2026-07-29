---
status: open
---

# GROUND-UP DISPATCH — coordinator runbook for the 12-subsystem rebuild campaign

**Scope (frozen):** drive every open row of GROUND_UP_REBUILD_MAP.md to DONE via one
/ground-up handoff session per row — ≤2 in flight fleet-wide, rows 4→3→2 strictly
sequenced, every fire with --notify-back to the coordinator, account chosen at fire time.

## Phase 0 — Orchestration (the "team" here is the handoff-session fleet)

- **Roster:** 1 COORDINATOR (the recycled successor of e891e080, standing) + up to 2
  concurrent REBUILD sessions (full handoff sessions, one per map row — visible split-pane
  peers per the dedicated-split-pane rule, never in-process subagents). Each rebuild
  session runs its OWN Agent Team internally per its own plan's Phase 0 — this file
  orchestrates SESSIONS, not teammates.
- **Dependency graph:** 4 → 3 → 2 strict chain (shared liveness/comms/succession seams);
  {5, 12, 10, 8, 7, 11, 9} independent of the chain and of each other; 6 blocked-by ALL
  (enforcement surface). Wave 1 = {4, 5}.
- **Worktree assignments:** each rebuild session claims its own warm worktree at fire time
  (handoff-fire does this); the coordinator holds NO worktree claim beyond its own pane's.
- **Spawn-wave order:** fire next-in-order only on (a) a verified completion ping AND
  (b) load < 10 AND (c) an eligible account per the fire-time policy below.

## Coordinator protocol (the recycled session runs this loop)

1. **Fire-time account choice** (never pre-assigned — quota moves): run `claude-accounts`;
   eligible = auth-healthy AND 5-hour headroom AND weekly headroom; among eligible prefer
   the SOONEST refreshTokenExpiresAt (use logins before their cliff); never two in-flight
   rebuilds on one account. Log the choice in this file's row.
2. **Fire** via /handoff → handoff-fire.sh --split-right --notify-back with the row's
   payload below. Verify ENGAGED (transcript birth), record pane uuid + account in the
   Wave log.
3. **On completion ping**: verify the row's DoD by DISK (map row updated, plan doc exists,
   landed shas content-verified on origin/main) — a ping is a claim, not evidence. Then
   fire the next row per the order. On a blocker ping: triage; a seam dispute is decided
   by the seam's OWNER row per the map.
4. **Cadence guards**: before each fire read `uptime` — 1-min load ≥ 10 ⇒ hold the fire
   until the running rebuild lands its next batch (the sessions are the load, not the
   lands). Coordinator itself recycles at ≥50% context per context-econ policy.

## Dispatch order (map §dispatch, dependency-aware)

4 → 3 → 2 (STRICT SEQUENCE, shared seams) · 5 · 12 · 10 · 8 · 7 · 11 · 9 · 6 (last —
enforcement surface of every other row). Wave 1 = row 4 + row 5 (independent of the 4→3→2
chain). Wave N = next-in-order as slots free.

## Per-row fire payloads

Template (compose per row; the /goal clause is the FALSIFIABLE distillation — superlatives
are banned by the skill):

```
/goal Rebuild <subsystem> from first principles so that <row's metric target> holds under
<row's standing constraint>; measured, landed, and verified by disk-truth acceptance reads.
Then: /ground-up <slug> — read docs/plans/GROUND_UP_REBUILD_MAP.md row <n>, the ground-up
skill, and docs/plans/LAND_PIPELINE_V2.md (exemplar) FIRST. Work in your own worktree;
land via /ship as you go; update the map row as part of your DoD; ping the coordinator
(--notify-back) on completion or blocker.
```

| Row | Slug | Metric target (the number in the /goal) | Standing constraint |
|---|---|---|---|
| 4 | session-registry-reaping | zero live-conversation reaps; reap decision ≤60s stale | never reap a live operator conversation |
| 3 | cross-session-comms | delivery ≥99% within one boundary; exactly-once ack | must survive pane recycles + .forward chains |
| 2 | session-lifecycle | fire→engaged ≤60s p95; zero illegible pane exits | a watched pane never vanishes without visible continuation |
| 5 | autonomy-dispatch | dispatch decision ≤5 min from backlog-add; zero false cliffs | backlog > concurrency is normal, not a stall |
| 12 | daemon-fleet-activation | every staged job runs-or-alarms within 24h of staging | disabled-bit trap; agent stages / operator activates once |
| 10 | operator-surface | every operator-owned step platter'd as ONE runnable command | absence-is-loud requires existence evidence |
| 8 | context-economy | recycle before 75% fill p95; zero auto-compact walls hit | rot degrades decisions before the wall |
| 7 | account-relogin | zero work stranded by login cliffs; routing reads live quota | cliffs are hard walls; 4 isolated accounts |
| 11 | worktree-warm-pool | claim ≤3s warm; disk drift bounded + swept | ownership is per artifact-class |
| 9 | memory-knowledge | index within read limits; zero anti-capture violations | memory rot is the failure mode |
| 6 | guardrail-hooks | zero accidental tool blocks; every deny attributable | rebuild LAST — every row's enforcement surface |

## Wave log (coordinator appends; map rows carry the durable status)

- 2026-07-29: campaign opened; coordinator = the recycled successor of session e891e080.

## Learnings (accumulate; never delete)

- Wave sizing is the load lever: sessions are the ambient load (14 ≈ load 88-104 pre-v2);
  lands are cheap now. Cap in-flight rebuilds, not landing frequency.

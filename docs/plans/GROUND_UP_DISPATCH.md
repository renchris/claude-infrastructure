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
- 2026-07-29T17:53Z: coordinator re-armed — pane `71B42B48-1331-4F60-8DA3-6849F2682CA2`,
  session `98f66842`, account next2 (claude-secondary), worktree `.worktrees/gu-coordinator`
  on `gu/coordinator`. Fire-time account snapshot (all 4 auth-healthy, `claude-accounts`):
  weekly-window expiry next2 08-01T10:59Z < next 08-02T03:59Z < next4 08-02T09:00Z <
  next3 08-04T12:00Z; `--rank general` = next > next3 = next4 > next2.
- 2026-07-29T18:03Z **WAVE 1 · row 4 FIRED** — session-registry-reaping. Account **next**
  (rank #1; ALSO the soonest login cliff 08-02T20:21Z — use the login before it dies).
  Pane `3446A212-B9A0-4754-95A4-66FBC33C97BC`, session `be504c79`, branch/worktree
  `gu-session-registry-reaping`. **ENGAGED verified by transcript CONTENT** — 12 assistant
  turns + 6 tool_use blocks, not birth alone (the /goal-prefix trap makes birth a false
  positive; this fire deliberately leads with plain text and self-arms a short `/goal`).
- 2026-07-29T18:03Z **row 5 HELD at the cadence guard** — 1-min load 12.58 ≥ 10 immediately
  after the row-4 fire. Account **next2** reserved (soonest-expiring weekly window,
  08-01T10:59Z). Fires resume when load < 10; the sessions are the load, not the lands.
- 2026-07-29T18:10Z **WAVE 1 · row 5 FIRED** — autonomy-dispatch, after the guard cleared
  (load 12.58 → 7.74 over ~7 min). Account **next2** (soonest-expiring weekly window).
  Pane `F3B8333C-AC94-4CF7-B1ED-1212A5D77A94`, session `8891c11f`, branch/worktree
  `gu-autonomy-dispatch`. **ENGAGED verified by content** — 23 assistant turns, 13 tool_use,
  and 0 rows carrying the 4000-char `/goal` rejection.
- 2026-07-29T18:12Z **wave 1 saturated (2/2 in flight); on-method check passed for both** —
  each session armed its own short `/goal` and has read the map row + the ground-up skill +
  the exemplar plan. Row 4: 81 assistant turns / 32 tool_use, writing. Row 5: 23 / 13.
  **Next fire is BLOCKED on a verified completion, not on a timer** — the next row in order
  is **3 (cross-session-comms)**, which additionally requires row 4 DONE (strict 4→3→2).
  So a row-5 completion does NOT unblock row 3; it unblocks **12 (daemon-fleet-activation)**,
  the next independent row.
- 2026-07-29T18:12Z coordinator side-fix LANDED `dfaf7323` (+ wave log `9014fb8b`),
  content-verified on origin/main. **Not yet DEPLOYED** — `~/.claude/scripts/` symlinks the
  shared checkout, which sits at `38eec335`; the deploy autopilot is fail-closed with no GREEN
  postland stamp yet. Until it advances, every cold fire must be preceded by
  `rm -f "$TMPDIR"handoff-deps-XXXXXX.sh` (the live script is still the pre-fix copy).

## Learnings (accumulate; never delete)

- Wave sizing is the load lever: sessions are the ambient load (14 ≈ load 88-104 pre-v2);
  lands are cheap now. Cap in-flight rebuilds, not landing frequency.
- **One rebuild fire moves the load guard by itself.** Row 4's fire took the 1-min load
  6.93 → 12.58 in ~90s (cold worktree + session boot + its own Phase-1 fan-out). So the
  guard must be re-read IMMEDIATELY BEFORE each fire, never once per wave — a wave-1 pair
  read as "both clear" at wave open is a stale reading by the time fire #2 is typed.
- **A rebuild fire payload must NOT start with `/goal`.** handoff-fire submits the whole
  file as the first prompt; a leading slash command makes CC parse the entire submission as
  that command, and `/goal` caps at 4000 chars — over it, the prompt is REJECTED and the
  session idles at an empty box while engagement-verify still reports "confirmed (birth)".
  Measured here: base 1.7 KB + the notify-back/self-retire trailers = 3423 chars, only 577
  under the cap, and the account-sweep bridge can be appended at fire time. Structure used
  instead: plain-text first line + an inline `Scope (frozen):` + a STEP 1 that has the fired
  session arm its own SHORT `/goal`. Zero cap exposure, and the goal condition ends up being
  the falsifiable one-liner the ground-up skill's Phase 0 actually asks for.
- **Verify engagement by transcript CONTENT, never the script's verdict.** `→ engagement
  confirmed (transcript/registry birth)` is satisfied by attachment/system rows alone. The
  real read is `type=="assistant"` turn count + tool_use blocks in
  `$CONFIG_DIR/projects/<slug>/*.jsonl`.
- **Cold `--worktree` fires collide on a literal temp filename** (fixed 2026-07-29, below):
  BSD `mktemp` only substitutes a TRAILING `XXXXXX`, so
  `mktemp "$TMPDIR/handoff-deps-XXXXXX.sh"` created a file named literally
  `handoff-deps-XXXXXX.sh` and every subsequent cold fire died `mkstemp failed … File
  exists`. First fire of the day always works; fire #2 onward never does — which is exactly
  the shape a per-wave campaign hits and a single manual fire never sees.

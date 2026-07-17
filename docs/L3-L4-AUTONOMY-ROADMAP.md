# L3 → L4 Autonomy Roadmap (4 Claude Code accounts, no SDK, no at-cost API)

**Owner:** Chris Ren · **Drafted:** 2026-07-16 (orchestration-desk session) · **Status:** LIVE — committed 2026-07-17; both P0 milestones DELIVERED (branch `feat/autonomous-lifecycle`, awaiting land). See §6 Milestones.
**Frame of reference:** Boris Cherny, "Steps of AI Adoption" (2026-07-16). Self-assessed at ~80th-pct **L3 (Supervised autonomy, ~100 agents)**.

> Scope (frozen): reach 100th-pct L3 and enter L4's *operating model* using ONLY the 4 Max accounts + Claude Code
> native primitives (Agent Teams, subagents, Dynamic Workflows, /loop, routines/schedule, hooks, cc-notify,
> the 2-way desk-orchestration). No Agent SDK, no at-cost API. Constraint is load-bearing: it caps agent COUNT,
> not the operating MODE.

## 1. What actually caps us below 100th-pct L3
Cherny's L3 bottleneck is *trust + decision throughput*. Ours is narrower and **mechanical**: the loop breaks on
**halts**, not on trust. Two halt-classes, ~1–few/hour, each converting away-from-keyboard time into dead time.
At L3 you should *monitor by exception*; today we monitor by **interruption**.

1. **Permission prompts.** Precedence is `deny > ask > allow` (docs-cited 2026-07-16). A broad `ask` SHADOWS any
   specific `allow` — so the whole "add safe allow-forms" method was inoperative. Only lever = **narrow/remove the
   ask** (or a PreToolUse hook). Empirically the live culprit is `rm -rf artifacts/` (static `rm:*` ask, ~21×/build)
   + custom-CLI classifier prompts on `handoff-fire.sh` / `cc-notify`.
2. **Idle lingering sessions.** Handed-off leads that don't self-close (`--recycle` pane-exit fails), coordination
   hangs (dead `model:fable` bare subagent → silent Opus + 35-min "Hatching"), the desk that can witness but not act
   (`it2 ls` returned 0). Teammates auto-reap; **leads do not.**

Closing these two IS 100th-pct L3. Both are in flight (git-reset ask fixed; rm relief + lifecycle reaper briefed).

## 2. 100th-pct L3 checklist — kill every halt → monitor by exception
- **Permissions → near-zero prompts.** Narrow all common-safe asks; build the **`rm` PreToolUse hook** (auto-allow
  within-repo/regenerable deletes; prompt only `~` / `/` / `.git` / outside-repo); allow-list trusted infra CLIs
  (`handoff-fire.sh`, `cc-notify`). Principle: the ONLY thing that ever prompts is a genuinely irreversible op
  (push, deploy, destructive migration) — and even those **queue for the next waking window, not block in place**
  (a PreToolUse hook can defer-to-a-review-file instead of halting).
- **Sessions → self-healing.** Autonomous-lifecycle reaper: reliable close (verify pane exited; force-close if
  successor live but pane persists) + idle-cause classifier + re-engage + safe reap (checkpoint-first, never kill
  active/owned-wait). Brief: `/tmp/autonomous-session-lifecycle-brief.md`.
- **Desk → persistent exception-monitor** across all 4 accounts: auto-recover the recoverable, queue only true
  decisions. Use last-*assistant*-ts + git-landed + structured errors, NEVER mtime/side-effect for causal claims.

## 3. The L4 leap — closing the loop WITHOUT the SDK
Cherny's literal L4 (1,000s of agents via SDK) is **not** reachable on 4 accounts/no-SDK. But L4's operating model —
closed loop, self-initiating work, steer-by-intent, monitor-by-exception — **is**, at 4-account scale. Native map:

| L4 capability | Native CC primitive (no SDK) |
|---|---|
| "Claude kicks off Claude" | Scheduled **routines** (`/schedule` / cron cloud agents) + the **2-way desk-orchestration** (spawns independent model-pinned instances) |
| Fan-out repetitive work | **Dynamic Workflows** + **Agent Teams** (worktree-isolated) + **/loop** / **/batch** |
| Self-initiating dispatch | A **dispatcher routine** that wakes on cron, reads a durable backlog, checks quota, spawns workers |
| Event-triggered automation | **Hooks** (PreToolUse=permissions, Stop=continuation, TeammateIdle=reaping) |
| Monitor by exception | The **desk** (persistent) |

**The closed loop = 5 pieces:** durable **backlog** (file/tasklist) → **dispatcher routine** (pulls items + spawns
teams unattended) → workers that run **without halts** (needs §2) → **verify+merge gate** (tests/build/lint/AV;
autonomous land on green, queue red) → **discovery feed** (standing critics / frontier-hole sweeps / "what's
missing" scans that refill the backlog). The discovery feed is the true L4 signature: *most work originates from
Claude, not the operator.*

## 4. The real ceiling is quota — and the asleep-window is the edge
4 Max accounts running 24/7 WILL hit weekly caps. The loop must be **quota-aware**: dispatcher routes across the 4
accounts by their 5h/weekly reset windows (`claude-accounts` routing), throttles when depleted, and **batches heavy
autonomous work into the sleep window** when the operator isn't also drawing quota. Deliver a **morning digest** of
what landed / what's queued for a decision. Highest-leverage single move for "use the time when I'm away."

## 5. Build order (all on 4 accounts, no SDK/API)
1. **P0 — `rm` PreToolUse hook + allow-list sweep** → kills most prompts. **DONE** (§6 M1).
2. **P0 — autonomous session-lifecycle reaper** → kills idle-linger + auto-recovers hangs. **DONE** (§6 M2).
3. **P1 — dispatcher routine + durable backlog** → self-initiating work (the "Claude kicks off Claude" spine).
4. **P1 — verify+merge gate** → green work lands unattended (reso `/ship` pattern generalized).
5. **P2 — discovery feed + overnight quota-aware batch + morning digest** → the L4 operating mode at our scale.

P0×2 → 100th-pct L3 (**both DELIVERED — §6**). P1–P2 → the L4 build (next).

## 6. Milestones — P0 DELIVERED (branch `feat/autonomous-lifecycle`, 2026-07-17; awaiting land)

The two P0 briefs, folded in as concrete milestones. Both are built + RED-proven + verified; the only
remaining step for each is **activation, which is C10 (human-only)** — an agent never self-installs a
permission-hook or a session-closing daemon. Runbooks generate the operator's one-shot scripts.

### M1 — `rm` PreToolUse hook (brief: roadmap §1.1 + §2) — DONE
- **Delivered:** `hooks/rm-safe-allowlist.sh` (deterministic; auto-allows `rm` of regenerable within-tree
  targets — build/cache/artifacts or `/tmp` scratch — and stays silent for `.git`/`~`/`/`/outside-repo →
  the ask prompt still fires). `tests/rm-safe-allowlist.bats` (44-case matrix, 10 tests). Operator wiring
  `docs/activation/rm-safe-activate.sh` (idempotent jq into all 5 settings.json). Runbook `docs/RM-SAFE-ACTIVATION.md`.
- **Key learning:** the existing `hooks/smart-bash-allowlist.sh` already had dormant rm-allow logic but was
  registered in ZERO settings.json — scoped a NEW rm-only hook instead of activating the broader one (blast
  radius). Allow is opt-in to a whitelist, never opt-out. Verified against copies of all 5 real settings:
  only the rm hook added, everything else byte-identical.
- **Commits:** `ef7b997`. **Activation (C10):** `docs/activation/rm-safe-activate.sh --apply`.

### M2 — Autonomous session-lifecycle reaper (brief: `/tmp/autonomous-session-lifecycle-brief.md`) — DONE
- **Delivered:** the reliable-close / classifier / safe-reaper trio, built ON the existing infra (did NOT
  reinvent — `cc-teardown`, `cc-sessions`, `cc-teardown-safety-gate`, `teammate-checkpoint` were reused):
  - **D1 (close):** fixed `bin/cc-teardown`'s blind-enumerator bug (an empty it2 `[]` at exit 0 → INDETERMINATE,
    never a false "pane gone"); enumeration routes via the registry (`cc-sessions`), immune to it2-ls-0.
  - **D2 (brain):** `bin/cc-classify` — 7-cause classifier from durable signals (last-ASSISTANT-ts, pid,
    structured `isApiErrorMessage`, git work-landed, team attribution), never mtime. Sub-fix: `claude-accounts`
    poll-throttle 429 → `poll_throttled` flag + cache-fallback, no longer mislabeled `rate-limited`.
  - **D3 (loop):** `bin/cc-reaper` — reaps ONLY handed-off-lead / finished-teammate that is work-landed +
    idle≥settle, checkpoint-first, double-gated (classifier + cc-teardown's own gate). launchd standing loop.
- **Verified for real:** `scripts/reaper-e2e.sh` — a throwaway iTerm2 window reproduces an orphan; the reaper
  closes the REAL pane (re-enumeration confirms GONE) and, in a staged race, checkpoints WIP to
  `refs/checkpoints` BEFORE aborting (never loses work). 7/7. Live dry-run vs 6 real sessions: 0 reaped.
- **Key learning:** the gap was never plumbing — it was an *authority boundary* (`cc-teardown`'s C10 "human-only"
  bar) + a fused classifier + a lead-idle detector. Crossed the boundary provably-safely by double-gating, not
  by weakening the actuator. CC-native `bridge-session` records are NOT a handoff signal (present in every
  session) — a false-positive that had to be excluded.
- **Gate:** `scripts/session-lifecycle-safety-gate.sh` (GREEN · 3 met · 0 failed). **Commits:** `013502f`
  (accounts), `1b4c489` (cc-teardown), `863df8c` (cc-classify), `20d3f89` (cc-reaper+gate+activation),
  `0d98384` (e2e). **Activation (C10):** `docs/AUTONOMOUS-REAPER-ACTIVATION.md` (`launchctl load` the plist).

## Related
- Permission model: memory `permission-autonomy-allowlist-method` (corrected 2026-07-16: `deny>ask>allow`).
- Lifecycle: memories `desk-read-transcript-before-asserting-why`, `desk-monitor-fixed-head-ref`, `cc-notify-session-pane-mapping`.
- Model pinning: `~/.claude/rules/agent-teams.md` §Model Pinning (non-session model needs an assignee/independent session, never a bare subagent).

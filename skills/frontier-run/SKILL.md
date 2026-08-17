---
name: frontier-run
description: Spend the frontier-model window (currently Fable 5 — SSOT ~/.claude/model-config.yaml frontier_access) on unknown-unknown discovery, via baseline-blind derivation panels over the project's FRONTIER_HOLES ledger or a fresh seam sweep. AGENT-INITIATED under the bounded-autonomy policy (CLAUDE.md § Frontier Tier Routing; the human never model-switches or starts frontier sessions) — invoke YOURSELF when (a) a qualifying wall BLOCKS the current task (inline, ≤2 panelists), or (b) at main-task wrap-up with ≥2 OPEN holes and the window active (batch). Also on user request ("/frontier-run", "run fable on the holes"). Bounds: hook-enforced per-session spawn cap (frontier_discovery_budget); blocked spawn = park, never retry. NOT for routine research (/research), identified bugs (/investigate), or implementation.
---

# frontier-run — spend the frontier window on what the default tier can't see

The frontier tier's value is exclusively the delta above the default tier:
problems Opus 4.8 @ max is **blind to**, not problems it has already found. The
deliverable is always a *report back* — findings tagged by novelty, ledger
updated — never silent token burn.

## Gate (hard, in order — stop at the first failure)

1. Read `~/.claude/model-config.yaml` → `frontier_access`. Require
   `active: true` AND today ≤ `end`. If closed: report it, offer a degraded
   panel on `fallback` (label every finding as fallback-tier), stop otherwise.
2. Require the eval track — the `Agent` tool `model: "fable"` override only
   resolves on CC ≥ 2.1.170 (`claude-next` / `claude-fable`). On the stable
   track: report and stop.
3. **Print cost before spawning — do not await approval**: Fable 5 = $10/$50
   per MTok ≈ 2× Opus, drawn from the 5-hour plan windows. Estimate the band
   (N agents × 150-250K context) and print it. Consent is the bounded-autonomy
   policy itself (CLAUDE.md § Frontier Tier Routing) — the printed number is
   the audit line, not a question. Respect `frontier_discovery_budget`:
   blocking-inline ≤ `inline_blocking_max`; batch only at/above
   `batch_min_open_holes`; the gate hook hard-blocks past
   `max_fable_spawns_per_session` — a blocked spawn means PARK the hole, never
   retry.
4. **Lock before spawning**: flip each selected hole to `IN-PANEL <date>` in
   the ledger BEFORE the Agent calls (concurrent-session double-spend lock).
   A hole already `IN-PANEL` is someone else's spend — skip it.

## How the frontier model starts (mechanics)

- **The lead session NEVER changes its own model.** The lead (typically Opus
  4.8) stays put and spawns panelists; each `Agent` call carries the call-time
  `model: "fable"` override. Fable runs as fresh-context subagents — also the
  cost design: a panelist bills only its brief + its own tool calls at
  frontier rates, never the lead's accumulated session history.
- **Never `/model`-swap a live session to Fable.** Prompt caches are
  model-scoped, so a mid-session switch reprocesses the entire conversation at
  uncached frontier input rates — the most expensive possible start — and a
  context-soaked lead is the opposite of baseline-blind. (The `/model` picker
  can also write a sticky model pin into the shared settings.json — the exact
  default-pin this design exists to prevent.)
- **Interactive multi-turn depth on ONE hole** (human in the loop) is the
  `claude-fable` launcher instead: fresh session, Fable lead. The ledger entry
  IS the hand-off — open with "work H-NNN from docs/research/FRONTIER_HOLES.md".
- **Not Agent Teams.** Discovery is read-only research → subagents. Teams
  enter only downstream, implementing confirmed findings, where
  `teammate_frontier` may pin a Fable teammate per-member (eval-track only).
- **Panelist effort = the lead's live effort, by construction.** In-process
  spawns have NO per-spawn effort surface (binary-verified 2.1.170: AgentInput
  has no effort field, frontmatter `effort` unparsed — GH #25591/#25669/#31536/
  #65598 open). From an Opus@max lead, panels run Fable@max: an accepted,
  BOUNDED premium (CursorBench $18-vs-$15 band/task, capped by the spawn gate).
  Do NOT ask the user to `/effort`-dip around a wave, and do NOT shrink the
  panel to compensate. If a session is already at ≤xhigh, fine — but effort is
  never a reason to defer a blocking-wall escalation.

## Select the work

- **Mode A (default — ledger)**: OPEN holes from `docs/research/FRONTIER_HOLES.md`.
  One baseline-blind agent per selected hole (order by `Confidence: high` first;
  K comes from the decomposition, not a default cap), plus 1 negative-space
  agent: *"what seam is nobody watching? List 3 with reasons."*
- **Mode B (proactive sweep)**: target = the ledger's **Seam Registry**, ranked
  stale-sweep × churn × exogenous trigger — but each BRIEF stays baseline-blind:
  pass the seam NAME + component globs only, never the registry's history or
  prior findings (targeting is the lead's job; anchoring kills the yield).
  Reserve **~30% of every sweep for registry-BLIND fresh derivation** — the
  registry cannot list seams nobody has enumerated, and registry-only targeting
  systematically misses new seams and low-churn code under exogenous change.
  Agents DERIVE failure modes top-down per memory
  `feedback-frontier-window-baseline-blind-derivation-2026-06-09` and read code
  only to confirm/refute. Panels are READ-ONLY: the LEAD applies all registry
  updates after returns, recording swept-DEPTH + verdict, never just a date.

## Brief discipline (each rule was paid for on the 2026-06-09 panel)

- **READ-ONLY, say it verbatim** in every brief — research subagents are blocked
  from file-writes; a write attempt wastes the slot.
- **Baseline-BLIND**: never paste known findings, worklists, or prior reports
  into discovery briefs. Anchoring turns a discovery panel into an evidence
  sweep that only finds what is already written down. Lead reconciles after.
- **grep-first, ≤400-line read windows** — long inlined context kills agents
  with "Prompt too long".
- Route via `Agent` tool, `subagent_type: "frontier-derivation"`
  (`~/.claude/agents/frontier-derivation.md` — baseline-blind method baked
  into the subagent's own system prompt), call-time `model: "fable"` per
  `~/.claude/rules/research-subagents.md` frontier routing. If the agent type
  is unregistered (fresh session before restart), fall back to
  `subagent_type: "deep-research"` with the method spelled out in the brief.
  Adversarial slots keep their ≤500-token verdict cap.

## After returns — the reconciliation that makes it worth 2×

1. **Reconcile against everything you hid from the agents**: diff findings vs
   prior runs, docs, and the ledger. Tag each finding:
   - `CONFIRMED` — independently re-derived something already known. That is
     convergence evidence (confidence ↑), not a discovery. Tag honestly.
   - `NEW` — the frontier delta. This is what the window was for.
   - `REFUTED` — a hole or assumption the panel killed.
2. **Falsify before you file**: every panelist returns 3-5 falsifiable runtime
   predictions — run the cheap probes (Bash load probe on a staging tenant,
   targeted property test, telemetry query). A missed prediction is a defect
   in the system MODEL itself — derivation can only confirm a wrong model, so
   a probe miss outranks every code finding: open a hole on the model error.
3. Write the dated report to `docs/research/` and update ledger statuses
   (`OPEN` → `CONFIRMED-BY-PANEL` / `REFUTED` / `SOLVED-PATH-KNOWN` /
   `ESCALATED`), moving closed holes to `## Resolved` with one-line provenance
   (panel date + verdict). Route emitted CAMPAIGN/GENERATOR candidates to the
   ledger's `## Campaign Candidates` (curation lives in `/frontier-campaign`,
   never inline here). Update Seam Registry rows (depth + verdict). INTEGRATE —
   never overwrite history.
4. **Report back**: what the frontier model saw that the default tier was blind
   to (NEW), what it merely confirmed (CONFIRMED), what it killed (REFUTED), and
   the cost actually spent. If NEW is empty two runs in a row, say so — that is
   the signal to stop spending the window on sweeps and leave it for holes.

> **Long async batch (user not watching):** when a verbatim send-to-user tool is
> available (`SendUserMessage` — 2.1.170 + the `mid-conversation-system-2026-04-07`
> beta; not exposed in every session), emit each panel's NEW/CONFIRMED/REFUTED verdict
> line through it AS the panel lands (`status: proactive`), so findings surface mid-run
> instead of only in the final report. It carries progress, never the deliverable — the
> dated `docs/research/` report + ledger update remain the real output (the harness's own
> rule: "do NOT use SendUserMessage to deliver your answer").

---
name: frontier-campaign
description: Curate and run a long-horizon frontier CAMPAIGN — a generator-class unsolved problem (one solution that dissolves ≥3 named worklist items) or a capability-ceiling build — with Fable 5 as bounded ARCHITECT/JUDGE over default-tier implementer teammates. AGENT-INITIATED for curation/spec under the bounded-autonomy policy; LAUNCH additionally requires the Sonnet red-team gate to pass and the SSOT concurrency cap (max_concurrent_campaigns). Use when a panel or wrap-up emits a campaign candidate, the user says "/frontier-campaign" or "promote C-NNN", or a ledger candidate sits unproven. NOT for bite-sized holes (/frontier-run), routine implementation (Agent Teams directly), or anything already on a worklist with a known path.
---

# frontier-campaign — long-horizon frontier work, structured so it survives

The frontier tier's headline capability is long-horizon work — but its edge is
**reasoning depth, not typing endurance**. A multi-hour autonomous Fable
implementation monolith re-creates every documented teammate context-crash at
2× price. So the campaign shape is: **Fable thinks in bounded phases; the
default tier implements; the lead acks between phases.** The harness supplies
the horizon.

## 1 — Curation gate (default-tier work; no Fable tokens yet)

A candidate (C-NNN in the ledger) passes only with ALL of:

- **Genuinely unsolved**: not on any worklist/plan with a known path. Check
  semantically (grep is insufficient — the 2026-06-09 panel re-derived ~7
  known findings that text-match missed). Cite what you checked.
- **Long-horizon**: ≥2 sessions / architecture-level; a ≤300-LOC fix is a hole.
- **Generator value PROVEN, not vibed**: ≥3 *named* worklist/ledger item IDs,
  each with one line — "becomes a no-op because…". Grandiose dissolve-counts
  with no named items are the signature of a fake generator. These named
  dissolutions become the done-rubric's acceptance criteria.

Then the **red-team gate — BEFORE any frontier spend**: one `general-purpose`
Sonnet agent, ≤500-token verdict, default-to-refute: *"Argue this candidate is
fake-generator / already-solved / not-long-horizon."* Survives → `REDTEAMED`.

## 2 — Spec (the full up-front specification; Fable architect, bounded)

One Fable architect session/spawn (counts against the spawn cap) produces
`docs/plans/CAMPAIGN_<slug>.md`:

- Problem, why-unsolved, and the dissolution list as acceptance criteria.
- Phase decomposition with interface contracts; per-phase sizing within
  agent-teams limits (≤300 LOC out, ≤2,000 LOC read per teammate).
- **Campaign budget + abort rubric (mandatory)**: total token band, wall-clock
  cap, and the tripwires — *no new commit in 45 min; any teammate context
  >40%; a phase failing lead-ack twice* → checkpoint + ABORT to lead with a
  one-paragraph state report. Window-end mid-campaign = checkpoint, then the
  architect role degrades to `frontier_access.fallback` or the campaign pauses.
- Ledger status flow: `CANDIDATE → REDTEAMED → SPEC'D → RUNNING(branch) →
  LANDED / ABORTED(reason)`. Governance is this status — the per-session spawn
  cap cannot see a multi-session campaign; the ledger can.

## 3 — Execution (Agent Teams, standard discipline, tiered models)

- **Fable = architect/judge only** (`teammate_frontier` slots): phase specs,
  interface contracts, phase-gate reviews. Bounded, judgment-dense spawns.
- **Per-teammate effort is set at worktree setup, not at spawn**: run
  `~/.claude/scripts/set-teammate-effort.sh <worktree> high` (xhigh for the
  capability-sensitive architect/judge members) BEFORE spawning — teammate
  panes re-resolve their worktree's `.claude/settings.local.json`
  (binary-verified 2.1.170; the lead's effort is not forwarded). Without the
  override, panes resolve the user-settings floor (xhigh).
- **Implementers = default tier** (Opus 4.8 teammates): worktree-isolated,
  ≤150-line briefs pointing at pre-greped SPEC SECTIONS (never "read the whole
  spec"), "stop on issue, message lead" verbatim, checkpoint per phase.
- **Lead (Opus) orchestrates**: explicit ack between phases; monitors commit
  cadence against the abort rubric; merges per standard team merge loops.
- **Surface phase verdicts verbatim**: when a send-to-user tool is available
  (`SendUserMessage` — 2.1.170 + `mid-conversation-system-2026-04-07` beta), emit each
  phase-gate verdict + commit-cadence-vs-abort-rubric status through it as the phase
  closes (`status: proactive`). A multi-session campaign the user isn't watching should
  report progress mid-run, not only at the final scorecard.
- Concurrency: `max_concurrent_campaigns` (SSOT) — default 1. A second
  candidate waits; it does not queue a second team.

## 4 — Close

Final report = the **dissolution scorecard**: which named acceptance items
actually became no-ops (verified, not asserted), cost spent vs budget, and
what the campaign surfaced for the ledger (new seams, holes, candidates).
`LANDED` only when the scorecard is verified; anything less is `ABORTED` with
the reason — an honest abort is a cheap outcome, a fake LANDED poisons the
next curation gate.

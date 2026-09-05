---
name: plan-conventions
description: >-
  Conventions for writing and updating PLAN documents so decisions accumulate losslessly across sessions. Load when creating or editing a plan / design / roadmap doc (the backup-before-write hook also auto-injects an abridged form on plan-file edits; this skill is the full version). Rules: INTEGRATE new content, never overwrite or delete existing sections; COMPLETED sections → compact to key learnings + commit hashes + blockers (drop granular step detail); UPCOMING sections → expand with file paths + line ranges + decision context + trade-offs; the MANDATORY Phase 0 rule — any plan with 2+ code-writing tasks MUST include Phase 0 (Agent Team Orchestration) as the FIRST section, declaring per wave its EXECUTION LOCUS (S = dispatched handoff session, the DEFAULT · T = in-session teammates · L = lead-inline; T and L each need one line of justification, S needs none) plus team roster + roles, task dependency graph with blockedBy, worktree/branch assignments, spawn-wave order, and the LEAD's own context budget + succession point; NEVER delete historical decisions, "Why:" rationale, learnings, or known issues (they compound in value). Triggers: "write a plan", "update the plan", "add a phase", editing a *plan*.md / design doc / .claude-plans/ file, Phase 0 orchestration. Companion to the plan-update skill/command (the mechanical applier) — this skill is the RULESET + rationale, not the editor.
---

### Plan Document Conventions (CRITICAL — All Agents)

Plans accumulate decisions across sessions. Always INTEGRATE updates using these patterns.
The `backup-before-write.sh` hook auto-injects these rules on every Write or Edit to plan files.

**This skill is the SSOT for the plan RULES.** The `plan-update` skill (also `/plan-update`) is the
mechanical applier — workflow steps, compaction/expansion templates, the Phase 0 scaffold — and it
cites these rules rather than restating them. Until consolidation audit 02 both files carried their
own copy of the ruleset and the two had drifted in wording; if a rule needs to change, change it
here.

**Completed Sections → Compact**

Mark DONE. Collapse to key learnings, commit hashes, and blockers only. Remove granular
step-by-step implementation details that are no longer needed. Example:

```
### Phase 5: Widget Schema — DONE (`abc123`, Mar 15 2026)
- Added widgetType + description columns. Migration 0045.
- Key learning: bare integer() needed for defaults (not timestamp_ms mode)
- Blocker resolved: pre-commit hook required staged migrations
```

**Upcoming Sections → Expand**

Comprehensive implementation detail — file paths with line ranges, decision context,
trade-offs, constraints. These sections are the working blueprint for the next session.

**Phase 0 Rule (MANDATORY — Agent Teams Default)**

**Agent Teams are the DEFAULT for all implementation work.** Any plan with 2+ tasks that
write or modify code MUST use Agent Teams and include Phase 0 as the FIRST section.
Only use background subagents for research/exploration (no code changes) or 50+ parallel
read-only tasks. The user expects 9/10 implementation sessions to use Agent Teams.

Phase 0 MUST include **Agent Team Orchestration**:
- **Execution locus per wave** — WHERE each wave runs (table below). FIRST field: it decides whose
  context pays for the wave, which every other field then assumes.
- **Task SIZE per unit** — the band each unit's brief is written to (table below). SECOND field, and
  measured to be worth **14× more than the locus**.
- Team size and roles (which agents, what each does)
- Task dependency graph (`blockedBy` relationships)
- Worktree assignments (branch names, isolation strategy)
- Spawn wave order (what runs in parallel vs sequential)
- **Lead context budget + succession point** (below)

This ensures parallel work is architected before implementation begins.

**Task size — declare a BAND, and it outranks the locus by 14×.**

A plan declares WHERE a unit runs and never HOW BIG it is, and size is the larger lever by an order
of magnitude. Measured over 1,664 units (`docs/research/workflows-vs-teams-2026-08-20.md` §3d):

| unit output | n | out/pp | med lifetime | med turns | med files |
|---|---:|---:|---:|---:|---:|
| 0–2K | 172 | 2,250 | 11 min | 26 | 1 |
| 20–40K | 304 | 49,986 | 17 min | 36 | 2 |
| **40–80K** | 567 | **61,168** | **32 min** | **60** | **3** |
| **80–150K** | 557 | **58,454** | **73 min** | **107** | **6** |
| >300K | 64 | 32,341 | 773 min | 310 | 15 |

**Spread across size bands: 27×. Spread across vehicles at matched size: 1.9×.** So the rule that
decides a wave's efficiency is not *"teammates, not workflows"* — it is **one task per unit,
40–150K output tokens wide, never below 20K, split above 300K or 10 files.**

Write the band into Phase 0 as a target a brief can be checked against: **40–150K output ≈ 30–75 min
≈ 60–110 turns ≈ 3–6 files.** Teammates today sit at a median of **36,848** output tokens — under
the peak band, so re-sizing existing briefs into it is **~+19% quota efficiency at zero risk and no
rule change**. Under-sizing is the common error, not over-sizing: the 0–2K band returns 2,250
out/pp against the peak's 61,168, a 27× loss on units that look cheap because each one is small.

⚠️ The band is a SIZING target, not a licence to widen scope. It sits beside — and never overrides —
the brief-discipline caps the **agent-teams** skill owns (≤150-line brief body, reading list ≤5
files, split any deliverable >500 LOC). A unit reaches the band by carrying ONE task that is
genuinely that large, never by bundling two.

**Execution locus — the DEFAULT is a dispatched SESSION, not a teammate.**

Parallelism has TWO units, not one, and Phase 0 named only the smaller one until 2026-08-07. Both
are fan-out; they differ on the axis that decides a long-horizon plan's outcome — **whose context
absorbs the work**.

| Locus | Mechanism | Whose context pays | Use when |
|---|---|---|---|
| **S · dispatched session** (DEFAULT) | `handoff-fire.sh --prompt-file <brief> --worktree <br> --notify-back <lead-uuid> --goal '<measurable end state> — proven by <the command the session runs and prints>; do not <constraint>'`, lead arms `cc-await-ping` in background | the CHILD's — the lead pays only for the brief it wrote and a one-line completion ping | **every implementation wave.** Needs no justification. |
| **T · teammates** | `Agent({name, …})` in-session | the LEAD's — every teammate report, shutdown exchange, and the whole merge loop land in the lead's window | members must be synthesised against each other *immediately* AND their combined output is small |
| **L · lead-inline** | the lead edits the files itself | the LEAD's, in full | the wave is ONE file's control flow and is genuinely unsplittable (precedent: `docs/plans/SESSION_LIFECYCLE_V2.md` — *"lead-only, no teammates … disjoint file ownership is unconstructible here"*) |

**`--goal` is part of the S recipe, not an extra** (2026-08-09). One measurable end state per wave,
with the check that proves it and the constraint that must hold — because the goal evaluator is a
separate TOOL-LESS model judging only what the session PRINTS. *"Wave 3 is done"* is unjudgeable;
*"`bats tests/x.bats` prints 0 failures"* is not. A goal dies with its session, so a wave that
recycles must re-arm it. Full rule + template: `commands/handoff.md` § Autonomous fire item 1.

**T and L each need ONE line of justification in the plan. S never needs a reason.** Naming the
locus is mandatory even when it is S: an unnamed locus resolves to L in practice, because writing
the code is what a lead does when nothing told it not to.

**Why S is the default — a mechanism, not a preference.** The lead's judgment is the scarcest
resource in a long-horizon plan and its quality falls as its context fills. Locus T — the *only*
delegation unit Phase 0 mandated before this rule — routes every teammate's output back INTO the
lead. So a plan that obeyed the Agent-Teams rule perfectly still spent the lead's window on
implementation detail it would never need again: **delegating harder made the protected thing
worse.** S is the only locus where fan-out and lead-context preservation point the same way.

**Lead context budget + succession point (MANDATORY).** Before 2026-08-07 the only `Context Budget`
section in the plan surface budgeted the *teammate* at 1M tokens with "Free buffer 500K+ · Unlikely
to hit context limit", and the lead — which absorbs every wave — had no row at all. State both:

- **Reserved for leading** — the share of its window the lead will not spend on implementation
  (default: hold ≥50% for decisions, per CLAUDE.md § Context Stewardship).
- **Succession point** — the wave boundary at which the lead recycles
  (`handoff-fire.sh --recycle`) instead of continuing. A multi-wave plan naming no succession point
  is silently asserting one session carries every wave. Existence proof that it does not: session
  `076a1186` (19 named teammate spawns, 3,413 transcript rows) answered the operator's *"you're
  going to run out of context"* with `Prompt is too long` and died in place. That is one incident,
  not a rate — 5 of the 8 recorded wall-deaths had zero spawns (`docs/plans/CONTEXT_ECONOMY_V2.md`
  §1.1) — so the argument for S is **judgment quality throughout**, not wall-avoidance alone.

**Never delete**: Historical decisions, "Why:" rationale, learnings, or known issues.
These compound in value across sessions and inform future decisions.

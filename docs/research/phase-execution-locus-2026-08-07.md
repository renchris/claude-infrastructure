# Why per-phase dispatched sessions were not the default — and what now makes them one

**Date**: 2026-08-07 · **Trigger**: operator question — *"each implementation phase should be a
separate handoff session so the main session's context stays for leading; investigate why this isn't
the default and what we need to do to make it the default."*

This is the **measurement** behind the rule. The rule itself is in
`skills/plan-conventions/SKILL.md` § Execution locus (SSOT) and `CLAUDE.md` § Agent Teams
Reinforcement. Do not restate the rule here — it perishes; this file holds only the evidence.

---

## 1. The answer in one line

Phase 0 answered **"who does the work"** and never **"where does it run"**, so the only delegation
unit it ever mandated — in-session teammates — is the one that routes every teammate's output back
into the lead's own context. **A plan could obey the Agent-Teams rule perfectly and still burn the
lead's judgment.** Delegating harder made the protected thing worse.

## 2. Three findings, each independently verified

### F1 — The spec was SILENT, not wrong (audit of the whole plan-authoring surface)

`skills/plan-conventions/SKILL.md:42-48` prescribed exactly four fields: roles, `blockedBy` graph,
worktrees, spawn-wave order. All four are in-session teammate constructs. Across
`plan-conventions/SKILL.md`, `plan-update/SKILL.md`, `agent-teams/SKILL.md`, `CLAUDE.md § Plan
Document Conventions`, and all three plan hooks, the count of statements about *the lead's context
budget*, *running a phase in a separate session*, and *dispatching a phase to `/handoff`* was
**zero**. Not contradicted — absent.

Two corroborating details:

- The one `Context Budget` section in the corpus (`plan-update/SKILL.md`, pre-change) budgeted the
  **teammate** at 1M tokens with *"Free buffer 500K+ · Unlikely to hit context limit"*, and gave
  intervention rows for teammate context at 75%/90%. The **lead — which absorbs every wave — had no
  row at all**, while the same scaffold prescribed a `**TOTAL** ~4–5 hours` single-lead sitting.
- The closest the corpus came to the idea was an **analogy**: `commands/handoff.md:369` calls a
  handoff wave *"the session-level analog of an Agent Teams wave"*. The link was one-directional —
  `/handoff` **reads** plans; plans never **emitted** handoffs.

### F2 — The machinery already existed and was never wired to plans

`scripts/handoff-fire.sh` already supports the entire loop: `--prompt-file` carries an arbitrary
verbatim brief; the non-recycle path leaves the **caller alive**; `--notify-back` + `cc-await-ping`
close the completion loop; `--worktree` isolates; `--account auto` ranks by live quota.
`commands/handoff.md:34` Mode C is *"FORK while this session KEEPS WORKING"*. So the answer to *"can
a lead dispatch a phase today?"* was already **yes** — nothing was missing but the instruction to
do it.

Real gaps that remain (filed, not fixed here):

1. **No per-phase brief builder.** The only composer (`bin/cc-dispatch:1088-1097`) is
   backlog-item-shaped. The lead hand-writes `/tmp/fire-<phase>.txt` every time.
2. **Plan→work granularity is one item per PLAN, not per phase** (`bin/cc-discover:183` emits a
   single *"advance \<plan title\>"* candidate). No autonomous route from a phase into the dispatcher.
3. **The completion callback is voluntary compliance** — `--notify-back` appends *English
   instructions* telling the child to run `cc-notify`. Already tracked as task #54 (*make the wake
   path MECHANICAL*) and #127 (`cc-await-ping` exit 144).

### F3 — Enforcement pointed at the wrong act

`hooks/agent-teams-enforce.sh` binds **matcher `Agent` only** — it cannot fire until the lead has
*already decided to delegate*. A lead that opens `Edit` on a source file and writes the phase by
hand hit **zero** delegation logic. The three PreToolUse `Write|Edit|MultiEdit` hooks gate on backup,
directory boundary/worktree lease, and MEMORY.md bytes — none reads a plan or a delegation decision.

And **no PreToolUse hook anywhere keys on context fill**: all 13 registered ones return zero matches
for `used_pct`/`context_pct`/`CONTEXT_FILL`. Context fill is read only by `waiting-recycle.sh`
(PostToolUse, after the call — and its only teeth, the Stage-2 exec, ship **SHADOW by default**) and
`boundary-handoff.sh` (Stop, after the turn, one-shot latched). There is no refusal on that axis.

> This is the `enforcement-must-live-at-the-chokepoint` memory recurring. That lesson **was**
> implemented — `hooks/lib/memory-index-budget.sh` is a real PreToolUse deny — but only for
> MEMORY.md bytes. It was never carried across to the context-fill axis or the delegation axis.

## 3. The empirical ratio

Census method: scan of `Agent` tool_use records across **2,816 deduped session transcripts** (2,372
spawns; 1,581 named), cross-checked against branch existence, `teammate-checkpoint.log`, and commit
attribution from `~/.claude/logs/bash-execution.log`.

**Of 12 sampled multi-phase plans with an execution record, exactly ONE dispatched its phases to
separate full sessions** — `docs/plans/GROUND_UP_DISPATCH.md`, and that is a campaign *coordinator*
whose "phases" are whole subsystem rebuilds. **11 of 12 kept implementation inside a single lead
session**: 7 via in-session teammates, 5 with the lead writing the code itself.

Two secondary findings that matter more than the ratio:

- **"Phase 0 says teammates" is ~60% predictive, not 100%.** Three sampled rosters were written and
  never spawned (`cap-qos/readout/leak`; `TERMINAL_AGNOSTIC_L3_L4` T1–T4; all of
  `CONCURRENCY_PROGRAM.md`, whose branch is 0 ahead / 58 behind). One that *was* spawned
  (`t2-guard`/`t3-alarm`) got **none** of the worktree isolation its Phase 0 table promised —
  `teammate-checkpoint.log` shows both checkpointing in the *lead's* tree.
- **The "lead" is a chain, not a session.** `TERMINAL_AGNOSTIC_L3_L4`'s 22 plan-cited shas resolve to
  6 sessions; `DEPLOY_LANE_GROUND_UP`'s 31 to 16. Work is already carried by successive
  recycled sessions — **none of which corresponds to a phase**. The succession was happening
  anyway, unplanned, at whatever moment the context ran out rather than at a wave boundary.

## 4. The incident — and its honest bound

Session `076a1186` (19 named teammate spawns, 3,413 transcript rows, two days) answered the
operator's queued *"youre going to run out of context 1% left"* with `Prompt is too long` and **died
in place**.

**Do not overread it.** Re-derived fleet-wide with an exact normalised match on a bare assistant
`prompt is too long` (a loose grep inflates 7→18 by matching prose *about* the error): **8 sessions,
11 events**, and **5 of the 8 had zero Agent spawns**. Per `docs/plans/CONTEXT_ECONOMY_V2.md`
§1.1/C4/C7, 39/39 fleet compactions are `trigger:"manual"` and 6 of 7 wall-killed sessions had zero
compactions. So the wall is **not** specific to fan-out leads, and nothing rescues a session at it.

**The argument for locus S is therefore judgment quality throughout, not wall-avoidance.** The wall
is the visible tail of a distribution whose body is silent: decisions made at 80% fill that would
have been made better at 30%, which leave no error message.

A second, differently-shaped incident is on record — `GROUND_UP_DISPATCH.md` § INCIDENT
2026-07-29T19:04Z: a lead died mid-wave with **5 assignees still working**; `gu5-decide` held ~518
uncommitted insertions; a resume restored the session but **not the team channel**
(`No agent named 'gu5-decide' is reachable`). That failure mode is a property of the *in-session
teammate* topology specifically — a dispatched session's work survives its parent.

## 5. What was already known, and why it did not land

`docs/proposals/C00-SECTION-8-TEMPLATE.md:3-12` **already diagnosed this exactly**, naming root
cause R4 from `docs/research/W0-W3_INTERVENTION_AUDIT.md` §5:

> *"C00 specifies the teammate layer rigorously; the session/lead layer was improvised live."*

and then explicitly scoped the session layer **out** of the global spec (*"§8 ≠ Phase 0 … it lives
in the per-build spec, not a global rule"*), leaving it a proposal in `docs/proposals/` that nothing
reads at authoring time.

This is the `conclusion-must-reach-the-enforcing-store` memory, verbatim: a correct analysis written
to an **advisory** store, behind a diode, where no behaviour reads it. The remedy is not a better
proposal — it is that the change lands in the stores that are actually read when a plan is authored:
the `plan-conventions` skill (SSOT), the resident `CLAUDE.md`, the two PreToolUse injectors, and the
PostToolUse lint. That is what this change does.

## 6. Known limits of the fix as landed

- The locus lint is **PostToolUse advisory**, not a block. It fires *after* the plan is written and
  can be ignored — the same weakness class that made the advisory-only `waiting-recycle` fire
  **0 times in 2,419 opportunities**. It is placed where the existing Phase 0 rail already lives, and
  it is a *grep for a declaration*, so it cannot verify the declared locus was honoured.
- **Nothing yet gates the act itself**: a lead that starts editing implementation source while an
  open plan has undispatched waves still meets no hook. That is the real chokepoint (per the
  memory-index precedent, a PreToolUse deny on the *act's own tool call*), and it is the follow-on
  worth building — with care, since false positives would block legitimate lead edits.
- The locus regex accepts any of `Execution Locus|locus S|dispatched session|handoff-fire|lead-inline`.
  A plan can satisfy it by naming a locus it does not follow. Declaration ≠ compliance.

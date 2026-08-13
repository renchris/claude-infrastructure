---
status: open
---

# MASTER: operator-gated — the rows no agent session can discharge

**Condition key:** `master-operator-gated` · **Live members 2026-08-12 (measured after the apply):** 25 (23 blocked · 2 open)
**Inventory:**
`cc-backlog list --all --json | jq -r '.[]|select(.condition=="master-operator-gated" and .status!="done")|"\(.id) \(.status) \(.title[0:90])"'`

🚨 **THIS IS NOT A WORK WAVE, AND THAT IS THE POINT.** Every other `master-*` file describes work an
agent does. This one collects the rows whose next step is a credential, a GUI click, a physical act,
or a value judgment that is the operator's to make — and its deliverable is a *rendered batch*, not a
diff. It is grouped for the opposite reason to the others: not so one session can work them, but so
**no session is ever fired at them at all.** 42 rows that each look dispatchable, and each of which
would burn a slot to discover it cannot act.

**Why the classifier routes on WHO CAN ACT before WHAT IT IS ABOUT.** A row reading *"Amplify console:
connect branch 'release', disconnect auto-build on main"* is about deployment, but no agent has that
console. Routing it by subsystem puts it in a wave that can only skip it. The operator gate is prior
to the subsystem for the same reason it is prior to the repo.

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
| **O1 · demote the false positives** | **L** (lead-inline) | every row an agent COULD do is re-keyed out of this group | — |
| **O2 · render ONE batch** | **L** (lead-inline) | the surviving rows reachable as one `cc-do` batch + counted `👤` line | O1 |
| **O3 · the standing renderer** | **S** | new operator-only rows join this group at FILING time, not by a sweep | O1 |

**O1 and O2 are lead-inline** because both are judgment over one store with no code to write, and the
judgment is exactly "can an agent do this" — which the agent doing the reading is best placed to
answer. O3 writes code and is dispatched.

**Lead context budget:** this wave is cheap; hold nothing special. **Succession point:** none — O1+O2
are one sitting.

## Sub-waves

### O1 · Demote the false positives — the honest half
An operator-only step **is not an escape hatch from work the agent could have done.** The test is
strict: file it as the operator's only if the agent *genuinely cannot* — credentials, a GUI-only
action, something physical, or a value judgment that is theirs. For each member, ask which. Suspected
demotions in today's membership, to be checked one by one rather than assumed:

- `arm the fleet inbox by construction: run the c10 migration …` — a migration an agent can run.
- `install.sh:342-344 persists a $HOME-DERIVED ABSOLUTE PATH …` — a code fix, not a decision.
- `re-link any Claude account whose CLI→GitHub link is missing` — may be scriptable per account.

Demote with `cc-backlog link <id> --condition <other-master> --force` and say why in the same breath.

### O2 · Render ONE batch, never a wall of commands
The rules are already settled and live in code, so this wave calls the renderer rather than
re-inventing it: `hooks/operator-readout.sh --render` renders the block from disk truth; `cc-do`
prints the runnable steps, confirms once, and runs them in irreversibility order; judgment items are
COUNTED, not itemised. A numbered wall of four-line commands is the defect that replaced.

Two populations inside the survivors need different treatment:
- **runnable** (a command exists) — file with `cc-backlog needs "<step>" --run "<cmd>"` so `cc-do`
  can drive it;
- **judgment** (a value fork: ⌘E binding, which bottle menu, whether the launchd dispatcher runs with
  `CC_FIRE_CLOUD=on`) — these are `cc-decide` packets, and an open class-C packet is what makes a
  close read `⛔` instead of `✅`.

### O3 · Fix it at the source
Every row here was routed by a regex over its title AFTER the fact. The producers should key it at
filing time: a generator that knows it is emitting an operator step files it with
`--condition master-operator-gated` itself. Enforcement belongs at the chokepoint, not in a sweep.

## Definition of done
Every member is either demoted (an agent can do it, and it is re-keyed to the wave that will) or
reachable by the operator in ONE batch — `cc-do --list` shows the runnable ones and the judgment ones
are counted class-C packets. No dispatch session is ever fired at this condition.

## Status log
- **2026-08-12 — created by W2 of `BACKLOG_SELF_DRAINING_2026-08-12.md`.** 42 rows joined by
  `group.py`, whose first taxonomy rule is this one. 41 of 42 are already `blocked`, which is
  corroboration rather than coincidence: the fleet had discovered the gate one row at a time.

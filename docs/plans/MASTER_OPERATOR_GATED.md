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
| **O3 · the standing renderer** — **DONE** | **S** | new operator-only rows join this group at FILING time, not by a sweep | — (see below) |

**O1 and O2 are lead-inline** because both are judgment over one store with no code to write, and the
judgment is exactly "can an agent do this" — which the agent doing the reading is best placed to
answer. O3 writes code and is dispatched.

**O3's "Depends on: O1" was wrong and the build proved it (2026-08-15).** The dependency was written
on the assumption that keying at filing time needed the demoted set settled first, so it would not
re-key rows O1 had just moved out. The implementation removes the dependency instead of waiting on
it: the auto-link is **non-force**, so it can only fill an EMPTY condition and a demotion is
structurally safe from it in either order. O1 can now run before or after O3 with the same result.

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

### O3 · Fix it at the source — DONE
Every row here was routed by a regex over its title AFTER the fact. The producers should key it at
filing time: a generator that knows it is emitting an operator step files it with
`--condition master-operator-gated` itself. Enforcement belongs at the chokepoint, not in a sweep.

**Built 2026-08-15 — and the chokepoint turned out to be ONE verb, not N generators.** The wave was
scoped as "teach every producer to key its own rows", which would have been N places to remember and
N places to drift. It is one: `cc-backlog block --needs` is the only way a row becomes
blocked-on-operator, the `--needs` payload is *required* (the verb refuses without it two hundred
lines before it writes anything), and `cc-backlog needs` composes onto that same transition rather
than hand-rolling records. So the membership is knowable at the moment the record is written, from
the record's own required field, and no generator has to know anything. `cmd_transition` links it
there. The two-command path `cc-dispatch` prints into every worker brief — `add`, then
`block <id> --needs "<step>"` — is the same path, so the two cannot drift.

**What it is NOT allowed to do, and why that is the load-bearing half.** The link is **non-force**.
`cmd_link` refuses to re-key a row that already carries a condition precisely because re-keying moves
it out of a group whose lease may be holding a live worker off duplicated work, so this arm can only
ever fill an EMPTY condition. Two consequences, both wanted: **O1's demotions stick** (a row an agent
CAN work, re-keyed out by hand, is never silently dragged back by the next `block`), and a row
already grouped by subsystem stays there and costs ONE line of stderr rather than a re-key. It is
advisory, runs after the append, and fails open in every direction — by the time it runs the
operator's step is already durable, and losing its *group* costs a place in a batch where failing the
transition would lose the *step*.

**`group.py`'s rule 1 stays, demoted to backfill.** It is the only thing that can key the rows filed
before this landed. It is also now the written record of why a regex there was always the weaker
instrument: it can only recover a fact the filer already had, and it mis-recovers by construction —
`--needs "collect the live output of X"` matches the imperative rule and lands correctly, while
`--needs "the operator must paste the key"` matches nothing and is routed by SUBSYSTEM into a wave
that can only skip it, which is the burn-a-slot-to-discover-it-cannot-act this whole file exists to
stop.

**Known consequence, stated rather than discovered later:** `unblock` does not clear the condition,
so a row the operator has discharged returns to the wave still grouped and its siblings serialize
behind one lease. That is not introduced here — it has held for the whole swept population since
2026-08-12 and it is what "N rows sharing one condition cost ONE session" means. Serialized is not
deadlocked (guard (6) refuses only while a sibling is claimed-and-live). A row whose remaining work is
genuinely an agent's is meant to leave by O1's demotion, said out loud, not by a silent side effect
of the operator finishing their half.

`CC_BACKLOG_OPERATOR_CONDITION` names the slug and `off` disables the arm; an invalid slug is a
no-op, never a refused `block`.

## Definition of done
Every member is either demoted (an agent can do it, and it is re-keyed to the wave that will) or
reachable by the operator in ONE batch — `cc-do --list` shows the runnable ones and the judgment ones
are counted class-C packets. No dispatch session is ever fired at this condition.

## Status log
- **2026-08-12 — created by W2 of `BACKLOG_SELF_DRAINING_2026-08-12.md`.** 42 rows joined by
  `group.py`, whose first taxonomy rule is this one. 41 of 42 are already `blocked`, which is
  corroboration rather than coincidence: the fleet had discovered the gate one row at a time.
- **2026-08-15 — O3 DONE** (backlog `4013dda07841`, dispatched to a cloud venue). `cc-backlog block
  --needs` now keys the row into `master-operator-gated` at filing time, non-force; `group.py`'s
  rule 1 is demoted to backfill for the pre-existing rows. Detail and the two design calls that
  matter (one verb rather than N generators; non-force is what makes O1 and O3 order-independent)
  are in the O3 section above. Gate: the direct-clause selection for `bin/cc-backlog` (44 suites),
  differenced against `origin/main` in the same container so the environment's own pre-existing
  reds cannot be read as this change's — the two failure sets are identical. Four new tests in
  `tests/cc-backlog-needs.bats`; three of them RED-proved with `bin/cc-backlog` stashed, the other
  two are absence-assertions and are vacuous by nature (they pin the opposite regression).
- **2026-08-15 — O1 and O2 CANNOT run off-box, and nothing in the classified span said so.** The
  same dispatch fired at a **cloud** venue, and both remaining sub-waves are judgment over the LIVE
  store: `~/.claude/autonomy/backlog.jsonl`, which is $HOME state on the operator's machine and is
  not in the repo. A cloud VM clones the tree, so `cc-backlog list --all` there returns **zero
  rows** — O1 has no population to demote from and O2 has nothing to render. This is a VENUE
  constraint, not an operator gate: the work is ordinary agent work that must run on the box that
  holds the store, so it must not be `block`ed (that would park it behind a human who has nothing
  to do).
  **Why the router could not see it.** `cc-eligible` classifies the item's *specification span* —
  title, dodRef, condition, source — and this row's span is `MASTER: operator-gated — the rows no
  agent session can discharge`. Not one of the BOX spellings (`~/.claude`, `live layer`, `this
  box`) appears in it; the fact that the DELIVERABLE is a fold of a $HOME-resident store lives only
  in the plan BODY, which the classifier deliberately does not read. So the row is off-box-eligible
  by every measurement available to the gate, and wrong.
  **Deliberately NOT fixed here.** Adding a spelling would be a guess at the class from one
  instance, and the right change — do MASTER rows whose deliverable is a fold of the live store
  need a venue class of their own, or a per-row `cc-backlog venue --venue local`? — needs a count
  over the very store this venue cannot read. Naming it beats guessing at it. **Next action: a
  LOCAL session, which is where O1 and O2 were always going to have to run.**
- **2026-08-15 — and the LAND cannot run off-box either, for an unrelated reason.** O3's code is
  committed and pushed to its branch, and `ship-land.sh --precheck` — the land gate's own statics +
  ratchets — was run here and is green on every arm this diff touches: hermeticity, wall-clock,
  AF_UNIX, moving-ref, git-identity, UTC-stamp, pipefail/SIGPIPE, dead-assertion, self-path,
  pane-spawn, permission-gate, TSV, bats-shellcheck, kill-guard, @test-name. Two arms went red for
  reasons that are the CONTAINER's, and each was differenced against `origin/main` in the same
  container before being called that:
  · **shellcheck** — RED under the VM's default 0.9.0 (three SC2119/SC2120 notes on `valid_records`,
    all pre-existing and all present identically on `origin/main`), **clean under 0.11**, which is
    the version `.shellcheckrc` itself documents the gate as running. Not a finding, a version skew;
    worth knowing that the gate's verdict here is shellcheck-version-dependent.
  · **`unattended-path-lint --selftest`** — fails 9 of its 30 assertions, *identically on
    `origin/main`*, because the detector's own fixtures are macOS PATH facts (`/sbin/md5`,
    `/usr/sbin/sysctl`, `/usr/sbin/lsof`). It fails CLOSED and it is right to: on this box its clean
    verdict would mean nothing, so it declines to give one. The land is therefore not refused by
    this diff — it is refused by the box, and no override belongs anywhere near it.
  **So: `/ship` for this work runs from the operator's machine, alongside O1 and O2.** Three
  independent reasons now point the same way, which is the useful part — the venue question for this
  condition is not about any one row.

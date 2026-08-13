---
status: open
---

# MASTER: enforcing store — a conclusion only counts where something enforces it

**Condition key:** `master-enforcing-store` · **Live members 2026-08-12 (measured after the apply):** 34 (22 open · 12 blocked)
**Inventory:**
`cc-backlog list --all --json | jq -r '.[]|select(.condition=="master-enforcing-store" and .status!="done")|"\(.id) \(.status) \(.title[0:90])"'`

**Why this is ONE effort.** Docs and plans ADVISE; only `settings.json`, a launchd plist, a PATH entry,
a registered hook — **and the work ledger itself** — BIND. Every member is a conclusion that exists and
is enforced by nothing: hooks built and never registered, migrations staged and never run, a launchd
label in the user DISABLED list that has never run, a memory index over its loader cap so the index
silently stops loading, and rows in the ledger whose premises have been refuted with nothing reading
the refutation.

**Why the LEDGER belongs in this group rather than an eleventh master.** `cc-backlog` is the store that
makes a *finding* binding. A row whose falsifier can never be attached is the same defect class as a
hook that was never registered: the conclusion is written down and nothing acts on it.

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
| **E1 · config-dir parity** | **S** | the four config dirs stop diverging, by construction | — |
| **E2 · staged → run** | **S** | every built-but-unregistered hook is registered or deleted | — |
| **E3 · ledger integrity** | **S** | a refuted premise and an un-probeable row are both reachable | — |
| **E4 · memory + CLAUDE.md** | **L** (lead-inline) | the index is under its cap; the two CLAUDE.md copies reconciled | — |

**E4 is lead-inline** because it is prose judgment over two files with a human-gated lossy half
(`/compact-memory`'s approval step is a member of `master-operator-gated` — coordinate, do not
duplicate).

**Lead context budget:** ≥50%. **Succession point:** after E2.

## Sub-waves

### E1 · Config-dir parity
`~/.claude-next/hooks` is a FORKED REAL DIRECTORY (53 entries) rather than a link — that fork is the
GENERATOR behind the drift, so fixing entries one at a time re-mints the problem. Account 1 configures
69 hook commands against 74 in accounts 2/3/4; 5 guardrail hooks are missing from `.claude-next`
(unattended-ask guard, session-deregister, …) with migration 0009 written to restore them. 19 skills
live in `~/.claude/skills` with NO tracked source (that row is keyed to `master-account-facts` — its
subject is the four-account fork; coordinate).

### E2 · Staged → actually running
`hooks/goal-inert-watch.sh` has never fired: its registration sits unapplied in staged migration 0005.
`hooks/mailbox-wake-arm.sh` needs a c10 migration to be an asyncRewake SessionStart hook.
`hooks/coldcompile-admit.sh` is unregistered. Staged migration 0007's preflight **refutes its own
header** (asyncRewake is ABSENT from the installed 2.19/2.20 binaries) — so read the preflight before
trusting the header. `com.claude.nightly-regression` has NEVER run from launchd: the label is in the
user DISABLED list. `hooks/task-quality-gate.sh`'s Phase-0 arm is doubly dead (it execs a script
removed in 2026-05).

### E3 · Ledger integrity — the store that makes findings binding
**The 430 pre-existing plan-open rows can never gain a falsifier**, because `add` is idempotent on
project+title+source and returns before writing — the `falsify` verb exists for exactly this and needs
to be pointed at them. `cc-backlog falsify` screens "does the probe pass NOW" but not "did it ALREADY
pass on the day the row was filed", which is the difference between a probe that retracts live work and
one that never should have been stored. ~~`cc-value tasks_closed` folds status as the RAW EVENT
(`bin/cc-value:179-180`), so any non-`done` event reads as a status.~~ **DISCHARGED 2026-08-13** — that
fold now keys status on `done|block|unblock|claim|reopen` and carries status *and* ts through
otherwise, matching the three sibling folds; fixing only the status half was measured to trade the
under-count for a worse over-count (the 241 venue-masked rows would all have read done-today), so both
move together. Rows filed under the wrong project
(code in claude-infrastructure, filed under `reso-management-app`) are unreachable by every dispatch
scoped to their real tree. And three DISPROOF rows sit open with nothing consuming their refutations.

### E4 · Memory index + the two CLAUDE.md copies
`MEMORY.md` is over the loader's read limit — **BYTES bind, not lines** — so the index silently stops
loading, which is the worst possible failure mode for the file whose whole job is to be loaded.
`~/.claude/CLAUDE.md` and `claude-infrastructure/CLAUDE.md` diverge and which side is authoritative is
unruled; the repo's own rule says a resident policy must not restate a perishable fact, so prefer
deleting a restatement over syncing it.

## Definition of done
Nothing in this group is "built but not binding": every hook is registered or deleted, every staged
migration is run or withdrawn with a reason, the memory index is under its byte cap, and the ledger can
attach a probe to a pre-existing row and surface a refuted premise without a human noticing it.

## Status log
- **2026-08-12 — created by W2 of `BACKLOG_SELF_DRAINING_2026-08-12.md`.** 29 rows on this condition
  (4 pre-existing from the 2026-08-09 triage, 5 by its verdict replay, the rest semantic — including
  the ledger-hygiene family that this wave's remit was widened to own).

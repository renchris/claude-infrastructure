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
user DISABLED list. ~~`hooks/task-quality-gate.sh`'s Phase-0 arm is doubly dead (it execs a script
removed in 2026-05).~~ **DISCHARGED 2026-08-15 — the arm is DELETED, and so is the suite that hid
it.** Both deaths confirmed on trunk: death 1 (the `|| true` unreachable rejection branch) was
already cured by `cb6314be`; death 2 was still live — both pointers to `scripts/team/verify-team.sh`
resolved to nothing, so every Phase-0 completion took the else-branch, logged `verify-team.sh not
found — skipping`, and passed. Fail-OPEN on the gate's own precondition. **Deleted rather than
repaired because there is nothing to point it at:** this repo's own
`skills/agent-teams/SKILL.md` § Liveness detection already rules *"No packaged checker exists
(`verify-team.sh` was a ghost pointer, removed 2026-07-18)"* and prescribes a deliberately
NON-script replacement (pull-check the iTerm2 API / osascript on the member's `tmuxPaneId`, crossed
with `teammate-lifecycle.log` + transcript age, and never trust `isActive` as "alive now").
`tests/task-quality-gate-phase0.bats` went with it: it fixtured a FAKE verifier into a temp project,
so its 5 green tests proved the arm could reject a file the test had just written — coverage that
answered "is this gated?" with yes over a gate that could not fire. Its one durable lesson (an
`X=$(cmd || true)` assignment's status is the assignment's, never the command's) is already held by
`docs/research/BATS_DEAD_ASSERTIONS_2026-07-25.md:434` and the `bats-*-lint` family. The surviving
`tests/task-quality-gate.bats` is 10/10. Packaging the *intent* as a real gate is new design, not a
repair — filed as follow-on, not invented here.

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
`MEMORY.md` is over the loader's read limit — so the index silently stops
loading, which is the worst possible failure mode for the file whose whole job is to be loaded.
*(Amended 2026-08-15, backlog `16a60c2431cc`: this read "**BYTES bind, not lines**". There are TWO
caps — Anthropic documents "the first 200 lines or 25KB, whichever comes first" — and which one
binds is a function of density, not a constant: bytes above 124 B/line, lines below it. True of THIS
index at 244 B/line; false as the general rule it was written as, and all three enforcers had
generalized it into code.)*
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
- **2026-08-15 — E2's `task-quality-gate` Phase-0 arm discharged (see the strikethrough in § E2), and
  the venue of this whole MASTER measured.** Worked from a CLOUD container, which turned out to be
  the finding worth writing down: **most of this plan cannot be advanced off-box, and the ledger
  already has the vocabulary to say so** (`cc-backlog venue` / the OFF-BOX ELIGIBILITY gate at claim
  time). Measured absent in the container: `~/.claude-next` and the other three config dirs, `~/.claude/settings.json`, `launchctl`, `~/.claude/MEMORY.md`, any installed CC binary track, and the
  backlog store itself (`list --all` → `[]`). So **E1 is entirely local-only** (its subject IS the
  four-config-dir fork), **E4 is local-only** (both of its files live outside this repo — `MEMORY.md`
  and `~/.claude/CLAUDE.md`; only the repo-side `CLAUDE.md` is reachable, and reconciling one side of
  a divergence is not reconciliation), and **E2's registration half is local-only by construction** —
  those migrations are c10, and c10's whole contract is that it edits `settings.json` and therefore
  *stages and waits for a human*. Also unverifiable off-box: E2's claim that 0007's preflight refutes
  its own header. The preflight (`0007:105-122`) greps installed tracks for `asyncRewake` and REFUSES
  when absent, while the header says it re-read the binary on 2026-08-09 and found it consumed at the
  dispatch call site — with no installed track in the container, neither side can be settled here.
  Read it on the box before trusting either. **What IS off-box-eligible in this MASTER is the code:**
  E2's dead arm (done, this entry) and E3's `cc-backlog falsify` retroactive screen — the
  "did the probe ALREADY pass on the day the row was filed" half, which is `bin/cc-backlog` source
  and needs no machine state. A future dispatch of this condition should route accordingly rather
  than spend a cloud slot on E1/E4.

  **AND THE LAND GATE ITSELF CANNOT PASS OFF-BOX — measure this before dispatching code work here
  again.** `ship-land.sh --dry-run` exits 6 (GATE RED) in a Linux container on
  `unattended-path-lint --selftest: FAILED (12 of 30)`. It is NOT a trunk defect and not the diff's:
  the identical 12/30 reproduces on a pristine `origin/main` worktree with this entry's changes
  absent. The cause is calibration, and it is worth knowing because it will recur on every cloud
  land. The lint reports a bare binary only when it is UNREACHABLE under
  `STOCK_PATH=/usr/bin:/bin:/usr/sbin:/sbin`, and its RED fixtures invoke `shellcheck` and `tmux` —
  which on the operator's macOS live in `/opt/homebrew/bin`, OFF that path, so they are detected and
  the selftest is green. In a Debian container both live in `/usr/bin`, ON it, so the detector
  correctly finds nothing and every "want 1, got 0" fires. The lint is right; the selftest is
  macOS-shaped. Consequence for routing: a cloud session can produce a correct, gate-green-on-its-own-
  diff commit for this repo and still be unable to LAND it, because the land gate fails for a reason
  that has nothing to do with the diff. Treat "off-box-eligible" for claude-infrastructure as
  *eligible to write*, not *eligible to land*, until that selftest is made portable.

  **LEDGER REPLAY OWED — the bookkeeping for this entry could not be written from the cloud.** The
  store is `~/.claude/autonomy/backlog.jsonl`, which is outside this repo and therefore outside the
  container: it was a 0-byte file here and `cc-backlog done 70ec97ddb82b` answered `unknown id`. That
  is a venue limit, not a refusal — the work landed, only its row could not be moved. On the box, replay:

  ```sh
  cc-backlog done 70ec97ddb82b --evidence "<the sha that landed this entry>"
  cc-backlog add --condition master-enforcing-store \
    --title "package the Phase-0 team-verify INTENT as a gate that can actually fire (successor to the arm deleted 2026-08-15)" \
    --dod-ref docs/plans/MASTER_ENFORCING_STORE.md
  ```

  The second row is the follow-on this entry deliberately did NOT invent: the 2026-04-17 incident it
  guarded (Phase 0 complete with zero worktrees) is still real, and the honest portable check is
  worktree PRESENCE for the team, not the iTerm2 liveness pull-check the skill describes. Scoping
  that is design work with a real over-blocking risk — a gate that exits 2 whenever it cannot verify
  would wedge Phase-0 completion in every repo — so it wants its own row, not a rushed arm.

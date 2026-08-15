---
status: open
---

# MASTER: fleet footprint — what the fleet leaves on the operator's machine

**Condition key:** `master-fleet-footprint` · **Live members 2026-08-12 (measured after the apply):** 58 (39 open · 18 blocked · 1 claimed)
**Inventory:**
`cc-backlog list --all --json | jq -r '.[]|select(.condition=="master-fleet-footprint" and .status!="done")|"\(.id) \(.status) \(.title[0:90])"'`

**Why this is ONE effort.** The box is the shared resource every other wave spends, and every member
is a leak in it: 273 worktree dirs on disk against 151 git-registered (122 orphaned, 209 carrying
`node_modules`); 2,363 of 2,428 task dirs holding no task; 4 orphaned research-subagent processes at
~2.4 GB RSS for 16 h 55 m; panes that finished and never closed. The operator feels this wave directly
— it is why their own `handoff-fire` gets refused on load.

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
| **P1 · GC correctness** | **S** | every reaper decision is recorded, and occupancy is never guessed | — |
| **P2 · process footprint** | **S** | orphaned workers and RSS bursts are attributable and bounded | — |
| **P3 · the kill switch** | **S** | a launchd-loaded destructive sweeper has a kill switch and a guard | — |
| **P4 · one-shot cleanups** | **L** (lead-inline) | today's orphaned panes/worktrees actually gone | P1 |

**P4 is lead-inline:** it is a handful of `cc-teardown` / `worktree-gc` invocations whose verdicts must
be read where they are run. Several of its rows are also `master-operator-gated` (a pane only ⌘W can
close) — check that group before doing anything by hand.

**Lead context budget:** ≥50%, and treat P3 as an escalation surface (a destructive sweeper). **Succession
point:** after P1.

## Sub-waves

### P1 · GC correctness — record the decision, never guess the occupancy
`worktree-gc --dispose-landed-dirt` removed 32 directories on 2026-08-11 and wrote **no disposal
record**, so nothing can say what was in them. It also swept an OCCUPIED worktree mid-session
(`close-integrity`, 01:50) because the occupancy oracle read live-ness wrong, and
`recheck_live()` swallows `claude_cwds` so "no live claude" and "lsof could not answer" are the same
answer. That collapse is the defect: **a probe that ACTS on absence must confirm the safe state**
(memory: `probe-that-acts-on-absence-must-confirm-presence`).

Also: landedness must be judged BY PATH and BY CONTENT before deleting anything — commit-landedness is
blind to staged and untracked bytes (memory: `landedness-over-commits-is-blind-to-staged-content`).

**DONE — the disposal record, and the occupancy collapse.** The record half had already landed
(`CC_WTGC_DISPOSAL_LOG` + `log_disposal()` + the warrant oracle + the gitignored blast-radius field);
the occupancy half landed 2026-08-15 in `27d0bcbd`. **The fix is not "handle the error" — it is a
POSITIVE CONTROL**, because the failures that mattered were silent ones (a sandboxed lsof, a seatbelt
denial, a wrong-flavour binary) that set no exit code anyone could trust. `claude_cwds()` now opens
by reading the cwd of **its own pid** — a process it owns, that provably exists and provably has one
— and reports `2` when it cannot. An lsof that cannot answer that cannot answer anyone's, so its
silence about `claude` is not evidence. Three consequences: the startup oracle count is taken from
the ANSWER rather than from `command -v` (a present-but-blind lsof used to satisfy the "cannot prove
idle ⇒ refuse" floor by itself); `recheck_live()` fails CLOSED; and the KEEP line names WHICH
reading it was, because "a session started inside the classify window" and "occupancy UNPROVEN" are
one operational fact apart.

⚠️ **The measurement is the finding: 33 of 83 existing tests went red the moment the control
landed** — a third of the suite had been proving removals over a shimmed lsof that could not see a
single process's cwd. The harness had reproduced the production defect inside itself. `pgrep`'s
stub was the same shape (`exit 0`, no output — a state no real pgrep can emit). *Generalisable:
when a subject reads absence as proof, its stubs must model an instrument that ANSWERS; a stub that
answers nothing certifies every absence for free.* 6 new discriminator pairs guard it — 4 are RED
against the pre-fix subject, and the 2 REMOVE halves are green in both, which is what stops
"removes nothing" from passing as a fix.

**Still open on P1:** the *landedness-by-path-and-content* clause above is already implemented
(`dirt_landed()` reads per dirty path against trunk CONTENT, index included) — no work found. The
2026-08-11 sweep's 32 unrecorded disposals are unrecoverable by construction; nothing can
retroactively say what was in them.

### P2 · Process footprint
4 orphaned research-subagents that cannot ack a `shutdown_request`; the `claude.exe` 4–40 GB
self-burst (54 events / 11 days) with no argv in the historic sampler; the compressor sentinel — the
ONLY guard against the 5-deaths-in-11-days kernel-panic class — running with an actuator that has no
release path (a freeze machine at design-point margins); 2,363 empty task dirs; 21 GB of `/tmp/claude-*`
TMPDIRs. ⚠️ **Orphanhood is not a discriminating signal here** — every backgrounded worker on this box
is ppid-1, so key any alarm on an axis the HEALTHY population lacks (memory:
`orphanhood-is-not-a-discriminating-signal`).

### P3 · The kill switch
`bin/cc-reaper` is launchd-LOADED, runs `git worktree remove --force` (`bin/cc-reaper:635`) and has NO
kill switch. That is the highest-blast-radius unattended actuator on the box. Treat any change here as
an escalation surface: it needs a kill switch, a guard, and a red-proved test before it needs anything
else.

**DONE 2026-08-15 — all three, in that order.** The kill switch is `CC_REAPER_DISABLE` **plus a FILE
half** (`~/.claude/autonomy/cc-reaper.disabled`), and the file half is the load-bearing one for the
same reason `worktree-gc.sh` has two: **launchd inherits no shell environment**, so an env-only
switch would stop the reaper everywhere EXCEPT where it runs unattended — the only place a kill
switch matters. Unset or `0` is the only ENABLED reading (a typo must not leave it armed). It sits
above every seam resolution and the sweep lock, so "disabled" means the program did nothing at all,
and it is a switch on the PROGRAM, not on a leg: the existing `CC_REAPER_GARBAGE` /
`CC_WATCHDOG_CENSUS` switches leave a `sweep --reap` still classifying, tearing down panes and
removing worktrees. It deliberately does NOT swallow a typo'd COMMAND (`sweeep` still exits 2), or
the switch becomes a way to hide a mistake.

The guard is three things, because the blast radius has three shapes:
  · **`--force` is gone.** It shipped here and nowhere else — `worktree-gc.sh` removes on three
    paths and never forces, and its suite guards the SOURCE against it. The tree is proven clean
    four lines above the call, so `--force` overrode nothing but git's own second opinion, on the
    one actuator with nobody to ask. Audit §8-H, now uniform across both reapers.
  · **A per-sweep removal BOUND** (`CC_REAPER_WT_REMOVE_MAX`, default 4; `-1` opts out; anything
    unparseable falls back to the DEFAULT, never to unbounded). Every other gate judges ONE
    worktree, and the failure class this plan exists for is a sweep whose judgment is
    *systematically* wrong — a moved trunk, stale classify evidence. Per-item correctness cannot
    bound that; only a count can. Past the bound it stops REMOVING, not reaping: panes still close,
    directories stay, and a directory on disk is recoverable by definition.
  · **A disposal RECORD** into the SAME ledger `worktree-gc.sh` writes (`actor` tells them apart) —
    P1's lesson applied here, including the gitignored blast radius, which `status --porcelain`
    cannot see and `git worktree remove` deletes anyway at exit 0. That record is the only trace
    those bytes existed.

13 tests, red-proofed: **8 fail against the pre-fix subject**, and the 6 that pass in both are the
discriminator halves (switch OFF still reaps, a raised bound still removes) — without them a reaper
that had simply stopped reaping would pass the whole group.

⚠️ **Found while testing, and it outlives this wave:** `tests/cc-reaper.bats` **cannot run off
macOS**. The fired-peer tenancy check parses `firedAt` with `TZ=UTC date -j -f` (`bin/cc-reaper:577`,
BSD-only); on GNU date it fails, the stamp reads INVALID, and the reap is refused — so **22 of 111
tests red on Linux against an unmodified trunk**, the whole `td_called` family among them, plus the
`ps -o lstart` sweep-lock group and a `date`-vs-`date -u` TZ assertion. The new tests are therefore
built on `handed-off-lead`, which reaches the same teardown → `worktree_cleanup` path with no stamp
and no date parsing, and they pass on both platforms. **NOT filed as a backlog item — this
session had no reachable store** (a cloud VM has no `~/.claude`; `backlog.jsonl` was empty), so
this paragraph is the record, and filing it is an operator step. A suite that can only be checked
on one machine is half a suite, and this one guards the box's most destructive actuator.

### P4 · Today's cleanups
Named panes and worktrees, each with its own row. Do these only after P1 lands the disposal record —
otherwise the sweep repeats the exact defect the group exists to fix.

## Definition of done
Disk and process footprint are bounded by a mechanism, not by a person noticing: every disposal writes
a record, occupancy is proved rather than inferred, the destructive sweeper has a kill switch, and the
worktree/task-dir counts on disk match the registry within a stated tolerance.

## Status log
- **2026-08-12 — created by W2 of `BACKLOG_SELF_DRAINING_2026-08-12.md`.** 49 rows on this condition
  (20 pre-existing from the 2026-08-09 triage, 10 by its verdict replay, the rest semantic).
- **2026-08-15 — P1 and P3 CLOSED (`27d0bcbd`, and this commit).** Both reduced to the same defect
  wearing two costumes: **a destructive actuator treating its own silence as evidence.** P1's probe
  could not tell "no claude is here" from "I never looked", and P3's reaper could not be stopped or
  bounded while acting on that kind of answer. The fix in both is a positive statement rather than a
  handled error — an oracle that proves it can answer before its absence counts; a switch, a bound
  and a record that make the destruction attributable.
  **Learnings worth carrying past this plan:**
  · *When a subject reads absence as proof, its STUBS must model an instrument that answers.* 33 of
    83 `worktree-gc` tests were passing over a shimmed lsof that could see no process's cwd — the
    harness had reproduced the production defect inside itself, and could not have caught it.
  · *An exit code you did not choose is not an answer.* Both `command -v` guards `return 0`;
    `pgrep`'s rc 1 is a finding and rc ≥2 is not. The distinction has to be made by hand, per
    binary, or it does not exist.
  · *Per-item correctness cannot bound a systematic error.* Every gate in both reapers judges one
    directory. A cap on the sweep's TOTAL is a different kind of safety, and the unattended actuator
    is exactly where it is needed.
  **Environment finding, NEEDS FILING (this session could not — no reachable store):**
  `tests/cc-reaper.bats` is macOS-only — 22 of 111 red on Linux against unmodified trunk
  (`date -j -f`, `ps -o lstart`, a TZ assertion). New tests here avoid that path; the existing ones
  still cannot run in CI or in a cloud session, which is where this plan's own work now happens.
  **Not touched:** P2 (process footprint) and P4 (today's cleanups) — both need the operator's live
  box (running processes, real worktree dirs, launchd), and P4 is gated on P1 by design.

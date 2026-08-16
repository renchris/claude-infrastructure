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

#### RULING 2026-08-16 · `ship/backup-*` (~248 refs) — GC the CARRIED subset, keep the rest (`d88c1640550f`)

**Yes, they can be GC'd — but by a proof per ref, never a window over the population.** The refs that
survive today are the ones whose land did NOT succeed, so each mirrors a *stuck fire tip*: its branch
is still parked at the very commit the ref names. `scripts/ship-backup-reap.sh sweep` deletes exactly
the subset where some live carrier ref CONTAINS the backup (`git merge-base --is-ancestor`), and KEEPS
and NAMES every ref with no carrier — the sole-holder class, which is the only part of this pile that
was ever worth protecting.

**The item's own worry — "deleting before their fire branch lands removes the redundancy" — does not
hold, for three reasons that are each mechanical rather than judgement:**

1. **The rollback point is regenerated, identically, before it is next needed.** `ship-land.sh:3708`
   writes `ship/backup-$(git rev-parse --short HEAD)` with `git branch -f` in the land preflight, so a
   fire branch still parked at that sha re-creates *the same ref name at the same commit* at the start
   of its next land attempt, before anything mutates the tree. The ref is not destroyed; it is deferred
   to the moment it has a job.
2. **No object is freed.** Ancestor-containment means the carrier already pins every object in the
   backup's history — `git gc` has nothing new to prune.
3. **The carrier cannot be swept out from under it.** `worktree-gc.sh` prunes a branch only when
   `landed()` holds (patch-id containment, `:433`), and a stuck fire's pre-rebase commits score `+`
   under `git cherry` — which is *why this population exists*. Its worktree-DISPOSE path independently
   refuses without a durable-ref proof and records `preserved_at: refs/heads/<branch>`.

**Why not the "rolling window (>14d AND P1-landed)" that INFRA_PERFECTION_2026-07-25:317 put on the
platter.** Age is not evidence about content, and the `landed` in that proposal meant patch-id — the
one reading that provably does not hold for this population (`git cherry` scores a rebased ref `+`,
which is the whole finding of STRANDED_EXPOSURE §8.2). A window would have had to either refuse the
interesting refs or guess. The proof-per-ref form refuses nothing and guesses nothing.

**Why a sweep is admissible at all**, given `ship-backup-reap.sh` refused one in code until now: that
refusal was about the CONTENT predicate, which decays against a drifted trunk (437 of 739 read "content
differs", where a dropped hunk and a moved trunk are the same observation). The sweep never asks that
question — it uses only the tool's first and strongest branch, ancestry, which has no drift term and is
strictly stronger than content identity. The refusal's second reason was "bulk disposal is an open
operator ruling with its own backlog item"; this is that ruling.

**Operational shape** — dry-run by default (`sweep` reports; `--apply` deletes), `SHIP_BACKUP_REAP=off`
kills both modes, a backup ref may never vouch for another (else one pass deletes a chain and its own
authority), the carrier is re-proved immediately before each delete (inventory moves mid-audit), and
every disposal writes a record naming the authorising carrier to
`~/.claude/autonomy/ship-backup-disposals.jsonl` — the question `worktree-gc --dispose-landed-dirt`
could not answer for the 32 directories it removed on 2026-08-11. Same treatment retrofitted to the
land-time `reap` path, so there is one deletion site and one record site.

**Not run here, and this is the reason.** `ship/backup-*` refs are never pushed
(`CLOUD_OBSERVABILITY.md:123`), so the population is invisible from the cloud VM this ruling was
authored in — it holds 0 of them. The sweep is landed and tested; the walk itself is one command on the
box, dry-run first:
`bash scripts/ship-backup-reap.sh sweep` → read the KEEP list → `sweep --apply`.

⚠️ **This item should never have been routed off-box, and `bin/cc-eligible` cannot see why.** Its
`BANKING` class refuses branch-corpus work by SPELLING, and this item's title spells none of the listed
words — it says `ship/backup-<sha>`, "branches", "fire branch", not `unpushed`/`unlanded`/`stranded`/
`local branch`/`worktree`/`wt-*`. So it classified `eligible` and burned a cloud slot on a population
the VM cannot see. **This is the same near-miss the `wt-slug` pattern was added for** (`4abcbbbbc997`,
which named its worktree only as `wt-bsm-gap`). The fix is a `ship/backup-` (and more generally a
never-pushed-ref-namespace) spelling in `BANKING`, per-token evidenced per that file's own header rule.
**Deliberately NOT done here:** `cc-eligible` is the off-box lane's own admission rule, and
`OFFBOX_LANE`'s stated law is that *a session this lane created cannot verify a change to the lane* —
the observer and the subject would be the same object. It needs a local session and its own row.

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
- **2026-08-16 — `d88c1640550f` ruled and mechanised** (P1). `ship/backup-*` may be GC'd where a live
  carrier ref contains them; sole-holders are kept and named. `scripts/ship-backup-reap.sh` grows a
  dry-run-by-default `sweep` mode + a disposal record on both modes; 11 new tests (21 total green), the
  carrier-set and sole-holder guards red-proved by mutation. Ruling + evidence in P1 above. **The walk
  itself has not run** — the refs are never pushed, so the cloud VM that authored this holds none of
  them; it is one command on the box. Also filed there: `bin/cc-eligible` mis-routed this item off-box
  and the fix needs a local session (the lane may not verify a change to itself).

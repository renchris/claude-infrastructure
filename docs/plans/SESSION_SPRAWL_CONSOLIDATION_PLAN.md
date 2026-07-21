---
status: complete
created: 2026-07-21
owner_repo: claude-infrastructure
---

# Session Sprawl Consolidation — one session per worktree, not N

**Status:** DONE 2026-07-21 · created 2026-07-21
**Owner repo:** `claude-infrastructure` (branch `main`)
**Scope (frozen):** Stop crash/limit recovery from resurrecting every historical
session per project. Recovery must consolidate to ONE live session per worktree
(plus an explicit, capped override), so a recovery never again lands 14 sessions
on one repo.

---

## Phase 0 — Agent Team Orchestration

**Verdict: SINGLE session, no team — and that is a deliberate call, not an omission.**

The default is Agent Teams for 2+ code-writing tasks. It does not apply here:
P1/P2/P3 are not independent tracks — they are **three edits to one decision
point** (which sessions get resumed). Splitting them across worktree-isolated
teammates would have two teammates racing the same selection path and a third
writing a report about a policy the others are still changing. The merge conflict
is guaranteed and semantic, not textual.

There is also a hard sequencing dependency: **Q1–Q3 in "Open questions" must be
answered before any code is written**, because they decide *where* the policy
lives. A team spawned before that answer would be briefed against a design that
does not exist yet.

| | |
|---|---|
| **Roster** | 1 lead (this successor). No teammates. |
| **Dependency graph** | Q1–Q3 (design) → P1 (policy) → P2 (ceiling) → P3 (report). Strictly serial. |
| **Worktree** | Repo root, `main`. Single writer ⇒ no worktree per CLAUDE.md's conditional rule. |
| **Spawn wave order** | n/a |

**Escalate to a team only if** the answer to Q1 splits the work across genuinely
separate files with no shared decision point (e.g. `resume-sessions` and
`/limit-recover` turn out to have fully independent selection paths — Q2). If
that happens, re-plan Phase 0 before spawning; do not improvise a team mid-flight.

**Research subagents are fine at any point** (reading `lr-audit.py`, tracing how
`/limit-recover` invokes the resume path) — they write no code.

## Why this exists — the observed incident (2026-07-21)

A machine-lag investigation found **39 live Claude Code sessions consuming 8.8 GB
RSS**, with **zero free RAM** (60 MB free, 24 GB/24.5 GB swap consumed, 30 GB in
the compressor). Breakdown by project at the time:

| project | live sessions | RSS |
|---|---|---|
| `voiceink` | **14** | 2.76 GB |
| `doc_classifier` | 16 | ~3.9 GB |
| `personal` | 5 | — |
| `lakehouse-lecture` + a worktree | 2 | — |

The 14 `voiceink` sessions were **batch-spawned within ~2 seconds of each other**
(`etime` 06:09:15–06:09:27 across the set) and every one was wrapped in an
`expect` process carrying `LR_CFG / LR_BIN / LR_MODEL / LR_EFFORT / LR_SID /
LR_PROMPT` — the signature of `scripts/limit-recover/lr-fire-resume.sh`.

They were killed (clean git tree, zero uncommitted work) and **did not respawn**
— confirming this is a one-shot recovery burst, not a running leak. No crontab,
no spawning LaunchAgent (`session-search-*` are transcript indexers only).

## Root cause — a policy gap in the CALLER, not the spawner

`scripts/limit-recover/lr-fire-resume.sh` resumes **exactly one** session per
invocation and is correct as written. Verified by inspection: it has **no dedup,
no cap, and no per-project grouping** — and it should not; it is the primitive.

The gap is in **who decides which sessions to resume**:

- `skills/resume-sessions/SKILL.md` Phase 1 says *"Enumerate resumable sessions
  across all 4 stores"*, then Phase 2 says *"For every session to bring back"* —
  the selection is left entirely to model judgment with **no consolidation rule
  and no ceiling**.
- `scripts/limit-recover/lr-audit.py` (1,478 lines) audits *workflow slots,
  subagents and teammates* for re-run — it is **not** the session-resume selector.
  Do not look for the fix there.

So "resume everything resumable" is the emergent default, and a project with a
long transcript history resurrects proportionally many sessions.

## The fix — three parts · **DONE 2026-07-21**

All three landed as one helper (`scripts/limit-recover/lr-select.py`, `ab55b95`)
consulted by all three sprawl-capable callers. Commits:

| | | |
|---|---|---|
| Design (Q1–Q3, Phase 0 re-plan) | `21ba59a` | four callers found, not one |
| P1+P2+P3 helper + 21 tests | `ab55b95` | grouping, ranking, ceiling, triage report |
| `--allow-missing-cwd` | `d986f57` | reaped worktrees stay resumable |
| Caller 3 `boot-resume.sh` + 4 tests | `efa405d` | was unbounded; fails closed now |
| Caller 2 `lr-reset-poller.sh` + 8 tests | `4d84557` | per-tick cap → per-recovery |
| Skill import (verbatim) | `93c8c2b` | it was untracked |
| Caller 1 skill Phase 1b | `ff92305` | the incident path |

**Learnings worth keeping:**

- **The per-file symlink trap nearly shipped a live regression.**
  `~/.claude/scripts/limit-recover/` is a real directory of per-file symlinks, not
  a symlinked directory. A new tracked file is therefore **not deployed** by
  landing it. The live, launchd-loaded, autofiring poller resolves its selector
  next to itself (`dirname "$BASH_SOURCE"` → the `~/.claude` copy), so landing
  without the symlink would have made it fail closed and **silently stop resuming
  anything**. Caught pre-land; symlink created by hand (there is no deploy script
  for these — a real gap, filed below). Same class as memory
  `deploy-lag-checkout-behind-origin`: landed ≠ deployed.
- **Fail-closed is the right default here, and it is counterintuitive.** For both
  automated callers the "working" fallback (fire everything up to the old cap) *is*
  the incident. An un-fired resume is human-recoverable; 8.8 GB of resurrected
  sessions took the machine down. Both callers therefore refuse to fire rather
  than fire unconsolidated, and both log loudly.
- **A loser must be retired, not left parked.** The poller's first correct-looking
  design left non-winners parked — but once the winner is running, `already-running`
  filters it out and the loser is elected next tick. That is the same sprawl at
  10-minute cadence. Losers move to `resumed/` (listed, never deleted); a genuinely
  new limit event re-parks them via the existing REPARK path.
- **Verified on real data**, read-only: 14 live candidates → 3 fired at
  `--max-total 3`, 11 listed, `doc_classifier` correctly consolidated to one.

## The fix — three parts (original specification)

**P1 · Consolidation rule (policy, in the skill).** Recovery groups candidate
sessions by `cwd`/worktree and resumes **one per group** — the most recent
session that holds real state. Others are *listed, not spawned*. Requires an
explicit opt-in to exceed one per worktree.

**P2 · Hard ceiling (mechanism, not judgment).** A total cap on sessions fired by
one recovery run, and a per-worktree cap of 1 by default. Exceeding it must be an
explicit flag, not a silent default — the same "no silent caps" discipline used
elsewhere: log what was dropped so a truncated recovery never reads as complete.

**P3 · Triage report before firing.** Recovery prints the grouped candidate table
(project → N sessions → which one wins → what the others were doing) and fires
only the winners. This is what would have made 14-for-one visible *before* it
consumed 2.76 GB.

## Open questions for the successor

1. Where should P1/P2 live — the `resume-sessions` skill text, a new
   `lr-select.py` helper, or a guard inside `lr-fire-resume.sh`? Preference is a
   **helper + skill rule**: keep the primitive dumb, put policy where it is
   testable. Confirm against how `/limit-recover` invokes it.
2. Does `/limit-recover` share this selection path, or does it have its own? Both
   must land under the same ceiling.
3. What defines "holds real state" for picking the winner — last activity time,
   uncommitted work in the worktree, or transcript length? Note `voiceink` had a
   **clean tree**, so uncommitted-work alone is insufficient as a signal.

## Answers — Q1–Q3 resolved (2026-07-21, successor session)

### Q2 first: the selection path is **NOT shared — there are four callers**, and only one has any cap

Q2 was asked as a yes/no and the answer reframes Q1. Full caller inventory, by
disk inspection:

| # | Caller | Selects by | Total cap | Per-worktree rule | Live? |
|---|---|---|---|---|---|
| 1 | `skills/resume-sessions/SKILL.md` Ph1→Ph2 → `reso-resume-one` | **model judgment** ("enumerate all" → "for every session to bring back") | **none** | **none** | **LIVE — the incident path** |
| 2 | `scripts/limit-recover/lr-reset-poller.sh` | limit-parked detection; per-`sid` dedup via `pgrep` | `MAX_PER_RUN=4` **per 10-min tick** | **none** | **LIVE, launchd-loaded, `LR_POLLER_AUTOFIRE=1`** |
| 3 | `scripts/boot-resume.sh` (`mode=resume`) | registry ghosts predating `kern.boottime` | **none — unbounded `while` over all ghosts** (L180-192) | **none** | staged, **NOT loaded** (latent) |
| 4 | `commands/limit-recover.md` → `lr-handoff.sh` | the ONE lead session being transplanted | inherently 1 | n/a | LIVE — **not a sprawl vector** |

Three consequences:

- **Caller 4 is exonerated.** `/limit-recover` does not share the sprawl path; its
  handoff moves exactly one lead session (`lr-handoff.sh:138` — a single `exec`).
  It needs no ceiling.
- **Caller 2's cap is per-tick, not per-recovery.** `MAX_PER_RUN=4` every 600 s
  means 14 parked sessions in one worktree still all come up — just over ~35 min
  instead of 2 s. Slower sprawl is still sprawl.
- **Caller 3 is a loaded gun.** It loops every ghost with no cap at all, and it is
  sitting in `pending-activation` awaiting an operator `launchctl load`. Activating
  it today would reproduce the incident *by design* on the next reboot. Fixing it
  before activation is the whole point of getting there first.

### Q1 — helper, and the answer is now forced

Preference confirmed, but Q2 upgrades it from taste to necessity: **a rule written
only in skill text would cover caller 1 and leave callers 2 and 3 uncovered** — and
those two are precisely the ones that run *with no human watching*. Policy therefore
goes in a shared, testable helper that all three consult:

- **`scripts/limit-recover/lr-select.py`** — grouping, winner-pick, ceiling, and the
  P3 triage report. Subsystem-neutral despite the `lr-` name (caller 3 is desk
  machinery, not limit-recover); named per this plan's own preference and sited
  beside `lr-audit.py`, with which it shares all transcript-parsing concerns.
- `lr-fire-resume.sh` and `reso-resume-one` **stay dumb** — unchanged. One-shot
  primitives, exactly as the root-cause section rules.
- The skill keeps a *rule* (call the helper, fire only winners), not a *policy*.

### Q3 — "holds real state", and a correction to the question

The question contains a latent flaw worth naming: **uncommitted work cannot pick a
winner within a group, because it is a property of the worktree, not the session.**
All N sessions sharing a `cwd` see the identical dirty tree. That — not merely
`voiceink`'s clean tree — is why the signal is insufficient: it is *constant across
the group*. It tells you the group matters; it cannot discriminate inside it.

So the two roles split:

- **Group-level annotation** — `dirty` (uncommitted file count). Marks the group HOT
  in the triage report and is the fact that justifies an operator override. Never a
  ranker.
- **Within-group ranking** — a lexicographic tuple of per-session signals, first
  non-tie wins:
  1. **last real activity** = the transcript's *internal* max timestamp, never file
     mtime (a bulk mirror touch gives many files an identical mtime that is not
     activity — the rule the skill already states for Phase 1 ranking).
  2. **substantive depth** = turn count, as tiebreak. A 2-turn stub loses to a
     400-turn session at the same timestamp.
  3. **session id**, lexicographic — a final deterministic tiebreak so selection is
     reproducible and therefore testable.

Hard filters run *before* ranking and are not tiebreaks: already-running
(`pgrep -f "resume <sid>"`), teammate sessions (`agentName` on early records —
lead-owned recovery), `agent-*.jsonl` / `wf_*` internals, and a `cwd` that no longer
exists.

### Phase 0 — re-planned (as this plan requires before any spawn)

**Verdict unchanged: SINGLE session, no team.** The rationale is *replaced*, because
Q2 fired the plan's own escalation trigger ("if `resume-sessions` and
`/limit-recover` turn out to have fully independent selection paths"). They did — so
the trigger is re-evaluated on its merits rather than followed mechanically:

The four paths are independent *callers*, but the work is not four tracks. It is
**one new helper that defines a contract, plus three ≤10-line wirings that consume
it**. No teammate can write a caller wiring before the helper's contract exists, so
the dependency is strictly serial and a team would serialize into a queue with extra
merge risk. The escalation condition ("genuinely separate files with **no shared
decision point**") is not met: the helper *is* the shared decision point — that is
its entire purpose. Research subagents remain unnecessary; the inventory above is
complete by direct inspection.

### Deployment finding (blocks P1)

`skills/resume-sessions/` is **not tracked in this repo** — it exists only as real
files in all 5 config dirs. Every other skill (`agent-teams`, `coding-standards`, …)
is a per-file symlink from all 5 dirs into the checkout. P1 cannot land as a
reviewable change until the skill is imported to `skills/resume-sessions/` and the
5 copies re-pointed. That import is therefore in scope.

`Scope (grown): +import the untracked resume-sessions skill into the repo and
symlink the 5 config dirs` — Follow-On Gate F1-F4 PASS (F1 P1 cannot land without
it; F2 verified by direct `ls -la`/`readlink` inspection this session; F3 no
escalation surface, matches the repo's own established symlink convention; F4 one
bounded commit, content-identical import + one appended rule).

## Constraints (HARD)

- **Do not delete or bulk-close anyone's sessions as part of this work.** The
  incident's cleanup was already done and operator-approved per project. The
  `doc_classifier` sessions hold **322 uncommitted files** — never touch them.
- Never propose age-based or bulk deletion as the mechanism; the fix is at spawn
  time, not a reaper.
- `git push` only on explicit operator request.

## Status log

- **2026-07-21 (successor)** — **Fix complete and verified.** Q1–Q3 answered before
  any code (see § Answers). Q2 reframed the work: four callers, not one. Single
  helper `lr-select.py` now owns the policy; all three sprawl-capable callers
  consult it; the spawners stayed dumb as the root-cause section required. 33 new
  tests + 10 existing boot-resume cases green. Nothing was deleted or bulk-closed;
  the `doc_classifier` sessions were never touched. Landed on `main` — see the
  table above for per-commit detail.
  **Open follow-up (named, not silently carried):** there is **no deploy script**
  for the `~/.claude` per-file symlinks. Every new tracked script under
  `scripts/**` must be hand-linked into `~/.claude/scripts/**` or it is landed but
  not deployed. That is a systemic gap of the class memory
  `desk-whack-a-mole-means-file-systemic-fix` says to file rather than hand-clear —
  a `scripts/link-live.sh` that reconciles checkout → live and reports drift.
- **2026-07-21** — Plan created. Root cause identified and evidenced (batch-spawn
  signature, `LR_*` expect wrappers, no dedup/cap in `lr-fire-resume.sh`,
  selection left to model judgment in the skill). Cleanup of the 14 `voiceink`
  sessions completed with operator approval; they did not respawn. Related but
  separate perf fix committed same day as `5d5ffce` (supervisor `find` pruning) —
  that addressed disk thrash, not session count.

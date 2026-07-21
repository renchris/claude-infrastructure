---
status: open
created: 2026-07-21
owner_repo: claude-infrastructure
---

# Session Sprawl Consolidation — one session per worktree, not N

**Status:** OPEN · created 2026-07-21
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

## The fix — three parts

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

## Constraints (HARD)

- **Do not delete or bulk-close anyone's sessions as part of this work.** The
  incident's cleanup was already done and operator-approved per project. The
  `doc_classifier` sessions hold **322 uncommitted files** — never touch them.
- Never propose age-based or bulk deletion as the mechanism; the fix is at spawn
  time, not a reaper.
- `git push` only on explicit operator request.

## Status log

- **2026-07-21** — Plan created. Root cause identified and evidenced (batch-spawn
  signature, `LR_*` expect wrappers, no dedup/cap in `lr-fire-resume.sh`,
  selection left to model judgment in the skill). Cleanup of the 14 `voiceink`
  sessions completed with operator approval; they did not respawn. Related but
  separate perf fix committed same day as `5d5ffce` (supervisor `find` pruning) —
  that addressed disk thrash, not session count.

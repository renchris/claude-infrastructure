---
status: open
---

# MASTER: stranded work — value that reached a branch and never reached trunk

**Condition key:** `master-stranded-work` · **Live members 2026-08-12 (measured after the apply):** 50 (34 blocked · 16 open)
**Inventory (run this, never trust the count above):**
`cc-backlog list --all --json | jq -r '.[]|select(.condition=="master-stranded-work" and .status!="done")|"\(.id) \(.status) \(.title[0:90])"'`

**Why this is ONE effort and not 87.** Every member is the same mechanism seen once per branch:
`ship-land` exited 5, 6 or 143, its auto-recovery did not finish the job, and a commit was left where
only this machine can see it. 62 commits across 21 abandoned wave branches were measured
content-stranded on 2026-08-10 (CLOSE_INTEGRITY recon). One sweep session with a roadmap re-lands
them; 87 dispatches would each re-derive the same sweep.

🚨 **The mechanical fold was RIGHT to refuse this shape and this plan is what makes it safe.** Its
largest sha-keyed cluster of 14 was nine different stranded worktrees, and joining them with no
roadmap behind them would have refused dispatch on all nine while delivering nothing. The join is
honest here *because* this file exists: the group's one session sweeps every member.

## Phase 0 · Agent Team Orchestration

**EXECUTION LOCUS PER WAVE.** S = dispatched handoff session (the default) · T = in-session teammates · L = lead-inline.

| Wave | Execution locus | Deliverable | Depends on |
|---|---|---|---|
| **S1 · census** | **S** | per-branch verdict: does this ref hold content trunk lacks, BY CONTENT | — |
| **S2 · re-land** | **S** (same session, serialised) | every ff-able branch landed, smallest diff first | S1 |
| **S3 · the generator** | **S** | why `ship-land` exits 5/6/143 and its recovery stops short | — (parallel with S1/S2) |
| **S4 · close by content** | **L** (lead-inline) | rows closed against `git ls-tree`, worktrees disposed | S2 |

**S4 is lead-inline** because it is one loop over one store with no code to write, and it must run
after S2's land in the same context that observed it.

**Lead context budget:** hold ≥50% for adjudicating land order and conflict resolution. **Succession
point:** between S2 and S3 — the census and the sweep are one context, the root-cause dig is another.

## Sub-waves

### S1 · Census — by CONTENT, never by commit count
`git rev-list origin/main..<branch>` reads 0 after a sibling rebase and proves nothing; a count is
also blind to staged and untracked bytes. Per candidate: `git ls-tree origin/main -- <paths>` plus
`git diff origin/main..<branch> --stat`, and for a live worktree also `git status --porcelain`.
Emit one verdict per branch: `LANDED` (close the row) · `HOLDS-CONTENT` (S2) · `EMPTY` (dispose).

### S2 · Re-land — serialised, smallest diff first
`git rerere` is enabled globally, so repeated same-hunk conflicts auto-resolve across branches. Land
via `scripts/ship-land.sh` only; never a bare `git push`. Rebase onto fresh `origin/main` per branch,
`--ff-only` merge, gate green, then verify BY CONTENT before closing the row.

### S3 · The generator — why the recovery stops short
Every row's own title names the exit code. Exit 6 dominates; 143 is SIGTERM (a signal-kill, which
`ship-land` currently misreports as GATE RED — see `master-verification-integrity`, and do not fix
it twice). The deliverable is the reason the auto-recovery leaves a branch behind, plus the fix, plus
a test that red-proves it.

### S4 · Close by content, dispose the rest
`worktree-gc --dispose-landed-dirt` writes NO disposal record today (a member of
`master-fleet-footprint` — coordinate, do not duplicate). Close each row with
`cc-backlog done <id> --evidence "landed <sha>, verified by content"`.

## Definition of done
Every member row is either closed against a content-verified land or carries a named reason it
cannot be landed. `git ls-tree origin/main` proves each claim. The exit-5/6/143 generator has a
landed fix with a red-proved test, so the population stops growing.

## Status log
- **2026-08-12 — created by W2 of `BACKLOG_SELF_DRAINING_2026-08-12.md`.** 87 rows joined to this
  condition by `scripts/backlog-consolidation/group.py`; 9 of them by the 2026-08-09 triage wave's
  own human adjudication (`link.py --dir` replay). Not yet worked.

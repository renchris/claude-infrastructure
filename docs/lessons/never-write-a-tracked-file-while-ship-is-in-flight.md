# Never write a tracked file while /ship is in flight

_Relocated VERBATIM from `.claude/rules/agent-operating-lessons.md` (always-loaded tier) — the rules file now carries the hook and links here. Nothing was shortened._

[Never write a tracked file while /ship is in flight](.) — 2026-09-08, self-inflicted: ship-land's OPTIMISTIC round gates UNLOCKED, then takes the land-lock and re-fetches; if a sibling landed during that window it releases the lock and **re-rebases**, and a rebase refuses on ANY unstaged change — `error: cannot rebase: You have unstaged changes` → `✗ ship-land: rebase onto origin/main hit a conflict`. The land had already spent 444s queued behind another worktree and passed every gate; it died on a one-line memory-rule edit made in the gap "while waiting". The window is invisible from outside: `git status` was clean when the land started, and nothing warns you that editing the tree re-arms a failure mode. ⇒ Between firing `/ship` and reading its verdict, the worktree is the LANDER's, not yours — do memory writes, scratchpad work and doc drafting either before the fire or after the verdict. If you must capture something, write it OUTSIDE the repo (the memory/ dir under the config root is not tracked here) and commit it after. Recovery is cheap when caught (no rebase is left in progress — it refuses before starting; commit the file and re-ship), but it costs a full contended land cycle.

---

## The stronger sibling: never REMOVE the worktree either — it destroys the lander's cwd

2026-09-21, self-inflicted, same family and worse. The rule above says the worktree is the
lander's between the fire and the verdict, and gives WRITING as the failure mode. **Deleting the
directory is the other one, and it is silent.** `scripts/ship-land.sh` was fired from
`~/Development/ci-wt-artifact-off`, exceeded the tool's 120 s foreground limit and was backgrounded
— still running, still inside that cwd. Six minutes later, believing the land finished because the
commit was already verifiable on trunk by content (`git ls-tree origin/main`, `merge-base
--is-ancestor` — both true, both about the LAND, neither about the PROCESS), the same session ran
`git worktree remove --force` on it.

**What that does.** Every subsequent `git` the lander forks inherits a cwd that no longer exists:

```
fatal: Unable to read current working directory: No such file or directory
```

exit 128, per invocation, forever. The land itself had already completed —
`✓ ship-land: LANDED → origin/main; content-verified` — so the headline verdict and the exit code
were both 0 and nothing looked wrong. What died was the leg still running: the stranded-branch
sweep, which reported

```
? stranded-sweep --mine: NO VERDICT — 0 own-session drops among 1384 readable branch(es),
  but 1551 branch(es) could not be read (above).
```

**Why this is worth its own paragraph rather than a footnote.** The sweep did the RIGHT thing —
it abstained rather than reporting a clean 0 over a population it could not read, which is the
`predicate-refusal-is-not-a-negative` discipline working as designed. Had it been written the
common way (`git cherry … 2>/dev/null || true`, count the empties) the identical damage would have
rendered as **"0 stranded branches"** — a false all-clear over 1551 unread branches, produced by
the session that caused it, on the surface built to catch exactly that.

**The generalisable rule, which is not about /ship.** A backgrounded process keeps its cwd as a
live handle on a directory, and `rm -rf` / `git worktree remove` / a reaped tmpdir revokes it
mid-flight. The victim never says "my cwd was deleted"; it says whatever its next syscall says,
which for git is a blanket exit 128 that reads as a repository or permissions fault and points
away from the cause. ⇒ **Before removing any directory, ask which still-running process was
launched from it** — `lsof +D <dir>` or a pgrep over the job ids, not "the command I was waiting
on printed its verdict". A verdict line proves the WORK finished; only the process table proves
the PROCESS did, and a lander's terminal verdict can precede its own housekeeping legs.

**Blast radius when it happens anyway:** nothing to repair. The sweep is read-only and re-runs on
every land from any session, so it self-heals; the land, the content-verification and the converge
are all unaffected. The cost is one lost audit pass and the minutes spent proving that is all it
was.

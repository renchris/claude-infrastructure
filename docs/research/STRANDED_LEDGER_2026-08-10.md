# Stranded work ledger — claude-infrastructure, 2026-08-10

Backlog item `0328e7cc5742` (MASTER M4), DoD in
`docs/plans/BACKLOG_CONSOLIDATION_2026-08-09.md` §M4.

**This file exists so that no branch below can be reaped, forgotten, or "cleaned up" without a
future reader knowing exactly what was on it.** Every branch named here is PRESERVED — nothing was
deleted, and nothing should be. `git worktree remove` is safe on any of them (the branch is the
durable ref); `git branch -D` is not.

---

## The headline

| | patches | branches |
|---|---|---|
| Unlanded when this sweep started | 95 unique (111 branch×patch rows) | 31 |
| Landed by this sweep | 1 | 1 |
| Already on trunk under a **different sha** (superseded — retirable) | 14 | — |
| **Genuinely unlanded and still stranded** | **83** | **24** |

The sweep landed one branch and was refused on 30. That refusal rate is the finding, not a failure
of the rail: **24 of 30 were rebase conflicts and 5 were gate-red.** Trunk took 2,278 commits in the
40 days these branches sat, so the oldest of them (2026-07-25) is rebasing across a fortnight of
churn in the same test files it edits. The work did not rot because it was unsafe; it rotted because
nothing ever asked it to land, and the cost of landing it rises every day it waits.

## How these numbers were measured (re-run before trusting them)

```
git -C <repo> worktree list --porcelain | awk '/^branch /{print substr($0,19)}' | sort -u \
  | while read -r b; do git -C <repo> cherry origin/main "$b" | grep -c '^+'; done | paste -sd+ - | bc
```

⚠ **`git cherry` is the only correct instrument, and both of its failure modes bite here.**
`git rev-list --count origin/main..<branch>` reports **455** for a branch holding **8** real
patches — it counts trunk's own commits since the fork. And a `git cherry` result of **0 means
LANDED**, not "the command did nothing"; the two are indistinguishable from outside.

⚠ **Count UNIQUE shas.** Three worktrees here (`fix/accounts-eval-bin-resolver`, `wt-dda10a298842`,
`wt-e06ba316a1aa`) hold byte-identical commit sets, because re-creating a worktree keeps the old
branch. A per-branch sum reports 111 for 95 real patches.

⚠ **Patch-id equivalence misses amended landings.** 14 patches here have a subject that is already
on trunk under a different sha — the commit was edited before landing, so `git cherry` still calls
it unlanded. Cross-check subjects before concluding a branch holds value:

```
git log --format='%s' origin/main --since='40 days ago' | sort -u > /tmp/trunk-subjects
git cherry -v origin/main <branch> | grep '^+' | sed 's/^+ [0-9a-f]* //' \
  | while read -r s; do grep -qxF "$s" /tmp/trunk-subjects && echo "SUPERSEDED: $s"; done
```

## The stranded branches

Ordered by patches at risk. "Status" is this sweep's `scripts/ship-land.sh` exit.
`rc=5` = rebase conflict (needs a human merge decision); `rc=6` = the gate ran and returned a
verdict about that diff.

| branch | genuine unlanded patches | tip | status | worktree |
|---|---|---|---|---|
| `deskless` | 17 | 2026-08-07 | rc=5 (REBASE CONFLICT) | `/Users/chrisren/Development/.worktrees/deskless` |
| `terminal-arm-land` | 8 | 2026-07-31 | rc=5 (REBASE CONFLICT) | `/Users/chrisren/Development/wt-terminal-land` |
| `wt-63929c8d6072` | 7 | 2026-07-25 | rc=5 (REBASE CONFLICT) | `/Users/chrisren/Development/.worktrees/wt-63929c8d6072` |
| `wt-02ba4e52389a` | 7 | 2026-07-25 | rc=5 (REBASE CONFLICT) | `/Users/chrisren/Development/.worktrees/wt-02ba4e52389a` |
| `terminal-iterm2-vs-kitty-arm` | 6 | 2026-07-31 | rc=5 (REBASE CONFLICT) | `/Users/chrisren/Development/wt-terminal-arm` |
| `fix/accounts-eval-bin-resolver` | 6 | 2026-08-01 | rc=5 (REBASE CONFLICT) | `/Users/chrisren/Development/.worktrees/wt-evalbin` |
| `wt-e06ba316a1aa` | 5 | 2026-08-01 | rc=5 (REBASE CONFLICT) | `/Users/chrisren/Development/.worktrees/wt-e06ba316a1aa` |
| `wt-dda10a298842` | 5 | 2026-08-01 | rc=5 (REBASE CONFLICT) | `/Users/chrisren/Development/.worktrees/wt-dda10a298842` |
| `wt-6cab0ab3cb2f` | 5 | 2026-07-25 | rc=5 (REBASE CONFLICT) | `/Users/chrisren/Development/.worktrees/wt-6cab0ab3cb2f` |
| `fix/sigterm-forensics` | 5 | 2026-08-09 | rc=6 (GATE RED — a verdict about this diff) | `/Users/chrisren/Development/.worktrees/wt-sigterm-forensics` |
| `cloud-g5-create` | 4 | 2026-08-09 | rc=5 (REBASE CONFLICT) | `/Users/chrisren/Development/.worktrees/cloud-g5-create` |
| `fix/postland-kill-nonverdict` | 3 | 2026-07-31 | rc=6 (GATE RED — a verdict about this diff) | `/Users/chrisren/Development/.worktrees/deploy-deadlock` |
| `feat/tmux-isid-resolver` | 2 | 2026-07-27 | rc=5 (REBASE CONFLICT) | `/Users/chrisren/Development/wt-tmux-isid` |
| `feat/consolidation-trigger` | 2 | 2026-08-10 | not attempted | `/Users/chrisren/Development/.worktrees/consolidation-trigger` |
| `wt-62599dd76a60` | 1 | 2026-07-31 | rc=5 (REBASE CONFLICT) | `/Users/chrisren/Development/.worktrees/wt-62599dd76a60` |
| `wt-3c6bf04ba842` | 1 | 2026-07-26 | rc=5 (REBASE CONFLICT) | `/Users/chrisren/Development/.worktrees/wt-3c6bf04ba842` |
| `fix/recycle-pane-probe-fail-safe` | 1 | 2026-08-06 | rc=5 (REBASE CONFLICT) | `/Users/chrisren/Development/.worktrees/wt-fix-recycle-pane-probe-fail-safe` |
| `fix/opus5-effort-ladder` | 1 | 2026-08-01 | rc=6 (GATE RED — a verdict about this diff) | `/Users/chrisren/Development/.worktrees/opus5-effort` |
| `fix/mailbox-writer-key` | 1 | 2026-07-30 | rc=5 (REBASE CONFLICT) | `/Users/chrisren/Development/wt-mailbox-key` |
| `fix/cc-blockers-fleet-suite` | 1 | 2026-08-01 | rc=6 (GATE RED — a verdict about this diff) | `/Users/chrisren/Development/.worktrees/wt-blockers-fleet` |
| `fix/bats-liveness-terminal-bench` | 1 | 2026-07-31 | rc=5 (REBASE CONFLICT) | `/Users/chrisren/Development/.worktrees/wt-bats-liveness` |
| `fix/banner-redproof-restale` | 1 | 2026-07-30 | rc=5 (REBASE CONFLICT) | `/Users/chrisren/Development/.worktrees/wt-redproof-fix` |
| `feat/multi-provider-plans` | 1 | 2026-08-10 | rc=6 (GATE RED — a verdict about this diff) | `/private/tmp/wt-multiprovider` |
| `docs/entrypoint-consolidation` | 1 | 2026-08-01 | rc=5 (REBASE CONFLICT) | `/Users/chrisren/Development/.worktrees/wt-entrypoint` |

Recovery for any row — the branch is intact, so this is all it takes:

```
git worktree add /tmp/recover-<name> <branch>     # if its worktree is gone
cd /tmp/recover-<name> && git rebase origin/main  # resolve conflicts, then:
bash /Users/chrisren/Development/claude-infrastructure/scripts/ship-land.sh
```

## Landed by this sweep

- `wt-87a515ed087e` → **`8bccd5da`** — `test(pin-guard): the M11 ratchet's one NEW UNPINNED FIRE
  SUITE, red on trunk since it landed`. Content-verified on origin/main.

## Why this will not simply re-accumulate

The removal path was never the leak. `scripts/worktree-gc.sh` gate 6 refuses to remove a worktree
whose branch holds unlanded commits (patch-id, not ancestry); `bin/cc-reaper`'s `work_landed()`
refuses on the same test and additionally leaves any tree carrying untracked files intact;
`scripts/branch-reaper.sh` deletes only merged branches, with `-d` and never `-D`. All three are
tested (`tests/worktree-gc.bats:163,224`, `tests/cc-reaper.bats:255,318,467`,
`tests/branch-reaper.bats:46`). **Finished work being deleted is a failure this repo already
engineered out.**

What was missing is the other half: **"unlanded ⇒ KEEP" had no counter-pressure.** A branch nobody
lands is kept forever, and the janitor's own verdict row reported it in the same integer as a
worktree kept because a session is live inside it —

```
2026-08-10 04:15  verdict=ok ... removed=16 kept=112 ... pop_owned=101 ceiling=150 rc=0
```

`kept=112`, and nothing anywhere said that 95 finished patches were inside it. The only reason the
number in this file exists is that a human summed it by hand.

So `scripts/worktree-gc-infra-run.sh` now measures and reports the balance it is holding
(`stranded_patches` / `stranded_branches` on every swept row) and raises
`verdict=stranded-over-ceiling` past `CC_WTGC_STRANDED_CEILING` (default 40). It is ranked BELOW the
population breach deliberately: the two have different remedies and different actors —
`over-ceiling` means REAP, `stranded-over-ceiling` means **LAND**, and reaping will never clear it.
`bash scripts/worktree-gc-infra-run.sh --assert` reports it on demand, sweeping nothing.

## Cross-repo — the count nobody had ever taken in one place

Measured 2026-08-10 with the same `git cherry` pairing. **Not ours to land from here** — both repos
have their own rails — but invisible is how it stays unlanded, so it is recorded:

| repo | branches with unlanded work | unlanded patches | branches already landed (retirable) | worktrees |
|---|---|---|---|---|
| `reso-management-app` | 152 | **1046** | 332 | 74 |
| `doc_classifier` | 31 | **57** | 40 | 63 |
| `claude-infrastructure` (this file) | 24 | 83 | — | ~105 |

**1103 patches across 183 branches in the other two repos.** 372 of their local branches are
patch-identical to trunk and are pure noise — 67% of all local branches across both.

Two structural notes, each a reason the number is what it is:

- **`doc_classifier` has no landing rail at all.** No `scripts/ship*.sh`, no `scripts/land*.sh`, no
  `.claude/commands/`, and no `CLAUDE.md` anywhere in the repo or on its trunk. It therefore makes
  no statement about landing cost, so the global default (auto-land) applies — its 57 patches are
  stranded without a policy reason *and* without a script an agent could run.
- **`reso-management-app` has the full rail** (`scripts/ship-reconcile.sh`, `scripts/land-lock.sh`,
  `.claude/commands/ship.md`) but its `CLAUDE.md:495` still reads *"Push / ship = `/ship`, your
  explicit call"*. It does **not** say landing spends money, which is the only condition the global
  ship policy accepts for gating on the operator — and its own `ship.md:11` says the command "Goes
  **straight through** — no 'shall I push?' pause." Note `scripts/land-status.sh`, cited in the
  global CLAUDE.md as reso's live-truth tool, **does not exist**. Reconciling that line is reso's
  call, not this repo's.

## What is NOT in this ledger, deliberately

- Branches held by a live session at sweep time (`m2-firegate`, `m5-enforcing-store`,
  `feat/backlog-ratchet`, `feat/consolidation-trigger` at its tip) — landing a peer's in-flight
  branch is interference, not recovery. The sweep skipped any branch whose worktree hosted a live
  Claude process or whose tip was under 30 minutes old.
- The 14 superseded patches — their content is on trunk under another sha. Those branches are
  retirable, and `git worktree remove` on them loses nothing.

# A cold `--worktree` fire under load misses its engagement window, and the recovery duplicates the session

**Measured 2026-09-19**, firing waves W1/W2/W4/W5 of `docs/plans/SUBAGENT_LIFECYCLE_ROOT_CAUSE.md`
from one lead pane while the box ran at load 18–28 on 10 cores.

## What happened

`scripts/handoff-fire.sh` scales its engagement window by load (`fire_engage_window`, base 120 s,
cap 480 s). At ~2/core that yields 223–261 s. **Three of three cold `--worktree` fires reported
`FIRE FAILED — never engaged` and all three were false** — each session's transcript and worktree
were moving minutes later:

| wave | window | verdict | truth |
|---|---|---|---|
| W2 | 223 s | never-engaged | engaged; transcript 1.47 MB, 4 files written |
| W1 | 261 s | never-engaged | engaged; transcript 1.57 MB, 5 files written |
| W4 | 480 s (`FIRE_ENGAGE_TIMEOUT_BASE=240`) | never-engaged | engaged; transcript 1.37 MB, 7 files written |

The verdict is a **window expiry, not a death** — the script says so itself and prints the two reads
that discriminate it. That part worked.

**The expensive half is the INC-4 recovery.** On expiry the script re-types the prompt once. For W2
that produced a SECOND session against the same worktree. The two collided visibly — the guard suite
went 54 → 61 → 54 tests as each wrote — and the later session correctly stood itself down
(`memory:argv-is-sampling-cwd-is-durable`), surgically removed its own edits, and verified the
sibling's work intact. Cost: one wave's worth of tokens, and a worktree whose complete, green work
was left **uncommitted and unowned** when the surviving session also departed.

**A warm `--cwd` fire into the existing worktree engaged in 9 s at the same load** (load 18.9). The
cold path's latency is worktree provisioning plus a cold `claude` boot; the warm path pays neither.

## The rule

1. **Under load > ~2/core, fire warm.** Provision the worktree yourself, then
   `handoff-fire.sh --cwd <worktree>`. Raising `FIRE_ENGAGE_TIMEOUT_BASE` does not fix it — W4 got
   the full 480 s cap and still "expired".
2. **A never-engaged verdict is a claim about the WINDOW, never about the session.** Run both
   discriminating reads before doing anything, and re-run them ~60 s later
   (`docs/lessons/a-never-engaged-verdict-is-mostly-false-and-its-real-cost-is-the.md`).
3. **The real cost is the unarmed goal.** Every expired fire reports
   `goal-arm verdict=unreachable reason=never-engaged`, so the peer runs with nothing blocking its
   Stop. Three of four waves here are goal-less and must be driven by hand.
4. **Never put a brief on a shared `/tmp` path.** `/tmp/fire-W2.txt` collided with a *different*
   lead's plan file of the same name; their fire read our brief 5 s after we wrote it and executed
   our W2 into our worktree. Use a per-plan directory.

## Companions

`a-never-engaged-verdict-is-mostly-false-and-its-real-cost-is-the.md` (this is its second
independent confirmation, plus the duplication mechanism it predicted) ·
`argv-is-sampling-cwd-is-durable` (how the duplicate resolved itself) ·
`a-cure-is-verified-only-under-the-load-that-caused-it.md` (why the warm/cold comparison is only
meaningful because both arms ran at the same load).

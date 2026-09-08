# A recovery batch is a PERISHABLE artifact, and nothing on the resume path knew that

**Date:** 2026-09-08 · **Origin:** cc-backlog `80ed5e7a1e7e`, dispatched to be executed.
**Verdict: the item's premise is REFUTED.** Its instruction was not merely unnecessary — by the day
it was dispatched, following it would have resumed three sessions into worktrees that now belong to
other branches. The disproof is below; the defect it exposed is fixed in the same commit.

## 1. What the row asked for

> Resume the 9 AT-REST panes still parked after the 2026-08-25 restart recovery. Batch is on disk at
> `~/.claude/autonomy/resume-remaining-2026-08-25.tsv` … **Re-run when mid-turn count is low.**

Filed 2026-08-25T08:12:40Z. It carries no expiry, and the whole of its correctness rests on a claim
about the world at the moment of filing: *those nine sessions are parked, and the TSV describes
where they live.*

## 2. Refutation A — they were never left parked. All nine came back the same morning.

The row's own premise names the competitor: *"the `com.claude.boot-resume` daemon was resuming in
parallel and competing for the same slots."* That daemon won. Counting transcript records written
after the TSV's own mtime (2026-08-25 03:12):

| session | worktree | records after the TSV was written |
|---|---|---|
| `30614274` | wt-pool-8 | 2305 |
| `bfaad69d` | personal | 1221 |
| `6da3ec72` | wt-pool-3 | 1196 |
| `ee52fbd4` | wt-sr-zerohuman | 630 |
| `af5b3de0` | wt-pool-4 | 483 |
| `f5762f7c` | wt-pool-6 | 467 |
| `7404858f` | wt-pool-2 | 338 |
| `3839badc` | wt-cc-180319-84744 | 207 |
| `5b6ddfa2` | ccbacklog-session-ladder | 0 — **it had already self-retired** |

The ninth needs no resume at all: its last words are `Both pings delivered. Retiring the pane.` The
`cc-resume-layout.sh` refusals the row treats as the blocker were losing a race that had already
been won, and the capacity ceiling that shed the batch was doing the right thing for a second
reason nobody had noticed — the slots were being spent on sessions that were already alive.

The others reached their own clean terminal states, in their own words:

- `6da3ec72` — *"I'm not recycling the pane: with the agent-drivable scope cleared and only
  operator-gated items left, a successor would inherit no work."*
- `3839badc` — *"Nothing waiting on you."*
- `f5762f7c` — *"…both open items filed … stays up for your feel check."*

## 3. Refutation B — fourteen days later the batch describes a machine that no longer exists

Measured 2026-09-08 (uptime 14 days; the box has not rebooted since the 2026-08-25 02:16 restart the
row names, so nothing here is a second crash):

- **0 of 9** sessions have a live process.
- **8 of 8** branches the TSV names are deleted (`personal`'s `master` is the ninth row and is not a
  session branch).
- **Nothing is stranded.** Every surviving worktree reads `origin/main..HEAD = 0`.
- **2 of 9 worktrees were reaped**: `wt-cc-180319-84744`, `ccbacklog-session-ladder`.
- **3 of 9 worktrees were RE-LET to other branches** — and this is the dangerous one:

| worktree | branch in the TSV | branch it holds today |
|---|---|---|
| `wt-pool-2` | `cc-222358-33352` | `cc-202858-38809` |
| `wt-pool-3` | `cc-145907-94063` | `cc-001001-11506` |
| `wt-pool-8` | `cc-030311-15391` | `pool/slot-8` (returned to the pool) |

## 4. The defect this exposed — and why only half of it was already covered

`bin/reso-resume-one` is the chokepoint: every resume path funnels through it. It validated the
branch on exactly **one** of its two paths.

- **Worktree reaped** → it proves the branch exists in the owning repo and exits 1 when it does not.
  So the two reaped rows above were already safe.
- **Worktree present** → it `cd`s in and resumes, asserting nothing. The 4th positional was carried
  as a label: forwarded to the pane title, and dropped.

That asymmetry encodes a belief that a directory's continued existence proves it is still the same
tree. On this box the belief is false by design: `~/Development/.worktrees/wt-pool-N` is a **slot**,
returned to a pool and re-let. Its existence outlives the row that named it, which is the only
reason the three rows above look resumable.

**The fix** (this commit) adds the identity check to the present-worktree path, with the polarity
the resume machinery already uses elsewhere: fail-closed on a proven mismatch, fail-OPEN on unknown.
A detached HEAD, a path that is not a worktree root, or a git that will not answer are all UNKNOWN —
announced and resumed — because stranding a real recovery is worse than the bug
(`tests/lr-resume-tombstone-guard.bats` states the same asymmetry). `CC_RESUME_ALLOW_BRANCH_DRIFT=1`
is the deliberate override.

The comparison is anchored on `rev-parse --show-toplevel` equalling the physical path, not on
`--abbrev-ref HEAD` alone. A bare `HEAD` read is answered for by whatever repository the path
happens to sit **under**, which would convict a plain directory on a branch it does not own — and
the first casualty would have been this file's own bats fixtures (memory:
`guard-refusal-fires-on-its-own-harness`). Test 4 of the six pins exactly that, and mutating the
toplevel check to `true` reddens that case and only that case.

## 5. The generalisable lesson

**A work item whose correctness depends on a snapshot must carry that snapshot's expiry.** This row
said "re-run when the box has room" and named a resource — capacity — that recovers in minutes,
while the artifact it pointed at rots in days. The queue then held it for fourteen of them. The
p90 dwell in this backlog is 9.3 days, so an instruction of the form *"replay this file later"* is
closer to the norm than to the edge case.

Two dispositions follow, and this commit takes the second:

1. Put an expiry on the row — helps this row, and no other.
2. **Put the staleness check where the batch is CONSUMED.** A resume can now say *"this is not the
   worktree that row named"* no matter which caller, file or fourteen-day-old TSV produced it.

Related: `work-item-next-step-inherits-its-stores-half-life` (a next step needing an ephemeral store
expires with it) — this is that rule with the store being the machine's own worktree layout, and
`enforcement-must-live-at-the-chokepoint`.

## 6. Supersession adjudication

The two sibling items flagged as possible supersessions — `8d84bdf7a047` and `92b48ac81692` — are
`deploy-live` convergence rows. They touched `bin/cc-resume-layout.sh` only incidentally and hold
none of this item's subject matter. Neither supersedes it.

## 7. Dispatcher vintage

`bin/cc-dispatch` blob `b4e8edb92e176248264267cd7a9a7cb04cfb1cbe` **equals** `origin/main`, so the
dispatcher that composed this brief is trunk. The worktree read `HEAD..origin/main = 0` and the
repository is not shallow: every trunk read above is a real read.

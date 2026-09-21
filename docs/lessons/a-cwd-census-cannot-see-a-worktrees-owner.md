# A cwd census cannot see a worktree's OWNER, only its workers

**Measured 2026-09-21, claude-infrastructure.** A peer session (`claude-infrastructure-428`)
looked for a live owner of `~/Development/.worktrees/wt-lr-100p`, found none by cwd census,
declared the worktree DEAD, and landed the two commits sitting on its branch.

The worktree was not dead. It belonged to the live `LIMIT_RECOVER_100P` lead (`d90959db`), which
had committed to it four minutes earlier and was about to commit to it again.

## Why the census was sound in form and wrong in fact

The rule it applied is a good one and is already in this fleet's memory as
`argv-is-sampling-cwd-is-durable`: *argv is blind while a worker THINKS, so key liveness on cwd.*
That rule is true **of a worker**. It is false of a **lead**.

A wave lead's own cwd is the repository root. It owns N worktrees *remotely* — it creates them,
briefs an agent into each, merges them, lands them, and writes its plan-doc commits into one of
them — while never once being cwd'd in any of them. So a cwd census over a lead-owned worktree
returns the empty set by construction, and returns it **with exactly the same shape** as a census
over a genuinely abandoned worktree.

The two states demand opposite actions — land the stranded commits, versus keep your hands off
another session's in-flight branch — and the instrument cannot separate them.

## Why it did not cost anything this time, and why that is luck

The commits were documentation, the gate was green, and the land was content-verified. Had they
been mid-wave code, this is precisely the incident `.claude/CLAUDE.md` opens with: commit `dfacccd`
(the limit-recover skill, 5 new files) silently dropped by a sibling's land of a branch it did not
own, while `git rev-list origin/main..HEAD` read 0 and therefore "looked landed".

The near-miss and the recorded incident share one root: **a session acted on another session's
branch on the strength of an absence.**

## The rule

Before treating a worktree as ownerless, ask for a POSITIVE owner signal, not the absence of a
cwd match:

1. **Recency beats presence.** `git -C <wt> log -1 --format=%cr` — a commit minutes old is a live
   owner however empty the cwd census is. Nothing abandoned commits four minutes ago.
2. **Ask the branch, not the directory.** A lead's worktrees are named for its wave
   (`wt-lr-w5a`…`wt-lr-w5f`) and its branches for its plan (`lr100p/*`). A live session whose own
   plan owns that namespace is the owner, wherever it is cwd'd.
3. **A census that cannot produce an owner has abstained, not acquitted.** Say `UNKNOWN` and leave
   the branch alone; the cost of waiting is a parked commit, and the cost of being wrong is a
   dropped one.

Landing someone else's branch is not a favour when you cannot name who you took it from.

**Companions:** [[argv-is-sampling-cwd-is-durable]] (the rule this refines — it holds for workers
and fails for owners) · [[clean-worktree-cannot-distinguish-never-worked-from-landed]] ·
[[one-armed-adjudication-only-convicts]] (an absence-only instrument can convict and never
acquit) · [[a-never-engaged-verdict-is-mostly-false-and-its-real-cost-is-the]].

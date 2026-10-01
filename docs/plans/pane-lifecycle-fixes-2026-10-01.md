---
status: open
---

# Pane-lifecycle fixes, 2026-10-01: brief for one dispatched session

You are a dispatched session in ~/Development/claude-infrastructure (fresh worktree). Read the repo's .claude/CLAUDE.md first; land only through scripts/ship-land.sh, never wrapped in your own timeout.

Scope (frozen): fix the pane-lifecycle defects that three read-only investigations found on 2026-10-01, after the husk F-a..F-e wave landed. For each item: confirm the defect on current trunk, write a failing bats arm, implement, prove with one mutant, then land. Raise conviction above 90% by reading code and measuring before you implement. Anything still below 90% after that goes to the operator as `cc-decide open --class C` with a number and a receipt. Never guess.

Evidence (read all three first; each gives file:line):
- docs/research/selfclose-failures-2026-10-01.md: self-close refusals and failures, modes M1-M12, ranked fixes.
- docs/research/recycle-unreachable-2026-10-01.md: --recycle aborts when kitty's API stalls under load.
- docs/research/husk-triage-2026-10-01.md § Gaps: custody is never consulted after a lead's death.

Items, in order (scripts/handoff-fire.sh is the shared file; you are its only writer this wave):
1. Stale-stamp self-close refusal of genuine fired peers (M1). Let the brief-contract repair and marker-proven adoption run on `stale`, not only `absent` (:10370, :10464). Move the superseded record aside, never overwrite it.
2. Check the stamp's marker before trusting a `valid` or `unknown` stamp (M9, near :10359).
3. Write closedAt and discharge custody only after the pane proof succeeds, or roll both back on abort (M10, :10864 vs :10988).
4. --recycle under a stalled kitty API: wait for the terminal to answer, in a detached helper, instead of aborting at :15029. Prefer resolving the self pane's tty from its own process tree, which needs no terminal call. Add per-phase timing to the recycle log row.
5. --window/os-window duplicate fire (M11, :14479 / spawn_frontmost): treat kt_launch UNKNOWN like it2_split rc 13, and never let fire-cleanup remove the worktree on UNKNOWN.
6. bin/reso-resume-one:712: close from inside on a clean exit with no recycle pending, reusing F-a's lib/pane-recycle-pending.sh.
7. Custody-aware husk verdicts: a lead whose custody was abandoned or returned after its death must not get "Resume it here" (hooks/lead-crash-watchdog.sh crash branch) and must not be resumed by `cc-husk-sweep --resume` (UNKNOWN is resumed today). Add a custody arm in both.

Never: close, kill or type into any pane; write settings*.json or allowlists; use --no-verify; run `git stash`, `rm -r` or `git reset --hard`. Any interactive prompt has no human to answer it. Stop on an issue and message the lead (cc-notify 09c26b2b-dd82-4cf2-b884-395d02cbddf1 "<message>").

Done = every item landed on origin/main, content-verified with git ls-tree plus an empty diff, its bats suites run by you with the `1..N` line shown and zero not-ok, and `CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh` converged. Then send a DONE ping.

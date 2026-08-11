---
name: resume-sessions
description: Recover and autonomously resume open Claude Code sessions across the 4 accounts after a crash or reboot, and un-stick sessions that stalled after /compact — inventory, shared selector, worktree recreation, non-blocking resume, re-engagement, keepalive. Use when the machine crashed/rebooted with sessions open, when sessions look stuck after resume→/compact (empty input box or ^[[<35;… gibberish), or on "recover my sessions" / "resume the crashed sessions" / /resume-sessions.
allowed-tools: Bash, Read, Skill
argument-hint: "[sid or account to resume just one] [--dry-run — show the triage table and fire nothing]"
---

# /resume-sessions — crash recovery + autonomous restart

This command exists because `skills/resume-sessions/SKILL.md` advertised a `/resume-sessions`
trigger that had no command file behind it — the runbook named an entrypoint that did not exist
anywhere in the tree, so the one phrase a reader would type after a crash resolved to nothing.

## Steps

1. **Load the runbook and follow it — do not improvise a recovery.**

   ```
   Skill(resume-sessions)
   ```

   It owns all five phases (inventory → shared selector → per-session resume → re-engagement →
   keepalive), and every one of them has a scar attached. `REFERENCE.md` beside it holds the
   rationale; read it when a step misbehaves.

2. **Show the selector's triage table (its stderr) to the operator BEFORE firing anything.**
   That table is what makes "14 sessions for one worktree" visible *before* it consumes 2.76 GB.
   `--dry-run` stops here.

3. **The engine is `bin/reso-resume-one`** (deployed as `~/.reso/bin/reso-resume-one`, a symlink).
   Two flags carry the operator's standing constraint that a recovered session comes back as the
   session it was:

   - `--effort <low|medium|high|xhigh|max>` — the account fixes the MODEL only. Pass the tier the
     session was running at, or a Fable-5-at-max session returns at `high` with a statusline that
     still reads "Fable 5".
   - `--repo <path>` — only needed when a reaped worktree's owner cannot be derived (two repos
     carrying the same branch name, and no `.git/worktrees` back-reference to it).

   It selects **"Resume full session as-is"**, not the summary. Option 1 `/compact`s the transcript
   and drops the session-scoped `/goal` hook, which is what left recovered sessions idle.

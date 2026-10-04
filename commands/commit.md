---
description: Atomic task-specific git commit with fixup/autosquash
disable-model-invocation: true
allowed-tools: Bash(git *), Bash(pnpm generate), Read
argument-hint: [task context]
---

> **Project rail first.** If the current repo's root holds `.claude/commands/commit.md` or
> `.claude/skills/commit/SKILL.md` (Read it; a missing file is the answer), stop reading this file
> and follow that one: a repo's own `/commit` owns the name inside that repo.

Task context: $ARGUMENTS

## State

- !`git status --short`
- !`git log --oneline -10`

## Workflow

1. **Isolate**: If unrelated changes exist from other sessions,
   `git diff > /tmp/stash.patch` then `git checkout -- <file>` per
   unrelated file. Mixed-change files: checkout, re-apply only this
   task's edits, stage.

2. **Stage by name**: `git add <files>` — never `git add .`
   If `drizzle/schema.ts` changed, run `pnpm generate` first and
   stage migrations together.

3. **Commit**: `type(scope): description` — match recent commits
   above for scope/style. HEREDOC format.

4. **Fixup?**: Only if this corrects a specific prior commit —
   `git commit --fixup=<hash>` then
   `GIT_EDITOR=true git rebase --autosquash <hash>~1`.
   Default: always new commit.

5. **Restore**: If patch saved in step 1,
   `git apply /tmp/stash.patch`. Final `git status`.

Stay scoped to committing: decide what belongs from `git status` / `git diff`, read a file only for the project-rail check above, and add no narrative beyond the commit.

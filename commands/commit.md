---
description: Atomic task-specific git commit with fixup/autosquash
disable-model-invocation: true
allowed-tools: Bash(git *), Bash(pnpm generate), Read
argument-hint: [task context]
---

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

DO NOT read files, explore code, or add narrative beyond the commit.

# claude-infrastructure — Project Memory

Project-only rules for THIS repo. Loaded as project memory (`./.claude/CLAUDE.md`, per CC docs) only
when working in `~/Development/claude-infrastructure`. NOT part of the global `~/.claude/CLAUDE.md`
core — kept here so a claude-infrastructure-specific safety rule never ships to every other project.

## Never commit or land in the shared checkout

`~/Development/claude-infrastructure` is the symlink source for `~/.claude` and frequently sits on
another session's feature branch. Committing there risks (a) landing onto a branch you did not
create, and (b) a concurrent `/ship` of that branch rebase-dropping your commit — incident
2026-07-11: `dfacccd` (limit-recover skill, 5 new files) silently dropped by a sibling land of
`feat/two-way-session-comms`; `git rev-list origin/main..HEAD` read 0 ('looks landed') while the
files were absent from main. Always work in a dedicated worktree, commit on your OWN branch, and
land via the project-local `/ship`. Verify landings by CONTENT (`git ls-tree origin/main --
<paths>`), never by count.

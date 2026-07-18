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

## Standing-land authorization (this repo only)

In THIS repo, work that is **complete + gate-green + committed on your own branch** lands via the
project-local `/ship` flow **without a fresh ask** — the 📦-offer/wait cycle is waived here
(operator standing directive 2026-07-18: identified net-positive work is finished, not offered;
Follow-On Gate F1-F4 in the global CLAUDE.md governs what qualifies). Why scoped here: parked
commits leave the LIVE `~/.claude` layer stale (this repo is its symlink/source), so
committed-not-landed is itself "work left on the table". The authorization is exclusively for the
fail-closed project-local `/ship` (landing lock + last-moment re-fetch + full gate + content-verify
+ stranded sweep) — never a bare `git push`. Global Git Safety is unchanged for every other repo.
After landing, sync the non-symlinked live copies (`~/.claude/CLAUDE.md` is a separate real file —
apply the same edits there; most of `skills/ hooks/ bin/ scripts/ commands/` are per-file symlinks
into the checkout and go live on the trunk fast-forward).

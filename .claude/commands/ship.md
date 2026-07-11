Land claude-infrastructure's current work onto the remote trunk, safely, under a
machine-wide landing lock with **content-level** verification. This project-local
`/ship` OVERRIDES the global `/ship` **inside this repo only** — infra is the
`~/.claude` symlink source and is frequently worked on by several concurrent
sessions, so its landing flow must be fail-closed against a sibling session moving
`origin/main` mid-flight. (Global light `/ship` still applies to every other repo.)

Arguments: `$ARGUMENTS`
- `--dry-run` — do everything except the final push; stop and print the reconciled plan.
- `--trunk <branch>` — target branch (default: auto-detected `origin/HEAD`, else `main`).

## 1. Preflight (read-only)
- **Trunk** = `git symbolic-ref --quiet refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@'`, else `main` (honor `--trunk`).
- Record: current branch, whether this is a linked worktree, `git status --short`, and — after `git fetch origin <trunk>` — `git rev-list --count origin/<trunk>..HEAD` (how much is unpushed). Note the count is a *starting* reference only; it is NOT the landing proof (see step 6).

## 2. Shared-checkout guard (root fix)
- **NEVER commit or land from `~/Development/claude-infrastructure`.** It is the source of the `~/.claude` symlink and often sits on a *foreign session's* feature branch — committing there risks landing onto a branch you did not create, and a concurrent `/ship` of that branch can rebase-drop your commit.
- Resolve the real CWD (`git rev-parse --show-toplevel`). If it is `~/Development/claude-infrastructure` → **STOP**: tell the user to re-run from a dedicated worktree (`claude -w <name>`), then land from there.
- Proceed only from a dedicated worktree on your **own** branch.

## 3. Commit in-scope work
- Stage **only** the files belonging to the current task — explicit paths, **never** a blind `git add -A`. Make one atomic Conventional Commit (lowercase, no redundant verbs).
- Unrelated or foreign changes present → **STOP**, do not sweep them in. Save them (`git diff > /tmp/stash.patch`), commit only the task, restore after.
- Already clean → continue.

## 4. Safety backup (before any history rewrite)
- `git branch -f ship/backup-<shortsha> HEAD`. This is the rollback point if the reconcile or push goes wrong — it stays intact on any fail-closed stop below.

## 5. Locked pipeline (reconcile + gate + push as ONE child under the landing lock)
Run the whole reconcile-gate-push as a single child process **under the landing lock** so `origin/main` cannot move between your rebase and your push:

```
scripts/land-lock.sh -- bash -c '<pipeline>'
```

`<pipeline>` (in order, fail-closed at every step):
- **Re-fetch the tip at the LAST moment** — `git fetch origin main` *inside* the lock so any sibling commits that landed while you were gating ride along in your rebase base.
- `git rebase origin/main` — keeps history linear. Any conflict that does not auto-resolve → **STOP** fail-closed (leave the rebase in progress, backup intact); never force past a conflict.
- **GATE** (prove green before landing): `shellcheck` on changed `*.sh`, `bats tests/` if present, `bash -n` on changed shell scripts, and `python -m py_compile` on changed `*.py` where present. Any gate failure → **STOP**, report which gate failed, do not push. Never `--no-verify`.
- `git push origin HEAD:main` — fast-forward land. **Never force-push `main`.** A non-fast-forward rejection means a sibling beat you inside the window → **STOP** fail-closed and re-run `/ship` (re-acquires the lock, re-fetches, re-rebases).

## 6. Content-verify (never count-only — count is what missed the incident)
- After the push: `git fetch origin main`.
- For **every changed path in the landed range**, assert BOTH:
  - `git ls-tree origin/main -- <paths>` shows the paths present on the landed trunk, AND
  - `git diff HEAD origin/main -- <paths>` is **empty** (trunk content matches what you shipped).
- A bare `git rev-list --count origin/main..HEAD == 0` proves **nothing** after a sibling rebase — it read 0 in the 2026-07-11 incident while the files were absent from `main`. Content-verify is the real landing proof.

## 7. Post-land stranded sweep
- Run `scripts/stranded-sweep.sh`. **Exit 1** means a sibling commit was rebase-dropped from `main` — **STOP** and recover per the recipe it prints before declaring done.
- Exit 0 → no stranded commits; proceed to report.

## 8. Report
- The landing lock releases automatically (its `EXIT` trap) — no manual unlock.
- Emit: landed SHA, gate results, content-verify ✓ (paths asserted present + diff-empty), and the stranded-sweep result. Only then is the 📦 → ✅ transition earned.

## Why locked + content-verified
On 2026-07-11 a concurrent land in claude-infrastructure silently dropped commit
`dfacccd` (the limit-recover skill — 5 new files) from `main`: a sibling session's
rebase-land of `feat/two-way-session-comms` moved `origin/main` between this
session's rebase and push, and the post-land check used only
`git rev-list origin/main..HEAD`, which read **0** — so the land "looked" complete
while the files never reached trunk. The lock (step 5) closes the rebase→push race;
the last-moment re-fetch lets mid-flight sibling commits ride along instead of being
clobbered; the **content-verify** (step 6) and **stranded-sweep** (step 7) catch what
a count check structurally cannot.

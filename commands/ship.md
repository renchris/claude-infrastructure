Land the current work onto the remote trunk, safely. `/ship` is the explicit
"push / land" action referenced by the Session Close Protocol's 📦 Parked state —
invoking it IS the authorization to push (that is the whole point of the command).

The default flow is tuned for **solo, single-branch** projects (you commit on the
trunk and push to origin). It also handles landing a feature branch or a worktree
back onto trunk.

Arguments: `$ARGUMENTS`
- `--dry-run` — do everything except the final push; stop and print the plan.
- `--no-gate` — skip the typecheck/lint/test gate (only when you know it is green).
- `--trunk <branch>` — target branch (default: auto-detected `origin/HEAD`, else `main`).

## 1. Preflight (read-only)
- **Trunk** = `git symbolic-ref --quiet refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@'`, else `main` (honor `--trunk`).
- Record current branch, whether this is a linked worktree, `git status --short`, and — after a `git fetch origin <trunk>` — `git rev-list --count origin/<trunk>..HEAD` (how much is unpushed).
- **No `origin` remote?** STOP: there is nothing to push to. Offer to add a remote or run `/pr`.

## 2. Commit in-scope work (per global git rules)
- If the tree is dirty: stage **only** the files belonging to the current task (explicit paths — never a blind `git add -A`) and make one atomic Conventional Commit (lowercase, no redundant verbs). Split unrelated changes into separate commits; if a pre-existing unrelated change is present, save it (`git diff > /tmp/stash.patch`), commit only the task, restore after.
- **Shared checkout?** Never commit onto a pre-existing feature branch you did not create THIS session — create your own branch (or temp worktree) first. A concurrent landing of that branch can rebase-drop your commit (claude-infrastructure incident 2026-07-11).
- Already clean → continue.

## 3. Safety backup (before any history rewrite)
- `git branch -f ship/backup-<shortsha> HEAD` (or `git bundle create` for a detached/worktree state). This is the rollback point if the reconcile goes wrong.

## 4. Reconcile onto trunk
- `git fetch origin <trunk>`.
- Rebase the current work onto the freshest trunk: `git rebase origin/<trunk>` — keeps history linear and eliminates the non-fast-forward push. (Enable `git rerere` for repeated conflicts.)
- Conflicts that don't auto-resolve → STOP: report the files, leave the rebase in progress for the user. Never force past a conflict.
- **Ordered-artifact caveat:** if the project has ordered migrations (a `_journal.json` / numbered migration dir) and origin added new ones, a plain rebase can silently drop yours — STOP and ask, or use the project's own reconcile script (see the reso reference below). Generic `/ship` does **not** auto-resolve migration collisions.

## 5. Gate (prove green before landing)
- Detect the package manager from the lockfile (`pnpm-lock.yaml`→pnpm, `bun.lockb`→bun, `package-lock.json`→npm) or the language toolchain.
- Run what the project actually has, skipping cleanly if absent: typecheck (`tsc --noEmit` / `pnpm typecheck`), lint, unit tests. Shell projects → `shellcheck` + the suite (e.g. `bats`).
- Any gate failure → STOP, report which gate failed with output, do **not** push. (Skip only with `--no-gate`.)

## 6. Escalation halt (STOP-ASK)
- Scan the landing range (`origin/<trunk>..HEAD`) for escalation surfaces and STOP-ASK before pushing if present: destructive DB migrations (`DROP TABLE|COLUMN`), auth/session changes, navigation-pattern changes. Land these only with explicit confirmation.

## 7. Land
- `--dry-run` → stop here; print reconciled SHA + gate results, no push.
- Push: on trunk directly → `git push origin HEAD:<trunk>`; a rebased feature branch → fast-forward land `git push origin HEAD:<trunk>` (or open/merge via `/pr` if the project uses PRs).
- **Never force-push `main`/`master`.** A non-fast-forward rejection means re-fetch and re-reconcile (step 4) — never `--force` the trunk.
- **Verify by CONTENT, never by count.** After the push, `git ls-tree origin/<trunk> -- <your changed paths>` must show them AND `git diff <your-sha> origin/<trunk> -- <paths>` must be empty. `origin/<trunk>..HEAD == 0` proves nothing after someone else's rebase. Then sweep local branches for stranded commits (`git cherry origin/<trunk> <branch>`, or a project's `scripts/stranded-sweep.sh`).
- On success delete the backup branch; on failure keep it and print recovery steps.

## 8. Report (Session-Close readout)
- Emit the governing one-liner: `✅ Complete & live on trunk` when `origin/<trunk>..HEAD == 0` after the push (the 📦 → ✅ transition). Include: landed SHA, gate results, and any deploy/CI a trunk push triggers if the project documents one. **Confirm the landing by CONTENT (per step 7 — `git ls-tree` present + `git diff` empty on your changed paths), not by the count alone** — a sibling rebase can zero the count while your files never reached trunk.

## Solo single-branch vs. multi-agent
- **Solo single-branch (default, most projects):** work on trunk → commit → fetch → rebase → gate → `push origin HEAD:main`. Done.
- **Worktrees / Agent Teams (concurrent writers):** land each worktree onto trunk **serialized, smallest-diff first, `--ff-only`** after rebase; serialize migration-generating sessions; `git rerere` on. `/handoff` parks unfinished work; `/ship` lands finished work.
- **High-concurrency projects** needing migration-safe reconcile (rebase-vs-cherry-pick) + a machine-wide landing lock have a fuller reference to borrow from: `reso-management-app/scripts/ship-reconcile.sh`, `scripts/land-lock.sh`, `.claude/commands/ship.md`. Copy those into a **project-local** `.claude/commands/ship.md` when a repo's concurrency/migrations warrant it — this global `/ship` stays intentionally light.

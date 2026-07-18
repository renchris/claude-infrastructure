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

## 4. Land via `scripts/ship-land.sh` (the whole fail-closed pipeline, as code)
The reconcile → gate → push → content-verify → stranded-sweep flow is **no longer prose you hand-execute** — it is one fail-closed script, so a paraphrase or an early stop can never skip the content-verify that caught the 2026-07-11 incident (G-P9-2). Steps 1-3 above (preflight read, shared-checkout guard, in-scope commit) are still yours to do first; then land with:

```
scripts/ship-land.sh [--trunk <branch>] [--dry-run]
```

What it does, in order — it stops **LOUD at the first failure** with the backup ref intact:
1. **Preflight** — refuses **in code** to land from the shared checkout on a non-session branch (exit 4; the prose guard of step 2 is now also enforced), refuses a dirty tree (exit 2), then **escalation-scans** the landing range: a destructive-SQL / credential pattern **PARKS** a class-B decision packet under `~/.claude/autonomy/decisions/` and exits 3 — such changes are **never auto-landed**. (auth/session/navigation code is escalation-worthy too, but is *not* in the default scan for this repo — its normal churn is saturated with those words; extend `SHIP_LAND_ESC_RE` for app repos.) Then it writes the `ship/backup-<sha>` rollback ref.
2. **Locked child** — `scripts/land-lock.sh`, the machine-wide-per-repo mutex now keyed on the **shared git dir** so every worktree of this repo serializes (was per-worktree `--show-toplevel`, G-P9-1). Inside the lock: last-moment `git fetch` → `git rebase origin/<trunk>` (conflict ⇒ exit 5, rebase left in progress, never forced) → **GATE** `shellcheck` + `bats tests/` + `bash -n` + `py_compile` on changed shell/python **including extensionless python by shebang** (fixes the `*.py` glob miss); red ⇒ exit 6, no push; never `--no-verify` → `git push origin HEAD:<trunk>`, never force `main`; a non-fast-forward rejection means a sibling beat you inside the window ⇒ exit 7, re-run `/ship`.
3. **Content-verify** — `scripts/land-verify.sh` asserts, for **every changed path**, that it is present on the trunk **AND** `git diff` against what you shipped is empty. A bare `git rev-list --count origin/<trunk>..HEAD == 0` proves **nothing** after a sibling rebase — it read 0 in the 2026-07-11 incident while the files were absent from `main`. Content-verify is the real landing proof; a failure ⇒ exit 8 with the backup ref intact.
4. **Stranded-sweep** — `scripts/stranded-sweep.sh` sweeps **every local branch** for commits whose content never reached the trunk (this is what catches a sibling's rebase-drop of *your* commit even when it landed from a branch you do not own). **Exit 1 is a REVIEW verdict, never an automatic failure and never an auto-recover**: recover ONLY your **own** just-dropped work via the printed recipe; a peer session's live feature branch (unlanded WIP — expected on a multi-session box) you **leave** — **never** cherry-pick a peer's WIP onto the trunk (the very cross-session interference this flow exists to prevent). `stranded-sweep.sh --mine <session-id>` narrows the sweep to your own drops for a decidable pass/fail.
5. **Self-attesting `land.log`** — each landing appends `{verify, sweep, esc_scan, sid}` so the audit trail can prove a given land was content-verified.

`--dry-run` runs everything up to and including the gate, then stops before the push and prints the reconciled plan. `--trunk <branch>` overrides the auto-detected trunk.

## 5. Report
- The landing lock releases automatically (its `EXIT` trap) — no manual unlock.
- On **exit 0**, `ship-land.sh` has already emitted the landed SHA, gate result, content-verify ✓ (paths present + diff-empty), and the stranded-sweep verdict — only then is the 📦 → ✅ transition earned. On any **non-zero** exit, surface the code and its meaning (2 dirty · 3 escalation-parked · 4 shared-checkout · 5 rebase-conflict · 6 gate-red · 7 non-ff · 8 verify-failed) and **STOP** — each is a fail-closed state above, backup ref intact.

## Why locked + content-verified
On 2026-07-11 a concurrent land in claude-infrastructure silently dropped commit
`dfacccd` (the limit-recover skill — 5 new files) from `main`: a sibling session's
rebase-land of `feat/two-way-session-comms` moved `origin/main` between this
session's rebase and push, and the post-land check used only
`git rev-list origin/main..HEAD`, which read **0** — so the land "looked" complete
while the files never reached trunk. The lock closes the rebase→push race; the
last-moment re-fetch lets mid-flight sibling commits ride along instead of being
clobbered; the **content-verify** and **stranded-sweep** catch what a count check
structurally cannot. All four are now enforced in code inside `scripts/ship-land.sh`
(step 4) rather than left to prose — a model can no longer skip the check that caught
this incident.

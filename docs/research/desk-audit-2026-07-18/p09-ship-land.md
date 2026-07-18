# P9 — Ship/Land & Worktree Safety (how finished work becomes landed work)

Beat objective: map the landing pipeline + its safety envelope, and name precisely what
separates today's "push is the user's call" (G3) from safe 24/7 autonomous landing.

**Coverage:** read 13 of 14 in-scope files (both `ship.md`, `land-lock.sh`+bats,
`stranded-sweep.sh`+bats, `SHIP_LAND_HARDENING_PLAN.md`, all 3 worktree hooks,
`WORKTREE_WORKFLOW.md`, `.claude/CLAUDE.md`, root `CLAUDE.md`) + probed the LIVE
`~/.claude/settings.json` hook wiring, `smart-bash-allowlist.sh`, `boundary-handoff.sh`,
`completion-push.sh`, `~/.claude/land.log` (empirical), `git rerere` config, and a live
worktree lock-key probe. The 14th (`memory/reference-landing-safety-tooling.md`) covered via
its MEMORY.md index line + the hardening plan. Empirical = read/ran; Theoretical = inferred.

**Headline (empirical, RED-proof):** `land-lock.sh` keys its mutex on
`git rev-parse --show-toplevel` (per-worktree path), NOT the shared git dir — so two
worktrees of the same repo get DIFFERENT lock dirs and land CONCURRENTLY. The serializer
built to prevent the 2026-07-11 silent-drop does not serialize across the desk's normal
topology (every session in its own worktree). Live probe: main hash `20e2ff242c91` ≠ wt
`91879085e9c8`; `--git-common-dir` shared. The bats suite overrides `LAND_LOCK_DIR`, so the
keying is untested.

---

## 1. Inventory

| Asset | Role in desk loop | Wiring | Depends on | Verified by | Serves goal | Gap ref |
|---|---|---|---|---|---|---|
| `commands/ship.md` (global, light) | Prompt: land any repo, solo-default | prompt-only slash cmd; symlinked `~/.claude/commands/ship.md`→repo (empirical) | git, `origin`, model following prose | none (prose) | land | G-P9-3,6 |
| `.claude/commands/ship.md` (project-local, heavy) | Prompt: land infra under lock+content-verify; OVERRIDES global in-repo (l.3-6) | prompt-only slash cmd | `land-lock.sh`, `stranded-sweep.sh`, git | none (prose) | land safely | G-P9-1,2,4,5 |
| `scripts/land-lock.sh` | Serialize gate+push (machine-wide-per-repo, claimed) | invoked ONLY by project-local ship.md l.33 (prompt-driven) | `git rev-parse`, `/tmp`, `~/.claude/land.log` | `tests/land-lock.bats` GREEN (7) — but keying untested | land safely | G-P9-1 |
| `tests/land-lock.bats` | Prove lock semantics | manual/CI (`bats tests/`) | bats | 7 tests GREEN | verify | G-P9-1 (blind to keying) |
| `scripts/stranded-sweep.sh` | Post-land: detect content-dropped commits across all local branches | invoked by project-local ship.md l.50 (prompt-driven); standalone-callable | `git cherry`, `git ls-tree` | `tests/stranded-sweep.bats` GREEN (4) | verify landed | G-P9-2,7 |
| `tests/stranded-sweep.bats` | Prove drop-detection + false-pos guard | manual/CI | bats + scratch repos | 4 tests GREEN | verify | none |
| `docs/plans/SHIP_LAND_HARDENING_PLAN.md` | Design record of the hardening | doc | — | status=COMPLETE, dogfood-landed | audit | none |
| `hooks/git-worktree-guard.sh` | Block reaping a live worktree/branch | **hook-enforced** PreToolUse(Bash), `~/.claude/settings.json:435` | `git worktree list`, `pgrep`/`lsof` | none (no test found) | protect WIP | G-P9-8 |
| `hooks/worktree-setup.sh` | Provision worktree for `claude -w` | **hook-enforced** WorktreeCreate, settings:850 | `jq`, pool/`new-worktree.sh` | none (no test found) | isolate writers | G-P9-9 |
| `hooks/check-edit-boundary.sh` | freeze/focus edit fencing | **hook-enforced** PreToolUse(W/E/ME), settings:459 | `jq`, `~/.claude/edit-boundary.json` | `boundary-hook-e2e.sh` present | scope edits | none |
| `hooks/smart-bash-allowlist.sh` | Auto-approve safe Bash incl. `git push` | **hook-enforced** (permission classifier) | grep patterns | `hooks/tests/validate-bash.test.sh` | autonomy | G-P9-3 |
| `hooks/boundary-handoff.sh` | Advisory /handoff-at-boundary (NOT ship/land) | **hook-enforced** Stop, settings:803 | telemetry/IDL | in-file blind-check notes | handoff | out-of-beat |
| `~/.claude/land.log` | Per-landing JSON telemetry | written by land-lock l.44-47 | — | 38 real entries (empirical) | audit trail | G-P9-10 |
| `git rerere` | Reuse conflict resolutions | **git-config-enforced**, global=true (empirical) | git | empirical | reconcile | none |
| `scripts/completion-push.sh` | OPERATOR notification push (cc-announce), NOT git land | prompt/exit-recipe | cc-announce | selftest | (comms beat) | out-of-beat |
| `scripts/worktree-gc.sh` | Referenced by guard hook as reap remediation | **ABSENT in this repo** (reso-only) | — | — | — | G-P9-8 |

No launchd plist lands work (only team-orphan-reaper / session-search / getAppState-fix).
No `core.hooksPath`, no `.git/hooks/pre-push|pre-commit` → the gate is NOT git-enforced in
infra (contrast reso's pre-push, `WORKTREE_WORKFLOW.md:156-159`).

---

## 2. Mechanism — the landing pipeline end-to-end

**Two variants, one override rule.** Inside `~/Development/claude-infrastructure` the
project-local `.claude/commands/ship.md` overrides the global (project-local ship.md:3-6).
Every other repo uses the global light `commands/ship.md`. Both are **prompt-only** — a slash
command is prose a model reads and executes; nothing invokes them autonomously (grep for
`git push`/auto-land across scripts/hooks/launchd = clean; only a permission-allowlist rule +
its test mention `git push`).

**Human touchpoints marked [H]:**

Global light `/ship` (`commands/ship.md`):
1. Preflight read-only: trunk detect, unpushed count (l.15-16). No `origin` → STOP [H] (l.17).
2. Commit in-scope, explicit paths (l.20). Shared-checkout warning: don't commit onto a
   foreign feature branch (l.21) — **prose**.
3. Safety backup `ship/backup-<sha>` (l.25).
4. `git fetch` + `git rebase origin/<trunk>` (l.28-29); conflict → STOP [H] (l.30); ordered-
   migration caveat → STOP [H] (l.31).
5. Gate: detect PM, run typecheck/lint/test (l.34-36); fail → STOP [H]. **`--no-gate` escape
   flag exists** (l.11) — a documented gate bypass.
6. Escalation halt: grep range for DROP TABLE/auth/nav → STOP-ASK [H] (l.39).
7. Land: push `HEAD:<trunk>`; never force main (l.43-44). **Content-verify by prose** (l.45):
   `git ls-tree` present + `git diff` empty; then sweep (`git cherry` or a project sweep).
8. Report ✅ only after content-verify (l.49).

Project-local heavy `/ship` (`.claude/commands/ship.md`) — fail-closed:
1. Preflight; count is a *starting ref only, NOT proof* (l.14).
2. **Shared-checkout guard [H]**: resolve `git rev-parse --show-toplevel`; if it is
   `~/Development/claude-infrastructure` → STOP, re-run from a worktree (l.16-19) — **prose,
   not code** (land-lock has no such refusal; confirmed).
3. Commit in-scope; foreign changes → STOP [H] (l.22-23).
4. Backup ref (l.27).
5. **Locked pipeline as ONE child** (l.29-40): `scripts/land-lock.sh -- bash -c '<pipeline>'`;
   pipeline = last-moment `git fetch origin main` INSIDE lock (l.37) → `git rebase origin/main`,
   conflict → STOP [H] (l.38) → GATE shellcheck+bats+`bash -n`+`py_compile` (l.39) → `git push
   origin HEAD:main`, non-ff reject → STOP + re-run [H] (l.40). **No `--no-gate` flag** (only
   `--dry-run`/`--trunk`, l.9-10) — gate is mandatory here.
6. **Content-verify** (l.42-47): per changed path, `git ls-tree origin/main` present AND
   `git diff HEAD origin/main -- <paths>` empty. Count "proves nothing" (l.47). **Prose.**
7. **Stranded-sweep** `scripts/stranded-sweep.sh` (l.49-54): exit 1 = **REVIEW [H]** — recover
   only YOUR dropped commit; leave peer WIP. Never cherry-pick peer WIP onto main.
8. Report; lock auto-releases via EXIT trap (l.57).

`land-lock.sh` internals: `REPO_ROOT=git rev-parse --show-toplevel` (l.27) → `HASH=shasum|cut
-c1-12` (l.28) → `LOCK=/tmp/land-lock-<hash>/lock.d` (l.29-30). `mkdir` mutex (l.61). Reap rule
(l.60-79): LIVE holder pid NEVER reaped even past TTL (l.69-70, deliberate divergence from reso,
l.57); DEAD pid reaped immediately (l.71-72); empty pid past 5s grace/TTL (l.66-68). Kill switch
`LAND_SERIALIZE=off` → `exec` unlocked (l.50-53). Holds ONLY across the wrapped cmd (l.8-9).
Telemetry JSON per landing → `~/.claude/land.log` (l.44-47). Wait-timeout → exit 75 (l.88).

`stranded-sweep.sh` internals: for each local branch (l.32), `git cherry origin/<trunk>` (l.78)
→ each `+` sha not SHA-reachable on trunk (l.44) whose changed paths are ALL absent from trunk
(`git ls-tree`, l.49-61) = STRANDED (l.63); prints recovery recipe (l.70-74). Path present on
trunk with different content → NOT flagged (false-pos guard, l.53-54). Exit 1 if any (l.85).

**Empirical landing evidence** (`~/.claude/land.log`, 38 entries): real lands from
`/private/tmp/wt-*` worktrees (hold 2-111s); one `exit:6` (gate caught a failure) then `exit:0`
(gate works); AND one land at `2026-07-18T03:20` with `repo=/Users/chrisren/Development/claude-
infrastructure, branch=main` — **a land FROM the shared checkout on main**, which the
project-local step-2 guard forbids → the prose guard was bypassed at least once.

---

## 3. Gaps & fragilities

| ID | file:line | FM | Sev | Failure scenario | Fix sketch |
|---|---|---|---|---|---|
| G-P9-1 | `scripts/land-lock.sh:27-28` | 24x7 | **P1** (P0 under concurrent-land load) | Lock keys on `--show-toplevel` = per-worktree; two infra worktrees landing concurrently get different lock dirs and both enter the rebase→push window. The serializer's stated "across all worktrees of that repo" (header l.7-8) is FALSE. Empirically proven (hashes differ; `--git-common-dir` shared). The exact race behind 2026-07-11 is not closed by the lock — only by the weaker non-ff-reject backstop + prose content-verify. | Key on `git rev-parse --path-format=absolute --git-common-dir`, strip `/.git`, `/worktrees/<n>` → identical across all worktrees. Add a bats test that does NOT override `LAND_LOCK_DIR` and asserts two worktrees hash-collide. |
| G-P9-2 | `.claude/commands/ship.md:42-47` | 24x7 | **P1** | Content-verify (the ONE check that caught the incident) is PROSE the model executes, not code. A model that stops after push (step 5) or paraphrases step 6 skips it silently. No script asserts "my changed paths present on trunk + diff empty". | Ship a `scripts/land-verify.sh <sha> <trunk>` that exits non-zero unless every changed path is `ls-tree`-present AND `git diff` empty; call it inside the locked child so a red verify fails the land. |
| G-P9-3 | `hooks/smart-bash-allowlist.sh:118-128` | 24x7 | **P1** | Protected-branch regex l.123 `^(develop|production|prod|release.*)$` OMITS `main`/`master` despite the l.118 comment "(not main/master…)". `git push origin main` (no-force) is AUTO-APPROVED (confirmed by `validate-bash.test.sh:182` → allow). So the permission layer does NOT gate autonomous trunk landing — only the G3 prompt rule + absence of an auto-invoker do. | Decide intent: if trunk push must stay human-authorized, add `main|master` to l.123 and the test; if desk auto-land is wanted, gate it behind the T-P9-1 wrapper, not a bare `git push`. |
| G-P9-4 | `.claude/commands/ship.md:16-19` vs `scripts/land-lock.sh` | 24x7 | **P1** | Shared-checkout guard ("never land from `~/Development/claude-infrastructure`") is PROSE only; `land-lock.sh` has no path refusal. `land.log` shows a real land from the shared checkout on main (2026-07-18T03:20) → the guard was bypassed. Landing there can push a foreign session's branch / be rebase-dropped (the incident class). | Enforce in code: `land-lock.sh` (or a preflight) refuses when `--show-toplevel` == the canonical shared checkout AND branch is not session-owned; exit non-zero LOUD. |
| G-P9-5 | `.claude/commands/ship.md:49-54` | 24x7 | **P1** | Stranded-sweep exit 1 requires HUMAN judgment ("your dropped work vs peer WIP") — on a multi-session box exit 1 is the NORMAL state (any peer with unlanded WIP trips it). An auto-lander can neither safely cherry-pick (pulls peer WIP onto main) nor safely ignore (misses its own drop). This is THE blocker to lifting G3. | Make ownership machine-decidable: stamp each session's commits with a session-id trailer / per-session ref namespace; teach the sweep a `--mine <session-id>` mode that recovers only own-drops and is silent on peers → turns REVIEW into a decidable pass/fail. |
| G-P9-6 | `commands/ship.md:11` | FM1 | **P2** | Global `/ship` has a `--no-gate` bypass; an autonomous or hurried lander can push ungated (no git-level pre-push in infra to backstop it). | Remove `--no-gate` from any auto-land path; require an explicit human token to use it. |
| G-P9-7 | `scripts/stranded-sweep.sh:53-54` | FM2 | **P2** | Drop-detection only fires when ALL changed paths are absent from trunk. A commit that ADDS files AND edits an existing tracked file (mixed) is NOT flagged if the edited file exists on trunk — a partial drop of the new files slips through. | Tighten: also flag when a `+` commit's NEW-file subset is entirely absent even if edited files exist; or diff-content-compare per path. |
| G-P9-8 | `hooks/git-worktree-guard.sh:40,57` | FM2 | **P2** | Guard's remediation hint points to `scripts/worktree-gc.sh`, which does NOT exist in this repo (reso-only) → a blocked operator following the hint hits a missing script. Guard still blocks correctly; only the advice dangles. | Make the hint conditional on the script's presence, or ship a minimal `worktree-gc.sh` here. |
| G-P9-9 | `hooks/worktree-setup.sh`, `git-worktree-guard.sh` | FM2 | **P2** | Worktree hooks have no bats/e2e test in `tests/` (unlike land-lock/stranded-sweep). A stdout-contract regression (the exact 2026-07-02 break: JSON on stdout killed `claude -w`) would ship silently. | Add a WorktreeCreate stdout-contract test + a guard block/allow test. |
| G-P9-10 | `scripts/land-lock.sh:44-47` | 24x7 | **P2** | `land.log` records only `{wait,hold,exit,pid}` — NOT the content-verify result, sweep result, or escalation-scan result. The audit trail can't prove a given land was content-verified. | Extend the JSON with `verify:ok|skip`, `sweep:0|n`, `esc_scan:clean|hit` so the trail is self-attesting for a 24/7 loop. |

---

## 4. Task candidates (incl. the complete safe-auto-land requirements list)

| ID | Action | Acceptance criterion | Depends on |
|---|---|---|---|
| T-P9-1 | Fix land-lock keying to `--git-common-dir` | Two worktrees of one repo resolve to the SAME lock dir; new bats test (no `LAND_LOCK_DIR` override) proves hash-collision; existing 7 tests stay green | — |
| T-P9-2 | Extract the whole ship pipeline into a single `scripts/ship-land.sh` (not prose) | acquire lock → refetch → `rebase` → gate → `push` → content-verify → sweep, fail-closed exit codes; the .md becomes a thin caller | T-P9-1 |
| T-P9-3 | `scripts/land-verify.sh` — content-verify as code | exits non-zero unless every changed path is `ls-tree`-present on trunk AND `git diff` empty; wired inside the locked child | T-P9-2 |
| T-P9-4 | Session-ownership tagging + `stranded-sweep --mine` | commits carry a session-id; sweep recovers only own-drops, silent on peers; exit code becomes decidable pass/fail | — |
| T-P9-5 | Enforce shared-checkout guard in code | land refuses (LOUD, non-zero) from the canonical shared checkout on a non-owned branch | T-P9-2 |
| T-P9-6 | Enforce escalation-scan in code | wrapper greps landing range for DROP TABLE/COLUMN, auth/session, nav; on hit → PARK for human, never auto-land (blast-radius cap) | T-P9-2 |
| T-P9-7 | Resolve the push-permission intent | add `main|master` to allowlist l.123 (+ test) so bare `git push origin main` is NOT auto-approved; route sanctioned auto-land only through T-P9-2's wrapper | G-P9-3 |
| T-P9-8 | Extend `land.log` schema | each entry carries verify/sweep/esc-scan results | T-P9-3 |
| T-P9-9 | Add worktree-hook tests | WorktreeCreate stdout-contract + guard block/allow bats | — |

**Complete requirements for a SAFE auto-land mode** (what must ALL hold to lift G3 for a
repo; each maps to a T-row):
1. **Serialized** — a correct machine-wide-per-repo lock (T-P9-1). *Currently broken.*
2. **Linear** — `rebase` then `push` fast-forward, non-ff → re-enter lock, never `--force`
   (prose exists; must be in the script, T-P9-2).
3. **Gated in code** — typecheck/lint/test actually RUN by the wrapper (behaviorally green,
   not model-asserted), no `--no-gate` on the auto path (T-P9-2, G-P9-6).
4. **Content-verified in code** — own paths present + diff-empty, hard-fail (T-P9-3).
5. **Ownership-decidable sweep** — machine-distinguishes own-drop from peer WIP (T-P9-4).
   *This is the crux that makes G3 liftable.*
6. **Blast-radius cap** — escalation-surface scan auto-PARKS destructive/auth/nav lands for a
   human; per-window landing rate limit; a desk-checked kill-switch file (T-P9-6).
7. **Rollback path** — on post-push verify failure, auto-restore `ship/backup-<sha>` and
   re-enter the lock with bounded retries (new).
8. **Self-attesting audit trail** — land.log carries verify/sweep/esc results (T-P9-8).
9. **Shared-checkout refusal in code** (T-P9-5).
10. **Permission posture matched to intent** (T-P9-7).

---

## 5. Cross-beat dependencies

- **Handoff/spawn beat**: the desk spawns sessions that COMMIT in worktrees but never
  auto-LAND — `WORKTREE_WORKFLOW.md:112-118` frames `/ship` as the mirror of launch; the
  gap between "committed in a worktree" (📦 Parked) and "landed" (✅) is exactly this beat's
  crux. Fired sessions self-close after handoff (WORKTREE_WORKFLOW.md:98-105) but landing is
  left to a human `/ship`.
- **Reaper/worktree-GC beat**: `git-worktree-guard.sh` defends against reaping a worktree
  that holds unlanded WIP; it references `scripts/worktree-gc.sh` (reso-only here). Any
  auto-land loop MUST run BEFORE the reaper harvests a branch, or a landed-but-unverified
  branch could be pruned with its backup ref (interacts with `prune-backups.sh`).
- **Permission-autonomy beat**: `smart-bash-allowlist.sh` decides what the desk may run
  unattended; its push posture (G-P9-3) is the permission-layer half of the autonomy tension.
- **Comms beat**: `completion-push.sh`/cc-announce is how a land result would be surfaced to
  the operator (audit trail consumer for T-P9-8).

---

## 6. Adversarial self-pass (what a hostile reviewer would say I missed)

- *"You assumed the lock works because the tests pass."* — Checked: the 7 bats tests override
  `LAND_LOCK_DIR` (`land-lock.bats:9`), so they NEVER exercise the repo-keying. I probed a
  live worktree instead and proved the key diverges (G-P9-1). The green suite is misleading.
- *"Is content-verify maybe enforced somewhere you didn't look?"* — Grepped scripts/hooks/
  launchd; no `land-verify`/`ls-tree`-gate script exists. stranded-sweep does content-CHECK
  but for OTHER-branch drop-detection, not own-paths-landed. So step 6 is prose. Confirmed.
- *"Does the desk actually auto-land today (making this moot)?"* — No autonomous pusher
  anywhere (grep clean; no launchd land job; no core.hooksPath). Landing is prompt-only. The
  tension is real and unresolved, not already-solved.
- *"Is the shared-checkout land a false alarm?"* — It's empirical in land.log (repo=shared
  checkout, branch=main, exit 0). I could not reconstruct WHY from here (would need transcript
  archaeology, out of scope) → logged as an Uncertainty, but the prose-only nature of the
  guard is code-confirmed regardless.
- *"Partial-drop blind spot?"* — Yes: stranded-sweep only flags all-paths-absent commits, so a
  mixed add+edit commit can partially drop (G-P9-7). Reviewer would catch this; now covered.
- *"You ignored `--no-gate`."* — Global `/ship` has it (G-P9-6); the heavy infra flow does NOT
  (verified: only `--dry-run`/`--trunk`). Asymmetry noted.

## 7. Uncertainties

- WHY a land ran from the shared checkout on 2026-07-18T03:20 (guard bypass vs direct
  land-lock call vs the shared checkout transiently being the session's own worktree) —
  unresolved without transcript archaeology (out of scope). The prose-only guard is confirmed.
- Whether `git push origin main` auto-allow (G-P9-3) is intended (test asserts it) or a stale
  comment / latent bug — the comment and code disagree; needs an owner decision.
- `land-lock.sh` exit-code `130` default (l.96) vs the child's real code — a wrapped command
  killed by signal could log 130; not load-bearing for landing safety but worth a glance.
- reso's `ship-reconcile.sh` (migration-aware reset+cherry-pick) is referenced as the model
  for high-concurrency repos but is NOT in this repo — infra's flow is rebase-only, so an
  ordered-artifact collision in infra would rely on the prose caveat, not code.

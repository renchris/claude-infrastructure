# Ship/Land Concurrency Hardening — claude-infrastructure + global /ship

**Scope (frozen):** make concurrent-session landings unable to silently drop a sibling
session's commit — in `claude-infrastructure` (the repo where it happened, which has NO
concurrency protections) and in the global `/ship` command's verification steps. reso's own
ship/land stack (land-lock + ship-reconcile + worktree pool) is NOT in scope except one
optional doc-level addition (T3) — it already has the protections; the incident happened in
the repo without them.

## Phase 0 — Agent Team Orchestration

Sizing: ~350-450 LOC total (2 bash scripts + bats tests + 3 doc/command edits) → **2
teammates** per the 301-500 split rule; worktree-isolated; lead = this fired session.

| Teammate | Worktree / branch | Scope | Est LOC |
|---|---|---|---|
| `infra-hardening` | `/tmp/wt-lh-t1` off `ship-hardening` | T1a `scripts/land-lock.sh` (port/generalize from `/Users/chrisren/Development/reso-management-app/scripts/land-lock.sh` — keyed by repo path, TTL + holder-pid liveness) · T1b `scripts/stranded-sweep.sh` (iterate local branches × `git cherry origin/<trunk>` × content-presence for `+` commits; exit 1 on stranded) · bats tests for both (repo convention: `tests/*.bats`) | ~300 |
| `ship-docs` | `/tmp/wt-lh-t2` off `ship-hardening` | T1c infra `commands/ship.md` (project-local: temp-worktree-per-landing, lock, last-moment re-fetch of the landed tip, content-verify, post-land sweep) + infra `CLAUDE.md` § concurrent writers (never commit in the shared checkout; temp worktree always) · T2 global ship.md edits (see below) | ~120 |

Dependency graph: T1a/T1b (infra-hardening) and T1c/T2 (ship-docs) are disjoint → **one
parallel wave**. Merge: lead cherry-picks/ff onto `ship-hardening`, gates, then lands onto
infra `main` **using the new locked flow itself** (dogfood). Pre-spawn checklist per
`~/.claude/rules/agent-teams.md` applies (briefs ≤150 lines, pre-grepped line ranges,
stop-on-issue verbatim).

## Incident record (2026-07-11, the motivating failure)

- Session A (wt-pool-4) committed `dfacccd` (limit-recover skill, 5 new files) onto
  `feat/two-way-session-comms` — the branch that happened to be checked out in the SHARED
  checkout `~/Development/claude-infrastructure` (the branch belonged to session B's
  in-flight feature work).
- Session B concurrently landed `feat/two-way-session-comms` onto `main` (rewrote SHAs:
  `602e6c6→8a29483` etc.) and its landing **dropped `dfacccd`** — main got the comms feature
  with ZERO limit-recover files, while `git rev-list origin/main..HEAD` read 0 ("looks
  landed") because the checkout now sat on the new main.
- Caught only because session A's ship preflight verified **content** (`git ls-tree
  origin/main -- <its paths>` + `git diff --stat dfacccd origin/main -- <paths>`), not just
  counts. Recovery: backup ref → cherry-pick onto fresh main → gate → push (`f0f4013`).
  Post-land `git cherry origin/main feat/two-way-session-comms` re-sweep: 0 stranded.
- Same class as reso memory `reference-stranded-committed-work-recovery-from-stalled-sessions`
  ("a landing rebase DROPS mid-history commits; branch tip looks done").

## Root causes (each maps to a task)

| # | Cause | Fix |
|---|---|---|
| A | Sessions commit directly in the SHARED infra checkout, on whatever branch is there — including a foreign session's live feature branch | T1c norm + T2a rule: branch/worktree-per-session; never commit onto a feature branch you didn't create this session |
| B | No landing serialization in claude-infrastructure (reso has `land-lock.sh`; infra has nothing) | T1a: generalized land-lock |
| C | Landing flows verify "0 unlanded" by COUNT on their own ref state — blind to commits that arrived on the branch mid-flight and to content dropped by a rebase | T1b + T2b: last-moment tip re-fetch + content-presence verification + post-land stranded sweep |
| D | Global `/ship` is deliberately light and defers to project-local hardening — but claude-infrastructure crossed the concurrency threshold without ever getting the local hardening | T1 overall (project-local ship.md per global /ship's own § reference) |

## Tasks

### T1 — claude-infrastructure hardening (root fix)
- **T1a `scripts/land-lock.sh`**: machine-wide mutex per repo (flock or mkdir lock under
  `/tmp/land-lock-<repo-hash>/`), holder pid + liveness check (never reap a live holder —
  reso memory: TTL-only reaping false-reaped live holders; default TTL 1200s + pid check).
  Read the reso original FIRST; port, don't reinvent.
- **T1b `scripts/stranded-sweep.sh`**: after any landing — for each local branch:
  `git cherry origin/<trunk> <br>` → for every `+` sha, verify its changed paths exist on
  trunk (`git ls-tree`) or flag STRANDED with the recovery recipe (backup ref → cherry-pick
  → gate → push). Also callable standalone. Exit codes: 0 clean / 1 stranded found.
- **T1c project-local `commands/ship.md` + `CLAUDE.md` section**: the infra landing flow =
  acquire lock → temp worktree at the branch tip (RE-FETCHED at land moment, so mid-flight
  sibling commits ride along) → rebase onto origin/main → gate (shellcheck + bats + bash -n
  + py_compile where present) → push → **content-verify the landed range's paths on
  origin/main** → stranded-sweep → release lock. Never land from the shared checkout.

### T2 — global `/ship` command hardening (the 2 rules that made+caught this incident)
- **T2a** step 2 addition: *"In a SHARED checkout, never commit onto a pre-existing feature
  branch you didn't create this session — create your own branch (or temp worktree) first;
  a concurrent landing of that branch can rebase-drop your commit."*
- **T2b** steps 7-8 addition: *"Verify the landing by CONTENT, never by count: `git ls-tree
  origin/<trunk> -- <your changed paths>` (+ `git diff <your-sha> origin/<trunk> -- <paths>`
  empty). `0 unlanded` after someone else's rebase proves nothing. Then sweep local branches
  for stranded commits (`git cherry`)."*
- File reality: `~/.claude/commands/ship.md` is a REAL file (not a symlink); check whether
  the infra repo has `commands/ship.md`. End state: repo copy is the source; convert
  `~/.claude/commands/ship.md` to a symlink (matching `handoff.md`'s pattern) OR keep both
  in sync explicitly — pick one, document it.

### T3 — reso (OPTIONAL, P2, single file)
- Add the post-land stranded-sweep step to reso's `.claude/commands/ship.md` step 8
  (operationalizes the manual memory playbook). No script changes in reso; reuse T1b via
  absolute path or inline the 4-line loop. Skip if time-boxed out.

## Acceptance gates (all must pass before landing)
1. **Race simulation** (the incident, reproduced): two temp clones of a scratch repo;
   clone-1 commits on branch F; clone-2 lands F-without-that-commit onto main (rebase);
   the new flow's content-verify + stranded-sweep FLAGS the drop (old flow: silent).
2. Synthetic stranded commit planted on a side branch → `stranded-sweep.sh` exits 1,
   names the sha + paths + recovery recipe.
3. `shellcheck -S warning` green on both scripts; bats tests green (`tests/land-lock.bats`,
   `tests/stranded-sweep.bats`); lock respects a LIVE holder (pid alive) past TTL.
4. Landing of THIS work onto infra main goes through the new flow itself.

## Hard constraints
- Work only in dedicated worktrees; the shared checkout `~/Development/claude-infrastructure`
  is read-only to this effort.
- Keep `~/.claude` live copies in sync with any repo-side command changes you land.
- Push to infra `main` only via the new locked+verified flow, once gates are green.
- reso repo: T3's single doc file at most; nothing else.

## Status log
- 2026-07-11 02:1x — plan created + committed on `ship-hardening` by the incident session
  (wt-pool-4, next4); handed off via /handoff fire. Nothing implemented yet.
- 2026-07-11 (session 2) — implementation started. Recon + decisions:
  - **Runtime** = CC 2.1.183 (claude-next / implicit-team model — spawn teammates via `Agent`
    with `name`+`model:opus`, no `TeamCreate`). Trunk = `origin/main`. bats 1.13.0 + shellcheck
    0.11.0 present. `tests/*.bats` convention confirmed (5 existing).
  - **File-placement decision (T1c/T2, resolves the "commands/ship.md" ambiguity):** repo-root
    `commands/` is the GLOBAL backing store (`handoff.md` is symlinked repo→`~/.claude`). Putting
    the heavy flow there would replace the LIGHT global `/ship` for every project (violates root
    cause D). So: **heavy infra flow → NEW `.claude/commands/ship.md`** (project-local override,
    active only in infra — matches global `/ship` line 52's own documented pattern + reso
    precedent). **Light global `/ship` → NEW repo `commands/ship.md`** (= current `~/.claude`
    content + T2a/T2b); lead flips `~/.claude/commands/ship.md`→symlink post-land (matching
    handoff.md). Chose "symlink" over "keep in sync" per T2's "pick one".
  - **land-lock generalization (T1a):** repo-keyed lock `/tmp/land-lock-<repohash>/lock.d`
    (shasum of `git rev-parse --show-toplevel`), telemetry → `~/.claude/land.log`. Test hooks:
    `LAND_LOCK_DIR` + `LAND_LOG` overrides.
  - **land-lock reap-rule divergence from reso (gate 3):** a LIVE holder pid is **never** reaped,
    even past TTL (reso reaps live-past-TTL for load reasons; infra must not — the incident's cost,
    a silently-dropped commit, outweighs a wedged-lock wait; `LAND_SERIALIZE=off` is the escape
    hatch). Reap only: dead pid (immediate) or empty pid past 5s grace / TTL.
  - Worktrees: `lh-t1` (infra-hardening: T1a/T1b + bats) + `lh-t2` (ship-docs: T1c + T2), both off
    `ship-hardening` @ b191f94. One parallel wave; lead merges → gates → dogfood-lands.

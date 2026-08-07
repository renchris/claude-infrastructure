---
status: open
---

# Deploy lane — ground-up rebuild of the advance invariant

**Status:** OPEN · created 2026-08-06 · handed off to a dedicated `/ground-up` session (Opus 5 @ max,
account next4).

`Scope (frozen):` Rebuild the deploy lane's **advance invariant** from first principles so the
green-stamp / anti-rollback deadlock cannot recur. Step 0 unwedges the live layer; Steps 1-3 make the
class impossible.

---

## Phase 0 — Agent Team Orchestration

This plan has ≥2 code-writing tasks (the guard rewrite and its RED-controls, then the deploy-path
integration), so per the global CLAUDE.md it runs as an Agent Team, not a solo lead.

| Track | Owner | Deliverable | Isolation |
|---|---|---|---|
| **T0 unwedge** | LEAD (operator-gated) | live layer current; deploy lane observably advancing | shared checkout, read + one gated command |
| **T1 invariant** | LEAD | the derived invariant + its failure table, written here before any code | none (design) |
| **T2 guard** | teammate | target-selection + anti-rollback rewrite, one RED-control per guard leg | own worktree |
| **T3 observability** | teammate | the lane states a human can read; no silent 536-refusal loops | own worktree |

T1 gates T2/T3 — do not spawn implementers before the invariant is written down and reviewed.
Split further if any deliverable exceeds ~500 LOC.

---

## The defect, as measured (2026-08-06)

Full evidence: `docs/research/machine-lag-and-kitty-2026-08-06.md` §5 (landed `955a8d2b`, extended
`d0209925`). Summary of the state to be fixed:

- `~/.claude` **symlinks into the shared checkout's working tree** — it is not a copy. 42 of the 50
  changed files under `hooks/ scripts/ bin/` are live symlinks, so a stale checkout is a stale fleet.
- Live layer pinned at `a9060c18`; `origin/main` has moved to `d0209925`. `git rev-list --left-right
  --count origin/main...HEAD` → **85  0** — a clean fast-forward is available and never happens.
- `deploy-live.sh:325` selects the newest commit whose **tree** carries a green stamp. That is
  `3725e543` (2026-08-04). Ancestry:

  | | |
  |---|---|
  | live HEAD `a9060c18` ancestor of `origin/main`? | **YES** |
  | target `3725e543` ancestor of `origin/main`? | YES |
  | live HEAD `a9060c18` ancestor of target `3725e543`? | **NO** ← the permanent refusal |

- So the anti-rollback guard refuses, correctly, forever: **536 refusals**, `launchd runs=269 exit 1`.
- It cannot self-heal: advancing needs a green stamp at or above `a9060c18`, and the corpus has
  produced **2 greens in 85 runs**, last one 2026-08-04T14:15Z.
- **The gap is divergent, not static.** Every land — including the two that produced this plan —
  widens it, and no mechanism narrows it.

### Why this is a ground-up and not another patch

The same deadlock is filed **five times** (`42c2a4879281`, `e1a0d2e7937f`, `08d2f8651ccd`,
`f271cd880295`, `3c4083af1397`) plus tasks **#50** ("Break the deploy-live bootstrap deadlock via a
green stamp" — marked *completed*) and **#71** (same title, still pending). A class that has been
diagnosed and patched this many times and still recurs is an invariant problem, not a bug.

Note the provenance honestly: the `/ground-up` methodology itself came from the **2026-07-28
landing-pipeline rebuild**, i.e. this same subsystem family. That rebuild did not close this class.
Treat its conclusions as evidence, not as settled ground — and say explicitly which of its premises
this rebuild keeps and which it discards.

## Step 0 — unwedge the live layer (operator-gated, do FIRST)

Design work done on an 85-commit-stale layer is designed on the defect, and anything it lands will
*also* fail to deploy — reproducing the failure one level up. So unwedge before designing.

Two blockers, both needing the operator:

1. **The bypass.** `deploy-live.sh --force` targets `origin/main` directly and banners itself
   `UNSTAMPED --force deploy — green-stamp gate BYPASSED by the operator`. Dry-run confirms it would
   fast-forward `a9060c18b314 → <trunk tip>`. Skipping the verification net on the layer every
   session executes is the operator's call, not the agent's.
2. **A sibling's dirty file.** The shared checkout carries an uncommitted
   `hooks/backup-before-write.sh` from another session, and that file **also changed on trunk**, so
   `git merge --ff-only` refuses regardless of the stamp gate. Park it per the global CLAUDE.md
   pattern (`git diff > /tmp/stash.patch`, restore after) — never discard another session's work.
   This is the exact condition `scripts/new-worktree.sh`'s own header documents from 2026-07-31.

**Verify by CONTENT, never by count:** after the deploy, assert a file that changed in the range is
actually current in `~/.claude` (`git ls-tree` + an `md5` of the symlink target), and confirm
`deploy.log` stops emitting refusals.

## Steps 1-3 — the rebuild

1. **Derive the invariant.** What must be true for the live layer to be allowed to move? State it as
   a property, then enumerate every way the current design can violate it. At minimum the answer must
   dispose of: a target *behind* live HEAD (today: 536 identical refusals and no escalation); a
   stamp producer that can starve the lane indefinitely; and a live layer that can advance past its
   own verification evidence. Do not open the existing implementation until the invariant is written.
2. **Implement**, with a **RED-control per guard leg** — each guard must be shown to fail when its
   condition is violated, or it is unproven. Beware the shape this repo has been bitten by: a guard
   that is runtime-correct but scanner-invisible, and a control that passes vacuously because a
   sibling mechanism already fixed the thing it tests.
3. **Land, then verify the live layer actually moved.** A landed fix that does not deploy is the
   current failure mode; the acceptance test is a *deployed* layer, not a green gate.

## Hard constraints

- **Never commit or land in the shared checkout** (`.claude/CLAUDE.md`) — dedicated worktree, own
  branch, land via the project-local `/ship`. Verify landings by CONTENT (`git ls-tree origin/main`),
  never by `rev-list` count.
- **Never `--no-verify`; never force-push; never `git clean -x/-X`.**
- **Do not discard the sibling's uncommitted `hooks/backup-before-write.sh`** — park and restore.
- The trunk corpus is RED and has been for 57h+. That red is **not yours** — do not drive it, and do
  not launder it into a green claim. `/ship`'s fast lane sheds smoke under load by design.
- `deploy-live.sh --force` is the operator's call every time it is needed. Surface it, never fire it.

## Status log

- **2026-08-06** — Diagnosed and handed off. Live layer 85 behind, 536 refusals, 2 greens in 85 runs.
  Evidence landed as `955a8d2b` + `d0209925`. This plan created for the `/ground-up` successor.

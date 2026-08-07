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

## Step 1 — THE DERIVED INVARIANT (written 2026-08-07, before opening the implementation)

**Provenance discipline.** Everything in this section is derived from *state and behavior only*:
the launchd declaration (`com.claude.deploy-live.plist`), `autonomy/postland/deploy.log`,
`autonomy/postland/stamps/*.json`, git ancestry, and the shared checkout's **reflog**.
`scripts/deploy-live.sh` was NOT read until §1.6 — the violation enumeration — so the invariant is
derived from the problem, not inherited from the incumbent's frame.

### 1.1 Measured constants, re-derived 2026-08-07

The 2026-08-06 filing was re-measured rather than inherited. Six of its numbers moved and **four
load-bearing facts were missing from it entirely**.

| Constant | Filed 2026-08-06 | **Measured 2026-08-07** | Command |
|---|---|---|---|
| live layer HEAD | `a9060c18` | `a9060c18` (2026-08-05 15:37) — unchanged | `git rev-parse HEAD` in shared checkout |
| trunk tip | `d0209925` | **`754c41e0`** (2026-08-07 00:40) | `git rev-parse origin/main` |
| gap (trunk ahead) | 85 | **87** | `git rev-list --left-right --count origin/main...HEAD` → `87  0` |
| anti-rollback refusals | 536 | **534** (log is subject to `com.claude.log-rotation`; read as ≥534) | `grep -c 'would ROLL BACK'` |
| launchd runs / last exit | 269 / 1 | **276 / 1** | `launchctl print gui/501/com.claude.deploy-live` |
| green stamps | "2 in 85 runs" | **exactly 2** — 85 stamps: 80 `red`, 2 `green`, 2 `cut`, 1 `hung` | census of `stamps/*.json` |
| live symlink share | "42 of 50 changed files" | **284 of 291** entries across `hooks/ scripts/ bin/ commands/` | `find -maxdepth 1 -type l` per dir |
| **verifier duration** | *absent* | **median 8852 s = 2h28m**; p90 11886 s; max 13248 s (3h41m) | `run_s` across 85 stamps |
| **third failure mode** | *absent* | **59 ×** `` /bin/bash: …/.claude/scripts/deploy-live.sh: No such file or directory `` — the deploy script is itself absent from the layer it deploys | `uniq -c` on `deploy.log` |
| **escalation coverage** | *absent* | 6 pages written for 6 stamp-starvation refusals; **0 pages for 534 anti-rollback refusals** | `grep -c 'wrote page'`; `ls autonomy/pages/` — newest `deploy-blocked-*` is 2026-08-03 |
| **target ↔ live ancestry** | "live HEAD is NOT an ancestor of target" | same, and its **converse holds**: target `3725e543` **IS** an ancestor of live HEAD (`rc=0`) — live is **43 commits ahead of its own target** | `git merge-base --is-ancestor` |
| **stamp key type** | *absent* | stamps are keyed on **TREE** sha; target `3725e543` (a `Revert`) inherits green from verified commit `29313ae4` because both carry tree `cd17174f48fb` | stamp filename vs `git rev-parse X^{tree}` |

Two derived rates, which together decide the whole design:

- **Land rate** — 87 commits between 2026-08-05 15:37 and 2026-08-07 00:40 (33h03m) = **≈63 commits/day**.
- **Evidence rate** — 85 verdicts over 2026-07-26T02:16Z → 2026-08-07T03:37Z (12.06 d) = **≈7.0 verdicts/day**, of which **≈0.17 greens/day**.

### 1.2 The decisive fact the filing does not contain: the live layer has SEVERAL writers

The filing reads the deadlock as *"the guard is correct; the state it guards is unreachable."* The
reflog refutes the implied cause. Live HEAD `a9060c18` was **not** set by a stamped deploy:

```
a9060c18 HEAD@{2026-08-05 15:40:37 -0700}: merge origin/main: Fast-forward
```

`deploy-live.sh` fast-forwards to a *specific stamped sha* (`merge <sha>: Fast-forward`, 6
occurrences — one of them the lane's single success, `merge 3725e5432bfc…` on 2026-08-04 10:40).
A fast-forward to **`origin/main`** is a different writer. Reflog census of the live layer's HEAD:

| Reflog action | Count | Writer | Gated by the stamp? |
|---|---|---|---|
| `merge origin/main: Fast-forward` | 13 | a session / `/ship` syncing the checkout | **no** |
| `reset: moving to origin/main` | 11 | a session resetting to trunk | **no** |
| `pull -q --rebase origin main` | 3 | a session pulling | **no** |
| `rebase (start): checkout origin/main` | 5 | a session rebasing | **no** |
| `commit:` | several | a session committing in the shared checkout | **no** |
| `merge <sha>: Fast-forward` | 6 | **`deploy-live.sh`** | **yes** |

The live layer is *the developer checkout's working tree*. Every ordinary git operation any session
performs there is a deploy to the entire fleet, because 284 of 291 entries under
`hooks/ scripts/ bin/ commands/` are symlinks into it. **The stamp gate governs ~6 of ~38 observed
writes.**

**The causal chain, measured end to end:**

1. 2026-08-04 10:40 — `deploy-live.sh` deploys, gated and green, to `3725e543`. (The one success in 705 log lines.)
2. 2026-08-05 15:40 — an **ungated** `merge origin/main: Fast-forward` moves the checkout to `a9060c18`, **43 commits past the stamped target**.
3. From that instant the lane's target is permanently *behind* live HEAD, so anti-rollback refuses — correctly, and **534 times in silence**, because the escalation path is wired to the *other* refusal class.
4. The only exit is a green stamp at or above `a9060c18`. At 0.17 greens/day against 63 commits/day, it does not arrive.

**So the failure is not an over-strict guard. It is a verification gate installed on a path that is
not the only path.** The ungated writers are strictly faster than the gated one; they overtake it;
and the moment they do, the gated writer's own safety property converts "I am behind" into "I refuse
forever." A gate on a non-exclusive path does not gate — it only deadlocks itself.

### 1.3 The invariant

State the system abstractly. `L` = the live layer's commit (what every session executes). `T` =
trunk tip. `E` = the evidence corpus. `W` = the set of writers that can move `L`.

> **THE ADVANCE INVARIANT.** At every instant `L` must simultaneously satisfy
>
> - **A1 · MONOTONE** — `L` never loses content it already had: every previous value of `L` is an ancestor of `L`.
> - **A2 · COVERED** — `L`'s content is not known-unsafe: no verdict in `E` marks any state at or below `L` as red without that red having been dispositioned.
> - **A3 · FRESH** — `L` is within a *declared, finite* staleness budget of `T`, in both commits and wall-clock.
>
> …and the conjunction **A1 ∧ A2 ∧ A3 must be reachable from every state the system can enter, for
> every writer in `W`.**

The last clause is the whole content of this rebuild. Stated as the derivation rule it enforces:

> 🚨 **A conjunction of safety guards is admissible only if the set of states satisfying all of them
> is reachable from every state the system can enter. Otherwise it is not a policy, it is a trap.**
> Safety properties compose freely; safety and liveness do not. Two individually-correct guards
> (`A1` monotone, `A2` covered) with no liveness obligation produced an absorbing state in 12 days.

Four corollaries follow, and each is a requirement on the rebuild:

- **C1 · EXCLUSIVITY.** Either every writer in `W` is subject to the invariant, or the invariant is
  decorative. A gate that governs 6 of 38 writes is decorative.
- **C2 · PRODUCER ADEQUACY, or DECOUPLING.** If advancing *requires* fresh evidence per target, then
  the evidence rate must dominate the land rate. Measured: 7.0/day (0.17 green/day) vs 63/day —
  **short by 9× at 100% green and by 375× as it actually runs.** Since the producer cannot be made
  ~400× faster, `A2` must be **decoupled from the advance**: evidence becomes a *veto on known-red*,
  not a *permit requiring green*. Absence of a verdict cannot mean "blocked", because absence is the
  overwhelmingly common case and is *structurally guaranteed* to be, forever.
- **C3 · NO SILENT NON-PROGRESS.** A lane that has not advanced within its `A3` budget must escalate,
  and the escalation must be keyed on **not-advancing**, not on any particular refusal reason. 534
  identical silent refusals is the measured cost of keying the alarm on a reason.
- **C4 · SELF-HOSTING IS A SEPARATE HAZARD.** The lane deploys the script that runs the lane, over
  live symlinks, with no staging and no atomicity — measured 59 times as *the deploy job's own
  executable missing from the layer it deploys*. Any design must be able to advance the layer while
  the layer contains a broken copy of the advancer.

### 1.4 Failure-mode table — every observed mode gets a structural answer

A mode without an answer is an unfinished design.

| # | Observed mode (with its measurement) | Which clause it violates | Structural answer required |
|---|---|---|---|
| F1 | Target permanently behind live HEAD; 534 identical refusals | A3 unreachable given A1∧A2 | Target selection must be a function of `T`, not of the evidence corpus; evidence vetoes, never selects |
| F2 | Evidence producer cannot keep up: 0.17 green/day vs 63 commits/day | C2 | Decouple: advance on *absence of red*, not *presence of green* |
| F3 | Ungated writers move `L` past its evidence (13 + 11 + 3 reflog entries) | C1 | Either give the live layer its own checkout (exclusive `W`), or make the invariant hold for the ordinary git path too |
| F4 | 534 refusals produce 0 pages; alarm keyed on the *other* refusal class | C3 | Alarm on **not-advancing for > budget**, reason-agnostic |
| F5 | Deploy script absent from the live layer, 59 × — the job cannot run at all | C4 | The advancer must not be self-hosted on the layer it advances, or must have a bootstrap that does not require itself |
| F6 | One dirty sibling file (`hooks/backup-before-write.sh`, now + untracked `hooks/lib/read-before-write-parity.sh`) blocks `--ff-only` regardless of the stamp | A3 vs the working-tree realization | The live layer must not be a surface anyone edits in place; if it stays one, dirty-file handling is part of the lane, not a manual step |
| F7 | Stamp is TREE-keyed while `last-green` holds a COMMIT sha; a `Revert` silently inherits a green | A2 (evidence identity) | Decide and document the key type; a verdict must name what it verified in the same key space it is looked up by |
| F8 | Making the gate *exclusive* without fixing F2 would freeze the fleet **totally** rather than partially | — | Recorded as a rejected alternative, not a fix: C1 alone is a worse system than today |

### 1.5 What this keeps and discards from the 2026-07-28 landing rebuild

The `/ground-up` methodology came from that rebuild — the same subsystem family — and it did not
close this class. Which of its premises survive is being derived from `LAND_PIPELINE_V2.md` by the
archaeology researcher; **this subsection is PENDING that read** and will be integrated before any
implementer is spawned. The one premise already contradicted by measurement is recorded now: a
design that treats *"the corpus goes green"* as an available event is refuted at 2/85.

### 1.6 Violation enumeration against the implementation

PENDING — `scripts/deploy-live.sh` is read only after this section. Each violation will be recorded
as `file:line → clause`.

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

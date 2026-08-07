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

Read after §1.1-1.5 were committed (`6b0579c9`). `scripts/deploy-live.sh` is 418 lines.

| V | Site | Violation | Clause |
|---|---|---|---|
| **V1** | `deploy-live.sh:322-330` | `TARGET` is chosen by walking `origin/main` newest-first for the first commit whose **tree** carries a green stamp. Selection is a function of the *evidence corpus*, so the target is bounded above by the newest green and therefore lags by (verify duration) + (1/green rate) = 2h28m median + a 2.4% hit rate. The target is a structurally **lagging** pointer. | C2 |
| **V2** | `deploy-live.sh:357-358` | `git merge-base --is-ancestor "$HEAD_SHA" "$TARGET" \|\| die`. Correct in isolation. Conjoined with V1 it has an **absorbing state**: once `HEAD` passes the newest green — reachable by *any* ungated writer — no future event restores satisfiability, because V1 cannot propose a target above the newest green and the producer cannot outrun trunk. | A1∧A3 |
| **V3** | `:331-345` **vs** `:357-358` | **Escalation polarity is inverted, at file:line.** The *transient* no-green refusal gets `damp_ok` + a `.page` + `die` (`:334`, `:336-342`). The *permanent* anti-rollback refusal gets a bare `die` (`:358`) — no damp key, no page, no backlog. Measured: 6 pages for 6 no-green; **0 pages for 534 anti-rollback**. The lane is loud about the recoverable failure and silent about the terminal one. | C3 |
| **V4** | `:216-227` (the comment) | The design **knows** about the second path and *accepts* it: *"content advances by a SECOND path: ~/.claude is per-file symlinks into this checkout, so every land moves the live layer for free."* That acceptance converts an ungoverned writer into a **load-bearing liveness dependency that nothing schedules, monitors, or owns.** | C1 |
| **V5** | `:224-227` (the premise) | The justification for V4 — *"The content stayed fresh throughout — only files that did not exist at the last successful advance rotted"* — **has since gone false.** Measured 2026-08-07: the last write of *any* kind to the live layer's HEAD was 2026-08-05 15:40:37 -0700, i.e. **33h17m of zero writes by any writer**, at 87 commits of lag. The 2026-07-30 fix (hoisting `link_refresh` above the guard) was correct *given its premise* and repaired the *namespace*; the premise it left standing was the *content*. | — |
| **V6** | `:367-369` + 59 log lines | The script states it rewrites itself mid-run. The launchd job (`plist` `ProgramArguments`) invokes `$HOME/.claude/scripts/deploy-live.sh` — a symlink created by `link_refresh`, *inside this script*. When the link is absent the job cannot start at all: **59 × `No such file or directory`**. | C4 |
| **V7** | header `:11-12` | Stamps are **tree**-keyed by deliberate design (so a rebase preserving the tree keeps its verdict), while `autonomy/postland/last-green` holds a **commit** sha. Consequence, measured: target `3725e543` (a `Revert`) inherits green from verified commit `29313ae4` — both carry tree `cd17174f48fb`. This is the *only* mechanism that has ever moved the target forward without a fresh green, and it is incidental rather than designed-for. | A2 |
| **V8** | header `:2-9` **vs** `:19-30` | **The generator.** The fail-closed policy was written for *"the OPERATOR's one safe command"* — a rare, deliberate human act, where refusing is a safe null. `--auto` then reused that same policy for an unattended **144×/day** job, where refusing is not null: it is a continuous accumulation of staleness. **Fail-closed is correct for a rare deliberate act and catastrophic for a continuous process**, because for a continuous process *not moving is itself a failure mode* — the fleet currently executes 87-commit-old hooks. The incumbent prices staleness at zero. | A3 |

**V8 is the class.** V1-V3 are its mechanism, V4-V5 are how it stayed invisible, V6-V7 are adjacent
hazards. A sixth patch to V1 or V2 leaves V8 intact, which is why five filings did not close it.

### 1.7 Step 0 correction — there are TWO independent blockers, not one

The filing describes the dirty sibling file as an obstacle *to the unwedge*. It is more than that: it
is the reason the **second path stopped too**, and it means curing the stamp gate alone would still
not deploy.

| | Blocker | Effect | Cures the other? |
|---|---|---|---|
| **A** | Stamp gate + anti-rollback (V1∧V2) — target `3725e543` is an ancestor of live HEAD | The *gated* writer refuses, 534 × silently | no |
| **B** | `hooks/backup-before-write.sh` is modified in the working tree **and** changed on trunk by `16dfe3b5` | `git merge --ff-only` refuses for **every** writer, gated and ungated alike — which is exactly why the reflog shows zero HEAD moves for 33h17m | no |

Verified 2026-08-07: `git merge-tree --write-tree HEAD origin/main` → **rc=0**, so the trees merge
cleanly. The refusal is purely the dirty working file. The untracked
`hooks/lib/read-before-write-parity.sh` is *not* added by trunk, so it is harmless to the
fast-forward and needs only to be left alone.

**Consequence for Step 0:** curing A without B still dies at `deploy-live.sh:388`
(`merge --ff-only … FAILED (dirty tree? diverged?)`). Both must be handled, B first.

**And a correction on which command to hand the operator.** Once B is parked, a bare
`git merge --ff-only origin/main` in the shared checkout *would* advance the layer — that is the
ungated second path, and it needs no green stamp because it was never gated. **It must not be
presented as the safer option.** It deploys exactly the same unverified trunk tip that `--force`
does, while skipping the banner (`:366`), `install.sh`, the post-deploy host checks (`:32-38`), and
the log line. `--force` is the strictly better instrument for the same content advance: it is the
same act, announced. Both remain the operator's call under the frozen scope — surfaced, never fired.

## Step 2 — THE DESIGN (2026-08-07)

### 2.1 The inversion

> **The incumbent asks "may the live layer move?" and defaults to no. The rebuild asks "why is the
> live layer not at trunk?" and defaults to moving.**

Staleness becomes a first-class failure with the same standing as a bad deploy. Today it is priced at
zero (V8), which is why refusing 534 times reads as safe behavior instead of as the outage it is.

**The repo already believes this on the land path and contradicts it on the deploy path.** `/ship`'s
own contract (`.claude/commands/ship.md`) states *"a CUT smoke never blocks… A non-verdict is not a
red (R6)"*. But `deploy-live.sh:135-143` `is_green()` returns true **only** for `verdict=="green"`,
so `red`, `cut` and `hung` are treated identically — a non-verdict is scored as a red. Of the 85
stamps, 3 are non-verdicts (2 `cut`, 1 `hung`). The deploy lane violates a principle its own land
lane enforces; D1 is partly just applying R6 where it was already settled.

### 2.2 D1 — evidence VETOES, it never PERMITS *(dissolves F1, F2)*

| | Incumbent | Rebuild |
|---|---|---|
| Target | newest commit whose tree carries a **green** stamp | newest commit on `origin/main` whose tree carries **no red** stamp |
| No stamp at all | ineligible ⇒ blocked | **eligible** — absence is the overwhelmingly common case and is structurally guaranteed to stay so |
| `cut` / `hung` | ineligible (conflated with red) | **eligible** — a non-verdict is not a red (R6) |
| `red` | ineligible | ineligible — walk back one commit and retry |
| Target position | bounded **above** by the newest green ⇒ lags | tracks trunk ⇒ **ahead of live HEAD by construction** |

The absorbing state disappears because target-selection stops being a function of the evidence
corpus. `deploy-live.sh:357-358`'s anti-rollback guard is **kept unchanged** — it stops being a trap
the moment the target is no longer a lagging pointer, and it still does its real job of refusing a
genuine rollback.

**The honest cost.** The fleet will run code that has not been proven green. It **already does**: 13
ungated `merge origin/main` fast-forwards put it there, and 45 of 309 live files currently differ
from trunk. D1 does not lower the safety bar; it stops pretending a gate exists where the measured
gate coverage is ~6 of ~38 writes.

### 2.3 D2 — a staleness budget, alarmed on NOT-ADVANCING *(dissolves F4, V8)*

`A3` gets numbers: `CC_DEPLOY_MAX_LAG_COMMITS` and `CC_DEPLOY_MAX_LAG_HOURS` (env kill switches, per
the methodology — never a revert-as-plan). Exceeding either pages **reason-agnostically**.

This is the single most important behavioral change and it is one line of policy: the alarm keys on
*"I have not advanced in H hours while trunk moved N commits"*, **not** on which refusal fired.
`deploy-live.sh:331-345` pages the transient no-green case and `:357-358` pages nothing — so the
permanent failure is the silent one. Measured: 0 pages across 534 refusals and 33h of total freeze.

R2 adds the confirming forecast: `SCAN_N=200` gives **66 commits of headroom**, after which the lane
flips from `would ROLL BACK` back to `no GREEN stamp` and starts paging again — **a change of
message, not a recovery**. An alarm that only fires once the diagnosis has become wrong is worse than
none.

### 2.4 D3 — exclusivity becomes unnecessary rather than enforced *(dissolves F3, C1)*

The obvious fix for C1 is to give the live layer its own checkout so `deploy-live.sh` is the only
writer. **Rejected as the first move** (F8): with the producer at 0.17 greens/day, a genuinely
exclusive gate converts today's *partial* freeze into a *total* one — strictly worse than the status
quo, in which ungated fast-forwards at least deliver content.

D1 dissolves the problem instead. Once the gated writer's target tracks trunk, the gated and ungated
writers **want to go to the same place**. An ungated `merge origin/main` stops being an overtake and
becomes a redundant, harmless instance of the same operation. Exclusivity stops being load-bearing.

### 2.5 D4 — the advancer must not be undeployable by its own outage *(dissolves F5, C4)*

The launchd job execs `$HOME/.claude/scripts/deploy-live.sh`, a symlink that `link_refresh` — inside
that same script — is responsible for creating. Measured 59 × `No such file or directory`. Fix:
`ProgramArguments` falls back to `$SHARED/scripts/deploy-live.sh` when the live symlink is absent.
**Precedent exists in-repo**: `operator-readout.sh:238-246` already does exactly this for the
platter, under the comment *"I11 — EXISTENCE-CHECK THE PLATTER… A recover command that cannot run is
worse than no row: it teaches the operator the board lies."* Same defect, same remedy, one file over.

### 2.6 D5 — the operator platter must be runnable *(V9)*

`cc-do` RUN 1 platters `bash ~/.claude/scripts/deploy-live.sh` — the exact command that has refused
534 consecutive times. By I11's own rule that is worse than no row. The platter must either carry a
command that can succeed under the current state, or name the blocker instead of offering a fix its
own gate rejects.

### 2.7 REJECTED ALTERNATIVES

Recorded so they are not relitigated.

| | Alternative | Why rejected |
|---|---|---|
| R-A | **Make the verifier fast enough to gate per-commit** | 2h28m median over 297 suites. Even a 10× speedup leaves ~1.6 verdicts/hour against ~2.6 commits/hour. The rate gap is structural, not a tuning problem — the same conclusion `LAND_PIPELINE_V2` reached for the *land* path and then failed to carry over to the *deploy* path. |
| R-B | **Re-add load/admission control so runs stop being killed** | **Forbidden.** Deleted deliberately (`postland-verify.sh:975`, §4.2.3/R7) and its *absence* is asserted by a structural test at `:1825-1830`. R3 flagged `wt-f8e40b4c577d`'s `f58a6cd3` as the losing side of exactly this argument. |
| R-C | **Widen `SCAN_N` past 200** | Changes which refusal prints, not whether it recovers (R2: 66 commits of headroom, then the message flips). Treating a message change as progress is how this survived five filings. |
| R-D | **Auto-`--force` when lag exceeds the budget** | Launders an unverified deploy through automation and takes the operator's documented escape hatch away from them. `--auto` is non-interactive *by construction* (`deploy-live.sh:76-79`); D2 pages instead. |
| R-E | **Wait for the corpus to go green** | Refuted on measurement, not on preference: 1 green / 44 red over 7 days, `flakes=0` at `retries=10-22` (hard reds, not machine noise — the `RETRY_QOS` ladder fix that would have explained them away is verified **live**), and the auto-revert net that should restore green now reports `skipped` and `FAILED(step=revert rc=90)`. |

### 2.8 ACCEPTANCE — disk-truth reads, not narration

Per the methodology, each criterion names the file or log that proves it. **Acceptance is a DEPLOYED
layer, not a green gate.**

| # | Claim | The read that proves it |
|---|---|---|
| A-1 | The lane advances | `git -C <shared> rev-list --count HEAD..origin/main` falls, measured twice ≥1 tick apart |
| A-2 | It advanced *by content* | `git ls-tree origin/main -- <path>` present **and** `md5` of the `~/.claude` symlink target == `git show origin/main:<path>` — never a rev-list count |
| A-3 | Refusals stopped | `grep -c 'would ROLL BACK' deploy.log` stops increasing across ≥2 launchd ticks (`runs=` advances in `launchctl print`) |
| A-4 | Non-advance is now loud | with the budget forced low, a page appears in `~/.claude/autonomy/pages/` keyed on lag, **not** on a refusal reason |
| A-5 | Each guard leg is proven | one RED-control per leg, red against the pristine pre-change tree recovered via `git archive` — never a hand-edited approximation |
| A-6 | No vacuous control | every control must be shown to FAIL when its leg is violated; watch for a control that passes because a sibling mechanism already fixed what it tests |

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

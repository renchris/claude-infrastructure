---
status: complete
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

### Phase 0 as ACTUALLY RUN (2026-08-07)

T1 was written and landed **before** `deploy-live.sh` was opened; the commit order is the provenance
proof (`6b0579c9` invariant → `c3ea951a` violation enumeration). Wave 1 was three read-only
researchers (archaeology · telemetry · branch-graveyard+seams), whose findings are folded into
§1.5-§1.9 and materially **revised D1** (see §2.2). Wave 2 is two teammates with disjoint file
ownership:

| Teammate | Branch / worktree | Owns | Deliverable |
|---|---|---|---|
| `t2-guard` | `deploy-lane-t2-guard` · `.worktrees/deploy-lane-t2-guard` | `scripts/deploy-live.sh` · `tests/deploy-live.bats` · `launchd/com.claude.deploy-live.plist` | D1 two-tier target · §1.7 message · D6 dirty-state · D4 plist fallback · 8 RED-controls |
| `t3-alarm` | `deploy-lane-t3-alarm` · `.worktrees/deploy-lane-t3-alarm` | `bin/cc-blockers` · `tests/cc-blockers.bats` | D2 `deploy-stale` kind · selector registration · runnable `recover_cmd` · 5 RED-controls |

Lead retains: this plan, the merge, the land, and the §2.6c activation script. **D5 (the `cc-do`
platter) is deliberately unassigned** — it is downstream of T2, so once the lane can advance the
platter becomes runnable on its own. Re-verify after the merge rather than fixing it twice.

**Spawn-API note (2.1.220):** teammates are `Agent({name})` with **no** `team_name` (it does not
exist on this runtime) and **no** `isolation` — passing `isolation` alongside `name` silently demotes
the spawn to an in-process subagent with no pane and no error, so the worktree is handed over as a
**path in the brief** instead.

### Material received mid-flight from the originating lag investigation

- **`docs/plans/MACHINE_CAPACITY_V2.md` §12.7.7 "LANDED ≠ LIVE"** documented this identical deadlock on **2026-07-31 at 75 commits behind**, quoting both refusal messages, and named memory `verify-throughput-below-trunk-velocity`. Verified on disk. That makes the divergence series **75 (07-31) → 85 (08-06) → 87 (08-07 07:57Z) → 91 (08-07 08:15Z)** across four independent reads — monotone, and re-confirmed twice inside this session.
- That plan (1655 lines, `status: open`, ground-up row 13) owns the **resource-governance** half — frozen scope 30 concurrent sessions, standing constraint *"the caller cannot be trusted"*. **Not re-derived here; out of this rebuild's scope.**
- **`bin/cc-bats`** was built 2026-07-30 (21,656 B) and no `CLAUDE.md` routes any caller to it — built-but-unrouted, i.e. inert. Noted, not in scope.
- The investigation's implication, which this plan accepts: the deploy lane is **why every fix landed since 07-31 is inert**, so Step 0 is the value rather than a precondition. Corroborated independently here: **45 of 309** live-present tracked files differ in content from `origin/main`.

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

`LAND_PIPELINE_V2.md` (landed `8d50f953`, `status: complete`, the `/ground-up` exemplar) is the same
subsystem family and did not close this class. Verdict on its own R1-R9 requirements table:

| R | Bearing on the advance invariant | Verdict |
|---|---|---|
| **R3** — *"live `~/.claude` only ever advances to a full-suite-green tree"* | **This IS the incumbent invariant** | **DISCARD AS STATED.** R3 is a *safety* property with no *liveness* partner — **a property satisfied by never advancing is not an advance invariant.** In 10 days `deploy.log` records exactly **one** autonomous advance. |
| **R9** — *"absence is loud"* | **Falsified for this exact state** | **KEEP the requirement, DISCARD the claim it was met.** R9 was implemented per-*fault*; the failing state is the *gap between* faults (§1.8). |
| **R7** — *"fail-closed never amplifies; shedding = SKIP"* | The lane refuses 534× at one unchanged state with zero escalation | **EXTEND**: R7 covers *cost*, not *futility*. A fail-closed path must **escalate on repetition**, not merely refuse. This is D2. |
| **R6** — *"a non-verdict is never a red"* | `is_green()` conflates `red`/`cut`/`hung` | **KEEP** — and D1 is largely just applying R6 where the land path already honors it. |
| **R5** — bounds cover what they bound | The 0-green half's proximate cause was a bound scoring itself (`833dcf35`) | **KEEP, strengthen.** |
| **R1** — land p50 ≤ 30s at 12+ writers | Fast landing is *what makes trunk outrun the verifier* | **KEEP, and state the coupling** — R1's success is R3's problem. |
| R2 / R4 / R8 | trunk-red bounding · no-lost-commits · escalation parking | KEEP; R2's *"≤1 verifier cycle"* is not achieved (trunk red 65.6h). |

**The missing row.** `LAND_PIPELINE_V2.md:438-456` maps 16 observed v1 modes to v2 answers. **There
is no row for "the green cursor is behind live HEAD."** Its §3 architecture diagram (`:265-279`)
draws exactly **one** arrow into the checkout — the second advance path is nowhere in the design.
And decisively: `755dd24a`'s own suite already carried
`@test "refuses to roll back: newest green is BEHIND the live HEAD"` (2026-07-25). **The case was
anticipated as a refusal and never as a state to escalate from.** That single sentence is the class.

**The premise the deadlock most strongly SUPPORTS** (`:646-651`) — *"v1 had already built every v2
component but kept the verdict on the land path, so each component waited on the others' liveness and
none could go live — an architecture problem is not fixable by component quality."* The deploy lane is
now the same shape one level down: gate, guard, link-refresh, damping, host-checks, alarms, each
individually correct and covered by 37 tests in `tests/deploy-live.bats` — and the lane has advanced
once.

**Two of its own REVISIT triggers have fired** and are hereby re-opened, not re-decided here:
- *Off-box CI, rejected "for the verdict; optionable later for the pure-hermetic subset as a second opinion."* The dominant failing suites are the machine-coupled ones — a hermetic-subset second opinion is **a green producer the design currently lacks.**
- *Second verification host, "revisit only if cycle time under load exceeds ~2h sustained."* Measured p50 ≈ 3.2h sustained across the newest 8 stamps. **By the doc's own criterion this is open.**

### 1.7 The anti-rollback guard prevents a FALSE SUCCESS REPORT, not a rollback

Re-derived in a throwaway repo (never the shared checkout): because the target **is** an ancestor of
live HEAD, `git merge --ff-only <ancestor>` returns *"Already up to date."* with **exit 0** — it
cannot roll anything back. Without the guard, the lane would take that exit 0, print
`deployed a9060c18b314 → 3725e5432bfc`, run `install.sh`, run the host checks and file a host-RED
backlog item — **all against an unchanged tree.**

So the guard buys **truthfulness, not safety**. Removing it risks the lane *lying about having
deployed*, not losing work. This reframes what the rebuild is giving up, and it means the guard is
kept for a different reason than the one its own message states — *"this would ROLL BACK the live
layer"* is a misnomer that should be corrected to name the real hazard.

Provenance (`git log --diff-filter=A -- scripts/deploy-live.sh` → `755dd24a` only): **both guards
were introduced by one commit**, `755dd24a` (2026-07-25), and **neither has ever been weakened.** The
green-stamp gate answers a **named incident** — *"the old nag emitted a raw `git pull --ff-only`,
which deploys whatever happens to be on origin/main, VERIFIED OR NOT"* — so it must not simply be
deleted (this constrains D1, see §2.2). The anti-rollback guard has **no incident** anywhere in the
commit, its diff, its tests, or the plan; it is a design assertion only.

### 1.8 Why no alarm ever fired: the covered states are the two ENDPOINTS

`bin/cc-blockers` has two deploy alarms and our state falls between them:

- `deploy-lag` (`:425`) requires `git merge-base --is-ancestor "$head_sha" "$gcommit" || return 0`, under its own comment *"The ancestor test is load-bearing: **a green stamp BEHIND the deployed HEAD is history, not lag**"* — so in exactly our state it **returns silently**.
- `never-green` (`:401`) requires `[ -z "$gcommit" ]` — no green **ever**. We have two, so it never fires.

Its own comment concedes the shape: *"deploy-lag structurally cannot cover it (it needs a green in
order to call one late)"* — written about the no-green case; the mirror case (**green-but-behind**)
fell into the identical gap. **The predicate the filings actually asked for — *"no green stamp is a
descendant of live HEAD"* — exists nowhere in `cc-blockers`.** Live run 2026-08-07: one `trunk-red`
row, **zero deploy rows**, while the live layer is 91 commits stale.

### 1.9 The provenance correction, and the trap it sets for THIS session's close

Two counts in this plan's own §"Why this is a ground-up" were re-derived and are wrong in **both**
directions:

- **`#71` is not an independent filing.** `50.json` and `71.json` are twins from a multi-config-dir task-store merge that ran three times on 2026-07-29/30 (`mergedFrom: .claude-quaternary`, both `originalId: 30`); `71` carries the *pre-completion* text and never received the completion event. The identical duplication exists for `#51`/`#72`. **Do not cite `#71` as evidence of recurrence.**
- **The class was filed ~20 times, not 5.** Census of `backlog.jsonl` (1,132 distinct items) → 107 matching items; net of one auto-minting generator family (18 items, itself filed as `07e6e3888e9c`), the distinct filings of *"landed work is not live because the deploy lane will not advance"* run to roughly twenty, from `2a51b6db07d3` (2026-07-20) onward.

🚨 **And task `#50` — marked COMPLETED — landed no commit at all. It was CLOSED ON A PREDICTION.**
Its closing text: *"Deploy's refusal CHANGED SHAPE from structural … to ordering …, **which
self-resolves**: the next green unblocks the lane."* Disk truth: the next green took **5 days**, and
in the interval `deploy.log` accumulated **160 refusals for that one target across 13 distinct live
HEADs**. A third category, neither *never-landed* nor *landed-and-insufficient*: **closed on a
prediction that the class was self-resolving.** (`833dcf35` is the one real remedy in that window —
it fixed the retry ladder scoring its own bound as a failure, i.e. the **scarcity** half. It never
touched the **ordering** half.)

**This binds this session directly.** R2's forecast is that `SCAN_N=200` leaves ~66 commits of
headroom, after which the refusal flips from `would ROLL BACK` back to `no GREEN stamp` — *a change
of shape*. Closing on "it will start paging again once the message changes" would be **task #50
repeated verbatim**. No claim in this rebuild may rest on a predicted future state; every acceptance
criterion in §2.8 is a disk read taken after the fact.

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

### 2.2 D1 — a TWO-TIER target: prefer green, degrade to not-red under a budget *(dissolves F1, F2)*

**Revised after §1.7.** The first draft of D1 made the target simply *"newest commit carrying no red
stamp."* That is too weak: §1.7 establishes the green-stamp gate answers a **named incident** (the
old raw `git pull --ff-only` shipping unverified trunk to the whole fleet), so deleting it outright
re-enters the incident. The freeze is not caused by the gate existing — it is caused by the gate
having **no degradation path**. So the gate is kept and given one.

| Tier | Condition | Target | Banner / page |
|---|---|---|---|
| **T1 · verified** *(default, unchanged from today)* | a green-stamped tree exists that is a **descendant of live HEAD** | that commit | none — this is the healthy path and stays silent |
| **T2 · budgeted degradation** | T1 is empty **AND** lag exceeds `A3`'s budget | newest commit on `origin/main` whose tree carries **no red** stamp | **loud banner + a page recording that an unverified advance occurred**, with the lag that authorised it |
| **T3 · blocked** | T2's walk-back reaches a red at every candidate | no advance | page — a genuine "trunk is red all the way down" state, which is real information |

Stamp semantics under T2, applying R6 where the land path already honors it: **no stamp ⇒ eligible**
(absence is the common case and structurally guaranteed to stay so); **`cut`/`hung` ⇒ eligible** (a
non-verdict is not a red); **`red` ⇒ ineligible**, walk back one commit.

The absorbing state disappears because T2 makes the target a function of **trunk** rather than of the
evidence corpus, so it is ahead of live HEAD by construction. The anti-rollback guard is **kept
unchanged in behavior** — but per §1.7 its message is corrected to name what it actually prevents (a
false success report), not a rollback that `--ff-only` makes impossible anyway.

**The honest cost, stated plainly.** Past the budget the fleet may run code that has not been proven
green. It **already does**, silently: 13 ungated `merge origin/main` fast-forwards put it there and
45 of 309 live files currently differ from trunk. The change is not *unverified deploys start
happening* — it is *unverified deploys start being announced, budgeted, and logged* instead of
arriving through a side door nobody records. That is strictly more safety than today, not less.

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

### 2.6b D6 — a dirty tracked file is a LANE STATE, not a generic death *(dissolves F6)*

`deploy-live.sh` dies with `merge --ff-only … FAILED (dirty tree? diverged?)` — a guess with two
alternatives, printed at the moment it matters most. §1.7's Step-0 measurement shows the real state
is knowable exactly: `merge-tree --write-tree` rc=0 (trees clean) and one modified tracked path that
also changed on trunk. The lane must **name the blocking path**, distinguish *dirty* from *diverged*,
and treat it as its own escalation class.

It must **never auto-stash or auto-discard.** The blocking file is a peer session's uncommitted work
(`hooks/backup-before-write.sh` today), and the repo's own `26-deploy-gate-unblock` refuses exactly
this for exactly this reason: *"That is very likely a peer session's uncommitted work. REFUSING to
overwrite it… this script never discards local work."* Detect, name, page, stop.

### 2.6c Step 0, revised — a surgical one-file deploy strictly narrower than `--force`

**The rebuild has the same bootstrap circle it is fixing**, and this must be said plainly: a landed
`deploy-live.sh` v2 is *not live*, because the live layer executes the `a9060c18` copy, which still
refuses. The fix cannot deploy itself. That is `C4`/F5 applied to this very change.

The repo already ships the right primitive, and it is **much narrower than the `--force` the filing
proposed**. `26-deploy-gate-unblock-activate.sh` documents the pattern (used 2026-07-31 to deploy a
fix while the checkout was 119 behind with 4 live writers): `git checkout origin/main -- <one path>`
in the shared checkout — **HEAD unmoved, nothing committed, nothing stashed, one file staged**. Left
*staged* deliberately, because an unstaged-but-modified file is a local modification that blocks the
very fast-forward it exists to enable, whereas index==worktree==trunk self-resolves on the next merge.

| | Filing's Step 0 (`deploy-live.sh --force`) | This rebuild's Step 0 |
|---|---|---|
| What is deployed | **91 commits**, unverified, in one shot | **one file** — the fixed advancer |
| Verification net | bypassed wholesale, by banner | untouched; the new lane then advances under its own budgeted policy |
| Blocked by the dirty sibling file? | **yes** — dies at `:388` | **no** — a path-scoped checkout does not touch `hooks/backup-before-write.sh` |
| Reversible | re-deploy | `git checkout HEAD -- <path>` |

Both remain **operator-gated** — they write the shared checkout's index, which the `26-` script
itself classifies C10 precisely because 4+ live sessions share one index and a sibling's bare
`git commit` can sweep a staged file. The agent stages the script; the operator picks the moment.

**Blocker B is still separate and still real:** once the new lane advances, its `merge --ff-only`
meets the dirty `hooks/backup-before-write.sh`. D6 makes that a named, paged state instead of a
generic death — but the file itself must still be parked by its owner or by the operator.

### 2.6d Recorded disagreement — the pure-veto law, and why this design stops short of it

A peer session landed `docs/research/inertness-generator-2026-08-07.md` (`ad847c01`), deriving the
generator this lane is one instance of. Its §3 law, verbatim:

> *"Reverse the polarity of every edge on the conclusion→behaviour path: no affirmative-permission
> gate may hold an advance; all safety is expressed as veto-after — the revert of a named land."*

It cites this plan's `2aeb23a7` as its seed. **That citation is one commit stale** — `2aeb23a7` was
D1's first draft (*"evidence vetoes red, it never permits green"*), and `9055ef2e` revised it to the
two-tier form after the archaeology found the green gate answers a named incident (§1.7). Surfaced to
the peer 2026-08-07; recorded here so the divergence is durable rather than living in an inbox.

**Where we agree:** past the staleness budget, exactly — advance on not-red. **Where we differ:**
inside the budget, where T1 prefers a green when one exists.

**Two objections, both measured, offered as narrowing rather than refutation:**

1. **Unboundedness is the defect, not permission-polarity as such.** Their Law 2 indicts a permission gate because it *"fails as a STATE: standing, unowned, unbounded"*. Agreed, and that is precisely this wedge. But a gate with a finite escape — T2 fires past budget with banner + page — cannot rot into a standing state. The narrowed law *"no permission gate may be **unbounded**"* is also checkable in a way the absolute form is not.
2. **Pure-veto moves all safety onto a mechanism measured failing.** The law makes veto-after the sole safeguard. Census of `~/.claude/autonomy/postland/runner.log`, all time: **AUTOREVERT `landed`=3, `FAILED`=5, `skipped`=17 — 12% success across 25 attempts.** Newest: `2026-08-07T03:40:57Z verdict=FAILED(step=revert rc=90) culprit=13bfa557db3a`. And the 17 skips are **one** culprit (`b3f728858a6f`) — attempted once, skipped forever after under `reason=already-attempted`, which is itself a fixed point of the system's own policy, i.e. the peer's own Law 3 shape sitting *inside* the remedy their §3 prescribes.
   > **Census correction (2026-08-07, item `8e8a306f6dc0`).** The counts hold exactly — 25 encounters, landed=3, FAILED=5, skipped=17 — but the 17 skips are **four** culprits, not one: `a1743ffebd35` ×3, `47a5350498ee` ×3, `57e162494c10` ×3, `b3f728858a6f` ×8 (2026-08-04 → 08-07). The argument is unaffected and in one respect stronger: every skip still read `reason=already-attempted`, so the fixed point is not one unlucky sha but the marker's *shape*, reproduced independently four times. The correction also splits the remedy, because the four are not one case — `b3f728858a6f`'s revert **landed** (`3725e5432bfc`), so its 8 skips are the correct refusal to revert twice, while the other three never landed and were disarmed by a fact about a single trunk tip. Fixed in `scripts/postland-verify.sh` (C26): a landed revert stays permanent but now pages instead of skipping silently; one that never landed re-arms on a moved tip or `POSTLAND_REVERT_RETRY_DECAY_S`, bounded by `POSTLAND_REVERT_RETRY_MAX`, whose expiry pages.

This does not block either document; both are landed and `T0`-`T3` remain this session's. It is
recorded because a design that stops short of a cleaner-sounding law owes a reason.

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

- **2026-08-07 — T1/T2/T3 built, verified and LANDED (`dcf2f11a`).** Six paths content-verified on
  trunk (`git ls-tree` present + `git diff` empty on each; the original shas are not ancestors because
  `ship-land` rebases, which is exactly why this repo verifies by content).

  | Suite / gate | Verdict, re-run on the MERGED tree |
  |---|---|
  | `tests/deploy-live.bats` | rc=0, plan `1..47`, 47 ok (baseline 37 → **+10**) |
  | `tests/cc-blockers.bats` | rc=0, plan `1..88`, 88 ok (baseline 81, +6 t3, +1 lead) |
  | shellcheck / `bash -n` | clean on `deploy-live.sh`, `cc-blockers`, and the activation script |
  | budget env agreement | **verified** across both files, not inherited from the brief |

  **A non-verdict was correctly not read as a red.** The first `deploy-live.bats` run returned
  **rc 75** — `cc-bats: REFUSED — 2 concurrent bats execution root(s) … AND load/core ≥ 2.0` — with
  `ok=0 notok=0`. Lead-caused (two suites in parallel), zero tests executed, so it is a non-verdict per
  R6 and was re-run alone. Recorded because scoring it red would have convicted a healthy tree.

  **Both teammates policed their own vacuous controls**, which §2.8 A-6 demands and which is the
  failure mode this repo has been bitten by: t3 marked its silence test *partly vacuous* (its negative
  half passes on the pristine tree by construction) and forced each budget leg to 0 in turn instead of
  counting a free pass; t2 found L1 passes pre-change by construction and attributed it with a mutant
  that lets T2 preempt T1. t3 also attributed its render test with a **one-site `LAND_SEL` mutant that
  reddens that test and nothing else.**

  **Lead-fixed defect t3 flagged against itself** (`c50685b0`): `hrs()` rounds to nearest, so a 5h45m
  layer rendered *"HEAD 6h old"* beside a 6h budget while the row had fired on the **commits** leg —
  telling the operator the wrong leg tripped. Floored at that site only (`hrs()` has three other
  callers where rounding is right); RED-proven at exactly `[ "$age" -lt 6 ]`.

### 2026-08-07 — the state moved mid-session, and it CONFIRMS §1.2 rather than dating it

At 01:56:38 a **sibling session** fast-forwarded the shared checkout `a9060c18 → 13672c26`
(`merge <sha>: Fast-forward`). `ship-land.sh` does **not** sync the shared checkout — grepped, no
ff-sync exists — so this was an ungated writer, precisely the second path §1.2 names.

- **Blocker B resolved itself.** The sibling's `hooks/backup-before-write.sh` landed, the tree went clean, and the ungated path resumed **immediately** — which is the confirming experiment for §1.7's claim that the dirty file, not the stamp gate, was what stopped *every* writer for 33h. `merge-tree --write-tree` now rc=0. Filed operator step `8fdefffaabf7` retired as stale (`work-item-remedy-can-become-forbidden`: a park keyed on a mechanism fact that a later fix silently obsoletes).
- **Blocker A is untouched and now demonstrably HEAD-independent.** `deploy.log` refuses with the *same* target against the *new* live HEAD: `target 3725e5432bfc is not a descendant of live HEAD 13672c26e4bb`. The deadlock followed the layer forward, which is what an absorbing state does.
- **v2 is landed and NOT live** — the layer sits 7 commits below `dcf2f11a`, and the live copies carry **0** hits for `CC_DEPLOY_DEGRADE` and **0** for `deploy-stale`. This is §2.6c's predicted circle, observed rather than argued.

### Acceptance status against §2.8 — three buckets, no predictions

Per §1.9 this session may not close on a forecast, so each criterion is bucketed by what disk says now.

| | Criterion | Bucket |
|---|---|---|
| A-5 / A-6 | one RED-control per guard leg, vacuous controls named | **PROVEN** — verdicts above, each control RED against a `git archive` pristine tree |
| — | v2 lands on trunk, content-verified | **PROVEN** — `dcf2f11a`, six paths |
| A-1 / A-2 | the lane advances, verified by content | **ACCRUING** — gated on the activation below; read via `rev-list --count HEAD..origin/main` falling twice ≥1 tick apart, plus the symlink-target hash |
| A-3 | refusals stop increasing | **ACCRUING** — `grep -c 'would ROLL BACK' deploy.log` across ≥2 launchd ticks (`runs=` advancing) |
| A-4 | non-advance becomes loud | **ACCRUING** — a `deploy-stale` row on `cc-blockers` once the alarm is live |

The gap between PROVEN and ACCRUING is exactly one operator step, and it is the ceiling this session
can reach: **acceptance is a deployed layer, and the agent cannot deploy it.**

### 2026-08-07 — ACCEPTANCE READ, taken after the fact (not forecast)

The operator ran `27-deploy-lane-v2-activate.sh` and it reported **both files already live** — a
sibling had already delivered them via `reset: moving to origin/main` at 02:28:28. **The ungated path
deployed the fix for the gated lane**, which is §1.2's thesis demonstrated on this rebuild's own diff.

| # | Criterion | Read | Verdict |
|---|---|---|---|
| A-1 | layer advances | `rev-list --count HEAD..origin/main`: **107 → 0** | ✅ (by an ungated writer, stated honestly) |
| A-2 | verified by content | `md5` of each live symlink target == `git show origin/main:<path>` — `deploy-live.sh` and `cc-blockers` both identical; markers 5 / 3 hits | ✅ |
| A-3 | refusals stop | old-style `would ROLL BACK`: **542, frozen** (no longer emitted). New-style: **1**, damped to one per 24h window | ✅ |
| A-4 | non-advance is loud | that single refusal **wrote a page** (`deploy-blocked-5b6c7e3e53dd.page`) — against **0 pages across 534** old refusals | ✅ V3/C3 closed, live |
| A-4b | no false positive | `deploy-stale` rows at low lag: **0** | ✅ the control holds live |

**A defect the live run exposed, fixed and landed (`12e55d69`).** The first live v2 evaluation, with
the layer exactly on `origin/main`, emitted *"REFUSED — no GREEN tree is a DESCENDANT … nothing is
safe to deploy"*. Every clause true, verdict wrong: at `LAG_COMMITS=0` the candidate set is **empty**,
so no tier can match and the ladder fell through to T3's `die`. Reporting a hazard where there is only
completion — and `die` exits 1, so the healthy steady state would pin `launchctl … last exit code = 1`
forever, the exact signal that hid the original freeze. §2.2's tier table had no row for *"already at
the tip"*; it does now.

Two second-order findings from that fix, both worth keeping:

- **Placement was itself a finding.** Keying the exit on TIP *before* the ladder also swallowed the `already deployed` state (a green **on** the live commit with unstamped commits above), which is genuinely more informative. It reddened two tests **that were right** — so the check belongs *inside* the T1-missed branch, on the same `LAG_COMMITS` precondition T2 already uses.
- **`tests/deploy-live.bats:28` had pinned the defect as intended behaviour** — its own comment read *"Lag here is 0 commits … this stays a refusal forever."* Its **subject** was never the exit code but the 2026-07-30 regression that `link_refresh` was dead code below the advance (`[ -L "$DEST" ]`). That assertion is untouched; only the fixture moved back onto the path it means to exercise. The rule that decided it: the side with the incident wins, and both sides had one.

**Residual, measured not assumed:** within budget with no green descendant the lane still refuses and
exits 1. That is **not** the deadlock class — it is bounded (T2 fires past the budget), damped (1 per
24h), and now **paged**. Recorded so a later reader does not mistake a bounded wait for the freeze.

### 2026-08-07 (later) — D5 and D4 closed; the two deferrals were BOTH false

Both remaining deliverables had been left on a prediction, and disk refuted both. This is the §1.9
trap firing on the rebuild's own tail rather than on its subject.

**D5 — the deferral's premise was false.** Phase 0 left D5 unassigned with a reason: *"it is downstream
of T2, so once the lane can advance the platter becomes runnable on its own. Re-verify after the merge
rather than fixing it twice."* Re-verified. Measured state: live layer **21 behind, 1h old** — both
**inside** the T2 budget (25 / 6h) — and no green descendant, so the ladder reaches T3 and dies. The
platter's RUN 1 could not succeed, by the lane's own verdict:

```
$ deploy-live.sh --dry-run
REFUSED — no GREEN tree is a DESCENDANT of live HEAD fda70147faaf … nothing is safe to deploy
$ cc-do --list
  RUN  1. deploy-live            [live layer 19 behind origin/main]
         bash ~/.claude/scripts/deploy-live.sh
```

The premise assumed the *degraded* path is the only way the lane declines; the **within-budget** state
is a third one, and it is the steady state, not an edge. Fixed in `e9ea14d6`: both renderers now **ask
the lane** (`--dry-run --offline`) and downgrade a refusing deploy to `⊘ HELD` carrying its reason —
named and counted, never numbered, never run. The predicate stays in the actuator; a second copy in a
renderer is what drifts.

`--offline` is new and exists for this call. Not plain `--dry-run`, for two reasons, and the second is
the load-bearing one: `operator-readout.sh` is a **Stop hook**, so a fetching probe is a network
round-trip at every turn close; and a *failed* fetch `die`s rc 1, which the caller reads as *"the lane
refuses"* — **a renderer reporting a deploy blocker that it caused itself.** It decides against the
already-fetched `origin/main`, the identical ref both renderers already use for `behind`.

**The enabling measurement.** The probe was 3.06s, too slow for a Stop hook. The cost was not the
fetch — it was the ladder forking `git rev-parse "$sha^{tree}"` per candidate, up to `SCAN_N`=200 per
evaluation: **2.233s vs 0.011s** for one `git log --format` process. Batched, byte-identical verdict,
probe now 0.86s — and ~28,800 forks/day removed from a job that runs 144×/day. It was slowest in
exactly the state that mattered, because T1 `break`s early only when it *finds* a green descendant.

**D4 — landed in a committed file, never reached launchd.** §2.5's fallback landed in `601908fe`. The
enforcing store never saw it:

| | ProgramArguments |
|---|---|
| repo `launchd/com.claude.deploy-live.plist` | `D="$HOME/.claude/…"; [ -x "$D" ] \|\| D="$HOME/Development/…"; exec "$D"` |
| **LIVE** `~/Library/LaunchAgents/…` (a COPY, mtime 07-30) | `exec "$HOME/.claude/scripts/deploy-live.sh"` |
| **LOADED** job (`launchctl print`) | the same pre-fix form |

`27-deploy-lane-v2-activate.sh` deployed the two *scripts* and says so in its own banner — *"Neither
launchd job was modified. No plist was touched (C10 intact)."* Correct and deliberate; the consequence
is that half of one change reached a commit and no enforcing store. Staged as
`34-deploy-plist-fallback-activate.sh` (`5802fecf`) — C10, operator-run. It asserts its own
precondition (a checkout behind `601908fe` would install a plist *without* the fallback and report
success), verifies **by content** out of `launchctl print` rather than trusting bootstrap's rc, and
its dry run prints the currently-loaded exec target so the operator sees the pre-fix form themselves.

**RED-controls (§2.8 A-5/A-6)** — each red against a `git archive 07f9707c` pristine subject carrying
these same tests. Suites: `deploy-live` 54/54 (was 49) · `cc-do` 28/28 (was 25) · `operator-readout`
63/63 (was 60).

| Leg | Pristine | Now |
|---|---|---|
| `--offline` agrees with a fetching run · decides with the remote unreachable · refuses with no fetched ref · one-process ladder | **RED** ×4 | ok |
| a refusing lane is HELD not RUN · a HELD deploy is never executed | **RED** ×2 | ok |
| `⊘ HELD` row draws no runnable slot · the probe is asked with `--offline` | **RED** ×2 | ok |

**Three controls pass on BOTH trees by design, and are declared rather than hidden** — A-6 asks for
exactly this. `deploy-live 52` (the *fetching* path dies on a broken remote) exists so leg 51's
absence-assertion has a control that *can* fail the same way. `cc-do 27` and `readout 62` are the
positive controls against the gate degenerating into always-hold: pre-change every deploy was RUN, so
they *must* pass on the pristine tree.

**And one existing test was retargeted rather than left to pass vacuously.** `cc-do` *"a REFUSING
deploy step does NOT halt the run"* used `mklag 1`, which post-change is HELD and never runs — so *"it
did not halt the run"* would have been true **because nothing ran**: a control passing because a
sibling mechanism already fixed what it tests. Its fixture is now probe-passes/run-fails, which is the
residual risk the skip genuinely exists for — the probe is taken when the board is **rendered** and the
run happens seconds later. The skip path is kept for that reason and is now the only thing testing it.

**A guard that indicted its own provenance.** The first spelling of the one-process test counted the
old pattern anywhere in the file and went red on `deploy-live.sh`'s **own comment explaining the
removal**. Anchored to `^[^#]*`: a text guard that cannot tell code from a comment forbids naming the
defect you fixed.

**This plan's own scar caught this plan's own diff, and that is the closing evidence.** The land gate
ran `permission-gate-lint` — built from `docs/research/inertness-generator-2026-08-07.md` §2.3 and
citing *this rebuild's* `dcf2f11a` as its worked example — and it went RED on `deploy-live.sh:444`,
the `--offline` missing-ref guard. Correctly: *"no already-fetched `origin/main` ⇒ die"* is an
affirmative-permission predicate on an actuation path with no clock, i.e. exactly the shape whose
un-clocked ancestor emitted 545 refusals. Attribution was measured, not assumed — the selftest passes
**29/29 on pristine trunk** and failed only on this branch.

The fix was not a declaration. It was noticing the guard had a **real** defect underneath: `--offline`
skips the fetch, so it decides against a possibly-arbitrarily-stale tip — and it could still **really
merge**. A no-network mode that deploys old trunk without ever saying it had not looked is a footgun
independent of any lint. `--offline` now forces `DRY_RUN` at parse time, which removes the mode from
the actuation path altogether, and *that* is what makes the `gate_bounded:` declaration true rather
than convenient: a gate that cannot withhold an advance can only decline to answer a question.

**And the first declaration was itself laundering — the lint caught that too.** Placed on the
enclosing `if`, the marker was accepted (the lint lets a multi-line gate declare its bound once) and
the count dropped from 10 to **9**: it had silently exempted the `git fetch … || die` on the *else*
branch, a pre-existing gate that **is** on the actuation path and is what the 144×/day launchd lane
hits. The marker's own text was false of that leg. Moved inside the branch, the count returns to 10
and the fetch gate stays counted. The ratchet's downward half — *"the count going DOWN is ALSO a
finding"* — is what surfaced it; without that half a marker can buy exemptions for its neighbours.

**Two REVISIT triggers §1.5 re-opened are now FILED**, not left in prose — `b4f93c9fa73c` (off-box CI
for the hermetic subset, a green producer the design lacks) and `343d7cc392b6` (second verification
host; the doc's own ~2h criterion is exceeded at p50 ≈ 3.2h). A completed plan's prose is where an
un-filed item goes to die.

**Remaining, and it is the operator's:** run `34-deploy-plist-fallback-activate.sh`. Nothing else in
this plan is open — `status:` flips to complete on that basis, with D4's activation surfaced through
the pending-activation queue where the platter renders it by construction.

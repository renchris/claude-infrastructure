---
status: complete
---

<!-- CLOSED 2026-09-09. The wave condition was adjudicated discharged on 2026-09-07
     (docs/research/w4-fire-gate-adjudication-2026-09-07.md) and independently re-verified clause by
     clause on 2026-09-09; see the Status log's final entry for the measurements and for where each
     residual now lives. `status: complete` is load-bearing: it is what retracts the derived
     plan-open falsifier, so this document stops minting a dispatch row every pass. -->

# MASTER: fire gate — what spawns, where it runs, and what refuses it

**Condition key:** `master-fire-gate` · **Live members 2026-08-12 (measured after the apply):** 62 (52 open · 9 blocked · 1 claimed)
**Inventory:**
`cc-backlog list --all --json | jq -r '.[]|select(.condition=="master-fire-gate" and .status!="done")|"\(.id) \(.status) \(.title[0:90])"'`

**Why this is ONE effort.** Every member is a defect in the same pipeline: a row is labelled for a
venue, admitted against a capacity term, claimed under a lease, fired with a brief, and returned. The
pipeline was measured **dead in place for 1 h 34 m** on 2026-08-12 (`fired:0, deferred:318`, no
timeout) and unwedged by W0 of the parent plan — but the arms that keep it self-healing are the least
proven part of it, and the members here are exactly those arms.

## Phase 0 · Agent Team Orchestration

**EXECUTION LOCUS PER WAVE.** S = dispatched handoff session (the default) · T = in-session teammates · L = lead-inline.

🚨 **SUPERSEDED FOR THE LOCAL DRAIN (2026-08-13): read every `S` below as `T`.** This table was
authored under the one-session-per-wave model. The non-cloud backlog is now worked by THE LOCAL DRAIN —
a single standing session whose entire purpose is that it occupies **one** of the ~15 concurrent slots
for its whole life (`BACKLOG_SELF_DRAINING_2026-08-12.md:392`: *"One slot, indefinite duration — because
the bottleneck is concurrent sessions (~15), not session length"*). Firing a dispatched session per wave
spends a second slot and defeats the mission. Work every wave with **teammates INSIDE the drain session**
(`Agent({name})`, worktree-isolated, ≤150-line briefs, each torn down with a structured
`shutdown_request` — a plain-text broadcast leaves an orphaned pane and worktree), and recycle at the
EFFORT boundary via `handoff-fire.sh --recycle` — same pane, fresh context, no new slot. The `S` markers
below are left in place as the historical record of how these waves were originally scoped.

| Wave | Execution locus | Deliverable | Depends on |
|---|---|---|---|
| **F1 · venue labelling** | **S** | every live row carries a `venuePlan`; the producer is not open-only | — |
| **F2 · the cloud round trip** | **S** | a fired cloud session provably retires and returns; `.retired` > 0 | — |
| **F3 · claim coverage** | **S** | no spawn path fires into a dispatch worktree without claiming | — |
| **F4 · the stale brief** | **S** | a fired worker reads its DoD from a TRUNK REF, not a shared-checkout path | — |
| **F5 · admission terms** | **S** | admission keys on ACTIVE concurrency with a memory term that can bind | F1 (venue term) |

All five are dispatched; F1 and F4 must land before `master-*` waves are fired at scale, because they
are what makes a fired brief correct.

**Lead context budget:** ≥50% held for the venue/capacity judgment calls. **Succession point:** after
F2 — the cloud round trip is a long observation window and deserves its own context.

## Sub-waves

### F1 · Venue labelling (the prerequisite W2 named) — DONE (refuted 2026-09-07; residual DROPPED 2026-09-09, harm measured)
**248 live rows carry no venue label at all**, because `cc-venue run` is open-only and new rows wait
for the next producer pass; the dispatcher is journalling `ready:false, state:"void",
reason:"venue-unlabelled"` right now (advisory, so not yet blocking).

🚨 **Do NOT "solve" this with `CC_DISPATCH_VENUE_ONLY=cloud`.** Only 47 of 536 rows (8.8%) are off-box
eligible, so that parks 489 rows indefinitely — and because the claim path is the only *blocking*
re-validation in the system, it also silently switches currency-checking off for 86% of the store. The
venue lever steers; it does not scale.

### F2 · The cloud round trip — DONE (refuted 2026-09-07; residual REFUTED 2026-09-09 — its remedy is a trap)
`cc-cloud retire` is FORWARD-ONLY: 41 declarations carry **0 `.retired` markers**. W0 wired the
terminal path to retire, but the release path has been DEPLOYED and never EXERCISED — its coverage is
structural and the behavioural proof is one live round trip. Also here: cloud create is intermittent
(1 of 4 on next3), a dispatcher-driven session sits NOT-STARTED past its boot budget, cloud fires die
on a LOCAL worktree freshness gate the VM never touches (2 of 3 lost), and two lands can run
concurrently on one cloud branch because the single-flight lock is per-PASS.

### F3 · Claim coverage — DONE (mitigated 2026-09-07; owning row closed 2026-08-21)
**Four spawn paths** fire a session into a dispatch worktree without ever calling `cc-backlog claim`,
so the lease governs a population that does not include them — and 20 live sessions were once measured
sharing one item's worktree. The lease is the whole economics of the grouping this wave inherits; a
spawn path outside it is a hole in the mechanism, not a missing nicety.

### F4 · The stale brief, by construction — DONE (fixed at the consumer 2026-09-07; proven at runtime 2026-09-09)
`cc-dispatch` composes its prompt from the row's title and `dodRef` — and **every `dodRef` in the
store is an absolute path into the SHARED CHECKOUT, which trails trunk.** So a worker reads a DoD from
bytes older than the fix it is being asked to build on. The `master-*` rows created by W2 write
`origin/main:docs/plans/<FILE>.md` instead; make that the rule for every producer.

### F5 · Admission terms (Wave D) — DONE (landed `61e39ef3`, verified BY CONTENT 2026-09-09)
The measured bind is `load >= 2.0/core` and it is asymmetric: unbounded for `handoff-fire` (**the
operator's own path**), budget-released after 3 refusals for unattended callers, and off entirely for
the Agent tool. W3 of the parent plan owns the symmetry; this wave owns the *terms* — admit on ACTIVE
concurrency, with a memory term that has ever actually bound.

✅ **LANDED 2026-08-13 — `61e39ef3`** (backlog `1c45598a91be`; D7 of `CONCURRENCY_PROGRAM.md` closed
by decision, not by waiver). `scripts/lib/capacity-admit.sh` carries `segments` (compressor-segment
%, ceiling 50, provisional and re-derivable from its own rows) and `active` (sessions mid-turn,
ceiling 8), plus `reserve-active` on proven operator presence; the mid-turn census is
`cc_sp_active` in `scripts/lib/spawn-presence.sh`. Both new terms are ON for the Agent tool — the
path that turns the LOAD term off, and the one axis 10's F3 fan-out actually travels. Full note,
including the three corrections the build made to the item as specified:
`CONCURRENCY_PROGRAM.md` §S6.6-LANDED.

⚠️ **Two things this wave did NOT close, named so they are not assumed:** (a) `handoff-fire.sh`'s
`capacity_gate()` — the OPERATOR's path — still carries only load+headroom. The MEASUREMENT is
shared (`cc_hw_compressor_segment_pct` sits in the shared-terms block ready for it); only the policy
is not wired, because adding a refusing term to the human's own path is a value call, not a build.
(b) F3's thundering herd is a **wake** of existing residents, and no spawn gate can see one by
construction — wake-side damping remains open and in no wave's scope.

## Definition of done
A row can be fired without a human in the loop: labelled for a venue, admitted on a term that binds,
claimed by the worker that runs it, briefed from a trunk ref, and returned with its slot released —
demonstrated by one full local round trip and one full cloud round trip carrying a `.retired` marker.

## Status log
- **2026-08-12 — created by W2 of `BACKLOG_SELF_DRAINING_2026-08-12.md`.** 57 rows on this condition
  (21 pre-existing from the 2026-08-09 triage, 7 by its verdict replay, the rest semantic).
- **2026-09-07 — the wave ADJUDICATED against trunk; F4 fixed at the consumer.** Full record with
  every measurement: `docs/research/w4-fire-gate-adjudication-2026-09-07.md`. Three of the four
  conditions this plan states are refuted on today's tree, and two of its own claims were already
  false when it was written:
  - **F1 REFUTED on the number.** 248 → 147 unlabelled, of which **144 are blocked and 3 open**; a
    blocked row's `venuePlan` is read by nothing (`cc-dispatch:1859`, pinned at `:3507`), so the
    dispatch-relevant population is **4**. The cure — `venue_label_new` at write time plus
    `ready_relabel` at admission — landed in **`5ac7990d9` on 2026-08-11, the day BEFORE this
    document was authored**; § F1 restated a 2026-08-09 measurement that was already cured.
    `cc-venue run` is indeed still open-only (`bin/cc-venue:587`), so that clause is literally
    unmet and materially irrelevant. 🚨 **This section's own anti-remedy was in force the whole
    time:** `CC_DISPATCH_VENUE_ONLY=cloud` entered the dispatcher plist in `9d2e50e34` (2026-08-11)
    and was removed **today at 17:37:06Z**, parking ~95% of the local queue (`venue-only=cloud
    parked 184 of 192`) — which is why the repair never drained the local rows. Residual: 4 rows
    that reach neither admission nor the truncated sweep pass.
  - **F2 REFUTED.** `.retired` is **666 across 687 declarations**, not 0 across 41; 79 `.returned`,
    74 of them retired within 0–2 s. Boot budget, the cloud-blind freshness gate and concurrent
    lands are all discharged (`a48ab4594`, `e39aa0be1`, `0efcc073d`, `8454c5778`, `land-lock.sh`).
    Residual: no per-BRANCH interlock, costing minutes on an operator-invoked path.
  - **F3 MITIGATED, and adjudicated 2026-08-21** (`BACKLOG_DRAIN_24_7.md`:24177-24297). The four
    paths still do not claim, but three cwd-keyed PreToolUse gates cover them; two of the four fire
    into a cloud VM, not a dispatch worktree, so they are outside this section's own title. "20
    sessions sharing one worktree" is not reproducible — 3 dispatch worktrees occupied, 1 session
    each.
  - **F4 — claim refuted, defect real, and THIS SECTION'S PRESCRIBED REMEDY IS A TRAP.** Not
    "every dodRef": 3 trunk-ref, 23 absolute, 57 other — and all 18 shared-checkout paths come from
    ONE producer line (`bin/cc-discover:273`). Do **not** "make that the rule for every producer":
    `cc-eligible._dod_path` and `cc-premise._plan_dodref` both resolve a dodRef as a FILESYSTEM
    path, and the second FAILS OPEN on a trunk-ref spelling — silently deleting the derived
    plan-open falsifier that those same 18 rows depend on. A third arm, `dod_trunk_state`, was
    already mis-answering that spelling as `absent`, so adopting the remedy at scale would have
    made question 1b refuse the newly-correct rows off-box. **Fixed at the CONSUMER instead**: new
    read-only verb `cc-venue dodspec` renders the DoD line as a trunk pathspec at compose time
    while the stored path stays as the filesystem arms expect it, fail-open so a missing resolver
    costs nothing. 20 tests, 15/15 red-proved. Harm re-measured: the shared checkout was 1 behind
    trunk **with 23 dirty files**, so the risk was a sibling's half-written file, not merely stale
    bytes.

- **2026-08-13 — F5 landed (`61e39ef3`).** Both terms in the gate, 21-case suite
  (`tests/capacity-admit-active.bats`) green and red-proved 0/21 against pristine trunk. Its
  dependency on F1 turned out to be nominal: F5 is a *machine*-capacity term and never reads a
  venue label, so it did not wait. The DoD's "admitted on a term that binds" clause is now met;
  the other four clauses are unchanged.

- **2026-09-09 — CLOSED. All five DoD clauses re-verified independently against trunk, and this
  session is itself the local round trip the DoD asks for.** The 2026-09-07 adjudication ruled the
  wave condition discharged but left the plan `status: open`, so `find-plan.sh --list-open` kept
  returning it and `cc-discover`'s C2 critic kept minting a dispatch row from its H1 — the
  `a50e6ab779e8` shape the derived falsifier exists to catch (a row read "advance README hero
  banner" for twelve days after that banner landed). Closing the frontmatter is therefore not
  bookkeeping: it is the only thing that retracts the claim. Verified from a worktree at
  `HEAD == origin/main` (0 behind) with the firing dispatcher's blob equal to
  `origin/main:bin/cc-dispatch`, so nothing below is read through a stale tree.

  | DoD clause | Verdict | Evidence, measured 2026-09-09 |
  |---|---|---|
  | labelled for a venue | MET | 80 of 89 open rows labelled; the 9 unlabelled route LOCAL and self-repair (below) |
  | admitted on a term that binds | MET | `scripts/lib/capacity-admit.sh` carries `segments`+`cc_sp_active` on trunk; `tests/capacity-admit-active.bats` present; the gate REFUSED two of this session's own subagent spawns at `13 sessions mid-turn > ceiling 8` — a term that binds, observed binding |
  | claimed by the worker that runs it | MET | row `6464f9d641ff` reads `status: claimed` while this session holds it |
  | briefed from a trunk ref | MET | see the runtime proof below |
  | returned with its slot released | MET | 676 `.retired` / 80 `.returned` under `~/.claude/autonomy/cloud`, newest `2026-09-09T02:04Z` — up from the adjudication's 666/79, so the round trip is live, not historical |

  **F4 is proven at RUNTIME by this session, which is stronger than the structural proof the
  adjudication had.** Row `6464f9d641ff` stores `dodRef:
  /Users/chrisren/Development/claude-infrastructure/docs/plans/MASTER_FIRE_GATE.md` — an absolute
  path into the shared checkout, F4's exact defect, still there because the store deliberately was
  not changed. The brief this worker actually received carried
  `DoD ref: origin/main:docs/plans/MASTER_FIRE_GATE.md`. That is `cc-venue dodspec`
  (`bin/cc-venue:625`, consumed at `bin/cc-dispatch:2981`) rendering the trunk pathspec at compose
  time while the filesystem arms keep the spelling they need — the consumer-side fix working on a
  live fire, not in a test.

  ⚠️ **`61e39ef3` is NOT an ancestor of `origin/main`** — `git merge-base --is-ancestor` exits 1.
  The land rebased it and rewrote the object. F5 was therefore verified BY CONTENT
  (`git show origin/main:scripts/lib/capacity-admit.sh`, `git ls-tree origin/main`), never by the
  cited sha. Memory: `cited-sha-may-not-survive-the-land`.

  **Residual dispositions — each one moved to a store that is read, or refuted here so nobody
  builds it.** The adjudication wrote that the residuals "belong to their own rows"; measured today,
  *no row was ever created for any of them*, and this document was about to become `complete`, which
  removes it from every producer's view. A residual recorded only in a closed plan is deleted, not
  deferred (memory: `a-plan-is-not-a-queue`).

  - **F1's residual — DROPPED, with the harm measured rather than assumed.** It has GROWN, 4 → 9
    open rows carrying no `venuePlan` (created 2026-09-04..09), so re-measuring mattered. It is
    still not a defect: every gating reader in `bin/cc-dispatch` tests `venuePlan == "cloud"`
    (`:2087`, `:2103`, `:2119`, `:2123`, `:2742`), so an empty label is read as *not cloud* and the
    row routes LOCAL — the safe default — and the admission-time repair inside `ready_state()`
    (`:1519`) relabels it in the same call that consumes it. `CC_DISPATCH_VENUE_ONLY` is unset, so
    the one filter that could park an unlabelled row is not armed. Consequence: none. Not filed.
  - **F1's residual has a CAUSE that is not the venue producer, and the cause is NOT the row this
    close first blamed.** `cc-venue run --apply` has exactly one automatic caller,
    `scripts/autonomy-sweep.sh` §2b-ii, on a 6 h cadence. Both `~/.claude/autonomy/venue-pass.stamp`
    and `premise-pass.stamp` have mtime **2026-09-07 ~12:00 — ~40 h stale**. The stamp is claimed
    BEFORE the pass runs, so a stale stamp proves the block was never REACHED, not that it ran and
    found nothing. Requested cadence is not delivered cadence (memory:
    `init-state-is-not-runtime-state`): the delivered tick rate is **2.2/h against a requested 12/h**.

    ⚠️ **The self-bound is only half the mechanism, and the first draft of this entry got it wrong.**
    Over 24 h, **52 ticks started: 26 self-bounded and 26 were SIGTERM'd by `cc-reaper`'s 600 s
    orphan-bash floor**, and ZERO reached below `1-collect-pages-alarms` — the other nine
    `sweep_yield` checkpoints have never fired in 7 d. Two drivable causes, neither of them the
    launchd plist: (1) the **D4 author-death join (`:646-762`) is UNBOUNDED** — p50 582 s, max
    1,459 s — so a tick entering it at t≈390 s reaches ≈970 s and is reaped, defeating the 400 s
    self-bound whose whole arithmetic (`400 + CC_SWEEP_BOUND_S 180 = 580 < 600`) assumes every phase
    fits 180 s; (2) **branch prune (`:556-581`) returns `rc=124` on 52/52 ticks**, burning p50 242 s
    — 60 % of the entire budget — and completing nothing.

    🚨 **CORRECTION, same session: cause (1) is MIS-ATTRIBUTED, and the right row already existed.**
    The join figure came from INTER-ROW DELTAS, which measure the span between two unrelated IDL
    rows and therefore cannot attribute a cost to a phase at all — the subagent that produced it
    said so, and this entry used it anyway. `36ce331197ce` (filed earlier, `blocked`) names the
    mechanism with DIRECT evidence instead: **§0a's cloud-return arm is bounded at 900 s inside a
    tick that ends itself at 400 s**, so one arm can consume the entire budget and measurably does
    — *elapsed at yield: median 1009 s, max 4883 s*. An arm over-bounded relative to its own
    container beats any hypothesis about a loop further down. It is correctly blocked on an operator
    design fork (A: move the 900 s land arm to its own launchd job — a `c10` migration; B: hoist the
    remaining cheap read-only arms above §0a), and three other plans depend on the placement
    headers either candidate would contradict. Three cheaper hypotheses were also refuted here:
    `close-attrib.jsonl` is 145 KB / 672 lines so `join_closed`'s per-marker grep is ~2 ms,
    `join_world_probe` already caches its `it2 session list` for the whole tick, and the join loop
    already caps at `JOIN_MAX_PER_TICK=100`.

    🚨 **The blast radius is far larger than "the venue label is stale": 14 of the 22 arms below the
    cut are WRITERS**, including the class-B default actuator, six event-dir reapers,
    `cc-premise sweep --record --close-falsified`, the custody deathwatch, and **§3 the desk notify —
    the only channel by which any of this reaches the operator.** Measured on disk: **154 new pages
    and 57 new announce-alarms written since the cut, none collected, summarised or delivered.**

    **This is a fix that landed and whose symptom survived.** Row `8e0a3eb2c4a4` is `done`, and its
    evidence cites precisely the arithmetic that is refuted above — it was closed on a STRUCTURAL
    proof (11 checkpoints exist, 70/70 bats green) where the claim was BEHAVIOURAL (does the lower
    half now run?). Downstream, `2d91af430c60`'s acceptance criterion (`premise_pass_rc:0 note:ok`)
    is **structurally unreachable** while this holds, and two workers have already burned claims
    against it. **Not a new row: `36ce331197ce` already owns this** — `6de092171021` and its
    re-filing `ebd907a9666f` were minted here before that row was found and are both closed as
    duplicates pointing at it. What this session added to it is landed `f0f57ea85`: per-phase
    elapsed at every `sweep_yield` checkpoint (bats 75/75, red-proved 2-of-3 against `origin/main`
    with the CONTROL green). That is not decoration — `36ce331197ce`'s own numbers are *elapsed at
    yield*, i.e. CUMULATIVE, so nothing on this box could cost an INDIVIDUAL arm, and its A-vs-B
    fork is precisely a question about per-arm cost. `41d05eae511c` is a genuine AGGRAVATOR and stays operator-blocked — its plist FILE
    dropped `ProcessType Background` on 09-06 but the LOADED job still reports `nice = 5` /
    `spawn type = background (5)`, so a `launchctl bootout+bootstrap` is still owed; the measured
    blast radius above was added to that row rather than duplicated into a new one. Evidence:
    `/tmp/sweep-reach-2026-09-09.md`; predecessor analysis `docs/plans/DRAIN_CIRCUIT_2026-09-01.md`
    §3b, which prescribed the self-bound that proved insufficient.
  - **F2's residual — REFUTED, and its prescribed remedy is a trap.** "No per-BRANCH interlock"
    reads as a hole; it is the opposite. `scripts/land-lock.sh:13-20` keys the mutex on the SHARED
    git dir (`--git-common-dir`), explicitly *not* the per-worktree toplevel, so at most one land
    runs per REPO across every worktree — strictly stronger than per-branch, and the fix for
    G-P9-1. The wait it costs is real and was measured (last 200 lands: mean 123.5 s, 28 % over
    60 s, max 1700 s), but every one of those lands targets one trunk, so serialising them is
    required, not a granularity defect: re-keying the lock per branch would restore exactly the
    rebase race the repo key was introduced to remove. Conviction that per-branch keying is the
    wrong remedy: ~93 %. Deliberately NOT filed, so that no later session implements it as written.
  - **F5's residual (a) — REFUTED. The operator's path is already wired.** This plan records that
    `scripts/handoff-fire.sh`'s `capacity_gate()` "still carries only load+headroom … only the
    policy is not wired", and that it was left so because a refusing term on the human's path is a
    value call. That was true when written and is false today: `capacity_gate()` carries a live
    `segments` term (`CC_FIRE_SEGMENT_TERM`, default `on`, ceiling `CC_FIRE_MAX_SEGMENT_PCT` →
    `CC_ADMIT_MAX_SEGMENT_PCT` → 50) reading `cc_hw_compressor_segment_pct`, and a live `active`
    term (`CC_FIRE_ACTIVE_TERM`, default `on`, ceiling 8) reading `cc_sp_active` — each with its own
    REFUSE branch, `emit_fire_refusal` and bounded-budget release, not a comment. The value call was
    made and shipped; no row is owed. Nothing was filed, deliberately: filing a `needs-human`
    decision that the code has already answered would have handed the operator a settled question.
  - **F5's residual (b) / F3's second half — wake-side damping — PARTIAL, and the open half is
    filed.** Per-TARGET damping does exist (`bin/cc-wake-headless` `CC_WAKE_MIN_S`, exit 2 =
    damped; `bin/cc-notify` reports a damped wake), so a single session cannot be hammered. What
    the plan actually named is different and still missing: a *herd* — many existing residents
    woken at once — which per-target damping cannot see, because each individual wake is its first.
    Filed as an ordinary open row; it is drivable agent work, not an operator gate, and it needs its
    own effort rather than a closed wave's footnote.
  - **F4's producer-side change** (`bin/cc-discover:273` still writes absolute paths;
    `bin/cc-discover:329` writes a worse `$HOME/.claude/…` deployed-layer path) stays deliberately
    untaken — it must move `cc-eligible._dod_path` and `cc-premise._plan_dodref` in the same diff or
    it silently deletes the derived plan-open falsifier. Filed as its own row carrying that
    constraint, because the constraint is the whole reason it was not done.

# D — The landing/deploy decision record (what the 100th-percentile judgment must not re-derive)

Scope: docs/plans/{LAND_PIPELINE_V2, SHIP_LAND_HARDENING_PLAN, DEPLOY_DECOUPLING_V2,
DEPLOY_GATE_CONVERGENCE, DEPLOY_LANE_GROUND_UP}.md · docs/research/{land-gate-serialization-2026-07-25,
LANDING_GATE_ROOT_CAUSE_2026-07-26, POSTLAND-CELL-BISECT-2026-07-29, inertness-generator-2026-08-07}.md
· docs/research/land-pipeline-v2-research-2026-07-28/. Repo read-only. Every "implemented?" cell was
verified by grep/git/launchctl this session, never assumed.

---

## 0. THE HEADLINE THE LEDGER FORCES

**The premise under judgment is falsified by the repo's own telemetry.** "Lands queuing behind peers on
the machine-wide lock inside 1h+ turns" was **v1's** pathology and it was **fixed on 2026-07-28**.
Measured over `~/.claude/land.log` (2,929 rows, split at the 2026-07-28 12:00 cutover):

| | PRE-v2 (n=447 lock rows) | POST-v2 (n=1,015 lock rows) |
|---|---|---|
| lock `wait_s` p50 / p90 / p99 / max | 0 / **1,961s** / **3,601s** / **7,386s (2h03)** | 0 / **77s** / **247s** / **728s** |
| lock `hold_s` p50 / p90 / max | 78 / 682 / **6,771s (1h53)** | 61 / 119 / **282s** |
| `exit 75` (waited the full 3,600s ceiling, gave up) | **19 events**, all 2026-07-26 | **0** |
| waits > 600s | 86 events | **1** (2026-07-30, 728s) |

**Lock utilization, last 7d: 1.2% · 0.7% · 1.5% · 1.8% · 3.6% · 4.1% · 4.8% · 3.2% of each day.**
A mutex held under 5% of wall-clock cannot generate hour-scale queues; at that occupancy the queueing
term is negligible, and the measured p90 wait of 77s confirms it. **The machine-wide land-lock is not
the congestion.** Any plan premised on "unwedge the land lock" is aimed at a solved problem — and two
landed plans explicitly forbid the obvious remedy (§3 below).

Where the hour actually goes — three measured candidates, in order of size:

1. **Gate-red retry loops. 38% of land attempts exit 6** (67 of 175 attempts since the `red`
   attribution field landed 2026-08-08T20:56; 18–45%/day across the 7d window). Each exit-6 is a
   *failed* land the agent must diagnose and re-run — a multi-minute agent turn each — and the loop is
   invisible to `wait_s` because an exit-6 land **never takes the lock**. Attributed causes since the
   field exists: `shellcheck` 17 · `dead-assertion` 11 · `shellcheck,dead-assertion` 7 ·
   `bats-shellcheck` 5 · `hermeticity` 5 · `shellcheck,hermeticity` 5 · named smoke suites ~12.
2. **The verifier lane, which IS hours-scale and IS breaching today.** `scripts/cycle-time-census.sh
   --all`, run this session: `verdict=BREACH` — scheduled lane `run_s` **p50 3.13h, p90 3.32h**, 57
   completed runs, **32/57 (56%) censored at the 10,800s suite bound**, so p50 is a floor.
   `DEPLOY_LANE_GROUND_UP.md` §1.5 records R2's "trunk red bounded to ≤1 verifier cycle" as
   **not achieved (trunk red 65.6h)**.
3. **Reconcile the counting.** 582 commits reached `origin/main` in 7d but only **357 successful
   ship-land runs** (`exit:0` attestation rows) — ≈1.6 commits per land event. The brief's "562
   lands/7d" is a *commit* count; per-land latency targets apply to ~357 events. This is the same
   error the corpus already caught once: `LAND_PIPELINE_V2.md:196` — *"My earlier 43/day was commits."*

---

## 1. DECISION LEDGER

Legend — **BUILT** = named mechanism found in `scripts/`/`hooks/`/`bin/`/`.claude/` and verified ·
**PROSE-ONLY** = named in a doc, no in-tree implementation · **BUILT-FORBIDDEN** = code exists and is
deliberately unlandable.

### 1.1 LAND_PIPELINE_V2.md (`status: complete`, landed `8d50f953` 2026-07-28, 25 commits)

| # | Decision (frozen) | Where | Implemented? | Superseded by |
|---|---|---|---|---|
| D1 | **The inversion**: the full corpus may never run per-land. It runs once, post-land, batched, background QoS, by one singleton; **deploy (not land) waits for the full-suite verdict**; a red trunk auto-reverts | §1:129-134 | **BUILT** — `ship-land.sh:978-982` structurally refuses bats under the lock in both lanes; `postland-verify.sh` is the singleton | — |
| D2 | **Nothing heavy may EVER enter the land-lock** (structural, not policy) | §4.1:354-356; `ship-land.sh:560-563` | **BUILT** — `IN_LAND_LOCK=1` ⇒ statics+ratchets only (`ship-land.sh:981-982`; v1 lane `:1993-1996`); test-enforced at `land-gate-cas.bats:214,259` and `ship-land.bats:1678` | — |
| D3 | **Shedding is SKIP, never wait** (R7 — the fail-closed-degradation-as-amplifier law) | §1 R7:165-167; §4.1:346-348 | **BUILT** — shed predicate on `CC_GATE_MAX_LOAD`; `gate_admit` deleted from the land path (survives only in `capacity-admit.sh`, `cc-bats`, `handoff-fire.sh` — non-land callers) | **EXTENDED** by DEPLOY_LANE_GROUND_UP §1.5: *"R7 covers cost, not futility. A fail-closed path must escalate on repetition, not merely refuse."* |
| D4 | Land gate = O(diff) statics + ratchets + **`--direct`-suite smoke under ONE total wall budget `SHIP_LAND_SMOKE_BUDGET_S=120`**; smoke RED blocks (exit 6), smoke CUT proceeds | §4.1:343-351 | **BUILT and correct** — `ship-land.sh:1022-1025` (non-integer ⇒ 120, *"never unbounded"*), deadline re-checked per suite `:1033`, bound recomputed per call from the shared absolute deadline `:861-865` with `timeout -k 10` **outermost so it owns the process group** | — |
| D5 | `stamp_gate_green` removed from the land path; `GATE_EFFECTIVE_FULL=0` **always** — the verifier is the sole writer of gate-green | §4.1:356-358 | **BUILT** — pinned by `ship-land.bats:422` | — |
| D6 | **Corpus partition**: host-coupled suites leave the tree verdict and run post-deploy against the live layer | §4.2; §5:565 | **BUILT** — `scripts/host-suites.manifest`, read by `postland-verify.sh`, `ship-land.sh`, `deploy-live.sh`, `gate-select.sh`, `deploy-parity-assert.sh` | **NARROWED 2026-08-08** (§2:224-235): the manifest is **3 of 331** suites, not 6. Five were de-listed after an empty-`HOME` re-measurement passed them at full count (8/8, 9/9, 3/3, 23/23, 108/108); only `deploy-parity-live` truly asserts the live layer |
| D7 | The **smoke must also exclude host-manifest suites** — the partition binds the land lane too | §4.1 DESIGN ADDITION:723-729 | **BUILT** — fastlane's final integration commit | — |
| D8 | Autonomous deploy **only** to a stamped-green tree (R3), plus post-deploy host checks and one-command activation | §4.3:519-542 | **BUILT** — `deploy-live.sh --auto`; `com.claude.deploy-live` loaded (`runs = 117`, **last exit code = 1**); `14-land-pipeline-v2-activate.sh.done` present in the live queue | **R3 DISCARDED AS STATED** — DEPLOY_LANE_GROUND_UP §1.5 |
| D9 | **R9 absence-is-loud**: verifier-freshness + deploy-lag alarms | §4.4:543-551 | **BUILT** — `bin/cc-blockers` kinds `verifier-inert` / `trunk-red` / `deploy-stale` (`:21-50`) | **"KEEP the requirement, DISCARD the claim it was met"** — DEPLOY_LANE_GROUND_UP §1.5 |
| D10 | Kill switches are **env, not reverts** (`SHIP_LAND_LANE=v1` · `POSTLAND_AUTOREVERT=off` · `POSTLAND_VERIFY=off` · plist unload) — *"a revert needs the pipeline"* | §6:603-605 | **BUILT** — all present in `ship-land.sh` / `postland-verify.sh` / `.claude/commands/ship.md` | — |
| D11 | **C29 cross-window corroboration**: the retry ladder's 3 runs are ONE observation; corroboration must key on elapsed **TIME**, never on "a lower load" — on a box whose steady state is 20-40 sessions a quiet window may never arrive, so a load-keyed gate *"could convict but never exonerate"* | §4.2.7:438-518; Learnings:768-797 | **BUILT** — dispatched session, branch `wt-4ac16c22d6ba` | — |

### 1.2 SHIP_LAND_HARDENING_PLAN.md (2026-07-11, COMPLETE, dogfood-landed `553c0df`…`9bdb31e`)

| # | Decision | Where | Implemented? |
|---|---|---|---|
| H1 | **Machine-wide mutex per repo**, keyed on the **shared git dir** so every worktree of one repo collides on ONE lock (G-P9-1) | T1a:55-58; `land-lock.sh:11-19` | **BUILT** — `land-lock.sh:41-48`, `--git-common-dir` + worktree-suffix normalization. *(The evidence-pack's F16 "keyed per-worktree, NOT BUILT" is **stale** — corrected at LAND_PIPELINE_V2 §2:287-290, with 0 same-minute lands in 180 as corroboration.)* |
| H2 | **A LIVE holder pid is NEVER reaped, even past TTL** — deliberate divergence from reso: *"a silently-dropped commit costs more than a wedged-lock wait"* | Status log:122-125; `land-lock.sh:92-95` | **BUILT** — `try_acquire()` reaps only a dead pid or an lstart mismatch (pid reuse) |
| H3 | **Verify landings by CONTENT, never by count** | T2b:73-76 | **BUILT** — `scripts/land-verify.sh`, in-lock post-push |
| H4 | Stranded-sweep exit 1 is a **REVIEW verdict**, never auto-recover; never cherry-pick a peer's WIP onto trunk | Dogfood finding:141-147 | **BUILT** — `stranded-sweep.sh` (+ `--mine <sid>`) |
| H5 | Escape hatch is `LAND_SERIALIZE=off` | `land-lock.sh:30` | **BUILT** — and `.claude/commands/ship.md:110` counter-instructs: **"Never set `LAND_SERIALIZE=off`"** |

Carried verbatim into LAND_PIPELINE_V2 §4.1 (§9:711-712). **These four safety rails are the one part of
the stack no later plan reopens.**

### 1.3 land-gate-serialization-2026-07-25.md (LANDED `190c839`; partially superseded)

| # | Decision | Where | Status |
|---|---|---|---|
| S1 | **Optimistic CAS landing**: the GATE proves the FINAL rebased tree; the LOCK covers ONLY fetch-compare → push → content-verify. Stale ⇒ exit 42, release, re-rebase, re-gate unlocked | §Chosen design:31-52 | **BUILT and still current** — `.claude/commands/ship.md:97` calls the 2026-07-25 invariant *"survives v2 intact"* |
| S2 | Rounds-exhausted fallback = full gate **inside** the lock | :48-52 | **DELETED by v2** — *"its premise is gone; nothing heavy may ever enter the lock"* (§4.1:354-356). This fallback is what produced the 3h36m holders |
| S3 | REJECTED — **B, changed-file-scoped gate**: *"unsound here (tests read docs; semantic coupling is unmapped); any conservative map degenerates to 'run everything'"* | :88-91 | Stands |
| S4 | REJECTED — **C, `bats --jobs`**: GNU parallel absent on this box; ~113 suites unaudited for parallel-safety | :92-97 | Stands; noted as stackable later behind an opt-in env after an audit |
| S5 | REJECTED — **D, two-phase lock (intent lock for push only)** | :98-100 | **Stands — the corpus's closest engagement with a delegated-writer shape** (quoted in full at §3.2) |

### 1.4 LANDING_GATE_ROOT_CAUSE_2026-07-26.md

| # | Decision | Where | Status |
|---|---|---|---|
| L1 | The failure is a **three-part loop**, not one root cause: `added ⇒ FULL` routes 85% of failing lands into a 20–53 min FULL gate → peers SIGTERM/SIGKILL it → `9c5d0ba74e79` launders the cut as RED → the session is told to "clear the sibling gates and land now" → back to the killing | Reconciliation verdict:169-178 | Keystone **LANDED**; the whole loop is dissolved by v2 (no corpus on the land path) |
| L2 | **Quote the era, never the lifetime number** — `gate_scope`/`selected_n` did not exist before `d1c5219` (2026-07-25 16:40); all-time reads give 26–35%, in-era 76–85% | :41-50 | Binding methodological decision. *Applies directly today: the `red` field first appears 2026-08-08T20:56, so absent exit-6 attribution before that date is the instrument's birthday, not a defect* |
| L3 | A blind Fable-5 panelist, given only the system model and raw telemetry, independently derived `added ⇒ FULL` as its dominant strand-producer and nominated the same smallest change | :185-190 | Recorded — *"convergence from an unanchored derivation is the strongest evidence in this document"* |

### 1.5 POSTLAND-CELL-BISECT-2026-07-29.md

| # | Decision | Where | Status |
|---|---|---|---|
| P1 | The reused ci-postland cell was **NOT** the 0-green cause — one-variable isolation, fresh vs reused, **155 ok / 0 not-ok** across C1/C2/D1; the single not-ok isolated to **`deploy-parity` alone** by a same-minute control | §VERDICT:6; :31-94 | **BUILT** (fresh worktree per run); this finding is what re-attributed D6 |
| P2 | The real 0-green cause was re-corrected twice: a whole-tree lint whose pure predicates ran a bare `grep -q`, so **rc=2 (grep could not RUN — fork exhaustion at load 15-48) was indistinguishable from rc=1 (no match)** — one transient fork failure FABRICATED a leak about a clean tree | LAND_PIPELINE_V2 §2:247-262 | **BUILT** — `afaf40de` (rc≥2 ⇒ NON-VERDICT) + `ed4e6c6a` (retry the pure predicates 3×), RED-proved by replaying the pre-fix artifact at `afaf40de~1` |
| P3 | The same conflation one layer out: `prelint_check` mapped every non-zero non-124 rc to FAILING ⇒ RED ⇒ `red_actions` ⇒ **could auto-revert a commit never shown to be at fault** (AUTOREVERT defaults on) | §2:263-269 | **BUILT** — only rc=1 is RED; 2/124/126/127/137 ⇒ `PRELINT_UNPROVEN` ⇒ CUT ⇒ the CUT_MAX page ladder |

### 1.6 DEPLOY_DECOUPLING_V2.md (`status: complete`, pattern record — reso's second implementation)

| # | Decision | Where | Transfers here? |
|---|---|---|---|
| C1 | **Axis 2 — the integration trunk is not the deploy trigger.** *"If landing spends money, landing becomes rare — and every pathology of a shared trunk follows from that, not from git"* | §1:9-10, 36-57 | **NO, deliberately** — §4:124: *"claude-infrastructure's 'deploy' is a symlink refresh — near-free — so axis 2 buys it little"* |
| C2 | **A scheduling decision is a timeout decision** — deprioritising a process implicitly re-specifies every wall-clock timeout inside it; the caller choosing the band must choose the budget, widen-only | §3:91-110 | **YES, universally.** Exposure measured not assumed: /Users/chrisren/.claude/bin/cc-bats has no per-test deadline so the framework-level bug cannot occur, but **16 of 269 `tests/*.bats` hardcode a `timeout N`, shortest 2-3s** |
| C3 | **A fail-closed verdict that discards its evidence is a wedge, not a verdict.** *"No-verdict says 'unknown'; evidence-free-RED says 'guilty' and destroys the appeal"* | §3:112-116 | **YES, universally** — audit every stamp emitter for a discarded subprocess output |
| C4 | Assert **every** trigger of an invariant from the live API; *"a setting someone can flip back is not an invariant, it is a hope"*; unreadable is UNKNOWN, never assumed-safe; verify the alarm as a live positive control | §2:61-88 | YES — already the shape of `deploy-parity` + the launchctl self-verify |
| C5 | **Deploy cadence stays a values call, not an architecture one** — reso rejected auto-deploy-on-green; this repo auto-deploys | §4:128-133 | Repo-specific, settled |

### 1.7 DEPLOY_GATE_CONVERGENCE.md (CLOSED 2026-08-08)

| # | Decision | Where | Status |
|---|---|---|---|
| G1 | The title (*"the deploy gate cannot converge"*) is **refuted by observation, not by argument** — the lane advanced mid-session `7bb7526e81b2 → 14711d73c3db`, then reported lag 0 | §8:288-295 | Closed |
| G2 | **§7.5's own fix was necessary and NOT sufficient.** The retry-ladder fix alone left the lane waiting at **3 greens in 97 stamps (3.1%)**. What closed the gate is **D1's two-tier target from DEPLOY_LANE_GROUND_UP §2.2** — degrade to the newest NOT-RED commit past 25 commits / 6h. *"Green left the critical path."* And: *"a reader who credits this doc's own fix with the convergence would draw the wrong lesson about which change to protect"* | §8.1:296-314 | **Load-bearing attribution — do not re-credit** |
| G3 | REJECTED — raising the corpus QoS band, on the premise of *"foregrounding a 233-suite corpus"* | §5:95 | **PREMISE REFUTED** by LAND_PIPELINE_V2 §8's revisit: `utility` is not foreground, it is still demoted below interactive; band tax measured **2.26×**. Filed `70dff02dcf4a`, **not fired** |
| G4 | `LAG_HOURS` is integer-truncated, so the 6h budget behaves as **≥7h**. *"Not a defect; the bound is simply one hour wider than the constant reads"* | §8.4:334-347 | Recorded so it is not re-found |
| G5 | Residual: `tests/boot-resume-launch.bats` red in 3 of the last 5 stamps, **zero `flakes.jsonl` rows** (never ladder-acquitted), **passes 10/10 standalone**. *"Named here, not fixed"* | §8.3:326-333 | **OPEN, owned elsewhere** |
| G6 | A hypothesis tested and **REJECTED** so the next reader does not re-derive it: the `cc-blockers` `deploy-stale` alarm firing while `deploy-live` is still inside its trip test is **not** two surfaces disagreeing on a threshold — both read the same constants; the gap is one tick wide and is G4's truncation | §8.4 | Recorded per `wrong-cause-corroborated-by-true-metric` |

### 1.8 DEPLOY_LANE_GROUND_UP.md (`status: complete`, 2026-08-07) — the audit of v2's own requirements

**This is the only post-2026-07-28 document that grades LAND_PIPELINE_V2's frozen criteria.** Verdicts
verbatim from §1.5:

| R | Verdict |
|---|---|
| **R3** live layer only advances to a full-suite-green tree | **DISCARD AS STATED.** *"R3 is a safety property with no liveness partner — **a property satisfied by never advancing is not an advance invariant.** In 10 days `deploy.log` records exactly **one** autonomous advance."* |
| **R9** absence is loud | **KEEP the requirement, DISCARD the claim it was met.** *"R9 was implemented per-fault; the failing state is the gap between faults."* |
| **R7** shed = skip | **EXTEND** — *"R7 covers cost, not futility. A fail-closed path must escalate on repetition, not merely refuse."* (534 refusals at one unchanged state, zero escalation) |
| **R6** a non-verdict is never a red | **KEEP** — `is_green()` conflated red/cut/hung |
| **R5** bounds cover what they bound | **KEEP, strengthen** — the 0-green half's proximate cause was a bound scoring itself (`833dcf35`) |
| **R1** land p50 ≤ 30s at 12+ writers | **KEEP, and state the coupling — "R1's success is R3's problem"**: *"Fast landing is what makes trunk outrun the verifier."* |
| **R2** trunk red bounded to ≤1 verifier cycle | **NOT ACHIEVED — trunk red 65.6h** |

> **The missing row** (§1.5, verbatim): *"`LAND_PIPELINE_V2.md:438-456` maps 16 observed v1 modes to v2
> answers. **There is no row for 'the green cursor is behind live HEAD.'** Its §3 architecture diagram
> draws exactly **one** arrow into the checkout — the second advance path is nowhere in the design."*
> And: *"`755dd24a`'s own suite already carried `@test "refuses to roll back: newest green is BEHIND the
> live HEAD"` (2026-07-25). **The case was anticipated as a refusal and never as a state to escalate
> from.** That single sentence is the class."*

Its own §2.7 REJECTED ALTERNATIVES — *"recorded so they are not relitigated"*:

| | Alternative | Why rejected |
|---|---|---|
| R-A | Make the verifier fast enough to gate per-commit | 2h28m median over 297 suites. *"Even a 10× speedup leaves ~1.6 verdicts/hour against ~2.6 commits/hour. The rate gap is structural, not a tuning problem — the same conclusion `LAND_PIPELINE_V2` reached for the **land** path and then failed to carry over to the **deploy** path."* |
| R-B | Re-add load/admission control so runs stop being killed | **"Forbidden."** Deleted deliberately (`postland-verify.sh:975`, §4.2.3/R7) and **its absence is asserted by a structural test at `:1825-1830`** |
| R-C | Widen `SCAN_N` past 200 | Changes which refusal prints, not whether it recovers. *"Treating a message change as progress is how this survived five filings."* |
| R-D | Auto-`--force` when lag exceeds the budget | *"Launders an unverified deploy through automation and takes the operator's documented escape hatch away from them."* `--auto` is non-interactive by construction; D2 pages instead |
| R-E | Wait for the corpus to go green | Refuted on measurement, not preference: **1 green / 44 red over 7 days**, `flakes=0` at `retries=10-22` (hard reds, not machine noise), and the auto-revert net now reports `skipped` and `FAILED(step=revert rc=90)` |

### 1.9 inertness-generator-2026-08-07.md — and the one RECORDED DOC-VS-DOC DISAGREEMENT

The generator's §3 law, verbatim (`ad847c01`):

> *"Reverse the polarity of every edge on the conclusion→behaviour path: no affirmative-permission gate
> may hold an advance; all safety is expressed as veto-after — the revert of a named land."*

`DEPLOY_LANE_GROUND_UP.md` §2.6d **records a durable divergence rather than adopting it** — the only
explicit doc-vs-doc contradiction in this corpus, and it opens by correcting the citation
(*"That citation is one commit stale"* — `2aeb23a7` was D1's first draft; `9055ef2e` revised it):

> *"**Where we agree:** past the staleness budget, exactly — advance on not-red. **Where we differ:**
> inside the budget, where T1 prefers a green when one exists."*

Two measured objections, *"offered as narrowing rather than refutation"*:

1. > *"**Unboundedness is the defect, not permission-polarity as such.** … a gate with a finite escape —
   > T2 fires past budget with banner + page — cannot rot into a standing state. The narrowed law *'no
   > permission gate may be **unbounded**'* is also checkable in a way the absolute form is not."*
2. > *"**Pure-veto moves all safety onto a mechanism measured failing.** … **AUTOREVERT `landed`=3,
   > `FAILED`=5, `skipped`=17 — 12% success across 25 attempts.**"* Corrected same-day
   > (`8e8a306f6dc0`): the 17 skips are **four** culprits, not one — *"the fixed point is not one
   > unlucky sha but the marker's shape, reproduced independently four times."* Split remedy landed in
   > `postland-verify.sh` (C26): a landed revert stays permanent but now **pages** instead of skipping
   > silently; one that never landed re-arms on a moved tip or `POSTLAND_REVERT_RETRY_DECAY_S`.

Also from the generator, binding on any landing conclusion (§3, §10): **trunk is not an enforcing
store.** Measured 2026-08-07 — the shared checkout sat **104 commits** behind `origin/main`
(75 on 07-31 → 85 → 104, *"accelerating"*), `deploy-live` `last exit code = 1`, log 708 lines with
**545 identical `REFUSED` lines**. Eight correct analyses landed and changed nothing. Its item 5 is
pointed straight at this ledger's subject: *"GROUND_UP row 1: 'DONE 2026-07-28 … 9 lands; exemplar' —
Confirmed verbatim, **and that exact subsystem is the one wedged in item 2**."*

---

## 2. IMPLEMENTED vs PROSE-ONLY — the grep sweep

Every mechanism the plans name by identifier, checked against `scripts/ hooks/ bin/ .claude/`:

| Named mechanism | Verdict |
|---|---|
| `SHIP_LAND_SMOKE_BUDGET_S` · `SHIP_LAND_LANE` · `GATE_EFFECTIVE_FULL` · `IN_LAND_LOCK` · `stamp_gate_green` | **BUILT** — `scripts/ship-land.sh` (documented in `.claude/commands/ship.md`) |
| `POSTLAND_AUTOREVERT` · `POSTLAND_VERIFY` | **BUILT** — `scripts/postland-verify.sh` |
| `scripts/host-suites.manifest` | **BUILT** — 6 consumers |
| `scripts/cycle-time-census.sh` + `tests/cycle-time-census.bats` | **BUILT** — runs; `verdict=BREACH` today |
| `land-lock.sh` shared-git-dir keying · pid+lstart reap · `--print-lock-dir` | **BUILT** |
| `launchd/com.claude.{postland-verify,deploy-live}.plist` | **BUILT + LOADED** — `runs = 105` / `runs = 117` |
| `14-land-pipeline-v2-activate.sh` (the one C10 hand-step) | **BUILT + RUN** — `.done` marker present in the live queue |
| `cc-blockers` alarms `verifier-inert` / `trunk-red` / `deploy-stale` | **BUILT** — `bin/cc-blockers:21-50` |
| `gate_admit` on the **land** path | **CORRECTLY ABSENT** — survives only in `capacity-admit.sh`, `bin/cc-bats`, `handoff-fire.sh` |
| `refs/proposals/gate-slot-semaphore` (the concurrency cap) | **BUILT-FORBIDDEN** — §3.3 |
| **Enforcement gap, recorded NOT closed**: the prelint invokes `./scripts/<lint>.sh tests`, never `--selftest`, so the 17 ratchet-RED-proof cases *"run nowhere automatically today"*; `com.claude.nightly-regression` is staged in `~/Library/LaunchAgents` but **NOT loaded** | **PROSE-ONLY remedy** — three candidates filed as backlog `76644e76aaae`, deliberately not picked. Note the exit-2 fix (P3) is a **prerequisite** for the first: before it, adding `--selftest` to `PRELINTS` would have made a fork-starved selftest auto-revert trunk |

**No plan-named mechanism in this corpus was found spec-only-never-built.** The single genuine
prose-only item is the *remedy* for the prelint-selftest gap, and the plan says so in terms.

---

## 3. QUESTION (c) — WAS AN ASYNC / QUEUED / SINGLE-WRITER / DELEGATED LANDING ARCHITECTURE EVER EVALUATED?

**Answer: YES — four distinct forms were evaluated and all four REJECTED; one of them was fully built,
tested, and is explicitly forbidden from landing. None was "never considered."**

### 3.1 Speculative merge-queue (batching — Zuul/bors) — REJECTED, LAND_PIPELINE_V2 §8:618-620

> *"**Speculative merge-queue (Zuul/bors batching)**: solves throughput but keeps latency ≥ corpus-time
> (fails R1) and keeps N-corpora concurrency (fails the load reality). Post-land + revert dominates on a
> single box with a trusted-author fleet."*

⚠️ **Note the rejection ground is corpus-bound latency — and v2 then removed the corpus from the land
path, so the stated reason has decayed.** So has the motive: the queue existed to serialize a corpus
that no longer runs there. Flagged because `work-item-remedy-can-become-forbidden` is a live trap here.

### 3.2 Two-phase / intent lock — a delegated push-only writer — REJECTED, land-gate-serialization §D:98-100

> *"**D — two-phase lock (intent lock for push only):** the rebase must sit in the same critical section
> as the push or the 2026-07-11 race reopens; with the CAS design the 'rebase' inside the lock is the
> degenerate check *that no rebase is needed* — same effect, no second lock."*

This is the corpus's most direct engagement with a single-writer / delegated-landing shape, and it is
rejected on a **correctness** ground (the `dfacccd` rebase-drop race), not a performance one. That
ground is durable — unlike §3.1's, it does not decay with the corpus.

### 3.3 A counting semaphore over concurrent gates (the queue) — **BUILT, TESTED, AND FORBIDDEN**

The single most important entry in this ledger. `refs/proposals/gate-slot-semaphore` = **`3d052701`**
(*"fix(ship-land): cut-twice is exit 9, and the gate takes an admission slot"*, 2026-07-26). Verified
this session: the ref exists, is reachable from **no branch head** (only from `wt-f8e40b4c577d`), and
carries 602 insertions over 5 files including **231 lines of tests**. It adds `gate_slot_acquire` — a
machine-wide **counting semaphore keyed on the same shared git dir as `land-lock`**, capping concurrent
gates at `SHIP_LAND_GATE_SLOTS` (default `cores/3`, floor 2 = **3 slots** on this 10-core box), the slot
held only across the unlocked gate, fail-open after `SHIP_LAND_GATE_SLOT_WAIT` (**2,700s**), with
`gate_wait_s`/`gate_slot` telemetry and a `SHIP_LAND_GATE_SLOTS=0` kill switch.

`land-gate-serialization-2026-07-25.md` § *"The cap WAS built, and it must NOT be landed"* (:297-332).
**Content-verified on trunk this session** (`git show origin/main:… | grep -c 'must NOT be landed'` = 1),
so this is landed policy, not a worktree opinion:

> *"The remedy this item asked for exists as finished, tested code. **Do not land it, and do not rebuild
> it.**"*

Three reasons, verbatim:

1. > *"**It would queue 45 minutes to protect 29 seconds.** The thing being admitted is no longer a 20-53
   > min corpus; it is statics + ratchets + a shed-able ≤120 s smoke — measured at **29 s** above. A
   > 3-slot gate with a 2700 s wait bound is a queue whose wait dwarfs its work by ~90×."*
2. > *"**Fail-open makes it buy latency, not protection.** After 2700 s the land 'proceeds unadmitted' —
   > so under exactly the sustained contention it exists for, it *still* does the uncapped thing, having
   > first spent 45 minutes. That is verbatim the critique that killed `gate_admit`: every waiter that
   > finally timed out ran the corpus anyway."*
3. > *"**It re-introduces a WAIT into the land path**, which R7 forbids outright."*

And the reusable distinction, stated as a decision:

> *"Note the mechanism critique does *not* transfer: a **count**-keyed semaphore has none of
> `gate_admit`'s self-starvation feedback (slots are directly controlled; loadavg is a noisy signal the
> waiters' own subjects produce, and is not even session-attributable). Had the corpus stayed on the
> land path, this would have been the *correct* fix and strictly better than the load-keyed shed. **It
> loses on subject size, not on mechanism** — record that distinction, because the reasoning is reusable
> if a corpus ever returns to the land."*

Its backlog item `6767ec9bb425` (*"gate admission bounds LOAD but not CONCURRENCY — N landers can all
observe load < ceiling and start together"*) is **closed with that section as evidence**, and the closure
concedes the observation was right: *"The observation was **exactly right**: the shed is a per-lander
predicate and genuinely does not cap the herd. What removed the risk is that the herd's per-member cost
collapsed to seconds — not that the herd got capped."*

### 3.4 Async verification — the one async architecture that WAS accepted, and it shipped

The asynchronous decision in this corpus is about the **verdict**, not the land: LAND_PIPELINE_V2 §1's
inversion moved the full-suite claim off the synchronous land path onto a singleton background verifier,
with deploy as the enforcement point and auto-revert as the net (§1:129-134). That is D1, and it is
built. Precedent cited: *"post-land CI + revert culture + deployment gating on green (Chromium
sheriff/TreeCloser, Google TAP), vs pre-land full verification which caps throughput at corpus-time and
was abandoned everywhere volume grew"* (§1:136-138).

**Adjacent rejections that constrain any re-proposal:**

- **Off-box CI (GitHub Actions)** — *"the corpus asserts THIS host (launchd, iTerm2, live `~/.claude`,
  BSD userland); a macOS runner proves a different machine. Rejected for the verdict; optionable later
  for the pure-hermetic subset as a second opinion"* (§8:621-623). **Re-opened** by DEPLOY_LANE_GROUND_UP
  §1.5 — *"a hermetic-subset second opinion is a green producer the design currently lacks."*
- **Second verification host** — §8's REVISIT was **performed 2026-08-08** (backlog `343d7cc392b6`) and
  the verdict is **still no**, on a *new* ground the original bullet did not contain: *"**A second Mac
  cannot produce a valid verdict for this corpus — the bullet two above says so.** Off-box CI is rejected
  here because *'the corpus asserts THIS host … a macOS runner proves a different machine.'* **That
  reason applies verbatim to a second Mac. These two entries contradict each other and always did.**"*
  Plus five deep single-machine couplings: *"the mutex is a local pid (`kill -0`), the stamp key is the
  bare tree sha with no host identity and last-writer-wins, work selection has no lease, and auto-revert
  **pushes to origin/main on a single verdict**. It is a protocol rebuild, not a purchase."* Also
  measured there: the lane is **not queue-bound — duty cycle 61.1%, it idles 39% of the time.**
- **Content-addressed proof cache** (old Phase 2b) — *"Superseded — do not build"* (§8:624-626); the
  tree-keyed STAMP is the only cache needed, one writer one reader.
- **Raising the admit ceiling / more retries / bigger budgets** — *"parameter motion inside the broken
  frame; every such knob either waits (starves) or runs-anyway (amplifies). R7 forbids the class"*
  (§8:627-629). Reinforced in Learnings:789-792 — *"the fix had to be an evidence axis, not a parameter
  — 'more retries' is explicitly a rejected class (§8) and would have been the obvious wrong move."*

### 3.5 The one shape genuinely NEVER considered

**A landing broker/daemon** — a service that accepts a patch and lands it on the author's behalf
out-of-band, so no session ever holds the mutex. §3.2 is the nearest neighbour and rejects only the
*lock topology*, not the service shape. But it is not a free option: §3.4's five single-machine
couplings (no host identity in the stamp key, no lease on work selection, last-writer-wins, a local-pid
mutex, single-verdict auto-revert to origin/main) are precisely the properties such a broker would have
to build first — so by the corpus's own argument it is *"a protocol rebuild, not a purchase."* And it
would be aimed at a lock measured at **0.7–4.8% utilization**.

---

## 4. QUESTION (d) — CONGESTION-RELEVANT OPEN/PARKED ITEMS, AND POST-2026-07-28 VERIFICATION

### 4.1 Open / parked, congestion-relevant

| Item | Where | State |
|---|---|---|
| **`70dff02dcf4a` — the corpus QoS band.** Two levers, **neither hardware**: corpus band `background`→`utility` (**2.26× measured**: `tests/cc-classify.bats` 51s/37s vs 103s/96s, interleaved at load 18-22; controls — pure `sleep 20` band-immune, pure CPU 5-6×) and the launchd envelope (`ProcessType Background` + `Nice 10` + `LowPriorityIO` — the **3.19×** scheduled/session gap the census re-confirmed live this session). *"even conservatively applied this brings the lane under 2h for $0"* | LAND_PIPELINE_V2 §8:675-691 | **FILED, NOT FIRED** — the band reverses a documented deliberate choice (`postland-verify.sh:285-297`, *"the verifier may never be the thing that waits"*) and the launchd half is C10 (plist edit + operator bootout; `launchd-parity-lint` reds the fleet on a repo-only plist edit) |
| **§8 cycle-time revisit trigger (>2h sustained)** | LAND_PIPELINE_V2 §8:630-700 | **OPEN TODAY** — `cycle-time-census.sh --all` this session: `verdict=BREACH`, scheduled p50 3.13h / p90 3.32h, 56% censored. *"it fired around 2026-07-30 and nothing noticed for nine days"* |
| **`76644e76aaae` — prelint `--selftest` never runs automatically**; `com.claude.nightly-regression` staged but not loaded | LAND_PIPELINE_V2 §2:270-281 | **OPEN** — three remedies trade off differently and change the corpus partition; deliberately not picked unilaterally |
| **`6767ec9bb425` — admission bounds LOAD but not CONCURRENCY** | land-gate-serialization:327-332 | **CLOSED**, with an explicit reopen condition: *"Should a corpus ever return to a land, reopen that item and start from `3d052701` rather than from scratch."* |
| **Off-box CI, hermetic subset** — *"a green producer the design currently lacks"* | DEPLOY_LANE_GROUND_UP §1.5 | **RE-OPENED, not re-decided** |
| **R2 not achieved** — trunk red 65.6h vs "≤1 verifier cycle" | DEPLOY_LANE_GROUND_UP §1.5 | **OPEN** |
| **`tests/boot-resume-launch.bats`** — red in 3 of last 5 stamps, 0 flake rows, 10/10 standalone | DEPLOY_GATE_CONVERGENCE §8.3 | **OPEN, owned elsewhere** — *"the lane no longer depends on it (T2 routes around red)"* |
| **16 of 269 `tests/*.bats` hardcode `timeout N`, shortest 2-3s**, inside a background-clamped loaded box | DEPLOY_DECOUPLING_V2 §4; LAND_PIPELINE_V2 Learnings:878-887 | **RECORDED, not rewritten** (Fix Observed Problems) — *"where to look first if a verifier RED ever lands with no assertion failure in its output"* |
| **Auto-revert at 12% success** (3 landed / 5 FAILED / 17 skipped of 25) — the net that is supposed to bound trunk-red | DEPLOY_LANE_GROUND_UP §2.6d | Partly fixed (C26); 12% is the measured live number |
| **`gate-home-isolation` corpus-only red** — 22/22 standalone at trunk, so *"a band/contention property, not a suite bug"*. *"This change makes it visible; it does not make it green."* | LAND_PIPELINE_V2 Learnings:826-829 | **OPEN, explicitly stated-as-not-fixed** |

### 4.2 Was v2's own §7 acceptance verified after 2026-07-28?

**Partially — and never consolidated against §7's five bullets. Scorecard:**

| §7 criterion | Verified? |
|---|---|
| *"land.log over the first 20 v2 lands: p50 ≤ 30s, p99 ≤ 3 min, wait_s ≈ 0, zero exit-9"* | **NEVER VERIFIED AS WRITTEN — and structurally unverifiable from the nominated artifact.** `land.log` records **no end-to-end land duration**: only `wait_s`/`hold_s` (lock-scoped) and `smoke_s`. Yet `.claude/commands/ship.md:100` says *"This log is also the acceptance read for v2's latency target (p50 ≤ 30s, p99 ≤ 3 min, `wait_s` ≈ 0) — measure it, do not narrate it."* **The field it instructs you to measure does not exist.** Adjacent evidence that does exist: a real land's full fast-lane gate completed **GREEN in 29s at 1-min load 56.75** — *"the item's own failure condition at 3× that load, completing in under half a minute"* (land-gate-serialization § Verified 2026-07-30); `wait_s ≈ 0` holds (p50 0, p90 77s); **`exit 9` in the last 7d: 0** ✓ |
| *"≥1 GREEN stamp exists; gate-green == stamped tip; stamp age alarm silent"* | **YES** — the first green in the system's history was minted post-bootstrap; DEPLOY_GATE_CONVERGENCE §8.1 records a 2026-08-08T00:47Z green *"minted at loadavg 19.43 after 4 retries — the ladder rendering a verdict under exactly the pressure that used to force the `cut` path."* But the green **rate** is 3/97 stamps (3.1%) |
| *"Deployed HEAD advanced autonomously to a stamped sha… a brand-new file landed in the window has a live symlink"* | **YES for one advance** (DEPLOY_GATE_CONVERGENCE §8, lag 0 observed live, 3 advances total). **NO as a general claim** — inertness-generator measured the shared checkout **104 commits behind** with 545 `REFUSED` lines, and the corrected rule now in the global CLAUDE.md is that *a land that **ADDS** a file gets no budget* (`LIVE_ADDS` > 0 breaches at lag 1) — measured on `scripts/lib/pane-spawn-log.sh`, where the ledger read *"BEHIND 7, within budget (25)"* while all twenty instrumented call sites did nothing |
| *"One induced red (fixture branch) auto-reverts within a cycle with backlog + notify artifacts"* | **CONTRADICTED IN PRODUCTION** — 3 landed / 5 FAILED / 17 skipped over 25 encounters = **12%**. No induced-red fixture run is recorded anywhere in the corpus |
| *"Sustained: a 12-session day with continuous landing and zero operator interventions"* | **NOT VERIFIED.** The nearest read contradicts it for the deploy leg: *"In 10 days `deploy.log` records exactly one autonomous advance"* (DEPLOY_LANE_GROUND_UP §1.5) |

**The one systematic post-hoc audit is `DEPLOY_LANE_GROUND_UP.md` §1.5** — a *requirement*-level audit
(R1-R9), not an *acceptance*-level one (§7). Its finding is the sentence any new landing judgment must
start from:

> **"R1's success is R3's problem" — *"Fast landing is what makes trunk outrun the verifier."***

---

## 5. OPEN QUESTIONS (things this corpus does not answer)

1. **Where does the operator's 1h+ turn actually go?** Not the lock (0.7-4.8% utilization, wait p90 77s,
   zero starvation post-v2). The two candidates this ledger can size are the 38% exit-6 retry loop and
   the 3.13h verifier cycle — but **no instrument in the repo measures end-to-end land wall-clock**, so
   neither can be confirmed as *the* cause. Closing this needs one new field, not a new architecture.
2. **Why is the exit-6 rate 38%, and is it rising?** Daily: 31 · 45 · 18 · 26 · 42 · 32 · 39 · 44%. The
   dominant attributed causes are `shellcheck` and `dead-assertion` — i.e. **statics, not tests**. No doc
   in this corpus treats the gate-red rate as a first-class metric.
3. **33.8% of lands run NO suite at all** (`smoke:"skipped"` 185/548 in 7d; `"none"` 272 more). The
   script's own message calls this *"behaviorally UNGATED"* and notes *"the post-land verifier is the
   only remaining net and it trails trunk by hours."* Was that trade-off ever re-priced against a
   verifier now measured at p50 3.13h? Not in any document here.
4. **Does `SHIP_LAND_SMOKE_BUDGET_S` need a ceiling?** 34 lands in 7d exceeded the 120s budget (max
   **1,200s**) because sessions raised it themselves. The mechanism is correct; the *policy* of a
   caller-raisable unbounded budget on the land path is undiscussed.
5. **Is `deploy-live`'s `last exit code = 1` (117 runs) expected?** No doc states the normal terminal
   exit for a no-op tick.
6. **§3.1's rejection ground has decayed.** The merge-queue was rejected for "latency ≥ corpus-time" and
   the corpus left the land path two days later. Nothing re-derived whether the *conclusion* survives its
   *reason* — the exact `work-item-remedy-can-become-forbidden` shape §3.3 was written to catch.

---

## 6. ADVERSARIAL PASS — what I checked because a hostile reviewer would

1. **"Your land.log read is survivorship-biased — a session killed mid-wait logs nothing."** Real, and
   bounded three ways: (a) `land-lock.sh:129-134` logs an `exit 75` row **before** exiting when the full
   `LAND_LOCK_WAIT` elapses, and there are **0 post-v2** against 19 pre-v2; (b) the pre/post contrast
   uses the *same* instrument, so any bias is common-mode and cannot manufacture a 25× p90 drop; (c) row
   accounting is internally coherent — 548 attestation rows, 191 exit-6 (which never reach the lock), 79
   exit-42 re-rounds, 449 lock rows: 548−191+79 = 436 ≈ 449. The gap where an unlogged wait could hide is
   bounded at 3,600s per event and would have to leave no `exit 75` at all.
2. **"Maybe the operator means a different repo."** `land.log` is global (`~/.claude/land.log`) and
   carries **745 distinct repo basenames** across `Development/.worktrees`, `Development/_worktrees`,
   `/private/tmp`, `.worktrees/{fix,feat,chore,investigate}`. The measurement spans all of them.
3. **"Is there a second machine-wide serializer on the land path?"** Swept `lock.d` / `mkdir…lock` /
   `flock` across `scripts/` + `bin/`: 15 files, but the only one on the land path is `land-lock.sh`.
   `postland-verify.sh`'s `run.lock.d` is the verifier singleton (skip-not-queue); `cc-reaper`,
   `prune-backups`, `rotate-autonomy-logs`, `handoff-fire` etc. are unrelated lanes. `.claude/commands/
   ship.md` adds no serialization of its own — it invokes `ship-land.sh`.
4. **"The smoke budget is breached — `smoke_s` hit 1,200s against a 120s budget."** Investigated; **the
   implementation is not at fault.** `ship-land.sh:1022-1023` defaults to 120 and coerces a non-integer
   to 120 *"never unbounded"*; `:861-865` recomputes the bound per call from the shared absolute deadline
   with `timeout -k 10` **outermost so it owns the process group it kills**; `:874` scrubs the var for
   the child, so a raised budget can only come from the caller. Configuration, not defect — but a real
   latency source, and payable once per CAS round.
5. **"126 of 191 exit-6 rows carry no `red` attribution — that's a telemetry hole."** **Withdrawn on
   measurement.** The `red` field first appears at **2026-08-08T20:56:59Z**; since then attribution is
   **65 of 67 (97%)**. This is L2's own law (*"quote the era, never the lifetime number"*) applied to my
   own read — I nearly filed an instrument's birthday as a defect.
6. **"Does any 'decided' row cite a decision, or only a proposal?"** Every row cites a section of a doc
   whose frontmatter reads `status: complete` or that is verified present on `origin/main` via
   `git ls-tree`. The one row that is not a *plan* decision — §3.3's forbidding of `gate-slot-semaphore`
   — was content-verified on trunk (`git show origin/main:… | grep -c 'must NOT be landed'` = 1), so the
   prohibition is landed policy. Three rows are explicitly downgraded from "decided" to "asserted and
   later falsified": R3, R9, R2.
7. **The axis I nearly assumed irrelevant: the deploy/verify lane.** That is where the hours are
   (`verdict=BREACH`, p50 3.13h) and it is *causally downstream of the land lane's success* — R1 made
   trunk outrun the verifier. **A judgment scoped to "landing" that stops at the push will target the one
   part of this pipeline that already meets its number.**

---

## 7. THE THREE THINGS A NEW LANDING PLAN MUST NOT DO

1. **Must not propose a landing queue, concurrency cap, or admission control.** Built (`3d052701`),
   tested, forbidden by a doc verified on trunk, and forbidden again by R-B — which is enforced by a
   **structural test asserting the absence** (`postland-verify.sh:1825-1830`). Reopen only if a corpus
   returns to the land path, and then start from `3d052701`, not from scratch.
2. **Must not aim at the land lock.** 0.7–4.8% utilization, wait p90 77s, zero starvation events since
   the cutover, `hold_s` max 282s against a pre-v2 max of 6,771s. The 1h+ turn is the **38% exit-6 retry
   loop** (agent-side; never touches the lock) and the **3.13h verifier cycle** (breaching today).
3. **Must not assert a land is done at the push.** Trunk is not an enforcing store; a landed diff that
   **adds** a file is absent, not stale, so `LIVE_ADDS` > 0 breaches at a lag of 1; and the auto-revert
   net that is supposed to bound trunk-red runs at 12%.

**The one cheap lever nobody has pulled:** `70dff02dcf4a` — the corpus band (2.26× measured) plus the
launchd envelope (3.19×, re-confirmed live by the census this session). Filed, priced, **not fired**,
for two reasons that are both real and both surmountable: it reverses a documented deliberate choice,
and the launchd half is a C10 operator step.

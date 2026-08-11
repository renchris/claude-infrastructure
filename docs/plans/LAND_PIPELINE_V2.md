---
status: complete
---

# LAND PIPELINE V2 — first-principles landing architecture

**Scope (frozen):** design + implement the v2 landing architecture so any of 12+ concurrent
sessions lands a commit to origin/main in seconds-to-minutes, 24/7, with no multi-hour queues
or wedges: corpus-free fast land lane · singleton background trunk verifier (fresh worktree,
corpus partition, auto-revert) · autonomous green-cursor deploy with post-deploy host checks ·
activation consolidated to one operator command; tests green; landed via project /ship.

Status: DESIGN 2026-07-28 · owner session e891e080 · branch `land-pipeline-v2`

> **Audited at fleet scale 2026-08-10** — `docs/research/land-architecture-100p-2026-08-10.md`
> (10-lane wave, all evidence in its sibling dir). Verdict: this architecture **CERTIFIED**
> (lock 0.7-4.8% util; residency law kills the queue class); seven implementation gaps filed as
> `land-arch-*` backlog items — the largest: stranded-sweep runs INSIDE the land mutex (~90% of
> the hold). **Read that doc before re-opening any land-congestion question here**; it also
> re-grades this plan's §7 acceptance and flags §8's merge-queue rejection ground as decayed.

### Implementation wave 2026-08-10/11 — what landed, and one audit figure that is now false

Shepherded from pane 113 (session ff519bfd, recycled onto next4). Landed and content-verified
(`git ls-tree origin/main` present + `git diff <sha> origin/main` empty on every changed path —
never a commit count, which reads 0 after a sibling rebase and proves nothing):

| Item | Landed | Measured outcome |
|---|---|---|
| P1 empty-the-mutex | `145fab7d` | in-lock hold **72s → 3s**; sweep+reap moved post-release, reap made atomic (reap-mutex + generation recheck, H2 unweakened), in-lock fetch/push bounded, 640-branch fixture |
| P6 converge-completeness | `52761c20` + `4b5d1412` | parity covers **all 19** install.sh classes (was 5), incl. the `~/.claude/CLAUDE.md` cp leg; UNGATED verdict files; copy-classes get detection only, deliberately never an `ln -sf` |
| P5 **R7 arm only** | `863089e5` | deploy refusal escalates on repetition instead of damping forever; 13 tests measured RED pre-fix; a quiet-half control proves a low-count refusal still stays silent |

🚨 **§2.E's scan-window figure is FALSIFIED — do not inherit it.** The audit says the newest
on-trunk green sits **320 commits down** vs `SCAN_N=200`, concluding T1 is *structurally blind*.
Replayed 2026-08-11 against the real 147-stamp store, the newest green sits at **depth 12 —
inside the window**. The famine is real but its culprit is **verifier-lag**, not scan-window
blindness, and the landed R7 escalation reports it that way (`culprit=verifier-lag`) rather than
asserting the audit's number. A remedy keyed on "widen `SCAN_N`" would aim at the wrong
mechanism. (Related: P7's own erratum corrects §2.I/§3-P7, where the lane searched for a
checkpoint collector *by spelling* and recorded its absence as fact — one already existed at
`hooks/teammate-checkpoint.sh:153-248`.)

**The live layer is operator-gated, not merely lagging.** `deploy-live.sh` refuses to advance: no
GREEN tree descends from live HEAD. That is the bootstrap circle already filed and BLOCKED twice —
`3df911c0470e` and `54b1c02d7872` — both needing the same one-time forced advance past the
fail-closed gate, and both recording that a **raw fast-forward is explicitly not the move**
(`04470b5d`: it wedges deploy and resets both alarm legs). The irony is load-bearing: the
escalation built to page on this famine cannot page until the layer it exists to unblock advances.

⚠️ **Every live-layer number in this section decays within the hour — re-measure, never quote.**
Measured 2026-08-11: live HEAD `145fab7d`, **14** commits behind trunk, **5 of them ADDS** (and per
CLAUDE.md an ADD breaches at a lag of 1, because an added file has no symlink and every consumer
guard on it is a *silent* skip). So **P1's mutex fix IS live** — `145fab7d` is P1's own commit, and
the fleet is already paying the 3s hold, not the 87s one. What is *not* live is everything above
it, including P6's parity coverage and P5's R7 escalation. The two blocked items are staler still,
naming live HEAD `dec39a391362` and `ed095d4b`.

**This paragraph is its own worked example.** Its first version said "P1's mutex fix is on trunk but
the fleet still pays the old hold" — false when written, because it quoted a `7adc3c93` reading I
had taken an hour earlier and never refreshed, in the very passage warning that these figures rot.
The rule this earns: a live-layer claim must carry the measurement that produced it *in the same
edit*, or it must not be made.

**Remainder + the succession contract** (so the next shepherd does not re-derive it). Order is
**P4 → P3 → P2 → P0**, serialized by one thing only: **exclusive ownership of
`scripts/ship-land.sh` + `land-lock.sh`**. Fire the next item when its predecessor's paths are
content-verified on `origin/main` — never two owners of those files in flight at once. Landed so
far: P4 `b078e2fa`; P3 dispatched 2026-08-11.

- Briefs live at `/tmp/fire-land-arch-p{2,0}.txt` (transient — if absent, regenerate from §5 rows
  P2/P0 of the audit plus the constraint block in this section; the content is not precious, the
  *ordering rule* is).
- Every brief must tell its session to rebase and read the **current** `ship-land.sh` — each
  predecessor reshapes it, and the audit quotes a version that no longer exists.
- **P7 and P5 are NOT in this chain.** Verified by diff: P7 touches `bin/cc-blockers`,
  `scripts/worktree-gc.sh` and its tests; P5-R7 touched `scripts/deploy-live.sh`. Neither touches
  `ship-land.sh`, so both ran in parallel with the chain and neither gates it. A shepherd that
  serializes them anyway idles the chain for nothing.
- ⚠️ If you are running under a `/goal` that names a *prerequisite ordering* rather than an end
  state, check it against this rule before pausing work — one such goal on 2026-08-11 required all
  of P1/P6/P7 landed before *any* chain dispatch, which is stricter than the file-ownership
  constraint and became permanently unsatisfiable once the chain correctly proceeded without P7.

---

## Phase 0 — Agent Team Orchestration

**EXECUTION LOCUS PER WAVE** (recorded retroactively 2026-08-08 — the field postdates this plan's
build wave, and the history below is what actually happened, not a re-plan):

| Wave | Locus | Why |
|---|---|---|
| Build wave (2026-07-28): fastlane · verifier · deploy | **T** — in-session teammates | Three deliverables had to be reviewed against each other at each Phase A ack against three frozen contracts (exit codes · stamp schema · manifest format), so the synthesis had to sit in one window. Checkpoint log below. |
| Every follow-on single-clause fix (C22-C29) | **S** — dispatched session, one per backlog item | Default. Each is one item against one already-frozen contract; the lead pays only for the brief and a completion ping. C29 (§4.2.7) ran this way on branch `wt-4ac16c22d6ba`. |

Lead context budget: ≥50% held for deciding; succession point = after each wave's merge, via
`/handoff`. Background subagents remain research-only — no code changes.

Three teammates, disjoint file ownership, spawned concurrently (no blockedBy edges — T3's only
dependency on T2 is the manifest CONTRACT, pinned in §4.2, not T2's code).

| Teammate | Deliverable | Owns (exclusive) | Worktree |
|---|---|---|---|
| `tv2-fastlane` | corpus-free land lane in ship-land.sh | `scripts/ship-land.sh`, `tests/ship-land.bats`, `tests/land-gate-cas.bats` | own |
| `tv2-verifier` | verifier v2: fresh wt, partition, QoS, auto-revert, gate-green sync | `scripts/postland-verify.sh`, `scripts/host-suites.manifest`, `tests/postland-verify.bats`(+new) | own |
| `tv2-deploy` | deploy autopilot + post-deploy host checks + one-command activation | `scripts/deploy-live.sh`, `launchd/*.plist`(new), `docs/activation/**`, `.claude/commands/ship.md` | own |

Lead: this plan, integration review, merge order (smallest-diff first, rebase+ff-only,
serialized), final land via project `/ship`. Briefs ≤150 lines, pre-greped ranges, verbatim
stop-on-issue clause. Merge conflicts impossible by ownership; semantic seams are the three
contracts in §4 (exit codes · stamp schema · manifest format) — frozen here, cite by section.

**Checkpoint-review criteria (lead, at each Phase A ack)** — spawned 2026-07-28, teammates
tv2-fastlane/tv2-verifier/tv2-deploy on branches tv2/{fastlane,verifier,deploy}:
1. tv2-fastlane: `run_gate` must auto-skip smoke when `IN_LAND_LOCK=1` (the drop-recovery
   re-gate at old :1065 and the rounds-exhausted fallback both run under the lock — statics
   only there; nothing heavy ever inside the mutex). The post-land verifier KICK at old
   :1101-1106 (`postland-verify.sh --run-if-needed`, detached, per land) must SURVIVE —
   launchd is the backstop, the kick is the fast path. No `sleep` may remain anywhere in
   the land path (grep it).
2. tv2-verifier: filtered corpus list must feed BOTH the bats invocation AND
   suite_files()/suite_file_at() (index→file attribution breaks silently otherwise);
   fresh-worktree teardown on EVERY exit path incl. signal traps; auto-revert lands FROM the
   temp worktree (never the shared checkout — exit 4 refusal would fire).
3. tv2-deploy: activation script must match the 09 idiom, never run launchctl itself in
   tests; host-check red exits 0 (deploy succeeded; the finding routes to page+backlog).
4. All: shellcheck + own-suite bats green BEFORE ack; no full-corpus runs ever.

**Checkpoint log:**
- 2026-07-28 tv2-fastlane Phase A ACCEPTED (bae6c664): all criteria pass; 8-scenario
  end-to-end fixture verification; deviation APPROVED — SHIP_LAND_LANE=v1 restores the corpus
  PROOF, never the in-lock pathology (never-bats-under-lock binds in both lanes, permanently);
  CAS smoke-fact handoff (SHIP_LAND_SMOKE_*) approved.
  Scope (grown): +tests/gate-home-isolation.bats → tv2-fastlane (was unowned; tests removed
  tier behavior — rewritten to the v2 smoke surface, never manifested).
  Routed: ship.md admission-control mentions → tv2-deploy's rewrite.
- 2026-07-28 tv2-deploy Phase A ACCEPTED (a5c2509c + parity amend pending): --auto guards/
  damping/host-checks/alarms verified with positive AND negative controls incl. live-disk
  silence; plist /bin/bash -c PATH idiom approved (launchd expands neither ~ nor PATH;
  postland precedent). §4.3.2 verdict: install.sh needs NO relink pass — every class re-globs
  from the repo each run (skills at :193-200). Deliberate non-links recorded: scripts/ globs
  *.sh only ⇒ host-suites.manifest is NEVER live-linked — harmless by design (verifier reads
  the manifest from the tree under test; deploy-live reads $DEPLOY_REPO); bin/ cc-*-only is
  pre-existing policy. One gap being amended: parity-assert skills existence leg (the guard
  claimed 1:1 install.sh mirroring while routing skills/* to want=0 — the live
  video-understanding gap is the cost).
- 2026-07-28 tv2-verifier Phase A ACCEPTED (d2a5029c + must-fix amend pending): fresh cell
  per run w/ EXIT handler on every verb + 8h reap; ONE list feeds bats argv AND
  suite_file_at; gate_admit deleted (proved by recording-taskpolicy argv:
  nice -n 19 taskpolicy -c background bats <filtered list>); auto-revert e2e in fixtures
  with all guards + positive controls; gate-green commit-sha sync; selftest 22/22.
  §4.2.4 AMENDED: no --auto-revert VERB — red_actions integration is the mechanism.
  DESIGN REFINEMENT (approved, load-bearing): auto-revert fires ONLY on an
  actually-bisected culprit — red_actions' undecidable-bisect fallback (target sha) must
  NEVER be reverted (innocent-tip protection); Phase B pins it with a positive control.
  Must-fix in amend: 7th manifest entry (test-hermeticity-lint.bats) + standalone
  pre-corpus lints — without these the verifier reds every cycle (the localized 0-green
  cause) and v2 would activate wedged. Routed: stale gate_admit comment in
  ship-land.bats:873 → tv2-fastlane Phase B.
- 2026-07-28 verifier amend VERIFIED (b41cab96: 7-entry manifest w/ meta-lint criterion,
  PRELINTS wired+selftested 26/26, ONE-list proof via discriminating fixture). BLOCKER
  routed by teammate and cleared by LEAD (11925061): walltime ratchet's stale
  cc-relogin-status grandfather line redded the whole tree 3/3 deterministic — deleted per
  the ratchet's own shrink rule; verified lint rc=0/selftest rc=0/suite 14/14. APPROVED:
  8th manifest entry tests/test-walltime-lint.bats (criterion-based: whole-tree meta-lint
  wrapper class, enforced standalone by PRELINTS); three verifier refinements — own-bound
  rc=124 ⇒ CUT never RED (a self-imposed timeout forges no finding; a false RED feeds
  auto-revert), lint-red skips the corpus (R7), absent-lint ⇒ skipped (history stays
  verifiable). tv2-deploy parity fix landed as own commit d9c9e807.

---

## §1 First principles — why the old frame cannot work

The system must land **~43 commits/day (344/8d measured)** from **12+ concurrent sessions,
24/7** on **one Mac** whose *ambient* load from those sessions alone (~15–20% CPU each + iTerm
+ WindowServer) sits at or above 10 — there is **no quiet window by construction**
(RESTART-BRIEF-2026-07-27: load 88–104 observed while "stuck"; ceiling 8).

The old frame: *every land proves the full corpus green before push*. Consequences, all
measured, none fixable inside the frame:

- **Cost**: corpus = 144 suites / 2,349 tests, 20–53 min quiet (monolith), growing ~14%/2d.
  43 lands/day × corpus × stale-gate re-rounds = multiple box-DAYS of bats per day, concurrent
  with the sessions producing the load that kills it.
- **P(green) collapses combinatorially**: per-suite interference rate q=2.94% ⇒ monolith
  P(green at n=126) ≈ 2.3% (ship-land.sh:517 MLE over 55 real runs). One branch died **37
  consecutive times**, then landed *first try* at load 9 with 0 not-ok — the tree was never red.
- **Every mitigation fed the loop**: unlocked parallel gates ⇒ N concurrent corpora ⇒ more
  load ⇒ kills ⇒ CUT misread as RED ⇒ dispatcher retries ⇒ more gates (f8e40b4c577d). Admission
  control ⇒ sleeping gates (postland slept ~2h/run: per-call 600s budget × ~12 calls,
  60ec4c2d86d4) ⇒ self-starvation below the gates' own ceiling (5 gates at load 16–18 vs
  ceiling 8 — each gate's corpus IS the load the others wait out).
- **The lock was never the problem**: 230 successful lands show hold 84–302s, wait 0s. The
  hold IS the in-lock work; queues appear only when the corpus enters the lock (in-lock
  fallback, 3h36m holder observed) or hangs (unbounded cc-inbox-guard fork, 5-day jam).

**Conclusion (the inversion):** the full corpus can never run per-land, per-session,
load-gated. It must run **once, post-land, batched, in the background QoS band, by exactly one
singleton** — and the *land* must carry only work that is O(diff) and bounded by wall-clock,
never by load. Correctness is preserved by moving the enforcement point: **deploy (not land)
waits for the full-suite verdict**, and a red trunk **auto-reverts**. Landing becomes
seconds; the live layer stays provably green; corpus growth affects deploy latency only.

Industry precedent (same conclusion at every high-volume shop): post-land CI + revert culture
+ deployment gating on green (Chromium sheriff/TreeCloser, Google TAP), vs pre-land full
verification which caps throughput at corpus-time and was abandoned everywhere volume grew.

### Requirements (from the goal + hard-won invariants that SURVIVE the redesign)

R1 land p50 ≤ 30s, p99 ≤ 3 min, at 12+ concurrent writers, load-indifferent.
R1b the VERIFIER's corpus is load-indifferent too: no test may read ambient machine state, and the
   verdict is a function of the TREE ALONE. Added 2026-08-08 (LOAD_INSENSITIVE_VERIFY_V2 C3) because
   R1 was propagated to the LANDER and silently never to the VERIFIER — and an unpropagated
   requirement leaves no trace, so nothing could detect the omission. The cost of leaving it unnamed,
   measured: 37 corpus suites reached a net-new fire while `capacity_gate()` read live loadavg and
   memory headroom, so on a permanently-saturated box they went red for a reason that was not in the
   tree; the verifier never stamped green; `deploy-live --auto` never opened; the live layer sat tens
   of commits behind. Naming it here is what stops the next relocation of a verdict from re-inheriting
   it — the corollary already learned twice is that MOVING a load-sensitive verdict does not fix it,
   it only changes who blocks on it. Enforced, not merely asserted: `scripts/test-hermeticity-lint.sh`
   RULE 2 binds on the whole tree with an EMPTY grandfather list, and it runs as a verifier prelint.
R2 trunk red is bounded: detected ≤ 1 verifier cycle, auto-reverted, author notified.
R3 live ~/.claude only ever advances to a full-suite-green tree (stronger than today: 0 green
   stamps have ever existed, so deploys have been manual/unverified all along).
R4 no lost commits: content-verify by paths after push; stranded-sweep; backup refs pruned on
   success; Session-Id trailers (all kept from v1 — they are seconds, not minutes).
R5 every step bounded by absolute-path timeout(1); a bound covers the failure mode it bounds
   (connect+rpc, whole process group); no per-call×loop multiplication; singleton locks are
   skip-not-queue, pid+lstart-reaped.
R6 verdict vocabulary keeps GREEN/RED/KILLED(CUT)/HUNG distinct end-to-end; a non-verdict is
   never a red; a named failure is never softened to retry; structured `verdict=` tokens, one
   exit code per outcome.
R7 fail-closed never amplifies: a degradation path must never pick a MORE expensive action
   (the fail-closed-degradation-as-amplifier law). Shedding = SKIP (defer to the net), never
   wait-then-run-anyway.
R8 escalation surfaces (destructive SQL / credentials) still PARK a decision packet pre-push.
R9 absence is loud: verifier stamp freshness + deploy lag + un-run activations surface via
   cc-blockers/operator-readout; an inert net is detected, never assumed live.

---

## §2 Measured constants this design is built against

| Constant | Value | Source |
|---|---|---|
| Lands/day | ~43 (344 / 8d) | git log origin/main --since 8d |
| Corpus | 144 suites, 2,349 @test | ls tests/*.bats; grep -c @test |
| Corpus wall (quiet, monolith) | 20–53 min; per-suite mode +3% | ship-land.sh:521-527 |
| Per-suite interference q | 2.94% raw; 0.49% with 1 retry | ship-land.sh:519-526 (MLE, 55 runs) |
| P(green) monolith n=126 | ~2.3% → 49.9% per-suite+retry | ship-land.sh:526 |
| Lock hold / wait (success) | 84–302s / 0s (n=230) | RESTART-BRIEF §1 |
| Ambient load, 14 sessions | 88–104 peak; 10–16 after browser close | RESTART-BRIEF §1 |
| gate_admit ceiling | 8 (load), 600s/call budget | ship-land.sh:290-352 |
| postland runs | 22 stamps, **0 green ever**; run_s 6,606–10,052 | RESTART-BRIEF §4/§6 |
| postland red set (load 9.34) | deploy-parity, desk-arm-live, desk-recycle-durable, lr-team-audit, session-continue, waiting-recycle | RESTART-BRIEF §6 |
| Land volume that died on one lint | 14 consecutive lands (fabricated-leak) | RESTART-BRIEF §2 |

(Telemetry addenda — exit-code distribution, flake ledger, suite timing samples — integrated
below as research lands; they tune parameters, not the architecture.)

**2026-07-28 telemetry (researcher, full land.log/flakes/stamps parse + timed sample):**
- Volume corrected: **12.9 lands/day calendar · 22.5/active-day · 47/day-equivalent** in the
  only valid window (33h post-instrumentation; earlier "0 reds" is a logging artifact — B2).
  341 attempts/14d → 180 lands (52.8%); valid window: 70% red. My earlier 43/day was commits.
- Scoped-tier autopsy: 62% of "scoped" runs were **effective-FULL** (selector returned FULL)
  → 95% red; genuine subsets (p50 27 suites) → 68% green. The tier that fails is the tier
  that doesn't narrow.
- Lock truth: post-unlock-fix median hold **1s** (was 299s), zero same-minute lands ever —
  but the fix CREATED exit-42 stale-gate (30%, 26.4h of wait for 79s of work) and exit-75
  starvation (19h) populations: **81% of all lock wait-hours ended in a non-outcome**. v2
  keeps the CAS shape but re-gates cost seconds, so the 42-tax collapses.
- Corpus is **sleep-bound**: ~2,889s of literal `sleep` ≈ 94-99% of the 49-57min sequential
  wall (3 estimators converge; postland run_s p50 50.9min corroborates); 82% of sleep in 7
  files; 1 of 10 cores used. ⇒ verifier under background QoS loses little; Phase-2 roadmap:
  per-suite parallelism + sleep-shrinking those 7 files → cycle ≈ minutes.
- postland runner spent **~10.0h of a 32h life in admission waits** (54/75 waits ended
  "proceed anyway"); every recorded flake occurred at load ≥ 7.85 (the ceiling is 8).
- exit 9 has NEVER fired (cuts absorbed as pass-on-retry below it); stranded-sweep `review`
  is 100%-saturated non-signal (81% of successful lands); reboot 07-27 19:02 wiped the lock
  dir and re-wrote the launchd disabled-override — all 13 com.claude.* labels sit DISABLED
  (activation MUST `launchctl enable` before bootstrap; install.sh's bootstrap alone fails
  EIO silently — deploy-layer G3).

**2026-07-28 10:53 live reads (lead):** load 5.87 (first sub-ceiling window of the week; lock
FREE; zero gates running — bootstrap-land window is OPEN). Newest postland run
(2026-07-27 10:02, tip ea6f7b5a): **RED, run_s 3132, retries 12, flakes 0, failing = exactly
the 6 host suites** (deploy-parity, desk-arm-live, desk-recycle-durable, lr-team-audit,
session-continue, waiting-recycle) — the strongest direct evidence for the §4.2 partition:
the tree verdict is red SOLELY because host-coupled suites assert a live layer the tree is
ahead of. Corpus cycle estimate for the verifier: ~52 min at moderate load.

> **CORRECTED on the attribution, 2026-08-08** (backlog `22b839c85a52`; the partition itself is
> unchanged and still right). "Failing = exactly the 6" was a set identity, not a per-suite
> conviction — those six *are* the manifest, so a red anywhere in them names all six. Only ONE of
> them ever asserted the live layer. `POSTLAND-CELL-BISECT-2026-07-29.md` ran the six in a fresh
> cell three times (C1/C2/D1) for **155 ok / 0 not-ok**, and isolated the single not-ok that did
> appear to **deploy-parity alone** by a same-minute control. Re-measured 2026-08-08 the way that
> distinguishes the two cases — a fresh cell with `HOME` pointed at an EMPTY dir, so `~/.claude`
> does not exist — the other five pass at full count (8/8, 9/9, 3/3, 23/23, 108/108) while
> `deploy-parity-live` goes red on `not ok 1`. So five entries, **151 tests**, sat out both the tree
> verdict and the land smoke for a property they never had; they are de-listed, and the reasoning
> plus the three ambient seams that had to be pinned first is in `scripts/host-suites.manifest`.
> Read every "the 6 host suites" below as **one** from that date.

---

**2026-07-28 archaeology deltas (evidence pack: docs/research/land-pipeline-v2-research-2026-07-28/):**
- **0-green re-localized (supersedes the restart brief's §6 cell suspicion):** clean-room full
  corpora fail on exactly ONE suite — tests/test-hermeticity-lint.bats:22, a whole-tree
  assertion that passes standalone and fails mid-corpus (2,085/1 and 2,242/1; backlogs
  b59eb997d035, b4e49b4b5014; "the other 6 convicted suites are spurious" — their
  convictions were verdict-path artifacts). §4.2 amended: manifest gains that suite as a 7th
  entry AND the verifier runs scripts/test-hermeticity-lint.sh + test-walltime-lint.sh
  standalone pre-corpus (whole-tree strict, bounded, named RED on failure).
  - **CAUSE CORRECTED 2026-07-29 (b4e49b4b5014 — the reproduction).** "A whole-tree assertion
    that passes standalone and fails mid-corpus" named a symptom, not a cause, and the cause it
    implied ("sees a tree the corpus is concurrently using") is FALSIFIED: the corpus never
    mutates the tree (watched for a full run — 149 and 155 `*.bats`, zero changes). Real cause:
    the lint's two pure predicates ran a bare `grep -q`, so **rc=2 (grep could not RUN — fork
    exhaustion at the measured load 15-48) was indistinguishable from rc=1 (no match)**, and one
    transient fork failure FABRICATED a LEAK / "the embedded allowlist is stale" about a clean
    tree. The corpus's only role was to be the load. Only this explains all three observations
    the mid-corpus story cannot: ~1 not-ok in 2,242 (not the 4 a deterministic whole-tree defect
    gives); WHICH of the suite's four whole-tree scans fails varying by run (`the real tree is
    CLEAN` in b59eb997d035 vs the SYMLINK selftest here); and `flakes.jsonl` recording
    **`pass-on-retry` at loadavg 17.38** — a deterministic assertion cannot pass on retry.
    Already fixed at the source: **afaf40de** (rc>=2 ⇒ NON-VERDICT, never a leak) + **ed4e6c6a**
    (retry the pure predicates 3×). RED-proved by replaying the pre-fix artifact at `afaf40de~1`
    under an intermittent `grep`: whole-tree exits 1 naming three clean suites as LEAKs and
    `--selftest` reports "the embedded allowlist is stale"; at HEAD both are green.
  - **Consequence found while reproducing it — the same conflation, one layer OUT (fixed here).**
    `prelint_check` mapped every non-zero, non-124 rc to `FAILING` ⇒ RED ⇒ `red_actions`. Both
    lints publish `0 clean · 1 violation · 2 unusable`, so an HONEST exit-2 non-verdict — exactly
    the state afaf40de created inside the lint — was filed as a verdict about the tree and could
    **auto-revert a commit never shown to be at fault** (AUTOREVERT defaults on). Now only rc=1 is
    a RED; 2/124/126/127/137 set `PRELINT_UNPROVEN` ⇒ CUT ⇒ the CUT_MAX page ladder (loud, never a
    green). 2 regression tests, RED-proved against the pre-fix mapping.
  - **Enforcement gap recorded, NOT closed:** the prelint invokes `./scripts/<lint>.sh tests`,
    never `--selftest`, so the 17 cases proving the ratchet actually goes RED run only in the
    partitioned-out wrappers and in `scripts/nightly-regression.sh` — whose launchd job
    `com.claude.nightly-regression` is staged in `~/Library/LaunchAgents` but **NOT loaded**
    (`launchctl print` → "Could not find service"). That proof runs nowhere automatically today.
    Three candidate remedies (add `--selftest` to `PRELINTS`; load the nightly — a C10 operator
    step; re-admit the wrappers to the corpus) trade off differently and change the corpus
    partition, so this is filed as backlog **76644e76aaae** rather than picked unilaterally. Note
    the exit-2 fix above is a PREREQUISITE for the first remedy: before it, adding `--selftest` to
    `PRELINTS` would have made a fork-starved selftest auto-revert trunk. That remedy additionally
    needs a verdict category separating "the LINT is broken" (selftest exit 1) from "the TREE is
    dirty" — otherwise a broken lint reverts an innocent commit, i.e. this same bug once more.
- **Carrier cap is a first-class failure mode (F14):** the agent Bash tool caps at 10 min;
  a ~50-min gate inside it truncates to a false exit-6 (6 observed). Bootstrap land (§6)
  therefore runs DETACHED (start_new_session Popen + log + Monitor), never as a foreground
  tool call. v2 structurally clears F14 for everyone else: smoke ≤2 min fits any carrier;
  the verifier runs under launchd/detached.
- **Correction to the evidence pack itself:** its §4 row "land-lock keying per-worktree,
  NOT BUILT" is stale — land-lock.sh:27-46 keys on --git-common-dir with worktree-suffix
  normalization ("Fixes G-P9-1"), read directly; telemetry corroborates (0 same-minute
  lands in 180). The report inherited a pre-fix audit doc claim.
- exit-9/cut-not-red have NEVER fired in production despite landing — the CUT≠RED machinery
  is labelling without policy; v2 makes the distinction structural (smoke cut ⇒ proceed;
  verifier CUT ⇒ re-cycle) instead of exit-code vocabulary.
- gate-select DIRECT edges can come from PROSE mentions (a71df503c6f1) — acceptable for
  smoke (over-selection is bounded by the budget), noted for a later selector tightening.

## §3 The architecture — three lanes, one verdict owner

```
Session lane (per session, seconds)          Verifier lane (ONE, background)         Deploy lane (ONE, seconds)
──────────────────────────────────          ───────────────────────────────         ─────────────────────────
commit → preflight → fetch/rebase           launchd every 5–10 min:                 launchd every 10 min:
→ O(diff) statics + ratchets                tip tree stamped? exit.                 newest stamped-green sha
→ DIRECT-suite smoke (≤120s budget,         else: FRESH worktree @ tip,             → ff-only advance shared
  SKIP under load — never wait)             background QoS (no admit sleep),        checkout → install.sh
→ land-lock (seconds): CAS fetch            TREE suites only, per-suite,            relink (new files) →
  → push → content-verify → unlock          bounded → stamp GREEN/RED/CUT/HUNG      post-deploy HOST suites
→ attested land.log line                    GREEN: stamp + gate-green sync          against live layer →
                                            RED: retry-ladder → bisect →            red ⇒ page+backlog
        ↓ trunk advances                    AUTO-REVERT culprit (bounded,           (live layer already
   (unproven-but-linted, briefly)           marker-keyed) + notify author           advanced — host red is
                                            CUT/HUNG: existing states, honest      a live-layer finding,
                                                                                    not a deploy blocker)
```

**Who asserts what** (the verdict inversion):

| Claim | v1 owner | v2 owner |
|---|---|---|
| "this diff is well-formed" (lint/ratchets/esc) | land gate | land lane (unchanged checks, O(diff)) |
| "the FULL suite proves this tree" (gate-green) | land gate (full runs) | **verifier only** (green stamp ⇒ gate-green marker) |
| "the live layer runs a proven tree" | operator judgment | **deploy lane** (fail-closed on stamps — deploy-live.sh semantics, now autonomous) |
| "the live HOST is healthy" | mixed into the corpus (the bootstrap circle) | **post-deploy host checks** (partitioned out) |
| "a red trunk gets fixed" | blocks every subsequent lander | **auto-revert** + author notification |

**Why trunk-briefly-unproven is sound here:** trunk is consumed only via (a) deploy — gated on
green, so the live fleet never sees an unproven tree, and (b) sibling rebases — which inherit
at worst one verifier-cycle of unproven commits, exactly what v1's `scoped` lands already
shipped (and v1's "full" gates proved trees under 2.3%-green conditions, i.e. mostly didn't).
The exposure is bounded by cycle time and healed by auto-revert (R2).

---

## §4 Component specifications

### 4.1 Land lane — `scripts/ship-land.sh` (tv2-fastlane)

Keep verbatim: preflight (shared-checkout refusal, dirty refusal), esc-scan → decision packet
(R8), backup ref, rebase-conflict exit 5, land-lock'd CAS→push→content-verify→sweep (the
84–302s core, minus the gate the hold was mostly made of), attested land.log, Session-Id
trailers, backup-ref prune on success.

Remove: the corpus. `run_gate` keeps ONLY: shellcheck/bash -n/py_compile on changed files ·
hermeticity ratchet (own-scope) · wall-clock ratchet (own-scope) · gate-select `lint` is NOT
run (selection no longer decides anything heavy). Then **smoke**: `gate-select --direct` suites
only, run per-suite under one TOTAL wall budget `SHIP_LAND_SMOKE_BUDGET_S=120`, `nice`d, and
**skipped entirely** (not waited) when 1-min load ≥ `CC_GATE_MAX_LOAD` — R7: shed = skip,
because the verifier is the net. Overrun ⇒ kill process group, remaining suites skipped,
land proceeds, `smoke:"partial"` attested. A smoke RED (named `not ok` in a direct suite) still
blocks (exit 6) — it is O(your diff) and the highest-value seconds in the pipeline. A smoke CUT
⇒ proceed (non-verdict never blocks a land; verifier decides).

Delete: optimistic-round full re-gates (CAS-stale ⇒ re-rebase + re-run statics+smoke only,
rounds bound stays), the **in-lock full-gate fallback** (its premise is gone; nothing heavy may
ever enter the lock), `gate_admit` waiting (smoke skips, never waits), `$HOME` clone for the
gate (nothing left worth isolating; verifier gets its own), `stamp_gate_green` from the land
path (a land makes no full-suite claim — `GATE_EFFECTIVE_FULL=0` always; marker advances via
verifier only, §4.2).

Exit codes unchanged (0/2/3/4/5/6/7/8, 9 now rare: smoke never yields 9 — a cut smoke
proceeds). land.log schema: `gate_scope:"fast"`, add `smoke:"green|red|partial|skipped|none"`,
`smoke_n`, `smoke_s`. Kill switch `SHIP_LAND_LANE=v1` re-enables the old full-gate path
(one release), default `fast`.

Worst-case land: rebase(5s) + statics(10s) + smoke(≤120s) + lock(hold: fetch+push+verify
≈5–15s) ≈ **≤ 3 min; typical ≈ 20–40s** (statics + few-suite smoke + push). Meets R1; hold
time collapses ⇒ 12 concurrent landers queue behind seconds, not minutes.

### 4.2 Verifier lane — `scripts/postland-verify.sh` (tv2-verifier)

Keep: tree-keyed stamps + schema (deploy-live.sh compatibility is the contract:
`<stamps>/<tree>.json`, `"verdict":"green|red"` + existing fields), GREEN/RED/HUNG/CUT states,
retry ladder (2/3 conviction), bisect verb, flakes.jsonl, pages/backlog on red, singleton
lock (TTL-reaped), PATH normalization, POSTLAND_SUITE_TIMEOUT_S/FILE_TIMEOUT_S bounds.

Change:
1. **Fresh worktree per run** — `git worktree add --detach <tmp> <sha>` + prune after (the
   reused-`ci-postland` cell is the prime suspect for the 6-suite red; fresh is strictly
   cleaner regardless). Bounded disk: prune on every entry.
2. **Corpus partition** — new `scripts/host-suites.manifest` (one `tests/<file>.bats` per
   line, `#` comments). Verifier runs `tests/*.bats` MINUS manifest lines ⇒ the **tree
   verdict**. Manifest seeds: the 6 measured reds + any suite asserting the deployed layer
   (deploy-parity family). Contract (frozen for T3): plain-text manifest at that path; a
   missing manifest ⇒ empty (verifier runs everything — fail-closed toward MORE proof);
   unreadable line ⇒ ignored+logged. Post-deploy host checks (§4.3) run exactly the manifest
   set. A tree-suite that asserts live state reds in the verifier ⇒ normal attribution names
   it ⇒ it moves to the manifest by a 1-line land. The partition is total by construction
   (set difference), never hand-synced.

   **AMENDMENT (2026-07-31, backlog 5ef018dfc992 — landed): the unit is the FILE, so the
   1-line land above is only correct when the file's live-layer dependence is the WHOLE file.**
   Listing a suite does not exempt its live-layer tests; it exempts every test in it, from the
   tree verdict AND (per the §4.1 addition below) the land smoke. A mixed file therefore rides
   its hermetic tests out of both lanes, and the entry looks exactly like a correct one — the
   loss is nameless. Live in `tests/deploy-parity.bats`: 31 tests, 29 fully hermetic, 2 reading
   the real `~/bin` + `~/.claude`. Measured at 09a0214a, `gate-select --direct` on the last land
   touching `scripts/deploy-parity-assert.sh` named exactly one direct suite — that file —
   which `filter_host_suites` then removed, so **the land ran zero tests**, and the exit-3
   third-state guards (7a40d5a8) were first exercised only post-deploy, after the change was
   live. Fixed by SPLITTING (`tests/deploy-parity-live.bats` holds the 2; the manifest lists
   it) rather than by loosening the frozen contract — matching the file boundary to the
   partition boundary honours per-file granularity instead of amending it. The split is pinned
   in both directions by two tests in `tests/deploy-parity.bats`, each two-sided RED-proved.
   **Admission rule going forward:** admit a file only when the live-layer dependence is the
   whole file; if it is a minority of the tests, split first.

   **AND RE-READ THE SEEDING RATIONALE ABOVE IN THAT LIGHT.** "Manifest seeds: the 6 measured
   reds" (and the 2026-07-28 10:53 log at §4.2) conflated two causes with different fixes —
   *asserts the deployed layer* vs *went red under corpus load*. The manifest header already
   records that correction for the two meta-lint wrappers (b4e49b4b5014: a bare `grep` rc=2
   under fork exhaustion FABRICATED failures about a clean tree; fixed at source by afaf40de +
   ed4e6c6a). A census of the other five seeded suites (2026-07-31, filed as backlog
   22b839c85a52) reports **zero** live-layer tests among them — desk-arm-live 8, desk-recycle-
   durable 9, lr-team-audit 3, session-continue 21, waiting-recycle 106, each pinning its
   subject through `CC_*` fixture seams — i.e. 147 tests excluded from the tree verdict and the
   smoke on a rationale that may never have applied to them. NOT acted on here and deliberately
   not treated as settled: 2 of the 5 were spot-verified by hand, the rest by the census alone,
   and de-listing risks re-entering the very bootstrap circle §4.2 exists to kill — so each
   suite needs its own clean-room AND in-corpus proof before it moves. Filed, not assumed.
3. **Background QoS, no admission sleeping** — run the corpus under `nice -n 19` +
   `taskpolicy -c background` (Darwin: background CPU/IO band, yields to sessions). Delete
   gate_admit-style load waits (closes 60ec4c2d86d4 by construction). The singleton MUST make
   progress at any load; wall time under load is deploy-latency, not blockage.
4. **Auto-revert** (new verb `--auto-revert`, ON by default, `POSTLAND_AUTOREVERT=off` kill
   switch): on REPRODUCIBLE RED with a bisected culprit C: refuse if C is itself a revert, or
   already marker-keyed (`<state>/reverts/<C>` — never twice), or > `POSTLAND_MAX_REVERTS=2`
   this cycle; else in a throwaway worktree: `git revert --no-edit C` → land via the
   **fast lane** (own branch, normal esc-scan — a parked revert is a feature, R8) → marker +
   `cc-backlog` packet + `cc-notify` to the author sid (land.log line whose `head`==C, else
   commit trailer). Revert-land red/conflict ⇒ page + backlog, deploy stays pinned (R3 holds).
5. **gate-green sync**: on GREEN stamp of tip T, write `<git-common-dir>/gate-green = T`
   (the marker's consumers — boundary-handoff.sh:122, wrap-ledger.sh:79 — read exactly the
   claim the verifier is now the only party able to make).
6. **Launchd**: `com.claude.postland-verify.plist` StartInterval 300 stays; add
   `KeepAlive.SuccessfulExit=false`? NO — skip-not-queue semantics + StartInterval suffice;
   absence-is-loud covers death (R9 freshness alarm via cc-blockers: newest stamp age).

#### 4.2.7 Cross-window corroboration — the ladder's three runs are ONE experiment (C29)

**Added 2026-08-08**, closing backlog `4ac16c22d6ba` (filed 2026-07-28). Landed in
`scripts/postland-verify.sh` (`conviction_observe`, `corroborate_convictions`, `conviction_clear`)
+ 6 new tests in `tests/postland-verify.bats` + 2 new `--selftest` asserts.

**The defect.** `classify_failures` re-runs a failing test twice more *back to back* — seconds
apart, on the same box, inside one run. Its three observations therefore sample **one load
window**, so ">=2/3 agreed" means only *"it failed twice under the same ambient load"* — which a
starved box produces exactly as reliably as a bug does. `GATE_ARCHITECTURE_PLAN.md:349-352` had
already recorded the governing law one variable off: *"re-running is evidence only if the
environment actually changed"* (written about a ladder that re-ran under the same wrong PATH three
times and called the agreement reproducible).

**Why this is not C24 restated — the band axis was tried, and it was not enough.** C24 (`08dd4e3c`,
2026-07-31) closed the *first* half of that law by elevating the re-run out of the corpus's
background clamp into the utility band, so the retry genuinely does run in a changed environment
now. It helped and it stays. But the variable it moves is **priority**, not **ambient load**: a box
at load 15 is at load 15 for all three attempts, and a suite losing to memory or IO pressure loses
in utility too. Measured 2026-08-08 over the 100 stamps on disk, split at C24's own landing:

| | n | red | green | cut | hung | consecutive red pairs fully DISJOINT |
|---|---|---|---|---|---|---|
| PRE C24 | 46 | 42 | 1 | 2 | 1 | 7 of 34 |
| POST C24 | 54 | 48 | 2 | 4 | 0 | 7 of 47 |

The fingerprint **survived the band fix**. A genuine red re-convicts the *same* file until somebody
fixes it; a convicted set that reshuffles sweep to sweep (`prev=11 now=2 overlap=0` · `prev=12
now=1 overlap=0` · `prev=9 now=1 overlap=0`) is the box talking, not the tree. Two greens in 54
sweeps. And a red is not merely a wrong stamp — it is terminal for that tree (C5 abstains on
`green|red|hung` forever) and it arms the bisect and **auto-revert**, which pushes a revert of an
innocent commit to trunk.

**The rule.** A conviction produced by the LADDER is a *candidate*, not a verdict. It reds only
when a later sweep, at least `CONVICT_SPREAD` (900 s) on, convicts the same file again. One window
⇒ the C23 abstention: `FAILING` empties, `CONVICT_PENDING=1`, the run stamps `cut`, and the tree —
still unstamped-green — is re-run next sweep. **That retry IS the second window**, so nothing extra
is ever scheduled. A real verdict spends the candidate ledger (`conviction_clear`, at the same
three sites as `cut_clear`), which is what stops a stale pre-exoneration row from corroborating a
later single-window failure into an instant red.

**Why this is not in the §8-rejected class.** §8 forbids *"raising the ceiling / more retries /
bigger budgets"* as parameter motion inside a broken frame, and the distinction matters: nothing
here adds an attempt, a poll, a sleep or a budget. The in-run ladder is untouched and costs exactly
what it did. What changes is what **one window's agreement is worth** — an evidence axis, and the
same shape C23 already landed (adding an abstention class). Nor is it a wait for a quiet box: that
is `gate_admit` (C19/R1), this box has no quiet window by construction
(`LOAD_INSENSITIVE_VERIFY_V2.md:11-13`), and a design that needs load to fall is already failed.
**The gate is separation in TIME, which the clock always eventually satisfies — never a lower load,
which would be unsatisfiable.** Load is recorded per observation as evidence for a human and is
never tested; a `--selftest` assert, anchored to statement position, forbids any `if`/`while`/
`until` branch on it (it matched itself when first written unanchored).

**Cost, stated rather than hidden.** A genuine red now takes two sweeps to heal instead of one.
That is deliberate: the announcement is cheap and the auto-revert is destructive, so the run that
cannot yet prove its conviction stamps a `cut` and reverts nothing. Deterministic reds — `bash -n`
and the whole-tree prelints — are **exempt** and still convict in one window, because they
reproduce by construction and a second window cannot tell them anything.

**The one interaction worth knowing about, because it is reachable and not obvious.** A C29 pending
takes the cut path, so it increments the *same* consecutive-cut counter a truncation does. A real
red therefore costs one cut and then clears it (`conviction_clear` runs beside `cut_clear` at every
verdict), and a load-flake clears it on the green — neither approaches `CUT_MAX`. But the pathology
this clause was built for — a box convicting a *different* file every sweep — now reaches
`CUT_MAX=3` and fires `cut_page` plus the 1800 s cool-off. That is the correct outcome and worth
saying out loud: three sweeps that cannot agree on *what* failed is exactly the state a human should
be told about, the page now says so in the C29 wording rather than claiming a truncation that did
not happen, and a half-hour cool-off on an unprovable tree is strictly better than the false RED
that used to be terminal for it.

**Seams.** `CC_POSTLAND_CONVICT=off` (kill switch, restores the one-window red) ·
`CC_POSTLAND_CONVICT_SPREAD_S` (window floor; tests shrink it to 0, which removes the wall-clock
floor ONLY — the two-sweep requirement stays live) · `CC_POSTLAND_CONVICT_TTL_S` (86400).
Ledger: `<state>/convictions`, TSV `epoch⇥file⇥tree⇥sha⇥load`, pruned to the TTL on every read.

**Known residue (not fixed here, deliberately).** The C13b sentinel — `not ok` present but no
`# (in test file …)` diagnostic ⇒ `FAILING=("tests/")` — still reds off a single window. It runs
*no* conviction runs at all, and `"tests/"` is not a key that can identify the same failure twice,
so corroborating on it would merge unrelated reds. Closing it needs a real attribution key, not a
wider filter.

### 4.3 Deploy lane — autopilot (tv2-deploy)

1. `launchd/com.claude.deploy-live.plist` (new): every 600s run
   `deploy-live.sh --auto` — new flag: exactly today's fail-closed green-cursor advance, plus
   (a) silent exit 0 when nothing new is stamped green (no page spam; the "no stamps dir"
   refusal pages at most once/day via damp marker), (b) after an ADVANCE: run install.sh
   (already in deploy-live), assert `deploy-parity-assert.sh`, then **post-deploy host
   checks**: bats over `scripts/host-suites.manifest` against the LIVE layer (their real
   subject, post-advance — the bootstrap circle §1 is dead: no pre-deploy check ever asserts
   "the future is live"). Host red ⇒ page + backlog packet (live-layer finding), deploy does
   NOT roll back (never rolls back today; rollback of the live layer is an operator decision).
2. **New-file symlink coverage**: verify install.sh covers brand-new tracked files on advance
   (the per-file-symlink gap that silently degraded scoped→full for live-path lands); if not,
   add the relink pass. Acceptance: land a new file end-to-end, symlink exists post-deploy.
3. **One-command activation**: consolidate to a single
   `docs/activation/pending-activation/14-land-pipeline-v2-activate.sh` — loads BOTH plists
   (verifier + deploy), idempotent, self-verifying (`launchctl list` grep + one
   `--run-if-needed` kick + `deploy-live.sh --dry-run`), and prints the two freshness alarms
   it arms. Stage to BOTH the repo SSOT dir and the live pending-activation dir (parity rule).
   Supersede/retire stale queue entries 09-postland-verify-activate.sh (fold into 14).
4. `.claude/commands/ship.md` (project): rewrite to describe the v2 contract (land = fast
   lane; the corpus claim belongs to the verifier; deploy is autonomous; what exit 6 vs 9 now
   mean; when to look at stamps).

### 4.4 Observability (folded into the three, no fourth component)

`cc-blockers`/operator-readout gain two fact-bound alarms (T3, thin): **verifier freshness**
(newest stamp age > 2× interval+corpus ⇒ surface) and **deploy lag** (green cursor ahead of
deployed HEAD > 60 min ⇒ surface). Both read disk only. land.log keeps one line per land
(now with smoke fields) — the p50/p99 acceptance read (§7) comes from it.

---

## §5 Failure-mode coverage (every observed mode → structural answer)

| Observed (v1) | v2 answer |
|---|---|
| 40-min gates × N sessions saturate the box | corpus runs 0 times per land; once per verifier cycle, background band |
| P(green)≈2.3% monolith false-reds | verifier per-suite + retry ladder (49.9%→ higher w/ fresh wt); land path has no corpus to fail |
| Load-kill → CUT misread RED → dispatcher retry loop | land smoke: cut ⇒ proceed; verifier keeps CUT/HUNG non-verdicts; nothing retries a corpus per land — **host lane joined only 2026-08-10** (§4.3 AMEND: it read `notok` before `rc==124`, so this row over-claimed for 2 weeks) |
| Admission sleep (2h/run; 5-gate self-starvation) | deleted both sides: smoke SKIPS under load; verifier never admission-waits (QoS band instead) |
| In-lock full gate ⇒ 3h36m lock holders | nothing heavy may enter the lock (statics+push only, 5–15s hold) |
| Unbounded fork (cc-inbox-guard) hangs gates for days | R5 absolute bounds per step; verifier HUNG state already isolates + names the wedging file |
| Whole-tree lint refuses unrelated lands | already own-scoped (kept); corpus reds no longer block ANY land — they route to auto-revert of the culprit only |
| Sibling lands mid-gate ⇒ stale re-gate churn | re-round = statics+smoke (seconds), not a second corpus |
| Rebase-drop / lost commits | content-verify + stranded-sweep + backup refs kept verbatim (R4) |
| 0-green-stamp deadlock (deploy-parity in the corpus) | corpus partition: host suites run post-deploy against their real subject |
| Reused ci-postland worktree cell | fresh worktree per run |
| Verifier dies silently (unloaded plist / pid exit) | one-command activation + freshness alarm (absence-is-loud, R9) |
| New-file symlink gap degrades live behavior | deploy relink pass + end-to-end acceptance test |
| Live layer runs unproven code (manual ff deploys) | autonomous deploy ONLY to stamped-green (R3) — first time this has ever been true |
| Red lands sit on trunk unnoticed | auto-revert ≤ 1 cycle + author notification (R2) |
| A revert war / revert of revert | marker-keyed, never-twice, never-a-revert, ≤2/cycle, kill switch |

---

## §6 Bootstrap & rollout (no half-measures, one clean cutover + kill switches)

1. Land v2 (this branch set) via the branch's OWN ship-land (the fast lane landing itself —
   precedented: the per-suite runner landed through the scoped path it created; standing-land
   authorization applies). DETACHED, never a foreground tool call (F14: the 10-min Bash
   carrier cap truncates gates into false exit-6). Exact invocation from the integration
   worktree after merging the three tv2 branches:

   ```bash
   cd /Users/chrisren/Development/.worktrees/claude-infrastructure-land-pipeline-v2
   LOG=/tmp/land-v2-bootstrap.$(date +%s).log
   python3 - "$PWD/scripts/ship-land.sh" "$LOG" <<'PY'
   import subprocess, sys
   subprocess.Popen(["bash", sys.argv[1]], stdout=open(sys.argv[2], "w"),
                    stderr=subprocess.STDOUT, start_new_session=True)
   PY
   # then: Monitor the log for '✓ ship-land: LANDED|✗|⛔|PARKED' + tail on completion
   ```
   The fast lane's own gate = statics + ratchets + direct-suite smoke (bounded ≤120s), so
   the land completes in minutes even mid-fleet; the first verifier cycle then makes the
   full-suite claim on the landed tree (kick it: `scripts/postland-verify.sh --run-if-needed`
   — a script run, NOT launchctl, so it is agent-runnable).
2. Operator runs `14-land-pipeline-v2-activate.sh` (the ONE C10 hand-step; classifier-blocked
   for agents). Until run, v2 lands still work (fast lane is self-contained); the alarms (R9)
   surface the un-run activation — degraded = loud, never silent.
3. First verifier cycle stamps the first GREEN in the system's history (or REDs with names ⇒
   normal attribution; the 6 host suites are already partitioned out, the prime-suspect cell
   is gone). Deploy autopilot advances on it. Acceptance (§7) read from disk.
4. Kill switches (env, not reverts — a revert needs the pipeline): `SHIP_LAND_LANE=v1` ·
   `POSTLAND_AUTOREVERT=off` · `POSTLAND_VERIFY=off` · deploy plist unload. Each is a lever
   the operator (or a session, for the env ones) can pull independently.

## §7 Acceptance (disk-truth, not narration)

- land.log over the first 20 v2 lands: p50 ≤ 30s, p99 ≤ 3 min, wait_s ≈ 0, zero exit-9.
- ≥1 GREEN stamp exists; gate-green == stamped tip; stamp age alarm silent.
- Deployed HEAD advanced autonomously to a stamped sha; deploy-parity + host suite run green
  post-deploy; a brand-new file landed in the window has a live symlink.
- One induced red (fixture branch) auto-reverts within a cycle with backlog + notify artifacts.
- Sustained: a 12-session day with continuous landing and zero operator interventions.

## §8 Rejected alternatives (and why)

- **Speculative merge-queue (Zuul/bors batching)**: solves throughput but keeps latency ≥
  corpus-time (fails R1) and keeps N-corpora concurrency (fails the load reality). Post-land
  + revert dominates on a single box with a trusted-author fleet.
- **Off-box CI (GitHub Actions)**: the corpus asserts THIS host (launchd, iTerm2, live
  ~/.claude, BSD userland); a macOS runner proves a different machine. Rejected for the
  verdict; optionable later for the pure-hermetic subset as a second opinion.
- **Content-addressed proof cache (old Phase 2b)**: pays per-land corpus cost on every cache
  miss and needed $HOME isolation to be sound; v2 makes the tree-keyed STAMP the only cache
  needed (one writer, one reader). Superseded — do not build.
- **Raising the admit ceiling / more retries / bigger budgets**: parameter motion inside the
  broken frame; every such knob either waits (starves) or runs-anyway (amplifies). R7 forbids
  the class.
- **Second Mac for verification**: real option, real money, not needed once the corpus runs
  once-per-cycle in the background band; revisit only if cycle time under load exceeds ~2h
  sustained.

  **REVISIT PERFORMED 2026-08-08 (backlog `343d7cc392b6`, re-opened by `DEPLOY_LANE_GROUND_UP`
  §1.5). The trigger is OPEN — and the answer is still no, for a reason the bullet above does
  not contain.** Verdict: **do not acquire a second host.** Three findings, in the order that
  decides it.

  **1. The breach is real, and worse than filed.** Partitioned to the launchd lane and to runs
  that actually produced a verdict: **p50 3.16h, p90 3.35h over 41 completed runs**
  (2026-07-26→08-08) against a 2h trigger. And **78% of those runs recorded the `SUITE_TO`
  wall (10800s) rather than their own work**, so 3.16h is a *floor*, not an estimate.
  The filing's "p50 ≈ 3.2h" was right by accident: it quoted the interval *between* verdicts
  beside a median *run* duration of 8852s as if one supported the other, pooled over both
  execution paths. Two ways that pooling reads BACKWARDS, both measured, both now pinned by
  `scripts/cycle-time-census.sh`:
  · *Non-verdicts shorten the median.* A `cut` writes a small `run_s`, so a lane collapsing
  into truncated runs reads as a lane that got fast. Over 89 rolling 8-stamp windows the naive
  and completed-runs-only medians disagreed about the trigger 5 times, **every disagreement one
  way** — naive quiet, honest firing.
  · *Two populations share one store.* Scheduled p50 3.16h vs session-invoked 1.28h. The
  discriminator is `env.cc`, not the loadavg column — that instrument was **blind in every
  scheduled run** until `4c58eaf5` and rendered blindness as `"load":"0"`, a dead sensor reading
  as an idle machine (38 of 96 stamps). Cross-check that the split is not an artifact of that
  fix: inside SCHEDULED, pre-fix p50 3.16h, post-fix 3.17h.

  **2. A second Mac cannot produce a valid verdict for this corpus — the bullet two above says
  so.** Off-box CI is rejected here because *"the corpus asserts THIS host … a macOS runner
  proves a different machine."* **That reason applies verbatim to a second Mac.** These two
  entries contradict each other and always did. Structurally: `scripts/host-suites.manifest`
  declares **3** of 331 suites machine-coupled, so 328 sit on the shared tree verdict with no
  hermetic partition to hand a second box. It lands on one of two horns — configured
  *identically*, it reproduces ~95% of the chronic reds (the largest single class, ~72 of them,
  is one launchd-plist PATH constant missing `/usr/sbin`:`/sbin`, proven by a same-tree same-box
  A/B in `2dbeb436`); configured *quiet and dedicated*, it stamps greens that do not hold on the
  machine the code runs on — defeating the detection `postland-verify.sh:154-178` deliberately
  preserves by refusing to normalize PATH. Nor is the lane queue-bound: **duty cycle 61.1%**, it
  idles 39% of the time. Green rate is 3/96; reds fall to zero when fixes land (11 measured
  cases). The constraint is verdict quality, not machine count. Adding a host would also cross
  five deep single-machine couplings — the mutex is a local pid (`kill -0`), the stamp key is
  the bare tree sha with no host identity and last-writer-wins, work selection has no lease, and
  auto-revert **pushes to origin/main on a single verdict**. It is a protocol rebuild, not a
  purchase.

  **3. The cheap lever the criterion should have pointed at was never priced.** The corpus is
  clamped to `taskpolicy -c background` (PRI 4, E-core confined) while every other actuator moved
  to `utility` (PRI 20) at `2514226e` for exactly this reason; `DEPLOY_GATE_CONVERGENCE.md:95`
  rejected raising it, but on the premise of *"foregrounding a 233-suite corpus"* — and `utility`
  is not foreground, it is still demoted below interactive. The corpus's own band tax had never
  been measured. **Measured 2026-08-08, interleaved on this box at load 18-22:
  `tests/cc-classify.bats` (58 tests, 0 sleeps) 51s/37s at `utility` vs 103s/96s at `background`
  = 2.26x.** Controls: pure `sleep 20` is band-immune (20s/20s), pure CPU carries 5-6x. Note the
  band is **not** what separates the two stamp populations — `QOS` is applied unconditionally to
  both — so the 2.46x scheduled/session gap is the *launchd envelope on top of it*
  (`ProcessType Background` + `Nice 10` + `LowPriorityIO`). **Two independent levers, neither of
  them hardware.** Bounded below by the ~1.2h of literal `sleep` in the corpus (4312s across 46
  files, band-immune), but even conservatively applied this brings the lane under 2h for $0.
  Filed as backlog **`70dff02dcf4a`** rather than fired here: the corpus band reverses a documented
  deliberate choice (`postland-verify.sh:285-297`, *"the verifier may never be the thing that
  waits"*), and the launchd half is C10 (plist edit + operator bootout, and `launchd-parity-lint`
  reds the fleet on a repo-only plist edit).

  **The criterion itself was the deeper defect, and is now executable.** "Cycle time" was never
  defined (three readings, all breaching), "under load" was unmeasurable from a blind instrument,
  and no denominator was named — so it fired around 2026-07-30 and nothing noticed for nine days.
  `scripts/cycle-time-census.sh` computes it with the population and denominator pinned, three-state
  (`WITHIN` / `BREACH` / `CENSORED` / `NO-VERDICT` — it refuses to call "within" on majority-censored
  data), covered by `tests/cycle-time-census.bats`, whose two controls each go red when their
  exclusion is removed. **Re-read it with `bash scripts/cycle-time-census.sh --all`; do not
  re-derive it by hand.**

## §9 Supersessions & backlog reconciliation

- GATE_ARCHITECTURE_PLAN: Phase 1 (per-suite) and 2a ($HOME clone) live on inside the
  verifier/smoke; **Phase 2b (proof cache) superseded by §8**; Phase 3 (hermeticity migration)
  remains valuable (shrinks q and the manifest) but is no longer on the landing critical path.
- Closes by construction: 60ec4c2d86d4 (admit cap ×N — admission deleted), da18f179ac50
  (0-green deadlock — partition), e65d45027b3d (embargo question — answered: not
  deployed-path shape; circle broken instead), 9c5d0ba74e79 / f8e40b4c577d invariants carried
  (R6/R7). Task #30 (gate-contention runaway) is THIS plan.
- SHIP_LAND_HARDENING_PLAN safety rails (CAS, content-verify, esc-park, backup refs) carried
  verbatim into §4.1.

**Deploy amend log (2026-07-28):** def04b7c+d9c9e807 ACCEPTED. launchctl print (not list|grep)
as the self-verify; trunk-red is a DISTINCT alarm kind from verifier-inert (opposite fixes;
floor 2 verdicts; mutually exclusive with STALE by construction). Parity widened to skills
with ordered deeper-first case patterns; lib correctly excluded (install.sh has no lib leg —
recorded as deliberate). TRUE-red surfaced: live layer lacks skills/video-understanding
symlink (deploy-parity test 8 red until `bash install.sh` runs live or the first --auto
advance self-heals it — operator readout carries the one-liner). Corpus exposure already
nil: deploy-parity.bats is manifest-partitioned since verifier Phase A.

**§4.1 DESIGN ADDITION (2026-07-28, found at integration):** the smoke's direct list must
ALSO exclude scripts/host-suites.manifest entries (read from the tree being landed; missing
⇒ no filter). A host suite arriving as a DIRECT suite of a diff reds the land for a
live-layer state the tree cannot control — the verifier partition's bootstrap circle
resurfacing in the land lane. Concrete: the integrated v2 land touches
tests/deploy-parity.bats, whose test 8 is TRUE-red on this box until the operator relink;
unfiltered smoke would exit-6 the bootstrap land itself. Routed to tv2-fastlane Phase B.

**Integration log (lead branch):** tv2-deploy COMPLETE and cherry-picked (310e264e /
ac47f2be / b73a7831, from 9ab93f66/eabcea9d/e58ad5b9); composed-tree gate re-run: shellcheck
clean, plist lint OK, deploy-live.bats 24/24. Their RED-proof caught a vacuous test via the
bats dead-assertion trap (non-final [[ ]] errexit-exempt ⇒ || false throughout) and an
ls|grep glob-literal trap — both now pinned in the suite itself.

**Integration COMPLETE (2026-07-28, lead branch = 23 commits):** all three assignments
delivered and cherry-picked; every component's suites re-run green ON THE COMPOSED TREE
(deploy-live 24/24 · cc-blockers 20/20 · postland-verify 49/49 + selftest 26/26 ·
ship-land/land-gate-cas/gate-home-isolation 96+ green · deploy-parity 15/16 with the one
KNOWN TRUE red = live-layer symlink, operator step). Fastlane's final commit closes the
integration-discovered gap: the smoke filters host-manifest suites (the partition binds the
land lane too). Verifier's parting merge-order constraint (walltime fix before verifier) is
satisfied by construction — single-branch integration, 11925061 precedes every verifier
commit in history, one ff push carries all atomically.

**LANDED 2026-07-28: 8d50f953 → origin/main** — 25 commits, via the branch's OWN v2 fast
lane, content-verified. First attempt exited 6 because the smoke CAUGHT A REAL DEFECT in the
landing range (the NEVER-ACTIVATED alarm firing in fixtured voids — fixed with the evidence
gate + pinned, 1ef916b6); second attempt landed in ~2.5 min total. The pipeline validated
itself on its own landing. Land latency at target on first production use.

**§4.3 AMEND (2026-08-10, backlog cb9980e4b0e5 — landed):** the §5 row "Load-kill → CUT misread
RED → dispatcher retry loop" was answered in the LAND and VERIFIER lanes and NOT in the host lane,
where the same mode was still live. `host_checks` tested `notok > 0` before `rc == 124`, so a suite
deploy-live itself killed mid-corpus was reported RED off whatever it had emitted before the kill,
paged, and filed as a backlog item — the retry loop, one lane over. Worse than a stray page: the
failing SET is a function of where the kill landed, and cc-backlog keys on project+title+source, so
one condition mints a new item every time load moves the truncation point (the sha-in-the-title
non-idempotency, by another door). Fixed by testing our own bound first; the reached failures are
NAMED in the log line so a non-verdict is not also a silence.

The item that surfaced it was itself an instance: `HOST RED: tests/test-hermeticity-lint.bats(2)` at
bda59c54, over a tree that is 52/52 green. That suite has NEVER produced a host verdict — CUT on 6
of 6 runs — because the 300s bound was a bench number and this runner is `ProcessType Background`
(PRI 4) + `Nice 10` + `nice -n 19`. Measured back to back on this box, one `--selftest`: 70s utility
band vs 252s under `taskpolicy -c background`, a 3.6x band tax; the suite is 272s utility.
**Scaling by that tax predicted ~980s and was 1.4x optimistic — the end-to-end run, issuing the
exact command host_checks issues, took 1399s wall (52/52 green, load 9-22).** A band tax is not a
constant you may multiply through; it moves with contention, and this box has been seen at load
15-48. Bound raised to 3600s (2.6x the realistically-loaded figure); 1800s, which this amend
originally carried, was only 1.29x it — enough to look fixed and enough for one spike to restore the
permanent non-verdict. **The general lesson for anything added to
`scripts/host-suites.manifest`: a bound below a suite's band-adjusted runtime does not bound that
suite, it deletes it** — and nothing says so, which is why this ran 12 days. That silence is the one
half NOT closed here: a per-suite consecutive-CUT counter for the host lane (postland-verify already
has the shape at `scripts/postland-verify.sh:527`, `CUT_MAX`) is filed as backlog 75463ef0d0f9.

**Bootstrap residue (ordered):**
1. Two PEER postland runners (pre-v2 code, wt-readme-pyramid copy) held the singleton lock
   at land time and will stamp tree 8d50f953 stale-RED — harmless (deploy already pinned);
   NEVER kill them (peer-kill pathology). On drain (monitored): lead kicks
   `bash scripts/postland-verify.sh --run 8d50f953` from a v2 checkout — fresh worktree,
   partitioned corpus, prelints — expected to mint the system's FIRST green stamp.
2. OPERATOR (C10, one step): `CONFIRM=1 bash ~/.claude/autonomy/pending-activation/14-land-pipeline-v2-activate.sh`
   (enable+bootstrap BOTH launchd jobs; the SessionStart parity check platters the repo→live
   cp first if needed). After it: verifier every 5 min, deploy autopilot every 10 min — the
   full land→verify→deploy chain is autonomous.
3. The live-layer symlink true-red (skills/video-understanding) self-heals on the first
   --auto advance (runs install.sh); no separate operator step required.

## Learnings (accumulate; never delete)

- 2026-08-08 (§4.2.7, C29): **N repetitions inside one environment are ONE observation, not N —
  and a fix that varies the WRONG variable leaves the count at one.** The retry ladder's
  ">=2/3 ⇒ reproducible" read as three independent trials but ran all three back to back, seconds
  apart, so it could not discriminate the very thing it existed to discriminate. The giveaway was
  never in any single stamp but ACROSS them: the convicted SET reshuffled sweep to sweep, which a
  real red never does. Three things generalise, and the middle one is the expensive one.
  **(a)** When a check repeats itself for confidence, ask what actually VARIES between the repeats.
  If the answer is "wall clock, by seconds", the repeats are decorative.
  **(b) A partial fix along a NEIGHBOURING axis reads exactly like a closed item, and only
  re-measurement tells them apart.** C24 (`08dd4e3c`) had already been prescribed by this very
  reasoning and had already landed — it varied the retry's BAND, which is genuinely the "changed
  environment" the law asks for, and any reader would have called this item closed on sight. The
  item was re-measured instead: 7-of-34 disjoint red pairs before C24, **7-of-47 after**, 1 green
  in 46 sweeps before, 2 in 54 after. Priority is not ambient load, and the fingerprint did not
  move. Had the re-measurement been skipped, the honest-looking close ("the band fix covers it")
  would have left an auto-revert convicting innocent commits off one experiment. The corollary for
  any parked item: **re-derive the evidence against today's tree, because the remedy that landed in
  between may have moved a variable adjacent to the one that mattered.** This also cut the other
  way — the WIP inherited from the pre-C24 session asserted in prose that "both the corpus run and
  the retry expand the same `QOS` array", which C24 had made FALSE; landing it unread would have
  shipped a confident, checkable lie in a comment block.
  **(c)** The fix had to be an evidence axis, not a parameter — "more retries" is explicitly a
  rejected class (§8) and would have been the obvious wrong move. The cheap axis was already on
  disk: the sweep the abstention *already* triggers is a free second window, so the second
  observation costs nothing that was not already being spent.
- 2026-08-08 (corollary, worth its own line): **an availability gate must key on something the
  world always eventually supplies.** Corroboration keys on elapsed TIME, never on "a lower load" —
  on a box whose designed steady state is 20-40 sessions, a quiet window may never arrive, so a
  load-keyed gate could convict but never exonerate. That asymmetry is the same one that produced
  the 0-green-stamp deadlock (C23) one clause earlier in the same function.

- 2026-08-07: **the verifier reached the right verdict and then filed almost none of it — two
  defects in one line, pointing opposite ways, each hiding the other.** `red_actions "$sha"
  "${FAILING[0]}"` filed exactly one backlog item per RED run, keyed on project+title+source with
  the sha *in the title* (`# sha defeats wasDone`, deliberately). Measured over `runner.log`:
  **69 RED runs · 472 failing-suite observations · 69 items minted · 38 of 58 distinct suites filed
  ZERO times.**
  - *Per-EVENT key* ⇒ the same standing red minted a fresh item every sweep (memory
    `per-event-key-defeats-per-finding-dedupe`: page per-EVENT, backlog per-FINDING).
  - *`FAILING[0]` only* ⇒ `FAILING` is corpus/TAP-ordered, so a suite that never sorts first was
    unfilable **by construction**, not by accident. Worst case `tests/gate-home-isolation.bats`:
    28 appearances, 0 filings, 0 rows in `flakes.jsonl` — never a flake correctly withheld, just
    never looked at. It went unnoticed because the *count* of items looked healthy (69 runs, 69
    items); only the ratio against the failing-suite population showed the hole.
  - **The two masked each other.** Fixing only the key would still file one suite forever; fixing
    only the breadth would mint N items per sweep instead of 1. Both had to move together, and the
    primitive for it already existed — `cc-backlog --condition` (stable state key, digits refused).
  - **The trap inside the fix**, worth more than the fix: `valid_condition()` rejects any key with
    a digit and REFUSES the whole `add` (rc 2), and this call site is best-effort. A slug that
    stripped digits would have filed 295 of 305 suites and silently dropped the 10 whose names carry
    one (`it2-*`, `iterm2-*`, `cc-dispatch-v2`, `subagent-stop-r1`) — **re-creating this exact
    invisibility for a different subset.** Digits are spelled out instead (`it2-kitty` →
    `postland-red-it-two-kitty`); verified over all 305 suites + the prelints + the sentinel:
    0 rejected, 0 collisions. Pinned by C13f.
  - Same reason the count is now a *checked* outcome (`verdict=filed n= refused=`), not the
    attempt count an `|| true` would have reported as success (memory
    `claimed-outcome-vs-checked-outcome`) — on the one path whose whole job is to stop failures
    going unseen.
  - **Not fixed here, and stated so it is not mistaken for fixed:** `gate-home-isolation` passes
    **22/22 standalone at trunk**, so its corpus-only red is a band/contention property, not a suite
    bug — consistent with the load-sensitivity note at `postland-verify.sh` §337-341. This change
    makes it *visible*; it does not make it green.

- 2026-08-06: **refusing to convict and reaching the right verdict are two different fixes, and
  the bisect needed both.** §4.2.4's innocent-tip protection (line 73) was defeated without ever
  being violated: the guard asks only *"did a bisect name this?"*, and the walk named the tip as a
  genuine culprit. Three commits closed it, from two independent sessions that did not know about
  each other:
  - `937c6fc5` — a walk that lands on the TIP must re-run it and CONFIRM; green there ⇒ undecidable.
  - `4348ddc2` — when the culprit is the first child of `good`, prove the FLOOR is actually green;
    a red floor convicts its first child.
  - **this commit** — the probe runs under the TMPDIR the CORPUS measured under. `git bisect run`
    had been inheriting the launchd `TMPDIR` while the corpus measured under `TMPDIR=$RUN_TMP`
    (`…/postland-run.XXXXXX`, **+20 bytes**), and a `tests/kitty-*.bats` fixture bound an AF_UNIX
    socket at its absolute path against Darwin's 104-byte `sun_path` cap — 87 under a session
    prefix, 107 under the corpus's. The red existed *only* at the longer prefix. Cost: `e80c85aa`
    (a correct, unrelated cc-queue fix) reverted as `f323b427`, restoring a permanent red it had
    just fixed; re-landed by `12549d8b`. N=2 with the `2026-08-01T21:00:00Z` flakes.jsonl row.

  **Why the first two do not subsume the third.** They make the walk *refuse* — the safety half.
  But a probe that cannot reproduce still names nobody, so an env-dependent red would stay
  permanently **unattributed**: safe, never diagnosed, and re-derived by hand every cycle. The env
  fix is the *attribution* half. It also lands at one site for three: both new guards re-run the
  same `$runner`, so they had been confirming and floor-checking at the wrong prefix too.

  **The general rule** (memory `adjudicator-env-must-match-the-measurement`): before trusting any
  adjudicating run — bisect, retry ladder, re-run, control — diff its environment against the run
  it is adjudicating. If they differ on an axis the failure depends on, its verdict is an artifact
  of the difference. And ask both directions: *can this instrument return each verdict at all?*
  A bound under what it re-runs can only CONVICT; a probe that cannot reproduce can only EXONERATE,
  which here meant convicting the endpoint by default.

  **Method note — a control caught a vacuous test before it landed.** The first fixture for
  "an all-GOOD walk convicts nothing" used a ONE-commit range and *passed against the unfixed
  script*, proving nothing. Measured against git 2.54.0: at range 1 git probes the asserted-bad
  **tip itself**, so an all-GOOD walk there already errored `was both good and bad` and named
  nobody; only from range ≥2 does git probe strictly inside the range, never test the tip, and
  converge on it unexamined. A RED-proof that is skipped can encode the wrong regime entirely and
  still look like evidence.
- 2026-08-02: **this design was implemented a second time, in `reso-management-app`, and
  the second run found two defects in ITS OWN copy of our requirements — both worth
  auditing here.** Record + diagrams: `docs/plans/DEPLOY_DECOUPLING_V2.md`; full build log:
  `reso-management-app/docs/plans/LAND_SHIP_V2.md`.
  1. **R7 re-entered through the SCHEDULER.** reso implemented "a non-verdict is never a
     RED" against exit codes, then ran the suite under `nice -n 19` + `taskpolicy -c
     background` — and vitest's per-test/per-hook budgets are *wall clock*. Its first real
     verifier run stamped the trunk RED with 12 failed files, 11 hook-timeouts + 1
     test-timeout and **zero assertion failures**, on a tree green at normal priority.
     Neither the exit-code map (`124/137 → hung`) nor CI retries catch it: the runner exits
     1 for a timeout and a regression alike, and all attempts lose the same race.
     **⚠️ Our exposure, measured 2026-08-02 rather than assumed:** this verifier runs the
     same band (`postland-verify.sh:185-193`), but our suites are **bats, which has no
     per-test deadline** — so the framework-level version of the bug cannot occur here.
     What *can*: **16 of 269 `tests/*.bats` files hardcode a `timeout N`, the shortest at
     2-3s.** A 2s budget inside a background-clamped, loaded box is a scheduling race, not
     a correctness check. Not yet observed failing here, so this is recorded rather than
     pre-emptively rewritten (Fix Observed Problems) — but it is where to look first if a
     verifier RED ever lands with no assertion failure in its output.
     The rule: deprioritising a process implicitly re-specifies every timeout inside it,
     so the caller choosing the band must choose the budget (widen-only multiplier).
  2. **A fail-closed verdict that discards its evidence is a wedge, not a verdict.** reso's
     verifier sent suite output to `/dev/null`, so a RED that pinned the deploy shut had no
     recoverable reason — diagnosis meant re-creating the cell by hand. No-verdict says
     "unknown"; evidence-free-RED says "guilty" and destroys the appeal. Worth checking
     every stamp emitter here for the same discard.
- 2026-07-28: v1's own evolution had already built every v2 component (scoped selector,
  postland net, green-cursor deploy) but kept the verdict on the land path, so each component
  waited on the others' liveness and none could go live — an architecture problem is not
  fixable by component quality. The decisive evidence for the inversion: 37 consecutive
  gate-REDs on a tree that landed 2307/0 first try once load dropped; 22 stamps 0 green with
  deploy-parity structurally unable to pass pre-deploy.

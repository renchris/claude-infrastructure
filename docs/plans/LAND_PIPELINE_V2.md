---
status: in-progress
---

# LAND PIPELINE V2 — first-principles landing architecture

**Scope (frozen):** design + implement the v2 landing architecture so any of 12+ concurrent
sessions lands a commit to origin/main in seconds-to-minutes, 24/7, with no multi-hour queues
or wedges: corpus-free fast land lane · singleton background trunk verifier (fresh worktree,
corpus partition, auto-revert) · autonomous green-cursor deploy with post-deploy host checks ·
activation consolidated to one operator command; tests green; landed via project /ship.

Status: DESIGN 2026-07-28 · owner session e891e080 · branch `land-pipeline-v2`

---

## Phase 0 — Agent Team Orchestration

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

---

**2026-07-28 archaeology deltas (evidence pack: docs/research/land-pipeline-v2-research-2026-07-28/):**
- **0-green re-localized (supersedes the restart brief's §6 cell suspicion):** clean-room full
  corpora fail on exactly ONE suite — tests/test-hermeticity-lint.bats:22, a whole-tree
  assertion that passes standalone and fails mid-corpus (2,085/1 and 2,242/1; backlogs
  b59eb997d035, b4e49b4b5014; "the other 6 convicted suites are spurious" — their
  convictions were verdict-path artifacts). §4.2 amended: manifest gains that suite as a 7th
  entry AND the verifier runs scripts/test-hermeticity-lint.sh + test-walltime-lint.sh
  standalone pre-corpus (whole-tree strict, bounded, named RED on failure).
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
| Load-kill → CUT misread RED → dispatcher retry loop | land smoke: cut ⇒ proceed; verifier keeps CUT/HUNG non-verdicts; nothing retries a corpus per land |
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

## Learnings (accumulate; never delete)

- 2026-07-28: v1's own evolution had already built every v2 component (scoped selector,
  postland net, green-cursor deploy) but kept the verdict on the land path, so each component
  waited on the others' liveness and none could go live — an architecture problem is not
  fixable by component quality. The decisive evidence for the inversion: 37 consecutive
  gate-REDs on a tree that landed 2307/0 first try once load dropped; 22 stamps 0 green with
  deploy-parity structurally unable to pass pre-deploy.

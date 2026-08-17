---
status: open
created: 2026-08-16
supersedes-for-operation: BACKLOG_SELF_DRAINING_2026-08-12.md (its status log remains the evidence record), CLOUD_BACKLOG_PIPELINE.md (its architecture remains the cloud-lane reference)
---

# BACKLOG_DRAIN_24_7 — SSOT plan: drain cc-backlog to zero, and keep it there

Scope (frozen): root-cause the false "drained to zero" reading; reconcile the ledger to disk
truth with zero lost work; then design, implement, verify, and START a 24/7 two-lane drain
pipeline — Claude Cloud for off-box-eligible rows, ONE self-recycling goal-armed local session
for everything else — with claim-time freshness re-validation and consolidation-before-fire,
such that the backlog trends DOWN (closes ≥ files, week over week) instead of net-filing.

## Phase 0 — Agent Team Orchestration

**Execution locus per wave** (S = dispatched handoff session · T = in-session teammates ·
L = lead-inline):

| Wave | Locus | What |
|---|---|---|
| W-R1 ledger reconcile | **L** | cc-backlog ops only (reap dead leases, per-branch re-land fold, reopen false closes) — no code writes; the lead already holds the forensics. |
| W-R2 stranded-content recovery | **S** | one dispatched session; lands/retires every unlanded branch + refs/land/failed pin by CONTENT verdict. |
| W-P1 pipeline fixes | **S** | one dispatched session per independent fix cluster (dispatcher un-wedge + venue policy; drain-chain self-perpetuation; inflow conservation; premise-pass repair). |
| W-P2 go-live | **L** | the lead fires the cloud lane + the local drain session and verifies first-drain evidence. |

Lead context budget: recycle at ≤60% fill; succession point = any wave boundary; this plan +
the ledger are the full disk state — a successor needs nothing from this context.

## §1 Root cause — why "resolved / drained to zero" was false (2026-08-16 forensics, 8-agent wave)

1. **No whole-backlog zero was ever claimed on disk.** Every zero was per-EFFORT and counted
   only `open`, silently excluding `blocked`: "master-stranded-work at ZERO open" (0 open,
   **4 blocked**, 83e32b012); recycle #9 "master-account-facts at 0 open" (**17 blocked**,
   e830cf050) followed by the session self-certifying *"Good to close — nothing of yours is
   pending"* at 2026-08-16T05:56Z. Blocked rows hold real work: e.g. cb6701bf2217's fix commit
   `674232c8` (wt-cb6701bf2217) is NOT on origin/main.
2. **The drain chain terminated by design this morning.** The local drain (9 recycles, account
   next4, pane 463, 2026-08-13T03:56Z → 2026-08-16T06:45Z) switched recycle #9's goal from the
   global DoD to an effort-scoped condition; the goal cleared, the operator interrupted, and
   **no recycle #10 fired**. Nothing chains effort N's clear into effort N+1's fire.
3. **Net-filing.** +426 rows over 5 days (1,129 filed / 503 closed, 42d27a758); 21-day totals
   1,530 adds vs 1,117 dones. Open trajectory 109 (Jul 26) → **578 peak (Aug 15)** → 568 now;
   never under 188 since Aug 1. Inflow is 70% model-filed — pumped by our own close gates
   (dispatch-assert.sh:191,225 and completion-assert D1/D4 refuse a close until follow-on is
   FILED; the Follow-On Gate governs *pursue*, not *file*) — and 24% ship-land's re-land
   generator (185 rows/7d; 39 duplicates for ONE stuck branch).
4. **The standing dispatcher drains nothing.** launchd `com.claude.dispatcher` runs
   `CC_DISPATCH_VENUE_ONLY=cloud` — explicitly warned against in 42d27a758 ("parks the local
   majority indefinitely", ~86% parked) — and the cloud leg is WEDGED in a claim→spawn-fail→
   release loop on 3 worktrees whose HEAD lacks origin/main (wt-ce7651b02a17, wt-62599dd76a60,
   wt-ee1ac85c6ff6). Fleet-wide: 2,462 claims → 1,543 releases (63%), 507 dones (21%). The
   churn the operator saw as "activity" was claim-thrash, not work: only **12 done→reopen
   cycles ever** — false re-closes are NOT the mechanism; failed claims are.
5. **Instrument residue** (of ~45 documented bugs, most fixed on trunk): find-plan.sh
   plan_status() reads only YAML frontmatter so a finished plan re-mints "advance" rows for
   days (e830cf050); 27 of 628 dones in 7d carry EMPTY evidence; the premise/freshness pass is
   wired (autonomy-sweep, 6h cadence) but has **validated 0 rows in production** (every run
   rc-124 bound-exceeded or rc-0 `note=unparsed`); backlog-ratchet coverage regression is live
   as of this hour (33.8 high-water, assert rc=1).

**One-line answer:** the backlog was never drained — a per-effort "0 open" close (blind to its
blocked tail) was read as program completion, the drain chain had no cross-effort successor, and
inflow (hook-pumped filing + a failed-land minter) outran the drain 4 days out of 5 while the
standing dispatcher was pointed at the ~14% cloud-eligible slice and wedged even there.

## §2 True state — 2026-08-16T09:00Z

- **568 live rows** (269 open · 298 blocked · 1 claimed-by-dead-PID) of 2,149 ever filed;
  1,581 done. Store: `~/.claude/autonomy/backlog.jsonl` (10,550 records, fold = last wins).
- Age: 92 ≤2d · 306 3-6d (the 08-10..13 cohort) · 118 7-13d · 52 ≥14d · oldest 07-20.
- Grouping: 381 rows under the 10 master-* conditions (convergence-deadlock 84 · product-repos
  58 · fire-gate 58 · fleet-footprint 56 · session-lifecycle 41 · enforcing-store 33 ·
  operator-gated 24 · account-facts 17 · verification-integrity 6 · stranded-work 4);
  **ungrouped regrew 7 → 123** (W2 floor is 50 — breached).
- Blocked (298): ~101 operator credential/sudo/auth gates · ~142 carry an executable `run`
  field (one-command operator actions) · 69 legacy re-land rows collapsing onto ~15-20
  branches · 28+6 operator decisions · 11 dependency-holds · 9 stale-marked.
- Validation: 151/568 carry a falsifier (26.6%) · 325 condition-only · 92 never-validated.
- Cloud eligibility: ~8.8-14% of the pile (79% of labelled refusals name THIS MACHINE as the
  work's subject — structurally local). 195 rows unlabelled (venue backfill needed).
- Quota: next4 weekly reset 09:00Z today (fresh); next/next2/next3 at 3%/0%/16% weekly.
  All four accounts auth ok — a 24/7 lane has headroom.
- Consolidation-2026-08-09 verdicts fully applied (117/117 PRUNE, 44/45 MERGE, 110/110 links;
  the 1 regex-missed MERGE (e27d37eac4cd) was later captured by grouping). M1-M6 all reached
  done 2026-08-10, deliberately mass-reopened 2026-08-12 as standing umbrellas.

## §2.1 Execution log (INTEGRATE-only; newest first)

- **2026-08-17 ~08:47Z — recycle #13: `master-verification-integrity` at `0 open / 1 blocked
  (1 operator-gated)`. Every one of the four rows was diagnosed WRONG in its own filing, and each
  was wrong in a different way — that is the transferable finding, not any single fix.**
  Lands: **`60b395923`** (0be0bd2c0b65), **`8c2705236`** (67a7d78c1134), **`d862e80af`**
  (ff3f38d6eeed), **`1d77c6d69`** (6a7eb069e703). **filed 2 / closed 4.**

  **The four rows, and what each filing got wrong.**
  · `0be0bd2c0b65` — ship-land RESTATED two lints' judged populations as hardcoded pathspecs, each
  under a comment asking the next author to keep them in step by hand. Nothing executes a comment,
  and the drift fails silently toward advisory (an own-set that MISSES a file does not error — an
  empty own-set is the legitimate spelling of "this land touches nothing I judge"). Both lints now
  answer `--print-scope`; ship-land DERIVES each own-set via `lint_own_scope`. An unanswerable lint
  is rc 2 → `arm_nonverdict` (GATE_KILLED, exit 9), never an empty own-set — that distinction is
  the same defect by a new route, and it is exactly what a future `|| true` would reintroduce.
  Control 9/9 RED at `33cf5df17`, 9/9 GREEN after. **Measured while doing it: the derivation
  NARROWS permgate's own-set** (its actuation globs, not all of `scripts/*`) — behaviour-preserving,
  since a file the lint does not judge can produce no finding.
  · `67a7d78c1134` — RETRACTED on measurement. The cure (`f1b813f6d`, dead-assertion analyzer +
  ratchet) landed 2026-07-25, **18 days BEFORE the row was filed**. 🚨 **The row's `2,561` counted
  `[[` OCCURRENCES, and the cure idiom `[[ … ]] || false` matches the same grep — so the metric
  could never reach zero and the row could never close by being worked.** Live proof the ratchet is
  enforcing rather than merely present: **it took THIS recycle's own land RED** for 6 dead
  assertions in the suite written above.
  · `ff3f38d6eeed` — the builtin-producer exemption cited `printf '%s' "$VAR"` at 0/200 to exempt
  every builtin. **That row measured a SIZE, not a command word.** Re-measured here: 0/10 at 62 KB,
  10/10 FALSE at 64 KiB and above — the boundary is the pipe buffer. Exemption now discriminates on
  the ARGUMENT (literal exempt, variable/substitution/backtick in scope). Census 30 → 157 sites,
  regenerated ratchet, tree green today. **The selftest's own fixtures were the trap:** g1/g2 were
  variable-sourced builtins asserted GREEN, so left alone the control would have certified the bug.
  · `6a7eb069e703` — the flake's stated hypothesis pointed at a `>(tee)` procsub that `61101fb28`
  had already deleted, and the obvious culprit (`52d93432b`, wait/liveness order) landed **9 days
  before the row was filed**, which is what proved a third cause. It is `exec 9> "$TEE_FIFO"`: a
  blocking `open(2)`, bash's SIGCHLD handler is not `SA_RESTART` and bash does not retry, so a
  background child dying in that window aborts it with EINTR and the next line's `2>&9` kills the
  child subshell before it can exec. **Not a flaky test — every eval-track session launches through
  this wrapper, so an interrupted open lost the SESSION.**

  **THE PATTERN ACROSS ALL FOUR, worth more than the fixes:** a filed row's DIAGNOSIS decays faster
  than its SYMPTOM. Two rows named a mechanism that had already been deleted or fixed; one row's
  metric counted its own cure; one row's cited measurement was of a different variable than the one
  it was used to exempt. Re-validate the premise against trunk before building — `#13` spent its
  first 40 minutes doing exactly that and it retired one row for zero code.

  **Cloud lease, and why the condition sat blocked for 90 minutes.** `67a7d78c1134` was held by a
  **cloud**-venue claim, and `claimer_live` returns rc 2 (UNRESOLVED, correctly — this box's oracles
  cannot see a cloud worker) so the CONDITION lease refused every sibling row. `cloud-return`
  abstained: **HTTP 401, account `next`'s OAuth token expired.** The abstain is right (a sensor that
  could not run is not a verdict) but MUTE — it names the account, not the cause; filed
  `c70f3bd06106`. Landed the VM's work by the local half (`cloud-reconcile` → conflict in the plan
  doc → cherry-picked and INTEGRATED both sections in date order), then closed the row on evidence
  re-derived HERE, independent of the VM's report. Do NOT read the board's `next token stale — heal
  skipped` as a gap: it has a stated policy (a live session owns the token lifecycle).

  **Filed (2):** `5fc8ff411a7c` — six MORE ship-land arms restate a pathspec; measured that none of
  their five lints has a runtime env seam, which is why they were left out of scope AND is the whole
  of their defence; cheap to close now the mechanism exists. `c70f3bd06106` — the mute abstain above.

- **2026-08-17 ~07:45Z — the chain is PROVEN self-perpetuating; recovery is COMPLETE; the cloud
  return path is the last leg (S4 fired, pane 154).**
  DRAIN CHAIN: recycle #10 closed master-account-facts at `0 open / 16 blocked (16
  operator-gated)` and fired #11 unattended; #11 closed master-operator-gated at `0 open / 25
  blocked`, conservation 1/1, and fired #12 — **two unattended boundaries = §5 gate (2) PROVEN;
  all four §5 gates now hold.** Chain lands so far: 9d8965faa+9dd286cb3 (install.sh nested-skills
  converger bug), dc47200cc (reap blocks are machine non-verdicts), f5d4a552e (cc-do was
  discarding .run for all 51 blocked rows), e7640e016. #11 found the operator-gated pile is a
  GENERATOR, not 30 judgment calls; the second generator (desk-land refile loop) is filed
  981a403a05fa as #12's pick.
  W-R2 COMPLETE, zero loss: **12/12 stranded branches resolved** (9 landed: 1817ca740 b4d0a3d0f
  f81808f5b 896973916 764f96963 c037c1aa1 73ceb76aa dbaba83ac 76d5dc100 · 3 retired-by-content
  with evidence); paid clawd-bmo assets landed 1e040c79c; blocked re-land rows **30 → 2**
  (neither ours). T1 reaper verdict confirmed at 39× enrichment + fixture repro, fix LIVE.
  Honest conservation: R2 personally +5 (population still drained); 8 branches needed real fixes
  (4 pre-existing on pristine trunk, each control-confirmed). All 12 shas verified ancestors by
  the lead. Custody for this cwd: fully discharged.
  CLOUD LANE: dispatcher now CREATES sessions that RUN (session_018in35KSYj7iLV7jZCNuCnj, item
  c33f3b1cb278, worker_status=running) — but the RETURN path abstains every poll ("control plane
  unreadable") while the identical read succeeds interactively (same ids, same accounts, rc=0) —
  a daemon-environment failure with a muted callee (cloud-return.sh:156 discards stderr). **S4
  fired** (pane 154, fix/cloud-return-daemon): un-mute the abstain, fix the daemon env, prove
  real return rows; the running session is the live A2 end-to-end probe. Also shed: two
  pane-less claude processes of completed S2/R2 sessions (TERMed after the reap-safe
  certificate: complete + custody discharged + pane gone + work content-verified).
- **2026-08-17 ~07:40Z — recycle #12 closed master-stranded-work at 0 open / 5 blocked (5
  operator-gated). Filed 2 / closed 4.** The live retry burn is DIAGNOSED and its cause is
  landed, after 789 `refs/land/failed/*` pins that had only ever been COUNTED.
  **Cause 1 — the lander threw away a resolution git had already applied (fixed, `b5f685081`).**
  Every retry died at ship-land **exit 5 = rebase conflict**, in 2-4 s, `head:"?"` (land.log,
  06:18Z batch); the driver is `cloud-reconcile.sh:559`, which relaxes
  `SHIP_LAND_SESSION_BRANCH_RE` so `claude/*` gets past desk-land's session-branch guard.
  Replaying one by hand showed why the count grew instead of the queue draining: `git rebase`
  exits non-zero the moment a conflict STOPS it, *including* when `rerere.autoupdate` (a global
  setting here, and referenced in NO script in the tree before this) has already replayed a
  recorded resolution and staged every path. `claude/fire-20260816T094145Z-41172-1` stopped with
  both conflicts staged, **zero unmerged paths and zero markers, and rebased clean in ONE
  `--continue`.** A retry can never re-apply a resolution the lander discards — which is exactly
  why 112 attempts on one branch changed nothing. `rebase_onto_trunk()` now asks whether anything
  is ACTUALLY unresolved instead of reading the exit code, and refuses in BOTH directions
  (unmerged paths keep exit 5; staged conflict markers refuse rather than land `<<<<<<<` on
  trunk). Measured while writing it: rerere itself *cannot* reach that second arm — it records
  ZERO postimages when markers remain — so the arm is fail-closed cover for a non-rerere stager
  and `tests/land-rerere-continue.bats` pins the reachable population instead
  (memory: cap-whose-population-is-empty). Mutant-attributed: only the rerere case reds.
  **Cause 2 — the queue was re-landing work that had already landed better.** All three demoted
  re-land rows retract on same-moment content evidence, none of them by commit count:
  `e96021115661` SUPERSEDED (trunk carries `--idle-scoped` ×5 and `mailbox_wake_idle_scoped` ×2,
  and trunk's files are LARGER than the branch's — 864/767, 518/380); `12f5beab9361` SUPERSEDED
  (trunk has the `wt-slug` pattern, the SIGPIPE fix as a variable capture at
  `test-hermeticity-lint.sh:1074` with the branch's own rationale at `:1061`, and now a
  systematic `scripts/pipefail-sigpipe-lint.sh` ratchet for the whole class); `1201e5884d2c`
  ALREADY LANDED 06:19:16Z, head `55e473a8` verified an ancestor of origin/main. **`git cherry`
  printed `+` for all of them** — it compares patch-ids and is blind to a superseding LARGER
  version (memory: landedness-over-commits-is-blind-to-staged-content), which is how #11's
  content adjudication could be right about the commit and wrong about the work.
  **Question 2 stays the operator's, and NOT because it is a value call in the abstract.**
  `ship-land.sh:897` files via the `needs` verb, which files ALREADY BLOCKED, so the row lands on
  the operator platter; these rows need a rebase, a supersession check or a gate fix — no
  credential, no GUI, nothing physical — so they fail CLAUDE.md's operator-step test and *should*
  be agent work. The one-verb fix is a TRAP: the recurrence brake that collapses one stuck branch
  into one row lives in `needs` **and nowhere else** (`cc-backlog --help`:462), so swapping in
  `add` would drop it and resurrect the 41-rows-for-one-branch explosion the brake exists to
  stop. Blocked as `981a403a05fa` with both options and the recommendation: **`needs --role
  agent`** — keep the brake, change the audience.
  Also filed: `44750ff72ae7` — `validate-bash`'s `git add -f` rule DENIED a plain
  `git add f.txt` in a fixture repo mid-investigation; same denylist-by-spelling class the
  memory of that name already records, and it now has a concrete innocent to pin as a control.

- **2026-08-17 ~05:30Z — W-P2 GO-LIVE: the drain chain is running.** (S3's own landed entry
  below carries the full root cause; this entry is the go-live record.) **First GREEN since
  08-15: `416a7191dea8` (475 suites, failing=[], run_s 2374); deploy-live ADVANCED on the
  VERIFIED tier — `origin/main..live = 0`.** Every W-P1 fix is now LIVE.
  Production evidence: the dispatcher's first live passes turned the stale-worktree case into
  claim→refuse→BLOCK (one cycle, wt-02ba4e52389a, 05:01Z) with zero churn on the three old ids;
  a cloud admission is in flight (row e2af8839be87, claim 04:46Z) = the A2 end-to-end probe;
  the lead's postland-red page at 6200a8698 was A/B-exonerated (findings=1 identically at
  parent/self/main). The rc-124 elapsed-discriminator content is on main (cherry `-`; branch
  sha 52e388369).
  **LOCAL DRAIN CHAIN FIRED: recycle #10, pane 131, worktree drain/recycle-10** — brief
  /tmp/fire-drain-recycle10.txt per §4.1 (chain constraint IN the goal; smallest-effort-first
  from the live fold; falsifier-first row picking; conservation printed per recycle; true-zero
  termination clause). §5 gate status: (1) convergence ✓ · (3) freshness ✓ (138 validated /
  5 closed in production) · (4) conservation structural in the goal · (2) the unattended recycle
  boundary proves on the chain's FIRST self-recycle (#10→#11) — watch for it. R2 (pane 106)
  still out: 7/12 stranded branches landed, T2 continuing; ledger shows rows closing with
  "re-land of the stalled cloud session's …" landed evidence.
- **2026-08-16 ~21:53Z — W-P1/S3 landed: the verifier was blocked by a FALSE prelint red, not by
  the ladder bound this wave was briefed against.** Landed `6ce67de91` · `e334bf6c1` · `2f84bf743`
  (content-verified on origin/main, 3 paths). The next sweep ran the corpus at 21:56:12Z —
  475 suites at `2f84bf7437fb` — the first corpus since 11:35Z.
  - **Root cause.** From 11:35Z every sweep logged `corpus SKIPPED — pre-corpus whole-tree lint(s)
    already red`, so **no GREEN stamp could exist at all**, deploy-live fell back to its degraded
    age-authorised path, and the bisect elected innocent lands as culprits (backlog `354c73ebd400`).
    The single finding was `ship-land.sh:3680 BRANCH — assigned inside a $( ) child`, chained to
    write_decision_packet ":584 assigns BRANCH". Line 584 is `ID="$id" BRANCH="$branch" … python3`
    — a command-PREFIX env assignment, which bash discards after the command returns (MEASURED for
    an external command AND for a function: `f(){ :; }; V=inside f` leaves V unset). It assigns no
    global; the trap's BRANCH was never stale. The lint's prescribed remedy — "return through a
    global out-parameter" — would have introduced the very global the lint exists to forbid.
  - **The brief's premise was refuted by measurement, twice.** `ladder UNPROVEN for
    tests/autonomy-sweep.bats — our own 5400s bound fired` preceded 16 cuts, but retry_once has
    TWO bounds (FILE_TO=300s per named test · RETRY_TO=5400s whole-file fallback), rc 124 is
    identical from either, and the message named RETRY_TO unconditionally. **A 5400s bound cannot
    fire in the runs that logged it — `run_s=3364` and `run_s=3538`.** The suite is not slow: at
    the ladder's exact band (`nice -n 5`, `taskpolicy -c utility`) it measures **77.09s /
    55-of-55** in-worktree and **69.79s / 55-of-55 in a PRISTINE detached worktree at origin/main
    under live contention**, slowest case 4159ms. A whole session was dispatched against a
    90-minute suite that does not exist. The bound is now an out-parameter named per leg, with one
    test per leg (anchor-checked: both fail against the pre-fix line, pass after).
  - **Also on the critical path:** `--mutants` scored the detector BLIND for obeying its own
    contract — its picker chooses a global the trap READS, while the detector also requires a
    DESTRUCTIVE use — making tests/subshell-cleanup-lint.bats a permanent red the corpus could
    never clear. The lint now arbitrates its own case through `--loose`; blind 2 → 0, testable
    10 → 11.
  - **Learning (generalisable).** A guessed figure in a cut message is not cosmetic — it is the
    rung the next reader stands on, and here it set an entire wave's brief. Ask WHOSE bound fired
    before sizing it (memory: *exoneration-bound-must-fit-what-it-bounds*,
    *repeat-verdict-indicts-the-diagnosis*). And a lint whose prescribed remedy manufactures its
    own defect class is worse than a silent one.
- **2026-08-16 ~20:30Z — W-P1 returns collected; convergence is the last gate; S3 fired.**
  S1 COMPLETE: C1 `46a86deb7` (re-land retry runs TRUNK's pipeline via throwaway origin/main
  worktree — extract-to-temp and checkout-into-tree both proven unworkable), C2 `944abba49`
  (cc-discover screens plan-open candidates through plan-phase-scan --falsify pre-mint,
  fail-open), C3 `672f34757` (done-with-empty-evidence warns, `verdict=done-without-evidence`);
  7 regression cases red→green; conservation 0 filed / 1 closed.
  S2 COMPLETE with BOTH production proofs: premise pass beat
  `premise_rows_validated:138, closed:5` — first non-zero in its production history (root cause
  refuted the brief: the pass runs at UTILITY, and 'unparsed' was `_die_open` exiting 0 with
  `verdict=unknown` on stdout); dispatcher no-reclaim proven on two consecutive LIVE passes,
  zero claim→release on the 3 wedged ids, "refusing to fire" lines gone (works while live layer
  is stale because `blocked` is a STORE state). The two content-holding worktrees are BLOCKED
  with exact salvage commands (row `925d843f6665`); wt-c07fb00eb9b6 was ff'd + fired in prod.
  R2 T1 LANDED `a87f32c66` — the SIGTERM-143 land killer was cc-reaper's garbage arm (land path
  not whitelisted + a vacuous `^bash$` kill-time re-check defeated by 41-min PID wraps), 39×
  reaper-shadow correlation on lands. **T1 also REFUTED the lead's postland hypothesis**: the
  postland cuts are 21 reaper / 17 sig9 / 18 machine-pressure / 35 unnamed / **16 = postland's
  OWN 5400s ladder bound firing on tests/autonomy-sweep.bats re-runs — including the last 5
  consecutive cuts**. That ONE suite-vs-bound mismatch is now the sole gate on convergence
  (live layer 25+ behind, every fix above landed-but-not-live). → **S3 fired** (pane 111,
  branch fix/postland-ladder-bound): reproduce the ladder's exact re-run, name the tail cases,
  fix by mechanism, prove one REAL postland verdict + a deploy-live advance.
  R2 T2 in flight: `1817ca740` (40416-1) + `b4d0a3d0f` (64880-1) landed, 7 branches to go.
  Custody: this cwd holds only fire-r2-recovery open; ~10 stale `cloud-session_*` debts from
  the dispatcher's old cwd are A2 evidence (cloud sessions that never returned) — cloud-lane
  cleanup item, not this session's.

- **2026-08-16 ~09:30Z — waves fired.** W-P1/S1 (inflow C1+C2+C3) → pane 105, branch
  fix/backlog-inflow-c123; W-P1/S2 (C4 premise-pass + A1 dispatcher un-wedge) → pane 104, branch
  fix/backlog-machinery-c4a1; W-R2 (recovery) → pane 106, branch fix/backlog-recovery-r2. All
  next3, goals armed+verified, notify-back custody to pane 102 (lead). First fire attempt was
  REFUSED by the capacity gate at 2.12/core — the fleet's load is system indexing + daemon
  fork-storms, and the wedged dispatcher is part of it; admitted at 1.94-1.99/core.
- **2026-08-16 — W-R1 lead ops done:** stale-claim `reap` ran (0 reopened — the one dead-PID
  claim 1d25b0e07668 is venue=cloud, so host-local oracles correctly decline it; lapses on lease
  TTL). b59eb997d035 re-asserted done with CORRECTED evidence (the case is not "gone" — it lives
  rewritten at tests/test-hermeticity-lint.bats:151 citing the row; substance stood, prose was
  false). **A3 done:** `cc-venue run --apply` over all 269 open rows — **10 cloud / 259 local**
  (160 ineligible-box · 23 spawn-rail · 22 branch-banking · 18 offbox-lane · 17 visual ·
  12 deep-history · 5 premise-suspect · 1 github · 1 premise-superseded). The cloud lane's real
  slice of TODAY'S pile is 10 rows (3.7%), not the planning-era 8-14%: Lane B is the drain.
- **2026-08-16 — stranded-work enumeration complete** (9th forensics agent): 543
  refs/land/failed pins → 333 landed-by-content · 131 REAL-UNLANDED collapsing to **7 fire
  branches** · 79 ambig. **12 claude/fire-* branches carry ~2,000 genuinely-unlanded lines**;
  5 of them have NO protecting row; 14 blocked rows guard already-landed content; 1
  false-retraction (93323-1: rows auto-closed on a retraction a LATER amend invalidated).
  Live bleed: every retry dies uniformly `SIGTERM-143` (fresh pins 08:35-08:55Z today) —
  hypothesis: bin/cc-reaper's orphan-bash arm (ppid-1 bash ≥600s off-whitelist) kills detached
  lands that take 20-80 min. W-R2's T1 verifies against the reaper log before fixing.

## §3 Reconciliation worklist (W-R1 + W-R2) — zero lost work

R1 (**L**, ledger ops):
- R1.1 Reap the dead-PID lease: 1d25b0e07668 held by `Chriss-MacBook-Pro-3-75161` (PID dead
  since ~07:43Z). Mechanism: cc-backlog's stale-claim reap (by=cc-backlog-reap precedent).
- R1.2 Per-branch fold of the 69 legacy re-land rows: keep ONE row per branch whose content is
  genuinely unlanded (S3 audit precedent: 34 of 43 protected real work; 39-row bulk-close
  precedent fc4db521/aa1886a5e). Verdict per branch by CONTENT: `git merge-base --is-ancestor`
  on EVERY pinned sha + `git cherry` requiring no `+` (bug-4-corrected arm).
- R1.3 Reopen the one proven-false close: b59eb997d035 (evidence claims a test case is "GONE";
  tests/test-hermeticity-lint.bats:151 still carries it) — reopen with the refutation as
  evidence, or re-close on TRUE evidence if the underlying work is genuinely moot.
- R1.4 Audit the 27 evidence-less dones (7d window, e.g. c864e1b81989): identify the writer,
  spot-verify 5 by content; file the "done requires --evidence" gate as a P1 item (→ P1.4).
- R1.5 Regroup the 123 ungrouped rows (sweep already detects; run the grouping pass to fold
  them under masters/minor groups so the drain walks efforts, not strays).

R2 (**S**, content recovery — the full stranded-work enumeration is the dispatched session's
first deliverable; forensics agent for this axis died mid-run and is being re-run):
- R2.1 Every `refs/land/failed/*` pin: verdict LANDED / REAL / UNKNOWN by content (slash→dash
  sanitisation trap applies); land or retire each.
- R2.2 Known-stranded: wt-cb6701bf2217 (`674232c8`, unattended-path-lint work, parked 6d behind
  trunk-red row 11d3a3cd8507); the 3 dispatcher-refused worktrees (rebase or retire).
- R2.3 Close each recovered branch's re-land row(s) with the landed sha as evidence.

## §4 Pipeline architecture (W-P1)

**Lane A — Claude Cloud, 24/7, for the off-box-eligible slice (~8-14% + backfill).**
Already built end-to-end and launchd-live: cc-venue → cc-dispatch (300s) → `cc-offload up
--via api` (POST /v1/sessions) → custody/goal/wake → cloud-return.sh auto-land →
cloud-refusal-route.sh. Fixes required before it counts as a lane:
- A1 **Un-wedge**: clear/rebase the 3 refused worktrees; add the rule "a claim that cannot
  fire because its worktree HEAD lacks origin/main FIRST rebases or retires the worktree —
  never re-claims into it" (the retry loop is the defect; 63% release rate is its fleet echo).
- A2 **Prove ONE dispatcher-driven cloud land end-to-end** (session pushes a ref; cloud-return
  lands it; row closes on content). The lane has never once done this — the only session ever
  created sat NOT-STARTED past its boot budget. Until this probe passes, cloud is a paper lane.
- A3 **Venue backfill**: cc-venue the 195 unlabelled rows so the eligible slice is fully known.
- A4 Keep `CC_DISPATCH_VENUE_ONLY=cloud` on the DAEMON (it is the cloud lane; the local
  majority is Lane B's job — the 42d27a758 warning is answered by Lane B existing, not by
  flipping the daemon to local and colliding with the drain session's leases).

#### A2 forensics 2026-08-17 — the return path is NOT the blocker; the LAND is (W-P2/S4)

**The premise this session was fired on is refuted, and the refutation is the finding.** The
brief read *"every daemon poll abstains"* and posed the question as a daemon-environment defect
— keychain unreadable from launchd, PATH/python3 divergence, config-dir resolution. All three
are false, and the ledger the brief quoted is what falsifies them:

| Hypothesis | Discriminating measurement | Verdict |
|---|---|---|
| the daemon's env cannot read the control plane | a probe launchd job with the sweep's OWN `ProgramArguments` (`/bin/zsh -lc`, `ProcessType Background`, same PATH export) ran the exact `cloud-create-api.py --account next4 --verify …` call: **rc=0**, `{"worker_status":"idle"}` | **REFUTED** |
| the login keychain locks under launchd | `security show-keychain-info login.keychain-db` → **`no-timeout`** — it never auto-locks | **REFUTED** |
| every poll abstains | `return.jsonl` by hour: 2026-08-17T00 = **109 real rows vs 6 abstains**; T05 = 73 vs 0; T06 = 14 vs 13. Abstains and real reads **interleave inside the same hour** | **REFUTED** — the brief sampled one abstain burst at the file's tail |
| the abstain bursts are a box-wide network loss | the two abstain classes (`control plane unreadable` / `state UNKNOWN` = `ls-remote failed`) occur in **disjoint minutes**, never the same pass | **REFUTED** |

What the bursts *are* stays open, and is now self-naming rather than re-derivable: 13 abstains
spanned ≤2 s ⇒ **~0.11 s each against a measured 0.52 s for a real API round trip**, i.e. an
instant local failure, hitting all four accounts at once and self-clearing by the next pass.
That is as far as history can be read, because the sensor recorded no cause — which is A2's
first fix and is landed (below).

**What actually blocks A2: 39 sessions are stuck in LAND REFUSAL, re-refused every pass.** The
sweep reads the control plane, computes RETURN-READY, calls the lander, and the lander says no —
which is why ~10 custody debts sit open for days (custody stays OPEN on an unlanded result *by
design*) and why `land-refused` is the ledger's dominant outcome (102 rows in one hour). The 39
artifacts classify into four causes, and **none is a cloud-return defect**:

| n | rc | cause | owner |
|---|---|---|---|
| 15 | 65 | the cloud branch is **CHECKED OUT in a stale worktree** (e.g. `/private/tmp/wt-land-31568-1`) — cloud-reconcile refuses to force, correctly | **A1** (reap the stale `wt-land-*` worktrees) |
| 18 | 70 | **rebase CONFLICT** on a plan doc the VM edited days ago (e.g. `BACKLOG_SELF_DRAINING_2026-08-12.md`) | **W3** refusal routing — a genuine conflict a VM must resolve |
| 5 | 70 | `mktemp: mkstemp failed on …/postland-run.VRdnYH/…` — the re-author step inherited a **TMPDIR pointing at a reaped postland-verify scratch dir**, so `cloud-reconcile.sh:424` could not compose the rewritten messages | a real, separate bug: the re-author must not trust an inherited TMPDIR |
| 1 | 143 | killed from outside — already handled as a non-verdict | — |

**Then the instrument fired, and both remaining causes named themselves within the hour.**

**(1) The abstain is an EXPIRED OAuth ACCESS TOKEN on one account — not the daemon's
environment.** The first live abstain after the fix landed, verbatim from `return.jsonl`:

```json
{"ts":"2026-08-17T07:58:12Z","id":"session_018in35KSYj7iLV7jZCNuCnj","outcome":"abstain",
 "why":"control plane unreadable",
 "err":"cloud-create-api: HTTP 401 from /v1/code/sessions/session_018in35KSYj7iLV7jZCNuCnj
        {\"type\":\"error\",\"error\":{\"type\":\"authentication_error\",
        \"message\":\"OAuth access token has expired. Re-authenticate to continue.\"}}",
 "rc":"4","account":"next"}
```

Discriminator, same call, same second, four accounts: **`next` → 401; `next2`/`next3`/`next4` →
404** (authenticated, and correctly reporting a session that is not theirs). So this is one
account's token, not a daemon-environment property — which is what every earlier hypothesis had
assumed. It also explains the bursty, all-account, self-clearing history: **the cloud lane's
token is refreshed only when a LOCAL Claude Code session on that account happens to take a turn**,
so an account whose session sits idle starves the cloud reads until something wakes it.
`cc-relogin next` REFUSES, and the refusal is principled — `next` has a live session, and a
relogin that rotates the token out from under a running CC has its rotation discarded, which *is*
a logout. Filed for the operator as `8636b8f829fe`, together with the second-order gap it exposes:
**cc-relogin's health gate keys on the LOGIN deadline (319 h away ⇒ "healthy") and is blind to an
expired ACCESS token**, so the board will keep prescribing "no re-auth needed" while every cloud
read 401s. **A2 is therefore blocked on exactly one named thing**, and the ledger says so itself
rather than needing this analysis re-derived.

**(2) The pass writing to the live store was never the daemon — it was postland-verify's
throwaway worktree.** Caught in the act at 2026-08-17T07:56Z, holding the live `.return.lock`:

```
RUNNING: /Users/chrisren/.claude/autonomy/postland/wt-run-61088/scripts/cloud-return.sh
```

The gate meant to stop exactly this read `case "$0" in "$_cc_cfg"/*`. postland-verify mints its
worktrees **under the config dir** (`$_cc_cfg/autonomy/postland/wt-run-NNNNN/`), so a verifier
copy's `$0` matches that prefix just as well as the deployed copy's does — the discriminator could
not discriminate, and **every postland run of this suite has been landing branches, closing backlog
rows and spending quota against live state.** This is the *same* incident the guard's own comment
records from 2026-08-11 (four concurrent passes out of `wt-run-54668`); it was never actually
closed, because the guard written to close it tested a prefix that contains its own harness
(memory: `guard-refusal-fires-on-its-own-harness`).

Three previously-loose facts collapse into this one cause: the refusal artifacts dying on
`mkstemp … postland-run.VRdnYH/…` (a verifier's private TMPDIR, reaped when its run ended); the
**absence of any `cloud-return` row in the sweep's own IDL journal** while `return.jsonl` filled up;
and the bursty, non-300s cadence of the ledger. The arm that should have caught it was a **grep for
`case "$0" in` over the source text**, which stayed green the whole time — text cannot show which
paths a pattern admits. The gate is now an exact-path comparison, and the behavioural arm runs the
real script from both locations with a recording stub plus a positive control.

**Landed this session** (`54aa27cd6`, content-verified on `origin/main`): the abstain row now
names its cause. `worker_status()` ran the status bin under `2>/dev/null` and folded every
failure into rc 2, so **384 rows read exactly `{"why":"control plane unreadable"}`** and could
not tell rc 127 (no python3) from rc 3 (a locked keychain) from rc 1 (an expired grant) — three
unrelated repairs. Capturing stderr alone would have changed nothing: the caller wrote
`ws="$(worker_status …)"`, a command substitution, so any global the sensor set died with that
subshell. The answer therefore moved to `WS_STATUS` and the sensor is now called **bare**, which
is what makes `WS_ERR`/`WS_RC` reachable at all. Rows carry `err`, `rc` and `account`; two bats
arms pin it, both verified to fail against the pre-fix artifact replayed from git.

**Lane B — ONE local self-recycling goal-armed session, 24/7, for everything else.**
The proven local-drain design (9 recycles) plus the one missing property — self-perpetuation:
- B1 **Chained recycle, no terminal goal.** Per recycle: goal = effort-scoped, provable,
  quotable (*"<current effort> reaches 0 open — proven by cc-backlog list --open --json | jq
  … printing 0; then fire the next recycle with handoff-fire --recycle"*). The recycle FIRE is
  part of the goal's constraint clause, so a cleared effort cannot strand the chain; the
  session picks the next effort smallest-first from the live fold (next: enforcing-store 33 →
  session-lifecycle 41 → fleet-footprint 56 → product-repos 58 → fire-gate 58 →
  convergence-deadlock 84 — re-read at each boundary; read master-convergence-deadlock's plan
  note before opening it).
- B2 **Freshness at claim, mechanically**: before working any row, run its falsifier against a
  pristine origin/main worktree (exit 0 ⇒ retracting → close on that evidence, don't build);
  re-measure dated titles; adjudicate landedness by content. This is the operator's
  "no stale ticket fires against an updated repo" requirement, and it is the drain's proven
  row-picking mechanism — keep it verbatim.
- B3 **Account rotation**: fire with `--account auto` (claude-accounts --rank general) at every
  recycle so the chain survives any one account's weekly cliff; next4 is fresh as of 09:00Z.
- B4 **Blocked-row platter**: the ~142 one-command operator rows render via the existing
  cc-do/operator-readout rail at every drain close; the drain never burns turns on them.
- B5 **Conservation**: each recycle reports filed vs closed and must close ≥ it files
  (42d27a758's named-but-never-implemented rule) — enforced in the recycle brief + goal
  constraint ("do not end the recycle net-positive on filings").

### §4.1 Lane B recycle-fire template (SSOT — the drain session regenerates its per-recycle brief from THIS)

Fire command (from any claude-infrastructure checkout; the drain session runs this ON ITSELF at
every pause-point — end of effort, ~60% context fill, or any natural seam):

    bash scripts/handoff-fire.sh --recycle --prompt-file /tmp/fire-drain-recycle<N>.txt \
      --account auto \
      --goal '<effort E> reaches 0 open rows (blocked tail reported, not hidden) — proven by
      cc-backlog list --open --json | jq output printed showing 0 open for condition <E>, plus the
      filed-vs-closed tally for this recycle (closed >= filed); then recycle #<N+1> is FIRED
      (handoff-fire --recycle) as the LAST action and its engagement line is printed; do not end
      the recycle net-positive on filings and do not close any row without same-moment content
      evidence'

Brief body invariants (regenerate the specifics each recycle; never drop these):
1. Pick the smallest live master-* effort from the CURRENT fold (never a remembered order);
   claim its CONDITION (one lease covers the group).
2. Per row: run the stored falsifier against a pristine origin/main worktree FIRST (exit 0 =
   retracting → close on that evidence); re-measure dated titles; landedness by CONTENT.
3. Close line format: `<effort>: N open / M blocked (K operator-gated)` — a zero without its
   blocked tail is the exact defect that produced this plan (§1.1).
4. Conservation: close ≥ file, printed in the close.
5. Operator-gated rows: platter via the cc-do/operator-readout rail, never burn turns on them.
6. THE CHAIN IS THE DELIVERABLE: firing recycle #N+1 (or, at true zero live rows, writing the
   chain-complete entry in this plan) outranks finishing one more row. A recycle that runs out
   of context mid-effort still fires its successor with the effort in-flight.

**Inflow control (the other half of "drain"):**
- C1 re-land minter: pre-fix-branch-bytes leak — the retry executes the BRANCH's old
  ship-land.sh (`git checkout $BRANCH && bash scripts/ship-land.sh`); make the retry command
  invoke TRUNK's ship-land against the branch so aa1886a5e's brake + 40613b786's rc-5 screen
  actually govern retries of old branches.
- C2 find-plan.sh plan_status(): read the status LOG/body, not frontmatter alone — kills the
  4-day "advance a finished plan" re-mint class.
- C3 done-with-evidence: `cc-backlog done` warns (then refuses, ratcheted) on empty
  --evidence.
- C4 premise-pass repair: it has validated 0 rows ever (420s rc-124 + `unparsed` on the one
  completing run). Fix the bound to fit the Background band it runs in (bound-fits-the-band)
  and the --json parse; prove ≥1 production pass that RECORDS validations.

## §5 Verification before mass fire (W-P1 exit gate)

1. Cloud probe: one real row through Lane A end-to-end (ref pushed, landed by content, row
   closed). 2. Local probe: one recycle boundary crossed unattended (effort clears → next
   recycle fires itself, goal re-armed, verified in the fired transcript). 3. Freshness probe:
   one stale row auto-closed by falsifier-retraction at claim. 4. Conservation visible: the
   recycle's close prints filed/closed. Only then W-P2.

## §6 Operating invariants

- The drain's unit of "done" is CONTENT ON TRUNK (ls-tree/diff), never a count, never a stamp.
- "0 open" is never reported without its blocked tail: the drain's close line format is
  `<effort>: N open / M blocked (K operator-gated)`.
- The chain is alive ⟺ a fire-drain-recycle-N brief younger than 24h exists OR a drain session
  holds a live lease — checked by autonomy-sweep; a dead chain files ONE condition-keyed row
  (`local-drain-chain-dead`), never a duplicate storm.
- Weekly report: adds vs closes; net-positive week ⇒ the INFLOW list (C1-C4) gets the next
  fix, not more drain horsepower.

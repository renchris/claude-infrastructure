# Commit → land → deployed-live at 15+ sessions — is the architecture at its 100th percentile?

**Scope (frozen):** investigate the 100th-percentile implementation for the architecture and
workflow of claude-infrastructure committing and landing to deployed live, if decision
perfection is not already reached; ground it in the measured congestion from 15+ concurrent
sessions; end in a verdict (certify the current architecture OR specify the target + gap list),
persisted here and landed. (Goal set 2026-08-10; operator's live example: a land alive,
correctly queued behind three peer sessions' lands on the machine-wide lock, waiter armed,
inside a 1h8m turn — "contention, not a fault".)

Status: INVESTIGATION OPEN 2026-08-10 · owner session ff519bfd · branch
`research/land-perfection-2026-08-10`

---

## 0. Method

Ten-subagent research wave (research-subagents discipline: 9 axes, 2 adversarial slots on the
frontier tier, decomposition-critic gated). Lanes: A land-path mechanism · B land.log
quantitative · C in-repo queue prior art · D plan-corpus decision record · E landed→live
convergence · F session-side wait cost · G1 steelman-current · G2 hostile-reviewer ·
H external merge-queue SOTA · I branch/worktree population. Lane artifacts live in the firing
session's scratchpad (`land100/*.md`); every load-bearing number is reproduced here with its
command so this doc stands alone.

Scale facts at open (measured 2026-08-10, shared checkout):
- 562 commits landed on origin/main in 7 days; 124 in the last day
  (`git log origin/main --since='7 days ago' --oneline | wc -l`).
- 493 local branches; ~130 registered worktrees (`git worktree list`).
- Land ledger `~/.claude/land.log`: 2,914 attempt rows since 2026-07-11
  (JSONL: ts · repo · branch · wait_s · hold_s · exit · pid).

## 1. The bar — what "100th percentile" means for this pipeline

A candidate architecture is judged against all seven; the current one is certified only if no
candidate dominates it on any criterion without losing on another:

1. **Sessions never wait on landing.** A session's scarce resources are its context window and
   its turn; queue time may exist, but it must not be spent inside a session's turn or window.
2. **Trunk safety by construction.** No dropped commits (the 2026-07-11 `dfacccd` rebase-drop
   class), content-verified lands, no red gate laundered — preserved from v2.
3. **Failure paths are durable and attributed.** A land that cannot complete (conflict, red
   gate, escalation) reaches a store that outlives the author session, with enough context to
   act on, and is guaranteed to be seen.
4. **Landed converges to live as an event, not a hope.** The enforcing ~/.claude layer follows
   trunk within a bounded, measured lag; ADDs converge as fast as edits; consumers never
   observe a torn state.
5. **Throughput headroom ≥10× current demand.** 124 lands/day today; the architecture should
   not degrade at 1,000+/day (the fleet doubles routinely).
6. **No new fragile singleton.** Anything that becomes the sole lander must fail visibly,
   restart itself, and degrade to the current path rather than wedge the fleet.
7. **Observable end-to-end.** Queue depth, wait/hold, convergence lag are measured continuously
   and rendered where closes/readouts already look.

## 2. Findings (by lane)

### 2.F Session-side cost — the congestion is gate-round churn, not lock queueing

- **367 of 368 successful August ships took ≥2 land-lock invocations.** The extra rounds are
  exit 42 — the CAS stale-gate signal (`ship-land.sh:2364-2367`): a sibling lands mid-gate, the
  optimistic out-of-lock gate is invalidated, and the outer loop re-runs the whole gate.
  Successful-ship episodes (n=368, Aug): span p50 **106s** · p90 **991s** · p99 **4,677s** ·
  max 6,107s; logged lock wait across the same episodes: p50 **0s**, p90 1s. Worst today:
  6 rounds/4,521s, 9 rounds/2,371s, 10 rounds/2,045s. **Contention bills the session as gate
  re-runs (livelock-by-invalidation), not queue time.** The operator's 1h8m turn is round-churn
  signature, and the pathology scales super-linearly with land rate.
- **Pure lock starvation is a v1 memory**: all 19 `exit 75` (LOCK-STARVED) rows in the 2,929-row
  ledger date to 2026-07-26, zero since v2.
- **Waits are survivor-biased**: `land-lock.sh:144-147` logs only in the release EXIT trap; a
  live holder had spent **17m33s** in the acquire poll invisible to the ledger. All-time honest
  figures: wait p50 95s (n=384 non-zero), tail 3600s. Depth/position are unobservable — the
  lock dir holds only one holder's pid/lstart/branch; there is **no FIFO fairness** (an unlucky
  waiter can starve while holders rotate).
- **There is no land waiter.** Sweep of bin/hooks/scripts/commands: `land-lock.sh:127-138` IS
  the wait (in-process 2s poll, `LAND_LOCK_WAIT` 3600 → exit 75). `cc-wait` (the durable
  wait-contract primitive) was never wired to a land. "Waiter armed" in the operator's example
  was hand-rolled; nothing guarantees the re-attempt.
- **A backgrounded land is silently killable.** The turn cannot hold a contended land
  (Bash-tool ceiling 600s < episode p90 991s) so `run_in_background` is the only workable
  shape — which sits behind the harness's process-group SIGKILL (the #127/exit-144 class), and
  `ship-land.sh` installs **no signal trap** (`LANDING_GATE_ROOT_CAUSE_2026-07-26.md:21`), so a
  killed land records nothing. There is also **no in-flight singleton**: ledger reads 📦 while
  a land is mid-flight and the close nudges pressure a **second** `/ship` on the same worktree.
- **No enqueue-and-close path exists.** No Stop hook and no launchd job runs ship-land (auto-ship
  is 100% model-driven prose); `completion-assert.sh:358-360` *convicts* a close attempted with
  commits unlanded — the machinery structurally forces the synchronous shape. The only async
  rail (cc-backlog → dispatcher) has no land-shaped composer and spends a full model session per
  mechanical push. Observed practice for blocked lands is a prose `needs:` note to a future
  reader — a note, not an enqueue.
- Misuse tax: 23 ledger rows are `exit 127` — agents guessing `land-lock.sh status` (not a verb;
  treated as payload). One waited **2,777s** on the mutex to run a nonexistent command.

### 2.C Prior art — every component of an async lander already exists and is live

- **Landed + live today**: `desk-land.sh` (delegated lander, deliberately synchronous, reached
  via `handoff-fire.sh land`), `cloud-reconcile.sh` (serialized multi-branch drain:
  smallest-diff-first, continues past per-branch failure, landedness decided BY CONTENT,
  default-off behind CONFIRM=1), `postland-verify.sh` (**an autonomous trunk writer already
  trusted**: auto-revert pushes to origin/main unattended on a 300s launchd tick), `cc-dispatch`
  (admission-controlled dispatcher, ceiling 6, thrash-ordered), `capacity-admit.sh` (bounded
  admission with budget-expiry-to-EVENT), `cc-backlog` (lifecycle store with thrash counter).
  **What does not exist is only the hop: a land-intent store and its drain.** `bin/cc-queue` is
  a red herring by name (permission board); `feat/cc-queue` is fully contained in origin/main.
- **The deferred-land pattern was hand-written twice** as untracked one-offs
  (`~/.claude/autonomy/deploy-when-green.sh`, `deferred-fire-deploy-lane.sh`: defer until quiet,
  retry under the same gate, bounded, loud) and never became a primitive. Backlog carries the
  casualties: `35de32d78364` (164 stranded patches across 36 branches — bulk sweep designed,
  never executed), `02ba4e52389a` (complete branch, ship-land SIGTERM-killed 4×, remedy: "run
  when the machine is quiet"), `3c6bf04ba842` (a nohup recipe that the repo's own measurements
  say the harness kill defeats).
- **v2 rejected "speculative merge-queue (Zuul/bors batching)"** (`LAND_PIPELINE_V2.md:616-620`)
  — but on land-LATENCY grounds (R1: latency ≥ corpus-time) in the corpus-gate era. It did not
  evaluate a deferred-demand queue whose objective is SESSION time, with the corpus already
  moved post-land. `concurrency-census-2026-08-07.md` rules: cc-backlog/cc-dispatch are "the
  sanctioned store, queue and dispatcher" — build on them, never a second one.
- Idempotency precedent: auto-revert once reverted a correct unrelated commit (restoring a
  permanent red; `postland-verify.sh:1555` incident); reso item `ce2bf742216d` pins the rule —
  **key completion on a content-verified landed sha, never an actuator's exit code**.

### 2.G Falsification (both adversarial lanes converge on one constraint)

- **G1 (steelman)**: land failures are author-shaped and routine — the exit vocabulary is
  judgment (3 escalation · 5 rebase-conflict · 6 red gate · 8 verify-exhausted), with two
  author-fixed red lands inside 20 minutes on the morning of measurement. A 3am daemon holding
  an exit-5/6 can only auto-resolve (the 2026-07-11 semantic-mis-merge class), strand, or page.
  Its falsifying checks: wait-tail attribution, author-judgment rate, close-integrity replay.
- **G2 (hostile)**: (i) the lock is per-repo, not machine-wide (`land-lock.sh` keys on the
  shared git dir) — congestion is 15 sessions concentrating on one repo; (ii) the censored
  tail — completed-lands data cannot distinguish wedge/retry pathology from genuine depth
  (LAND_LOCK_TTL=1200 means a wedged holder blocks peers 20min before reap; one wedge + retries
  explains "3 peers, 1h8m" with zero throughput problem); (iii) **off-box writers already bypass
  the flock** — cloud sessions push straight to origin, so the durable serialization point is
  the REMOTE, not one machine's /tmp; (iv) async lands orphan their failures: `wrap-ledger.sh`
  computes 📦/✅ from `trunk..HEAD` at close, so naive async makes every close read 📦 and kills
  the self-certifying close. Demand is policy-manufactured (ship-at-every-close), so the close
  protocol is itself a congestion lever.
- **Shared verdict**: any redesign lives or dies on (1) preserving an un-fakeable close and
  (2) owning judgment-shaped failures after the author session is gone. Both are satisfiable —
  the enqueue can record the DoD paths for mechanical post-land content-verify, and
  judgment-shaped exits can file backlog items that the existing dispatcher staffs with a NEW
  authorized context — but neither happens for free, and no naive queue provides them.

### 2.A Mechanism ground truth — the lock is not the correctness boundary

- **The dead-holder reap is racy — reproduced, not theorized**: `land-lock.sh:120-123` is
  `rm -rf` + `mkdir` (non-atomic); 6 concurrent acquirers against one dead-pid lock produced
  **3 simultaneous holders 13ms apart**. `tests/land-lock.bats` (11 tests) has no concurrent-reap
  case. What actually prevents the 2026-07-11 drop class is **CAS (`ship-land.sh:2101-2109`) +
  content-verify (`land-verify.sh`) + bounded retry — all of which work whether or not the lock
  held.** Exposure ∝ queue depth at the moment a holder dies (large in v1, small today).
- **The hold is O(local branches) and growing**: `stranded-sweep` measured 59.2/59.2/62.7s over
  497 branches, inside the mutex (`ship-land.sh:2228`); daily hold p50 31→32→50→46→57→**69s**
  (08-05→08-10) tracking ref growth; the one historical drop followed a backup-ref GC. Both
  published figures are stale (README "5-15s"; ship.md "84-302s"). The in-lock CAS-mode budget
  is ~90% sweep.
- **A live-but-hung holder has no recovery**: in-lock `git fetch`/`git push` carry **no
  timeout**; H2 (never reap a live holder) is deliberate; the only escape is the forbidden
  `LAND_SERIALIZE=off`. A stalled push wedges every lander on the box until the process dies.
- **Ratchets are O(repo), not O(diff)** — contradicting ship-land's own header; six timed arms
  sum **60.2s/round** (hermeticity 32.6s, git-identity 12.3s, …). Blocking is supposed to
  narrow to own-diff files (`CC_*_OWN`) but measured exit-6 attribution is "mostly repo-wide
  ratchets firing on files the land did not touch" — the narrowing leaks for some arms, so
  trunk-wide debt taxes innocent lands (the #112/#126 red-on-trunk class). Re-round rate 22-23%
  all-time, each re-round a full unlocked gate.
- **Behavioral coverage reality**: 83% of lands execute no test of their own diff (smoke
  none/skipped/partial); the verifier's newest green was 55.7h old against its own 24h
  staleness ceiling ⇒ `net:"inert"` on 312/530 lands. `smoke:"none"` collapses **five distinct
  causes** into one token; exits 2/4/7/42 and the in-lock fallback's exit-6 write **no
  attestation row**; the fallback lane runs ~60s of ratchets **inside** the mutex; exit 9 is
  structurally unreachable in the fast lane (confirmed 0 ever). The exit-127 class is fully
  explained: `land-lock.sh` treats any unrecognized flag as the wrapped command
  (`--status` reproduced: takes the real mutex, exits 127).
- Test-calibration trap for any P1 fix: `land-gate-cas.bats` asserts `hold_s ≤ 2` on a
  ~2-branch fixture — structurally blind to the sweep that dominates the real hold (a control
  calibrated to the fixture, not the mechanism).

### 2.B Quantitative — the queue is a staleness generator; the gate is the loss channel

- **Schema first**: `~/.claude/land.log` is TWO interleaved record types — LOCK rows
  (`land-lock.sh:74`, one per lock acquisition, carries wait/hold) and TOOL rows
  (`ship-land.sh:476` attestation, one per ship-land invocation). All-rows percentiles are
  poisoned in both directions (labelled so in the lane artifact); every figure below is
  exit-split. A gate-red never reaches the lock, so the LOCK ledger is structurally blind to
  the largest loss channel.
- **Lock exoneration, refined**: peak utilization ever 21.9% (07-30); last week 1.2–4.7%.
  Post-v2 wait on *landing* rows p90 23.7s; hold p50/p90/max 87/123/282s. Zero starvation.
- **The staleness mechanism, measured**: P(exit-42 | wait>0) = **49%** (14d) → **86%** (3d) —
  a waiter queued during a successful hold is by construction gating against a base the holder
  is about to move; it acquires at release, spends 0–2s discovering staleness, discards its
  gate, re-rounds. Utilization stays low precisely because queued work is discarded, not
  performed. The **wait-free** staleness column (base moved between gate-end and lock-take) is
  the rising one — 4→6→4→15→21 across 08-06→08-10, 48% of the partial day's LOCK rows:
  push-RATE pressure, not lock contention.
- **Attempt-level loss**: gate-red = **27% (14d) → 39% (3d) → 45% (last day)** of ship-land
  invocations (TOOL denominators; pre-v2 was 69–71%). Smoke is `none`/`skipped` on **89%** of
  invocations (load-shed), so the reds are statics — shellcheck + ratchets. Attribution exists
  only since 2026-08-08 (79% of 14d reds unattributed = instrument birthday, not mystery).
- **Retry chains** (grouped repo+branch, 15-min gap): 71% of branches land on the first lock
  acquisition; dead-chain rate 3% (pre-v2: 44%); landed-chain wall-clock p50/p90/p99/max =
  **98s / 665s / 2,362s / 5,536s** — and this is a floor that excludes the pre-lock gate phase.
  Consistent with the operator's 1h8m turn as a p99-tail episode.
- **Coverage, proven live**: a queued waiter writes NOTHING until resolution
  (`land-lock.sh` logs only at timeout or the release EXIT trap) — three live waiters observed
  with zero rows, all four rows appearing at once on release with wait_s matching observed
  process age ±1s; the operator's pid 69428 has **no row** (the signature of a still-queued
  waiter). Two lands measured spending **845s and 703s (77–78% of lifetime) in unlocked gate
  rounds while attesting `wait_s: 0`** — the fallback lane `exec`s land-lock so the ledger
  clock starts at exec. A SIGKILLed holder writes no row at all (trap can't fire) — frequency
  unmeasurable from the log. Event coverage is good (882/882 attested heads resolve; TOOL and
  LOCK exit-0 agree ±1/day; 96% of trunk commits inside attested ranges): the under-report is
  of TIME, not of events.
- **Live pathology at measurement**: current lock holder pid 82031 is **orphaned (ppid 1)** —
  its owning session died; H2 policy (never reap a live holder) keeps it. Box at load 28–50 on
  10 cores, 56 processes >100MB totalling 31.4GB — each gate round ~4–5 min under that load vs
  the 29s bench figure. Land throughput is coupled to fleet load, and the lands themselves run
  at nice 5.
- Demand denominator: 581 commits/7d over ~380 attested lands = 1.5–2.2 commits/land.

### 2.D Decision record — the lock is exonerated; the alternatives were already adjudicated

- **Pre/post-v2 split of the same ledger** (2,929 rows, cutover 2026-07-28 12:00): lock wait
  p50/p90/p99/max **0/1,961/3,601/7,386s → 0/77/247/728s**; hold p90/max **682/6,771s →
  119/282s**; exit-75 starvation **19 → 0**; waits >600s **86 → 1**. Lock utilization last 7d:
  **0.7–4.8% of each day.** A mutex under 5% occupancy cannot generate hour-scale queues — the
  "queued behind peers on the machine-wide lock" framing was v1's pathology, fixed 2026-07-28.
- **Where the hour actually goes, measured**: (1) **38% of land attempts exit 6 (gate-red)** —
  67/175 attempts since attribution landed 2026-08-08, causes led by `shellcheck` and
  `dead-assertion` — agent-side diagnose-fix-rerun loops that never take the lock; (2) **the
  verifier lane breaches today**: `cycle-time-census.sh --all` → BREACH, scheduled p50
  **3.13h**/p90 3.32h, 56% of runs censored at the 10,800s bound; trunk red **65.6h** vs R2's
  "≤1 verifier cycle"; **auto-revert 12% success** (3 landed/5 failed/17 skipped of 25, C26
  split-remedy landed since); (3) counting: 582 commits/7d = **~357 land events** (1.6
  commits/land — quote both, the corpus itself once made this error).
- **Async/queued/single-writer/delegated landing: evaluated 4×, rejected 4×.**
  (i) Speculative merge-queue rejected (`LAND_PIPELINE_V2.md` §8) on corpus-latency grounds —
  ⚠️ **ground decayed** two days later when the corpus left the land path; nothing re-derived
  the conclusion (open). (ii) Two-phase/intent lock (delegated push-only writer) rejected on a
  **durable correctness ground**: the rebase must sit in the same critical section as the push
  or the 2026-07-11 `dfacccd` drop-race reopens. (iii) **A gate-concurrency semaphore was
  BUILT, TESTED, and is FORBIDDEN by landed policy** (`3d052701`, 602 insertions incl. 231
  test lines; "do not land it, and do not rebuild it" — it would queue 45 min to protect 29s;
  reopen only if a corpus returns to the land path, and start from `3d052701`).
  (iv) Load-keyed admission (`gate_admit`) deleted; its absence is asserted by a structural
  test (`postland-verify.sh:1825-1830`). The async architecture that WAS accepted is the
  verdict, not the land: post-land singleton verify + deploy-as-enforcement + auto-revert (D1).
  The one never-considered shape — a landing broker/daemon — is priced by the corpus's own
  words: five single-machine couplings make it "a protocol rebuild, not a purchase," aimed at
  a lock measured at 0.7–4.8% utilization.
- **v2's own acceptance was never consolidated**: its land-latency criterion is structurally
  unverifiable from the artifact it nominates (`land.log` has **no end-to-end duration field**,
  yet ship.md instructs measuring p50≤30s from it); the induced-red revert drill was never run
  (production shows 12%); "12-session day, zero interventions" never verified (deploy leg
  contradicts it). The standing audit (`DEPLOY_LANE_GROUND_UP.md` §1.5) grades R3 "DISCARD AS
  STATED — a property satisfied by never advancing is not an advance invariant", R7 "EXTEND —
  a fail-closed path must escalate on repetition" (534 refusals, zero escalation), R2 "NOT
  ACHIEVED", and states the coupling any successor must start from: **"R1's success is R3's
  problem — fast landing is what makes trunk outrun the verifier."**
- **Open, congestion-relevant, already-priced levers**: `70dff02dcf4a` — corpus QoS band
  (measured **2.26×**) + launchd envelope (**3.19×**), "brings the lane under 2h for $0",
  filed-not-fired (reverses a documented deliberate choice; launchd half is a C10 operator
  step). Open questions the corpus cannot answer: no instrument measures end-to-end land
  wall-clock (one new field closes it); gate-red rate (38%, daily 18–45%) is no doc's
  first-class metric; **33.8% of lands run NO suite at all** (smoke skipped/none — behaviorally
  ungated, with the only net a verifier hours behind); `SHIP_LAND_SMOKE_BUDGET_S` is
  caller-raisable without ceiling (observed raised to 1,200s).
- Constraints on any new plan, from landed policy: no landing queue/cap/admission control; do
  not aim at the land lock; never assert done at the push (trunk is not an enforcing store).

### 2.E Landed→live — the gated lane is starved; hand-pulls do the real work

- **Mechanism**: live paths are per-file symlinks into the root checkout's working tree, so
  content goes live when that checkout advances. Three advance paths exist; only one is gated:
  (A) `deploy-live.sh --auto` on a 600s launchd tick behind the T1/T2/T3 ladder; (B) **agents
  typing `git pull --ff-only` in the shared checkout — ungated, scriptless, measured in
  transcripts** (4+ in the last 200 reflog entries; the sanctioned `merge <sha>: Fast-forward`
  shape appears 16×); (C) `deploy-now.sh` (operator, ungated).
- **The gated lane is deadlocked by a green-stamp famine.** Stamp histogram now: 107 red ·
  18 cut · 3 green · 1 hung (2.3% green — trunk flake noise keeps the verifier red, cf. the
  47h-red trunk with 3..14 flake swings). Newest on-trunk green sits **320 commits down** vs
  `SCAN_N=200`; at 142 commits/day the window lasts ~34h ⇒ T1 structurally blind. Current log:
  **601 refusals; last sanctioned advance 9h ago.** Live lag is nonetheless 4 commits / 18 min —
  **because path B keeps it low, which also suppresses the T2 lag-threshold self-heal.** The
  parity tool itself says it: the unconditional link-refresh "cleans up the symptom on a 600s
  timer while the ungated advance that caused it goes on undetected."
- **Architectural incoherence**: v2's land lane is built on "post-land verify + auto-revert
  dominates pre-verification" — yet deploy-live re-imposes pre-verification (green-before-live)
  at the deploy boundary, where it starves. The two halves of the pipeline embody contradictory
  philosophies; the famine is the contradiction expressing itself.
- **Torn state is observable and unguarded** (no lock/quiesce/staging on the advance path):
  mixed-generation windows while the ff-merge rewrites files one-by-one (28 paths across
  today's 4-commit delta); `ln -sf` is unlink+create (transient ENOENT under `[ -f x ] && . x`
  guards); the advancer rewrites itself mid-run (documented one-deploy-late incident 8035ea63).
  Exposure scales with lag — another reason big-bang advances are wrong.
- **ADD gap verify-at-HEAD: REMEDIED with a named residual.** Sensor (LIVE_ADDS breaches at
  lag 1, `wrap-ledger.sh:416,445-446`, sha 83fe0b84) and cause (link_refresh unconditional on
  every tick, c2f24edc/a7cba56d) both landed. But the repair consumes a fixed pathspec —
  `hooks commands scripts bin skills` — covering **5 of ~19 install.sh link classes**:
  `agents/`, `lib/`, `vendor/`, `githooks/`, root configs (`accounts.json`,
  `model-config.yaml`), and launchd COPIES have no tick-driven repair; they wait on an
  `install.sh` that only a successful (famine-blocked) advance runs. Latent, in-parity today.
- **`~/.claude/CLAUDE.md` — the highest-consequence live file — has no converger and no
  detection**: real file, no install.sh leg, excluded from the parity pathspec; in parity only
  because a session hand-synced it 34 minutes before measurement.
- **Sensor blind spots**: a session whose cwd IS the root checkout gets `LIVE=1` by tautology
  (`merge-base --is-ancestor HEAD HEAD`), and `compute_live_layer` runs only on the ✅-eligible
  path — so the population doing the ungated pulls is exactly the one the 🚀 rung cannot
  convict. Migrations arm healthy: 0 failed, 7 staged operator-owned c10s.

### 2.I Population — the growth is refs and residue, not stranded work

- **The stranded-branch myth, corrected**: of 499 branches, 279 hold 612 truly-unlanded commits
  (patch-id census; raw ahead-counts inflate **5.9×** because rebase-landing mints new shas —
  five outlier branches read 455-ahead while 447/456 commits are patch-equivalent to trunk).
  **69% of "stranded" branches are `ship/backup-*` rollback refs** (272 of them, minted one per
  land at `ship-land.sh:2344`, protected from the janitor by design, discharged ~half by the
  land-time content reap; a retrospective sweep is deliberately forbidden — the predicate
  misclassifies 437/739 against a drifted trunk). 75% of truly-stranded branches hold exactly
  ONE commit; 61% are <4d old (in-flight). Real backlog: 71 branches >7d.
- **The unmanaged growth term**: `refs/checkpoints/` = **5,175 refs at ~700/day** (teammate
  shutdown preservation), **no collector, no retention policy** — and they are load-bearing
  (reap-guard reads them as a work-preservation oracle), so the gap is policy, not deletion.
  Loose objects 692→1,832 in one day (auto-gc cliff at 6,700 turns some session's next write
  into a gc over a 120MB pack). `refs/heads` is 8% of packed-refs — branch-only remediation
  misses 92% of the store.
- **Worktrees**: 125 registered; 90 >7d stale, of which only 25 hold unlanded work (82
  commits) — **64 are landed-content residue kept by the dirty-tree KEEP rule
  (`worktree-gc.sh:726`) which never asks whether content landed**; the cron passes only
  `--prune-branches`, never `--dispose-abandoned` ⇒ nothing automatically removes an abandoned
  worktree. 9 unowned dirs (no `.git` pointer) are structurally invisible to the janitor while
  counting toward its ceiling. Warm pool is reso-only: every claude-infrastructure fire takes
  the cold path (fetch + worktree add + secret copy; cheap here — no lockfile).
- **Verify-at-HEAD**: ea58210f (janitor tripling) PARTIALLY REMEDIED — the three in-file
  failure modes closed; the fourth (janitor not running at all) is recorded in a `--assert`
  probe with **zero callers**. Ref-lock/fetch-storm coupling to population: **REFUTED** (0
  genuine `cannot lock ref` occurrences; HEAD is per-worktree) — but the one population that
  CAN cause index sweeps has degraded 4×: **8 of 15 live sessions cwd'd in the shared checkout**
  (was 2/10 on 08-09), in direct violation of the project rule, and identical to the population
  doing 2.E's ungated pulls that the sensors cannot convict.

### 2.H External SOTA — batching has no purchase here; residency is the binding constraint

- **Invariant census** (bors/bors-ng, rust bors, GitHub merge queue, Zuul, Uber SubmitQueue,
  Google TAP, Prow/Tide, GitLab trains, Gerrit(+queue), Meta push-rebase, Mergify, Aviator —
  URLs in the lane artifact): every system is single-writer-to-trunk and validates against the
  state trunk will have at land time — **both already present here** (the repo-keyed mutex;
  the in-lock CAS = textbook optimistic concurrency with validate-at-commit). Batching exists
  to amortise a ~30-min CI gate and is paid for with bisection/ejection machinery; speculation
  exists to fill a long pipeline. **This fleet's gate is seconds (smoke p50 0s, `fast` scope
  84%), the mutex duty cycle is 5.6%, and capacity is ~13× demand — both levers are worthless
  here.** TAP, the hardest batcher, is exactly the system that abandoned the green-trunk
  invariant (true head vs green head) — and batching also breaks auto-revert's
  culprit-granularity (an innocent author gets reverted with the guilty one).
- **The residency law** (measured, `merge-tree` over all refs by tip age): conflict rate
  **55% at <6h → 78% at 6-24h → 91% at 24-72h → 95% at 72-168h**. The fleet's ~0% land-time
  conflict rate (0 exit-5 in 1,021 v2 lands) is a *consequence of landing within minutes of
  committing*, not an independent property. **Any residency-adding design (queue, batch,
  window, speculative tree) converts ~0% into 55-91%** — this kills the queue class
  independently of its economics, and simultaneously certifies ship-at-every-close as the
  conflict-suppression mechanism, not just a latency preference.
- **The finding that reorders the remedy**: the v2 success path holds the mutex a median
  **87s** against its own design comment of "a 5-15s hold" (0/1,021 lands in that band) —
  because `stranded-sweep.sh` (**55.8s measured, O(branch refs), read-only**) and
  `ship-backup-reap` run INSIDE the lock (`ship-land.sh:2140-2250`), while `land-verify.sh` —
  the race-window proof the lock exists for — costs **0.485s** and push+fetch ≈ 1.5s. The
  critical section grows with fleet size: the textbook convoy generator, and the substantive
  (not structural) violation of v2's own "nothing heavy in the lock" law D2. Wait ≈ hold ×
  depth: emptying the lock to ~2s collapses the tail arithmetically (peak-depth-13 drain:
  19min → ~26s) and shrinks the queued-during-hold staleness window ~40×.
- **Candidate ranking under fleet constraints**: (A) *empty the critical section* — pure
  subtraction against a measured attribution, no new daemon, survives; (B) *ticket-lander
  daemon on the dispatcher spine* — the only design where a dead author is a non-event, but
  dies on launchd fragility (agents may `disable` but are DENIED `launchctl enable`;
  install.sh boots the spine out on every advance swallowing errors; this box already
  suffered a 13-label blackout) — a wedged lock today starves one session, a wedged lander
  stops the fleet; (C) *local-trunk advance + async publish* — makes landed≡live structurally
  but inverts the content-verify-on-origin invariant this repo paid the 2026-07-11 incident
  to learn. **Composite adopted: A + B's inbox half** — the durable failure inbox needs no
  daemon: the author's own dying process writes `refs/land/failed/<ts>-<sid>-<branch>` + a
  `cc-backlog needs` row (exact re-land command, keyed to session id) on any non-zero terminal
  exit; the existing renderers surface it whether or not the author survives.
- Caveats carried: the 87s attribution is 56s confirmed + ~30s inferred (time the whole
  in-lock block before quoting a post-fix number); `git replay` is experimental (not needed
  for A); the conflict-by-age table includes dead branches (the monotone shape is the
  load-bearing part, the level is an upper bound).

## 3. Verdict

**The architecture decision is already correct — certified. The implementation is not at the
100th percentile — seven defect classes, all measured, none requiring new architecture.**

**Certified, three independent ways** (decision record · measurement · external theory):
synchronous, author-attached, optimistic-CAS landing under a per-repo mutex + post-land
singleton verification with auto-revert + gated live convergence is the right shape for 15+
sessions on one machine at ~380 lands/week.

1. The decision record already adjudicated the alternative class four times (merge-queue,
   two-phase intent lock, concurrency semaphore — built, tested, and forbidden — and load-keyed
   admission), one rejection on a durable correctness ground (the `dfacccd` drop-race), and the
   corpus prices the never-considered broker as "a protocol rebuild, not a purchase" (§2.D).
2. Measurement exonerates the serialization point: lock utilization 0.7-4.8%/day, zero
   starvation post-v2, dead-chain rate 3%, 71% first-try lands (§2.B, §2.D).
3. External theory closes it: the two invariants every industry system shares are already
   present, the two levers they add (batching, speculation) amortise costs this fleet does not
   pay, and the residency law makes every queue-shaped design actively harmful — landing fast
   IS the conflict-suppression mechanism (§2.H).

The premise "commits get queued and congestion piles up on the machine-wide lock" is **v1's
pathology, fixed 2026-07-28**. Today's 1h+ turns decompose, measured, into: agent-side
gate-red fix loops (27→45%/day, statics), CAS re-rounds re-running unchanged work (rising with
push rate), a mutex ~85% occupied by housekeeping that does not need it, verifier-lane breach
(p50 3.13h) starving the deploy gate, and a close protocol that is blind to an in-flight land.
Demand policy (ship-at-every-close) is also certified: it is what keeps residency low and
conflicts at ~0%, and post-remedy capacity headroom is ~400×.

**Not certified — the seven gaps, ranked by leverage:**

| # | Defect (measured) | Class |
|---|---|---|
| P1 | 56s of the 87s median mutex hold is `stranded-sweep` + backup-reap — in-lock housekeeping, O(refs), the convoy generator (§2.H) | land path |
| P2 | Gate-red 27→45%/day of attempts, statics-dominated; red dies at land time instead of commit time; rate is no one's first-class metric; part of the rate is ratchet blocking-scope leaking beyond own-diff, taxing innocent lands with trunk-wide debt (§2.A, §2.B, §2.D) | demand quality |
| P3 | A CAS re-round re-runs file-local statics whose verdict cannot have changed; each stale round costs a full gate (~minutes under load) and the wait-free staleness column is the rising one (§2.B, §2.F) | gate economics |
| P4 | Land lifecycle: no signal trap (killed land attests nothing), no in-flight marker (double-fire + close-conviction), waiters invisible until release, an orphaned (ppid-1) holder pages nobody, `exit 127` misuse takes the mutex, a failed land's notice dies with its pane, the dead-holder reap races (3 simultaneous holders reproduced), and a live-hung holder wedges the box — in-lock network calls are unbounded (§2.A, §2.F, §2.B, §2.G) | lifecycle |
| P5 | Verifier lane breaches (p50 3.13h, 56% censored; green 2-3%) with the 2.26×/3.19× QoS lever priced and unfired; auto-revert at 12%; 601 deploy refusals with zero escalation (R7 gap) (§2.D, §2.E) | verify→live |
| P6 | Live convergence incompleteness: ADD-repair covers 5/19 link classes; `~/.claude/CLAUDE.md` has no converger or detector; ungated hand-pulls (8/15 sessions in the shared checkout) do the real work and suppress the self-heal; torn-state windows unguarded (§2.E, §2.I) | verify→live |
| P7 | Growth without policy: `refs/checkpoints/` 5,175 @ ~700/day no collector; `ship/backup-*` discharge ~50%; 64 landed-content worktrees kept forever; `--assert` liveness probe has zero callers; loose objects 2.6×/day toward the auto-gc cliff (§2.I) | population |

P0, cross-cutting: **no instrument measures end-to-end land wall-clock** — v2's own acceptance
criterion is unverifiable from the artifact it nominates, waits are right-censored, and two
lands attested `wait_s: 0` while spending 77-78% of 15-18min lifetimes in gate rounds (§2.B).

## 4. Target architecture

The certified shape, completed rather than replaced:

1. **The mutex carries only the race window** — fetch-CAS → push → `land-verify.sh` (~2s).
   `stranded-sweep` and `ship-backup-reap` run post-release in the same process (their
   predicates key on the captured `LANDED_HEAD`, not live trunk, so post-lock execution is
   sound; the sweep already treats exit 1 as a normal REVIEW verdict on a multi-session box) —
   or fold into `postland-verify.sh`. Serialized capacity ~990/day → ~40,000/day. Three
   lifecycle closures ride with it (§2.A): the dead-holder reap becomes atomic
   (generation-checked rename, with a concurrent-reap test — none exists), the in-lock
   fetch/push get bounded (`timeout` with a distinct machine-verdict, never a gate-red), and a
   hold past budget PAGES (H2's never-reap-a-live-holder stands; the page is the recovery).
2. **Statics shift left and memoize.** The land gate's statics become runnable at commit time
   in the author's worktree (same scripts), and per-file statics verdicts are memoized by
   blob-sha (shellcheck/`bash -n`/py_compile are pure functions of file content) so a CAS
   re-round re-runs only repo-global ratchets + policy-selected smoke — seconds, not minutes.
   This extends v2's existing cross-round verdict-carry (`SHIP_LAND_SMOKE_*`) to statics and is
   distinct from the rejected changed-file-scoped *suite selection* (S3): no suite selection
   changes, only memoization of file-local pure checks. The ratchet arms — repo-wide by
   construction, 60.2s measured across six of them — get their own keying (verdict cached
   against lint-sha + scanned-set state, or made diff-incremental where sound), and every arm's
   BLOCKING scope is verified to truly narrow to own-diff files (§2.A measured leakage: reds
   citing files the land never touched). Attestation coverage extends to exits 2/4/7/42 and the
   in-lock fallback's exit-6; `smoke:"none"` splits into its five causes; the stale published
   hold figures (README "5-15s", ship.md "84-302s") get corrected; and the P1 fix ships with a
   mechanism-keyed test — a fixture with hundreds of refs — replacing the 2-branch hold
   assertion that is structurally blind to the sweep.
3. **Every land terminates loudly, author present or not.** ship-land traps
   TERM/INT/HUP and attests its own death (the cc-await-ping `_sig_verdict` pattern); on any
   non-zero terminal exit it writes `refs/land/failed/<ts>-<sid>-<branch>` + `cc-backlog needs`
   with the exact re-land command. An in-flight marker (pid+lstart, per worktree) makes
   `wrap-ledger`/`completion-assert` read LANDING instead of convicting 📦 mid-flight and
   blocks a second concurrent fire. Waiters register in the lock dir (visible depth; ledger
   row at acquire-start). An orphaned live holder (ppid 1) is never reaped (H2 stands) but
   PAGES. `land-lock.sh` grows a verb allowlist so `status` cannot take the mutex.
4. **The verifier gets the machine share its role demands** (fire `70dff02dcf4a`: QoS band +
   launchd envelope, measured 2.26×/3.19×, lane <2h ⇒ greens return ⇒ T1 revives), the
   auto-revert net completes its C26 arc toward reliability, and deploy refusal escalates on
   repetition (the R7 extension) instead of damping forever.
5. **Landed≡live convergence completes**: link-refresh (or install.sh's link pass) covers all
   19 link classes on every tick; `~/.claude/CLAUDE.md` gains a parity leg + a converge
   mechanism; the ungated-advance verdict (already rendered by `deploy-parity-assert.sh`)
   files/pages instead of printing; the shared-checkout session population (8/15) returns to
   worktrees (rollout owned by task #114). Torn-state windows: accepted at small lag by
   explicit decision (exposure scales with lag; P5 keeps lag small), recorded here so it is
   not re-found.
6. **Population gets policies, not sweeps**: retention for `refs/checkpoints/` (age-bounded,
   LAST-superseded — respecting reap-guard's oracle reads), a content-aware disposal path for
   landed-residue worktrees (the KEEP ladder asks "did this content land?" before "is it
   dirty?"), `--assert` wired to a consumer (`cc-blockers`), and a gc-headroom policy.
7. **The pipeline measures itself end-to-end**: the TOOL attestation grows
   `total_s`/`gate_rounds`/`gate_s` (+ existing lock fields), and `cycle-time-census` renders
   land-latency, gate-red rate, and P(stale|waited) — v2 §7 acceptance becomes a computable
   verdict instead of prose.

Explicit non-goals, decided with evidence: no land queue, broker, batching, speculation, or
concurrency cap (§2.D forbidden + §2.H residency law); no second verification host (§2.D); no
aiming at the lock's topology; no demand batching at close time (residency law — land fast IS
the design).

## 5. Gap list → implementation

Filed as backlog items (the sanctioned store; the dispatcher staffs them), each carrying its
lane evidence. Locus: dispatched sessions per item (plan-conventions default); P1-P4 touch
`scripts/ship-land.sh`/`land-lock.sh` and serialize behind each other by file ownership;
P5's launchd half is already the operator-owned C10 `70dff02dcf4a`.

| Item | First move | Success measure |
|---|---|---|
| P1 empty-the-lock | time the in-lock block end-to-end, then move sweep+reap post-release | hold p50 ≤5s (from 87s); wait p90 ≤5s; staleness-given-wait falls toward the wait-free floor |
| P2 shift-left statics | expose the land statics as a commit-time entry point + red-rate census panel | gate-red ≤10%/day within two weeks |
| P3 statics memo | blob-sha-keyed verdict cache, re-round runs ratchets only | re-round cost ≤10s at load; exit-42 rounds stop costing full gates |
| P4 loud lifecycle | trap+attest; in-flight marker read by wrap-ledger/completion-assert; waiter registry; orphan-holder page; verb allowlist; failure inbox (`refs/land/failed` + backlog row) | zero silent land deaths; zero mid-flight 📦 convictions; a dead author's failed land renders at the next close |
| P5 verifier share | fire `70dff02dcf4a` (repo half now; C10 half stays operator-owned); R7 escalation arm | verifier p50 <2h; ≥1 green/day; deploy T1 advances without hand-pulls |
| P6 converge completeness | extend link-refresh classes; CLAUDE.md parity leg; UNGATED verdict files | `LIVE_ADDS` breach impossible for any install.sh class; hand-pull rate → 0 |
| P7 population policy | checkpoints retention + KEEP-ladder content question + `--assert` consumer | packed-refs stops monotone growth; stale-residue worktrees ≤10 |
| P0 self-measurement | attestation fields + census panels | v2 §7 renders as a computed verdict |

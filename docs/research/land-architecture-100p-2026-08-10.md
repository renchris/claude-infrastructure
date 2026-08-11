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
#### P6 IMPLEMENTED 2026-08-10 — and one premise above is corrected by the tree

Built in `scripts/deploy-parity-assert.sh` (+ a comment-only widening note in `deploy-live.sh`'s
`link_refresh`, which needed no code change — consuming a verdict instead of re-deriving a want-list
is exactly why the scope could widen underneath it). Tests: `tests/deploy-parity.bats` 42 → 64,
`tests/deploy-live.bats` 84 → 86.

1. **Every install.sh SYMLINK class is now enumerated**, so `link_refresh` repairs all of them on the
   600s tick: added `agents/*.md`, top-level `lib/*.{sh,zsh}`, `hooks/*.py`, `scripts/lib/*.sh`,
   `bin/desk-*`, the root SSOTs (`model-config.yaml`, `providers.json`), and `vendor/<plugin>/` as
   ONE dir link per plugin (never per-file — install.sh:546 links the directory on purpose).
   Repair stays monotone/create-only, unchanged. `accounts.json` is deliberately absent: install.sh
   links it, but it is gitignored, so a tracked-file listing structurally cannot see it.
   *Two classes the §2.E table did not name were also missing and are now covered:* `hooks/*.py`
   (settings.json wires `curl-gate.py` and `enforce-email-formatting.py` BY PATH) and
   `scripts/lib/*.sh` — the latter is the very directory holding `pane-spawn-log.sh`, the file whose
   silent no-op produced the `LIVE_ADDS` rule. The want-list matched `scripts/*.sh` and
   `scripts/limit-recover/*`, and `scripts/lib/…` fell into the `scripts/*/*` want=0 arm.
2. **install.sh's COPY classes are detected, deliberately not tick-repaired**: `githooks/*`,
   `launchd/*.plist`, `statusline.sh`, `bin/it2-wrapper`→`bin/it2`, `CLAUDE.md`, under their own
   `COPYMISS`/`COPYSTALE`/`CLAUDEMD` tokens. They must never use the `MISSING: ln -sf` spelling:
   install.sh:289 records that githooks shipped as symlinks for six hours and calls it "a critical
   bug" (a link into the working tree dangles on any branch switch, and git fails OPEN on a dangling
   hook). So these classes gain detection, not convergence — the honest half of P6.
3. **A per-class table renders on every run, clean or not.** This is why the hole survived five
   sessions of readers: a per-file report over a 5-class pathspec is indistinguishable from one over
   a 19-class pathspec whenever both are clean, so "no rows about `agents/*.md`" read exactly like
   "`agents/*.md` is in parity". Live at implementation: 19 classes, all in parity.
4. **The UNGATED verdict now FILES** a `cc-backlog needs` row instead of only printing, damped by a
   condition key (a constant title — the trigger is a standing STATE, so cc-backlog's event key IS
   the condition key — plus a TTL marker so the 600s tick does not shell out 144×/day). No `--run`
   is offered: there is no command that repairs it, and the one that looks like it (another ff) is
   the cause. Filing runs on the DERIVED path only (same subject discipline as the provenance leg),
   is `CC_PARITY_FILE`-seamed, and returns 0 on every path — a parity leg that could break the
   advance is a converger that stops convergence.

🚨 **PREMISE CORRECTED — `~/.claude/CLAUDE.md` DOES have an install.sh leg.** §2.E above says "no
install.sh leg"; install.sh:583-587 has had a `diff`-guarded `cp` since before this investigation.
The finding's substance survives intact and the correction sharpens it: the file had no *tick-driven*
converger and no detection *at all*, because its one converger sits on the advance path and was
famine-blocked with everything else. So the P6 build adds the missing half — detection (a parity row
+ a `cc-backlog needs` row when diverged) — and explicitly does NOT auto-write the live file. The
direction is a judgment, not a mechanism: this repo's own rule is that a land here is followed by
hand-applying the same edits live, so a divergence can equally mean "the repo advanced" or "the live
file holds an uncommitted edit", and a converger that guessed would destroy operator work in the
second case. That is also the only thing that licenses an operator-owned `needs` row rather than
just doing it. **Follow-on decision, unresolved:** whether to make the live copy derived-only
(forbidding hand edits) and converge it on the tick — which is a policy change to how the global
instructions are edited, not a script change.

**Also corrected, in the tree rather than the doc:** `tests/deploy-parity.bats` carried
`printf 'x' > lib/thing.sh  # top-level lib/ — install.sh has NO lib leg` and required exit 0 over
it. True when written, FALSE from 931641a4 (which added install.sh:360's `lib/*.zsh` + `lib/*.sh`
loop) — so for weeks a test was pinning the ABSENCE of a check the tree needed, and stayed green
because a clean fixture exit 0 is indistinguishable from a correct one. The enumeration is now held
against install.sh's own loop heads by an anti-rot test rather than by prose.

- **Sensor blind spots**: a session whose cwd IS the root checkout gets `LIVE=1` by tautology
  (`merge-base --is-ancestor HEAD HEAD`), and `compute_live_layer` runs only on the ✅-eligible
  path — so the population doing the ungated pulls is exactly the one the 🚀 rung cannot
  convict. Migrations arm healthy: 0 failed, 7 staged operator-owned c10s.

### 2.I Population — the growth is refs and residue, not stranded work

> **ERRATUM 2026-08-10 (P7 implementation session).** Two claims in this lane are FALSE at HEAD and
> are struck below; the lane's other findings stand and were re-verified. Both errors point the same
> way — *a sensor was searched for by SPELLING and its absence recorded as a fact*.
>
> 1. **"no collector, no retention policy" is refuted — by this lane's own cited grep.** A bounded
>    retention GC has existed since 2026-08-06 at `hooks/teammate-checkpoint.sh:153-248`:
>    `GC_FLOOR=3` newest-per-member immortal · `GC_KEEP=50` per-member rank cap · `GC_DAYS=14` age
>    rule, deletions batched through `update-ref --stdin`. The evidence file states its search as
>    `update-ref -d.*checkpoints`, `prune.*checkpoints`, `CHECKPOINT_RETAIN`, `reap.*checkpoint` over
>    `scripts/ hooks/ bin/` — re-run verbatim, the third pattern HITS `teammate-checkpoint.sh:45`
>    (`TEAMMATE_CHECKPOINT_RETAIN_DAYS`). The first two miss only because the code deletes via a
>    batched `--stdin` transaction rather than `update-ref -d`. It also demonstrably RUNS: it swept in
>    three sibling worktrees within 30 min of this check, and the cap binds (12 members sit at exactly
>    50, **zero above**). The store is therefore **bounded, not unbounded**; 5,175 → 5,553 is growth in
>    MEMBER COUNT, not per-member. The true residual is small and structural: **65 dead members
>    holding ~180 refs immortal under `GC_FLOOR`, ≈3.2% of the store.** Building a second collector
>    would have raced the existing one's `packed-refs` lock.
> 2. **The loose-object figure was true when measured and is now moot.** 1,832 loose objects was a
>    real reading at ~01:20; a repack has since run and the count is **513 — 7.7% of the 6,700
>    auto-gc threshold**, `garbage: 0`. There is no gc-headroom pressure to act on.
>
> Consequence for §5: P7 items **1 (checkpoint retention) and 4 (gc headroom) are DROPPED**. Items
> **2 (KEEP ladder asks content) and 3 (`--assert` consumer)** were verified TRUE at HEAD and are the
> implemented scope. See §3 P7 row and `land-architecture-100p-2026-08-10/I-population.md` §3.4.
>
> **A third correction, found while implementing item 2 and load-bearing for anyone who reuses this
> lane's framing.** "64 landed-content residue" is the right count of a WRONGLY-NAMED class: it is
> not residue. Measured over the live population, **79 of 84 dirty worktrees carry TRACKED entries**,
> dominated by paths **staged-but-never-committed** — and `git cherry` calls 72 of them "landed"
> because it reads COMMITS, which those paths are not in. Four such staged paths
> (`tools/blender/clawd_bmo.py` + three `assets/blender/clawd-bmo-*.webp` renders, **held in six
> worktrees each**) are **absent from `origin/main` entirely and exist on no ref anywhere**. A
> remedy that trusted `landed()` would have force-removed the only copies of expensive generated
> assets — the class `~/.claude/CLAUDE.md` protects by name. The shipped gate therefore asks
> **per-dirty-path content** against trunk (`ls-tree` blob identity, ship-backup-reap's shape: any
> uncertainty KEEPS), which frees 36 of 84 and correctly holds the rest.

- **The stranded-branch myth, corrected**: of 499 branches, 279 hold 612 truly-unlanded commits
  (patch-id census; raw ahead-counts inflate **5.9×** because rebase-landing mints new shas —
  five outlier branches read 455-ahead while 447/456 commits are patch-equivalent to trunk).
  **69% of "stranded" branches are `ship/backup-*` rollback refs** (272 of them, minted one per
  land at `ship-land.sh:2344`, protected from the janitor by design, discharged ~half by the
  land-time content reap; a retrospective sweep is deliberately forbidden — the predicate
  misclassifies 437/739 against a drifted trunk). 75% of truly-stranded branches hold exactly
  ONE commit; 61% are <4d old (in-flight). Real backlog: 71 branches >7d.
- ~~**The unmanaged growth term**: `refs/checkpoints/` = **5,175 refs at ~700/day** (teammate
  shutdown preservation), **no collector, no retention policy** — and they are load-bearing
  (reap-guard reads them as a work-preservation oracle), so the gap is policy, not deletion.
  Loose objects 692→1,832 in one day (auto-gc cliff at 6,700 turns some session's next write
  into a gc over a 120MB pack).~~ **STRUCK — see ERRATUM above.** A bounded collector exists
  (`hooks/teammate-checkpoint.sh:153-248`, floor 3 / cap 50 / age 14d) and runs; the store is
  bounded, and the residual is 65 dead members' ~180 floor-immortal refs (≈3.2%). Loose objects
  are 513 (7.7% of the cliff), not 1,832. What SURVIVES from this bullet: the refs ARE load-bearing
  (reap-guard reads them), and `refs/heads` is 8% of packed-refs — branch-only remediation
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
| P7 | ~~Growth without policy: `refs/checkpoints/` 5,175 @ ~700/day no collector~~ (STRUCK — a bounded collector exists and runs, §2.I ERRATUM); `ship/backup-*` discharge ~50%; **84 dirty worktrees kept forever by a dirty-tree rule that never asks whether the dirt is already on trunk** (36 are freeable; the rest hold staged assets absent from trunk); `--assert` liveness probe has zero callers; ~~loose objects 2.6×/day toward the auto-gc cliff~~ (STRUCK — 513, 7.7% of it) (§2.I) | population |

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
| P3 statics memo | ~~blob-sha-keyed verdict cache, re-round runs ratchets only~~ **STATICS HALF DONE 2026-08-10** (`scripts/lib/gate-memo.sh`); **arm half NOT DONE, deliberately** — see §5.P3 below | ~~re-round cost ≤10s at load~~ **NOT MET, and not reachable this way**: statics 2.15-2.27s → 0.14s ✓, but the whole re-round is 127-137s and the ratchet arms are ~112s of it |
| P4 loud lifecycle | trap+attest; in-flight marker read by wrap-ledger/completion-assert; waiter registry; orphan-holder page; verb allowlist; failure inbox (`refs/land/failed` + backlog row) | zero silent land deaths; zero mid-flight 📦 convictions; a dead author's failed land renders at the next close |
| P5 verifier share | fire `70dff02dcf4a` (repo half now; C10 half stays operator-owned); R7 escalation arm | verifier p50 <2h; ≥1 green/day; deploy T1 advances without hand-pulls |
| P6 converge completeness | ~~extend link-refresh classes; CLAUDE.md parity leg; UNGATED verdict files~~ **DONE 2026-08-10** (see §2.E "P6 IMPLEMENTED") | `LIVE_ADDS` breach impossible for any install.sh **symlink** class ✓ · CLAUDE.md sensed ✓ · UNGATED files ✓ · hand-pull rate → 0 *(pending — the filed row is the escalation, not the cure)* |
| P7 population policy | ~~checkpoints retention~~ (DROPPED — already exists and runs, §2.I ERRATUM) + KEEP-ladder content question (`--dispose-landed-dirt`, per-dirty-path `ls-tree` identity) + `--assert` consumer (`cc-blockers` kind `janitor-stale`) | 36 of 84 dirty worktrees become reapable; a janitor that stops running surfaces on the board instead of silently |
| P0 self-measurement | ~~attestation fields + census panels~~ **DONE 2026-08-11** — see §5.P0 below | v2 §7 renders as a computed verdict — **mechanism met; the latency criterion becomes CHECKABLE from the next land on, and is not claimed retroactively** (the field has a birthday; §5.P0 states the coverage) |

### §5.P3 — what the statics memo actually bought, and why the ratchet half is filed rather than shipped

*(Implementation note, 2026-08-10. INTEGRATE-only: the row above is struck, not deleted, because
the target it states is the thing this note refutes.)*

**Shipped**: `scripts/lib/gate-memo.sh` — per-file verdicts for shellcheck / `bash -n` / py_compile
keyed on the blob sha **plus the checker's own version**, so a ShellCheck upgrade invalidates rather
than carrying a verdict it no longer means. Every unknown re-runs: a miss, a corrupt body, an
unreadable entry, a superseded version, and any red. Only rc 0 is ever recorded, so a red is never
replayed from cache and a corrupt store cannot manufacture one. Pinned by `tests/land-gate-memo.bats`
(9 tests), RED-proofed against a naive control memo (`tests/fixtures/gate-memo-naive.sh`) that keys on
path alone — the control fails exactly the invalidation, corruption and dirty-tree tests and passes
the rest, which is what attributes each test to a mechanism.

**The item's premise does not survive measurement.** P3 says the re-round waste is re-proving the
statics. Measured on this worktree:

| | cost |
|---|---|
| statics phase, re-round — **before → after** | **2.15-2.27s → 0.14s** (3 samples each; 0 files sent to the checker) |
| whole gate, cold | 149s |
| whole gate, re-round | 127-137s |
| the fifteen ratchet arms inside it | ~112s (~88s main runs + ~24s `--selftest` preambles) |

So the statics were ~2% of a re-round. The memo retires them completely and the **≤10s target is
untouched** — it was never reachable by memoizing statics.

**The arm half is left alone, per the item's own "where an arm cannot be keyed soundly, say so".**
Three findings, in order of how much they bind:

1. **An arm's verdict is not file-local**, so the blob key does not transfer. `test-hermeticity`
   rule 4 asks whether two tools name the *same* scratch path — a property of a PAIR of files, so
   no per-file verdict exists for either one to cache.
2. **The arm-level key the item prescribes has a measured ceiling below the target.** Keying an arm
   on (lint blob + scanned-set state) lets a re-round skip it only when the sibling's delta missed
   that arm's population entirely — true for **35-46% of the last 200 lands** per arm, and **27%**
   against a whole-tree-minus-prose population. That retires one to two re-rounds in five
   completely and does nothing for the rest.
3. **The population declaration it would key on is not a superset today.** The natural source is
   each arm's own-scope pathspec, maintained under a stated invariant ("THE PATHSPEC IS THE GATE'S
   SCOPE, and it must list every population the lint judges"). Two counter-examples found by
   reading the lints: `unattended-path-lint` also judges `settings.json`, which its pathspec does
   not list, and pipefail's pathspec lists `docs/*` — so neither the declared spec nor
   "tree minus prose" is reliably a superset. Keying on a non-superset is precisely the
   stale-verdict generator the item forbids, and an unsound memo on a repo-wide arm is worse than
   the seconds it saves.

**What would actually reach ≤10s** is per-file memoization *inside* each lint's scan loop — the same
blob key, applied where the population is. That needs a file-locality proof per lint (finding 1
already fails it for one) and touches ~15 gate scripts, so it is a **separate item, not a silent
widening of this one**. The prerequisite for it is a mechanical read-set declaration per lint, which
is also what would make finding 3's superset claim checkable instead of asserted.

### §5.P2 — the per-arm own-diff blocking audit, and what shifting left actually shifts

*(Implementation note, 2026-08-11, backlog 46eb9be14249. INTEGRATE-only: §5's P2 row states the
target; this is what the fifteen arms were measured to do.)*

**Shipped, three parts.**

1. **`scripts/ship-land.sh --precheck`** — the commit-time entry point. It is a dispatch verb on
   ship-land itself, so it calls the identical `run_gate()` on the identical range; there is no
   second implementation of any rule and therefore no second authority to disagree. It takes no
   lock, writes no `land.log` row, claims no in-flight marker, writes no backup ref, files no
   inbox row, never rebases, and is offline by default. `--working` gates the WORKING TREE
   (`git diff <base>` with a bare rev), which is the position an author is actually in at commit
   time and the one `--dry-run` structurally cannot reach — `--dry-run` refuses a dirty tree and
   rebases the branch before gating, and a check that rewrites your history is not a commit-time
   check. Pinned by `tests/gate-precheck.bats`.
2. **`scripts/gate-red-census.sh`** — the rate, its causes, and its denominators, rendered.
3. **Three own-diff blocking leaks fixed**, plus the caller-side own-scope mechanism.

**Part 1's honest scope, per §5.P3's first finding.** The precheck runs the statics AND all
fifteen ratchet arms — ~112s of the land gate's 127-137s, i.e. the expensive part, not the cheap
2%. It does NOT run the /Users/chrisren/.claude/bin/cc-bats smoke phase. That is a deliberate line and it is stated in the tool's
own output, not only in its header: smoke is already `none`/`skipped` on **84.8%** of the
invocations that record the field (`gate-red-census.sh`, 1,651 invocations, 2026-08-11 — §2.B's
"89%" is the same finding taken by hand; the tool is now the citable source, and the two differ
only in how they treat the 20.8% of rows predating the `smoke` field), so its absence cannot move
the red rate the entry point exists to pre-empt, while
including it would have made the check cost a corpus. Measured cost of a full precheck on this
worktree: **3m35s**, against a land round that costs the same gate PLUS a fetch, a rebase, an
attested exit-6 row, a failure-inbox row, and a lock round-trip — and that cannot be run before
the commit exists at all.

**The entry point's own first defect, found by the land gate on this very commit — and worth
recording because it is the failure mode the whole design is supposed to exclude.** `--working`
was built on `git diff <base>`, which reports only files git already knows about. A **brand-new,
untracked file was therefore invisible to every own-set the gate builds** — and a new file is the
commonest thing an author has in hand at commit time. Measured live: `tests/gate-precheck.bats`
was untracked, `--precheck --working` said **GREEN**, and the land then said **RED** on that
file's missing `$HOME` fixture. That is precisely the *clears a tree the land will refuse*
direction, i.e. a second authority disagreeing with the first, arriving through the data the two
were reading rather than through the rules they applied — the identity tests all passed because
they compared verdicts over the same *visible* population. The fix makes the untracked files
visible via `git add -N` into a **throwaway copy of the index** (`GIT_INDEX_FILE`), so every git
command in the gate sees them and the author's real index is never opened for writing; a
partially staged tree survives untouched. Pinned by a regression test that also asserts the file
is still untracked afterwards. If the scratch index cannot be built, the precheck says so out
loud rather than silently reporting on a tree the author does not have.

**Part 3, the audit.** Every arm was read for the same question — *can a finding on a file this
land did not touch contribute to a non-zero exit?* — and every answer was then exercised with a
per-arm mutant (`tests/gate-ownscope-leak.bats`, 17 tests): one fixture tree carrying a violation
of THAT arm's rule and nothing else, asserted in every reachable own-state, including the states
that must still block. A suite that only proved "does not block" would pass against a deleted
ratchet.

The mechanism is three states, and every leak was a collapse of two of them:

| | own-set | meaning | required behaviour |
|---|---|---|---|
| UNSET | no caller scoped | strict | the whole tree may block |
| SET-BUT-EMPTY | a caller scoped, owns nothing here | a docs-only / launchd-only / commands-only land | **nothing** may block |
| SET | a caller scoped | these files are mine | only these may block |

ship-land ALWAYS exports the variable, so SET-BUT-EMPTY is the common case, not a corner — and a
lint spelling its presence test `${CC_X_OWN:-}` cannot express it.

| # | arm | verdict | evidence |
|---|---|---|---|
| 1 | test-hermeticity | does not leak | all ten blocking counters increment inside `in_own`; verdict is their sum (`:1580`). Latent: the own-set is basenamed (`:1289`), so a same-named file in another dir would block — **no basename collisions exist in the tree today** (checked across `bin/ scripts/ hooks/ tests/`) |
| 2 | wall-clock | does not leak | `bombs`/`stuck` inside `in_own`; verdict `:153`. Own-set population = judged population = `tests/*.bats`, so the basename collapse is 1:1 |
| 3 | AF_UNIX | does not leak | `bad`/`stuck` inside `in_own`; verdict `:175`. Same 1:1 population |
| 4 | git-identity | does not leak | `bad`/`stuck` inside `in_own`; verdict `:335`. Same latent basename vector as arm 1, no live collisions |
| 5 | UTC-stamp | does not leak | `bad`/`stuck` inside `in_own`; verdict `:155`. Matches the PATH, not the basename — which is why ship-land strips the leading component (`:1904`). Separate defect filed, see below |
| 6 | pipefail-SIGPIPE | **LEAKED — FIXED** | `${CC_PIPEFAIL_OWN:-}` (`:327`) — two-state. Measured pre-fix: empty own-set ⇒ rc 1 over a sibling's file |
| 7 | /Users/chrisren/.claude/bin/cc-bats dead-assertion | does not leak | no own-set at all: ship-land hands it an explicit file list, and the lint cannot judge a file it was not given. The tightest of the fifteen |
| 8 | script-dir self-path | does not leak | `bad` AND the stuck-ratchet half both inside `in_own` (`:346-365`); verdict `:400` |
| 9 | pane-spawn coverage | does not leak | exactly one `rc=1` site (`:147`), reached only past the own-scope `continue`. Reads no state outside the repo |
| 10 | unattended-PATH | **LEAKED — FIXED** | the stuck-ratchet `return 1` (`:896`) consulted neither `$own` nor `$have_own`. Measured pre-fix: rc 1 in **all three** own-states, including one naming a different file |
| 11 | permission-gate | does not leak | `bad`/`stuck` inside `in_own`; verdict `:475` |
| 12 | chromium-bundle | **LEAKED — FIXED** | `${CC_CHROMIUM_OWN:-}` (`:90`) — two-state, same defect as arm 6. Its own `--selftest` **encoded the defect**: the harness defaulted the own-set to `""` and set the variable unconditionally, so every case labelled "strict" was in fact running SET-BUT-EMPTY and passing only because the lint conflated them the same way. A control that encodes the defect cannot catch it |
| 13 | TSV field-collapse | does not leak | `bad`/`stuck` inside `in_own`; verdict `:258`. Its basename leg is deliberately over-wide and documented (`:64-67`) — that direction costs a loud nameable refusal, not a silent pass |
| 14 | .bats shellcheck | does not leak | LINE-scoped; `bad` inside `in_own` and the scanned set is pre-narrowed to suites carrying an own line (`:627-641`). Its one file-scoped path — an UNANALYZABLE suite whose shellcheck run aborted — is argued at `:62-71` and is a deliberate exception, not a leak |
| 15 | unguarded-kill | **by design, not a leak** | strict whole-corpus, no own-set. Declared at `ship-land.sh:2425-2429` with its reason (the introducing commit swept the corpus to zero, so the strictest rule is the free one) and a named release. Its correctness rests on an unenforced runtime invariant — baseline stays 0 — which is filed, not fixed: weakening it would lower the bar, which P2 forbids |

**The caller side had a fourteenth defect, and it was the escape hatch itself.** All thirteen
env-scoped arms read `[[ "${SHIP_LAND_<ARM>_OWN_SCOPE:-on}" != "off" ]]` to decide whether to
BUILD the own-set, then exported `CC_<ARM>_OWN="$own"` **unconditionally**. Setting the documented
kill switch — whose own comment reads *"restores whole-tree blocking"* — therefore left the set
empty and still exported it, so the lint saw SET-BUT-EMPTY and blocked on **nothing**. The escape
hatch for a leaking arm silently DISABLED that arm. All thirteen now route through one
`own_run()` helper that `unset`s the variable on `=off`; the switch is consulted in exactly one
place, so a later arm cannot get it wrong by copying a neighbour, which is how all thirteen came
to share one defect. Two sibling suites pinned the OLD spelling (`grep -q 'CC_PERMGATE_OWN='`,
`grep -q 'CC_BATS_SC_OWN='`) and went red on a change that kept the wiring and moved only its
shape — the assertions working, not failing. Both are now keyed on the variable NAME, and
permission-gate's leg-execution harness extracts `own_run` from ship-land rather than stubbing its
own, since an undefined `own_run` there is a command-not-found swallowed by the harness's
`2>/dev/null`, which would have made all four of its mutation cases pass vacuously.

**§5.P3's two named leads, resolved.**
- *unattended-path also judges `settings.json`* — **REFUTED, the lead is stale.** Every
  `settings.json` occurrence in that lint is a comment, and `:686-698` records that intersecting
  the population with the live settings.json was **removed** precisely because it made the verdict
  a function of the operator's machine rather than of the tree. `hook_population` is `ls hooks/*.sh`
  and nothing else.
- *pipefail's pathspec lists `docs/*`* — **confirmed, and not a leak.** The lint's own filter
  accepts `*.sh|*.bats|bin/*|hooks/*|scripts/*`, so `docs/*` in the pathspec can only widen the
  OWN-SET, never the judged population.
- *a third arm whose declared scope disagrees with what it judges* — **none found.** Judged
  population ⊆ ship-land pathspec was verified for all fifteen under the default environment.
  Two unread widening SEAMS would break that if anyone ever set them — `CC_PERMGATE_SET` and
  `CC_TSVPAD_DIRS` move a judged population without moving the pathspec. Filed.

**What the fix does NOT claim.** The spec's "gate-red ≤10%/day within two weeks" is a trailing
outcome no single session can observe, and it is not claimed here. What is claimed is mechanism
plus a baseline the census now renders, so the claim becomes checkable later by re-running one
command instead of reconstructing it by hand.

**Filed rather than fixed, with reasons** — each is a real finding, none is an own-diff blocking
leak, and pulling them in would have been scope metastasis on a file three siblings had just
landed into:
1. **Nine arms collapse a lint's exit 2 (could-not-run) into `gate_red` (your tree is bad).** This
   is the NON-VERDICT class that `5e53e629` fixed for two arms (afunix, tsv-pad) — a machine
   condition arriving as an author-fixable red. `permission-gate-lint` and `bats-shellcheck-lint`
   both go to real lengths to *produce* a distinguishable 2 that the caller then discards.
2. **`pipefail-sigpipe-lint`'s exit 2 is unreachable on the `--scan` path** (`hits="$(scan)" ||
   true` swallows the subshell's exit), so ship-land's `pf_rc == 2` → `GATE_KILLED` branch is dead
   code, and an unusable scan root produces exit 1 with a *fabricated* "you fixed a grandfathered
   site" report.
3. **`utc-stamp-lint`'s driver collapses `lint_dir`'s return 2 into `rc=1`** (`:238`) — a scan root
   with nothing to judge reads as "your tree is bad". Unreachable in this repo today (all three
   roots are non-empty), latent otherwise.
4. **`bats-assert-liveness` fails OPEN on every non-verdict** — ship-land reads its stdout, not its
   exit code, so a missing `python3` or a traceback reads as GREEN. Deliberate and commented, but
   it is the opposite direction from its four neighbours and worth an explicit decision.
5. **`unattended-path-lint`'s finding set is a function of the caller's live `$PATH`** — with the
   stuck-ratchet now own-scoped its blocking channel is closed, but "author's worktree green,
   landing box red" remains reachable from an inventory difference alone.
6. **The basename-collapse vector in arms 1, 4, 5 and 13** — latent today (no collisions in the
   tree), and it fails toward blocking, so it would surface as a loud nameable refusal.

### §5.P0 — the instrument, and the two things measuring it changed about the findings

*(Implementation note, 2026-08-11, backlog 42ee2eaeed97. INTEGRATE-only: §5's P0 row is struck, not
deleted, and the two corrections below are corrections to THIS document.)*

**Shipped, five parts** (`48875a11` ship-land + suites, `638b0a1a` census + suite, and the doc
corrections in the same land).

1. **`total_s`, `gate_rounds`, `gate_s`** — plus `gate_arms_s` and `gate_statics_s`, because §5.P3
   already measured where the seconds are (arms ~112s of a 127-137s re-round, statics ~2%) and one
   opaque total cannot separate *re-gated three times* from *the remote hung*. Carried across the
   locked re-exec in the environment (`SHIP_LAND_T0`, `SHIP_LAND_MEAS_*`) and back through the
   post-state handover, for the same reason `SMOKE_*` already was: the fallback lane's gate runs in
   the CHILD, so an outer that re-derived the counter would report one round short and exclude the
   only gate that ran.
2. **Every terminal exit attests.** Implemented as ONE arm in P4's existing EXIT trap rather than a
   call bolted onto each of the fourteen `exit` sites — the set grows, and a rule enforced per-site
   is a rule the next author does not know about. Non-zero only: a zero exit either already attested
   or is a "nothing to land" no-op, and minting a success row for those would inflate the very
   denominator this item exists to make readable. The `SHIP_LAND_LANE`/`GATE_SCOPE` refusal had to
   MOVE to dispatch — it fired at a top-level line that runs before the traps are installed and
   before `attest_land` is defined, so the one exit code an operator can reach by typo was
   structurally incapable of attesting.
3. **`smoke:"none"` split.** See the correction below — it was six causes, not five.
4. **Census panels** in `scripts/gate-red-census.sh` (P2's renderer, extended — one reader per
   store): LAND LATENCY split by outcome, GATE COST (rounds + arms vs statics), STALENESS
   (P(stale|waited), the wait-free column, rounds/land) and MUTEX HOLD. Deliberately NOT merged
   with `cycle-time-census.sh`, and neither calls the other: that tool reads the postland STAMP
   store about the VERIFIER lane's cycle time. Two stores, two subjects, two tools.
5. **The published figures corrected**, with their coverage and decay mode — see below.

**Correction 1: `smoke:"none"` was SIX causes, not five, and the sixth is the second largest.**
§2.B says five. The code has six reachable in `land.log` (seven counting `--precheck`, which writes
no row): the audit's five — no-suites-in-repo, in-lock, selector-missing, selector-FULL, lint-only —
plus **the gate never reached the smoke phase at all**, because the fifteen ratchet arms `return 1`
straight out of `run_gate` and `SMOKE_STATE` was still at its initial value. Measured on the live
store: **305 of the 735 `none` rows are exit-6 rows**, i.e. 41% of the token's population is this
cause, and reading it as "no suite mapped to this diff" is reading a refusal as a coverage decision.
It is now `none-unreached`.

**Correction 2: the wait-FREE staleness column was measured on the WRONG SENSOR, and the right one
did not exist.** §2.B derives P(exit-42 | wait>0) and the wait-free column from the LOCK ledger,
which is the only place a `wait_s` lives — and that ledger is structurally blind to exactly the
population the column is about, because a round that never queued still takes the lock and still
goes stale, but its row is indistinguishable from a fast successful hold unless the wrapped
command's exit happens to be 42. Re-measured on 2026-08-11 the lock-side numbers hold and have
sharpened (P(stale|waited) 53.7%/14d → 90.4%/3d → **95.8%/1d**; wait-free 11.4% → 25.5% → **31.2%**,
so the audit's "rising" reading is confirmed and the level is higher than the 48% partial-day figure
suggested). The tool-side sensor P0 adds — one `stage:"round"` row per re-round, written by the
OUTER process after the lock releases — is the one that sees rounds the lock ledger cannot attribute,
and its column reads **0 for all of history**: the field has a birthday, and the census says so
rather than reporting an absence as a zero rate.

**The published figures, re-measured** (and this is the third time this document's own numbers have
had to be re-derived rather than quoted, which is the finding):

| figure | published | measured 2026-08-11 | population |
|---|---|---|---|
| mutex hold | README "5-15s" · ship.md "84-302s" | **p50 3s · p90 5s · p99 139s · max 146s** | 110 completed holds since `145fab7d` (P1, 2026-08-11T01:32Z) moved the sweep + reap out of the lock |
| mutex hold, before P1 | — | p50 61s · p90 228s · **max 6771s** | 1,571 holds |
| in-lock wait | ship.md "0s wait" | p50 **0s** · p90 0s · max 125s | same 110 |
| gate-red rate | 27%/14d → 39%/3d → 45%/1d (§2.B) | **29.3%/14d → 40.0%/3d → 40.8%/1d** | 1,678 invocations |
| land latency | *unverifiable — no duration field existed* | **coverage 0%, and honest**: the field ships with this land | — |

Two of those needed a mechanism, not just a re-run. The hold figure was wrong in **two directions at
once** in two documents, for a day and a fortnight respectively, because its only home was prose:
nothing could refute it more cheaply than an investigation. It is a census panel now — and the panel
carries the warning its own data demands, that a rolling window spanning P1 pools two mechanisms and
describes neither. The latency figure is the sharper case: v2's acceptance criterion named
`land.log` and instructed "measure it, do not narrate it", and the field it needed was never there,
so **the criterion was narrated for v2's entire life**. It is now checkable, from the next land
forward, and reporting it as 0%-coverage rather than back-filling an estimate is the whole point
(memory: published-figure-decays-with-its-source).

**Filed rather than fixed, and the reason is a boundary rather than an effort estimate.** §5.P2 item
1 — nine ratchet arms collapsing a lint's exit 2 (COULD-NOT-RUN) into `gate_red` (THE TREE IS BAD) —
is the same non-verdict class as splitting `smoke:"none"`, and it is deliberately NOT taken here. It
is already backlog **`446fe07464e0`**. The two look alike and are not: `smoke` is an ATTESTATION
field that decides nothing, so splitting it changes what the store can say and cannot change what a
land does; the exit-2 conflation decides whether a land is refused as **6** ("fix your tree") or
**9** ("retry when the box is quieter"), across nine arms, each needing a mutant that produces a
genuine 2 and one that produces a genuine red. Folding a verdict-semantics change into a measurement
side-car would also break this item's own constraint — that the instrument fail no wider than itself
— by giving a bug in it the power to refuse a land. What P0 does give it is the instrument it was
missing: `red:"<arm>"` attribution plus the exit histogram make the conflation COUNTABLE, so the
next session can size it from a re-run instead of a re-derivation.

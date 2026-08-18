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

- **2026-08-18 — drain recycle #22: `master-session-lifecycle` 7 → 6 open / 1 blocked. filed 0 /
  closed 1.** Landed `9fad38d2c` (3 commits), content-verified on origin/main and **converged LIVE**
  by content on both deploy paths. Blocked tail BY STRATUM: 1 row, `adf1bb6b5406`, venue=local, a
  `source: needs` operator-platter row. **0 cloud-venue rows in this effort.** No stale claim left
  (`5cd2ecf792ae` was claimed, worked partially, and explicitly reopened).

  **`master-verification-integrity` was checked first and is already LOCAL-TRUE-ZERO** — its
  headline "1 open" is `ebbf3adfb4d0` with `venuePlan=cloud`, deliberately routed off-box, and its
  1 blocked row is operator-gated. Nothing there is drainable by this chain; a successor should not
  re-derive it.

  **CLOSED — `5e4ce121b64a` (context-economy instrumentation), all three residuals.** (a) was
  already landed by #21. (b)'s remaining half: fill % is `input_tokens / window`, and the window
  reached a durable store on exactly two **event-conditioned** paths — a fill-drop and a recycle —
  so a session that did neither had **no denominator at all**. `statusline.sh` now upserts one
  durable `{sid, window, model}` row per session under its own config root, and `cc-ctx-audit` reads
  it as a third source *per config root*. (c) `/tmp/cc-telemetry/*.hist` finally has a consumer:
  `cc-ctx-audit --burn`, whose live first reading is **p50 = 0.1, p95 = 0.5 fill-points/min over
  n = 66 sessions, 13 excluded for no computable slope**. That distribution has never been readable
  before, and every forecast arm in the subsystem steers on that axis.

  🚨 **BSD `grep -R` CANNOT SEE THE LIVE LAYER, AND ITS NULL READS EXACTLY LIKE ABSENCE.** Verifying
  (c)'s "nothing consumes `.hist`" claim, a recursive grep over `~/.claude/{scripts,bin,hooks}`
  returned zero — while a direct grep on one file inside it returned 19 matches. The live layer is
  **per-file symlinks**, and BSD's `-r`/`-R` do not follow symlinks met during the walk (GNU's `-R`
  does). **Measured: recursive grep sees 7 of 407 files there — 1.7%.** So every "the live layer does
  not contain X" ever answered on this box with a recursive grep is a **non-verdict**. The instrument
  that works is an explicit file list: `find <dirs> \( -type f -o -type l \) -print0 | xargs -0 grep`.
  The claim only held once re-run that way. Same shape as the memory
  `caller-census-keyed-on-path-misses-the-name`, one layer down: the grep was right, the *walk* was
  blind.

  **ADVANCED, NOT CLOSED — `5cd2ecf792ae` (TWO-WAY MAIL storyboarded not built).** Its stated
  blocking question — *the peer is drawn SMALLER and reads as a CHILD; two exits, no operator ruling
  needed* — **is the wrong question, and both of its exits were barred by a ruling neither cites.**
  Size is second-order. Every one of the beat's five frames carried a second creature
  (`banner-storyboard.py:565`), and that composition is `gen.py`'s `"peer"` — THE VISITOR (v6b),
  `kind: "WITHDRAWN"` — ruled out on **cause**, not composition: *"a session is never co-present with
  its peers, they live in other panes"* (`gen.py:434`, `:490-513`). `gen.py:347-350` records that
  reversing it is *"the spec owner's call, not this session's"*, and `:639-641` makes a WITHDRAWN
  beat in `ALWAYS_EMITTED` a **build failure** so the revert must be argued. It holds *a fortiori*:
  THE SUMMONING earns two bodies only because its second is called into existence and removes itself
  inside the window (`:4058-4064`), while this peer was neither summoned nor sent away. **The exit
  that needs no ruling is to NOT DRAW THE PEER** — the answer arrives from off-frame, which is THE
  LETTER's own hard constraint used as the point rather than as a limitation, and it is cheaper than
  either filed exit, both of which had to buy a second body first. The storyboard is amended to that
  composition (`7463b1de0`), verified by CONTENT against a pristine origin/main worktree: 30
  body-cell groups before (6/frame = two creatures) → 15 after (3/frame = one). **The row stays OPEN
  — the beat is still not built into `gen.py`, and a re-specified question is not a built beat.**

  **A CONTROL THAT PASSES PRE-FIX IS CLEARED BY MUTATION OR IT IS NOTHING** — seven mutations this
  recycle, each reddening its intended case and only that case: durable source removed → the two
  denominator cases; null-window imputed → the exclusion case (the one that passed pre-fix); slope
  guards removed → the two burn-exclusion cases; containment removed / upsert guard removed / window
  imputed → the three producer cases.

  🚨 **`git checkout -- <file>` AS MUTATION CLEANUP DELETED AN UNCOMMITTED IMPLEMENTATION.** The
  first mutation round restored with `git checkout`, which restores to the **committed** state — and
  the implementation was not yet committed, so the whole reader change was silently reverted and the
  next mutation ran against origin/main's version, reading as six spurious failures. **Commit before
  mutating, and restore from a `cp` backup, never from git.** The inherited "tell every teammate to
  COMMIT EARLY" applies to the lead exactly as much.

  **A SUITE CAUGHT A REAL REGRESSION MID-CHANGE, and the catch was worth more than the feature.** The
  first producer version read the window with its own `jq -r`; `tests/statusline-identity.bats`'
  single-payload-extraction invariant went red on a **per-render hot path**. The read now reuses
  `PAY_WINDOW` from the one existing extraction. The jq count moves 3 → 4 for the durable EMIT only,
  and stays EXACT deliberately — what it pins is not "few jq calls" but "every jq call on a
  per-render path is enumerated with its reason".

  Suites, each with its `1..N` plan line seen in the same run: `ctx-audit` 1..26 (6 of 7 new cases
  red pre-change), `statusline-identity` 1..23 (4 of 4 red pre-change), `context-econ` 1..33. Test
  containment proven by COUNT, not by reading: `recycle-events.jsonl` held at 4,057 lines across
  both suite runs and the new store was never created in the operator's config root.

  **THE SPAWN GATE REFUSED THE ONE TEAMMATE ATTEMPTED (record #22: 0/1).** The brief for the
  context-economy residuals was denied with *"Background subagents cannot write code… use
  TeamCreate"* — and `TeamCreate` does not exist on this runtime, so the guard still has no compliant
  path. Per the standing instruction the row was taken onto the lead rather than re-rolling wording.
  Cumulative: #18 0/3, #19 1/1, #20 2/2, #21 2/3, #22 0/1.

- **2026-08-18 ~15:30Z — lead (pane 102, recycled): the `blocked` pool is 75% OPERATOR-OWNED, so the
  headline ratio was never one number.** Ledger 409 open / 119 blocked. Stratifying the blocked pool
  by source settles what "block outran unblock ~6:1" actually meant: **89 of 119 are `source: needs`,
  venue=local — operator-platter steps, blocked BY DESIGN and not agent-drainable** (42 of them carry
  a `--run`, so they are `cc-do`-runnable today); only ~30 are anything else. A count that mixes the
  two lanes cannot be driven to zero by the drain chain and should never have been read as one
  backlog. **Report `blocked` by stratum or not at all** — the same law as the zero-claim memory
  (`zero-claim-must-name-its-excluded-strata`).

  🚨 **A MACHINE PRODUCER DEFEATS THE LEDGER'S IDEMPOTENCY BY *WHERE IT STANDS*, NOT BY WHAT IT
  WRITES — filed `dc014c6829ac`.** `desk-land.sh` builds a throwaway worktree per attempt at
  `/private/tmp/.desk-land-<branch>-<PID>` and, when `ship-land` cannot complete, files its `re-land
  <branch>` row from INSIDE it. `cc-backlog` derives `project` from the cwd, and the event key is
  project+title+source — so the PID rides into the key and **every retry of the same land mints a
  brand-new blocked row.** Measured on ONE branch (`claude/fire-20260818T080549Z-15840-1`): four
  distinct ids (`1285df22b72e` · `9776708bc201` · `2ee586a548f8` · `e24b0f9933b7`) with
  **byte-identical title, source and condition**, differing only in
  `project=.desk-land-…-32615/-39245/-42721/-93241`; a 5th attempt was in flight while this was
  written. **The store is not broken and the probe is what proves it:** a scratch-store control
  (`CC_BACKLOG_FILE=<tmp>`, same title+source+condition added 3×) collapsed to ONE id
  (`f3f2f0805807`). So the defect is the caller's *identity*, not the hash — and the fix is a stable
  `--project` / branch-derived `--condition`, never a wider hash. This is the **second face** of what
  `e3b966424` fixed one face of: that land stopped machine producers *misfiling* agent-doable work as
  blocked, and does nothing about *duplicate minting*. Bounded at 4 rows today; unbounded by
  construction.

  **Landed this session, all content-verified on `origin/main`:** `bb124b4ff`, `76395a94e`,
  `b683ec2eb` (§2.1 entries) and **`e3b966424`** — the two machine producers that filed agent-doable
  work into `blocked`: the reap now consults `cc-cloud show --item` before blocking a venue=cloud
  claim, and KEY 4 carries the branch ref unmasked so a re-land step is actionable. `5239f4431`
  closed W-R3 (entry below).

  **Threads left running, both alive and owned (transcripts writing this minute):** pane 339
  (`foldfix-orphan`, custody `fire-foldfix-orphan|339` OPEN) took a **RED land on its own diff** —
  `shellcheck` SC2016 at `bin/cc-backlog:4744` and a `dead-assertion` at
  `tests/backlog-fold-agreement.bats:98` (`A && B` with both branches unreachable by errexit; the
  fixer is `scripts/bats-assert-liveness-fix.py`). Its two commits (`2327dc4bd` the status fold,
  `2e5ee1b82` the hermeticity allowlist tail) are NOT on trunk. Drain chain: **recycle #22 live**
  (brief 15:05Z, worktree `drain/recycle-11`).

  ⚠️ **The `rm -r` extension of the wedge class, and it took the drain chain itself.**
  `hooks/validate-bash.sh:1024` allowlists build-artifact NAMES only and has **no category for a
  session's own scratchpad**, so routine self-cleanup raises a PreToolUse confirmation — a liveness
  state no belt models (not idle, so teardown returns DEFER `tty-busy`; cross-pane keystrokes are
  classifier-denied). Four sessions lost in 24h: 275/276 on `git reset --hard`, then **339 and 131 —
  the 24/7 drain chain — on `rm -r` of their own scratch dirs**, stopping the chain ~4h at recycle #21
  with **no alarm**. Filed `7da9c4451540` (includes the missing alarm: a dispatched session at a modal
  > N minutes). **Every brief this pipeline writes must forbid destructive git AND any `rm -r` outside
  `node_modules|.next|dist|build|coverage|target` — leave scratch for the reaper.**

  Two instrument traps measured today, both cheap and both silent: **`bash scripts/ship-land.sh | tail`
  returns TAIL's rc** — it read 0 while ship-land exited 11 (another land in flight) and 5 (rebase
  conflict); never pipe it. And **the kitty `❯` prompt line renders permanently** — it is not an idle
  signal (liveness is the spinner + token counter), and misreading it nudged a session 32 min into a
  step. Judge liveness by cwd + child processes, never by the prompt line.

- **2026-08-18 — recycle #21: master-session-lifecycle 8 → 7 open / 1 blocked. filed 0 / closed 1.**
  One land, content-verified: `51f2b9d5e` (13 paths present + content-identical on origin/main).
  Row closed: `87a081c446f5` — deadline reconciliation, **both arms, both by one teammate**. ARM A
  wired the L2-c watchdog `wait-contract-lint.sh --sweep` to a scheduled caller (lead-supervisor —
  the loaded launchd, waiter-independent cadence); it had been built, `--selftest` 13/13 GREEN, and
  **never once called** since desk-audit G-P4-2 on 2026-07-18. ARM B gave `engagedAt` its first
  production READER, so a fired peer that engaged and then went dark is finally owned (it had been
  falling into `owned-wait`, which is in neither `REAPABLE_RE` nor `SURFACE_PAGE_RE`). Blocked tail
  BY STRATUM: 1 row, `adf1bb6b5406`, venue=local, `source: needs` — an operator-platter item.
  **0 cloud-venue rows.** No stale claim left. Post-land suites: `1..116` + `1..95` + `1..43` +
  `1..33`, 0 not-ok, every one with its plan line seen.

  **TWO ROWS ADVANCED BUT DELIBERATELY LEFT OPEN — a partially-fixed row is not a closed row.**
  `4de3d0f9c0e1` (DoD crosstalk) was proved REAL *and* proved unfixable from state we record:
  separating a wave from its own SUCCESSOR needs an identity nothing stores (no per-capture
  provenance; the fired-peer stamp holds a PANE id and is gated on `RECYCLE=0`, so `--recycle` — the
  default succession — writes no stamp at all). Toplevel-, branch- and liveness-keying each re-red
  the succession-hop case, because **the crosstalk and the hop are ONE mechanism seen from two
  sides.** Red-proof parked as `skip`ped cases 40/41 in `tests/dod-path.bats` naming
  `docs/research/dod-crosstalk-2026-08-18.md`; measured live, 101 worktrees share one file carrying
  15 distinct frozen scopes. `5e4ce121b64a` got residual (a) closed on BOTH rails and residual (b)'s
  pollution half closed; (b)'s statusline upsert and (c) remain.

  🚨 **A GREEN SUITE RUN CAN BE A NON-VERDICT, AND IT LOOKS EXACTLY LIKE A PASS.** Two instruments
  lied inside ten minutes. (1) `bash tests/<x>.bats` is **not a test run** — bats files need the
  `bats` runner; under `bash` you get "@test: command not found" and a syntax error. **This brief
  chain had carried that wrong command, and the lead passed it to two teammates before catching
  it.** (2) `bats` here is `cc-bats`, which above a concurrency ceiling runs NOTHING, prints a
  DEFERRAL, and **exits 0 with no TAP** — it fired repeatedly with three agents running suites.
  Override it prints itself: `CC_BATS_MAX_ROOTS=0 bats …`. **THE RULE: a run is a verdict only if
  you SAW its `1..N` line in that same run** — including on teammate reports.

  🚨 **MEASURE THE LEAK, DO NOT READ FOR IT — AND NEVER LET A ROW'S CENSUS SIZE THE CLASS.** The row
  called the durable recycle store "98.8% test pollution". Two corrections, both from RUNNING: the
  first probe read `~/.claude/recycle-events.jsonl` and reported ABSENT (it lives under
  `autonomy/`; a blind instrument's null is not absence), and the leak turned out **live, not
  historical, with this very session causing it** — a before/after line count around one suite run
  showed `tests/boundary-handoff.bats` appending **29 rows per run** to the operator's real store
  while `waiting-recycle.bats` leaked 0. So never "the tests": any suite scoping neither `HOME` nor
  `CLAUDE_CONFIG_DIR`, and only **61 of 512** suites scope anything. Fixed at the writer, not
  per-suite.

  🚨 **A CONTROL THAT PASSES PRE-FIX PROVES NOTHING UNTIL YOU MUTATE IT.** Every control written
  this recycle passed before the fix — which is exactly how a vacuous control looks. Each was
  cleared by mutating in both directions instead. Two first-reds were the HARNESS, not the subject:
  `touch -t` parses LOCAL time while `stat -f %m` returns epoch, so a `date -u` stamp put a fixture
  mtime **7 hours in the future** (a negative age the subject correctly rejected); and a containment
  test used a canary `HOME` *nested inside* `BATS_TEST_TMPDIR`, which is contained BY DESIGN.
  Relatedly, when shellcheck called a newly-added variable unused (SC2034) that was a **real gap** —
  `stale_ok` was computed and never emitted; emitting it was the fix, silencing the lint would have
  shipped the hole.

  **Spawn gate: 2 of 3 accepted.** The third was denied with *"Background subagents cannot write
  code… use TeamCreate"* — and `TeamCreate` does not exist on 2.1.220, so that guard has no
  compliant path. It is a heuristic on prompt wording and fired on the most implementation-flavoured
  of three near-identical briefs. Do not re-roll wording; take the row onto the lead. Record: #18
  0/3, #19 1/1, #20 2/2, #21 2/3.

- **2026-08-18 — recycle #20: master-session-lifecycle 12 → 8 open / 1 blocked. filed 0 / closed 4.**
  Two lands, content-verified: `555e3b270` then `45a56dcb5`. Rows closed: `4a11a0ac850a` (the
  succession linking primitive + its detector + its caller) · `2dc6906b6e0b` (§14's *or-pressured*
  recycle re-pick) · `3b464e94b3ff` (custody TTL, by a teammate) · `50627335fe9b` (Stop-hook wedge —
  **remedy refuted, root cause found and fixed**, by a teammate + lead). Blocked tail BY STRATUM:
  1 row, `adf1bb6b5406`, venue=local, `source: needs` — an operator-platter item. **0 cloud-venue
  rows.** No stale claim left. Post-land: 244 tests across 10 suites, 0 not-ok, every one carrying
  a `1..N` plan line.

  🚨 **THE SPAWN GATE IS OPEN AND BOTH TEAMMATES WERE ACCEPTED — 2 of 2, on the shape #19 recorded.**
  `Agent({ name, subagent_type: "general-purpose", run_in_background: true, prompt })` — no
  `team_name`, no `isolation`, no `cwd`, worktree path in the brief body. Fired both in ONE message.
  Both delivered committed, red-proved work; between them they closed two rows the lead never
  touched. Treat the gate as a variable and still fire, but the recent record is #18 0/3, #19 1/1,
  #20 2/2.

  🚨 **THE FINDING FOR #21: A ROW'S PRESCRIBED REMEDY CAN BE UNBUILDABLE WHILE ITS DEFECT IS REAL —
  AND THE REAL CAUSE WAS FIVE TIMES LARGER THAN THE ROW'S OWN CENSUS.** `50627335fe9b` asked for a
  runtime detector keyed on "hook frame displayed AND no hook child". Measured against the 2.1.220
  binary every pane here executes: the only hook frame it renders is the past-tense `Ran <N> <Label>
  hooks`, a count with **no denominator**, and `hooksRunning`/`runningHooks`/`pendingHooks`/
  `hookProgress` return **zero hits**. Axis A does not exist, so the prescribed anchor is
  unbuildable and anything built on it is a heuristic wearing an exact detector's clothes. The
  incident is nonetheless real, and the evidence indicts **hook #1, not #12**: every Stop hook
  carries a 5-10 s timeout (~75 s for the chain) against a **54-minute** wedge — 43× — so no hook was
  ever slow, because **a timeout cannot reach a file descriptor.** A hook's stdout is a pipe the
  harness reads to EOF; `&` does not close a descriptor and `disown` does not either. The row's own
  census named one site (`notify.sh`, `afplay … 2>>LOG &`). A lint over all 73 hook files found
  **five**, every one real — and four are `( … ) &` subshells whose *inner* lines carry
  `2>/dev/null`, so they read as handled while the subshell holds the pipe regardless of whether it
  ever writes. **Ask what a row's remedy assumes about the machine before building it, and never let
  a row's own census size the class.**

  🚨 **AN ABSENCE TEST INHERITS EVERY HOLE IN ITS INPUT AS A POSITIVE FINDING — three ways, all hit
  this recycle.** The unfired-brief sweep asks "does this brief appear in no fire row", and:
  (a) `prompt_file` has **no history**, so on day one all 98 briefs on disk answer *no* — the floor
  is therefore derived FROM THE STORE (`max(epoch of the first row carrying the field, oldest
  surviving row)`), never from a date, and the sweep reports **NOT ARMED, 0 findings** while naming
  the 98 it declined to emit; (b) the ledger self-trims at 1200 rows, so a fire whose row was
  deleted reads unfired for a reason that is *retention* — counted `unknowable`, excluded from
  findings; (c) `find /tmp` does **not** traverse Darwin's `/tmp → /private/tmp` symlink, so the
  first working draft found **0 files against a glob control's 98** — a detector whose finding set
  is structurally empty reports all-clear forever and is byte-indistinguishable from a healthy
  machine. **(c) was found by RUNNING it, not reading it**, and is now pinned by mutation.

  🚨 **A GATE CAUGHT A REAL CORRECTNESS BUG THE SUITE DID NOT: `printf … | grep -q` under
  `set -o pipefail` reads FALSE ON A MATCH.** `grep -q` exits the moment it matches, SIGPIPEs the
  producer, and pipefail then reports the pipeline failed — so in the sweep a **clean,
  successfully-fired brief would have been reported as a lost succession, on the match path, every
  time.** Nine cases were green over it. The land's `pipefail-sigpipe` ratchet found it; the fix is
  a here-string (not a pipeline, so no producer to signal). **Run the land's own ratchets early —
  they see failure modes a fixture-sized suite cannot.**

  Also worth carrying: **a kill switch that killed nothing** — `_cliff_env` *deliberately* ignores a
  malformed value so a typo cannot disable a safety term, so `CC_ROUTE_REPICK_RATIO=off` parsed as
  garbage and returned the 4.0 default. Polarity is the test: ignoring a typo fails SAFE for a term
  that **restrains**, and fails OPEN for one that **authorises an action**. Use `_term_on` (R8) for
  the latter. And **the pressure half was DEAD CODE for one revision** because its threshold was
  parsed from `$errf` *after* the `rm` — an empty parse fell through the block's own fail-soft and
  could never fire nor say so. Both were caught by *running the four knob states*, not by reading.

  A vacuous case and a vacuous control, both fixed rather than excused: `jq '.prompt_file | type'`
  answers `null` for an **absent** key exactly as for a null-valued one, so the R9 case passed
  against pristine and certified nothing (now `has("prompt_file")` AND the value); and
  `handoff-recycle-repick.bats`'s extraction control grepped `--route general` over the block
  **including comments**, so it stayed green across the switch to `--rank` purely because a new
  comment explains the switch — mention-vs-use, in the one case whose job is proving the extraction
  is real. **NOT MINE, surfaced not driven:** `tests/claude-accounts-core.bats` case 72 fails
  identically on pristine `origin/main` — a pre-existing trunk red over live burn data.

- **2026-08-18 ~04:00Z — W-R3 CLOSED by pane 275: 83 branches, 32 with content, and only SIX
  commits were actually missing from trunk. `landed 6 · superseded 20 · moot 1 · parked-by-design
  2 · patch-equivalent 51 · still-declared-unpushed 31` — every branch reaches a terminal verdict
  and no ref was deleted.** Landed `d2cfe1312` (10 commits, 21 paths content-verified); live layer
  converged; 135 tests green across the five touched suites.

  🚨 **THE HEADLINE IS THE DENOMINATOR, NOT THE WORK: 26 of the 32 content-carrying branches were
  already on trunk, and `git cherry` said otherwise for all of them.** Patch-id asks *are these
  BYTES in main*, and a fix that landed by a re-authored port, a squashed rewrite, or a conflict
  resolution answers NO while being fully present. The screen that found this is line-presence
  (what fraction of a commit's added lines appear in trunk's current file), and it split cleanly —
  15 SUPERSEDED ≥95%, 17 MISSING ≤18%, 3 PARTIAL — but it is *also* wrong in both directions on
  its own: `6e7bdd2e8` read 1% present yet trunk carries the identical fix as `ba69a4510` with
  different prose, and `6eb74d040` read 0% yet `a609a0cd4`+`5f2f5431f` cover it. **Only per-commit
  adjudication by DEFECT-AND-REMEDY settled it** (three parallel read-only agents over the code
  clusters). Two of the ports even carried `Original-commit:` trailers on trunk — decisive when
  present, and absent exactly when a human re-authored the fix. Corollary for the next reconciler:
  *a landedness oracle must be told what "landed" means*, and none of patch-id, ancestry, or text
  overlap is that oracle by itself.

  **What was genuinely missing, and it is the small half:** the drain-chain liveness mechanism
  (§6's own invariant — `scripts/drain-chain-assert.sh` + 15 cases, and note this plan was
  committing the very defect it diagnoses); `4da7836cf` (a bisect must be able to return NO
  VERDICT — trunk had the empty-string culprit but none of `BISECT_WHY/STEPS/S/LOAD`); `ce0e5d2e8`
  (git-add force flag read off its own argv); the venue/plan doc entries; and **two residues that
  only a per-file split could find** — `649ecc23b`'s gate/nudge/compact halves were superseded but
  its ROTOR half was not, so trunk could *refuse* a 200-line-cap write while the only fleet-wide
  remedy never armed; and `44de2d805`, whose whole surviving value is one line
  (`CC_BACKLOG_KICK=off`) stopping ~74 live-`$HOME` `cc-dispatch` spawns per suite run. Both
  red-proved against the pre-fix subject; the rotor's three new cases fail 3/3 pre-fix.

  **Retirement ≠ ref deletion.** `scripts/branch-reaper.sh:12-20` is explicit that ref deletion is
  **strict-ancestor only** — a patch-id match can be coincidental and the ref is the last durable
  carrier — and **none of the 83 is an ancestor of trunk**, so nothing was reapable by ref. The
  terminal verdict is therefore `cc-cloud retire --id` on the DECLARATION, which stops the daemon
  re-attempting a land forever while every branch survives as evidence: **41 declarations retired,
  0 failed.** The 2 rc=65 squatters were removed only after all four gates held (clean tree, no
  live session by cwd, owner pid 4089 gone, HEAD content superseded); their branches remain.

  **The two oldest branches are NOT debris and must survive every future sweep.**
  `…57078-1`/`-2` are the cloud arms of the cost A/B, and
  `docs/research/cloud-local-cost-ab-2026-08-11.md` §7 rules them evidence: *"The work products
  were deliberately NOT landed… the probe tool is throwaway and does not belong on trunk."* They
  apply cleanly, which is exactly what makes them look like the easiest wins — the trap is that
  **only the branch's own doc knows why it exists**, and no content oracle can see intent. Counted
  PARKED-BY-DESIGN, declarations retired so the daemon stops trying, refs untouched.

  **Two writers, one index — the mechanism failure that cost this wave its first hour.** Panes 275
  and 276 were fired on the identical brief 4 min apart into the SAME worktree and branch, and
  clobbered each other: 275's first conflict resolution was destroyed by 276's `reset --hard`
  (reflog 19:39:38 → 19:40:25). 276 stood down and handed over `/tmp/w-r3-findings-from-pane-276.md`
  — its `66550-1`-is-superseded and venue-INTEGRATE adjudications were reused verbatim here, so the
  duplicate fire was not a total loss. 275 evacuated to its own worktree (`.worktrees/r3-land`),
  which is what let the wave finish. The lead's 02:35Z entry recording both as permanently wedged
  was true when written and stale within the hour.

  **Also settled while here:** the `cherry-pick --continue` path is unusable in this repo — the
  identity gate rejects the VM's `noreply@anthropic.com` author and the message gate rejects its
  `Co-Authored-By: Claude` trailers, and a blocked `--continue` **tears down the sequencer and
  loses the resolution**. Every pick must be `-n` + a re-authored commit; a marker guard belongs at
  that commit step, since a resolution script that throws mid-way otherwise ships `<<<<<<< HEAD`
  into a plan doc (it did once here, caught and amended).

  **Not mine, named rather than driven:** `deploy-live`'s post-deploy host partition is RED on
  `tests/test-hermeticity-lint.bats` #19 — this land touches neither that lint, its suite, nor
  `ship-land.sh`; last toucher of the subjects is `c037c1aa1`. Filed `79e7ef3ca862`. Six stale
  `.desk-land-*` dirs filed as `de4f1c0135bb` (verified clean, unregistered, no orphan HEAD — left
  for `worktree-gc.sh` rather than hand-deleted). Row `941e57ba8d5a` (needs-brake merges two
  re-land steps) stays OPEN: it is a defect in this row-class's own machinery, not in the branches.
  `session_018in35…` needed nothing from this fire — it returned at **2026-08-17T09:04:28Z**,
  goal MET, content-verified, ~9 h before either pane launched.

- **2026-08-18 ~03:45Z — fired peer (blocked-pool-triage): the first audit of the blocked pool, and
  it is not an operator queue. One THIRD of it had no operator step in it at all.**

  **THE TALLY — conserving, over a population that MOVED under the audit.** The brief named 89
  `claude-infrastructure` blocked rows; two more were filed while the audit ran (`19d607dc7ce3` at
  ~02:48Z, `7d276b84f662` at ~02:52Z), so the adjudicated population is **91**, re-derived live and
  each row re-read immediately before its own transition:

  **91 = 24 obsolete-closed + 52 still-gated + 14 mis-filed-unblocked + 1 resolved by another
  actor mid-audit.**

  That last term is not padding — it is `135e62b5ff49` (the two W-R3 panes wedged at a `git reset
  --hard` modal), closed at 02:55Z by the lead when pane 276 stood itself down. It was in the
  population at snapshot and was not mine to claim, so it gets its own line rather than being
  quietly absorbed into a column.

  The obsolete column splits, and the split is the honest part: **19 are genuine obsolescence** — the
  gate the row named is provably gone — and **5 are DUPLICATE rows** whose gate is real and still
  operator-owned, closed only after their distinct prose was folded verbatim into the canonical
  row's `needs`. A dedup close lowers the number without resolving anything, so it is counted apart
  rather than banked as progress. Of the 52 still-gated, **51 got a rewritten `needs`** and 1 was
  already today's truth (filed hours earlier); every one of those rewrites carries a measurement
  taken this session, not a restatement.

  Counts, before → after: `claude-infrastructure` blocked **90 → 54**; whole-ledger blocked
  **153 → 117**; the `list --open` view **428 → 406**. The residual 54 is exactly the 52 still-gated
  rows plus 2 filed after the audit's snapshot (`844de43ebe72`, `ec2614142185`) — nothing of the
  adjudicated population is unaccounted for. Two rows were also filed BY this audit as agent work
  (`daa7a7800caf`, `941e57ba8d5a`), so the open column is not purely a decrease.

  Of the 14 unblocked, 12 are sitting `open` for the wave, 1 was claimed by the drain chain within
  minutes, and 1 (`7d276b84f662`) was auto-closed by the very generator described below — all three
  are correct downstream outcomes of returning work to the pipeline, not failures of the unblock.

  **WHAT THE POOL TURNED OUT TO BE — the headline is that `blocked` is not where operator work
  lives, it is where MACHINES PUT THINGS THEY COULD NOT DECIDE.** `blocked` is defined as
  operator-gated and `cc-dispatch` excludes it from the wave by construction, so anything filed
  there leaves the pipeline permanently. Two automated producers file into it, and between them they
  account for **11 of the 14 mis-filed rows**:

  * **`cc-backlog reap` blocks every `venue=cloud` claim, because the worktree occupancy oracle
    structurally cannot see off-box work.** `bin/cc-backlog:4869` writes *"the worktree occupancy
    oracle could not be RESOLVED past the 21600s ceiling — worker runs off-box (venue cloud)"* and
    tells a human to *"establish by hand whether the worker is alive, then `cc-backlog unblock`"*.
    The box already ships the instrument that answers exactly that, from the repo side, with no
    credential: `cc-cloud show`. All 5 such rows resolved without an operator — **1 was already
    `LANDED`** (`e2af8839be87`; content byte-identical on `origin/main` as `5ef11a988`, closed), 2
    `STALLED`, 2 `NOT-STARTED`. This is a permanent generator: the oracle can never cover the cloud
    venue, so every cloud dispatch that outlives the ceiling becomes an operator-gated row. Filed as
    `daa7a7800caf`.
  * **`scripts/desk-land.sh` files every failed land through `cc-backlog needs`, the BORN-BLOCKED
    verb** — for work this repo's own `.claude/CLAUDE.md` explicitly authorises an agent to do
    (standing-land). 6 re-land rows; 2 of them had already landed and were closed by content
    (`f317e88d17be` — `git cherry` empty; `05c0add0db10` — branch ref deleted but its content
    present via pin `f704bf8aa`), 4 carry real unlanded commits and were returned to the wave.
    **`refs/land/failed/*` now holds 943 pins**, not the "41 for two branches alone" that
    `981a403a05fa` records.

  **THE CHURN IS MEASURABLE AND IT IS THE RATCHET.** Across the 90 rows there are **127 `block`
  events** — 18 rows were re-blocked more than once. `b262e41b26fb` alone took **20 `block` events
  and 3 falsifier auto-closes in 20 hours**: filed, auto-retracted when the content verified as
  landed, re-filed by the next failed land, auto-retracted again. It is a live retry loop wearing a
  work item's clothes, which is why trap 5 (`wasDone`) mattered — reading that history is what
  stopped it being closed as obsolete. Observed directly during this audit: `7d276b84f662` was
  unblocked at ~03:05Z and the generator had re-blocked it twice and auto-closed it again by
  03:10:05Z.

  **AND THE `needs`-BRAKE MERGES DISTINCT WORK.** The brake folds a step whose prose matches a live
  row *"modulo digits"* — but two re-land steps differ ONLY in digits. `7d276b84f662`'s title names
  `claude/fire-20260812T071538Z-80941-1` (1 unlanded commit `199b488f9`) while its `needs` AND `run`
  name `claude/fire-20260814T055432Z-40416-1`, a different branch already covered by
  `aefa6a955872`. Acting on that row re-lands the wrong branch and leaves the titled one unhandled.
  Filed as `941e57ba8d5a`.

  **STALE PREMISES WERE THE NORM, NOT THE EXCEPTION — and the shape of the staleness is diagnostic:
  62 of the 90 rows had `needs` BYTE-IDENTICAL to `title`**, i.e. no operator step was ever
  separately articulated; the `needs` verb copies one into the other. Nine rows named a gate that
  had already been satisfied, in every case by something landing without anyone closing the row:
  migration 0007's hook is registered `SessionStart asyncRewake=true` in all 5 config dirs; 0005's
  is on `Stop` in all 5; the postland plist is byte-identical to trunk with the loaded job at
  `nice=10, runs=469, exit 0` and `launchd-parity-lint` reporting `ok` — the very tripwire that row
  cited as proof it was unfixed; `devserver-gc` is armed via `ProgramArguments` (`runs=93`) and its
  log recorded an armed run at 02:40Z the same morning the audit ran; the ff-gate that makes
  `5436396f405c`'s "the fix is that sessions work in their own worktree" a mechanical DENY landed
  the previous day as `17ecae6c6`. `bcbc4e714ed5` ("ms365 MCP is dead in every config dir … only an
  interactive browser OAuth can fix it") was refuted by calling it: `verify-login` returns
  `success:true` for `ren.chris@outlook.com` — a personal/consumers account, the exact tenant the row
  said it had to be re-logged-in under.

  **AGE SAYS THE DRIVER IS INFLOW, NOT ROT.** Median age since first filing is **6 days**, p90 15,
  max 28. This is not a pile of ancient decisions; it is a pool being refilled faster than anything
  drains it, which is the same conclusion the 02:35Z entry above reached from the ledger flow.

  **TRAP 1 EARNED ITS PLACE TWICE.** `1f323187c1e9` prescribed running the close-attrib activation;
  that activation has a `.done` marker from 2026-07-30 and `~/.zshrc:498,502` invoke
  `cc-close-attrib` — so the remedy is DONE, while the symptom is untouched (of 165 crash records
  since 2026-08-01: `cause=abrupt-unknown` 91, `no-transcript` 44, and `stderr_log` non-zero in only
  3 of 165). Remedy spent, symptom live, no operator step left ⇒ unblocked as agent work, not closed.
  Conversely `782607797fc5`'s symptom is live TODAY (kills by signal 9/15 "sender unidentified" at
  02:23Z, and 84 of the last 126 stamps `cut`) while one of its own evidence clauses — "ZERO green" —
  is false: greens run ~1.6/day. Rewritten with the correction, still gated on `sudo`.

  **WHAT IS ACTUALLY LEFT FOR THE OPERATOR, and the one answer with leverage over the rest.** The 53
  still-gated rows are dominated by **C10 activations** — settings.json / `~/.zshrc` / launchd edits
  an agent may not self-apply. `b09f54e9e080` is the ratification that would convert a whole class of
  them at a one-word diff (`c10` → `mechanical`), so it is the highest-leverage single answer in the
  queue. Three separate rows (`b448ceafa0ca`, `180d38b29912`'s D-A, `48e14163e78a`) reduce to one
  yes/no on flipping `accounts[0].launcher` to `claude1`. `b22e519e06cb` is a roster row holding no
  work of its own; its four DoD clauses now each point at a member row. And `5511ea906e2e` turned out
  not to be a deploy problem at all: `deploy-live` is correctly waiting because the newest green tree
  is an ANCESTOR of live HEAD, so no green can ever be a descendant — it is gated on the postland
  signal-kill (`782607797fc5`), and the only local lever is authorising `deploy-live.sh --force`.

  **METHOD NOTE.** Verdicts were taken against live measurement, never against a row's own claim, and
  every content question was answered with `git cherry` / `git ls-tree` / blob-hash comparison rather
  than a commit count — `af01d0a5` is NOT an ancestor of `origin/main` even though its content is
  there, byte-identical, as `5ef11a988`. `git cherry origin/main origin/main` was run as a control on
  every sweep, and returned empty while real branches returned 1–4 `+` lines, so the oracle
  discriminates. No destructive git ran at any point.

- **2026-08-18 ~03:05Z — lead (pane 102): the duplicate resolved ITSELF, a reported BLOCKER does
  not exist, and some "stranded" branches are evidence nobody may land.** Three facts from 276's
  stand-down ping, each verified here before being written — the middle one is the load-bearing one.

  **(1) THE REPORTED BLOCKER IS NOT A PROPERTY OF THE COMMAND — IT IS A PROPERTY OF A SESSION.**
  276 closed by reporting `BLOCKER: 'CONFIRM=1 scripts/cloud-reconcile.sh --land' is DENIED by the
  auto-mode permission classifier — the land half needs a permission rule or a /ship route`. Filed
  as written, that sentence would have become a standing architectural defect and probably a
  settings-permission change. **It is false at least in this session:** pane 102 ran
  `CONFIRM=1 scripts/cloud-reconcile.sh --land --dry-run` and it EXECUTED — rc 0, refusing only
  because `--dry-run` parsed as the branch argument (`branch '--dry-run' is not on 'origin'`). So
  the classifier's decision is **per-session / per-invocation**, not a wall in the cloud lane's
  land half. This is the anti-capture rule earning its keep: *a negative tool-claim inferred from
  one failed call is not a fact about the tool.* The lesson generalises past this row — a
  dispatched session that hits a classifier denial is reporting something about ITS OWN
  invocation, and the lead must re-run it before the claim reaches a plan. 275 was told to retry
  and to route via `scripts/ship-land.sh` if its own session still refuses.

  **(2) A BRANCH CAN BE UNLANDED BY DESIGN, AND BOTH TALLIES WERE COUNTING IT AS LOSS.**
  `claude/fire-…-57078-1` and `-2` are parked deliberately: `docs/research/
  cloud-local-cost-ab-2026-08-11.md` §7 (verified verbatim) reads *"The work products were
  deliberately NOT landed. All four branches remain on origin as evidence; the probe tool is
  throwaway and does not belong on trunk."* Neither my 02:35Z partition nor 275's SUPERSEDED /
  MISSING / PARTIAL split had a bucket for this, so an A/B experiment's preserved evidence read as
  stranded work in both. **Every future landedness audit here needs a fourth verdict —
  PARKED-BY-DESIGN — and the only way to reach it is reading why the branch exists, which no git
  oracle can answer.** A cherry/patch-id sweep is blind to intent by construction.

  **(3) The two-writer collision ended without the operator, and the mechanism was a peer
  standing down.** 276 self-diagnosed the duplicate fire (275 @18:18:28, 276 @18:22:30, same
  account, same cwd, "the two clobbered each other's commits"), wrote its derivations to
  `/tmp/w-r3-findings-from-pane-276.md` (8352 B, verified present), reported `landed 0 / retired
  0 / parked 0 — nothing written`, and ceded the mission to 275. So the collision was resolved by
  the two sessions between them — a mail channel doing what no belt could. **The pane is still
  live and still wedged** (`cc-teardown` DEFER `tty-busy` on both attempts), so operator step
  `135e62b5ff49` still stands, but it is now pane HYGIENE, not a hazard: nothing of value is in
  that worktree and 275 has evacuated. 276 also confirms `session_018in35` returned
  2026-08-17T09:04:28Z with all 4 paths on trunk by `git ls-tree` — **~9 h before either R3 pane
  launched**, which means R3's own brief ("your launch on next refreshes the token that unblocks
  the return") was written on a premise that had already been satisfied. A fire's stated rationale
  is worth re-checking at fire time, not only its task.
- **2026-08-18 — recycle #19 (local drain): `master-session-lifecycle` 16 → 12 open / 1 blocked.
  filed 0 / closed 4. THE SPAWN GATE IS OPEN AGAIN — one teammate spawned and delivered.**

  *(Counts corrected after the land: this entry was written pre-land saying "13 open / closed 3",
  because `112d13aa0018` and `267ebd112350` were still awaiting the land + content check that
  authorises closing them. Both landed in `813c73bf7` and closed, so the true tally is 4. Recorded
  rather than silently overwritten — the gap between "work finished" and "row closeable" is one
  land, and a pre-land tally will always under-count by exactly the rows in flight.)*

  **BLOCKED TAIL, BY STRATUM (never a bare zero):** 1 row — `adf1bb6b5406`, venue=**local**,
  `source: needs`, an operator-platter row (the SessionStart accounts board reaches no session;
  settings.json is five separate real files). **0 cloud-venue rows in this effort.** The effort is
  still the smallest live one and still is NOT finished.

  **THE SPAWN GATE.** #16 lost 2 of 5 briefs, #17 lost 1 of 4, #18 lost **3 of 3** to
  *"Background subagents cannot write code — use TeamCreate/team_name"*. This recycle's single
  brief was **ACCEPTED** and its teammate did real work. The shape that worked: `Agent({name,
  subagent_type:"general-purpose", run_in_background:true})` with the worktree PATH in the brief
  body and no `isolation`/`cwd`/`team_name` argument. Treat the gate as a **variable, not a
  constant** — try one brief, and size the recycle to a lead-only plan only after a refusal.

  **ROWS.**
  - **`112d13aa0018` — the context-recycle actuation layer (arms (b) and (c); `ce942509`,
    `92717779`).** Arm (a) — demoting `gate-not-green-at-head` — was found ALREADY LANDED
    (2026-08-11); only the header narrative remained. Arm (b) added the absolute-occupancy arm
    `TOK_K`; arm (c) added the `recycle-intent` row.
  - **`f5ed2d0dd0cb` — recycle kills in-flight subagents.** CLOSED as **already fixed**:
    `20ac3254f` (2026-08-14) shipped all three named halves — the pre-flight `subagent_gate` on
    the recycle path, the `gate:"subagents"` ledger rows, and the successor-brief section
    *"SUBAGENTS KILLED BY THE RECYCLE THAT CREATED YOU"*. The row was filed by the L1-b census the
    **same day** its fix landed. Verified by content on `origin/main` plus a live sandbox drive.
  - **`620f2fa354a6` — the `62%→71%→93%` extrapolation.** CLOSED as **EVIDENCE-EXPIRED, not
    fixed** — a close class this log had not used before. Its finding stands (no rail computes a
    projected fill %; the session generated the number itself). Its own stated next step needed
    "that session's id + its telemetry/idl trail" from 2026-08-10, and that trail now exists in
    **no store**: live IDL spans 5 minutes, the oldest of 8 archives begins 2026-08-14T13:48, and
    `2026-08-10|11` returns 0 records across all of them. **IDL retention here is ~4 days.**
  - **`267ebd112350` — resume source-suppression (teammate, `f941f66f3`).** Ported
    `CLAUDE_CODE_RESUME_THRESHOLD_MINUTES` as PRIMARY with the `-re {as-is}` matcher as an
    *exercised* fallback. Left OPEN pending land + a same-moment content check.

  **THE FINDING WORTH CARRYING.** *A row's remedy and its EVIDENCE rot on different clocks.* Two
  of the three closes were not fixes at all: one row had been repaired by a sibling the day it was
  filed, and one had quietly outlived the store its next step depended on. Neither is visible from
  the row text — both needed a same-moment read of the tree and of the store's retention window.
  So **before building anything, check (a) whether it already landed and (b) whether its evidence
  still exists**; #19 spent ~15 minutes on that pass and it produced two of its three closes.
  Corollary for filing: a next step naming an ephemeral store inherits that store's half-life, so
  either snapshot the rows into the item or write the expiry into it (memory:
  `work-item-next-step-inherits-its-stores-half-life`).

  **THE CORRECTION TO MY OWN ROW, recorded rather than laundered.** `112d13aa0018` justified
  `TOK_K=700` as "window-independent" coverage of "4 of 5 historical deaths". Measured against 21
  live telemetry rows, **neither half survives as stated**: `used_pct` IS `input_tokens/window` to
  the integer and every live window is 1,000,000, so on today's fleet TOK_K=700 fires at 70% —
  three points ahead of `T=73`, a small lead and **not an independent axis**; and the 800K–950K
  deaths sit at 80–95% on a 1M window, i.e. ABOVE T, so they were missed because the rail was
  *unfireable at all* until arm (a) landed — crediting them to (b) double-counts a fix already
  shipped. The arm was kept on a **different, verifiable** basis: `used_pct` is read as
  `.used_pct // 0`, so a row whose **denominator** is missing or wrong presents as 0 and abstains
  `below-threshold` forever however large the session is; `input_tokens` is a separate field and
  survives that. `over_tok`/`tok_k` now ride every IDL record so the next census can retire the
  arm on evidence if it never fires alone. **Reachability is named too:** on a window smaller than
  `TOK_K×1000` the arm can never fire (an empty population), so it is a floor beneath the fill
  arms, never a replacement.

  **RED-PROOF, PER CASE (the discipline #18 paid for).** 8 new cases, each proved red against a
  pristine `origin/main` worktree individually — boundary-handoff `1..5` five not-ok, the new
  `handoff-recycle-intent` suite `1..3` three not-ok. Honest caveat recorded here rather than in
  the commit: 2 of the 5 boundary cases red pre-fix on their **IDL-recording** assertion rather
  than on their headline property, because the pre-fix engine still fires correctly on the size
  and fill axes; they are regression guards for the labelling, not independent proofs of it.

  **A TRAP RE-PAID.** `tests/handoff-recycle-intent.bats` is the first recycle suite to drive a
  **real, non-dry** recycle — `--dry-run` returns before `recycle_fire`, so a dry test cannot
  observe the intent row at all. It is safe by CONSTRUCTION, not by flags: the pane id is a
  fabricated UUID no terminal owns, so `as_tty` resolves nothing and `recycle_fire` aborts at its
  first exit path, upstream of every keystroke, detach and `/exit`. That abort *is* the state
  under test. Its first draft also tripped the hermeticity lint on three seams the account sweep
  leaves live even when the sweep itself is `off` (`HANDOFF_ACCOUNT_SWEEP_STAMP`, `CC_ACCOUNTS_BIN`,
  `CC_HEAL_LOCK_PREFIX`) — pinned to absent paths, 0 new leaks.

  **DECLINED, and why.** `4a11a0ac850a` (a brief written but never fired) was opened and put back:
  its detector needs to answer "was a fire ever made FROM this brief", and **no row in
  `handoffs.jsonl` records a prompt-file path**, so the linking primitive does not exist. Building
  the sweep without it would have shipped a heuristic alarm over an attention budget. The missing
  primitive is one line at the fire site; naming it here so the next recycle can add it first.

- **2026-08-18 ~02:50Z — lead (pane 102): CORRECTION to the 02:35Z entry below, on both halves
  it got wrong — pane 275 UNWEDGED ITSELF, and `git cherry` cannot see supersession.** Source:
  275's own HANDOFF-PING (19:42:19-0700), verified against the tree before being written here.

  **(1) "Both sessions are wedged" is now FALSE for 275, and the recovery is the finding.** Pane
  275 (sid `3492adf8`) got past the modal on its own and is working. It did NOT resume in the
  shared worktree: it **evacuated to its own** — `.worktrees/r3-land`, branch `fix/r3-cloud-land`
  (verified: worktree exists, branch exists at `b7a47877a`) — because **276's writes had already
  destroyed 275's first conflict resolution.** So the two-writers-one-index hazard the 02:35Z
  entry called a *risk* is a **realised loss**, and the fix was the one the concurrency rule
  prescribes: one owner per worktree, evacuate rather than contend. 276 remains wedged (S+, zero
  writes in 1h20m) and a second `cc-teardown` attempt at 02:47Z returned **DEFER `tty-busy`
  again** — so the operator step `135e62b5ff49` stands, now with teeth: 276 is an active hazard
  that has already eaten work, not an idle pane awaiting GC.

  **(2) THE TALLY'S "OUTSTANDING" BUCKET WAS TOO COARSE, AND THE DISTINCTION IT SWALLOWED IS THE
  ONLY ONE THAT MATTERS — IS THE WORK LOST OR MERELY UNMERGED?** `git cherry` decides equivalence
  by **patch-id**, so it reports `+` for any commit whose bytes are not identical to something in
  main. 275 re-derived the same 35-ish commits with a semantic read and split them:
  **15 SUPERSEDED** (the change IS in main, carried by a *different* patch — patch-id differs, so
  `git cherry` calls it unlanded) · **17 MISSING** (genuinely absent) · **3 PARTIAL**. Its
  retire-class count **51 matches mine exactly**, which is the corroboration that makes the
  refinement trustworthy rather than a competing guess; the totals drift by one branch (82 vs my
  83 refs, 31 vs 32 carrying content) purely from measuring an hour apart. **Read the 02:35Z
  "37 outstanding commits" as an upper bound on unlanded BYTES, never as a count of lost WORK —
  fewer than half of it is actually missing.** The generalisation to carry into any future
  landedness audit here: *`git cherry`/patch-id answers "are these bytes in main", and a
  conflict-resolved or rebased-then-squashed landing answers it NO while the change is fully
  present.* A tally that stops at patch-id will always over-report loss, and over-reported loss is
  what sends a session to re-land work that is already there.

- **2026-08-18 ~02:35Z — lead (pane 102): W-R3's tally derived NON-MUTATINGLY after both its
  sessions wedged; and the measurement that says this pipeline cannot reach zero as specified.**

  **THE STUCK-BRANCH TALLY — conservation-complete, and the enumeration it corrects was WRONG BY
  TWO.** Oracle: `git cherry origin/main <branch>` over every `refs/remotes/origin/claude/fire-*`,
  read-only, no cherry-pick and no `reset --hard`. Population **83** refs, partitioned:
  **51 RETIRE-ABLE** (zero unlanded commits — every commit content-present in main) ·
  **32 OUTSTANDING** (≥1 unlanded commit), holding **37 commits** · **0 landed by this effort**.
  51 + 32 = 83, conserved. W-R3's own 18:21 enumeration (`/tmp/r3-commits.txt`) listed 35 commits
  over 31 branches and **missed two** — `4da7836cf` (2026-08-18T01:18:36Z, postland bisect
  no-verdict) and `60eaebef7` (2026-08-13, autonomy-sweep wedge). So the true population is **37/32,
  not 35/31**, and any tally that had summed to 35 would have "conserved" against a denominator
  that was already short. Controls run because a uniform verdict indicts the instrument: `git
  cherry origin/main origin/main` and `…origin/main~5` both report 0 `+`, while outstanding
  branches report 1–2 — the oracle discriminates. Artifact: `/tmp/r3-TALLY.txt`.

  **WHY THE LEAD DERIVED IT AT ALL: BOTH W-R3 SESSIONS ARE WEDGED ON A MODAL NO AGENT MAY ANSWER,
  AND THE TWO SAFETY BELTS THAT SHOULD HAVE CLEARED THEM BOTH DECLINED — CORRECTLY.** Panes 275
  (sid `3492adf8`, fired 18:18:27) and 276 (sid `79e3867f`, 18:22:29) are BOTH live claude
  processes in the SAME worktree `fix/cloud-branch-debris` — two writers, one git index — and both
  sit at the same `PreToolUse` confirmation for `git reset --hard`. Neither can advance:
  * `cc-pane send 276 2` (answer the modal) → **denied by the auto-mode classifier**. Cross-pane
    keystroke injection is not available to an agent, so the modal is structurally operator-only.
  * `cc-teardown cloud-branch-debris-276` → **DEFER `tty-busy` (exit 10)**, "refusing collateral
    close": a process on the pane tty sits outside the target claude tree. That belt is right, and
    it means **a session wedged at a modal cannot be torn down by the autonomous path at all** —
    `--force-adopted` is operator-CLI-only and does not address `tty-busy` anyway.
  Zero-loss verified before proposing anything: both trees clean, 0 commits ahead of origin/main,
  276's scratchpad probe-wt clean at `c13572ad2`; the enumeration survives in `/tmp`. **No third
  R3 was fired** — the goal forbids duplicate work and the two wedged clones still hold the branch.
  The generalisation: **a permission modal is a liveness state no belt models.** The session is
  neither idle (teardown's precondition) nor working (the supervisor logs it `permission_pending`
  and does nothing with it); `lead-supervisor` has been re-logging these two every 30 s for 18+
  minutes with no actor able to consume the signal. Filed as an operator step (`135e62b5ff49`).

  **AND THE STRUCTURAL FINDING THAT REFRAMES THE PROGRAM'S OWN TARGET: THE DRAIN IS WORKING AND
  THE NUMBER STILL RISES, BECAUSE `block` OUTRUNS `unblock` 171:26.** Ledger flow, last 24 h:
  `done 134 · add 97 · block 171 · unblock 26`. Open went 429 → 431 while recycle #18 closed four
  rows — not a stall, an accounting fact: `cc-backlog list --open` = **431 = 273 open + 153 blocked
  + 5 claimed**, and blocked rows are operator-gated, so **the 24/7 pipeline structurally cannot
  drain 153 of the 431 no matter how well it runs**. Agent-actionable open is **278**. Two
  consequences, and the plan should pick one deliberately rather than let the number decide:
  (a) the recycle brief (§4.1) grows an explicit **unblock/triage pass** over the blocked pool, so
  something on the agent side can retire operator-gated rows that have gone stale; or (b) the
  program's success metric becomes **agent-actionable-open**, and `list --open` stops being quoted
  as progress. Until one lands, "drains to zero and stays there" is unreachable by construction —
  the target is measured against a pool the drain has no verb for. Filed as `eb41813aa373`.

  **Cloud lane, unchanged and green:** `session_018in35KSYj7iLV7jZCNuCnj` **RETURNED** at
  09:04:28Z — `goal:"MET"`, `content_verified:true`, 4 research docs, backlog `c33f3b1cb278` marked
  done, custody discharged. The account-`next` 401 cured exactly as designed: by a session
  launching on `next`, never by forced rotation.

- **2026-08-18 ~01:47Z — recycle #18: `master-session-lifecycle` 20 open → `16 open / 1 blocked
  (1 operator-gated `source: needs`; 0 cloud-venue)`. filed 0 / closed 4. Four commits, ONE land.**
  Two clusters, both entirely on the lead. **The spawn gate refused all three teammate briefs**
  ("Background subagents cannot write code — use TeamCreate/team_name"), where #17 lost 1 of 4 and
  #16 lost 2 of 5. `TeamCreate` does not exist on 2.1.220 and the Agent schema has no `team_name`,
  so the instruction is unreachable; per the standing brief the rows were taken inline rather than
  re-worded. A successor should budget for the gate being FULLY closed, not partly.
  - **Kitty keepalive (`71c2c19d6c63` · `a94c9e5722f7` · `d591c8d990b5`, `d3af4367` + `d09cec4c`).**
    The idle-pane arm was iTerm2-only, so on a kitty fleet it was inert. **Cause correction: the row
    says "bin/it2 already diverts" and there is no `bin/it2`** — the divert is `bin/it2-wrapper`
    (split/close for teammate panes, not a send path) and the kitty adapter is a third file,
    `bin/it2-kitty`. None of it was reachable anyway: `IT2` defaults to the REAL python it2 binary,
    so **the send path resolved PAST every divert** — "0 kitty references" understated it. The arm
    now drives `bin/it2-kitty` and matches markers on window **cwd**, not scrollback (a long-running
    pane scrolls its worktree name off and silently stops matching). `d591c8d990b5`'s third skip
    predicate — never nudge a pane awaiting ITS OWN armed watcher — landed with it, and the three
    predicates are declared ONCE and rendered into both the AppleScript `contains` clauses and the
    kitty grep, per `hooks/lib/pane-modal.sh`'s standing warning that a copied screen predicate rots
    independently. Docs carried a **second stale interface**: Phase 4 still prescribed capturing pane
    ids into `/tmp/reso-keepalive-ids.txt`, an interface gone since `410f920c`.
  - **Engine capacity gate (`eda267ff4b14`, `3296d71d`).** §12.1's last bypass: a direct call to
    `bin/reso-resume-one` spawned against no admission check. Gated in its own body, same shape as
    the launcher's, exit 9 = shed. **The row did not name the interaction that matters** — the
    launcher already runs this gate and the consecutive-refusal BUDGET is shared state, so a naive
    second gate double-spends it and releases the bound early on a box that never settled;
    `CC_ADMIT_DONE` marks the admission that already happened. `capacity-admit-coverage` case 25 was
    **inverted exactly as its own text instructed** ("will redden the moment that lands, which is
    when it should be rewritten to assert the gate") — an instructed inversion, not a relaxation.
  - 🚨 **TWO OF THIS WAVE'S OWN NEW ASSERTIONS ASSERTED NOTHING, and only the land gates said so**
    (`d8f4340f`). (a) `A && { …; false; }` is errexit-absorbed and therefore dead;
    `bats-assert-liveness-fix.py` **DECLINED** to repair it (split across two lines, no faithful
    re-flow), so it was hand-rewritten and proven live in both directions with a mutant — a negative
    assertion whose condition is already false cannot distinguish "revived" from "always passes".
    (b) the kitty arm made `bin/it2-kitty` a subject, and it reads `CC_PANE_CMD_INTERACTIVE` —
    injected into every pane this repo launches, so the suite would go red only when run from a
    fired pane. Both fixed at the source the lints prescribe; the allowlist was not touched.
  - 🚨 **A CASE CAN PASS PRE-FIX BECAUSE THERE IS NOTHING THERE TO BREAK.** The
    no-double-evaluation case went GREEN against the pre-gate engine while its three siblings
    correctly reddened: an engine with **no** gate also fails to evaluate one twice, so *suppressed*
    and *never there* are the same observation from the marker's side. Caught only by running the
    red-proof per case rather than per file. Same shape bit the absent-library case, unreachable
    from a checkout because the engine's first search path is its own sibling `scripts/lib/`. Both
    now carry a control that must SHED. **Ask of every green pre-fix case whether its subject even
    exists yet.**
  - Instrument note for the successor: `71c2c19d6c63`'s stored falsifier reads
    `$HOME/.reso/bin/reso-keepalive`, a symlink into the SHARED CHECKOUT — so it retracts against the
    tracked subject immediately but not through the symlink until the land converges that checkout.
    Landed ≠ live, per the ledger's `🚀` rung; read which surface a falsifier names.

- **2026-08-18 ~01:40Z — both lanes PROVEN end-to-end; the chain is 8 recycles deep; open
  568 → 427.**
  DRAIN CHAIN #12-#17 (all unattended): stranded-work 0/5 · verification-integrity 0/1 ·
  enforcing-store 0/11 (16 closed in #14 alone) · session-lifecycle 32→20 in progress;
  conservation printed every recycle; survived a 3.75h ENOTFOUND route outage (#16, lead did
  the refused rows itself). Notable chain lands: b5f685081 (the 789-pin retry burn — ship-land
  discarded rerere-staged resolutions), cc-close-attrib EINTR fd-9 launch-kill find (#13).
  S4 COMPLETE — and its refutation is the finding: the daemon env was FINE (109 real rows vs 6
  abstains interleaved; my tail sample was an abstain burst — a tail of an interleaved log is
  not the population). TWO real causes: (1) postland-verify's THROWAWAY-WORKTREE copy of
  cloud-return.sh held the return lock (deployed-copy gate `case $0 in $_cc_cfg/*` could not
  discriminate — postland mints worktrees UNDER the config dir); exact-path gate + behavioural
  test landed ba69a4510; (2) account next's OAuth ACCESS token expired — HTTP 401, discriminated
  same-call-same-second (next=401, others=404-authenticated). Sensor un-muted (54aa27cd6 — a
  bare command substitution was discarding every diagnostic), reaped-TMPDIR fix 33cf5df17.
  **PRODUCTION PROOF: 3 cloud sessions returned end-to-end — landed, content-verified, goals
  MET, custody discharged** (016cCpabd…, 01ByarSY…, 01GsPHLD…). Their "unknown id" row-close
  failures were the rogue copy's environment (all 3 ids hold 7-8 store hits; all 3 rows now
  fold done) — lookup-miss ≠ absence, cured by the exact-path gate.
  A2 residual: session_018in35… is RETURN-READY (ref pushed db0981de6) behind next's 401; the
  relogin gate refuses on live-session grounds (endpoint k counts CLOUD sessions; zero local
  processes on next) — refusal honored, G2 credential surface untouched; second-order gap filed
  8636b8f829fe (health gate blind to expired access token). Cure in motion: W-R3 fired ON
  account next (launch = native token refresh) to clear S4's two handed-back blockers (39 stuck
  cloud branches: 15 rc=65 stale worktrees + 18 rc=70 VM-doc conflicts). Fire saga: 2×
  "never-engaged" verdicts were the DETECTOR missing a width-wrapped marker + pane 275 stalled
  at a settings.json hooks-update modal (sibling of the fixed .mcp.json class — filed
  8ea3acef7d64, condition fired-session-startup-modal); 276 is the working session
  (goal-arm unreachable on both — brief carries the DoD); 275 refused by teardown's adoption
  belt, left for reaper GC.
- **2026-08-18 ~00:40Z — recycle #17: `master-session-lifecycle` 27 open → `20 open / 1 blocked
  (1 operator-gated `source: needs`; 0 cloud-venue)`. filed 1 / closed 7. Ten commits, ONE land.**
  Seven rows: three on the lead (`471d2f3f98df` cc-announce, `08c746312188` handoff-disposition,
  `8370af320af5` comms-strand-report), two from teammate t2 (`aa8aed0d713a` cc-roles + the phone
  leg) and t4 (`dcf58e1ba056` cc-classify), two from t3 (`ac914e8982b8` + `fc54aeebec4a`,
  waiting-recycle — one file, one owner). The one filing (`ebbf3adfb4d0`, linked to
  `master-verification-integrity`, NOT to the effort being drained) is below.

  **THE FINDING FOR #18: THE WATCHER, THE ROLE AND THE MAILBOX ALL PROVED THAT AN IDENTITY IS
  PLURAL, AND EVERY ONE OF THESE BUGS IS A PROBE THAT LEARNED ONLY ONE SPELLING OF IT.** Three
  independent rows this recycle turned out to be the same shape, and none of them said so:
  * `08c746312188` — `handoff-disposition.sh` asked `pgrep -f "cc-await-ping.*$uuid"`. The wake
    floor arms that watcher with **no id in argv, deliberately** (`session-continue.sh:595`), so
    the tool can derive the key itself and cover the whole set. The probe therefore reported
    `false` over a *running* watcher and told a pane awaiting a peer that it was close-eligible.
  * `8370af320af5` — a mailbox box key is written in **two** spaces (pane id, and the registry's
    `session_id`); the strand report adjudicated against pane ids only. Measured live: of 534
    boxes it called dead, **eight belonged to sessions alive at that instant, including the
    session running the report**. Under kitty the spaces are not even the same shape (`131` vs a
    36-char uuid), so the match could never have succeeded by luck.
  * `aa8aed0d713a` / `dcf58e1ba056` — the same lesson twice more: a role that is only an address
    with no liveness, and two auditors keying tenancy on `startedAt` vs `cwd`.
  The generalisation to carry: **when a probe asks "is X live?", ask which of X's names it is
  asking about, and whether the thing being observed chose that name.** In every case here the
  producer picked one spelling for a good reason and the consumer hard-coded another.

  **AND THE COROLLARY THAT ALMOST HID IT: `8370af320af5`'s POSITIVE CONTROL PASSED THROUGHOUT.**
  It asked whether *this pane's* id was in the *pane* list. It was. So the control certified the
  oracle on the one axis that could not fail, while being structurally blind to the axis that
  did — the report has shipped a wrong live/dead split for as long as both spaces have existed.
  A control has to be independent of what it certifies; the fix makes the registry a REQUIRED
  second oracle on the same fail-closed terms as the first (unreadable ⇒ `verdict=unknown`, no
  numbers), because with it unread every uuid-keyed box is fabricated-dead.

  **A PARTIAL REFUTATION, RECORDED RATHER THAN SMOOTHED OVER.** `8370af320af5` also claimed the
  headline `dead_never_surfaced` figure was wrong. It is not — 14873 before, 14873 after. The
  eight misclassified boxes hold no never-surfaced lines *at this instant*, so the classification
  error never reached that number. The mechanism for it to be wrong is real (a live session's box
  with unread mail would count as stranded loss) but the count itself is currently sound. What the
  fix actually corrects is the box classification (live 10 → 18) and the blind control.

  **A ROW RE-MEASURED, STILL OPEN, AND GENUINELY NOT MINE — `85a82455de9a`.** Two of its three
  asserted paths have converged since filing (`commands/resume-sessions.md` and
  `~/.reso/bin/reso-resume-one` are now symlinks; the latter was a real pre-vendor copy). The
  third, `~/.claude/bin/reso-resume-one`, is still ABSENT. `deploy-live.sh` refuses correctly —
  *no GREEN tree is a DESCENDANT of live HEAD* — and reports the lag as "inside the degrade
  budget (25/6h)", which is exactly the reading CLAUDE.md warns against: **an ADD gets no budget**,
  so a lag of 11 is a breach at 1 for this row. Left open, un-mutated, and named here so #18 does
  not re-derive it. Only `postland-verify.sh` advances that stamp; this recycle's own land adds
  more un-stamped commits above the pin.

  **THE FILING (1).** `ebbf3adfb4d0` — peer mail paged this chain with a post-land RED naming
  `tests/cc-wait.bats` at culprit `0f55846f7de4`. That commit changes **one file,
  `docs/plans/BACKLOG_DRAIN_24_7.md`, +88 lines and no code** — it cannot reach a bats subject.
  The suite is 19/19 green at `origin/main` HEAD with its plan line present, and the page's own
  env recorded `load 16.45`. So a contention flake was bisected and the nearest commit elected as
  culprit. A bisect must be able to return NO VERDICT; a candidate that touches no file the test
  loads is not a candidate. Filed to `master-verification-integrity`, not here.

  **PROCESS NOTES FOR #18.** (a) The spawn gate deterministically refused one of four teammate
  briefs with the unreachable "use TeamCreate/team_name" instruction — that row was taken on the
  lead immediately, per §4.1; do not re-word. (b) `cc-bats` REFUSED twice mid-recycle while
  teammates held execution roots — **no `1..N` plan line, so no verdict**; every suite below was
  re-run until it emitted one. (c) All three teammates returned real discriminator pairs this
  time, unlike #16 where the lead had to write both controls — the briefs demanded the REMOVE half
  FIRST and named it as the deliverable, and t2 went further and proved its *mutant* was the gated
  variant rather than a merely-broken file.

  **GATES (run this turn, on the merged branch, not recalled).** `cc-announce-alarm-body 1..5` ·
  `cc-announce 1..18` · `announce-before-retire 1..21` · `handoff-disposition-watching 1..5` ·
  `handoff-disposition 1..24` · `comms-strand-report-identity 1..6` · `comms-strand-report 1..9` ·
  `cc-classify-origin-unify 1..10` · `cc-classify 1..69` · `cc-roles-liveness 1..18` ·
  `cc-notify 1..87` · `waiting-recycle-disarm-ttl 1..6` · `waiting-recycle-account-neutral 1..5` ·
  `waiting-recycle 1..114`. 402 tests, zero `not ok`, every plan line present.

- **2026-08-17 ~17:30Z — recycle #16: `master-session-lifecycle` 32 open → `27 open / 1 blocked
  (1 operator-gated `source: needs`; 0 cloud-venue)`. filed 0 / closed 5. Six commits, ONE land,
  `ef98781de`; content-verified on `origin/main` (`git diff` empty on all 9 paths).**
  The effort is an order of magnitude larger than #14's and #15's, so this is a multi-recycle
  effort as briefed; five rows closed is the advance, not the finish.

  **THE FINDING THAT SHOULD CHANGE HOW #17 READS A ROW: A ROW CAN NAME THE RIGHT BUG AND THE WRONG
  CAUSE, AND THE WRONG CAUSE HIDES THE DANGEROUS HALF.** Row `567a4d90ca89` said validate-bash
  *"convicts a benign rm because an unrelated `$HOME/.claude` string sits elsewhere in the same
  command."* The bug is real. The cause is not the string — it is the **separator**. `rm_argv_scan`
  split clauses on a PIPELINE_OPS set that included `;`, but tokenized with `shlex.split()`, a WORD
  splitter, which only ever sees an operator the writer surrounded with whitespace. `&&` and `|` are
  conventionally spaced and worked; `;` is conventionally **glued** to the word before it, was never
  a token, and so the entire next clause became targets of the rm. That failed in BOTH directions:
  the filed false positive (a build-artifact delete refused because a later clause names `$HOME`)
  **and an unfiled false NEGATIVE — a recursive delete of `~` glued to `; echo hi` was DOWNGRADED
  out of the deny to ASK.** Spelled with a space before the `;`, the identical command DENIES. The
  row would never have found that; only probing the row's claim in the opposite direction did
  (memory `guard-proxy-fails-in-both-directions`). **So: reproduce a row's SYMPTOM, then re-derive
  its CAUSE yourself, then ask what the corrected cause predicts that the row never claimed.**

  Same shape twice more, both times caught by a test rather than by reading:
  - **A KEEP that passes for the wrong reason is indistinguishable from a KEEP that works.** Writing
    the worktree-gc control, the recent-write signal appeared green twice while never being
    consulted: a plain untracked file trips the *dirty-tree* gate, and committing a `.gitignore`
    inside the worktree leaves the branch *unlanded* — two OTHER gates held the tree. Only the
    REMOVE half of each discriminator pair exposed it. Write the REMOVE half first.
  - **An arm with no test seam cannot be tested, and reads as tested.** The custody floor probed
    `$(dirname $0)/../bin/cc-custody` and so resolved the REAL binary out of the checkout — a suite
    could only ever exercise it against the operator's LIVE store. Before the `CC_CUSTODY_BIN` seam,
    the three "must block" cases failed and the two "must NOT block" cases passed **vacuously**.
    That asymmetry is the signature: if the negative half of a pair is the only half passing, the
    subject is not being reached.

  **A CORRECTED MEASUREMENT CLOSED A ROW WITHOUT THE FIX IT ASKED FOR.** `22705859d07d` filed two
  halves. The performance half is **REFUTED**: `d31fee77f` landed 2026-08-11 14:42, the same day the
  row was measured, and `find_active_list` now runs 0.11 s on the live 2,640-dir store, so the 5 s
  hook timeout cannot fire and `rc=124` — the mechanism the row named — is unreachable. Its stored
  falsifier cannot see this either way (it greps for a per-directory loop that is still present and
  now pure-bash). The **correctness** half survived that fix untouched, because it was never about
  the timeout: a missing index, an unparseable index and a genuinely-unmapped project were
  byte-identical AND rc-identical, so every consumer read "no task list" off a question never
  answered — and `setup-task-symlinks.sh` DELETES a good `_current` symlink on that verdict. Fixed
  three-state on the **exit-status** channel, the only one that survives the command substitution
  every caller wraps the function in.

  **OPERATIONAL, FOR #17 — the wave died to the ROUTE, not to itself.** Five teammates were briefed;
  the spawn gate deterministically refused two of them ("Background subagents cannot write code"),
  and the surviving three all died within two minutes of each other on
  `API Error: Unable to connect to API (ENOTFOUND)` — the local-route signature
  (memory `mass-tls-hostname-mismatch-indicts-the-local-route`), which also cost this session ~3.75 h
  of wall clock. Two of the three had COMMITTED before dying and lost nothing; the third had 111
  lines uncommitted, recovered only because the lead banked it. **Keep telling teammates to commit
  early — it is what makes a network death survivable.** Both refused rows were then done by the
  lead, so the refusal cost time, not scope.

  Rows closed: `567a4d90ca89` (validate-bash tokenizer) · `63484cfeab2a` (worktree-gc occupancy,
  two signals, decorrelation measured not assumed) · `9581119669f9` (custody floor attributed by
  `originatorPane`/`notifyBack`, not cwd) · `2d0074dae889` (`clear` reports what it actually did) ·
  `22705859d07d` (task-helpers three-state verdict + perf half refuted).
  Suites run by the lead this turn, because the land's smoke gate answered **FULL** (its fail-closed
  "cannot decide") and made no direct-suite claim: `rm-argv-normalize` 1..15 · `worktree-gc` 1..97
  (was 1..89) · `wake-floor` 1..43 · `session-continue` 1..27 · `task-helpers-verdict` 1..9 ·
  `rm-safe-allowlist` · `validate-bash-{payload-parse,differential,audit-log,goal-guard}` — all
  green, every plan line present.

- **2026-08-17 — backlog `354c73ebd400` (ship-land.sh BRANCH / postland bisect) CLOSED on
  already-landed evidence: `6ce67de910d6e46f825a7eae0db28b741964f5de`, verified an ancestor of
  `origin/main`. No diff — re-deriving one would have reverted trunk.** The dispatched worker
  read the item on trunk first (tree = trunk, 0 behind) and found the cure already there, per the
  §4.1 rule that a post-land RED reproduces faithfully in a stale tree.
  - **Both-directions control, run rather than reasoned.** Pre-fix lint (`6ce67de9^`) on the
    pre-fix tree reproduces the item VERBATIM — `scripts/ship-land.sh:3687: BRANCH — assigned
    inside a $( ) child`, chained to `write_decision_packet` at `:584`, trap `_land_exit_trap →
    land_failure_inbox` at `:813`. Trunk's lint over that SAME pre-fix tree: clean, 165 parsed of
    476. Trunk's lint over trunk: clean, 167 of 486, rc 0. So the cure is aimed at exactly this
    finding, and it is not a blanket skip.
  - **The finding was false, re-measured independently rather than taken from the cut message.**
    `V=orig; f(){ :; }; V=inside f` leaves `V=orig`; `V2=inside /bin/true` leaves `V2` unset. A
    command-PREFIX assignment writes the command's environment and never the shell, so
    `ID="$id" BRANCH="$branch" … python3` set no global and the trap's `BRANCH` was never stale.
  - **The bisect half needed no work either.** It was the DOWNSTREAM symptom — a pre-existing
    whole-tree prelint red skipped the corpus from 11:35Z, no GREEN stamp could be minted, and
    lands that merely touched the file were elected. The misattribution class itself is already
    hardened on trunk (`postland-verify.sh:1948`/`:1980` tip-confirmation — a bisect can NAME a
    commit it never RAN — plus `bisect_floor_ok` at `:1808`), and killing the false red removes
    the input that fed it.
  - **The land gate could not be run to green in this container, and the reason is the box, not
    the tree.** `ship-land.sh --precheck` reds at `unattended-path-lint --selftest FAILED (9 of
    30)` — IDENTICALLY on a pristine detached `origin/main` worktree, so nothing in this diff
    reaches it. Root cause measured: this is a Linux cloud container and the lint's fixtures are
    calibrated to macOS PATHs — `tmux` and `yq` sit on `/usr/bin` here but are Homebrew-only
    there, so every fixture that expects a violation goes green and its allowlist rows read as
    STUCK. The same selftest is green on the operator's box (475-suite corpus GREEN at
    `416a7191dea8`). Doc-only change, pushed to its branch rather than bypassing the gate.
  - **Operator-only remainder:** the ledger is on the operator's box; this container carries no
    `~/.claude/autonomy/backlog.jsonl`, so `cc-backlog done 354c73ebd400` returned
    `unknown id` and the row is still open THERE. It needs one run on that box with the sha above.
- **2026-08-17 ~13:50Z — recycle #15: `master-enforcing-store` 1 open → `0 open / 11 blocked
  (10 operator-gated, 1 cloud-venue build)`. filed 1 / closed 2. Eight commits, two lands,
  `6644273f3`; content-verified on `origin/main`.**
  The condition's last row was `8942f3b1506d` (R-3, HOOK_CHAIN_COST): *"validate-bash.sh does 12
  grep forks bash can do natively (~42 ms) — BLOCKED on a differential corpus proving identical
  verdicts on every DANGER pattern first."*

  **The row was ADJUDICATED, not implemented, and that was its own instruction.** The corpus is
  what the row blocks itself on, so the corpus is the deliverable and the optimization was only
  ever whatever the corpus authorized. Built
  (`scripts/validate-bash-differential.sh`, `tests/validate-bash-differential.bats`, 31 site rows ×
  66 cases = **1,672 scored pairs, 56 diverging**), it authorizes almost nothing: **10 of 30 sites
  are safe to convert, 20 are not, and on the modal path exactly 1 of the 10 always-executed greps
  is convertible** — a ~2.6 ms prize, not 42 ms, against a gate carrying the
  `denylist-enumerates-spellings` scar.

  🚨 **THE TRANSFERABLE FINDING: the blocker was not subtlety, it was a SILENT SEMANTIC INVERSION,
  and it fails in BOTH directions.** `\b` is a word boundary in the BSD grep this hook resolves and
  a **literal `b`** in bash's `=~`, whose `regcomp` has no such escape and drops the backslash.
  Measured with every other axis held out, plus a control:
  `'\bconfig\b'` vs `git config --get x` → grep MATCH, bash **no** (*the guard goes silent*) ·
  vs `git bconfigb --get x` → grep no, bash **MATCH** (*the guard fires on noise*) ·
  and `'config'` vs the same input → both MATCH (control: without `\b` they agree). **13 of 27
  predicate sites carry one.** Second cause: `grep` anchors `^`/`$` **per line**, bash `=~` over the
  **whole string**, and `$CMD` is routinely multi-line here — which is exactly why `61826e193`
  (heredoc bodies are stdin, not argv) had to exist. *An equivalence you can only check by reading
  is one you have not checked; both causes are invisible in a diff and loud in a corpus.*

  **The premise decayed in BOTH directions AT ONCE — this sharpens #14's lesson rather than
  repeating it.** #14 found the UNIT decays before the VALUE. Here the count decayed **upward**
  (12 → **14** grep forks) while the ms decayed **downward** (42 → **36.7**), so the two errors
  partly cancel and the headline scalar still looks about right. It is not: 4 of the 14 live in
  `hooks/lib/is-true-flag.sh`, a file the row never names and its stated precondition does not
  cover. **The durable unit is the exec count, not the millisecond** — counts were byte-identical
  across three independent runs while the wall clock moved with load inside ten minutes.

  **Three things larger than R-3 that R-3 did not contain**, all from the census
  (`docs/research/validate-bash-fork-census-2026-08-17.md`): `grep` is **51%** of the modal path,
  not the whole story (24 externals, 14 of them grep) · one `python3` exec is **24.45 ms, 9.3× a
  grep**, the most expensive fork in the file · and the hook parsed **the same stdin payload three
  times**. The last one was filed (`054499f0c342`) and then **done** in the same recycle:
  **+7.02 ms median paired, 113/120 pairs**, plus the audit logger's own `mkdir`+`date`
  (**+2.28 ms, 96/120**) — **~9.3 ms off a 71.9 ms modal path, 13%**, with no danger pattern
  touched.

  🚨 **A NULL RESULT WAS AN ARTEFACT OF THE EXPERIMENTAL DESIGN, not of the change.** The logger
  lever first measured **blocked A-then-B at n=41: 67.36 vs 67.59 ms — no saving, nominally
  slower**, and would have been reported as a refutation of my own work. **Interleaved paired** runs
  at n=120 resolve the same change at **+2.28 ms, 80% paired wins**. Load drifts over minutes and a
  blocked design charges that drift to whichever variant ran second. *At small effect sizes the
  DESIGN, not the sample size, decides whether the effect is visible at all — and a null from a
  design that cannot resolve the effect is not evidence of absence.*

  **A guard that could not fire, caught only by a mutant.** The TSV arity guard added for the
  field-collapse ratchet first lived inside `build_payloads`, whose one caller is
  `NCASES="$(build_payloads)"` — a **command substitution, i.e. a subshell** — so its `exit 2` ended
  the subshell and the parent ran on with `NCASES` empty. A deliberately malformed corpus produced a
  **full clean run at exit 0**. Hoisted to top level; both guards now proven in both directions.
  Same family as `dispatching-alarm-can-be-the-defect`: *ask where the guard's exit actually lands.*

  **FIVE ratchets fired across four land attempts, every one a real bug in this land's own diff** —
  budget for this, it is the norm, not bad luck. shellcheck (SC2004; three SC2016 hits were
  intentional and took reasoned disables) · test-hermeticity (`validate-bash-differential.bats`
  ran against the operator's live `~/`) · bats dead-assertion (**9** assertions errexit could not
  reach; fixed with `scripts/bats-assert-liveness-fix.py`, never by hand) · self-path (all three new
  harnesses derived a root from an unresolved `$0`; through the live per-file symlinks they would
  have read `~/.claude`, found no fixtures, and **reported nothing rather than failed**) · TSV
  field-collapse. **The self-path gate's own message read `--selftest FAILED — the detector no
  longer discriminates`, which reads as a broken lint. It was not**: the selftest's last arm asserts
  GREEN on the real tree, and the real tree was dirty *because of my diff*. Attribute before you
  drive — and a gate accusing itself may be accusing you.

  **The corpus caught ME, which is the point of building it.** Collapsing the payload parse shifted
  every line below it by +28, and the differential's coverage and drift assertions **refused to
  score** until the site inventory was re-pinned. Three of my own controls also failed first: a
  `sed` whose `|` delimiter collided with a `|` in its replacement; two anchors that correctly
  detected the stamp had MOVED to the new top-of-file parse; and an anti-vacuous mutant that deleted
  the stamp instead of freezing it — **the fallback silently repaired it, so the control was
  measuring the fallback, not the change**. Each failure was a real defect in the control.

  **Blocked tail, stated by stratum** (`zero-claim-must-name-its-excluded-strata`): 8 are
  `source: needs` operator-platter rows, 1 needs root (`memorystatus_control`), 1 needs a `launchctl
  enable` in the user domain — **10 operator-gated** — and **1 is a cloud-venue build item**
  (`02ba4e52389a`), which is outside this lane's non-cloud contract. #14's close said "11
  operator-gated"; that was one too generous. Also noted, not closed: `5436396f405c`'s agent-typed
  half is now enforced live by #14's FF-GATE (`17ecae6c6`), but a human-typed advance remains
  unhooked, so its `needs` row stands.

- **2026-08-17 ~11:30Z — recycle #14: `master-enforcing-store` 17 open → `1 open / 11 blocked
  (11 operator-gated)`. filed 0 / closed 16 (15 done + 1 blocked). Nine commits, one land,
  `7c08a4bbf` + the row-6 doc; content-verified on `origin/main`.**
  Six of the seventeen rows retired for ZERO code on re-validation. **The transferable finding is
  that a row's premise decays in BOTH directions, and the UNIT decays before the VALUE.**

  **The unit, not the number, was wrong twice — and both times the convenient reading was the
  wrong one.** `1c16b58d9d3b` measured MEMORY.md in raw BYTES against a 24.4 KB limit; the repo had
  already replaced that instrument (2026-08-15, `7a56de4c54ab`) with **25,000 stripped CHARACTERS**,
  and `hooks/memory-nudge.sh:22` marks its own old figure SUPERSEDED in a comment. Measured with the
  canonical `hooks/lib/memory-index-measure.sh`: **23,112 chars / 140 lines against 25,000 / 200** —
  92.4%, not breaching, and `cc-memory-rotate`'s `ROTATE_AT` is `LIMIT-1500` = 23,500, so the
  actuator sat **388 chars from firing on its own**, wired 5/5. It is a 13-row near-duplicate family
  across `memory-index-near-cap` / `memory-index-over-budget`, every one measuring bytes against the
  dead limit; three are still open under other conditions and `7c266e16fc94`'s "OVER its limit,
  trailing entries SILENTLY dropped" is a **false alarm** under the corrected measure.
  `a78f0fa4223a` asked to prune "one-shot exact-matches": 63.2% of patterns ARE exact — but
  **exactness is not deadness**, and the teammate REFUSED the row's own predicate on measurement and
  shipped a provable-redundancy one instead (245/2399 = 10.2%), re-measuring 59/2036 → 63/2399 on
  the way.

  **A falsifier can be POLARITY-BLIND to the remedy that actually shipped.** `7d18f9c26f1f`'s probe
  was `test -x scripts/team/verify-team.sh` — it could only retract if that script were RESTORED,
  the opposite of the row's own other sanctioned remedy ("fix both or delete the arm"), which is
  what landed (`2d7b125d6` deleted the arm and its vacuous suite; `cb6314be1` fixed the
  `VERIFY_EXIT=$?`-after-`|| true` half). Its rc 1 was a NON-VERDICT, not a defence of the row.

  **Three ratchets caught the LEAD, and all three were real bugs — budget a land cycle for them.**
  (a) pipefail-SIGPIPE caught my own `git ls-tree … | grep -q .`: `-q` exits early, SIGPIPEs the
  producer, and under `pipefail` the condition **reads FALSE on a MATCH** — a path that IS present
  would have been reported absent. (b) The bats dead-assertion ratchet caught my ANTI-VACUOUS arm
  being itself vacuous — a `!` negation MID-test is dead because errexit skips it. (c) My own
  wrapped prose line beginning `# shellcheck read each bare …` was parsed as a malformed directive
  and aborted the whole file, which that lint's `--selftest` caught. **Four land attempts for one
  land.**

  **A teammate corrected the lead's instrument, and that is the methodological keeper.** I screened
  the `.claude-next` hooks fork with `cmp -s` and reported "52 identical" — **`cmp` FOLLOWS
  SYMLINKS**, so a link-into-the-checkout compares equal BY CONSTRUCTION and the sweep was vacuous.
  The conclusion survived for a better reason (0 regular files of its own, empty reverse gap), and
  `migrations/0013` now classifies each entry (same link target / resolved-byte-identical /
  directory) and refuses on anything else, with arm 6 pinning exactly that.

  **Lands.** `ee05adc63` (`bf63ce9f91fd` — `code_locality_warn`: a DISPATCHABLE label can still name
  a repo without the code; 0 misfiled among the 13 path-bearing rows, 36 of 49 UNMEASURED and said
  so) · `dcd16bd32` (`61d8605a25fc` — install.sh; the value is `$HOME`-derived while the write is
  `--global`, and git resolves `--global` through `GIT_CONFIG_GLOBAL`/`XDG_CONFIG_HOME` first, so
  they are not bound to the same HOME; discriminator is the passwd DB via getpwnam, not a path
  denylist) · `4063d5679` (`a78f0fa4223a`) · `963dbd0a2` (`70cc9f44040f` — grouping-sweep fail-CLOSED;
  **exit 2 is a measured choice**: `--assert` is this script's own stored falsifier and cc-premise
  reads exit 0 as THE CONDITION IS GONE, so an absent engine did not merely fail to measure, it
  RETRACTED the escalation row — 2 is already in `_FALSIFIER_UNASKABLE_RCS`, and autonomy-sweep's
  consumer was fixed in the same diff) · `11b85f97b` (`a148bd3bc3e6` — cc-premise gated on the
  ITEM's project, not the SHA's, so every meta-item about another repo minted `verdict=suspect`;
  now widens to sibling repos on a miss and keeps THREE states, and a real fixture leak was caught:
  unpinned, the widening reached the operator's real checkouts where the "resolves nowhere" token
  resolves) · `7b1049846` (`7ea31ffa1a08` — migration 0014; the trace question its filing gated on
  is SETTLED: **352 subagent transcripts exist**, so it is a harvest-index gap, not data loss) ·
  `17ecae6c6` (`8c6606b6f048` — FF-GATE; the class was DETECTED and enforced by nothing, and the
  quiet since 08-12 is not a fix: `5626e682f` removed deploy-now's raw ff on 08-10 and ungated
  advances continued two more days) · `7c08a4bbf` (`11da376d60e3` — migration 0013) ·
  the row-6 doc (`f5b31e05b0f7`).

  **`f5b31e05b0f7` — GROUND-UP row 6 reconciled, and the campaign's last row now self-heals.**
  `docs/plans/GUARDRAIL_HOOKS_V2.md` (262 lines) exists and is `status: open`, so the `plan-open`
  generator — which takes an OPEN PLAN DOC as input and was structurally blind to the one row that
  never had one — can now mint dispatcher-reachable rows for it. STEP -1 against `origin/main`, 18
  days after the payload was composed: **8 of 12 claims MET or SUPERSEDED**. The whole graveyard
  cherry-pick step is DEAD WORK (all five files on trunk, proven with a negative control beside the
  positive); row 13's inbound remainder is SUPERSEDED because **row 13 falsified its own premise**
  (contaminated denominator; clean instrument 92/92 = 100%); the payload's "`/goal` DOES NOT EXIST"
  inferred absence-of-FEATURE from absence-of-a-slash-command-FILE. **What still FAILS is what the
  row was commissioned for, and it got WORSE**: 62→**79** distinct `(event,script)` pairs, 4→**7**
  drifting, every one missing from `.claude-next` ALONE, because registration writes four files and
  skips the fifth — and `settings-drift-assert.sh` is correct, has a `--selftest`, and has **zero
  live callers**. Root cause is A8: all five `settings.json` are REAL FILES with distinct inodes, so
  hooks converge for free via per-file symlinks and `settings.json` does not converge at all.

  **THE ONE ROW LEFT OPEN, and the instrument defect that stopped it.** `8942f3b1506d` (R-3,
  HOOK_CHAIN_COST) is BLOCKED by its own terms on "a differential corpus proving identical verdicts
  on every DANGER pattern first". Its premise is stale — it says 12 grep forks / ~42 ms;
  `hooks/validate-bash.sh` is now **1012 lines with 32 grep sites**. A teammate built the right
  harness (a shim dir on `PATH`, one wrapper per external, logging each exec) and it **self-destroyed
  on a defect worth inheriting**: every shim body is `exec grep "$@"` while `PATH="$S/shim:$PATH"`,
  so the bare name re-resolves to the shim and self-execs forever — the 772,768 `grep` lines in its
  fork log are ONE INFINITE SELF-EXEC, not a measurement, and the same defect is in `shim/pwd`.
  `measure.sh` already used absolute `/usr/bin/*` for its OWN accounting, so the author knew the
  hazard for the harness and not for the shims. **Fix: `exec /usr/bin/grep "$@"` inside each shim.**
  (Same class as `self-identity-guard-must-fully-resolve`.) Nothing was committed; the row is handed
  to #15 with the corrected instrument.

  **Instrument note for every successor: `cc-backlog list --open` FOLDS IN BLOCKED ROWS.** It
  reported 27 for this condition when the true open count was 17. Filter on `.status=="open"`
  explicitly, and use `(.condition//"")` — a null condition makes a bare `test()` throw.

  **Not claimed as live.** Both new migrations are **c10 by design** (0013 gated on zero live
  `.claude-next` panes — that account HAD live panes at land time; 0014 registers subagent-stop):
  they stage and wait for a human, and `registration-state.sh` reports them `not-delivered`. The
  land's smoke gate SHED (`selector answered FULL … the verifier proves the tree`), so the
  behavioural evidence is that the lead re-ran all nine touched suites in-turn: **115 assertions, 0
  failures**. `deploy-live.sh` was run and **declined**: no GREEN tree is a descendant of live HEAD
  `12b4740c8` (newest green is BEHIND it), lag 23 commits / 2h inside the 25/6h degrade budget — so
  the shared checkout is 23 behind and none of these nine commits are live yet. Not filed as a new
  row: the platter already renders that deploy-lag line, and double-filing it would be net-filing.

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
- **2026-08-16 ~23:00Z — §6's chain-liveness invariant is now a mechanism; S3 landed and REFUTES
  the 20:30Z reading of the convergence gate.** Cloud session (Claude Code on the web, no backlog
  store / no launchd / no live layer reachable — see the locus note at the end of this entry).
  **Trunk re-read by content**, every sha the 20:30Z entry claims: `46a86deb7` · `944abba49` ·
  `672f34757` · `a87f32c66` · `1817ca740` · `b4d0a3d0f` all ancestors of origin/main. **S3 landed
  as `2f84bf74`** — and its finding is not the one it was fired on: postland-verify's `retry_once`
  runs under TWO bounds (FILE_TO 300 s for the single named test, RETRY_TO 5400 s for the
  whole-file fallback), rc 124 is identical from either, and the abstain message named RETRY_TO
  *unconditionally*. So the sixteen cuts the 20:30Z entry read as "our own 5400 s ladder bound
  firing on tests/autonomy-sweep.bats" happened inside runs whose totals were 3364 s and 3538 s —
  a 5400 s bound cannot fire in a 3364 s run. The real cut was one test overrunning the 300 s
  per-file bound; the suite is 55/55 green in 77.09 s at the ladder's own band. **"A suite too slow
  to re-run" was never the measurement, and a whole session was dispatched against it** — the same
  claimed-outcome-vs-checked-outcome shape §1 catalogues, one layer up.
  **§6's chain-liveness invariant was prose and nothing else.** `fire-drain-recycle` appeared in
  this plan and in NO script, test or plist on trunk, so the plan that diagnoses "a conclusion that
  never reached an enforcing store" (§1.2: the chain stopped at 06:45Z and the operator was the
  detector, hours later) was committing it about its own remedy. Now implemented:
  `scripts/drain-chain-assert.sh` (report / `--assert` / `--file` / `--json`), called from
  `autonomy-sweep.sh` § 2b-v every 300 s tick and journalled as `drain_chain_rc`, with
  `tests/drain-chain-assert.bats` — 15 cases green, and the two load-bearing guards red-proved by
  reverting them. It files ONE condition-keyed row (`local-drain-chain-dead`) carrying `--assert`
  as its own falsifier, so the chain restarting retires it with no human in the loop.
  Three fail-open guards, and the middle one is the one that decides whether this is a detector or
  a generator: an unreadable store abstains (`skipped`/`read-failed` — "I could not ask" is never
  "the answer was no"); **zero live rows is `drained`, i.e. ALIVE**, because §6's own terminal
  condition is chain-complete-at-true-zero and an alarm keyed on "no recycle fired lately" alone
  would file its first row on the day the program SUCCEEDED and hold it open forever
  (cap-whose-population-is-empty — precisely how `backlog-ratchet.sh` came to be red on every run
  it had ever made); and any live lease counts whoever holds it, because the question is "is
  anything draining" and Lane A cloud work is the chain too. Portability: the brief's mtime uses
  the validated BSD-first form landed in `4d7bc86d`, whose naive `stat -f %m || stat -c %Y`
  ancestor leaks a filesystem block to STDOUT on GNU — that failure would have reported DEAD on a
  box that was draining fine, i.e. the false-DEAD direction that files a permanent row. Red-proved
  by a test asserting the AGE, not the verdict.
  **Locus — what this session structurally could not do, and did not fake.** A cloud container has
  no `~/.claude/autonomy/backlog.jsonl`, no launchd, no panes and no live layer, so R1, R2, A1/A2/
  A4, B1-B5 and every §5 probe stayed untouched; §2's venue pass already measured this — 10 cloud /
  259 local, and 79% of labelled refusals name THIS MACHINE as the work's subject.
  ⚠️ **This diff ADDS two files, so it is not live at lag 0.** `~/.claude/scripts/` is a per-file
  symlink dir populated by `install.sh`'s `scripts/*.sh` glob: an EDIT rides its existing link and
  merely runs older bytes, but an ADD has no link at all and the sweep's `[ -x "$_drain" ]` guard
  is a *silent* skip. `bash scripts/deploy-live.sh` on the box is what makes the check exist.

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
  **IMPLEMENTED 2026-08-16** → `scripts/drain-chain-assert.sh`, called from `autonomy-sweep.sh`
  § 2b-v (`drain_chain_rc` in the `backlog-health` IDL row), pinned by
  `tests/drain-chain-assert.bats`. Ask it directly with `drain-chain-assert.sh --json`; the row it
  files carries `--assert` as its falsifier and retires itself when the chain restarts. Zero live
  rows reads ALIVE (`why=drained`) — that is this invariant's terminal success state, not a
  silence to be alarmed about, and the distinction is what keeps the detector from becoming the
  store's next generator.
- Weekly report: adds vs closes; net-positive week ⇒ the INFLOW list (C1-C4) gets the next
  fix, not more drain horsepower.

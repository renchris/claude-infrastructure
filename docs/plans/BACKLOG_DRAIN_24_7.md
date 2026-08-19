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

- **2026-08-19 — drain recycle #51: the reaper's safety guard was inverted with respect to the loss
  it prevents, and the fix is not a wider guard but a second channel — and a row filed as "three
  rare instances you cannot schedule" turned out to be 352 measured events, 17 of them today.**
  `master-fleet-footprint` **11 open / 4 blocked (4 operator-gated; 0 cloud-venue, 0 claimed, no
  stale claim)** — unchanged from intake. **filed 0 / closed 0.** Landed `4e4c0f3f4` +
  `a10986411` + this entry (`e02b1d775`). *(Those first two shas are the post-rebase objects. This
  entry originally cited `d4239f179`, which the land's own rebase rewrote — `--is-ancestor` reads
  rc 1 for it against trunk while the content is plainly there. Corrected the same pass rather than
  left as a dead pointer; memory `cited-sha-may-not-survive-the-land`, and the reason this log
  verifies landings by CONTENT.)* Effort choice: `date` read 2026-08-19, so
  `master-session-lifecycle`'s `62363cac1e39` efficacy re-census (due ~2026-08-24) was still shut
  and correctly declined for the 24th consecutive recycle. Intake property re-measured and it held:
  11/11 open are `venuePlan=local` AND `project=claude-infrastructure`. Both claims came back clean,
  no advisory. 0 teammates, 0 Explore surveys.

  **`7c22e9b43956` (cc-reaper reaps a peer that never committed) — BUILT AND LANDED, LEFT OPEN.**
  #50's forensics were right and the remedy it warned was "not obvious" really is not. The
  discriminator is the worktree's **own HEAD reflog**, never the ahead-count: measured on this box, a
  worktree holding 173 commits reads `ahead=0` once landed and carries 173 reflog `commit` entries,
  while a fresh worktree reads `ahead=0` and carries none — same ahead, opposite reflog. But the
  obvious remedy is the hazard: "never reap a 0-commit session" would permanently exempt every peer
  that legitimately finished without committing, and the log says that costs real volume (618 REAP
  lines / 173 distinct panes, against 3,631 DEFERs). So the belt asks for **positive done-evidence on
  the two channels a dispatched peer actually has** and fires only when BOTH are definitively silent:
  it never committed here, AND it never announced to the back-channel armed at fire time.
  **The second oracle already existed and the reaper had never called it** — `$mailbox/.sent/<pane>`,
  written by `cc-notify _record_send`, read by `handoff-fire.sh sc_announce_before_retire`. That read
  runs only on the **self-close** path, and the reaper's entire population is the sessions for which
  self-close never ran, so sharing the code would not have shared the reach (question (n): X was
  built and called by nobody *on the path that needed it*). Narrowed to peers fired WITH
  `--notify-back`, measured first: 144 of 938 fired stamps carry one, and of 30 recently-reaped panes
  14 had a send record and 16 did not — the oracle reads both ways on the live population.
  Three-valued throughout; only definite negatives combine. **LEFT OPEN because the row's stored
  falsifier is broader than what I built**: it names a fixture with a valid fired-peer stamp and says
  nothing about `--notify-back`, so an unarmed peer is still reaped on `ahead=0`-by-silence. That
  remainder is real and the row already names its candidates — transcript/beat evidence, or a
  pending-background-task check. Not narrowed, not argued away.
  10 bats cases, 6 red against pristine `637eca308` — and the honest split is recorded in the suite
  itself, because only two of the six are evidence about the defect (B1/B2); B4/B6 red only on their
  new log assertions and B9/B10 red because the functions do not exist yet. 8 mutants, 8 applied, 8
  reddened ≥1 case, 0 green, 0 non-verdicts, subject restored byte-identical. One prediction was
  wrong and running it is what said so (M3 was expected to red B4; it defaults only an EMPTY address
  and B4 arms a real one). Full suite after: **145/145, plan line `1..145` seen, 0 skips.**

  **`b38279c10c55` (capture the sender of the group-SIGTERM) — PREMISE CORRECTED, LEFT OPEN.**
  The row and its source doc frame this as two-or-three unschedulable instances. Measured across all
  four transcript stores (6,996 files): **352 distinct events** deduped on task-id, **348 of them
  mid-session** (median 293 records follow — which refutes the pane-teardown explanation outright,
  since a teardown TERM would be the last thing in its transcript), 109 watcher/wake-path arms
  against 243 ordinary backgrounded polls and builds, running to 42/day. So the row's blocker —
  *"you cannot schedule the hit, decide how you will prove a recorder fires before you build it"* —
  dissolves: at one event every few hours, a recorder armed in ANY backgrounded group captures an
  `si_pid` within a day. Confirmed no recorder is in the tree (only `cc-await-ping`'s comment saying
  one is needed), and flagged the constraint that will bite whoever builds it: **macOS ships no
  `sigwaitinfo`**, so Python cannot host it and a compiled helper means a new `bin/` file, i.e. a
  `LIVE_ADDS` breach until the converger runs. LEFT OPEN — the sender is still unnamed.
  → `docs/research/exit-144-population-2026-08-19.md`; the 2026-08-07 doc's §5 gains a pointer.

  **RECIPE-LEVEL FINDINGS (recorded here, not filed — conservation).**
  (a) **Five instruments, four wrong, each reading as a clean answer** — the fullest instance this
  chain has recorded. Counting `exit code 144` over the transcript corpus counts the sessions
  *discussing* it (including the one counting); the fuller phrase `failed with exit code 144`
  selects the **identical** 215 files, and that identity is the tell; classifying `tool_result`
  records as events counts every Bash call that merely PRINTED the source comments; counting
  `queue-operation` records double-counts because the notification is written twice per event. Only
  **dedupe-on-`task-id` over `type=="queue-operation"`** answers. The law: **a quotable string cannot
  distinguish an event from a discussion of it — find the record TYPE, which quoting cannot forge.**
  The positive control is what proved it: this session displayed the phrase nine times, suffered no
  144, and carries zero `queue-operation` matches.
  (b) **A sixth error nearly shipped a wrong headline**: testing "is this a cc-await-ping death?" by
  looking for `await-ping` in the notification returns **1 of 352** and reads exactly like "the row's
  subject is a non-event". That field holds the **operator-written prose description**, so the real
  arms are spelled `Arm inbox watcher` / `Re-arm inbox wake watcher` — 109 of them. Same law as
  `pgrep-f-matches-agent-briefs` and `caller-census-keyed-on-path-misses-the-name`.
  (c) **`grep -c` prints `0` AND exits 1**, so `$(grep -c … || echo 0)` yields the two-line string
  `"0\n0"` and every numeric test downstream errors out — which rendered, in this pass's first
  census, as `never-committed=0` across every worktree, i.e. exactly the answer that would have
  killed the row. No `||` arm: the count IS the answer.
  (d) **`sort -u | tail -N` over a corpus that changed identifier format samples only the OLD era.**
  Cross-checking reaped panes against `.sent` returned `0 of 40` — read as "reaped peers never
  announce", was actually "these 40 are UUID-era ids and `.sent` is keyed by the numeric pane id
  today". The current era is 200/200 numeric and the key spaces DO align. Sample the recent tail
  explicitly when an id format has migrated.
  (e) **The live-layer converger's refusal now has a named culprit.** `deploy-live.sh` refused for
  the 25th consecutive recycle, correctly (`--ff-only` would exit 0 without moving the tree). The
  block is **one un-landed commit sitting in the shared checkout `~/Development/claude-infrastructure`
  on `main`, dated 2026-08-19 04:10** — `git rev-list --count origin/main..9709c99d3ce2` = 1. Not
  this chain's (this chain never commits in the shared checkout, per the project CLAUDE.md). Naming
  it beats re-reporting "no GREEN tree is a descendant": the remedy is to land or drop that one
  commit. Consequence owned honestly: **the reaper belt landed this pass is NOT live until that
  clears**, because the launchd job runs `~/.claude/bin/cc-reaper`.

- **2026-08-19 — drain recycle #50: two rows closed on measurements that contradicted the brief
  they were handed to me in — a migration four recycles carried as "pending" was already live, and
  the session death nobody could explain was killed by our own reaper, past a guard that cannot
  fire for a session which has not yet made its first commit.**
  `master-fleet-footprint` **11 open / 4 blocked (4 operator-gated; 0 cloud-venue, 0 claimed, no
  stale claim)** — down from 12. **filed 1 / closed 2.** Landed `cb980161b` + `eefdd0396` + this
  entry. Effort choice: `date` read 2026-08-19, so `master-session-lifecycle`'s `62363cac1e39`
  efficacy re-census (due ~2026-08-24) was still shut and correctly declined for the 23rd
  consecutive recycle. Intake property re-measured and it held: 12/12 open were `venuePlan=local`
  AND `project=claude-infrastructure`. Both claims came back clean, no advisory.

  **CLOSED `5d1b5dd9b3db` (headless-substrate spec) — the first recycle for which closing it was a
  live option, and it closed.** The row's OWN falsifier passes: `headless-precondition-probe.sh
  --json` under T1's specified `env -u ITERM_SESSION_ID -u CC_PANE_ID` returned `P1_no_pty=PASS`,
  `P2_hooks=PASS` (`P2_missing=""`), `P3_mail=PASS` with `P3_reached_model=yes`, rc 0 — T1's
  contract was "P3 FAIL pre-fix, PASS post-fix". Tests: **312 cases / 9 suites, all green, every
  `1..N` plan line seen in that run, 0 skips.** Closing record landed into the spec doc itself.
  **Four corrections to the carried-forward record**, each re-derived at the moment of the close:
  1. **F0 IS NOT UNRUN.** #46-#49 all carried "run migration 0007 — OPERATOR-ONLY, pending".
     `scripts/registration-state.sh` says `verdict=registered … verifier exit 0 in all 5 config
     dir(s)`. `migrations/README.md:37` defines that verifier as "exit 0 ⇒ the effect **is live in
     the enforcing store**". `ledger=staged` means the SCRIPT was never invoked, not that the
     EFFECT is absent — and the instrument already distinguishes `registered` from
     `staged-pending`. **Nobody in four recycles had asked it.** Generalisable: when a brief says
     an item is pending, check whether the item's own verifier agrees before inheriting the claim.
  2. **E10's population is empty BY CONSTRUCTION** (upgrading #49's "empty today").
     `bin/cc-pane-headless:197` is `export CC_PANE_ID="$id" && unset ITERM_SESSION_ID && exec "$@"`,
     so the only sanctioned headless spawner GUARANTEES an address, and no launchd job spawns a
     local claude session at all. Live census (`ps -axo pid=,command=` anchored on argv[0], this
     session as a positive control — **PRESENT**, pid 96992, which `pgrep` structurally could not
     have found): 17 claude procs, 17 with an address, 0 with neither.
  3. **E6's key is `session_id`, not `sessionId`** — sharpening #48, whose refutation stands. A
     reader keyed on `.sessionId` misses as surely as `.sid`. Near-miss checked and **cleared**:
     `cc-reconcile:221` reads `.sessionId` from Claude Code's OWN per-pid store, whose schema
     genuinely uses that spelling, and re-emits it as `session_id` at `:248-251` — it is the
     translator between two schemas, not drift.
  4. **Q2 no longer gates gap 2.** The doc still said Q2 "is the one that actually gates gap 2" —
     true of gap 2 AS DESIGNED, over `asyncRewake` (W2). What was BUILT is W1: `cc-wake-headless`
     writes stream-json to the fifo `cc-pane-headless` holds open (5 fifo refs, **0** asyncRewake).
     **A spec's stated blocker can be routed around by the implementation, and the spec never
     learns.**

  **CLOSED `b521cb445465` (the unexplained session death) — a closer DID run: `cc-reaper`.**
  `cc-reaper.out.log` carries the lifecycle `[active] → [active] → [finished-teammate] "idle 473s
  < settle 600s" → REAP`. The transcript's last record enqueues a task-notification for background
  Bash task `bn8c8kjam`, so **the session was blocked waiting on its own background task when it
  was killed**; there is no SessionEnd record in it. Transcript mtime `Jul 29 21:39` local against
  a `2026-07-30T04:39:12.303Z` record fixes PDT = UTC-7 and puts the reap in the same minute.
  **Why the guard could not fire:** the chain checks landed (`:1323`) BEFORE settle (`:1332`), and
  the victim's log shows the `:1332` message — so it necessarily passed `:1323` with `landed=yes`.
  **The log ORDERING is the evidence; it is not inferred from reading the code.** `work_landed`'s
  first line is `bin/cc-reaper:842` — `[ "${ahead:-1}" = 0 ] && return 0  # 0 ahead by COUNT →
  landed`. The victim had made **no commits at all**, so the fast path returned "landed" and the
  guard whose own comment calls it "still the whole safety story" was structurally unable to
  protect it. `ahead=0` conflates *committed everything and landed it* with *never committed
  anything*; `:1432` calls the reap "positive done-evidence, not inferred from silence", but for a
  session that never committed, **`ahead=0` IS the silence** (`lookup-miss-is-not-absence`).
  **THE PROTECTION IS INVERTED WITH RESPECT TO THE LOSS**, and the same sweep proves it: three
  sibling `finished-teammate` sessions were SAVED by the DEFER guard, every one of them *because it
  held commits* — the recoverable case. The victim held none, so its entire work product lived only
  in its transcript, and it was the one session in the sweep with no protection at all. The
  2026-07-24 belt (`:1342`) does not cover it either, symmetrically: that belt exempts properly
  stamped fired peers, which is exactly what a dispatched peer is. Record:
  `docs/research/reaped-uncommitted-peer-2026-08-19.md`. The row's own hypothesis named the right
  subsystem and the wrong element — not the marker, the DEFER guard's PREDICATE.

  **FILED `7c22e9b43956`** (the remedy, into `master-fleet-footprint`) rather than built: `cc-reaper`
  is a live janitor with real blast radius, and a correct predicate must distinguish "never
  committed" from "committed and landed", which `ahead` alone cannot do. Needs its own red-proofs
  and a full window. Conservation: **closed 2 ≥ filed 1.**

  **Strata of the remaining 11**, so the next recycle does not re-derive them: `399b9938bef8` is
  genuinely CROSS-REPO (reso's `scripts/worktree-pool.sh`) despite its `project` field — not
  drainable by this chain. `e78107996dea` re-checked a THIRD time and still **23,128/23,128 NULL**
  `argv0` over 2026-07-30→2026-08-19, i.e. the log has NOT rotated and #40's landed field has still
  never converged — structurally blocked on the live layer, not on analysis. `475222a572de` +
  `ce775801633b` remain a blocked pair. `66ef300dd0b4` is an umbrella to refresh, not to work.
  `f0283c35130e` is a value call on live daemons. That leaves `2029c52b8a32`, `b38279c10c55`,
  `d4fa449e3895`, `15265ac3c502` and the new `7c22e9b43956` as genuinely agent-workable — and
  **`7c22e9b43956` is the best of them: a named defect with a stated falsifier and a real death
  behind it.**

  **Instrument notes (recorded, not filed).** (a) A `for i in …; do grep "T$i[ :,)]"` sweep returned
  `files=0` for all 17 ids — **an instrument failure that reads exactly like absence**, because zsh
  parses `T$i[ :,)]` as an array subscript. Re-run in `bash -c` it found the real answer. The
  all-zero column matching the hypothesis is precisely when to check the instrument (#49's second
  law, hit again). (b) `LIVE_LAG=35` / `LIVE_ADDS=38` at close were **attributed and are NOT mine**:
  `git diff --name-status --diff-filter=A` over my range under `bin hooks scripts commands` is
  empty — my only add is a `docs/research/` file, which is not in the live layer.

- **2026-08-19 — drain recycle #49: a pooled worktree runs several sessions and the liveness
  registry had room for exactly one, so the second session erased the first's proof of life.**
  `master-fleet-footprint` **12 open / 4 blocked (4 operator-gated, `source: needs`; 0 cloud-venue,
  0 claimed after release, no stale claim)** — unchanged. **filed 0 / closed 0.** Landed
  `bdf57e195` (E14) + this entry. Row `5d1b5dd9b3db` LEFT OPEN, claim RELEASED.
  Effort choice: `date` read 2026-08-19, so `master-session-lifecycle`'s `62363cac1e39` efficacy
  re-census (due ~2026-08-24) was still shut and correctly declined for the 22nd consecutive
  recycle. Intake property re-measured and it held: 12/12 open were `venuePlan=local` AND
  `project=claude-infrastructure`. Claim came back clean, no advisory.

  **E14 — BUILT AND LANDED (`bdf57e195`).** `hooks/live-session-registry.sh` keyed its row
  `basename($cwd)`, a PER-WORKTREE key. A pooled worktree hosts more than one session, so the
  second session's row REPLACED the first's and the registry recorded one pid out of two. The
  unrecorded session then has no positive liveness proof at all: once the recorded pid exits (or
  its SessionEnd removes the row), `worktree-gc.sh` `registry_live()` answers NOT-LIVE for a
  worktree that is still OCCUPIED and falls back to the flaky cwd/lsof oracle that file's own
  header says it exists to eliminate — a LIVE worktree becomes reapable.
  **MEASURED AT INTAKE, not assumed:** `wt-pool-2` and `wt-pool-8` each carried TWO live `claude`
  procs with DIFFERENT parents — SIBLINGS, not the nested-probe ancestry the tenancy gate covers,
  which is exactly why that gate never caught this. Pids 21808 and 54762 were unrecorded.
  The key now carries the sid (`<basename>-<sid8>`) and `registry_live()` reads `$base` AND
  `$base-*`, keeping the worktree if ANY row is live.

  **Three things the fix had to get right, each pinned by a case — and the first CORRECTS the
  spec.** (a) The bare key is NOT a transition window, as E14's text assumes.
  `~/.reso/worktree-gc-run.sh:96` is a SECOND WRITER into this shared store, from another repo,
  and it still keys bare — its rows are the `scan`-sid ones visible on the live box. Both shapes
  must count indefinitely. (b) The wider read must not manufacture liveness: base `wt-pool` globs
  `wt-pool-*`, which matches a row belonging to the DIFFERENT worktree `wt-pool-2`. The
  recorded-cwd check now runs PER ROW, which is what makes the glob safe — and it is why the
  spec's prescribed `"$base"*` was narrowed to `"$base"-*` plus that per-row check.
  (c) The tenancy gate is not silently disarmed. A sid-bearing nested probe now lands on its own
  key and structurally cannot overwrite the tenant, so the gate no longer fires for it; it still
  covers the degraded no-`session_id` input. Said plainly in the source rather than left looking
  load-bearing, and tests 5/6 now fire the nested probe WITHOUT a session_id so that path stays
  reachable instead of passing vacuously — #47's law ("the guard exists and nothing can reach it")
  applied to a guard this recycle was itself about to strand.

  **Tests: `tests/live-session-registry-atomic.bats` 8 → 15 cases, 15/15 green, `1..15` seen, 0
  skips.** Cases 1-8 were MIGRATED, not weakened — they pinned the old key shape, which this change
  deliberately alters (#46's law: the census was right, so migrate it and extend it). Two
  migrations carry real content: test 2 now re-registers the SAME sid, because two different sids
  write two different files and would never exercise replacement at all, and test 4 hammers one sid
  for the same reason. `registry_live()` had **NO test coverage at all** before this; cases 11-14
  extract it behind an anti-vacuity check, because a per-session key that no reader globs for would
  be strictly WORSE than the bug it replaces.
  **Red-proof: 9, 10, 11, 12 red pre-fix** against the restored `origin/main` subjects (control
  asserted pre-fix, restoration proven by `git status --porcelain` + `diff -q`). **13, 14, 15 are
  GREEN PRE-FIX BY CONSTRUCTION** — they assert a PRESERVATION, and their guarantee is carried by
  named mutants, never reported as red-proof.
  **7 mutants, 7/7 MATCH**, plan line asserted on every run with non-verdict arms for a missed
  anchor, a wrong plan line and any `# skip`: M1 (drop the sid suffix) reds 1,2,7,8,9,10 — wide,
  and that IS the key shape's real blast radius; M2 (drop the bare key) reds 13 ALONE; M3 (drop the
  per-row cwd check) reds 14 ALONE; M4 (gate never refuses) reds 5; M5 (drop the IDL write) reds 6;
  M6 (first row decides) reds 12 ALONE; M7 (suffix unconditionally) reds 6,15.
  **M4 refuted my own prediction and the mismatch is the finding:** I expected it to red 5 AND 6,
  but the IDL journal write PRECEDES the `exit 0` it replaces, so the refusal is still recorded
  while the row is stolen. The mutant was right and my model of the ordering was wrong.
  **M6 exists because writing it exposed a weak case.** Case 12's live row originally sorted BEFORE
  its dead one, and a glob expands in sorted order — so it would have passed just as well against a
  reader that stops at the first row it finds, pinning "some row is live" rather than "ANY row
  keeps the worktree". The dead row now sorts first, deliberately.

  **E10 — NOT BUILT, AND THE REASON IS A MEASUREMENT: ITS POPULATION IS EMPTY TODAY.** #48's brief
  required re-measuring before building, and that was the right instruction. E10 asks
  `bin/cc-reconcile` to synthesise a sid-keyed row for a session with no pane. But `:190-197`
  already prefers `CC_PANE_ID` and already accepts `hdl-<16hex>` (E1-E5 landed by widening that
  address gate), so `cc-pane-headless` sessions are NOT in the class. The residue is a session
  carrying NEITHER `CC_PANE_ID` NOR `ITERM_SESSION_ID`. **Censused live: 0 of 17 live claude
  sessions.** All 17 carry `ITERM_SESSION_ID`; 1 also carries `CC_PANE_ID`. Building it now would
  be speculative and unverifiable — #41's law, a population with no member of the class cannot
  report what that class would get — and its prescribed `n_headless` counter would be an alarm that
  can only ever read 0. **E10 stays open with its population recorded, not with a guess.**

  **RECIPE-LEVEL FINDING, recorded here rather than filed (conservation — this recycle closes 0).**
  🚨 **`pgrep` EXCLUDES THE CALLER'S OWN ANCESTORS, so a census a session runs on itself is
  structurally blind to that session.** Found as a failed positive control: my own registered,
  demonstrably-live session (pid 65515, `lsof` cwd correct, `kill -0` fine) was absent from both
  `pgrep -f claude` and `pgrep claude`. **The obvious hypothesis was argv length and it is REFUTED
  ON BOTH ARMS** — this session's argv is 71,565 bytes because it carries the whole recycle brief,
  but a synthetic NON-ancestor at 60 KB is VISIBLE, and a synthetic ancestor of only ~20 bytes is
  INVISIBLE with a same-moment non-ancestor control VISIBLE beside it. The two variables were
  confounded in the natural sample (both invisible procs were long AND ancestors); decorrelating
  them is what produced the verdict. Two earlier probes of mine were VACUOUS in ways that read as
  confirmation — `sleep` rejected the pad and died (every case "INVISIBLE"), then
  `bash -c 'sleep 5' NAME` EXEC'd sleep and dropped argv[0] (every case "INVISIBLE" again). Only
  adding a control that the marker was actually IN the subject's argv turned the answer over.
  In-repo call sites that run from inside a session and therefore inherit this blind spot:
  `hooks/lead-crash-watchdog.sh:996-997` (concurrency count), `hooks/git-worktree-guard.sh:99`,
  `scripts/desk-arm-live.sh:122`. Not filed — each needs its own semantics checked first, and a
  filing while closing 0 would end this recycle net-positive on filings.
  Complementary to memory `pgrep-f-matches-agent-briefs` (argv so wide it matches too much); this
  is the same instrument failing the other way. Memory: `pgrep-excludes-the-callers-ancestors`.

  **Also observed, NOT filed:** `~/.reso/live-sessions/.wt-149789b69fc4.65918` is a leaked atomic-write
  tmp file dating to 2026-08-07 — the `mv`-failure path in the register hook cleans up, so this is
  most likely a kill mid-write. One stale byte-range, no correctness impact (readers glob real keys),
  and it is swept by the reso janitor's dead-pid pass. Recorded for a successor, not minted.

  **Teammates/subagents: 0 code, 0 Explore** (#44-#49 all spawned none). `master-fire-gate` (46
  open) and `master-convergence-deadlock` (55 open) remain UNSURVEYED — #43's and #28's Explore
  surveys both failed to return in-pass even with a call budget and a partials clause.

- **2026-08-19 — drain recycle #48: five of gap 1's eight uncensused edits were already DONE, and
  the sixth's prescribed edit points at a field that does not exist.** `master-fleet-footprint`
  **12 open / 4 blocked (4 operator-gated, `source: needs`; 0 cloud-venue, 0 claimed after release,
  no stale claim)** — unchanged. **filed 0 / closed 0.** Landed `5e8ba16ae` (E13), `602d51c64`
  (five dead red-proofs), + this entry. Row `5d1b5dd9b3db` LEFT OPEN, claim RELEASED.
  Effort choice: `date` read 2026-08-19, so `master-session-lifecycle`'s `62363cac1e39` efficacy
  re-census (due ~2026-08-24) was still shut and correctly declined for the 21st consecutive
  recycle. Intake property re-measured and it held: 12/12 open were `venuePlan=local` AND
  `project=claude-infrastructure`. Claim came back clean, no advisory.

  **THE CENSUS — the item this recycle was handed, and its answer is mostly "already done".**
  `E6 · E8 · E9 · E10 · E12 · E13 · E14 · E15` had been unverified for two recycles running. Done
  by PREDICATE, never by the spec's proposed identifier or line number, per the standing law:

  | edit | verdict |
  |---|---|
  | **E6** `bin/cc-sessions` | **LANDED, by a different route — and its prescribed edit is REFUTED.** All three sub-predicates hold: the `lstart` re-check sits beside `kill -0`, and the it2-membership stale test is skipped for `surface != headless` with a comment naming the very `lookup-miss-is-not-absence` trap the spec cited. But the prescribed `jq -r '.paneUUID // .sid // empty'` **cannot ever fire**: `hooks/session-register.sh:259-265` writes `paneUUID` on EVERY row (`hdl-<16hex>` for headless), so the `//` fallback is unreachable, and the sid is recorded as **`sessionId`** — there is no `.sid` field to fall back TO. Building it would have added dead code pointing at a nonexistent key. |
  | **E8** `bin/cc-notify` | **SATISFIED by ordering, not by the prescribed guard.** `target_live()` is registry-FIRST; the it2 fallback is reached only when NO row matched, so a registered headless target is never adjudicated by a pane list. The prescribed `[ -n "$pane_of_row" ]` gate presumes a row is in hand — which is exactly the branch that already returns before it. |
  | **E9** `bin/cc-reconcile` | **LANDED.** `:135-148` drops `--version` always and `-p` only when `--input-format` is absent; the comment cites "E9" by name. |
  | **E10** `bin/cc-reconcile` | **NOT landed** — `n_no_pane++; continue` stands, no `n_headless` counter. Narrower than it reads: `:191` already prefers `CC_PANE_ID`, so a `cc-pane-headless` session DOES get a key and is not in this class. The residue is a raw `claude -p --input-format stream-json` started outside that spawner. |
  | **E12** `bin/cc-reaper` | **LANDED** (argv half) — `live_pane_count` at `:811-819` carries the same `--input-format` discriminator, in the lockstep its own header demands. |
  | **E13** `bin/cc-inbox-guard` | **WAS NOT landed. BUILT THIS PASS** — see below. |
  | **E14** `hooks/live-session-registry.sh` | **NOT landed** — `:30` is still `base=$(basename "$cwd")`; the pooled-worktree collision (§4 A2) stands. Carries a migration obligation on `worktree-gc.sh`'s `registry_live()`. |
  | **E15** `bin/cc-teardown` + `hooks/teammate-auto-shutdown.sh` | **LANDED** — both scrapers read `^CC_PANE_ID=` first with `^ITERM_SESSION_ID=` as an annotated fallback. |

  So gap 1's remaining agent-doable surface is **E10 and E14 only**, and E6 should be struck from
  the spec the way E11 was by #41 — same shape of finding, one layer down.

  **E13 BUILT AND LANDED (`5e8ba16ae`).** Its own adversarial pass (§4 A4) calls it a precondition
  for turning the substrate on, not optional hardening. `owner_liveness()` reads `it2 session list`,
  which enumerates PANES; a headless address (`hdl-<16hex>`) is not 8-4-4-4-12, so `canonical_uuid()`
  rejected it and the function returned INDETERMINATE **before any probe ran** — every headless box
  with overdue mail escalating on the fail-loud arm with the cause *"'<key>' is a NAME-keyed box —
  not a pane uuid it2 can adjudicate"*: true of the SHAPE, false about the session. Now
  `headless_beat_live()` asks the beat at the two sites that were about to concede, with four
  narrowings, **and the KEY one is where a naive fix silently does nothing**: the beat is keyed on
  the SESSION id and the inbox on the PANE id, so a plain `cb_last_beat "$u"` misses on every box
  and reads as a working no-op — the registry row is the join. `indeterminate_why()` replaces the
  old two-way cause, which after E13 is a fabricated cause for exactly the class it was built for.
  6 cases, **2 red pre-fix against a pristine `origin/main` worktree**; the other 4 assert a
  PRESERVATION or an ABSENCE and are green pre-fix by construction, carried by named mutants.
  **14 mutants attempted across two rounds, 7 in the final series, 7/7 MATCH**, every run asserting
  its `1..6` plan line and zero `# skip`.

  **A MUTANT CORRECTED MY MODEL OF MY OWN CASE, WHICH IS THE REASON TO RUN THEM.** M3 (drop the
  surface gate) came back **GREEN**. Not a bad mutant and not a no-op: case 4 used the default
  readable `[]` it2 stub, and a canonical-shaped pane row is **adjudicated and returns one branch
  EARLIER** than the gate it claimed to pin — the case pinned nothing, over a population already
  excluded upstream. Making it2 unreadable moves the case onto the only path where a canonical row
  consults the beat at all, and M3 then reds it. This also **refuted my own first reading** that the
  second wiring site is purely defensive: it is reachable, and on it the surface gate is the only
  thing between a pane row and a beat-borne LIVE verdict. Both the case and the commit message were
  corrected before landing.

  **THE CARRIED FINDING WAS FIVE, NOT ONE (`602d51c64`).** #47 recorded that
  `tests/mailbox-drain.bats`'s E2 red-proof had degraded to a permanent `# skip`. Grepping the
  corpus for other moving-ref controls, as #47 advised, found **four more, all already dead**:
  `mailbox-drain.bats:399` + `:525`, `cc-await-ping.bats:997`, `operator-readout.bats:1243`. Each
  fetched its control with `git archive origin/main` and guarded staleness with `if grep -q
  '<sentinel>'; then skip; fi` — so the moment the change under test landed on main, the control
  BECAME the fixed tree and the case reported `ok … # skip` forever. **A stale control does not go
  red; it SKIPS, and bats renders a skip as `ok`** — which is why three suites read fully green over
  five controls that had stopped controlling. `tests/wake-floor.bats:164-170` had diagnosed this
  exact hazard in its own suite and fixed it the same way; the siblings were never migrated. All
  five are now pinned to the immutable parent of the commit that introduced their sentinel
  (`a94c8a5ea` · `73ceb76aa` · `f704bf8aa`), each verified an ancestor of origin/main with a
  two-sided control (sentinel hits 0 in the pinned tree, >0 in the introducing tree), and the
  staleness guard is a **hard FAILURE**, not a skip. Before: 5 permanent skips. After: mailbox-drain
  `1..53`, cc-await-ping `1..68`, operator-readout `1..81`, cc-inbox-guard `1..31` — **not-ok=0 and
  skips=0 in all four**.

  **RECIPE FINDING, recorded not filed (conservation).** `"$SHA:hooks/mailbox-drain.sh"` inside the
  Bash tool is mangled by **zsh's `:h` history modifier** — it resolved to `.ooks/…` and git answered
  *"ambiguous argument … unknown revision"*, while the very next `grep -c` in the pipeline printed a
  clean **`0`**. A verification control that reads as "the string is absent" when the file was never
  read at all. Wrap any `<rev>:<path>` in `bash -c`, and treat a `0` beside an error on the previous
  line as a NON-VERDICT. Same family as the standing zsh traps (`--include=*.sh`, unmatched globs).

  Row `5d1b5dd9b3db` stays OPEN with its remainder now precisely named — **gap 1: E10 + E14 (E6
  refuted, E8 satisfied, E9/E12/E15 landed); gap 2: F0 only, and F0 is operator-only (run migration
  0007)**. Claim released with `cc-backlog reopen`, no stale claim left. Smoke gate abstained on
  `tests/cc-await-ping.bats` (exit 124, budget cut, ZERO `not ok`) — the known non-verdict, and that
  suite was run in full by hand, green, `1..68`, before the land. Both commits `M`-only ⇒
  `LIVE_ADDS=0`: `bin/cc-inbox-guard` was extended rather than factored into a new `hooks/lib/` file,
  and the beat lib it sources was already symlinked.

- **2026-08-19 — drain recycle #47: the floor was killing the very sessions it exists to keep
  reachable, because the address it keyed on was never the one the substrate actually mints.**
  `master-fleet-footprint` **12 open / 4 blocked (4 operator-gated, `source: needs`; 0 cloud-venue,
  0 claimed, no stale claim)** — unchanged. **filed 0 / closed 0.** Landed `bf9bb8335` (F6),
  `3372ca5c6` (F7), + this entry.
  Effort choice: `date` read 2026-08-19, so `master-session-lifecycle`'s `62363cac1e39` efficacy
  re-census (due ~2026-08-24) was still shut and correctly declined for the 20th consecutive
  recycle. Property re-measured at intake and it held: 12/12 open were `venuePlan=local` AND
  `project=claude-infrastructure`. Row `5d1b5dd9b3db` claimed with no advisory, worked, and **left
  OPEN with its claim released** — F3 and F0 remain, and F3's premise is corrected below.
  - **F6 — THE SPEC SAID "PANE-LESS" AND MEANT EMPTY; THE SUBSTRATE MINTS A PERFECTLY ORDINARY
    ADDRESS.** `wake_floor()` blocks a Stop to demand an armed `cc-await-ping`. A resident
    `--input-format stream-json` agent has no turn boundary but a WRITE TO ITS STDIN, so that block
    demands a continuation the substrate cannot produce and the measured outcome is a DEATH
    (`Error: Input must be provided`). The guard that was supposed to prevent this already existed —
    `wake_floor` returns early on an empty `_ouid`, and the suite has pinned "a pane with no inbox
    identity is never blocked" for weeks. It never fired, because **gap 1 did not land the
    empty-pane fallthrough the spec prescribed**: `cc-pane-headless:124` mints `hdl-<16hex>` and
    `:197` exports it as `CC_PANE_ID`, so a headless session arrives with a NON-EMPTY address and
    sails past. This is #46's design-level law hit a second time — *the property held, the
    prescribed diff never landed and never should* — and it generalises: **a guard written against
    a value's ABSENCE is dead the moment someone supplies a legitimate value. Ask what the producer
    actually emits, never what the spec assumed it would.**
  - **THE DISCRIMINATOR IS THE WRITER'S ENV, AND THE REPO ALREADY SAID SO IN TERMS.**
    `hooks/session-register.sh:134-145` states that reading the surface off an id's SHAPE is "the
    exact mistake", because only the writer knows it. Both hooks now use that file's predicate
    verbatim (`[ -n "$CC_PANE_ID" ] && [ -z "$ITERM_SESSION_ID" ]`) rather than matching `hdl-`.
    Reusing an SSOT predicate beat re-deriving one, and no new lib file was added — `LIVE_ADDS=0`
    on both commits, proven `M`-only with `git diff --name-status <sha>~1 <sha>`.
  - **F7 — THE FILED REASON IS REFUTED AND THE ITEM SURVIVES ANYWAY.** F7 says the drain nudge
    advertises "a command that cannot run — `cc-await-ping` exits 3 headless". **It does not.**
    `bin/cc-await-ping:193` derives its uuid from `${CC_PANE_ID:-${ITERM_SESSION_ID:-}}`, landed
    2026-07-31 in `7b7a7e014` — *before the spec was written* — and `cc-pane-headless:197` exports
    exactly that variable. The command resolves fine. The item survives for a different reason:
    arming is not this session's job at all, so the advisory names no action its recipient can take.
    **Suppressed the two arm-advertising branches, kept the third** ("kill $pid, it is holding your
    goal inert" IS an action a headless agent can take). **A refuted rationale is not a refuted
    item — re-derive the reason before you drop the work, and before you do it.**
  - **WHY F7 WAS NOT OPTIONAL ONCE F6 LANDED.** `tests/wake-floor.bats` already pins that the floor
    and the drain must not disagree about the arm. Landing F6 alone would have made the floor stand
    down while the drain kept nagging for the same arm — **re-creating the pinned defect in a shape
    the pin could not see**, since it compares command TEXT, not whether to advise at all. *When you
    silence one of two advisories a test pins as agreeing, check whether the pin can see your axis.*
  - **F3 IS REFUTED — `v_send` HAS ZERO CALLERS, AND ITS STATED PURPOSE WAS ALREADY ACHIEVED.**
    F3 wants `cc-pane-headless`'s `send` verb routed through `cc-notify`, "what joins the two
    disjoint substrates". Measured: the verb's only non-doc references are its own file, its own
    suite, and the spec — **nobody calls it, and nobody reads `$dir/inbox`** (the other `inbox` hits
    are agent-teams' unrelated `$team_dir/inboxes/*.json`). Meanwhile #46's `8d38fec34` already made
    `cc-notify` reach a headless session, so **the substrates are joined and F3's rationale is
    stale.** Worse, its prescribed remedy is HAZARDOUS for the population: `cc-pane-headless` execs
    ARBITRARY argv, most of which is not a Claude session, has no registry row and cannot drain —
    and `cc-notify` on a row-less address returns UNKNOWN rather than inventing one (pinned by
    `tests/headless-address-consumers.bats:13`). Routing unconditionally would break the majority
    case to serve a caller that does not exist. **Left unbuilt deliberately; the correction is the
    deliverable.**
  - **RED-PROOF, STATED HONESTLY.** 10 new cases, 14 mutants, **14/14 MATCH**, plan line asserted on
    every run, no `# skip`, tree `diff -q`-verified restored. **7 of the 10 are red pre-fix**; the
    other 3 assert a PRESERVATION (a pane session still blocks / still gets the nudge) and are green
    pre-fix by construction — their guarantee is carried by named mutants (M3, M12), not by
    red-proof. One case replays the pre-fix hook from a **pinned** sha (`3b11e115`), never a moving
    ref — the defect that file's own header documents.
  - **TWO MUTANTS CAME BACK GREEN AND BOTH WERE PREDICTED NO-OPS (M2, M11).** Dropping the
    `CC_PANE_ID` conjunct from either predicate changes nothing, because an empty address already
    short-circuits upstream in both hooks. **That conjunct is DEFENSIVE, not load-bearing** — it is
    there to mirror `session-register.sh`'s expression exactly. Recorded rather than dressed up as
    coverage: a green mutant whose no-op you predicted is evidence about the code, but it credits no
    case.
  - **CARRIED FINDING, recorded not filed (conservation).** `tests/mailbox-drain.bats` case 47
    (`E2 RED-PROOF: the pre-fix drain from origin/main…`) has **silently degraded to a permanent
    `# skip`** — `control is not pre-fix`. Its control is `origin/main`, a MOVING ref, so it became
    a no-op the moment E2 landed. This is precisely the defect `tests/wake-floor.bats`'s header
    documents and fixed by pinning to an immutable sha, in the sibling suite, unfixed. **It renders
    as `ok` in every run.** Predates this diff and is not this session's loose end; the fix is one
    pinned sha, and the next recycle should take it. *A red-proof pinned to a moving ref does not
    fail when it expires — it skips, and a skip reads as a pass.*
  - Instruments: both lands' smoke gates ABSTAINED under budget (exit 124, zero `not ok`) on suites
    that are **not mine** — `tests/install-wire-hooks.bats`, then a budget exhaustion. Own suites run
    green by hand with their plan lines seen: `wake-floor 1..49`, `mailbox-drain 1..53`,
    `headless-address-consumers 1..13`. `bats-shellcheck-lint` read **0 changed .bats lines before
    each commit and 84 / 57 after** — the commit-range blindness, hit twice more.

- **2026-08-19 — drain recycle #46: the remedy was BUILT, TESTED and reachable from nothing — and the
  one field needed to reach it collapsed the column beside it.** `master-fleet-footprint`
  **12 open / 4 blocked (4 operator-gated, `source: needs`; 0 cloud-venue, 0 claimed, no stale
  claim)** — unchanged. **filed 0 / closed 0.** Landed `8d38fec34` (+ this entry).
  Effort choice: `date` read 2026-08-19, so `master-session-lifecycle`'s `62363cac1e39` efficacy
  re-census (due ~2026-08-24) was still shut and correctly declined for the 19th consecutive recycle.
  Property re-measured at intake and it held: 12/12 open were `venuePlan=local` AND
  `project=claude-infrastructure`. Row `5d1b5dd9b3db` (headless substrate) claimed with no advisory,
  worked, and **left OPEN with its claim released** — this pass built E7/F5 only.
  - **THE BRIEF'S REMAINDER WAS STALE, measured first.** It said "ALL of gap 2 (F1-F7)" remains.
    **F1, F2 and F4 are already built** — landed 2026-08-13 under backlog `8ad4b02602dc`, outside
    this chain: `bin/cc-pane-headless` spawns on a `mkfifo` stdin with a holder process (the header
    at `:27-36` documents why `</dev/null` was the whole of the bug), `meta` publishes
    `fifo=`/`holder=`/`sid=`, and **`bin/cc-wake-headless` exists complete with
    `tests/cc-wake-headless.bats` (1..11 green)**. Still unbuilt: **F3** (`v_send` still appends to
    `$dir/inbox`, a private file no fleet reader knows), **F6** (`wake_floor()` must abstain for a
    pane-less session), **F7**.
  - **THE PATTERN THIS RECYCLE HIT — a remedy fully built and structurally unreachable.** The fleet's
    ONLY wake primitive for a pane-less session had, on the whole tree, **zero callers**: its only
    non-doc references were its own source, its own suite, and two PROSE comments in
    `bin/cc-pane-headless`. So mail to a headless session enqueued and sat there while `cc-notify`
    told the sender it "drains on its NEXT turn" — false for a resident `--input-format stream-json`
    agent, whose only turn boundary is a write to its stdin (spec §2.2). The discriminator was
    already on disk too: `hooks/session-register.sh:134-145` writes `surface:"pane"|"headless"` into
    every row and calls it *"a fact only the writer knows"*, and `bin/cc-sessions:275` consumes it —
    but all six of `cc-notify`'s `surface` matches were the English word. **This is #43's shape one
    turn further on: not "the check already exists and reaches nobody" but "the ACTUATOR already
    exists and is called by nobody".** Ask of a row that says *build X*: is X already built, and is
    the real defect that nothing invokes it?
  - **THE COUPLING THE SPEC'S OWN E7 DID NOT NAME — and it would have paged the operator.** E7
    prescribes a new `reason=` token *"→ `verdict delivered reason=no-watcher-headless`"* as though
    the reason token were the contract between the tools. It is not. **`bin/cc-announce:145-149`
    classifies this line by grepping the LITERAL substrings `NO watcher armed` and `wake-path armed`
    out of cc-notify's HUMAN sentence, and its final arm is fail-CLOSED** — *"an unrecognized rc-0
    string alarms, never VERIFIED"*. Writing a clean new headless sentence without the matching
    phrase therefore does not lose a nuance; it sends **every headless announce to
    `VERDICT=UNKNOWN`** and alarms. Both phrases are retained deliberately, with the reason recorded
    at both ends and two cases pinning them. **Generalisation: before changing an operator-facing
    string, grep for who GREPS it — a human sentence can be a wire protocol, and a fail-closed
    consumer converts a cosmetic edit into a page.**
  - **A LATENT DEFECT THIS CHANGE ACTIVATED, then fixed — and it is the one worth carrying.**
    `REG_ROWS` is TAB-separated and read with `IFS=<tab>`. **Tab is an IFS *whitespace* character, so
    `read` COLLAPSES RUNS OF IT.** A row whose `lstart` is empty emitted
    `<name>\t<pid>\t<uuid>\t\t<surface>` and bound `lst="<surface>"` — every column after the empty
    one shifted LEFT by one. `pid_live()` then compared a live process's start time against the
    literal `pane`, no row matched, and **EVERY peer — pane and headless alike — resolved as
    `reason=target-not-live`.** Measured by A/B against a pristine `origin/main` worktree; **5 of 15
    live registry rows carry no `lstart`**, so this was the common shape, not an edge case. Fixed by
    emitting a `-` sentinel for every column so the collapse has nothing to collapse (`pid_live()`
    maps `-` back to "unknown"), which also makes a future column safe to append. The latent half
    predates this change: an empty LEADING field is stripped the same way.
    **Carry this: appending a TSV column is only safe while every earlier column is guaranteed
    non-empty. A trailing-empty column is fine; an interior one silently shifts everything after it.**
  - **AND THE INSTRUMENT LESSON: the block census could not have caught it, by construction.**
    `tests/cc-notify.bats`'s "registry TSV" case is a SOURCE-TEXT census — it greps `bin/cc-notify`
    for reader/producer shapes. The collapse is a RUNTIME BINDING, invisible to any grep. The census
    is extended to the new column and to a no-empty-column rule, but the real guarantee is a new
    BEHAVIOURAL case asserting the verdict for a row with no `lstart`. **A source census and a
    behavioural case are not substitutes; the census tells you the shape is right and says nothing
    about what the shell does with it.** Also: the census greps had to be anchored `^[^#]*` because
    **my own explanatory comment inside `cc-notify` matched one of them** and made it report 4
    readers where 3 exist — the match-comments law, hit from the writing side rather than the
    reading side.
  - **Red-proof, stated honestly.** 9 new cases (suite now **1..100**, no skips; siblings green —
    `cc-announce` 1..18, `completion-push` 1..8, `cc-wake-headless` 1..11, `session-registry` 1..36).
    **Only 4 of the 9 are red pre-fix** (the headless woken/refused/phrase cases); the other five
    assert PRESERVATION — pane rows untouched, an absent `surface` reading as pane, an armed watcher
    not double-fired, name resolution intact, the no-`lstart` row still live — and are green pre-fix
    by construction. Their guarantee is carried by named mutants, not by red-proof. **9 mutants, all
    9 landing exactly as predicted on the second pass; the table printed expected-vs-actual with a
    NON-VERDICT arm for a missed anchor and for a wrong plan line.** Every one of the 9 cases is red
    by ≥1 mutant (3→M1,M7,M8 · 4→+M4 · 5→+M3 · 6→+M5 · 7,8→M2,M8 · 9→M9 · 10→M6 · 11→M8).
    **Three mutants first read as MISMATCH and all three were the EXPECTATION's error, not the
    mutant's** — M2/M6/M8 also red the block census because it pins those literals in source text, so
    case 2 is coupled to them BY CONSTRUCTION; and M8 (revert the sentinel) reds 10 of 11 cases,
    which is not an over-wide mutant but **the defect's true blast radius**. Restoration proven by
    `diff -q` against the fixed copy plus a clean `git status --porcelain`.
  - **Ledger attribution.** `LIVE_LAG=24` (inside the 25 budget), `LIVE_ADDS=37` — **not mine**:
    `git diff --name-status 8d38fec34~1 8d38fec34` is `M`-only on both paths. `deploy-live.sh` still
    correctly declines. The land's smoke gate CUT `tests/cc-notify.bats` at its 120 s budget
    (exit 124, ZERO `not ok`) — the adjudicated non-verdict, not a red; the defence is that the suite
    was run here first, green, with its `1..100` seen.

- **2026-08-19 — drain recycle #45: the row's remedy was correct and its SCOPE was not — "closes
  every path that must type into an already-existing pane" is false for the busiest such path, where
  the fix is itself the hazard.** `master-fleet-footprint`
  **12 open / 4 blocked (4 operator-gated, `source: needs`; 0 cloud-venue, 0 claimed, no stale
  claim)** — down from 13. **filed 0 / closed 1.** Landed `942fb269f`.
  Effort choice: `date` read 2026-08-19, so `master-session-lifecycle`'s `62363cac1e39` efficacy
  re-census (due ~2026-08-24) was still shut and correctly declined for the 18th consecutive recycle.
  Property re-measured at intake and it held: 13/13 open were `venuePlan=local` AND
  `project=claude-infrastructure`. `e78107996dea` re-checked first, as the brief directs, and it is
  still structurally blocked — `argv0` reads null on **all 22,821** rows of the live
  `capacity-alarm.jsonl` (the file has rotated since #44's 68,091, and the field is null in every row
  of the new population too), so there is nothing to census until the converger runs.

  **The row: `d90bbcd9e01f`, CLOSED.** `bin/it2-kitty`'s `run` verb now mints a fresh nonce per
  attempt, types `: <nonce>; <line>`, reads the screen back, and sends the CR only on a match. Half 1
  (`--keep-focus`) landed in #33 as `ed7eee4c4`; half 2 is this pass. The stored falsifier — the row
  author's own done-criterion, scoped entirely to `bin/it2-kitty` — RETRACTS (rc 0) against a
  pristine `origin/main` worktree at close time, and the close was made on that plus content
  (`git diff origin/main` empty on both paths, `type_verified` present 3× in
  `git show origin/main:bin/it2-kitty`).

  **THE FINDING, and it is a scope finding rather than a mechanism one.** The row prescribes a remedy
  that "closes every path that must type into an ALREADY-EXISTING pane". That clause is FALSE, and
  the counter-example is the busiest caller: `scripts/handoff-fire.sh:as_write` routes `/exit` through
  this exact verb into a **live Claude Code composer** on the self-close and recycle paths — this
  chain's own succession mechanism. There `: <nonce>; /exit` executes nothing; it is entered as a
  CHAT MESSAGE and submitted. So the prescribed remedy is not merely useless on a TUI pane, it is
  **destructive**, and applying it as written would have broken every recycle in this chain. The
  guard is therefore gated on the oracle the row itself names — `in_alternate_screen`, tested for
  identity against False so an absent field reads as "a TUI may be up" and abstains. Re-measured at
  intake: **12 of 12 live Claude panes True, the one bare-shell pane False.** Generalisable:
  **a row can be right about the defect, right about the file, right about the oracle, and still
  wrong about the POPULATION its remedy may be applied to — and the population is the part that
  decides whether the fix is a fix.** Nearest memories: `guard-refusal-fires-on-its-own-harness`,
  `prescribed-remedy-worse-than-the-bug`.

  Carrying #44's lesson forward literally: all three of `run`'s dispositions are now **named in the
  code** — ARMED (file transport via `deliver_argv`, untouched) / TUI (abstains before any keystroke,
  today's send byte for byte) / SHELL (verified) — and the row's own central case, the teammate spawn
  typing `cd <path> && env … claude.exe …` into a fresh interactive shell, reaches the SHELL
  disposition. That check was run deliberately because #44 shipped a fix wired at a gate its row's
  central case never reached.

  **The residue has a home and it is not this row.** The "shared helper" extraction the row defers to
  is item `270106134cc8`, which is **done**. The one live raw-send pane-typing site left is
  `bin/cc-pane`'s `send` verb, owned by OPEN row `07ac6d58d88d` (`master-convergence-deadlock`) — a
  different file, a different row, and a candidate for whoever drains that effort.

  **Instrument record — 7 new cases in `tests/it2-kitty-argv-spawn.bats` (extended, not added, so
  `LIVE_ADDS=0`; both paths `M`, proven with `git diff --name-status`).** Suite `1..21`, 21 ok, 0 not
  ok, 0 skips. Against the PRE-FIX subject the 7 filtered cases run `1..7` with **3 RED**; the other
  4 assert an ABSENCE and are **green pre-fix by construction** — "abstains" is trivially true of a
  subject with no verifier — so their guarantee is carried by the boundary mutants, stated rather
  than passed off as red-proof (#44's law). 8 mutants, expected-vs-actual printed per mutant:
  c1←M5,M8 · c2←M2 · c3←M1,M2 · c4←M6 · c5←M5,M7 · c6←M3 · c7←M4.

  **TWO MUTANTS CAME BACK WRONG, WHICH IS WHY THEY WERE RUN.**
  · **M6 red the WRONG CASES (4 and 5, predicted 4).** Not a bad mutant — a real coupling: a second
    nonce only exists if attempt 1 declined to submit, so "sends the CR unconditionally" necessarily
    kills the fresh-nonce case too. **The EXPECTATION was wrong, not the mutant**, and the test now
    records the coupling. #44's rule said a wrong-case red indicts your model of the SHELL; this adds
    the other author — it can equally indict your model of your own TEST's dependencies.
  · **M8 came back GREEN and refuted my own comment.** It swaps the `grep -cF` count form back to
    `grep -q`, which the code claimed inverts under `pipefail`. Measured on this box: with the bash
    **builtin** `printf` the pipeline reads **rc 0** (no inversion), while a forked `/bin/cat` on the
    same shell reads **rc 141**. **The `grep -q`/pipefail hazard is PRODUCER-DEPENDENT**, and the
    always-quoted form of that law overstates it for a builtin producer. The count form was kept — it
    is the shape that stays correct if the producer ever becomes a fork — but the comment was
    corrected to say what was measured. Memory `grep-q-under-pipefail-inverts-the-verdict` is not
    wrong, it is **unqualified**: it needs "when the producer is a fork".

  Two assertion defects were also found **by running them**, not by reading: a `-- .?$` regex meant to
  prove "nothing was submitted" reds on the `^U` scrub too (^U is also one character), and a
  `grep -c` over a `$KLOG` that the armed path never creates exits 2 with empty output. The submit
  oracle is now a CR in the log, which is the only payload that executes a line.

  **A CORRECTION TO #44's CARRIED BRIEF — its finding (e) is REFUTED; do not spend a pass on it.**
  #44 recorded that "`damp_should_send` is never sourced in `bin/cc-reaper`, so originator-page
  damping is inert". It **is** sourced: `bin/cc-reaper:280-284` carries a three-path resolve for
  `hooks/lib/page-damp.sh` under the comment "D7 send-damping (best-effort: absent lib ⇒ undamped)".
  Measured this pass — both `bin/../hooks/lib/page-damp.sh` and `~/.claude/hooks/lib/page-damp.sh`
  are PRESENT, and sourcing the lib DEFINES the function. The `command -v` guards at :690 are a
  fail-open belt on a sourced lib, which is the same shape `context-econ.sh` and `cc-beat.sh` use two
  blocks below. So damping is **live** for both `handle_safeguard_blocked` and `handle_stranded`.
  The lesson is #44's own, turned around: **`command -v` at a call site is not evidence the lib was
  never sourced — the source block can be 400 lines away.** Grep the resolve, not the guard.

  Gates: `shellcheck -x` clean, `bats-shellcheck-lint` clean over 132 changed `.bats` lines,
  `bats-assert-liveness` clean, plus kill-guard / pipefail-sigpipe / self-path / unattended-path /
  test-hermeticity / **typed-send** lints all rc 0. The ship-land smoke gate ran **GREEN** (11 suites,
  104 s) rather than abstaining, and `land-verify` reported both paths content-identical on
  `origin/main`. `LIVE_LAG=21` / `LIVE_ADDS=37` at close are a sibling's, not this diff's.
  0 code teammates spawned, 0 `Explore` surveys — `master-fire-gate` (46 open) and
  `master-convergence-deadlock` (55 open) remain **UNSURVEYED**, and the two attempts that did not
  return in-pass (#28, #43) still stand as the reason to give any future one a hard wall-clock
  return instruction.

- **2026-08-19 — drain recycle #44: the verdict was already being computed every sweep and thrown
  away into a logfile with no reader — and the case it most needed to cover was the one my own first
  fix could not reach.** `master-fleet-footprint`
  **13 open / 4 blocked (4 operator-gated, `source: needs`; 0 cloud-venue, 0 claimed, no stale
  claim)** — down from 14. **filed 0 / closed 1.** Landed `6e106182a` + `3090a58d3`.
  Effort choice: `date` read 2026-08-19, so `master-session-lifecycle`'s `62363cac1e39` efficacy
  re-census (due ~2026-08-24) was still shut and correctly declined for the 17th consecutive recycle.
  `e78107996dea` re-checked and still structurally blocked — 68,091 `top_procs` rows in the live
  `capacity-alarm.jsonl`, **every one `argv0: null`**, so the converger still has not run.
  Property re-measured at intake and it held: 14/14 open were `venuePlan=local` AND
  `project=claude-infrastructure`.

  **CLOSED `1b19ab3096d2`** (handoff succession contract unenforced on the durability leg) after
  building the leg #43 left. Both of the row's enumerated "Needs:" are now on trunk and were
  content-verified at the moment of the close.

  *The finding.* This is #43's lesson one layer down. #43 found a prescribed check that existed twice
  and reached nobody. Here the check existed **once, in the right place, computing exactly the right
  thing** — `landed != yes` on a REAPABLE cause is precisely "this session is done and its work is not
  on trunk" — and its entire disposition was `say` (the stdout of a launchd job) + `log` + `continue`.
  A grep for a consumer of that log line returns `bin/cc-reaper` itself. **The reaper is the last actor
  that can still see the branch of a session which never ran a close path, and it was writing the
  answer to itself.** `handle_stranded()` re-derives the evidence at act time — both halves the row
  names, `rev-list --count TRUNK..HEAD` AND tracked dirt — and routes it to the ORIGINATOR, the party
  holding the false "complete" belief. Deliberately *not* `handle_surface`: that page is desk-only and
  its remedy list ("re-engage a hang · close a crashed pane · confirm-close a shared-review") contains
  nothing resembling "land the branch". `handle_safeguard_blocked` is the precedent and the shape.

  *🚨 The sharper half, and the one worth carrying: **checking hardest before closing my own row is
  what found the hole in my own fix.*** The first commit wired the page at the landed gate — which only
  `REAPABLE_RE` causes ever reach. **`crashed` is in `SURFACE_PAGE_RE`, not `REAPABLE_RE`**, so it
  takes the surface path and never reaches that gate at all. A crash is the canonical *"no close path
  ever ran"* — the row's **central** case — and it would have stayed dark behind a green suite, a green
  land, and a commit message claiming the leg was built. `3090a58d3` adds `STRANDED_SURFACE_RE`,
  deliberately narrow: `crashed` in; `coordination-hang` OUT (that session is LIVE and stuck, and a
  working session normally *has* unlanded work — firing there is the always-firing alarm);
  `finished-*`/`task-less` OUT (operator-owned, already paged, human owns the disposition).
  **Generalisable: a fix wired at ONE gate covers only the causes that reach THAT gate — enumerate the
  dispositions your subject actually has before believing a call site is coverage.**

  *Polarity, both directions.* (a) PRESENCE — the page acts on a NEGATIVE, so with 0 unlanded commits
  and no tracked dirt it says nothing at all rather than paging on absence. (b) A LAND IS NOT A STRAND
  — `STRANDED_S` defaults to 1800 s, sized against what it must not convict: a `ship-land` run takes
  ~4-6 min and is bounded at `timeout 900`, so any threshold at or under ~15 min pages every session
  that is merely *landing*. The DEFER itself is untouched — nothing is destroyed; the refusal just
  reaches someone now.

  *Instrument corrections — two of my own mutants were wrong, and this is the transferable part.*
  **M2 came back GREEN**: its anchor edited the dirty-clause, not the branch, which lives earlier in
  the same string. **M11 came back red on the WRONG case**: `: [[ … ]] && cmd` makes `[[` an
  **argument to the `:` builtin**, so `:` returns 0 and the `&&` call runs **unconditionally** — it had
  silently inverted from a *remove* mutant into a *widen* mutant. Both re-aimed. Same law, and it is
  #43's extended one more turn: **a green mutant indicts your model of the code, and a red one on the
  wrong case indicts your model of the shell.** Verify what a mutant DID; never reason about it.
  Also paid: `declare -A` does not exist on this box (macOS ships **bash 3.2**) — the driver uses a
  `case` function instead.

  *Evidence.* 12 red-proof cases (`W-STRANDED-1..12`); 10/12 red against the pre-fix subject, the two
  exceptions being the ones that assert an **absence** (case 5 presence-guard, case 12 exclusion) which
  are green pre-fix *by construction* — **their guarantees are carried by mutants, not by red-proof,
  and saying so is part of the proof**. Case 5 was rewritten mid-pass for exactly this reason: as first
  written it asserted only "pages nobody", which is trivially true of a subject with no pager, so it now
  also asserts the guard RAN and DECLINED. 12 mutants, one per case, every one matching its predicted
  red-case set with `1..12` printed on every run. `tests/cc-reaper.bats` **1..135, 135 ok, 0 not ok, 0
  skips** run directly — the land's smoke gate cut this very suite at its 120 s budget (exit 124, zero
  `not ok`) **twice**, so that non-verdict was converted into a verdict rather than inherited. Six
  adjacent suites green (reap-guard 19 · reap-sweep-bounds 11 · reap-freshness 10 ·
  teammate-reap-alarm 21 · cc-blockers-teammate-reap 9 · desk-invariant 24 = 94). Both commits are
  `M`/`M` — **zero adds**, so `LIVE_ADDS` is untouched by this diff.

  *Recorded, not filed (conservation — closed 1, filed 0).* (i) A worktree whose session is absent
  from the registry **entirely** is never enumerated by `cc-classify`, so no sweep-driven page can
  reach it — but `ship-land.sh`'s stranded-sweep already enumerates `refs/heads/` independently of
  sessions, so the population has coverage from a different actor. A different mechanism, not this
  row's. (ii) **`damp_should_send` is never sourced in `cc-reaper`** — it is only ever
  `command -v`-guarded — so originator-page damping is inert today for the **pre-existing
  `handle_safeguard_blocked` path** as well as this one. This is why no behavioural damping case was
  written: it would have been vacuous. The fingerprint's freedom from volatile counts is pinned from
  the shipped script instead (case 10).

- **2026-08-19 — drain recycle #43: the row asked for a durability check to be BUILT, and it already
  existed twice — neither copy reached anyone who could act on it, while the one message the lead
  *does* receive told it the work was safe.** `master-fleet-footprint`
  **14 open / 4 blocked (4 operator-gated, `source: needs`; 0 cloud-venue, 0 claimed, no stale
  claim)**. Property re-measured at intake and it held: 15/15 open were `venuePlan=local` AND
  `project=claude-infrastructure`. **filed 0 / closed 1.** Landed `4a455e43b`.
  Session-lifecycle row `62363cac1e39` correctly declined again — `date` read **2026-08-19**, its
  efficacy re-census window opens ~2026-08-24.
  - **Row `1b19ab3096d2` — BUILT and left OPEN.** It asked for (1) the fired-session brief to state
    land-BEFORE-ping-BEFORE-close and (2) a lead-side reaper checking `rev-list origin/main..HEAD`
    for every fired worktree, "since 'pinged' != 'work is safe'". Leg 2's remedy is **REDIRECTED**:
    the prescribed check already exists in TWO places and neither delivers.
    - `bin/cc-reaper` `work_landed()` runs exactly the prescribed predicate. Its "not landed"
      disposition is `say` + `log` + `continue` — the reaper's own stdout and its own logfile. The
      surface-PAGE path sits in the branch ABOVE it, reached only for `SURFACE_PAGE_RE` causes, so a
      *reapable* cause with unlanded work falls through to a bare `continue`. Nothing pages.
    - `scripts/handoff-fire.sh`'s self-close preflight (CLOSE_INTEGRITY W2) computes the count
      itself and emits `⚠ self-close: N commit(s) … are NOT landed`. **`_sc_ahead` had exactly two
      uses in ~9,900 lines, both inside the block that computed it**, and it is written to the
      stderr of a pane that is about to evaporate. The warning's own comment says *"it names the
      branch so the ping can carry it"* — nothing carried it.
  - 🚨 **THE HALF THAT WAS NOT IN THE ROW AT ALL, AND IS THE LOAD-BEARING ONE: the announce the
    originator DOES receive asserted "Its work is committed (self-close refuses a dirty tree)".**
    A true sentence about the wrong store, arriving at the exact moment a peer retires with unlanded
    commits. That is how the measured incident read as a completed track — bs-footer-motion pinged
    completion twice, self-closed cleanly, left 2 commits stranded, and only an operator screenshot
    surfaced it. The trailer carried the SAME false equivalence to the other party, naming
    "committed/clean" as the bar a retiring peer must meet. **One wrong idea — *committed = safe* —
    was installed on both ends of the same handshake.** Both are fixed; the clause now rides every
    announce path, and the unlanded fact overrides the ping verdict, because the peer's self-report
    is precisely the channel that failed while `rev-list` is a measurement rather than a report.
    Polarity preserved by the count itself: 0 ahead sends nothing, so an ordinary landed close is
    exactly as quiet as before. Strictly additive — params 4-6 default to 0/empty, pinned by its own
    legacy-3-argument case. **Row stays OPEN**: the lead-side sweep over worktrees whose session is
    already gone — the case where no close path runs at all — remains unbuilt.
  - **Row `f9b5ce0c5d17` (task-store prune) — CLOSED on same-moment re-derivation, not on its own
    text.** Amortised over 20 iterations with a null control (2.247 ms): **37.3 µs/dir over 2414
    real dirs, threshold 26,796 dirs to cost 1s — 11× headroom**, independently reproducing the
    row's own 36 µs / ~28,000. Cited fix `8d642bca9` adjudicated **by CONTENT** (`--is-ancestor`
    returns rc≠0 — the rebased-land case, not absence): on trunk `find_active_list` holds two `jq`
    occurrences, one real call made ONCE before the loop and one in a comment, with both
    per-directory loops pure-bash globs. **The "without this the fix decays again" half needed a
    different instrument** — decay requires monotonic growth, and the count *decreased* across three
    readings (2428 at filing → 2392 at #42 → 2414 now), which proves removal is happening. Limit
    stated in the evidence rather than papered over: **the specific reaper was NOT identified**, and
    the mtime floor (2026-07; none older) is consistent with removal but cannot prove it, since
    mtime records last touch and not creation — the decreasing COUNT is what carries the claim.
    Not filed as an operator step: with the urgency premise refuted, putting a destructive action
    with no measured benefit on the platter is worse than closing.
  - 🚨 **RECIPE — A MUTANT THAT LEAVES THE SUITE GREEN INDICTS YOUR STATED RATIONALE, NOT ONLY YOUR
    COVERAGE (extends #40).** 8 mutants for 9 cases; 7 matched their predicted case set on the first
    run and **M5 red nothing**. The mutant had applied (the anchor assert would have failed loudly).
    The real cause was that the case's *comment* claimed an unsanitised `[ "$x" -gt 0 ]` on junk
    "aborts under set -euo pipefail" — **it does not**: `[` returns rc 2 and a condition inside `if`
    is errexit-EXEMPT, verified by direct probe rather than reasoned about. The case pinned a real
    property but by a mechanism that did not exist, so nothing in the subject could break it. Fixed
    by re-aiming the mutant at what the line actually guarantees — the sanitiser's **direction**
    (junk must fail toward *make no claim*, never toward *assert this peer stranded work*) — and by
    correcting the comment. **A green mutant is a question about your model of the code; a plausible
    rationale in a test comment is as capable of being wrong as the code, and nothing else checks
    it.** Second run: **8/8 MATCH, every one of the 9 cases credited to a site.**
  - 🚨 **RECIPE — WHEN YOUR FIX IS "ROUTE A FACT TO ITS CONSUMER", WRITE THE WIRING CASE FIRST.** The
    defect here was never a wrong measurement; it was a correct measurement delivered to nobody. A
    correct function called with three arguments would have been the identical bug wearing a new
    shape, and every behavioural case would still have passed. Two cases therefore read the
    **shipped script** rather than the sed-extracted function, and assert the capture site precedes
    the announce site by line number — otherwise the call reads the pre-seeded zero forever.
    Memories: `conclusion-must-reach-the-enforcing-store`, `spec-named-mechanism-may-be-prose-only`.
  - Gates all green (shellcheck rc 0, bats-shellcheck-lint clean at **138 changed `.bats` lines**
    post-commit, kill-guard / pipefail-sigpipe / self-path / unattended-path / hermeticity /
    typed-send / assert-liveness all clean). Suites run this pass: **30/30 announce-before-retire ·
    98/98 self-close batch · 134/134 fire+payload+notify batch · 24/24 desk-invariant**, every plan
    line seen, no skips. The land's smoke gate cut `desk-invariant.bats` (exit 124, zero `not ok`) —
    the known non-verdict; **run directly afterwards and green at 24/24**, so it was a budget cut and
    not evidence about the tree. `LIVE_ADDS=0` from this diff by construction — both files were
    already tracked and symlinked.

- **2026-08-19 — drain recycle #42: the row named the wrong mechanism, and the RIGHT one had been
  predicted on trunk for nine days with nothing built to see it — so a stranded lock had silently
  disabled every git maintenance run on the box for a week.** `master-fleet-footprint`
  **15 open / 4 blocked (4 operator-gated, `source: needs`; 0 cloud-venue, 0 claimed, no stale
  claim)**. Property re-measured at intake and it held: 16/16 open were `venuePlan=local` AND
  `project=claude-infrastructure`. **filed 0 / closed 1.** Landed `ccfe342ba`.
  - **The row (`ad18a72e2be5`) had two premises and BOTH were false.** (1) "gc.auto threshold
    crossing within hours" — refuted, *and already refuted on trunk by name since 2026-08-10*:
    `docs/research/memory-econ-rearchitecture-2026-08-10/git-maint.md` §7 measured that git's
    `too_many_loose_objects()` never compares anything to 6,700 — it counts entries in `objects/17`
    ONLY, firing above `gc.auto/256` = 27. Measured 2026-08-19: `objects/17` held **62**, so the
    threshold was not "hours away", it had been continuously TRUE for a week while auto-gc fired on
    every commit across 88 worktrees and achieved nothing. (2) ".claude.json 171KB no-lockfile
    rewrites — single-owner/lock design" — refuted as work this repo can do: `~/.claude.json` is
    **129,406 bytes** (the cited 171KB is stale, and low), there is no lockfile and no tmp file
    because claude.exe writes in place, and a `git grep` over `bin/ scripts/ hooks/` finds **ZERO**
    lines in this tree that redirect into it. We are not a writer, so we cannot be made its single
    owner. Vendor-gated, named as an excluded stratum rather than dropped.
  - **The real mechanism was `<objectdir>/maintenance.lock` — no TTL, no observability, one
    instance shared by every worktree.** git-maint.md §8 named it the shared store's single point of
    failure and §9 filed the reaper as **"L2 — missing, this is the real gap"**. It had since
    HAPPENED and nothing could see it: the lock was stranded from **2026-08-12 13:18** — age 9,636
    min = **6.7 days** — with no holder (`lsof` clean), no `gc.pid`, no `gc.log`, and no gc running.
    Every `git maintenance run --auto` on the machine had been a silent no-op for a week. The
    failure is silent BY CONSTRUCTION: git's `warning: lock file … exists, skipping maintenance`
    goes to a closed fd under launchd, the exit code stays 0, and no alarm exists.
  - 🚨 **THE GENERALISABLE LESSON, and it is not about git: A PREDICTED FAILURE WITH NO DETECTOR IS
    AN UNDETECTED FAILURE.** Two landed research docs named this exact mode, gave it a name, gave it
    a file path, measured its cost at another repo (reso: 5.5 days undetected → 11,660 loose
    objects, +1.1 GB) and filed the remedy as a numbered gap — and then it happened here anyway,
    ran for seven days, and was found only because a drain pass re-derived a row's premise from
    scratch. Prose in `docs/research/` ADVISES; only a script on a schedule OBSERVES. When an
    analysis ends in "L2 — missing", the analysis is not finished, it is a work item with no
    owner. (Memory: `conclusion-must-reach-the-enforcing-store`,
    `spec-named-mechanism-may-be-prose-only`.)
  - 🚨 **AND THE INSTRUMENT LESSON: EVERY PASSIVE SIGNAL SAID HEALTHY.** `gc.auto` unset (correct),
    `gc.autoDetach` unset (correct), no `gc.log` (looks like no failures — it is actually git's
    `gc.logExpiry` deleting it after a day), no `gc.pid`, no `*.lock` at `.git/` top level, 6 packs
    under the 50-pack limit, `prune-packable: 0`, `garbage: 0`. **Four separate "is anything wrong"
    probes returned clean over a subsystem that had been dead for a week.** The one signal that
    discriminated was an mtime histogram: loose objects spanned only 2026-08-12 → 2026-08-19 with
    **nothing older**, which is not what accumulation looks like — it is what a store looks like
    when everything before a specific instant was packed and nothing since has been. Dating the
    floor of a population is what named the instant; the config never could.
    🚨 And the first path I checked was the WRONG one: `.git/maintenance.lock` is ABSENT — the lock
    git actually uses is `.git/objects/maintenance.lock`. A miss at the wrong path reads exactly
    like health (memory: `lookup-miss-is-not-absence`).
  - **Built + landed:** `scripts/worktree-gc.sh` section 4 — detect and reap, fail-closed. The
    oracle is the lock's **own open fd** (`hold_lock_file_for_update` holds it for the whole run),
    never its age, because a long live repack is exactly as old as a strand (memory:
    `liveness-proxy-cannot-be-output-age`); `CC_WTGC_MAINT_LOCK_MIN` (default 60 m) is a SECOND
    gate; an `lsof` that cannot answer its own positive control makes the holder **UNPROVABLE ⇒
    KEEP**, the same rule gate 4 applies. Reported on the machine `counts` line as
    `maint_lock` / `maint_lock_age_min` / `loose_objects` — safe to append because
    `worktree-gc-infra-run.sh:505` reads that line by NAMED field, which is exactly why the line
    exists; the human summary line, whose reader is positional, is untouched. Scheduled by the
    already-loaded `com.claude.worktree-gc-infra` at 04:15 daily, so a future strand is bounded at
    ~24 h instead of unbounded. Chosen host BECAUSE it is already live-symlinked ⇒ `LIVE_ADDS=0`.
  - **Proof it was the cause, not a plausible story — same-moment, on the real artifact.** The
    shipped gate classified the live lock `maint_lock=would-reap age=9623m` under `--dry-run`; the
    real run reported `maint_lock=reaped` with `removed=0 kept=89` (idle floor raised via
    `CC_WTGC_IDLE_MIN` so the reap was the ONLY action and no worktree was touched). Auto-maintenance
    then recovered **by itself**, within minutes:

    | | before reap | after |
    |---|---|---|
    | loose objects | 15,233 | **7** |
    | loose size | 154 MiB | **32 KiB** |
    | packs | 6 | 2 |
    | commit-graph chain | 2026-08-12 06:37 | **2026-08-19 05:55** |

    Red-proof: **7/7 RED** against the pre-fix subject from HEAD (`1..7` seen, no skips), 107/107
    green post-fix, `worktree-gc-infra.bats` 53/53. Six mutants, each isolating exactly its
    predicted case set: M1 reap-no-op {1} · M2 holder test disarmed {2} · M3 age floor deleted {3,7}
    · M4 dry-run made to act {4} · M5 blind probe certifies absence {5} · M6 absent default flipped
    {6}. Restoration verified byte-identical after the series.
  - 🚨 **RECORDED, NOT FILED (conservation — closed 1, filed 0): reso is still uncovered, and it is
    the repo that already had this failure.** `gl.reso.worktree-gc` runs a DIFFERENT script
    (`~/.reso/worktree-gc-run.sh`), not this janitor, so reso inherits nothing from this fix. Checked
    same-moment and clean today: reso-management-app, personal, finance-ai-web-app, doc_classifier
    all have no stranded lock. The durable point for whoever works reso: the reaper is ~40 lines and
    the seam is `CC_WTGC_REPO`.
  - 🚨 **A note for the next pass on the classifier wall:** the auto-mode classifier DENIED both a
    bare `rm -f <the lock>` and the first janitor run. The brief's standing advice held — it is
    transient, and the identical command succeeded on retry. The better move was the one the denial
    pushed toward anyway: let the TOOL be the actuator rather than hand-removing the file
    (memory: `make-the-actuator-the-arbiter`).

- **2026-08-19 — drain recycle #41: both rows were blocked on a question already answerable — one
  from disk, one by running the thing for ninety seconds — and both measurements REMOVED work
  rather than adding it.** `master-fleet-footprint` **16 open / 4 blocked (4 operator-gated,
  `source: needs`; 0 cloud-venue, 0 claimed, no stale claim)**. Property re-measured at intake:
  17/17 open were `venuePlan=local` AND `project=claude-infrastructure`. **filed 0 / closed 1.**
  Landed `c88d31f18` (R-7 answered) + `7c10fb998` (E11 resolved) + this entry. Date checked first:
  2026-08-19, so `62363cac1e39` (due ~2026-08-24) was correctly still not drainable — **it is now
  ~5 days out and is the next recycle's best pick if the date has passed.**
  - **`f6cc5c79885b` (R-7) — CLOSED. The census it said did not exist was always derivable, and the
    build it was going to justify is refuted by the number it would have produced.** #38 argued a
    live-settings PostToolUse match-all counter was the only route to a fleet figure; #39 killed the
    "structurally absent population" that justified it. Re-derived directly: **352,926 tool calls
    over 6,997 files / 9.46 GB**, four stores deduped by realpath. Windowed to
    `bash-execution.log`'s own span so numerator and denominator share one window — the span
    mismatch R-7 itself names — **28,400 all-tool / 20,778 Bash / 7,622 non-Bash (26.84%),
    ALL/Bash = 1.3668x**, cross-validated against that independent instrument at **98.6%**, with
    **234 of 234** log sessions carrying a transcript. Full record: `HOOK_CHAIN_COST.md` §5.3.
  - 🚨 **DEDUPE IS LOAD-BEARING, AND ENUMERATING THE FOUR ROOTS IS NOT ENOUGH.** 368,278 raw
    occurrences against **353,270 distinct** tool_use ids — 15,008 redundant (4.08%) — and **6,118
    of the 6,912 repeated ids appear in more than one STORE**: the same session `.jsonl` exists
    under two account roots, because the transplant path (limit-recover) writes a session into a
    second account. A four-store census that does not dedupe on the `toolu_` id over-counts ~4%,
    and a session count taken per-root double-counts every transplanted session. This is the direct
    successor to #39's root-enumeration lesson: the roots were necessary, not sufficient.
  - 🚨 **THE BIGGEST MATCH-ALL HOOK HAD NEVER BEEN PRICED, AND THE THREE ARE ALREADY MATCH-ALL.**
    In `settings.json`, `teammate-checkpoint.sh`, `cc-permission-beacon.sh clear` and
    `mailbox-drain.sh post-tool` all carry `matcher: ""` — only `log-bash` and `waiting-recycle` are
    `Bash`-scoped. So §2.3's "PostToolUse/Bash — 4 hooks" priced them *on a Bash call* and their
    firing on the other 26.84% of tool calls was in no total. Measured per-call (abstain path, 40
    iterations, load ~15, null control `/usr/bin/true` = 2.65 ms): teammate-checkpoint **18.90 ms**
    (63% below §2.3's 51.57 — M3 landed and works, measured independently of the commit claiming
    it), cc-permission-beacon **14.78 ms** against §2.3's published **14.76** — Δ 0.02 ms, which is
    the **positive control on the timing method** — and **mailbox-drain 72.58 ms, never measured
    anywhere, 68.3% of the 106.26 ms chain.** The largest term was the unmeasured one.
  - **The decision that closes it:** per-hour cost is **0.147% of the 10-core box at the mean**,
    0.360% at p95; the part a Bash-only census structurally cannot see is **0.0395%**. So the
    counter is **rejected**, not merely unnecessary — it would report four hundredths of one
    percent, and being itself a match-all hook it would fire on all ~498 calls/h and cost the same
    order as the term it reports. Residue named: all per-call figures are the **abstain** path.
  - **`5d1b5dd9b3db` — E11/Q1 SETTLED BY RUNNING ONE; row LEFT OPEN, claim RELEASED.** The spec
    said resolve by measurement, never by guess, and nobody had. Two headless sessions were run on
    the running 2.1.220 binary, each with no controlling terminal (`ps -o tty=` → `??`): a resident
    `-p --input-format stream-json` with stdin held on a FIFO (pid 56890), and a plain one-shot
    `-p` (pid 4459). **Both got a session file, keyed on pid exactly as `sessions_file_for`
    expects, and both read `kind:"interactive"` with `entrypoint:"sdk-cli"`.** So
    `cc-reconcile`'s `[ "$kind" = "interactive" ]` **already admits a headless session** — E11 had
    nothing to accept and is struck from the diff. **The discriminator is `entrypoint`, not
    `kind`**, which does not vary with headlessness at all.
  - 🚨 **A POPULATION WITH NO MEMBER OF THE CLASS CANNOT REPORT WHAT THAT CLASS WOULD GET.** The
    spec's 9 live rows all read `interactive` — re-measured here, **14 rows across 4 distinct
    `sessions/` dirs, still all `interactive`** — and that sample was consistent with *every*
    hypothesis, because every live session is an interactive pane. Only running one could
    discriminate. Row stays OPEN: gap 1 (E1-E15 minus E11), gap 2 (F1-F7), and E7's rc-3
    `no-watcher-headless` verdict all remain, and **Q2 — does `asyncRewake` synthesise a turn under
    `stream-json` — is now the question actually gating gap 2.**
  - **Two candidates checked and REFUTED, so #42 need not re-derive them.** (i) `d4fa449e3895` was
    flagged by #40 as the most plausible untested close; it is **genuinely open**. Its falsifier
    exits 1 (a real verdict, not blindness — instrument and plan both present). Every section reads
    PENDING, which looks like a blind classifier, but the vocabulary hypothesis is refuted: only
    **4 files / 6 headings** fleet-wide use `IMPLEMENTED`/`RESOLVED`/`LANDED` against 27 with a
    bounded `DONE`, and the plan carries explicit "Residue — named, not absorbed" sections plus a
    `⛔ NOT LIVE` one, so a perfect classifier would still exit 1. (ii) `e78107996dea` is **not
    closeable yet and the reason is structural**: #40's `argv0` field reads **0/3 on every row** of
    `capacity-alarm.jsonl` because the live copy symlinks into the shared checkout, which is behind
    (`LIVE_LAG=5`, `LIVE_ADDS=0` — within budget). **The instrument cannot accumulate until the
    converger runs**, so that row's close path is gated on convergence, not on more analysis.
  - **Recorded here rather than filed (conservation).** The E11 land's stranded-sweep returned
    **NO VERDICT** on `docs/gc-cpu-vs-session-ceiling` (`git cherry` exit 128, unknown commit) under
    a headline attributing it to this session. Diagnosed, not assumed: the ref resolves **nowhere**
    — not locally, not on origin, not in the shared checkout — and the head count fell **1,813 →
    1,796 within minutes**, so a sibling deleted the branch between the sweep's `for-each-ref`
    enumeration and its `git cherry`. A benign TOCTOU under 14 concurrent sessions, and the sweep
    reports it honestly as an abstain rather than a false clean. `--mine` confirmed **0
    own-session drops**. No row: the instrument behaved correctly.

- **2026-08-19 — drain recycle #40: the fleet's 150 multi-GB `claude.exe` events were the binary's
  own embedded grep, and the instrument that named them is the only one of three that cannot say so.**
  `master-fleet-footprint` **17 open / 4 blocked (4 operator-gated, `source: needs`; 0 cloud-venue,
  0 claimed, no stale claim)**. Property re-measured at intake: 17/17 open are `venuePlan=local` AND
  `project=claude-infrastructure`. **filed 0 / closed 0.** Landed `fcb354d37` (argv[0] on every
  footprint row) + this entry. `e78107996dea` worked and **left OPEN, claim released** — remainder
  named below. Date checked first: 2026-08-19, so `62363cac1e39` (due ~2026-08-24) was correctly not
  yet drainable.
  - **The row's subject is a labelling artifact, and the artifact is structural.** `e78107996dea`
    reads "identify the claude.exe 4-40GB self-burst trigger". Re-derived from the live log: **150
    events at ≥4 GB across 20 days**, latest 2026-08-18 — the phenomenon is real and current. But
    `top -stats pid,mem,command`, which `read_top_procs` reads, reports **p_comm, derived from the
    executable image**. Claude Code reaches its embedded ugrep/bfs by re-exec-ing *its own binary*
    with argv[0] rewritten — `ARGV0=ugrep "$CLAUDE_CODE_EXECPATH" …` / `exec -a ugrep …`, from the
    shell snapshot that shadows `grep`/`find`. So an embedded search **is** the claude.exe image, and
    the rung filed it as a session. Caught live on one process, same pid and same moment (pid 71388):
    `top` → `claude.exe`, `ps -o comm=` → `ugrep`, `ps -o command=` argv[0] → `ugrep`. **Darwin
    resolves both ps columns through argv[0], so top(1) is the only blind one of the three** — the
    ps-rss fallback this rung also carries was never the bug.
  - **The historic corroboration is a same-pid, same-minute contradiction between two live stores.**
    `ugrep` appears **0 times in 22,575 rows** of `capacity-alarm.jsonl`. `compressor-sentinel-snap.log`,
    which reads argv, watched pid 15222 climb **6.8 → 12.2 GB as `ugrep`** at `2026-08-10T07:09:07Z`;
    `capacity-alarm.jsonl` logged **that same pid in that same minute as `claude.exe` at 16 GB**. One
    process, two names, and the rung kept the one that cannot be acted on.
  - **The row's stated blocker — "no argv in historic sampler" — is refuted by a sibling store.**
    `compressor-sentinel-snap.log` has a `--- top N by RSS, full argv ---` section that is
    **rank-bounded and unfiltered** (222 blocks), and it has been capturing the bursting command
    lines the whole time. Three of them, all the same shape: `-a -o` with a permissive
    wildcard-context regex over a huge tree or the minified CC binary — `isEnabled:\(\)=>[^,]{0,200}
    ultrareview…` (6.0 GB), `.{0,250}hasRemoteEnvironment.{0,250}` (7.9 GB), `.{0,160}Ydr.{0,160}`
    (12.2 GB). **This is our own agents' grep recipe**, reached through the shadowed `grep`.
    ⚠️ A first pass read the file's *other* section header — `--- argv (node|chrom|next|vitest|
    esbuild|playwright) ---` — and nearly filed "the sampler's filter excludes claude". That was
    wrong and a `grep -cF claude.exe` (3,821 hits) caught it. **A section header is not the file's
    schema.**
  - **The magnitude in the title is instrument-specific and should not be quoted as RSS.** `top`'s
    MEM is not `ps` RSS and diverges in both directions, measured same-moment: WindowServer 1772 M
    vs 249 MB, kitty 1160 M vs 256 MB, Dia 901 M vs 1184 MB. The "4-40 GB" figure is top-MEM; the
    **RSS-measured ceiling for this class is 12.2 GB**. The 40 GB sample (pid 80508, 2026-08-02)
    predates snap-log coverage and has no argv, so it is unattributable either way.
  - **Landed remedy — argv[0], bounded, additive.** `read_argv0()` resolves argv[0] for the top-3
    pids in **one** batched `ps -o pid=,command= -p …`, and every `top_procs` row now carries
    `"argv0"`. **Full argv was refused deliberately**: argv carries whole agent briefs (memory
    `pgrep-f-matches-agent-briefs`) and this row is written every ~65 s, so it would put multi-KB
    prompts on disk forever. `cut -c1-200` bounds the read and only the basename is kept — ~10 bytes
    per process against ~823 bytes per row. Existing readers are untouched.
  - **Red-proof: 5 cases, all 5 red against origin/main's subject, each on its own argv0 assertion.**
    Mutants: **M1** lookup neutered → reds xxxiii/xxxiv/xxxv/xxxvii (xxxvi correctly stays green —
    empty is what it asserts) · **M3** argv0 on the first row only → reds exactly xxxiii + xxxvii ·
    **M4** a miss substitutes `cmd` back in → reds **exactly** xxxvi. 🚨 **The leak mutant took three
    tries and taught the real property**: `M2` (basename split only) and `M2b` (+ the producer's
    `NF == 2` guard) both still yielded `ugrep`, because the consumer's single-field `A[$2] = $3`
    read drops the tail independently. **The argv tail is bounded at three independent sites**, and
    only the three-site `M2c` reaches (xxxv)'s negative assertion. Recorded in the case, because a
    refactor collapsing those layers into one would otherwise land silently. *A mutant that leaves
    the suite green has not proven the case vacuous — it may have failed to do what you think.*
  - **REMAINDER — why the row is left OPEN.** The trigger is identified for the stratum where argv is
    readable, and **not** for the population. Of 6 distinct pids ≥4 GB with snap-log coverage, **3
    are unmistakably the embedded grep** (the shadow's fixed `-G --ignore-files --hidden -I
    --exclude-dir=…` prefix) and **3 render as `(claude.exe)`** — parenthesised, i.e. ps could not
    read argv at all. And **62 of the 150 events predate snap-log coverage** (begins 2026-08-06), so
    no argv is possible for them. Closing on "identified" would be exactly the narrowing this chain
    refuses. What changed is that the question is now *answerable*: `argv0` lands on **every**
    capacity-alarm row every ~65 s, far denser than the trip-gated snap blocks, so a successor can
    close this row on population coverage rather than on 3 readable pids. **The `cwd` leg of the
    row's prescription was not built** — argv[0] identifies the *class*, cwd would identify *which
    session*, and `lsof -a -d cwd` at this cadence is a cost this effort should not pay unattributed.
  - **Follow-on NOT filed (conservation: closed 0, so filed 0 — the sanctioned escape valve, per
    #24 and #30-#36, #39).** The genuinely actionable finding is upstream of this row: **our own
    agents routinely issue `grep -o` with `.{0,160}`-style wildcard-context regexes under `-a` over
    `~/.claude` and the minified binary, and that recipe costs 6-12 GB RSS per invocation.** 150
    events in 20 days. That is a recipe-level remedy, not a capacity-alarm one, and it belongs to
    whoever next opens a row on agent search discipline — recorded here rather than minted as a row.

- **2026-08-19 — drain recycle #39: the "evidence expired, close it" row had its evidence intact in
  an account store nobody enumerated — and the same blind spot had already manufactured a phantom
  population inside the measurement #38 landed one recycle earlier.**
  `master-fleet-footprint` **17 open / 4 blocked (4 operator-gated, `source: needs`; 0 cloud-venue,
  0 claimed, no stale claim)**. Property re-measured at intake: 17/17 open are `venuePlan=local`
  AND `project=claude-infrastructure`. **filed 0 / closed 0.** Landed `e797317cd` (session-end
  attribution) + this entry and the R-7 retraction. `b521cb445465` worked and **left OPEN, claim
  released**, remainder named below.
  - **`b521cb445465` is NOT evidence-expired, and the instrument that said so read one store of
    four.** The inherited brief offered it as a close candidate on `find ~/.claude/projects -name
    '*380dce96*'` → no output. **The transcript exists** — 701,799 bytes, 236 rows, at
    `~/.claude-tertiary/projects/…/380dce96-….jsonl`. The row's own account is `next3` =
    `claude-tertiary`, so the one root searched was guaranteed not to hold it. Do not close this row
    on evidence expiry; the evidence is complete.
  - **Two instrument traps inside the same investigation, each of which renders as a clean answer.**
    (i) *Timezone.* `sessions.log`, `lead-crash-watchdog.log`, `session-index.log` and
    `teammate-lifecycle.log` timestamp in **LOCAL** time (`[2026-07-29 21:39:12]`); `cc-reconcile.log`
    and the jsonl stores are **UTC** (`[…T04:39:12Z]`). The death at `04:39Z` is `21:39` local **on
    the previous day** — a first pass querying `2026-07-30T04:3*` found nothing across every
    lifecycle store and read exactly like "no closer ran". (ii) *Format.* Those same four stores use
    a space, not `T`, so even a right-day grep for `2026-07-30T04:` is blind by construction. Memory
    `process-start-time-renders-in-ambient-timezone`, `lookup-miss-is-not-absence`.
  - **The death RECLASSIFIES, but does not resolve.** At the death second the fleet logged
    `[2026-07-29 21:39:12] Session ended`, and `lead-crash-watchdog.log` carries
    `[watchdog 380dce96-…] pid file gone — exit` for this exact sid — the clean-shutdown branch.
    `claude-crashes.jsonl` has no row for it, which is the *documented expected* consequence of that
    branch, not a mystery. So the observed signature is a clean SessionEnd, **not** the unlogged
    abrupt kill the row's title asserts. **What it is NOT is proof of the initiator**, and the
    tempting inference was checked and refused: `session-deregister.sh:10-32` records that
    `claude mcp list` emits a PHANTOM SessionEnd on every SessionStart (reason `other`, fresh random
    sid), and **5360 of 6208** such lines are phantoms — so an unattributed "Session ended" is ~86%
    likely not to be a real end at all, and `session-end.sh`'s own straggler GC can remove a
    *sibling's* stale pidfile, so `pid file gone` does not uniquely convict this session's own hook.
    **Remainder: name what initiated the close.** Left OPEN deliberately — closing on the literal
    sub-question ("did any closer run") while the row's actual concern (a watched pane vanished with
    no visible continuation) is unanswered would be exactly the narrowing §6 forbids.
  - **Landed the remedy the investigation proves is needed** (`e797317cd`). `hooks/session-end.sh`
    wrote its `Session ended` line at line 2, **before reading its own stdin** — discarding the
    `session_id` and `reason` it parses four lines later. Both are now emitted
    (`Session ended sid=<sid|-> reason=<reason|->`), the literal phrase preserved verbatim so every
    existing consumer greps unchanged, both fields charset-sanitized and length-bounded because they
    reach a shared append-only log (a newline would otherwise forge a whole record). The duplicate
    `cat` below was **removed, not left**: a second read of a consumed stdin returns empty and still
    **exits 0**, so the `|| echo '{}'` fallback never fires and the sid would silently blank,
    disabling every removal in the hook — a mutant (M4) pins that regression. Suite 7 → 13 cases,
    every case anti-vacuity-guarded; **5 mutants, each redding its own assertion group with its own
    message** (M1 → 6,7,8,10 · M2 → 7,8,10 · M3 → 9 · M4 → 1,2,11 · M5 → 8).
  - 🚨 **RETRACTED a number this chain landed one recycle ago.** #38's R-7 measurement reported
    **110 of 214 sessions with NO transcript at all — 55% of Bash volume**, and
    `docs/plans/HOOK_CHAIN_COST.md` called it "not sampling noise, a structurally absent
    population", using it to argue a live-settings PostToolUse counter was *the only* way to reach a
    fleet figure. It was the two-root defect a third time. **There are four distinct transcript
    stores** — `~/.claude`, `-secondary`, `-tertiary`, `-quaternary` (plus `~/.claude-next/projects`,
    a symlink to the first: a glob double-counts it, a `find` reports it empty). Re-derived over all
    four on the log's own span: **218 of 218 sessions have a transcript; the absent population is
    ZERO**, with conservation asserted both ways and the two-root set a strict subset. The `1.40x`
    is therefore not confined to a stratum — the stratum is the fleet — and R-7's remainder may be a
    *measurement*, not the build. §5.2's paragraph is struck through with the correction in place.
    **The generalizable half:** `positive-control-the-denominator` binds the CORPUS YOU READ, and
    "I added the root I was missing" is not a control — enumerating `~/.claude*/projects` is. New
    memory `transcript-corpus-spans-four-account-stores`.

- **2026-08-19 — drain recycle #38: a row can be TRUE at its stated site and still prescribe the
  design its own subsystem already refuted — and the shortcut that would have answered the second
  row was refuted by its own denominator.** `master-fleet-footprint` **17 open / 4 blocked (4
  operator-gated, `source: needs`; 0 cloud-venue, 0 claimed, no stale claim — the 4 claimed rows
  fleet-wide are all `venue=cloud`, a stratum, none in this effort)**. Property re-measured at
  intake and at close: 17/17 open are `venuePlan=local` AND `project=claude-infrastructure`.
  **filed 0 / closed 1.** Landed `60f6ca46e` (case 29) + `a17164a7` (R-7 measurement).
  - **Closed `9a88cb04dab2` as PRESCRIBED-REMEDY-REFUTED** — not fixed, not already-fixed. It asks
    to wire `cc_capacity_admit` into the pane-split sites and stores the falsifier
    `grep -q cc_capacity_admit bin/cc-pane`, which is TRUE (count 0, re-measured at the moment of
    the close). **The falsifier was left exiting 1 and was not rewritten: this row is not closed by
    satisfying it.** Two independent reasons it is still wrong. (i) *The prescribed site is dead* —
    `cc-pane spawn` owns both raw `session split` sites (`bin/cc-pane:146,149`) and NOTHING calls
    that verb: 0 callers in the tracked tree, 0 in the live layer via a symlink-aware
    `find … | xargs grep` (a recursive grep there sees 1.7% of it), positive-controlled at 114 for
    `cc-notify`. Wiring the remedy would green the row's own falsifier while gating a path with no
    traffic. (ii) *The remedy at the primitive is the refuted design* — `handoff-fire.sh:6354` is
    `if [ "$RECYCLE" = 0 ]; then capacity_gate || exit 9; fi`, because a recycle REPLACES a session
    (net-zero panes) and is exempt on purpose. A term inside the primitive cannot see `$RECYCLE`:
    it fires on every split, so it would **refuse recycles — including this chain's own successor
    fire** — while putting the BUDGET-BOUNDED `cc_capacity_admit` underneath the UNBOUNDED
    `capacity_gate`. `handoff-fire.sh:4210-4213` names that composition verbatim ("ONE gate for
    both would re-commit the fix that §8.5.2 and §12.2 already refuted") and MACHINE_CAPACITY_V2
    §12.1 closes with "NOT by universalising `capacity_gate()` — §12.2 stands unamended". The
    population the row worries about is already gated **at the caller** (§12.1 census + coverage
    cases 21/23/24/25, landed `57cb9a60`/`64a7d1fae` on 2026-08-07 — the SAME DAY as the row's
    `firstTs`, `scan-revision-predates-the-fix`). Its cited incident `149789b69fc4` is the
    tsv-field-collapse guard row, not the load-781 pane meltdown.
    **Deliverable: case 29 in `tests/capacity-admit-coverage.bats`** — the ledger §12.1 itself
    designates ("read that suite, not this table") — stating the residue §12.1 never stated: the
    CALLER owns the gate because boundedness is a property of the caller, not of the primitive.
    Suite `1..15`, 15/15 ok, 0 skips; **4 mutants, one per assertion group, each RED with its own
    distinct message**; anti-vacuity locator asserts the split sites exist before claiming anything
    about them. `test-hermeticity-lint` caught my own diff (INHERIT on `CC_PANE_CMD*`, which case 29
    made subjects of this suite) — pristine-main attribution check confirmed rc=0 there, so it was
    mine; fixed by `unset` in `setup()`.
  - **`f6cc5c79885b` (R-7) left OPEN, claim RELEASED, remainder NARROWED** — `HOOK_CHAIN_COST.md`
    §5.2. R-7 wants an ALL-tool census; the obvious objection is that one exists un-consumed as the
    `tool_use` blocks in the transcripts. **Measured, that objection is wrong in R-7's own way.**
    Both counts bounded to `bash-execution.log`'s span (a Bash numerator over one span and an
    all-tool denominator over another IS the span mismatch R-7 names): 20,071 entry-starts across
    **214** sessions, of which only **104 have a transcript in either root** (9,069 entries) and
    **110 have none at all (11,000 entries — 55% of Bash volume)**. Transcript census: 13,388
    `tool_use` blocks deduped on tool_use id → **all/Bash = 1.40x**, cross-validated because its
    9,566 Bash calls closely match the 9,069 the log attributes to the shared stratum. So the ratio
    is real but scoped to 49% of sessions; the missing 51% is a structurally absent population, not
    sampling noise, so R-7 stays open and the counter it asks for is still the only fleet answer.
  - **Three instrument defects found INSIDE that measurement, each invisible in its own output** —
    recorded in §5.2 rather than smoothed away, and all three are re-hits of memories this chain
    already holds. A glob of `~/.claude/projects/*/*.jsonl` saw **899 of 1,817** files and missed
    the **second transcript root entirely** (`~/.claude-secondary/projects`, 1,725 files), reporting
    a confident **1.84x over roughly a quarter of the corpus**. A hand-typed epoch in the prefilter
    was **a year off** (Aug 2025, not Aug 2026), so it excluded nothing and said so nowhere — now
    derived from the window string. And the have/without split used `find … | grep -q .`
    (`grep-q-under-pipefail-inverts-the-verdict`) followed by `for u in $misslist` **under zsh,
    which does not word-split** — together producing "110 sessions with 0 entries", an arithmetic
    impossibility that is what exposed both. Final figures carry a conservation check (20,069 vs
    20,071, the log being live). **Lesson for the successor: `positive-control-the-denominator`
    applies to the corpus you READ, not only to the population you COUNT — and this fleet has TWO
    transcript roots.**
  - Teammates 0 code / 0 Explore. `deploy-live.sh` not run — the live layer is the pipeline lead's,
    and no land moves the postland-verify marker (see #24-#37).

- **2026-08-19 — drain recycle #37: a guard that defers "while it is busy" permanently exempts the
  population that is ALWAYS busy — and my own land re-created the defect I had just closed the
  sibling of, within minutes. `master-fleet-footprint` 18 open / 4 blocked (4 operator-gated,
  `source: needs`; 0 cloud-venue, 0 claimed, no stale claim). filed 1 / closed 2.** Land
  `5305ee34c`, content-verified on origin/main (`git diff origin/main` empty on both paths;
  `release_frozen` ×3, `kill -CONT` ×1, 10 unfreeze cases present).
  - **Date checked FIRST.** 2026-08-19 → `62363cac1e39` (due **2026-08-24**) still not drainable;
    effort = `master-fleet-footprint`, property re-measured **19/19 open were `venuePlan=local` AND
    `project=claude-infrastructure`**. #38 must check again — 2026-08-24 is now **5 days out**.
  - **Row `477f0b771ec3` — CLOSED, BUILT.** The sentinel actuator justified choosing SIGSTOP over
    SIGKILL in its own words — *"so we must be the reversible one"* — and the reversal was never
    built. Measured: **109 trips** (the row says 91; it has grown), **59 real SIGSTOPped events**,
    actuator armed for real (`CC_SENTINEL_ACT=stop` in the launchd wrapper), and **zero SIGCONT
    senders** in the tree. Now has a freeze ledger + `release_frozen` with an explicit three-mode
    policy (clear / ceiling / **exit**, the last so a daemon restart cannot strand a cohort), gated
    on `(pid,lstart)` TZ-pinned both sides so a recycled pid is dropped **without** a signal.
    - **Precondition substituted, and said so in the close.** The row asks to replay the snapshots
      through `select_stop_targets`; I measured the live actuation RECORD instead — the selector's
      real outputs rather than a simulation of them.
    - **10 cases; red-proof 10/10 `not ok` on pristine origin/main, 0 skips, instrument checked.**
      11 mutants: every case 1-10 redded by ≥1, including **per-SITE** mutants for both
      `record_frozen` call sites — the other nine cases drive the arm directly, so deleting a CALL
      would have left them all green (`invariant-can-live-in-an-absent-token`).
  - **Row `475222a572de` — LEFT OPEN, and the close-time re-measure is why.** Half 2 (no SIGCONT
    sender) is now built by the land above. Half 1 read REFUTED at intake: the running daemon's
    fd 255r held 72,743 B = `origin/main` exactly. **Re-measured at the moment of the close, it had
    become TRUE AGAIN — `origin/main` was now 79,904 B and the daemon still held 72,743.** My own
    land re-created it. Half 1 is not a one-time bug; it is structural.
  - **Row `e43e95c0ad18` — CLOSED as PREMISE-REFUTED + REMEDY-UNBUILDABLE, explicitly not "fixed".**
    Refuted **on trunk by name** in `TEAMMATE_SELFCLOSE_INVESTIGATION.md` CORRECTION 1: the shared
    cwd is TRUTHFUL and the teammate really runs there (proven three ways), so the tree a per-member
    gate reads IS their real tree; `.members[].cwd` is vendor-written and our repo has **zero
    writers**. Residue ("the gates are ownership-blind") deliberately NOT re-filed — it is a
    different claim and already recorded in that same trunk doc.
    - **The survey said "zero writers" and I re-derived it anyway** — my own writer-shaped grep
      returned **1** hit, which on inspection was a jq OUTPUT TEMPLATE (`cwd=\(.cwd // "?")`), i.e.
      a read. The verdict held; the instrument did not.
  - **FILED `ce775801633b` (1 filed vs 2 closed — conservation holds).** `install.sh:864` skips any
    job that currently holds a PID — correct for a periodic job hours deep, **permanently wrong for
    a `KeepAlive` daemon that by design never exits**, so its "next natural load" never arrives.
    **6 of 22** fleet plists are `KeepAlive`, i.e. six jobs the converger can never advance;
    `deploy-live.sh` issues no `launchctl` verb at all and the daemon has no self-reload. This is
    why "the live-layer convergence fix did not hold" — **a per-file symlink converger cannot reach
    a process that already holds the fd open.** Memory: `reload-guard-excludes-the-always-busy`.
  - **Explore survey over the 10 fleet-footprint rows no brief in this chain had assessed** (~25-call
    budget, partials allowed): 10/10 verdicts, no NOT-REACHED. Flagged premise drift on
    `66ef300dd0b4` (49→60 rows, 37 already done; 21GB→3.9GB TMPDIR) and `ad18a72e2be5` (`.claude.json`
    171KB→129KB, and that half is vendor-gated). Best unworked ratios it returned, for #38:
    **`9a88cb04dab2`** (S — `cc_capacity_admit` already proven at 5 call sites, absent from
    `bin/cc-pane`; its own falsifier still reads 0) and **`f6cc5c79885b`** (S — a Bash-only log
    consumed as a fleet-wide rate; the denominator already exists un-consumed in the transcripts).

- **2026-08-19 — drain recycle #36: two counts that justified a decision were each measured over a
  span their consumer never reads — one excluded a whole surface for 11 days, the other would have
  made the fix inert. `master-fleet-footprint` 19 open / 4 blocked (4 operator-gated, `source:
  needs`; 0 cloud-venue, 0 claimed, no stale claim). filed 0 / closed 1.** Lands `e1b0bb804` +
  `da0e8daf8`, both content-verified on origin/main (`git diff origin/main` empty on all 8 paths).
  - **Date checked FIRST.** 2026-08-19 → `62363cac1e39` (due **2026-08-24**) still not drainable;
    effort = `master-fleet-footprint`, property re-measured **19/19 open are `venuePlan=local` AND
    `project=claude-infrastructure`**. #37 must check again — 2026-08-24 is now **5 days out**.
  - **Row `bb2495b098b8` — CLOSED.** skills/ and agents/ now have the live→checkout auditor the row
    asked for, and the vendor-vs-ours split it demanded is recorded in `skills/LOCAL_ONLY.md`.
    - **The exclusion was carried by a count measured over the wrong span, and this is its THIRD
      revision — which reverses the second.** 20 (stale directory count) → 82 (right unit: the leg
      reports FILES, and the 5 live-only skill dirs hold 82 real files) → **5**. `sweep_strays` is
      **non-recursive and skips subdirectories**, so it visits depth 1 only: one `SKILL.md` per dir.
      `react-best-practices` contributes **1**, not 59. #35 landed the 82 figure with the conclusion
      *"the alarm-polarity case is STRONGER than when written — do not re-open this now that it is
      only 5"*; measured against the consumer, 5 declarations absorb the entire wall and the
      objection **dissolves**. Memory `assertion-span-must-equal-its-subject` — a span that does not
      equal its consumer's span is not a measurement of that consumer.
    - **The row's PRESCRIBED remedy would have killed the manifest's own anti-rot device.** It (and
      the manifest header) called for bare glob rows `skills/<name>/*`, *"the form `lib/*.prelink-bak`
      already uses"*. They are not the same form: a witness stem is the literal remainder after the
      `*` — `.prelink-bak` there, but the **EMPTY STRING** for a bare `*`, and `grep -F ''` matches
      every line. All 5 rows would have silently degraded to *"does the witness file exist"* while
      still reading as honoured. `declared_owner` now derives a whole-directory row's stem from its
      directory name; the fallback is reached by no existing row.
    - **FOUND BY THE WIDENING, not assumed:** `skills/kpmg-deck/showcase.pptx` — a gitignored build
      artifact inside an otherwise fully tracked skill, a class content-matching structurally cannot
      see. Declared, witnessed by `MIRROR.md`. And the widening's own witness check caught my
      incomplete `agents/motion-reviewer.md` declaration before I noticed it.
    - **`commands/` MEASURED, not assumed: 20/20 live entries are symlinks, zero real files** — so
      the one prompt-document surface left excluded holds nothing for this leg to find. That
      measurement is what closed the row; it is also what my own commit body predates (it says
      *"row stays OPEN"*, written before the measurement).
  - **Row `5d1b5dd9b3db` — spec 03 E9+E12 built and landed; row LEFT OPEN, claim RELEASED.**
    - **The measurement that would have made the fix inert.** The `-p`/`--version` exclusion scans
      argv fields **3..8** (2..7 in the reaper). In the real invocation
      (`scripts/headless-precondition-probe.sh:121-125`) `--input-format` lands at **field 9** —
      past that window. A marker scan reusing the same window returns "absent" for every genuine
      resident headless session, so the change reads correct in review and detects **nothing**. An
      independent probe had already flagged the narrow window
      (`tests/fixtures/codex-probe/runs/cp-06__D.md:125`) and nothing had acted on it.
    - **The spec's own edit list is incomplete for its stated outcome.** E9 names the argv filter
      alone, but `cc-reconcile:220` then requires `kind=="interactive"`, so an admitted headless pid
      still gets **no row**. Not guessed at: the spec already files this as **open question Q1**
      (`03-headless-substrate.md:446` — *"All 9 live rows read interactive. Measure."*). Re-measured
      2026-08-19 and **still unanswerable by observation** — 9 session files across all four config
      dirs, every one `interactive`, and **zero headless claude processes running**. So the tests
      assert exactly where the evidence ends: the resident is COUNTED LIVE (the E9 delta, 0→1) and
      reaches the kind gate. `live_pane_count` never consults `kind`, so the reaper's blind-spot
      detector is fixed outright.
    - Remaining and named: E7's rc-3 `no-watcher-headless` verdict, the E11/Q1 kind gate (blocked on
      a measurement), and **all of gap 2** (nothing wakes an idle headless session).
  - **TWO OF MY OWN NEW CASES WERE VACUOUS AND ONLY A MUTANT SAID SO.** Both asserted `rows==0` for a
    probe `cc-reconcile` rejects at the *kind* gate anyway, so they held at 0 whatever the argv rule
    did — the mutant that drops the `-p` exclusion outright reded their `cc-reaper` sibling and left
    both green. Re-asserted on the live count, the number the rule actually moves. **Asking "which
    mutant reds THIS case" is what surfaced it; the pristine-main red-proof did not.**
  - **Instrument notes for #37.** (1) An **apostrophe inside a single-quoted `awk` program** ends the
    shell string — three of them in comments I added broke both binaries at once and reded *every*
    pre-existing case, which reads like a logic error and is not. (2) The `zsh` no-word-split trap hit
    a `for n in $list` on the very first measurement. (3) `bats-shellcheck-lint` read `0 changed .bats
    line(s)` before committing and **81 after** — it scopes on a COMMIT RANGE, exactly as briefed.
  - **Not my loose end:** `deploy-link-parity` was **already red on trunk** before my diff (3 findings
    — `bin/browsermcp-wrapper.sh`, `bin/cc-cloud-watch`, and `bin/it2` drifted from its tracked
    `bin/it2-wrapper` source). My change adds **zero**. The `bin/it2` drift is a real, separate,
    unfiled defect: the manifest header cites it as the canonical *content-matched copy-deploy* case,
    and it no longer content-matches.

- **2026-08-19 — drain recycle #35: the fleet's own liveness oracle `(pid,lstart)` existed at two
  organs and reached NEITHER registry reader — and the guard that fixes it ships a WORSE bug unless
  its timezone is pinned. `master-fleet-footprint` 20 open / 4 blocked (4 operator-gated,
  `source: needs`; 0 cloud-venue, 0 claimed, no stale claim). filed 0 / closed 0.** Lands
  `8df2914e2` + `c1c8b48fa`, both content-verified on origin/main (`git diff origin/main` empty;
  `LIVE_ADDS=0`, `LIVE_LAG=2` inside the 25 budget).
  - **Date checked FIRST.** 2026-08-18 at intake → `master-session-lifecycle`'s `62363cac1e39`
    (efficacy re-census, due **2026-08-24**) still not drainable; effort = `master-fleet-footprint`.
    **Property re-measured, not inherited: 20/20 open are `venuePlan=local` AND
    `project=claude-infrastructure`.** #36 must check the date again — 2026-08-24 is now 5 days out.
  - **Row `5d1b5dd9b3db` — the LIVENESS half built and landed; row LEFT OPEN, claim RELEASED.**
    Pattern (d) again, seventh recycle running, and the widest form of it yet: the correct oracle was
    already written, tested, deployed and reasoned about — in `bin/cc-pane-headless:64-92` `is_live()`,
    *the very driver that mints the `hdl-` address* #33 taught the registry to accept — and again in
    `hooks/session-beat.sh:72-82` ("identity is (pid,lstart), never pid alone"). **30 files in this
    tree carry that idiom. `cc-registry` was the one store it had not reached**, so both readers
    adjudicated liveness with a bare `kill -0`.
    - **The defect, proven against pristine origin/main** (one live pid, a row whose recorded start
      time does not match it): `cc-sessions --names` printed `row-match row-recyc` — offering a dead
      session as addressable — and `cc-notify row-recyc` **resolved** it. Post-fix both return
      `no-such-target`. This is the false-LIFE mirror of `lookup-miss-is-not-absence`, and worse than
      a miss: cc-notify reports delivery for mail nobody will read.
    - **Why it bites headless hardest, i.e. why NOW.** A pane row has a second corroborator — the
      live-pane cross-check — but `1028a238b` (#34) deliberately skips it for `surface:headless`,
      because a pane list can only ever MISS a headless address. That was right, and it left a
      headless row's liveness resting on `kill -0` alone. **A fix can create the need for the next
      fix**: #34's correct narrowing is what made this the load-bearing gap.
    - 🚨 **THE TIMEZONE PIN IS THE LESSON, AND IT NEARLY SHIPPED THE INVERSE BUG.** `ps -o lstart=`
      renders through the AMBIENT timezone — measured, one live pid: `Tue 18 Aug 23:02:07 2026`
      local, `Wed 19 Aug 06:02:07 2026` under `TZ=UTC`, `Wed 19 Aug 15:02:07 2026` under
      `TZ=Asia/Tokyo`. Unpinned, the string changes for a process that **never restarted** whenever
      DST flips or a reader runs under a different TZ than the writer (every launchd daemon), and
      every reader convicts every row at once — **a fleet-wide false DEATH, strictly worse than the
      false life being fixed.** This repo had already paid for exactly that bug:
      `tests/watchdog-census.bats:197-221` pins lead-crash-watchdog's *third state*, which exists
      only to survive it. **UTC has no DST, so pinning removes the class instead of classifying it.**
      Found only because a `grep lstart tests/` surfaced that sibling suite — read the neighbours of
      any idiom you adopt. Safe to define the rendering because there was no corpus to migrate:
      **0 of 11 live rows carried `lstart` at all.**
    - **Fail-open twice, on two DIFFERENT facts** — no recorded value ⇒ a row predating the field
      (never convict on what nobody wrote); an unreadable `ps` ⇒ not proof of death. Only a value
      READ and DIFFERING convicts. Measured worth: mutating that fail-open out breaks **21 of the 87
      pre-existing cc-notify cases**, so the backward-compatibility claim is a number, not a hope.
    - **The TSV column was the silent hazard.** `REG_ROWS` is tab-separated and `read` puts all
      remaining fields in its LAST variable, so a reader left at `read -r n p u` does not fail — it
      binds `u` to `<uuid><TAB><lstart>` and every address comparison silently stops matching. All
      **3** readers moved in one diff; a **block census** case pins 2 producer arms / 3 four-field
      readers / 0 three-field readers, and its mutant reds both the census AND real name resolution.
    - **Spec R3 deliberately NOT adopted, and the correction is the deliverable.** `03-headless-substrate.md`
      prescribes *beat freshness* as the session-level oracle because two live sids share one pid
      (C2). True for the harness-sid design that spec assumed; **false for the address this tree
      adopted** — `hdl-` is minted per agent process, so `(pid,lstart)` does discriminate. Named in
      the commit body. **Remainder, for #36:** argv classifiers E9/E12, the rc-3
      `no-watcher-headless` verdict, and gap 2 entirely.
  - **Row `bb2495b098b8` — precondition discharged, premise CORRECTED, row LEFT OPEN, claim RELEASED.**
    Its stated blocker was "needs the vendor-vs-ours split decided FIRST, then an auditor". The split
    is **already decided by siblings**: `f542c8b2c` tracked 13 skills, `8b33db9e6`/`ab62d3a08` two
    more, and `9d8965faa` recorded the surviving 5 as third-party derivatives in `skills/LOCAL_ONLY.md`
    with a durable reason each. So 20 of 35 unversioned → **5 of 35**.
    - 🚨 **AND THE OBVIOUS CONCLUSION FROM THAT IS WRONG — measurement refuted my own hypothesis
      mid-pass.** "Only 5 left, so the alarm-polarity exclusion of `skills/` has expired, widen the
      STRAY sweep" is exactly backwards. **The STRAY leg reports FILES, not directories**: those 5
      dirs hold **84 files (82 real, 2 symlinks it already excludes)** — `react-best-practices` alone
      is **59**. Widening today prints an **82-line** wall, not a 5-line one, so the alarm-polarity
      case is **~4x STRONGER** than when written. "20 of the 35 live skills" conflated a DIRECTORY
      count with a FILE count and understated the wall 4x. Both sites now carry both numbers and an
      explicit *do not re-open on the directory count*.
    - **Two near-misses worth keeping.** (1) I was about to VERSION `pyramid-principle-full` as an
      unbacked 116K asset with zero git objects anywhere — until reading the citing commit revealed
      it is a **deliberate copyright call** (a derivative of Minto's book, never to enter git
      history). *Read the commit that made the decision before "fixing" its outcome.* (2) The
      declaration the sweep commit promised "in the next commit" landed as a **doc**
      (`skills/LOCAL_ONLY.md`), not in `config/live-only.manifest` — the store
      `deploy-link-parity.sh` actually reads (`conclusion-must-reach-the-enforcing-store`). Adding
      manifest rows now would be **inert**, because the sweep does not reach `skills/` at all.
    - **Coherent remedy recorded for #36:** 5 glob rows (`skills/<name>/*`, the form
      `lib/*.prelink-bak` already uses) witnessed by `skills/LOCAL_ONLY.md`, landed as **ONE unit**
      with the widening — rows are inert until the sweep reaches them, and the widening without them
      IS the 82-line wall. `agents/motion-reviewer.md` is a real file in no checkout, same class.
  - **Two RED lands, both correct, both caught defects in MY tests — and one exposed a prescribed
    pre-land check that is strictly weaker than the gate.**
    - 🚨 **`bats-assert-liveness-fix.py --dry-run` IS NOT THE GATE, AND ITS rc=0 IS NOT A
      CLEARANCE.** The gate runs the DETECTOR `scripts/bats-assert-liveness.py`; the brief's
      prescribed pre-land command runs the **fixer**, which reports `would fix 0` and **exits 0** for
      any shape it cannot auto-rewrite. Same file, same moment: fixer `--dry-run` rc=**0**, fixer
      real-mode rc=**2** (declines), detector rc=**1** (one finding). It cost a 5-minute RED land.
      **#36+: run `python3 scripts/bats-assert-liveness.py <suites>`** (memory:
      `prescribed-repro-weaker-than-the-harness`, `cost-gate-must-be-strictly-weaker`).
    - **`scripts/bats-kill-guard-lint.sh` is a blocking gate and is NOT in the brief's sweep list.**
      It caught `[ -n "$P" ] && kill "$P" 2>/dev/null; return 0` — `&&` does **not** exempt errexit
      for the last command of an AND-list, and a trailing `; return 0` never runs, so a child already
      reaped under load aborts the body. Add it to the sweep.
    - **A `git checkout HEAD -- <file>` after a mutant ate an UNCOMMITTED fix** (the #22 trap, hit
      again). Cure used: `cp` the fixed file aside BEFORE mutating, restore from the copy.
    - **A mutant filter matched the WRONG case** — `-f 'ambient TZ'` hit the cc-sessions case, not
      the register case labelled `ambient-TZ` (hyphen), and the resulting `ok` read as "the mutant
      did not red it". *Prove your filter selected the case you think it did* (#34's law, new shape).
  - **7 mutants, and every one of the 10 new cases is credited by at least one.** M1 drop the TZ pin
    (read side) → the matching-still-live + TZ-identical pair · M2 delete the cc-sessions guard → the
    recycled-row case alone · M3 drop the TZ pin (write side) → both write-side cases · M4 remove
    `pid_live` fail-open → the truth table **+ 21 of 87 pre-existing** · M5 one reader back to 3
    fields → census **and** name resolution · M6 remove cc-sessions fail-open → the legacy-row case
    alone · M7 drop the TZ pin in `pid_live` → truth table + over-conviction control. Tree verified
    restored (`git diff --stat HEAD` = 0) after every one.
  - **Suites run green by hand before landing: 16, ~500 cases, each with its `1..N` seen and 0
    `# skip` in the new blocks** — so the land's smoke abstain on `tests/cc-notify.bats` (exit 124,
    zero `not ok`, the documented non-verdict) cost nothing. `session-registry` 1..36 ·
    `cc-notify` 1..91 · `deploy-link-parity` 1..34 · plus 13 consumer suites.
  - **Teammates 0 / Explore 0** — both rows were pre-surveyed by the brief; direct re-derivation was
    cheaper, as it was for #31-#34.

- **2026-08-18 — drain recycle #34: a fix can land at TWO organs and be re-refused by SIXTEEN, and
  a landedness check by SHA can read "never landed" over content that is plainly on trunk.
  `master-fleet-footprint` 20 open / 4 blocked (4 operator-gated, `source: needs`; 0 cloud-venue,
  0 claimed, no stale claim). filed 0 / closed 1.** Land `1028a238b`, content-verified on
  origin/main (13 paths, `git diff origin/main` empty, predicate present at every site).
  - **Date checked FIRST.** 2026-08-18 — `master-session-lifecycle`'s `62363cac1e39` (efficacy
    re-census, due **2026-08-24**) still **not drainable**. #35 must check again; on or after
    2026-08-24 it outranks fleet-footprint.
  - **Property re-measured, not inherited: 21 open at intake, 21/21 `venuePlan=local` AND
    `project=claude-infrastructure`.** 4 blocked, all `source: needs`.
  - **Built the CONSUMER half of `5d1b5dd9b3db`; row LEFT OPEN, claim RELEASED.** `b532c67ec` made
    `hdl-<16 hex>` a real registry identity at the writer (`session-register.sh`) and the drain
    (`mailbox-drain.sh`). **Sixteen other readers each carried their own copy of the retired rule**
    `*[!0-9A-Fa-f-]*`, and `h`/`l` are not hex digits — so a headless session was addressable at the
    two fixed organs and structurally invisible at every other one: not a fired peer (cc-classify,
    cc-reaper ×3), counted pane-less (cc-reconcile), un-recoverable (cc-recover-safeguard),
    un-wakeable (mailbox-wake-arm), **wake floor inert and mail never folded** (session-continue ×5),
    stamp unreadable (desk-invariant), unstampable (handoff-fire `mark_fired_peer`), unswept
    (lead-supervisor), unaddressable (cc-notify). Replaced with the safe-filename-component
    predicate the tree already settled on — `''|.|..|.*|*[!A-Za-z0-9._-]*` — each site pointing at
    the SSOT rationale rather than restating it.
  - **THE PATTERN HELD A SEVENTH TIME, and this is now its most reliable shape: question (d) —
    *does the fix exist and simply not reach its consumer?*** Seven rows across #31-#34. Here the
    fix had already landed **and been proven**, one level away from sixteen call sites.
  - **`cc-notify`'s arm 1b is the generator caught in the act.** It was added 2026-08-07 for exactly
    this failure (`cc-notify 247` → no-such-target while `--list` printed pane 247 live) and fixed it
    by enumerating **one more spelling** (`^[0-9]+$`). A headless address walked straight back into
    the same hole. Widened to the CLASS; the row-file requirement that makes it safe is untouched and
    is pinned as a control. **Enumerating a spelling does not retire the defect — it schedules it.**
  - **Widening was SEQUENCED deliberately.** `mark_fired_peer` (stamp WRITER) and cc-reaper's three
    stamp READERS moved in one commit: today no headless stamp can exist, so widening the readers
    alone changes nothing observable and widening the writer alone produces stamps the reaper
    ignores. Together a headless fired peer becomes both stampable and reapable.
  - **TWO EXISTING ASSERTIONS PINNED THE OLD SPELLING — corrected, not deleted.**
    `tests/cc-reaper.bats` "a non-UUID pane can never carry a marker (path-fragment guard fails
    safe)" passed **`PANE-X`**, which is not a path fragment at all — it is a perfectly safe filename
    that merely is not hex. The case asserted a *harmless* address is inert and **would tripwire any
    widening**. Fixture is now a real traversal, name states the class, and the positive half (a
    headless pane DOES carry a marker) is added beside it.
    `tests/handoff-fire-stamp-daemon-path.bats` pinned the refusal wording `not UUID/hex-shaped`;
    `%3` is still refused, only the message changed, because that phrase had stopped describing the
    rule. (memory: `stale-assertion-becomes-an-inverted-guard`)
  - **The hermeticity gate caught this session's own suite twice and was right both times.**
    `cc-recover-safeguard` reaches `cc-notify`/`cc-sessions` by **BARE NAME**, so without
    `CC_RECOVER_NOTIFY_BIN`/`CC_RECOVER_SESSIONS_BIN` the behavioural case would have executed the
    operator's **deployed** binaries. A fixtured `$HOME` did not cover it and the suite looked
    perfectly hermetic. Both seams pinned to absent paths.
  - **Red-proof, and its anti-vacuity half.** `tests/headless-address-consumers.bats` extracts the
    REAL arm list of all 15 case blocks from the shipped files and asserts a **semantic** property,
    not a spelling: *a headless address must be classified by the SAME arm as a canonical pane uuid
    and a DIFFERENT arm than a path-traversal string.* Pristine origin/main: **`1..13`, 12 red,
    1 control green, zero skips**; post-fix 13/13. A per-file **block census** fails loud if the
    guards vanish, so the suite cannot silently test zero. Mutants, all four as designed: single-file
    revert → **case 2 only** (attribution); over-wide predicate → **OVER-WIDE** at that site only
    (the control direction, which no revert covers); guard **deleted** → **BLOCK CENSUS** red (the
    vacuity proof); `cc-notify` row-file requirement dropped → **case 13 only**, case 12 still green.
  - **Closed `d40d148d0333` on its own falsifier — and the sha it cites is NOT on main.**
    `7a218edc` is **not an ancestor** of origin/main (full sha, `merge-base --is-ancestor` rc 1); it
    was rewritten on the way in and the content landed as `d3951e5e3` + `2a352788b`. **A landedness
    check by sha would have read "never landed" and re-derived a fix that has been on trunk for nine
    days.** Adjudicated by CONTENT: `bin/it2-kitty` carries the `AGENT-PANE`/`AGENT-NO-BOX` branch at
    five sites, `tests/it2-kitty-composer-guard.bats` pins it with 10 named CONTROL cases,
    **`1..47`, 47/47 green this turn**; and 0 of 11 live `claude`-argv0 processes carry the agent-id
    flag, so none is idle >2h. (memory: `landedness-oracle-is-blind-to-intent`)
  - **`pgrep-f-matches-agent-briefs` fired twice inside one measurement.** A bare `--agent-id` ps
    grep returned a hit that was a **`jq` process whose argv carried the backlog JSON**, and a
    self-matching grep counted **its own pipeline** as 3 agent panes. The honest census anchors on
    argv0 and reports its denominator: **0 of 11**.
  - **Instrument note for #35:** `bats-shellcheck-lint` infers its scope from `origin/main...HEAD`,
    so it reports **0 changed `.bats` lines** for an UNCOMMITTED test file and prints *clean*.
    `git add -N` does not help — it needs the **commit**. Re-run it after committing, or its silence
    is blindness. (memory: `gate-scope-from-git-diff-is-blind-to-untracked`)

- **2026-08-18 — drain recycle #33: the pattern held a FIFTH and SIXTH time, and both times the
  unreachable fix was an ADDRESS THE FLEET ALREADY MINTS. `master-fleet-footprint` 21 open /
  4 blocked (4 operator-gated, `source: needs`; 0 cloud-venue, 0 claimed, no stale claim).
  filed 0 / closed 1.** Lands `b532c67ec` (headless registry address) and `ed7eee4c4` (it2-kitty
  delivery proof), both content-verified on origin/main.
  - **Date checked FIRST.** 2026-08-18 — `master-session-lifecycle`'s `62363cac1e39` (efficacy
    re-census, due **2026-08-24**) still **not drainable**. #34 must check again; on or after
    2026-08-24 it outranks fleet-footprint.
  - **Property re-measured, not inherited: 22 open at intake, 22/22 `venuePlan=local` AND
    `project=claude-infrastructure`.** 4 blocked, all `source: needs`.
  - **Built + closed `4b9d5e93b40a` — the row's premise was wrong and the defect was real
    underneath it.** The row says cc-registry "is keyed on a pane UUID" and the 38 KB spec written
    against it (`docs/research/scaling-bottlenecks-2026-08-09/03-headless-substrate.md`) prescribes
    a 15-edit re-key onto the harness `session_id`. Neither was needed. `bin/cc-pane-headless:124`
    ALREADY mints `hdl-<16 hex>` and `:197` runs the agent under
    `export CC_PANE_ID="$id" && unset ITERM_SESSION_ID` — i.e. the seam that spec calls "the whole
    leverage" was built, landed and wired. What refused it was one `case` arm in
    `hooks/session-register.sh`: `''|*[!0-9A-Fa-f-]*) return 0`. **`h` and `l` are not hex digits**,
    so the gate refused the address its own fleet mints and the session got NO ROW AT ALL — from
    which every symptom follows (cc-sessions never lists it; cc-notify converts the lookup-miss
    into `reason=target-not-live`; peers retire a live session).
  - **The gate was already wrong in the OTHER direction too, which is what proves "hex" was never
    the rule.** The fleet runs kitty; `scripts/kitty-setup.sh:305` synthesises
    `ITERM_SESSION_ID="w0t0p0:$KITTY_WINDOW_ID"`, and those small integers pass only because digits
    are hex. "UUID-shaped" had stopped describing the live keyspace in both directions at once.
  - **Fixed at the 4 sites that form ONE keyspace and cannot move separately** — write
    (`session-register.sh`), remove (`session-deregister.sh`), read (`bin/cc-sessions`), drain
    (`hooks/mailbox-drain.sh`). The predicate is the one this tree had ALREADY settled on for this
    exact class: `hooks/lib/mailbox-pending.sh:118-124` `_mbx_valid_uuid` — a safe filename
    component, which is the property the guard actually protects (the value becomes
    `$reg_dir/$pane.json`). Inlined rather than sourced: the hook runs every SessionStart under a
    hard wall-clock budget and that lib is 824 lines.
  - **🚨 The drain edit is what keeps the registration edit HONEST rather than harmful.** Registering
    a headless session while `mailbox-drain.sh` still exited at its own hex gate would have traded
    "correctly reported dead" for "reported live, deliverable, and structurally deaf" — the worse of
    the two, because nothing looks wrong. **Ask of any addressability fix: does the thing I just made
    reachable have a working receive path?**
  - **TWO SPEC PRESCRIPTIONS REJECTED, both named in the commit body.** E3 ("skip the ancestor walk
    on the non-pane branch — a sid is not inherited") is true of a harness session_id and **FALSE of
    the address actually received**: `cc-pane-headless` EXPORTS `CC_PANE_ID`, so a nested `claude -p`
    inherits the tenant's address exactly as a pane child does. Taking it would have reopened the
    2026-08-08 dead-pid-corpse squat on precisely the sessions with no pane to be re-addressed
    through. E4's "skip the alias write / coverage fold / migrate for headless" is unnecessary under
    this design: keying on the driver-minted address instead of re-keying on the session id leaves
    all five downstream uses working unchanged, because each treats the value as an opaque mailbox
    key. **A spec's edit list is calibrated to ITS OWN design; adopting a different design silently
    invalidates parts of it.**
  - **Partially built `d90bbcd9e01f`, LEFT OPEN, claim released.** Same pattern a sixth time:
    `bin/it2-kitty` has owned `pane_exists()` since `:322` with exactly ONE caller, and
    `identity_ok()`/`composer_state()` guard only `close` — so the DESTRUCTIVE verb was proven
    against three oracles while the two DELIVERY verbs were proven against none. Re-measured live
    at the same moment as the fix: `kitty @ send-text --match id:999999 -- ""` → **rc=0**, id absent
    from `ls`, so the `|| exit 1` on both verbs is dead code and mis-delivery is undetectable.
    `prove_target()` wires the existing oracle in, fail-OPEN on rc 2 (indeterminate is not absence).
    **Not closed**, because the row's other half — a nonce echo-verify catching text that arrives
    MANGLED rather than nowhere — cannot be lifted from `scripts/lib/cc-type-verified.sh`: every
    function there shells out to osascript against `com.googlecode.iterm2`, so adopting it means
    writing a kitty transport in the one script `handoff-fire.sh` routes its own typing through.
    That wants a window that can exercise the fire path end to end.
  - **A gate refusal that was RIGHT for a reason that was not its message.** `pipefail-sigpipe-lint`
    said `bin/cc-sessions` "was FIXED but its allowlist count was not lowered — set it to 0". It had
    not been fixed: adding a guard as a **line continuation** pushed `printf` off the statement head,
    where the detector could no longer see it. Obeying the instruction would have made a live
    SIGPIPE site permanently invisible. Removed the hazard for real (herestring, no pipe), which
    made the count-0 honest. **When a ratchet says a site disappeared and you did not remove one,
    the census went blind — check before lowering it.**
  - **Red-proof discipline held (both rows).** Every fixture constructs the `hdl-`/stub shapes
    LITERALLY and calls NO symbol the fixes introduce; run against pristine `origin/main` worktrees:
    5 red + 3 both-direction controls (row 1), 2 red + 2 controls (row 2), plan lines seen, **zero
    `# skip`**. Two mutants that no revert covers: adding spec E3's tenancy bypass reds the
    nested-squat case; treating rc 2 as absent reds the unreadable-enumeration case and nothing
    else. Both controls are load-bearing rather than decorative.
  - **For #34:** `5d1b5dd9b3db` still holds the CONSUMER half of the same predicate — **16 further
    sites** of `*[!0-9A-Fa-f-]*` across `bin/cc-reconcile:178`, `bin/cc-reaper:725/741/762`,
    `bin/cc-notify` `target_live()`, `bin/cc-inbox-guard`, `hooks/mailbox-wake-arm.sh:115`,
    `hooks/session-continue.sh` (5 sites), plus the argv `-p` classifiers — and all liveness
    hardening (the spec's `(pid,lstart)` pair; note C2's shared-pid subagent case, where two live
    sids share one pid, so pid can prove the CONTAINER alive but never the SESSION).

- **2026-08-18 — drain recycle #32: both rows were a defect whose FIX ALREADY EXISTED and could not
  reach the class that needed it — once as a blind ratchet, once as a proof living in the wrong
  file. `master-fleet-footprint` 22 open / 4 blocked (4 operator-gated, `source: needs`; 0
  cloud-venue, 0 claimed). filed 0 / closed 2.** Lands `f223b2c5c` (class-B pane-id preference) and
  `d20134339` (alias-trail tenancy gate), both content-verified on origin/main.
  - **Date checked FIRST.** 2026-08-18 — `master-session-lifecycle`'s `62363cac1e39` (efficacy
    re-census, due **2026-08-24**) still **not drainable**. #33 must check again; on or after
    2026-08-24 it outranks fleet-footprint.
  - **Property re-measured, not inherited: 24 open at intake, 24/24 `venuePlan=local` AND
    `project=claude-infrastructure`.** 4 blocked, all `source: needs`. No stale claim.
  - **Built + closed `0f796daa0c76` — the pane-id rename's OWN ratchet was structurally blind to the
    class it needed to cover.** `tests/cc-pane.bats` already enforced "no production file reads a
    BARE `$ITERM_SESSION_ID`" and had been green since it first fired. It greps the SHELL spelling
    `${ITERM_SESSION_ID:-}` — a process reading its OWN id. A disjoint class reads ANOTHER pid's
    pane id out of a `ps eww` blob, where the key is a STRING (`grep '^ITERM_SESSION_ID='`,
    `env_val "$blob" ITERM_SESSION_ID`, `index($i,"ITERM_SESSION_ID=")`). None contains that
    expansion, so five un-migrated sites sat behind a green gate. Extended the ratchet to class B.
  - **Three corrections to that row, all landed in the commit body.** (1) The population is **5**
    in-track sites, not 4 — `bin/cc-teardown`'s `pane_occupants()` was unnamed, and that file
    already preferred CC_PANE_ID for its OWN id at :148 while the oracle reading OTHER processes did
    not. (2) A **6th** genuine class-B site exists at `scripts/handoff-fire.sh:3277`, excluded BY
    CONSTRUCTION on the class-3 exemption list the original ratchet already carries. (3) The obvious
    remedy — widening the grep to `^(CC_PANE_ID|ITERM_SESSION_ID)=` — is wrong **twice**: it matches
    EITHER key (a stale inherited iTerm id beside a fresh CC_PANE_ID resolves the pid to a pane it
    does not occupy), and it would have been **INERT anyway**, because CC_PANE_ID accepts the BARE
    uuid, on which the existing `${line##*:}` yields `CC_PANE_ID=<uuid>` and every downstream UUID
    check rejects it. **Stripping `KEY=` BEFORE `##*:` is the load-bearing half.**
  - **Built + closed `66ec1b04f050` — the alias trail was the THIRD pane→session store and the only
    ungated one.** The same nested-`claude` hazard was gated on the registry WRITE side
    (`session-register.sh:126-165`, 2026-08-08) and the REMOVE side (`session-deregister.sh:12-32`,
    2026-08-05). Both turn on `pid_is_strict_ancestor`, defined INSIDE `session-register.sh` and on
    no path `hooks/lib/mailbox-pending.sh` can see — so the store written on EVERY boundary, rather
    than only at SessionStart, had no gate at all.
  - **The row's own precondition, established before fixing as it instructed.** "Does any resolver
    read the TIP?" — `mailbox_alias_of()` does and would MISDELIVER, but has **ZERO production
    callers**, so that harm does not exist. `mailbox_session_is_current()` does and IS live: it is
    the liveness proxy guarding pull-adoption. So the row's reassurance *"self-heals at the parent's
    next boundary"* is true of the TIP and **FALSE of the TRAIL** — which is append-only, and
    `mailbox_adoptable_predecessors` keeps only the 3 most recent entries, so every nested write
    permanently consumes an adoption slot and pushes a real predecessor off the end. Its mail is
    then never adopted, silently. (Memory: `reassurance-clause-is-the-untested-half`.)
  - 🚨 **A RED-PROOF CAME BACK 5/5 GREEN AND WAS VACUOUS — the sharpest lesson of this pass, because
    the failure mode is invisible.** Run against a pristine `origin/main` worktree, the tenancy cases
    all reported `ok`. They had not passed: the fixture called `_mbx_claude_pid`, which does not
    exist pre-fix, so it returned empty, the cases hit their `skip` guard, **and bats renders a skip
    as `ok`**. A control that could not fail read exactly like one that passed. **A red-proof fixture
    must never call into the subject, and a `skip` inside one is how it goes vacuous** — both guards
    are now hard failures. Generalises `verification-harness-vacuous-pass-traps`: the trap here was
    not a shell quirk but the *harness's own rendering* of abstention as success.
  - **Mutants, one per check — and 2 of 5 answers were NOT the expected ones.** Dropping the call
    site / the ancestry walk / the kill switch each reds exactly one named case. Dropping
    `kill -0 "$inc"` and dropping the self-row early return red **NOTHING**: a dead pid is not in
    our ancestor chain either, and the walk starts at our claude's PARENT so our own pid can never
    match. Both are fork-saving fast paths, **not** the safety property — kept, and the code now
    says which is which, because a reader who believes a fast path is a guard will not dare touch
    it. A **live-non-ancestor (pid-reuse)** case was ADDED as a result: until it existed, nothing
    credited the ancestry check, making it indistinguishable from decoration.
  - **Teammates 0 / Explore 0** — both rows were pre-surveyed by #31's brief or re-derived directly;
    a fresh fan-out would have cost more than the derivation. Recycled at **~32% fill**, deliberately
    early, so #33 inherits a full window for `4b9d5e93b40a` / `5d1b5dd9b3db` (below).
  - **Measured for #33, so it need not re-derive:** `4b9d5e93b40a` (headless sessions never register)
    is **LIVE** — `hooks/session-register.sh:101-103` returns 0 on an empty/non-hex pane, writing no
    row; its falsifier `grep -q headless hooks/session-register.sh` finds **0** hits. But its remedy
    is the sibling row `5d1b5dd9b3db`, the **38 KB** headless-substrate spec (15+8 edits, 17 tests,
    `docs/research/scaling-bottlenecks-2026-08-09/03-headless-substrate.md`). They are a
    defect/remedy PAIR and the claim gate allows only one at a time. **Do not split it:** landing the
    writer without the reader's glob and the deregister path makes headless rows unreapable orphans.
    Give it a full window.

- **2026-08-18 — drain recycle #31: both rows were already SOLVED somewhere in the tree and neither
  solution could be reached from the place that needed it. `master-fleet-footprint` 24 open /
  4 blocked (4 operator-gated, `source: needs`; 0 cloud-venue, 0 claimed). filed 0 / closed 2.**
  Lands `d72f2981b` (cc-teardown tty guard) and `9df04881b` (successor engagement gate), both
  content-verified on origin/main.
  - **Date checked FIRST, as #30 instructed.** 2026-08-18 — `master-session-lifecycle`'s
    `62363cac1e39` (efficacy re-census, due **2026-08-24**) is still **not drainable**. #32 must
    check again; on or after 2026-08-24 it outranks fleet-footprint.
  - **Property re-measured, not inherited: 26 open at intake, 26/26 `venuePlan=local` AND
    `project=claude-infrastructure`.** 4 blocked, all `source: needs`.
  - **Built + closed `47878886746f` — `tty_foreign()` counted the launcher's OWN close-records
    `tee`, so every wrapped session was un-reapable by construction.** The marking walk is strictly
    DOWNWARD from the target, and `cc-close-attrib` spawns its `tee` (:222) and the real binary
    (:242, `{ exec "$REAL_BIN" "$@" 2>&9; } <&0 &`) as two background SIBLINGS. The tee is therefore
    never in the marked tree and is not a shell, so it scored 1 and the guard DEFERred `tty-busy`
    forever. Fix reads the target's own ppid from the SAME ps table and stops counting processes
    hanging off it.
    - **The obvious discriminator was measured and found DEAD, which is what chose the rule.**
      "Exempt siblings only under a non-shell wrapper" is unimplementable here: `ps -o comm=`
      reports a `#!`-script as its interpreter, so `cc-close-attrib` reads as `/bin/bash`,
      indistinguishable from the interactive shell. Measured with a probe before writing code.
      That also explains the row's `count=1` — every ancestor in the chain is a shell script and was
      already allowlisted; only the `tee`, a real binary, ever scored.
    - **Structural, not a spelling.** Adding `tee` to the shell allowlist would exempt a genuinely
      foreign tee on any tty — the opposite of the guard's purpose.
    - **The pre-existing control was VACUOUS for this axis and could not stand in for either arm.**
      Scenario 10's target is absent from its own ps table, so `tppid` is empty and nothing is
      exempted; neither mutant reds it. Two new scenarios, opposite polarity: M1 (drop the sibling
      skip, == pre-fix) reds ONLY 10b with the row's own symptom `rc=10/DEFER`; M2 (drop the
      ppid-equality, keep the non-empty guard) reds ONLY 10c `rc=0/TEARDOWN`, which is what earns
      the narrowness arm. Ratchet `tests/cc-teardown.bats` 25 → 27.
  - **Built + closed `93a9f880b6fe` — SCOPE CORRECTED: the row's prescribed remedy was not needed
    and was not built.** It asked for a resume special-case ("when launched with `--resume <sid>`,
    verify against THAT sid's transcript and assert it GREW"). `engagement_seen` already has a
    resume-proof CONTENT path keyed on the fire marker, its own comment NAMES this row, and
    `tests/handoff-lifecycle-record.bats` already proved that path returns 0 where the registry path
    returns 1. The defect was one level up: the sole consumer, `successor_engaged`, called it with
    an **empty marker**, so the better oracle was unreachable from the only gate that needed it.
    - **Nothing new had to be built — the field was already being written and ignored.**
      `mark_fired_peer` records `.marker` for exactly this purpose; its own field comment reads *"so
      successor_engaged no longer depends on row 4's registry row carrying a `.session_id`"*. The
      conclusion had simply never reached the enforcing call site (memory:
      `spec-named-mechanism-may-be-prose-only`, `conclusion-must-reach-the-enforcing-store`).
    - **The fix covers a LARGER population than the row named**, which is why no resume branch
      exists: any pane holding `ensure_registration`'s PROVISIONAL row has no `.session_id` at all
      (M-9) and was equally unprovable. Not resume-specific.
    - **Three mutants, three cases, one each — M3 exists because case 3 was otherwise dead.** M1
      (drop the marker read, == pre-fix) reds ONLY case 1; M2 (`${3-}` → `${3:-}`) reds ONLY case 2;
      M3 (treat a recorded marker as proof by itself — the plausible wrong fix) reds ONLY case 3,
      which passes under both other mutants. The `${3-}`-vs-`${3:-}` case is the
      `harness-default-collapses-the-states-under-test` memory made falsifiable.
    - **The land's own gate caught a real gap and its remedy was the better one.**
      `bats-shellcheck` went RED on two SC2034 dead assignments THIS diff wrote. They are consumed
      by the sed-extracted unit, not by any test body — so the gate was right. Taking its second
      suggestion (`export`) over a per-site `disable` states the truth instead of silencing it.
      Fixed and re-verified LOCALLY by running `scripts/bats-shellcheck-lint.sh` rather than paying
      a second 5-minute land cycle to find out.
  - **The second land's smoke gate ABSTAINED (`smoke PARTIAL`, 9 suites attempted, 120s budget
    exhausted) and the land proceeded — not a red, and it cost nothing** because all four affected
    suites had been run green in-session with their `1..N` seen: handoff-lifecycle-record `1..15`,
    fire-engagement `1..34`, handoff-engage-scan-window `1..10`, handoff-fire-pane-parked `1..30`.
  - **Instrument note for #32: `grep -c 'fdir="${3-'` returned 0 on a file that CONTAINS that
    string.** The interactive grep here reads `{3-` as an interval expression, so the null was a
    regex-flavor artifact, not absence — `grep -cF` found it at `handoff-fire.sh:2423`. A
    content-verification null is not evidence until the instrument is controlled.
  - **Surveyed-but-not-taken, carried forward for #32:** `15265ac3c502` has NO detail body and no
    falsifier — its primary site (`hooks/worktree-setup.sh`) already uses the prescribed
    `bash <script>` form at :62 and :175, but closing it means proving a whole CLASS adopted, which
    is a broader claim than it looks; a first grep for it was wrong twice (pattern required no space
    after `bash`, and `\./` matches the `./` inside `../`). `0f796daa0c76` remains 4 confirmed sites
    with one G2 escalation surface (`teammate-auto-shutdown` resolves a pane in order to CLOSE it).
  - **Teammates: 0 code spawns, 0 Explore surveys** — #30's survey section covered the rows taken,
    and re-deriving its claims directly was cheaper than a fresh fan-out.

- **2026-08-18 — drain recycle #30: a subagent's ALREADY-FIXED verdict was refuted by the log and
  then re-confirmed by the code, arriving at the same close for the opposite reason.
  `master-fleet-footprint` 26 open / 4 blocked (4 operator-gated, `source: needs`; 0 cloud-venue,
  0 claimed). filed 0 / closed 2.**
  Land `81831f80e` (window-census `--pid`), content-verified on origin/main.
  - **Re-measured rather than inherited, and the property held.** 28 open at intake, **28/28
    `venuePlan=local` AND `project=claude-infrastructure`**. Date checked FIRST:
    `master-session-lifecycle`'s `62363cac1e39` (efficacy re-census, due **2026-08-24**) is still
    **not drainable** on 2026-08-18; #31 must check the date again before anything else.
  - **Built + closed `cb47f6a92fe9` — `window-census.swift` grouped on `kCGWindowOwnerName`, which
    is the APP's name, so two instances of one app summed into ONE row.** The `pid` column was
    whichever window was enumerated last. Cherry-picked the 25-line `--pid` hunk from `dd695e1a0`
    (branch `terminal-arm-land`, **not** an ancestor of main); the base blob is byte-identical
    across `dd695e1a0^` / `origin/main` / `HEAD` (`38a50d7fd`), so the land is main plus exactly
    that hunk and nothing else from a branch whose bake-off verdict has been warranted away.
    - **The flag was not merely absent — it was silently IGNORED, which is strictly worse.**
      Pre-fix, `--pid <a windowless pid>` exits **0** with `verdict=OK` and all 37 owners on the
      box: the tool answered a question nobody asked and certified it. Post-fix, exit 3 /
      `verdict=NO-DATA`, the same rule `--owner` already followed.
    - **Three mutants, one per SITE, each red its named case and no other — 0 weak.** M1 filter-site
      red BOTH cases; M2 keying-site (always key on app name) red **only** arm 2; M3 no-data-site
      red **only** arm 1. M2 is the one that matters: it proves arm 2 is load-bearing rather than
      decoration, because a fix that satisfies arm 1 by making `--pid` always return `NO-DATA`
      would pass arm 1 while destroying the only reason the flag exists.
  - **Closed `594dcaa4e976` as ALREADY-FIXED — but the Explore survey's verdict did not survive
    first contact, and re-deriving it is what produced the real evidence.** The survey called it
    already-fixed and explained the falsifier's red as a cumulative append-only log measuring
    history. The log **refuted that**: the newest `rc=67` is **2026-08-17**, seven days AFTER the
    fix landed (`5f5fd7270`, 2026-08-10 11:05:41 -0700), so the residue was not all historical.
    - **The code then re-confirmed the close for the opposite reason.** 13 events post-date the
      fix, and they are the arm the remedy **deliberately preserves**. With a zero-byte screen
      capture (verified: `20260818T044659Z-win300.txt` is 0 bytes) the landed `no_box` predicate at
      `bin/it2-kitty:727` reaches `UNKNOWN` only when `agent == "-"` — an argv-unproven pane. And
      `tests/it2-kitty-composer-guard.bats` case **17**, *"CONTROL: the same zero-rule screen
      WITHOUT an agent argv is refused"*, pins that refusal as **required**.
    - **⇒ The stored falsifier cannot green on the row's own prescribed remedy, and was NOT
      rewritten.** It demands `grep -c 'rc=67' == 0` while the remedy it prescribes keeps `rc=67`
      for the rendered-but-unreadable arm. Closed on independent content evidence instead: the
      split is on main at `:727`, both states are admitted at `:972`, the suite is `1..47` green
      this moment, and refusals collapsed 46 (Aug-7) / 24 (Aug-9) / 57 (Aug-10) → 3 / 3.
    - **Two instrument traps worth carrying.** The fix landed as `AGENT-PANE` / `AGENT-NO-BOX`, not
      the row's proposed `NO-COMPOSER`, so grepping the row's own token returns nothing and reads
      as *not landed*. And the row's `firstTs` (05:29) is EARLIER the same day than the fix
      (11:05) — dating the fix against the row is what separated "sibling already did it" from
      "still open".
  - **For #31: a subagent verdict is a claim, and BOTH directions of checking it paid.** The survey
    (5 rows, ~14 calls, all reached) was high-value, but its one actionable verdict was wrong in
    its reasoning and right in its conclusion. Re-deriving cost four commands. Its other verdicts —
    `4b9d5e93b40a` (headless sessions never register; multi-file, writer+deregister+reader must
    change together), `47878886746f` (`cc-teardown` `tty_foreign` counts a sibling `tee`;
    single-file, control already exists), `15265ac3c502` (**EVIDENCE-EXPIRED** at its primary site
    — `hooks/worktree-setup.sh` already uses the prescribed `bash script.sh` form) and
    `d90bbcd9e01f` (spawn half landed, existing-pane half unwired; large) — are UNVERIFIED
    survey prose, not measurements. Re-derive before claiming.

- **2026-08-18 — drain recycle #29: the row's two premises were both false and the defect underneath
  them was real; a standing trunk red, not mine, was what actually held the land.
  `master-fleet-footprint` 28 open / 4 blocked (4 operator-gated, `source: needs`; 0 cloud-venue,
  0 claimed). filed 1 / closed 2.**
  Lands `aa0ce5cbf` (residency) + `f7c17fd2b` (cc-backlog sentinel), both content-verified on origin/main.
  - **Re-measured rather than inherited, and the property held.** 30 open at intake, **30/30
    `venuePlan=local` AND `project=claude-infrastructure`**. `master-session-lifecycle`'s
    `62363cac1e39` (efficacy re-census, due **2026-08-24**) was checked against today's date FIRST
    and is still **not drainable**; #30 must check the date again before anything else.
  - **Built + closed `4a7762ca46c0` — `scripts/assignee-pane-residency.sh` reached `it2` and `jq`
    by bare name, and the failure mode is a PERMANENT quiet degradation, not a crash.** `win_ids()`
    maps a 127 to `unreachable`, which is the correct degradation and is deliberately distinguished
    from `empty` — but nothing ever recovers it, so the alarm runs on the process table alone while
    still printing a confident verdict token. `PS_BIN` one line below already spelled its binary
    absolutely, so the file disagreed with itself.
    - **BOTH of the row's premises were FALSE, and saying so is part of the deliverable.**
      (1) The row asserts a box rebuilt from this repo "would 127 on it" because `bin/it2` is
      untracked. REFUTED: `install.sh:758` runs `copy_file "$REPO_DIR/bin/it2-wrapper"
      "$CONFIG_DIR/bin/it2"`, and live `~/.claude/bin/it2` is byte-identical to tracked
      `bin/it2-wrapper` (sha256 `5e57f1c7c10e`). A rebuilt box gets it. The real hazard is narrower
      and still real: callers other than the launchd job, which prepends both dirs itself via
      `bash -c` and is fine.
      (2) The row instructs "delete the `scripts/assignee-pane-residency.sh:it2` row from
      `EMBEDDED_ALLOWLIST`". **There is no such entry** — `git log -S` over
      `scripts/unattended-path-lint.sh` on origin/main returns nothing. Its cited commit
      `66960552` is **NOT AN ANCESTOR of origin/main**; it never landed. An instruction premised on
      unlanded history is unexecutable, and one `--is-ancestor` call is what separates the two
      (memory: `work-item-citation-refutes-its-own-remedy`).
    - 🚨 **THE GATE REJECTED THE FIX, THE GATE WAS RIGHT, AND ITS SECOND SUGGESTION WAS BETTER.**
      The first cut copied the established `hooks/teammate-auto-shutdown.sh:_it2_bin()` precedent
      verbatim — `command -v it2 2>/dev/null || echo "$HOME/.claude/bin/it2"`. `unattended-path-lint`
      went **rc=1** on it: that spelling puts a bare name at COMMAND position. Taking the lint's
      SECOND offered remedy instead — harden PATH at the top of the file, the idiom
      `teammate-auto-shutdown.sh:55` documents — was strictly better: lint green, **no allowlist
      entry to carry**, and it covers `jq`, the file's second bare name, for free. APPEND never
      prepend, so a caller keeps its own resolution order.
    - **Two arms pulling opposite ways, and the mutant is what proves the second one.** Plan line
      seen on every run: pre-fix `1..2` arm1 **not ok** / arm2 ok · fixed `1..21` all ok · mutant
      (prepend instead of append) `1..2` arm1 ok / arm2 **not ok**. Arm 2 exists only to catch a fix
      that passes arm 1 while silently overriding every caller; without the mutant run it is
      indistinguishable from a dead assertion (`guard-proxy-fails-in-both-directions`).
    - **NOT PINNED, explicitly:** `jq` rides the same PATH append but has no arm of its own — both
      new tests hold `CC_RESIDENCY_JQ_BIN` absolute precisely so a red can only be about `it2`.
  - **Closed `68b8279b1457` on a sibling's landed fix, content-verified, not on its subject line.**
    `7408f4c11` ("a probe that could not answer was reaping on its silence") addresses this row's
    exact defect and not an adjacent one — its body names `claude_cwds()` having "one output channel
    — stdout — and two meanings on it", and names `recheck_live()` as the consumer that now "fails
    CLOSED". Verified in the code, located by NAME: `claude_cwds()` returns rc 2 on every
    unanswerable path, gated by a POSITIVE CONTROL (lsof reading the cwd of its own pid — "an lsof
    that cannot report that cannot report anyone's"), and `recheck_live()` reads `rc` and returns
    KEEP with `RECHECK_WHY="occupancy UNPROVEN"`. The third state on the rc channel, with the
    null-result kept off the error channel — `lookup-miss-is-not-absence`,
    `probe-that-acts-on-absence-must-confirm-presence`.
  - 🚨 **THE LAND WAS REFUSED BY A STANDING TRUNK RED THAT WAS NOT MINE, AND ATTRIBUTING IT FIRST IS
    WHAT MADE THE FIX CORRECT.** `tests/tsv-field-collapse.bats` case 34 ("no padding sentinel is
    ever left in a tracked source file as a raw byte") failed the smoke gate, so `ship-land.sh`
    refused to push. It named `bin/cc-backlog`: **8 raw 0x1f bytes** across 4 lines. A **pristine
    detached origin/main checkout reported the identical finding** while the same scan over this
    session's own two files exited 1 — so it was a standing red blocking every lander, exactly the
    shape case 34's own comment records from `28a8fba9b`. Fixed with the remedy the guard prescribes
    (`\037` inside the `printf` FORMAT, which printf interprets itself), proven inert by `od -c`
    rather than argued: `printf 'a\037b'` and `printf 'a<raw>b'` are byte-identical. Controls:
    tsv-field-collapse `1..34` case 34 now ok; `backlog-blocked-producers.bats` `1..8` green before
    AND after (the only suite exercising the changed lines — unchanged behaviour is the claim);
    `shellcheck -x bin/cc-backlog` 0, run EXPLICITLY because the file is extensionless and the usual
    `grep '\.sh$'` drops it silently.
    `Scope (grown): +unblock the standing tsv-sentinel red in bin/cc-backlog` (F1-F4 PASS: it
    unblocks every land in the repo, not only this one).
  - **Filed 1, deliberately OUT of the effort being drained** (`master-verification-integrity`, so
    it does not inflate fleet-footprint's own open count): `scripts/unattended-path-lint.sh` on
    origin/main is **blind to the `${VAR:-name}` spelling** and sees only a bare name at COMMAND
    position. Measured decisively rather than inferred — it was silent on
    `IT2_BIN="${CC_RESIDENCY_IT2_BIN:-it2}"` for that defect's entire life and went rc=1 the instant
    the spelling changed. The detector that closes it exists ONLY on the unlanded `66960552`, which
    also touches `scripts/boot-resume.sh`. That lint GATES EVERY LAND, so widening it is its own
    piece of work, not a passing edit.
  - **Survey (1 read-only Explore, ~25-call budget, returned in-pass with 5 verdicts — and one of
    them was WRONG, which is why they get re-derived).** It called `f0283c35130e` a CLOSE-CANDIDATE;
    one plist read refuted it — `launchd/com.claude.browser-spin-guard.plist:34` says verbatim **"IT
    DETECTS AND SURFACES; IT DOES NOT REAP"**, and its ProgramArguments run `--notify`, never
    `--reap`. A subagent's prose is a CLAIM (`synthesis-loses-provenance`). Verdicts handed to #30:
    `cb47f6a92fe9` STILL-LIVE and buildable (commit `dd695e1a0` and ref `terminal-arm-land` at
    `088e7c2df` both still exist; the merge bug is intact) · `0f796daa0c76` STILL-LIVE, all 4 sites
    ITERM_SESSION_ID-only, and **not a sed** — they read another pid's `ps eww` env blob, so it is a
    two-key blob lookup · `93a9f880b6fe` STILL-LIVE at REDUCED scope — the oracle was fixed and its
    comment names this row, but the consumer `successor_engaged()` calls it with an EMPTY marker, so
    the fixed path is unreached; the minimal fix is threading the marker, not the growth assertion
    the row prescribes.
  - **`475222a572de` re-checked and #29's own first reading corrected.** Half 2 (no SIGCONT sender)
    is **CONFIRMED STILL LIVE**: a bare `git grep CONT` hits the sentinel file and reads as YES, but
    every hit is a COMMENT explaining why the freeze is one-way — `grep -vE '^\s*#'` first returns
    nothing (`spec-named-mechanism-may-be-prose-only`). Half 1's stated evidence has moved (tree,
    live symlink and origin/main now all read 72,743 B against the row's cited 42,679 vs 52,618),
    but that does NOT clear it: the row's claim is about the bytes the RUNNING daemon holds an fd
    on, which no file-size check can see.
  - **Instrument note worth carrying:** `$?` after a pipe is the LAST command's rc. A
    `lint.sh | tail -40` + `echo $?` read as a clean **rc=0** while the lint was about to report
    **rc=1** on this session's own diff. Capture it as `out=$(cmd 2>&1); rc=$?`.
  - Live layer: `deploy-live.sh` declines as it has for #24-#29 — no GREEN tree is a descendant of
    live HEAD (the postland-verify stamp has not advanced). `LIVE_ADDS=0` for this pass: both
    commits extend already-symlinked files and add none. Not this session's loose end.

- **2026-08-18 — drain recycle #28: the guard was real, and every artifact a human reads ignored it.
  `master-fleet-footprint` 30 open / 4 blocked (4 operator-gated, `source: needs`; 0
  cloud-venue, 0 claimed). filed 0 / closed 1.**
  Land `904bacdcc`, content-verified on origin/main.
  - **Re-measured rather than inherited, and the inheritance held.** 31 open at intake, **31/31
    `venuePlan=local` AND `project=claude-infrastructure`** — the property #27 established is still
    true, so the lane needed no re-derivation. `master-session-lifecycle`'s `62363cac1e39` (efficacy
    re-census, due **2026-08-24**) was checked against today's date and is **not yet drainable**;
    #29 should check it first, since on or after the 24th it outranks anything in fleet-footprint.
  - **Built `6e1361f39202` — `auto_revert` refused the orphaned culprit; the page, the durable
    backlog row and the peer ping all went on naming it anyway.** The guard landed 9795ec7b and
    logs `reason=culprit-not-in-trunk`, but it runs at the BOTTOM of `red_actions` and all three
    human-facing artifacts are written ABOVE it. So the fix was real and *invisible*: the operator
    was handed a sha to act on that the code one screen below had already ruled un-actionable.
    Measured 2026-08-09 (item a31d1fe3de3d): culprit 57e162494c10, not an ancestor of origin/main,
    patch on trunk as 28949c7b with five commits on top. 2 of 9 all-time revert markers carry
    non-ancestor culprits. Cause is the land-lane race — target captured at entry, corpus runs ~1h,
    a rebase-land inside that window rewrites the shas.
    - **EXTRACTED the predicate, did not copy it** — the row's own FIX clause said so and
      `make-the-actuator-the-arbiter` is why. `trunk_state()` is now the single arbiter; `auto_revert`
      calls it with **both log tokens and the fetch byte-identical**, which is what makes the
      pre-existing **C20** (a real revert lands) and **C31** (orphan refused) the extraction's own
      controls rather than tests I had to write.
    - **THREE answers everywhere, never two.** `trunk`/`orphan`/`blind`, and for the twin
      `<sha>`/`none`/`blind`. A `blind` instrument renders exactly today's plain line and adds NO
      claim — refusing to accuse a sha of being orphaned on evidence we could not obtain is the same
      discipline `no-trunk-ref` already encoded one layer down (`lookup-miss-is-not-absence`,
      `probe-that-acts-on-absence-must-confirm-presence`).
    - **`patch_twin()` names the operator's real next move.** Naming the orphan alone hands back a
      dead end; the actionable fact is "act on the twin". A rebase-land preserves the patch and
      changes the sha, so the twin is located by **patch-id** and never by sha or tree — which is
      exactly why `--is-ancestor` is the discriminator and patch-id the locator. ONE fork pair for
      the whole window (`git log -p` emits its own commit headers and `patch-id` attributes each
      diff back to them), bounded by commits (120) and seconds (60).
    - 🚨 **The locator was positive-controlled against the REAL repo before being trusted** — a
      known trunk commit's own patch-id resolved back to itself. `control-must-replay-the-real-artifact`:
      a locator proven only inside its own fixture proves the fixture.
  - **The row's stored falsifier CANNOT green on the remedy the row prescribes.** It greps
    `red_actions` for a literal `is-ancestor` — i.e. for exactly the re-implementation the row's own
    FIX clause forbids. Measured against a **pristine origin/main worktree**, that spelling and
    `trunk_state` both read 0, so it was a true pre-fix RED and is now a permanent false negative.
    **Not rewritten**: a rewritten probe on a row that closes with the same change is unfalsifiable
    ceremony, and narrowing a falsifier so one's own row can close is the move this chain forbids.
    Named in the commit body instead, where a future re-file will look
    (`work-item-citation-refutes-its-own-remedy`, `control-calibrated-to-implementation-decays`).
  - **Red-proof: C34 + C35, 5 mutants one-per-SITE, 5/5 red their named case, 0 weak.** C34 reuses C31's own `orphan_culprit_bats()` fixture —
    one race, two consumers — so the orphan is produced by the REAL land-lane shape rather than a
    hand-set flag; its twin is minted as the culprit's own tree on the culprit's own parent, which
    is what makes it prove the *locator* and not merely the orphan half. **C35 is the too-wide
    control**: an over-firing guard would satisfy every C34 claim while telling the operator not to
    act on perfectly actionable shas, and C20 could not catch that because it never reads the page
    text. Both carry a `NO VERDICT` control, because every claim lives on the convicted branch and
    an abstained run would satisfy them vacuously.
  - 🚨 **NOT independently pinned, and said so rather than implied:** the peer-ping rendering. It
    rides the same computed `$orphan` guard as the other two, but no test in this suite asserts
    `cc-notify.argv` and `author_sid` does not resolve in the fixture. Covered by construction, not
    by assertion — the #27 lesson about a comment overclaiming what the code does, applied to a
    close instead of a comment.
  - **Instrument note for #29 — the cheap anchor half paid for itself again.** The mutation harness
    validates every anchor BEFORE paying for a single suite run; the first firing aborted on a stale
    M4 anchor (mangled by shell quoting of an `awk` fragment) having spent nothing. Under this box's
    load (~10-15, the live postland daemon sweeps concurrently) each case-run is ~5 min, so a
    7-run proof is ~35 min — background it and do read-only work, and never edit the subject while
    it runs.
  - **The land's own smoke gate abstained, correctly, and #29 should read it the same way.**
    `tests/cc-reaper.bats` was CUT by the 120s smoke budget — exit 124, **ZERO `not ok`** — and the
    gate says so in its own words: *"It is NOT a red and NOT evidence about your tree"*, land
    PROCEEDS with `smoke:"partial"`. That is a BOUND firing under a loaded box, not a verdict about
    the diff, and it is a suite this change does not touch (`timeout-rc-collides-with-the-childs-own-rc`,
    `bound-must-fit-the-band-not-the-bench`). Do not chase it, and do not launder it into a green
    either — the gate already named which it is.

- **2026-08-19 — drain recycle #27: the briefed effort was UNDRAINABLE BY CONSTRUCTION, so the pass
  switched on one measurement and drained `master-fleet-footprint` 35 → 31 open / 4 blocked (4
  operator-gated, `source: needs`; 0 cloud-venue, 0 claimed). filed 0 / closed 4.**
  Lands `c961dc779` + `24357bdc5` + `ef1fe0478`, each content-verified on origin/main.
  - **`master-product-repos` is not this chain's to drain, and the reason is structural.** It was
    the indicated pick (smallest, 34 open). Measured at intake: **33 of its 34 open rows target
    repos that are not claude-infrastructure** — reso-management-app 27 · doc_classifier 3 · reso 1
    · reso-qa-runner 1 · agent-build-hackathon 1 — and the single claude-infrastructure row
    (`79e7c3cb7357`) is the **wave-PARENT meta row** describing exactly those other-repo rows, not
    a fix. Closing them would mean committing to another project's default branch, which the chain
    forbids. Its two `claimed` rows are **`venue=cloud`** — a stratum, not the stale local claims
    the brief warned might be there. `master-fleet-footprint` is the right lane and this is why, so
    #28 does not re-derive it: **35 open, 100% `project=claude-infrastructure` AND 100%
    `venuePlan=local`** — the only sizeable effort with that property. The switch cost one query.
  - **Built `d65dcfd22ce2` — the seam's argv contract.** `cc-pane list --json` and `cc-pane list`
    were BYTE-IDENTICAL because the verb dispatch never passed `"$@"`; a consumer asking for JSON
    got integers, `json.load()` raised, and the failure read as the DATA's fault. Fixed at SIX
    sites — list/address/close on **both** `bin/cc-pane` and `bin/cc-pane-headless`, the latter
    load-bearing rather than symmetric: cc-pane `exec`s that driver with `"$@"` intact, so an
    iterm2-only guard leaves `CC_PANE_DRIVER=headless cc-pane list --json` still lying. **Refused
    the flag rather than implementing it**, which the row offered as its other branch: `list`'s
    contract is one opaque id per line, the three drivers cannot all answer id/cwd/alive, and a
    `--json` that lied on the headless driver would recreate this defect one layer down.
    6 cases + **6 mutants, one per SITE** (21 caught / 0 weak over the whole harness).
    - **The row asked whether a prior fix had regressed, and answering it was half the pass.**
      It flagged completed item K5 ("it2-kitty ignores --json") as the same SHAPE. Neither
      regressed nor half-covered: `bin/it2-kitty` still implements `session list --json` and emits
      `[{"id":…}]`. The hole was one layer UP, in cc-pane's own argv. A row naming a prior fix is
      asking a real question, and answering it is what stops the same fix being applied twice in
      the wrong place.
  - **Built `34f41cc9118b` — the landed-dirt path destroyed directories and recorded nothing.**
    `--dispose-abandoned` has always appended a disposal record (that record is what distinguishes
    abandoned-BY-DECISION from dropped-BY-ACCIDENT, which git alone cannot); `--dispose-landed-dirt`
    reaped 32 directories on 2026-08-11 and appended none. **The asymmetry is the defect, not the
    stakes** — gitignored bytes are recorded NOWHERE else, and the echo scrolls past.
    - 🚨 **The row's own framing needed two corrections, and both are in the landed diff.** (a) It
      prescribes "a `dispose_record()` call"; the record-writer is **`log_disposal()`** —
      `dispose_record()` is the whole gated DISPOSE action and would have re-run gates that do not
      apply to a landed branch. (b) Copying the abandoned path's record wholesale would have
      written a FALSE field: `preserved_at` is hardcoded `refs/heads/<branch>`, true only for that
      class because those branches are UNLANDED so `--prune-branches` skips them
      (`landed "$branch" || continue`). A landed-dirt branch is landed and worktree-less, so the
      **same run may legitimately `branch -d` it** — the record would point at nothing. Hence a new
      OPTIONAL 11th parameter defaulting to the old value (every existing caller byte-identical),
      and the dirt row names the TRUNK. `unlanded_patches` is 0 with no shas for the same reason:
      being LANDED is what DEFINES the class, not an unmeasured default.
    - **The CONTROL case is the one that earns the parameter.** A 4-mutant red-proof, one per SITE,
      each caught by its OWN named test with no over-wide reds: the call deleted (original bug
      restored) · `preserved_at` falling back to the branch · **the optional param's DEFAULT broken
      — caught ONLY by the abandoned-path control** · a phantom row on `--dry-run`. Unmutated
      control green before AND after; subject restored from an in-memory copy, `shasum`-confirmed
      identical to the `cp` backup.
  - **Closed on evidence, not on work: `2224128627d0` (ALREADY-FIXED) and `1f89d52cb049`
    (EVIDENCE-GONE).** The first asked to investigate + fix "an armed /goal never evaluates on this
    box" and listed two live hypotheses; `goal-in-handoff-2026-08-08.md` now opens
    `# RESOLVED 2026-08-09`, refutes BOTH by name plus hook-shadowing, and reads the real mechanism
    out of the binary (goal evaluation is gated on a QUIET task registry, and a 4-hour
    `cc-await-ping` background Bash holds one open) — guard landed `c00595bf7`, widened `d59dff44c`.
    **This session was itself live evidence: its own `until … sleep` watcher was DENIED at the tool
    call with that exact message.** The second's subject script does not exist on origin/main at
    all (a throwaway probe harness), the grid it blocked completed 36/36 the day the row was filed,
    and its prescribed `start_new_session` pattern predates it in both `ship-land.sh` and
    `handoff-fire.sh`.
  - 🚨 **A read-only `Explore` survey is the highest-leverage FIRST move in this effort — do it
    before building anything.** One agent ran the three-question pass over 5 candidate rows in ~2
    minutes and settled all five; it is how both evidence-closes were found, and its three
    STILL-LIVE verdicts are the successor's map. **Every verdict was re-verified by the lead
    against origin/main before use** — a subagent's finding is a claim, not a measurement.
  - **STILL-LIVE, mapped, for #28:** `6e1361f39202` — `postland-verify.sh` `red_actions()`
    (:2483-2622) has ZERO ancestry tests; the only one is in `auto_revert` at :2361, and the
    2026-08-17 fix (`ebbf3adfb4d0`) addressed the bisect-ABSTAINED case, **not** the orphaned-sha
    case. · `475222a572de` — both halves open: `deploy-parity-assert.sh` explicitly disclaims
    daemons, so a launchd-resident sentinel on stale bytes is invisible to it BY DESIGN, and the
    only two SIGCONT strings in the tree are prose acknowledging the one-way freeze.
  - **A comment that overclaims is the same defect class as the flag the row was about.** The lead
    wrote "EVERY VERB REJECTS ARGUMENTS IT DOES NOT IMPLEMENT" above a dispatch where `driver` and
    the help verb still drop theirs, caught it in self-review, and **narrowed the comment rather
    than widening the code** — widening would have added two sites the red-proof does not mutate,
    which is how a proof starts overstating its own coverage. The next agent reads a comment as a
    contract and does not re-derive it. Landed separately (`24357bdc5`) so the correction is
    legible rather than buried in the fix.
  - **Two instrument findings, recorded here rather than FILED — a recycle that closes 4 may still
    not end net-positive on filings, and neither is measured enough to be a row.** (a) `pgrep -f
    '<script>.sh'` used to poll a background job **matches the poller's own argv**, so it reported
    RUNNING against a process that was this session's own `zsh -c` wrapper; the anchored form is
    `ps -eo pid,etime,command` filtered to exclude the reader, or a pid captured up front. This is
    `pgrep-f-matches-agent-briefs` re-hit inside our own waiting code, which is corroboration of
    that memory rather than a new item. (b) There is **no generic enforcement** of the
    `start_new_session` rule surfaced by `1f89d52cb049` — `hooks/validate-bash.sh` has zero hits
    for `nohup`/`setsid`/`start_new_session` — so the doctrine lives only in the two scripts that
    already obey it. Speculative as a row; named here so it is not lost.
  - ⚠️ **`bash scripts/ship-land.sh` outlives the Bash tool's 600 s CEILING, and the brief's
    "tool timeout 930000" is silently CLAMPED to it.** The second land returned exit 143 at 10m00s
    with no output — and had **already pushed**: `origin/main..HEAD = 0`, empty path diff,
    `_dirt_head` present twice in the landed copy. This is the exact failure the operating rules
    already warn about, arriving through the TOOL's cap rather than the script's own `timeout`.
    **Always adjudicate a land by CONTENT before believing it failed.**

- **2026-08-18T23:30Z — LEAD (pane 102) wave synthesis: all three fires returned inside 50 minutes,
  ledger 417 → 404 live, and every one red-proved BOTH ways against the REAL pre-fix artifact.**
  `d6d4b85ebd4c` → `206d0c001` · `7da9c4451540` → `27fb9da42` · `dc014c6829ac` → `017650872`, each
  content-verified on origin/main by this lead independently of the assignee's claim. The alarm
  half of `7da9c4451540` was FILED as `6a5a218fd9a8`, not prosed. Per-fix detail is in the three
  entries below; what follows is only what the WAVE showed that no single entry could.
  - 🚨 **THE POPULATION GREW WHILE THE FIX WAS BEING WRITTEN: four duplicates at filing, NINE by
    the time the assignee started, two minutes later.** Nothing went wrong — that is simply what an
    INFLOW GENERATOR does while you repair it. The lesson is about how such a row must be WORKED:
    **a count in a filing note is a LOWER BOUND with a timestamp, never the population.** A fix
    that closed exactly the ids the note named would have left five siblings behind, still minting,
    and would have reported success. Consolidation must RE-CENSUS at claim time. All nine folded
    onto canonical `20eff55d74f7`, each fold evidenced, none deleted — and that row stays OPEN,
    because the re-land work it describes is genuinely unlanded (`land-content-verify` rc=1).
    Closing it would have been exactly the false-zero this plan exists to prevent (§1.1).
  - 🚀 **All three are landed and NOT live, and the converger is RIGHT to refuse.**
    `deploy-live.sh` returns rc=0 and declines: **no GREEN tree is a DESCENDANT of live HEAD**
    `36cbb55eda4c` — the newest green, `555e3b270f1e`, is BEHIND it, so deploying it would report a
    deploy that never happened. Lag 17 / 25 commits, 3h / 6h, inside the degrade budget, and
    `LIVE_ADDS=0` so the budget legitimately applies (an ADD would breach at lag 1). Two assignees
    hit this independently and reported it identically, which is the mechanism working. **But name
    what is inert:** `~/.claude/scripts/drain-chain-assert.sh` is a per-file symlink into the shared
    checkout, so the alarm the 24/7 pipeline depends on still runs the OLD blind predicate on the
    real box until a green tree lands. The stale `postland-verify` stamp is PRE-EXISTING, red long
    before any of these diffs — named, not driven, per the attribution rule.
  - **Two lanes, one store, no collision — because the rows were CLAIMED before they were fired.**
    A claim is a lease, so the drain chain (recycle #26, running throughout) could not pick up work
    a dispatched session held. This is the cheap half of two-lane safety and it cost three commands.

- **2026-08-18 — `d6d4b85ebd4c`: §6's liveness invariant was blind to the failure that happens, and
  the INPUT was the fix.** `scripts/drain-chain-assert.sh` was wired correctly (autonomy-sweep
  § 2b-v, 300 s, condition-keyed, self-falsifying) and had filed ZERO rows at any status in its
  whole deployed life — through the ~4 h dead-stop at recycle #21 (pane 131 wedged on a `rm -r`
  PreToolUse modal, `7da9c4451540`). Cause: `alive ⟺ fresh brief` is the age of a file the chain
  wrote when it last STARTED, so a session that wedges a minute after launch certifies itself alive
  for 24 h. Predicate replaced (§6, struck-through and superseded there): a fresh brief is now
  NECESSARY, never sufficient, and the successor must be **progressing** — resolved through
  `handoffs.jsonl` → `target_pane` → cc-registry → sid → transcript, requiring both a
  content-bearing assistant turn and a fresh mtime. `CC_DRAIN_CHAIN_MAX_AGE_S` deliberately
  UNCHANGED: the axis was wrong, not the magnitude — shortening it convicts a healthy long recycle.
  **The false-positive guard is half the work:** a `handover-grace` arm keeps the chain ALIVE across
  the blind window at every recycle, where nothing about the successor is knowable yet and this
  plan's own lead once misread a healthy chain as dead (a 42-min brief beside a 1-min ping).
  RED-PROVED both ways against the REAL pre-fix artifact (`git show origin/main:…` replayed via the
  new `CC_DRAIN_SUBJECT` seam): pre-fix the wedge case reads ALIVE, post-fix `dead`/`stalled`;
  21/21 post-fix, and the live box still reads `progressing` (pane 131, transcript 417 s) rather
  than being convicted. All three fail-open guards untouched and still checked first.

- **2026-08-18T22:40Z — lead recycle (pane 102): the three rows this lead FILED but never started
  are now fired, and the capacity refusal that parked one of them was a 2-hour fact, not a wall.**
  Claimed `dc014c6829ac` · `d6d4b85ebd4c` · `7da9c4451540` under `lead-102` BEFORE firing — a claim
  is a lease, so the drain chain cannot pick up a row a dispatched session is already holding, and
  the two lanes cannot duplicate the work. Then one dispatched session each, goals armed and
  read back from each session's own transcript: pane 349 `fix/desk-land-dup-rows`, pane 350
  `fix/drain-chain-predicate`, pane 351 `fix/validate-bash-scratchpad`. All three re-validated
  against the tree at fire time, not against the filing note — `desk-land.sh:148` still builds
  `TMP_WT="$WTROOT/.desk-land-$safe-$$"`, and the assert still answers on fresh-brief alone.
  Custody debts open on all three; this lead does not close until they return.
  - **The park was priced wrong.** `d6d4b85ebd4c`'s fire was refused earlier by the capacity gate
    at load 2.08/core against a 2.0 ceiling, and the lead parked it. At this recycle the box read
    **0.58/core** (5.75 over 10 cores), and 0.77/core after all three fires. A capacity refusal is a
    reading of one minute, and treating it as a property of the work leaves the row parked for as
    long as nobody re-reads the instrument. **Re-measure a park before inheriting it** — the same
    lesson as `parked-blocker-obsoleted-by-later-fix`, arriving through load rather than through a
    mechanism fix.
  - 🚨 **The chain's own alarm was RIGHT this time and still carried zero information — which is the
    third live demonstration of `d6d4b85ebd4c`, and the sharpest.** `drain-chain-assert.sh` answered
    `chain ALIVE (fresh-brief) · 417 live row(s) · newest brief 2950s old`. Recycle #26 *was* alive:
    pid 25405, state `R+`, 6.9% CPU, 49 min elapsed, cwd in its own drain worktree. But the assert
    did not know that and could not have. It read the age of a file #26 wrote when it STARTED, so it
    would have returned the identical verdict had #26 wedged at a modal in its first minute — which
    is exactly how the chain dead-stopped ~4h at recycle #21 with the alarm silent. **An alarm that
    is correct by coincidence has not been tested by the case where it agrees with you.** The lead
    only knew the chain was healthy because it went and read the process; the instrument built to
    answer that question contributed nothing to the answer.
  - **Rate unchanged from the previous entry, so the fires do not change the headline:** live rows
    417, and the growth is still in the operator lane `cc-dispatch` excludes by construction. These
    three rows are agent-lane work — they reduce INFLOW rather than the level: `dc014c6829ac` stops
    every land retry minting a fresh blocked row, and `7da9c4451540` stops the wedge that has cost
    four dispatched sessions in 24h, one of them this very chain.

- **2026-08-18 — drain recycle #26: `master-session-lifecycle` 5 → 4 open / 1 blocked (1
  operator-gated, `source: needs`). filed 0 / closed 1.** Closed `4de3d0f9c0e1` — the repo-keyed
  DoD crosstalk, open across #21/#24/#25, each of which landed real work on it and correctly left
  it open. Landed `63b71c0e` + `a40f5dca3`, content-verified on origin/main (0 unlanded, empty
  path diff, `dod_lineage_record` present in the landed copy). **0 cloud-venue rows in the live
  population.** The 4 remaining are the same set #24 and #25 named as excluded by construction, all
  re-verified live: `62363cac1e39` efficacy re-census due ~2026-08-24 (today 08-18 — the FIRST
  drainable row here once that date passes) · `68fdc99b17c7` blocker `e06ba316a1aa` still OPEN ·
  `b69b1d957cec` standing watch, revisit conditions unmet · `85a82455de9a` not this chain's.
  **This effort now has NO drainable row until 08-24.**
  - **What was left: prerequisite 2 only — a succession lineage token, `--recycle` included.** #24
    landed prerequisite 1 (per-capture provenance) and sized this half without building it; the
    obstacle it recorded was that no `FIRING_CWD`/`TARGET_CWD` exists in the 9.5k-line
    `handoff-fire.sh` to hang it on. **That obstacle dissolved on one measurement**: `LAUNCH_DIR` is
    assigned at exactly ONE site (`:7841-7845`), reached by every dir-changing succession — ordinary
    `--worktree`/`--cwd`, self-routing, and `--recycle --worktree` — and `$PWD` there IS the firing
    session's cwd, because nothing above it `cd`s outside a subshell (the script states that
    invariant itself at `:6449`). One call at one site covers the lot.
  - 🚨 **THE PROOF THAT MADE THIS BUILDABLE: two of the file's own cases were CONTRADICTORY.**
    `dod-path.bats` case 1 (a successor inherits) and case 8 (a concurrent sibling does not) have
    the **same setup** — A freezes a scope, B reads it — and **opposite required answers**. No
    function of that setup satisfies both. So #24's "not buildable from state this tree records" was
    right about the *read* side and could never have been cleverer: the fix was a missing **INPUT**,
    not a missing rule. That is also why case 1 minting the edge in its setup is **not a narrowed
    falsifier** — it supplies the input the case always lacked, and makes case 1 state the invariant
    it always *claimed* (a SUCCESSOR inherits) instead of the weaker "any worktree of the repo
    inherits" it could express before. The un-recorded direction is pinned separately (case 11).
  - **A measurement that shrank the work.** "`--recycle` writes no lineage record" is only ever
    about the RELOCATING form: with no `--worktree`, `LAUNCH_DIR="$PWD"` byte-identically, so the
    toplevel identity is unchanged and there is nothing to record. The writer drops that self-loop
    itself, and a case pins it.
  - **Fail-open is the design, and its cost is pinned rather than left to be found.** A capture with
    no `toplevel=` stamp is unattributable and is ALWAYS inherited, so the filter can only fail
    toward *keeping* the crosstalk, never toward losing a contract you own. The accepted trade —
    a hand-made `claude -w` sibling has no edge, is treated as concurrent, and re-freezes its own
    scope — is case 11, not a footnote. Grandfathering on "the writing toplevel no longer exists"
    was **considered and rejected**: it re-introduces a liveness discriminator the research doc
    already refuted, for a one-time transition benefit.
  - 🚨 **`grep -q` UNDER `pipefail` INVERTS A FILTER'S VERDICT.** `dod_filter_for … | grep -qF` in
    the grown-line dedup: `-q` exits on the first match, the upstream filter takes SIGPIPE, and
    `set -o pipefail` reports the pipeline as FAILED **on the very input it just matched** — a dedup
    that re-appends every grown line forever. Caught by `dod-persist` case 16 because it COUNTS the
    appends. Live form is the count idiom: `n="$(… | grep -c … || true)"; [ "$n" -eq 0 ]`.
  - 🚨 **A STALE `sed` MARKER DOES NOT FAIL — IT INVERTS.** The SessionStart frame said "full
    INTEGRATE-only history"; the filter made "full" false, and `dod-persist` keyed a
    `sed -n "1,/$HIST_MARK/p"` range on that phrase. `sed -n '1,/nomatch/p'` selects the **whole
    input**, so every "…is not above the history" assertion silently widens to the whole document
    and passes by accident. Marker narrowed to its wording-stable core plus `_hist_mark_live`, which
    asserts the marker EXISTS before anything slices on it. Same family as #25's fixture lesson:
    a fixture is a function of the artifact, and editing prose re-times it.
  - **Both of those were caught by the EXISTING suites and fixed in the code, not the assertion.**
  - **Attribution — 9 mutants, one per site, control green before AND after, none uncaught:**
    unfiltered REMAINDER reds case 7 alone · unfiltered injection reds 8 alone · a depth-1 lineage
    walk reds 9 alone · dropping unattributable blocks reds {3,10} · **restoring the pre-fix
    "always keep" reds {7,8,11} — the whole defect** · removing both cycle guards reds 12 alone ·
    recording the self-loop reds 13 + intent-5 · removing the writer call reds intent-4 alone ·
    letting `--dry-run` record reds intent-6 alone. Every mutant ran from an in-memory `cp` backup
    with the text computed BEFORE the file was opened for write.
  - **Verification, all this turn.** `dod-path` **14/14** · `dod-persist` **30/30** · `wrap-ledger`
    **75/75** · `completion-assert` **91/91** · `handoff-recycle-intent` **6/6** — every plan line
    (`1..N`) seen in its own run. `shellcheck -x` rc=0 on all four scripts;
    `bats-assert-liveness-fix --dry-run` clean. `CC_DOD_CROSSTALK_REDPROOF` is **deleted**: a
    permanently-skipped case reports nothing.
  - **`LIVE_ADDS=0` on purpose.** The lineage went into `hooks/lib/dod-path.sh`, already symlinked
    into the live layer, rather than a new lib — an ADDED file has no symlink, is in no tree the box
    can reach, and every `[ -f … ] && .` guard on it is a SILENT skip until the converger runs.
  - **Live layer: `deploy-live.sh` declined again, for the third recycle running and for the same
    CORRECT reason** — no GREEN tree is a descendant of live HEAD `36cbb55eda4c` (the newest green,
    `555e3b270f1e`, is BEHIND it), i.e. the postland-verify stamp has not advanced. Lag **11 / 2h**,
    inside the degrade budget (25 / 6h), `LIVE_ADDS=0`, `MIG_FAILED=0`. **Not this chain's loose
    end** — it predates every commit here and no land can move that marker.

- **2026-08-18 — drain recycle #25: `master-session-lifecycle` 6 → 5 open / 1 blocked (1
  operator-gated). filed 0 / closed 1.** Closed `5cd2ecf792ae` — TWO-WAY MAIL, storyboarded since
  2026-07-30 and the only genuine close candidate left in this effort. Landed `761d41e15` (4
  commits), content-verified on origin/main. The 5 remaining are the 4 #24 named as excluded by
  construction — each re-verified live this recycle: `62363cac1e39` due ~2026-08-24 (today 08-18),
  `68fdc99b17c7` whose blocker `e06ba316a1aa` is still OPEN, `b69b1d957cec` standing watch (npm
  latest now **2.1.235**, we hold 2.1.220, revisit conditions unmet), `85a82455de9a` not this
  chain's — plus `4de3d0f9c0e1`, whose prerequisite 2 remains and is the next drainable row here.
  - **The row's blocking question was RETIRED, not answered.** It asked whether the
    one-saturated-subject rule should be overturned so a second creature need not be drawn SMALLER
    and read as a CHILD. `90ecfac9c` (#22) had already settled that size is second-order to
    CO-PRESENCE — a second creature sharing the frame at all is `gen.py`'s `peer` (v6b), WITHDRAWN
    on its CAUSE — so **the peer is NOT DRAWN**, and the answer arriving from off-frame is THE
    LETTER's own hard constraint used as the point. Built to that composition: `rMail` at
    **39.0-44.5s**, which is FORCED — rAsk ends 35.0, peek/peer open 48.5, `EVENT_GAP` is 4.0s on
    both sides, so the legal interval is exactly as wide as the beat. Prime-window and not the free
    85s after rTrace, because the placement rule inverts by KIND: a narrative beat a reader never
    sees has told them nothing.
  - **A cost recorded rather than discovered later.** That slot was withdrawn `rOverlap`'s
    (36.0-44.25). Its 8.25s cannot coexist with this 5.5s inside a 13.5s gap, so **restoring THE
    OVERLAP is no longer the one-line change `ALWAYS_EMITTED` promises** — noted in `RARE_EVENTS`
    beside both windows.
  - 🚨 **THE LESSON: INK IS NOT DIRECTION, AND ONLY A RENDER CAUGHT IT.** The first cut built
    clean, and drew the beat BACKWARDS. The inbound message's offsets counted UP from the walker
    instead of DOWN to it, so the answer *left* the hand it was supposed to arrive at and exited
    the left of the frame — and at the crossing instant, which is the entire beat, the second
    letter sat occluded inside the silhouette. **Every gate passed**: the flights overlapped in
    time, the lanes cleared each other, the outbound left the frame, every step was a whole pixel,
    and all three `BEAT_INK` probes measured real ink. An ink probe asks whether an element PAINTS;
    it cannot ask whether it paints in the right direction. The remedy is `mail_offsets` — ONE
    definition read by the emitter AND the gate, because a second copy of those numbers is exactly
    what let the inversion through — plus a gate asserting each lane holds one even heading and the
    inbound ends AT the walker.
  - **Adding a beat re-times the loop, and two red-proof fixtures went back to proving their
    neighbour.** `_duty` (over-long window at 39.0-58.0s) and `_two_features` both collided with
    rMail, so the disjointness gate convicted first and both reported the WRONG check. The harness
    caught it only because it compares the MESSAGE, not the exit status — key a fixture on the
    message or it stops being proof the moment the timeline moves. `_duty` is now on its **third**
    re-timing, noted in place. For `_two_features` the obvious repair is wrong: a strip feature's x
    is `STRIP_V * its start`, so moving rOverlap later slides it a whole canvas away and the gate
    stops being able to fire at all — the fixture moves rMail aside instead.
  - **Verification, all this turn.** `banner-verify` PASS 6/6 on all four assets ·
    `banner-beat-ink` 2233/2254/385 px against a 25px floor, **with the pre-change asset as a
    natural 0-ink control** (same probes, elements absent, all three read 0) ·
    `banner-gate-redproof` **PASS 41/41**, including four new `mail:` cases and the five constants
    + the `mail_offsets` FUNCTION added to `sandbox()` (a swapped function leaks exactly like a
    swapped constant — the leak `hop_pulses` is in that list to record) · rendered at 5 timestamps
    across both schemes and the widest and narrowest variants, and looked at.
  - **Instrument note (verify, do not assume).** `banner-shots.sh` IS pixel-deterministic as its
    header claims. Two runs on ONE unchanged asset differ in **file** hash and agree **exactly** in
    decoded pixels — PNG carries a `tIME` chunk. Comparing file hashes to test render determinism
    reads as a regression that is not there; hash the IDAT. This nearly convicted a
    behaviour-neutral refactor, which the SVG bytes then exonerated (all four byte-identical).
  - **A dead guard deleted rather than narrowed.** A duplicate-keyframe-percentage check written
    against `pct`'s 24 ms quantisation was unreachable under `pctx`'s nine decimals: a mutant
    driving the step to 1/40th of a cell — 857 stops — did not trip it. What actually breaks at
    that step is the GRID, so the check moved to where it is reachable, beside
    `assert_summon_on_grid`'s. A guard that cannot fire is a guess.

- **2026-08-18 — drain recycle #24: `master-session-lifecycle` 6 → 6 open / 1 blocked. filed 0 /
  closed 0.** Two lands, no close, and the count is the honest number: of the 6 open rows, **4 are
  excluded by construction and I re-verified each** — `b69b1d957cec` standing watch (npm latest is
  2.1.234, we hold 2.1.220; the revisit conditions are unmet), `85a82455de9a` not this chain's,
  `68fdc99b17c7` whose blocker `e06ba316a1aa` I confirmed still OPEN, and `62363cac1e39` an efficacy
  re-census **not due until ~2026-08-24** (today is 08-18 — running a soak 6 days early buys a
  premature verdict, so it stays). That leaves two, and both are large: `5cd2ecf792ae` (banner beat)
  and `4de3d0f9c0e1` (DoD crosstalk). I worked the second.
  - **What landed.** `dc597de18` — per-capture provenance, prerequisite 1 of
    `docs/research/dod-crosstalk-2026-08-18.md`. The DoD store is repo-KEYED, so 101 worktrees append
    to one file, and `persist_dod` recorded the writing cwd only in the FILE HEADER — i.e. for the
    FIRST writer. Every `## <ts>` block now names its own `toplevel=` (+ `session=` when known,
    OMITTED rather than blank when not). `e215a1416` — the §5 adjacent finding, which §2 measured as
    the **active every session** half: SessionStart framed the whole shared file as *"Every 'Scope
    (frozen):' line below is binding … until ALL of it is met"*, handing each session 15 waves'
    contracts as its own. **It needed no ruling on what "binding" means, because the frame
    contradicted its own store** — `get` and `last_recorded_scope` have always returned the newest
    frozen line only. Now: newest = `THE CURRENT CONTRACT`, the rest labelled `NOT additional binding
    scope`, **LOSSLESS** (full history still injected verbatim).
  - **The row stays OPEN, deliberately.** Prerequisite 2 — a lineage token on the succession paths,
    `--recycle` included, recording the *firing* cwd — is unbuilt, and without it no reader can
    separate a wave from its own successor. `tests/dod-path.bats` cases 7/8 stay skipped. I sized
    prereq 2 and stopped: there is no `FIRING_CWD`/`TARGET_CWD` variable in `handoff-fire.sh` (9k
    lines) to hang it on, and closure needs BOTH consumers filtering too. Do not "fix" this by
    reverting to a per-toplevel key — that re-breaks the worktree hop from the other side.
  - 🚨 **A DEAD-ASSERTION CLASS OUR OWN ANALYZER DOES NOT FLAG, and it cost two wrong diagnoses.**
    Under bats a bare **`! cmd` is live ONLY as a test's FINAL command** — bash errexit explicitly
    does not fire "if the command's return value is being inverted with `!`", so an **intermediate**
    `! cmd` passes whatever the truth is. Mine sat mid-test and passed against a string I then
    *proved present from inside the harness*. Settled by positive control, not by reasoning (`! true`
    as a last line DOES fail). Live form is a count: `n="$(… | grep -c … || true)"; [ "$n" -eq 0 ]`.
    `scripts/bats-assert-liveness-fix.py --dry-run` reports **no dead assertions** on that same file
    — though it DID catch the sibling `A && B && C` form in the first land, and its fixer is the
    right tool there. **Not filed** (this recycle closed 0, and filing would end it net-positive);
    recorded in the doc and memory `negated-assertion-dead-unless-final`. Widening the analyzer was
    deliberately not attempted in passing — it gates every land.
  - **Method that paid.** Per-site mutants, one per case, both directions: M1 no-stamp → reds 20-24;
    M3 blank `session=` → **23 alone**; M5 first-writer memoization (the precise §4.1 defect) →
    **24 alone**; M4 stamp-makes-a-`- [ ]`-box → reds the reader-neutrality CONTROL, which is what
    proves that control can fail at all (it passes pre-fix by construction). M2 reverted the stamp
    outright and isolated nothing — an over-wide red indicts the MUTANT.
  - **Two traps paid for.** `open(SRC,"w").write(mutate(...))` TRUNCATES before the assert runs, so a
    missed anchor leaves an EMPTY subject — compute the mutated text FIRST (restored from the `cp`
    backup, verified by `git diff --stat`). And the converge recipe in the brief is **stale**: a
    `git pull --rebase` in the shared checkout is now DENIED by a guard ("ungated advance … creates
    no symlinks"); `scripts/deploy-live.sh` does the advance itself.

- **2026-08-18 — drain recycle #23: `master-operator-gated` 2 → 0 open / 50 blocked. filed 0 /
  closed 2.** Picked this effort over `master-session-lifecycle` (6 open) because the fold showed it
  cheaper, per the goal's own "or whichever effort the fold shows cheaper". Landed `070f205de`
  (content-verified on origin/main, then **converged LIVE** by content: `~/.claude/scripts/
  land-content-verify.sh` carries the fix; the diff ADDS no file, so no add-breach). Blocked tail BY
  STRATUM: 50 rows — 49 `source: needs` operator-platter rows and 1 `source: session-a28e8b9c`;
  **0 cloud-venue rows in this effort.** No stale claim left (both claimed rows were closed).
  - **The two rows were `re-land …` predictions that had come TRUE, and their own falsifier could
    not say so.** `25337307a1a8` (reland/goal-wake): the stored probe exits 0 this moment — all 6
    paths on trunk, which is strictly ahead. `515cfb4cd736` (reland/drain-chain): every path landed
    by content — `scripts/drain-chain-assert.sh` and `tests/drain-chain-assert.bats` byte-identical
    to trunk, the calling arm live at `scripts/autonomy-sweep.sh:832-834`, the §6 case at
    `tests/autonomy-sweep.bats:1144` — yet the probe still convicted it.
  - **THE FINDING, and it is a generator not an incident: `diff` is POSITIONAL, so a line that
    landed at a NEW OFFSET reads as a strand.** The oracle's existing rescue arm asks whether trunk
    once carried the ref's whole-file BLOB; the case that actually occurs is trunk carrying the
    ref's LINES elsewhere and never that blob. The miss is **systematic for the file class this repo
    mandates everywhere — INTEGRATE-only, newest-first logs**, where landing an entry at the top
    while the ref appended at the bottom re-positions every line. Measured on this very plan file:
    reported as "19 line(s) present only in the ref" while all 18 non-blank ref-only lines were on
    trunk VERBATIM (`grep -qxF --` each, 0 absent). Because ship-land wires the script as a
    FALSIFIER and a falsifier retracts only on exit 0, both rows were **structurally unable to
    retract** while reading as mechanised.
  - Fixed by a **MULTISET** superset arm (`trunk_covers_every_line`), never a set one: a set test
    forgives a LOST DUPLICATE, which is a real strand. Three per-site mutants, each reddening only
    its own case: set-instead-of-multiset → case 24 alone; forgive-everything → the 6 strand
    controls incl. 3 pre-existing; arm-absent → case 23 alone. Suites run with the plan line seen —
    `tests/land-content-verify.bats` `1..25` (25 ok, 0 not ok) and the consumer
    `tests/ship-land.bats` `1..143` (143 ok, 0 not ok).
  - 🚨 **The fix did NOT launder either row closed, deliberately.** Post-fix the drain-chain ref
    still exits 1 — 2-of-5 paths became 1-of-5, the plan file correctly reclassified RELOCATED, and
    `scripts/autonomy-sweep.sh` still convicted because its 6 residual lines are a
    **superseded-by-REIMPLEMENTATION** variant: the ref's `case $0 in $_cc_cfg/*` glob, which trunk
    replaced at `:946-947` with an exact-match test *because the glob also matched the verifier's
    own throwaway worktrees*. **Actioning that row's prescribed `run` would have re-applied a
    regression to trunk.** The rows were closed on independently verified content evidence, not on a
    narrowed probe. **Residue for a successor: reimplementation-supersession is not decidable by any
    content oracle** — trunk holds neither the blob nor the lines — so that row class needs a
    different EXIT, not a smarter falsifier.
  - Instrument notes paid for this recycle: a `grep -qxF "$l"` where `$l` begins with `-` is parsed
    as an OPTION and the check is blind — use `grep -qxF -- "$l"`; and a `hash-object`/`rev-parse`
    identity check compares EMPTY to EMPTY when the path is malformed, which renders as IDENTICAL —
    print both hashes. Converging also required moving 2 untracked files aside in the shared
    checkout (both byte-identical to the incoming adds, both restored identical by the pull);
    `pull --rebase` ABORTS on such a collision rather than reporting a stale live layer.

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

  **Amended ~21:00Z with the RATE, which is the half that actually settles it.** A snapshot cannot
  say whether a pile is draining, so the 24 h event flow was measured off the store directly:
  **`done 108 · add 68`** — the agent lane is **net-draining, −40** — against **`block 153 ·
  unblock 46`**, a **3.3:1** accumulation into blocked (down from the ~6:1 this session inherited,
  and `reopen 20` is the third term nobody counts). So the live-row count creeping **412 → 417**
  across one afternoon is **not the chain losing ground**: closures beat filings, and every bit of
  the growth is in the lane `cc-dispatch` excludes by construction. **"Drain to zero" is therefore
  unreachable by the agent lane alone** — it is gated on the operator lane moving (13 runnable via
  `cc-do`, 145 needing a call), which is exactly what the `OPERATOR ▸` block already renders. Two
  independent samples agree on the composition: recycle #23 closed `master-operator-gated` at
  `0 open / 50 blocked` with **49 of the 50 operator-platter**, reached over a different slice by a
  different session. **A pipeline's health is a RATE, and a rising total is not evidence against
  it** — read the flow before diagnosing the level.

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
- ~~The chain is alive ⟺ a fire-drain-recycle-N brief younger than 24h exists OR a drain session
  holds a live lease~~ — **THIS INVARIANT WAS WRONG AND IS SUPERSEDED (2026-08-18, backlog
  d6d4b85ebd4c). Kept struck-through, not deleted: the detector below implemented it faithfully,
  and it is the invariant itself that could not see the failure that happens.** A recycle brief is
  authored by the predecessor and stamped when the successor is FIRED, never while it works — so
  "a brief younger than 24h" is THE AGE OF A FILE THE CHAIN WROTE WHEN IT LAST STARTED, satisfied
  identically by a chain that is draining and by one that wedged sixty seconds after launch.
  Measured cost: `scripts/drain-chain-assert.sh` filed ZERO `local-drain-chain-dead` rows at any
  status across its entire deployed life, including the ~4 h dead-stop at recycle #21 when pane 131
  wedged on a `rm -r /tmp/_ce` PreToolUse modal (backlog `7da9c4451540`). The magnitude was never
  the defect and `CC_DRAIN_CHAIN_MAX_AGE_S` is deliberately unchanged — shortening the window only
  convicts a healthy long recycle. **The replacement:**

      alive ⟺ zero live rows (`drained`, the terminal SUCCESS state)
            ∨ the chain fired inside CC_DRAIN_HANDOVER_GRACE_S (`handover-grace`)
            ∨ somebody holds a live lease (`live-lease`, any holder — Lane A counts)
            ∨ the session that brief was fired into is STILL EMITTING (`progressing`)

  A fresh brief is now NECESSARY and never SUFFICIENT: brief-fresh-and-nothing-progressing is
  precisely the wedge and reads `dead`, with the `why` naming which dead state it reached
  (`no-brief-no-lease` · `stalled` · `unverifiable`). Progress is resolved newest brief →
  its `prompt_file` row in `handoffs.jsonl` → `target_pane` → the cc-registry row → `.session_id`
  → `<sid>.jsonl`, and requires BOTH a content-bearing assistant turn (`assistant_turn_in`, sourced
  from `hooks/lib/engagement.sh` rather than re-spelled) AND an mtime younger than
  `CC_DRAIN_PROGRESS_MAX_AGE_S` — mtime alone calls a newborn transcript alive (*birth is not
  engagement*), and the turn-check alone is the old bug one level in, because the wedged pane HAD
  taken real turns before it froze. The **handover grace** is the false-positive guard the fix
  cannot be shipped without: between the fire and the successor's first turn nothing about it is
  knowable, and that is the state of a healthy chain at EVERY recycle — the lead that filed this
  row misread exactly that window once (a 42-minute-old brief beside a 1-minute-old ping). It is
  bounded, because a wedged successor fires nothing and its brief ages out of the grace.
  All three fail-open guards are untouched and are still checked BEFORE the progress arm: an
  unreadable store answers `skipped`, an empty pile answers `drained`, any live lease answers
  `live-lease` without the successor having to be identified at all.
  **IMPLEMENTED 2026-08-16** → `scripts/drain-chain-assert.sh`, called from `autonomy-sweep.sh`
  § 2b-v (`drain_chain_rc` in the `backlog-health` IDL row), pinned by
  `tests/drain-chain-assert.bats`. Ask it directly with `drain-chain-assert.sh --json`; the row it
  files carries `--assert` as its falsifier and retires itself when the chain restarts. Zero live
  rows reads ALIVE (`why=drained`) — that is this invariant's terminal success state, not a
  silence to be alarmed about, and the distinction is what keeps the detector from becoming the
  store's next generator.
- Weekly report: adds vs closes; net-positive week ⇒ the INFLOW list (C1-C4) gets the next
  fix, not more drain horsepower.

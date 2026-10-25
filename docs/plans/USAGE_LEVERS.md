---
status: in-progress
---

# Usage levers — getting more work from the same 4 Max 20x accounts

Scope (frozen): act on the verified usage-efficiency levers surfaced by `claude -p /usage`
(research: `docs/research/usage-levers-2026-10-23/REPORT.md`, round 2 in `round2/REPORT.md`),
implementing what clears 90% conviction and running the one cheap test each remaining lever needs,
each wave landed via `/ship` and converged live.

Scope (grown, 2026-10-24): **operator ruling — yes to all four recommendations** of
`docs/research/usage-levers-2026-10-23/decisions-2026-10-24/TESTS.md` (idle recycle at 200k after 15
idle min with guards `43da49891e75`; Workflow block-once `a4c54d1744d1`; busy-scoped keepalive
`c0f9d5368147`; subagent poll-loop deny `3df527edd333`), **plus telemetry and a hillclimb loop**
(method: claude.dev "Automating eval design and hillclimbing") that quantifies each change's net
impact so it is rolled back or continued on evidence. Packets close with `cc-decide action` as each
change lands. Design: § "W7+ — telemetry, hillclimb and the approved switch-ons".

## Phase 0 — Agent Team Orchestration — DONE (W0–W4, W6 fired and landed 2026-10-24; remainder is W5)

**Execution locus per wave**

| Wave | Locus | Why (T/L only) |
|---|---|---|
| W0 research + this plan | L | docs only, already in the lead's hands; no code |
| W1 binary pin + "reads are free" doc reword + log-only Workflow shadow hook | S | — |
| W2 cache-read quota probe | S | — |
| W3 idle-cache redesign (shadow mode) | S | — |
| W4 context-recycle thresholds | S | — (gated) |
| W5 switch-on decisions from shadow logs | S | — (gated; earliest 2026-10-31) |

**Task size per unit:** 40–150K output tokens (≈30–75 min, 3–6 files). W1 is three small tasks in
one unit because each alone is under 20K; W2 and W3 are one task each.

**Team / roles:** each S session leads its own team only if it ends up touching 2+ independent
files sets; W1's three tasks are disjoint files (bin/cc-notify; docs + two script headers; one new
hook + its bats) so it may run them as three teammates.

**Dependency graph**
- W1, W2: no blockers — fire in parallel.
- W3: blockedBy W2 (decides which weighting the break-even uses); its Phase-0 counts may run now.
  W2 DONE 2026-10-24: meter weights apply.
- W4: blockedBy W2 (only worth doing if cache reads are charged — round 2 says 90%, one short).
  W2 DONE 2026-10-24: charged (98%), W4 unblocked.
- Deny-mode Workflow hook: blockedBy W1 shadow data (3 days from when the operator runs migration
  0078, which registers the hook; the earlier ≈2026-10-27 assumed it would register itself).

**Worktrees:** one per S session, branch `usage-levers-w<N>`, created by `handoff-fire.sh --worktree`.

**Spawn order:** W1 ∥ W2 now → W3 after W2 reports → W4 after W2 reports, if charged.

**Lead context budget + succession point:** the lead holds ≥50% of its window for deciding; it
recycles (`handoff-fire.sh --recycle`) once W1 and W2 have reported and their results are folded
into this plan, or at 35% fill while idle, whichever comes first.

## W0 — research + plan — DONE (`5b52c6fab`, 2026-10-24)
- `/usage` is free and diagnostic, not a saving; it double-counts subagent transcripts copied
  between accounts (next4 7-day requests ~46% high).
- Ranked levers and the binary hazard: `docs/research/usage-levers-2026-10-23/REPORT.md`.
- Round 2 convictions: cache reads charged 90% (weekly ≈0.0048 pp/Mtok on Opus 5.5, 28–35% of the
  meter); lean enforcement 65% (saving ≈3–4%/week, not 5.2%); idle-cache fixes 60% (both fixes as
  first written are wrong). Dropped: skill-listing trim, watcher timeout wakes, peer-message
  batching (each <1%).

## W1 — binary pin, doc reword, Workflow shadow hook — DONE (2026-10-24)
Landed `b6c6b8e9f` (pin), `2086f6774` (reword), `baf1c3185` (shadow hook), `75a74ae8b` (stubs via
`cc_stub`); the migration renumber and its guard land with this plan update. Converged live.
1. **Binary pin.** `bin/cc-notify` (`--cloud`), the research router's fast classifier call and
   `scripts/rm-preempt-probe.sh` now ask `bin/cc-claude-bin` first and fall back to PATH;
   `CC_CLAUDE_BIN` unchanged. Bats in `cc-notify.bats` and `research-router.bats`, each red on the
   pre-fix code with an older `claude` first on PATH.
   - Learning: the router resolves once per process and BEFORE both cold calls start. Resolving
     lazily inside the fast call (+30 ms) let the careful stub answer first and cancel it, which
     reddened "the real classifier call" test.
   - Learning: in a test with a fixture `$HOME` and no zshrc pin, `cc-claude-bin` falls to rung 3,
     the REAL `~/.claude/bin/claude-latest`; a PATH-stub test must also set `CC_CLAUDE_BIN`.
   - The resident classifier daemon keeps its old fast binary until its next restart: the fast
     binary is not part of `classifier_config()`'s id, so nothing restarts it.
2. **Doc reword.** All six sites now say "discounted, ≈0.005 pp/Mtok weekly on Opus 5.5" with a
   dated CORRECTED note; the 0.049 bound constant stays.
3. **Shadow hook.** `hooks/workflow-lean-shadow.py`, log-only, to
   `~/.claude/logs/workflow-lean-shadow.jsonl`: per `agent()` call the verdict (`has-agent-type`,
   `would-deny`, `keep-default` when the brief names commit/ship/Skill/MCP, `unknown` when the brief
   or options are not static), the rewrite, the markers, and wall/CPU latency. Kill switch
   `CC_WORKFLOW_SHADOW=off`. Registration is c10 migration
   `0078-workflow-lean-shadow-registration.sh`, operator-run; the shadow clock starts when it runs.
   - Learning: W3 landed its own `0077` the same hour, and a `mig 0077` test glob then ran the
     wrong file. Renumbered to 0078; `deploy-migrations.bats` 3b now refuses a duplicate number
     (0009/0016/0021/0055 grandfathered: renaming them would change their ledger keys).
   - Learning: the land's smoke selector answered FULL ("cannot decide"), so the land ran no
     suite; every touched suite was run by hand (cc-notify 1..112, research-router 1..69, hook
     1..3, c10 1..9, all 0 not ok).
- Next: deny-mode decision reads ≥3 days of that log after 0078 runs.

## W2 — cache-read quota probe — DONE (2026-10-24): reads are CHARGED, 98%
- Ran on next3 from a next session: 1,149 tool-free `-p` calls re-reading one 458,656-token cached
  context (1h tier, 0 writes in the window) = **527.0M cache reads**. Meters, baseline → after:
  5h **1 → 21** (wire), weekly **12 → 16** wire / **13 → 16** endpoint, so +3 to +4pp. "Free" predicted
  +0.006 / +0.001pp. The only other live next3 session added ≤0.07pp 5h in the window.
- Weights at large context: 5h ≈0.038 pp/Mtok (≈1.9× round 2), weekly 0.0057–0.0076 pp/Mtok
  (≈1.2–1.6× fit4's 0.0048). Open confound: the context was above 200k, so the excess may be a
  long-context premium. A same-size probe below 200k would split it (≈0.7pp weekly, not run: cap reached).
- Spent ≈3–4pp of next3's week (stopped by the 4pp guard on the final batch). Decision 1: 90% → 98%.
- **Unblocks:** W4 (its gate was "reads charged"); W3 uses round 2's meter-weight branch, with reads
  ≈1/32–1/43 of a cache write, not 0.
- Report, readings table, scripts and data: `docs/research/usage-levers-2026-10-23/round3-probe.md`,
  `round3/`.

## W3 — idle-cache redesign, shadow mode — DONE (2026-10-24): shadow live; switch-on decision due ≈2026-10-31
- Landed `af0043319` (keepalive + gap ledger + migration 0077), `d9ffc3964` (subagent count-only
  rule), `5982877c4` (read-out); converged live the same day. Nothing wakes and nothing denies.
- **Gap ledger (live now):** `hooks/cache-expiry-tracker.sh`, already on Stop, runs
  `hooks/lib/idle_gap.py`: one row per main-session idle gap in `~/.claude/logs/idle-keepalive.jsonl`
  with duration, context at the gap start, what the first request after it paid (`obs_cw`, so the
  1 h TTL is checked, not assumed), and the priced outcome of one wake at gap start + 3300 s.
  Round 3 weights; break-even ≈2.7–3.5% of woken gaps must be rescued. Non-interactive sessions skipped.
- **Timer (needs 0077):** `hooks/idle-keepalive.sh`, its own asyncRewake Stop group, so the
  `mailbox-wake-arm.sh:203` claim guard cannot suppress it; logs a would-wake row (with
  `watcher_armed`) and exits 0, which asyncRewake cannot turn into a wake. Registration is
  operator-owned: backlog `63335887df76`, `migrations/0077-…--confirm settings.json`.
- **Subagent rule (live now):** `hooks/subagent-long-bash-shadow.sh`, piped by `validate-bash.sh` only
  for a subagent's foreground call with a timeout; logs broad (timeout > 270 s) and narrow (poll loop,
  sleep ≥ 270, waiter, long runner, with `why`) to `~/.claude/logs/subagent-long-bash.jsonl`.
- **Read-out:** `cc-idle-cache-readout [--days 7]`: per account and day, would-wakes and net pp; the
  subagent rows joined to real runtime and next-request cache write, priced per class and as
  first-offense-per-agent, with the ACCEPT line against the 0.2% bar.
- Switch-on decision after ~7 days of logs: keepalive wake mode if net pp is positive per account
  and timer rows match long gaps; subagent deny only for the classes the read-out prices under 0.2%.
- Known, not mine: `tests/validate-bash-differential.bats` was already red on the base (its site
  fixture predates the hook's current line numbers).
- Cause (reproduced): the mailbox watcher (`--timeout 14340`) exits silently on timeout, and the
  3300 s wake floor stands down while that hook is registered (`hooks/session-continue.sh:688`);
  a keepalive added beside it does nothing because `mailbox-wake-arm.sh:203` exits when a watcher
  is armed. Prototype: an idle-scoped keepalive timed from the gap start, waking about once per gap.
- Subagent rule: a blanket deny on Bash `timeout > 270 s` would hit 5,941 harmless calls to save 250
  rebuilds; narrow it, run it as count-only for a week, accept only if wrongly denied calls cost
  <0.2% of weekly usage.

## W4 — context-recycle thresholds — DONE (2026-10-24): 150k after 15 idle min, ≈19.7 pp/week; operator ruling pending
- Brief (kept): only if W2 confirms reads are charged. Main sessions run a 1M window at median 231k /
  p90 459k; the recycle rails act at 250k–750k. Do not force busy sessions to drain; the candidate
  is an earlier idle recycle. Estimated 3–8.5% of weekly usage.
- **Result** (`627abfe27`, report `docs/research/usage-levers-2026-10-23/w4/REPORT.md`): 14 days,
  1,679 main sessions on all 4 accounts, 0 cross-account duplicate requests. Recycling at a turn
  start after ≥15 idle min at ≥150k context saves **19.7 pp of weekly quota per week fleet-wide**
  (17.4–21.8 across round 3's read weights; next 4.0, next2 6.4, next3 4.4, next4 5.0), **0.31 extra
  recycles per session** (max 5). The stated 35%/25% practice fully applied: 9.1 pp/week. Almost all
  of it is later requests at lower context; panes that never resume cost −1.6.
- **Learnings.** (1) A session waiting on its own background job is not idle: ignoring that doubles
  the answer (41.1). Job intervals come from launch → `<task-notification>` (first written as a
  `queue-operation` record). (2) Past 55 min the saving collapses (the 55-min wakes split gaps, and
  the handoff turn must rewrite its context), so N must stay ≤55. (3) Re-prime = median first request
  of a fresh session, 43.8k written + 14.8k read; successors grow no more in their first turn than
  fresh sessions. Unpriced: rework after a successor's first turn — why K stays at 150k, not 100k.
- **Shipped log-only** (`d2742f48c`, live): `hooks/boundary-handoff.sh` "IDLE-RECYCLE SHADOW" logs
  each Stop's preceding idle gap to `~/.claude/logs/idle-recycle-shadow.jsonl` with `would_advise`;
  no advisory, IDL row or latch changes (`tests/boundary-handoff-idle-shadow.bats`, 4/4, red on base).
  Expect ≈38 would-advise turns/day.
- **Decision `43da49891e75`** (class C, conviction 75): keep 25/35% vs 150k after 15 idle min.
  Acting on it also needs a wake at idle minute 15 (W3's idle keepalive), since an idle pane runs no hook.

## W5 — switch-on decisions from the shadow logs — PENDING (gated; earliest 2026-10-31)
Nothing here is drivable before its gate; checked 2026-10-24 with all of W0–W4 on trunk.
- **Operator gates, filed:** migration 0077 registers the idle keepalive (backlog `63335887df76`);
  migration 0078 registers the Workflow shadow hook (backlog `25661bbbd8fc`); neither had run on
  2026-10-24 (no `workflow-lean-shadow.jsonl`, neither hook in `~/.claude/settings.json`). The W4
  ruling is decision `43da49891e75`.
- **Readouts, once their data exists:** (1) keepalive wake mode, from `cc-idle-cache-readout --days 7`
  over the gap ledger (rows since 2026-10-24) plus timer rows after 0077; (2) subagent long-Bash deny,
  per class, against the 0.2% bar, same read-out; (3) Workflow deny mode, from ≥3 days of
  `workflow-lean-shadow.jsonl` after 0078; (4) idle recycle at 150k/15 min, from
  `idle-recycle-shadow.jsonl`, only after `43da49891e75` is ruled yes.
- Backlog `fa0304864f4e` (this plan) is parked not-yet-true until 2026-10-31.
- **Update 2026-10-24 (later):** both migrations ran (0077, 0078 verified in `~/.claude/settings.json`;
  backlog rows closed). The ruling inputs changed — see the next section.

## Decision re-research (2026-10-24) — receipt `docs/research/usage-levers-2026-10-23/decisions-2026-10-24/REPORT.md`
None clears 90%; all are sign-off class. Replay of the shadow logic over 14-30 days of history:
- **Idle recycle** (`43da49891e75`, 75 → 65): recommend **200k/15 min**, not 150k (net ≈+11.1 vs
  +9.7 pp/week). Successors start at 78k, not 59k; orientation + handoff turns cost ≈6.6 pp/week at
  150k. 150-200k holds 15 of 19 context-dependent operator replies. Guards G1-G6 (busy test by the
  launching tool, activity resets the clock, brief carries the final message + open questions,
  pending-question hold, lazy orientation, 7-day fixed shadow) are prerequisites.
- **Workflow deny** (packet filed 2026-10-24, 25-55%): not yet. On 2.1.293 lean saves 39-43k prefix
  tokens, not 91-113k; deny turns negative if lean needs ≥1.33x turns. The bigger, hook-free lever is
  the agentsync b13 round template (≈+9-10 pp/week while that loop runs; no b13 run on 10-24).
  A deny on a resumed run re-runs finished slots (18 runs, 72-78 pp over 30 days): the shadow must log
  `resumeFromRunId`. Never auto-rewrite (48 of 275 would-deny runs needed Skill/MCP/commit).
- **Keepalive wake** (packet filed, 65%): keep log-only; today an `away_summary` record ~190 s into a
  gap ends 52% of timers, and only 47% of rebuild gaps get a timer. Redesign busy-scoped first.
- **Subagent long-Bash deny** (packet filed, 68%): deny only the poll-loop class; the message must say
  foreground `timeout 260 bash -c …`, never `run_in_background` (trips the /goal gate; 86 of 798 poll
  loops ran under a goal); exempt commands with an inner timeout < 300 s.

## W6 — make the shadows measure correctly — DONE (2026-10-24): landed `1b3a9b3dc`..`809299a35`
Scope (frozen): items 1-4 below exactly as listed; everything log-only, settings.json unchanged.
- **Landed:** (3) `1b3a9b3dc`, (2) `473e5f109`, (1) `6897f9eb2`, (4) `809299a35`; each change has
  a bats case that fails on the base (RED-proof lines in the four suites).
- **New shared reader** `hooks/lib/session_jobs.py`: background-job intervals by launching tool
  (bg Bash / Agent / Workflow / harness-moved foreground Bash; Monitors and cc-await-ping are
  watchers with deadlines), and the G4 pending-question test. Used by items 1 and 4.
- **New log fields, for W5's readouts:** keepalive wake rows v2 `busy`, `busy_kinds`,
  `watcher_fires_before_ttl`; Workflow rows `resume_from_run_id`, `script_sha`, `repeat_in_session`,
  slot `needs_default`; subagent rows v2 `would_deny_class`, `exempt`, `inner_timeout_s` (exempt rows
  are `narrow:false`, so `cc-idle-cache-readout`'s narrow/ACCEPT numbers already exclude them; its
  `by_why` table still keys on `why`); IRS lines `would_advise_k2` (200k), `busy_tool`,
  `pending_question`/`pq_why`, `guarded`/`guarded_k2`.
- **Learning:** the poll-loop pattern missed loops opened by a quote (`bash -c 'until …'`), the very
  form the proposed deny message recommends; widened in item 3.

Every item stays log-only; none wakes, denies or changes an advisory.
1. `hooks/idle-keepalive.sh`: end a gap only on a new user/assistant record (not `away_summary`);
   log whether the session's own background job was running and whether a watcher would fire before
   the cache TTL, so the busy-scoped redesign can be read from the log.
2. `hooks/workflow-lean-shadow.py`: log `resumeFromRunId`, script sha, repeat-in-session, and honor a
   `needs-default` marker in the would-deny verdict.
3. W3 subagent rule (`d9ffc3964`): split would-deny by class (poll-loop / long-runner / waiter) and
   exempt an inner timeout < 300 s in the count.
4. `hooks/boundary-handoff.sh` idle-recycle shadow: log `would_advise` at 200k as well as 150k, plus
   the G1 busy test and G4 pending-question flag, so the 7-day shadow week answers decision 1.

## W7+ — telemetry, hillclimb and the approved switch-ons

**Phase 0 for this stage.** Execution locus: **S for every wave** (one dispatched session per row
of the wave table in §4 below, each leading its own team when it touches 2+ independent files).
Lead: the recycled successor of the origin pane (`b287d693`), which fires waves, awaits pings,
verifies landings by content and folds results into this plan; it writes no code (L/T: none).
Size band: each wave 40–150K output (the table's "Out" column). At most 6 waves in flight;
dependencies per the "Needs" column; first fire: S1 and S7a in parallel. Lead context budget: hold
≥50% for deciding; succession point: recycle the lead at 35% idle fill or after S6 lands,
whichever comes first. Receipt for every number below:
`docs/research/usage-levers-2026-10-23/telemetry-design-2026-10-24/`.

Synthesis: option C's staged canary and control plane (judged best on detection 7/7 and rollback 9/9), plus B's offline evals and judge rules (fidelity 9/9), plus A's lineage resolver and plumbing gate. Number tags: [NF] measured by /tmp/lev-design/noise-floor/scripts/{eventmde,cuped,stats,meter}.py over 28 d; [A] /tmp/lev-design/option-a-session-ab/{cluster_mde,d1_perreq}.py; [C] computed by /tmp/lev-design/option-c-staged-canary/stage_mde.py from the NF SDs; [INV] /tmp/lev-design/telemetry-inventory/{au,shadow}.py; [B] /tmp/lev-design/offline-evals-b/{shadow_now,d1_pool}.py; [R] measured in the synthesis pass (`ls -la ~/.claude*/settings.json`, `ls migrations`, grep of config/store-bounds.manifest, scripts/rotate-autonomy-logs.sh and bin/cc-reaper). "est." = estimated, with the method stated.

### 1. Answer first
**What gets built:**
- (a) **One control plane.** `~/.claude/state/levers/flags.json` is read at every hook call, and again at idle-keepalive's due time. A guard can only lower a lever, and a dead-man switch drops everything after 30 min without a guard heartbeat.
- (b) **Hash arms per lever, never per account.**
- (c) **`cc-lever-score`.** It prices every eligible event in both arms from deduped transcript tokens (pp/Mtok: read 0.0057-0.0076, write 0.245, output 0.404) and keeps a ledger per session.
- (d) **Offline evals built from production transcripts.** Graders are programmatic first; Sonnet judges only what code cannot check.
- (e) **An auto-rollback daemon.**

**Why it can tell + from −:**
- Arms run at the same time as their controls, because drift between weeks (13-20%/wk [NF]) is larger than any lever's effect (0.35-2.8% of the fleet [NF]).
- Outcomes are priced per event, because the meter cannot split arms. It reads in whole percents, a sweep runs every 444 s (median), and dozens of sessions share each account's meter [INV au.py].
- Each lever is decided only by an instrument whose measured noise floor (MDE) is strictly below its smallest improvement acted on (SIA):
  - **D3:** decided online, per gap. Context-only MDE is 2.85 pp/wk at 28 d with a 50% share [C], below SIA 3.0, which is below the expected 3.9-5.1.
  - **D1:** decided by chain accounting per recycle, with the model checked against control-arm continuations, plus an offline eval of successor behaviour. Comparing session outcomes is ruled out: MDE 14.4 pp/wk at 4 wk against 8-11 expected [C].
  - **D2:** decided by an offline paired eval plus online compliance. There were 73 Workflow sessions in 28 d, and the per-session MDE is 89% [NF].
  - **D4:** must first pass a population gate. Today there are 0 would-deny poll-loop rows; all 36-51 poll loops are exempt by their inner timeout (INV shadow.py; B shadow_now.py; a judge's count over the last 400 rows). Expected verdict: PARK.
- Guards catch only large harm (tool errors +41% relative, failed lands +73% relative, at 7 d and 50/50 [NF]). They trigger rollbacks and never count as evidence of a gain.

**Verdicts:** ADVANCE or KEEP, REVERT, PARK, NOT-MERGED (within noise, never merged), PLUMBING (no verdict).

### 2. Per decision
**Common to all four levers:**
- **Stage ladder:** S0 shadow (pct 0, arms computed, both arms logging), then S1 10% (tripwires and compliance only), then S2 50% (decides at pre-registered looks), then S3 100% minus a holdback.
- **Salt:** fixed per lever across stages, so 10% ⊂ 50% ⊂ 100%. It is rotated after a trip. Only the operator raises a stage.
- **Before S2:** the S0 pseudo-salt A/A must show a false-positive rate in [2%, 8%] and an MDE at the final look below SIA. Otherwise the savings verdict is offline-only and the lever runs online under guards only.
- **Looks:** Haybittle-Peto bounds, |z| ≥ 3.0 at interim looks and 1.96 at the final. Interim MDEs are therefore ×1.37 (est.: (3.0+0.84)/(1.96+0.84)).
- **ADVANCE** iff all hold: CI lower bound > 0 at the look's bound at both read-weight ends; point estimate ≥ SIA; the offline replay agrees in sign; no guard breach; plumbing clean.
- **REVERT** iff the CI upper bound < 0 or any guard breaches. Maximum dwell reached with the CI still spanning 0 → NOT-MERGED, back to pct 0.
- **Pooled, not split:** the switch-on look is pooled. Nothing was tuned on that data, and splitting it would push D3's 28-d MDE to 4.0 (est.: 2.85×√2), above SIA. Train/test applies to every hillclimb round (§3).

**D3 c0f9d5368147 — busy-scoped keepalive with watcher skip**
- **Metric:** per gap episode, the pp of the wake turn(s) plus the first request after the real return. Fleet pp/wk = Δ × eligible gaps/wk. All gaps of 55 min or more run 906/wk [NF]; the busy-scoped count is measured at S0.
- **Arm:** one per gap episode (`sid:gap_start`, salt_D3).
  - CI: cluster bootstrap by session, stratified by account. Its width must sit within 20% of the pseudo-salt A/A SD.
  - Results are reported split by D1 arm. There is one wake per gap across all levers.
  - The return_s covariate is used only if KS p ≥ 0.05 and |SMD| < 0.1. With it, MDE is 1.48 / 1.05 / 0.74 at 1 / 2 / 4 wk [C], and the day-7 interim MDE is about 2.0 (est.: 1.48×1.37).
- **Offline:** a programmatic replay of 3,625 main gaps over 28 d [NF] through idle_gap.outcome()/gap_costs().
  - It must reproduce recompute.out's 3.79 / 2.67 and 5.07 / 4.23 within ±5%.
  - Perfect foresight must score at least every policy; never-wake must score 0.
- **S0:** at least 7 d of v2 gap rows (earliest 2026-10-31), and timer coverage of at least 80% (47% today [C]).
- **S1:** 3-7 d, ending at 20 fired wakes. It trips on any of:
  - a second wake in one gap;
  - a wake with busy=false, or in a headless session;
  - a wake with no completed turn within 10 min;
  - median wake cost > 0.012 pp (2× the measured 0.0060, n=943 [C]);
  - a Wilson lower bound above 30% on the share of wakes that make the model act.
- **S2:** looks at d7, d14 and d28; SIA 3.0 pp/wk.
- **S3:** 95% with a 5% holdback. Its rolling 28-d check catches only reversals of 6.5 pp/wk or more (1.7 with return_s) [C].
- **Kill:** `cc-lever off D3`. Harder: `CC_IDLE_KEEPALIVE=off` (c10), or a forward revert through /ship.

**D4 3df527edd333 — subagent poll-loop deny**
- **Metric:** per target call, the pp from the call to the agent's first request after the external wait, including slices, re-issues and the deny round trip. It is scored on input-side classes, because agent output is mostly imputed (subagent output in 1 d: 112,559 recorded vs 2,170,057 after imputation [A: `cc-token-ledger --since 1d`]). It is re-priced at a write weight of 0.20.
- **Arm:** one per agent_id, with CIs clustered by session. The 4-wk MDE lies between 1.34 (per call) and 8.12 (per session) pp/wk [A cluster_mde.out]; the S0 A/A measures it at the agent unit.
- **First:**
  - the fixed message: a non-wait branch, `echo rc=$?`, and repeat the slice on 124;
  - a wider pattern (`select(undef`, `time.sleep(`), run in shadow only;
  - cross-account copies owned by the earliest file (the cc-token-ledger rule).
- **Offline:** a replay of 3,730 poll-loop calls from 28 d [C] through the real hook, with its log redirected (the replay_pred.py method).
  - Grader: programmatic precision and recall against is_wait labels (20 read by hand, plus a Sonnet labeller on 100, κ ≥ 0.8).
  - Compliance model runs (about 1.2 pp per variant, est. B) only after the headroom check passes.
- **Population gate:** at least 20 non-exempt would-deny calls a week under the v3 pattern, pricing at least 1.0 pp/wk. If it fails: PARK, re-checked weekly, and the one-day trial is logged as "approved, no target population".
- **S1 (the one-day trial):** 50%, at least 24 h, ending at 10 denies, at most 7 d.
  - It trips on any of:
    - 3 or more non-wait denies in 24 h;
    - a Wilson lower bound above 10% on second denies;
    - a /goal-gate trip after a deny;
    - 3 or more consecutive denies to one agent.
  - It continues iff the Wilson lower bound on "re-issued as told" is at least 0.60 (n ≥ 6 at 100% [C]) and the wrong-deny cost is under 0.2% of weekly usage on every account.
- **S2:** SIA 2.0 pp/wk; looks at d14 and d28.
- **Kill:** `cc-lever off D4`. Harder: `CC_SUBAGENT_LONG_BASH=off` (c10).

**D2 a4c54d1744d1 — Workflow block-once**
- **Metric:** per run, the deduped workflow-agent cost (input side; output reported as imputed) plus the deny round trip, as a treatment/control log ratio. Also the edited-resubmit compliance rate. Quality comes from the offline eval only.
- **Arm:** one per lineage root (salt_D2). A cost verdict comes online only if the S0 σ(log run cost) is 1.2 or less (est. [C]).
- **Offline d2-lean:**
  - Cases: would-deny agent() slots without agentType, taken from 28 d of `subagents/workflows/<run>/` transcripts and the shadow rows, plus F2's 10 code-graded briefs. About 20/20 train/test (est. B).
  - Grader: facts checked by code first (key.json check_cmd), then a blind Sonnet judge per ask.
  - Runs: ABBA order on one account per block, R=2, each variant in a fresh process (agent definitions are cached at session start).
  - Gate: lean − default pass rate with a CI95 lower bound of at least −10 points; requests ratio with a one-sided 95% upper bound of at most 1.3; pp ratio < 1.
  - Cost: about 9 pp for the baseline plus 1.7 pp per round (est. B, from cost.out).
- **S1 (the one-day trial):** 50%, at least 24 h, ending at 3 treated denies, at most 72 h. It trips on any one of:
  - a deny on a resume;
  - a deny of a needs-default or keep-default slot;
  - a second deny of the same (sid, script_sha);
  - a hook timeout (5 s) or self-bound;
  - p95 latency above 3 s.
- **S2 (needs a d2-lean KEEP):** runs to 25 denies or 28 d.
  - ADVANCE iff the compliance Wilson lower bound is at least 0.80 (n ≥ 16 at 100%, 25 at 95% [C]).
  - REVERT iff the Wilson upper bound is below 0.80, or the cost log-ratio CI lower bound is above 0.
- **Kill:** `cc-lever off D2`. Harder: `CC_WORKFLOW_SHADOW=off` (c10).

**D1 43da49891e75 — idle recycle at 200k after 15 idle min (G1-G6)**
- **Metric:** net pp per recycle, by chain accounting (scripts/lib/lever_chain.py). The successor's requests within 24 h are re-priced at the predecessor's projected context (w4/sim.py). From that subtract: the actual price, the wake turn, the handoff turn, orientation beyond the median fresh session, and the priced file-touch rework.
- **Model check:** on control-arm would-recycle points, the projected cost must match the actual continuation within ±25%, else PLUMBING.
- **Arm:** one per lineage root.
  - Resolution order: env `CC_LEVER_LINEAGE` (exported by hf_succ_stage), then lineage/<pane>.json, then the process cache, then the session's own sid.
  - Repair: offline pane+time join.
  - Successor/predecessor arms must agree at least 95% of the time, else PLUMBING.
- **Offline (programmatic):** a K/N replay that must reproduce 16.36 / 15.39 pp/wk gross at 150k / 200k within ±5%.
- **Offline d1-successor (model runs):**
  - Cases: about 200 production returns after at least 10 min idle at 150k or more (est.: double the 14-d counts in B's d1_pool.py).
  - Fixtures are truncated at the idle point. A capture hook records and denies the first state-changing call.
  - Grader: action class graded by code, then blind Sonnet claims C1-C4.
  - It imports the 60 + 133 existing labels (κ 1.00 / 0.88) and the 10 A-class replays. Cost: 2-10 pp per variant (est. B).
- **Gate S0→S1:**
  - S0 is the approved 7-day shadow, counted from when the IRS v2 rows land (next-prompt sha and head; the 200k field on every row). Earliest 2026-10-31.
  - Measured on the d1-successor test split:
    - projected wrong actions at most 1 a week, upper 95% at most 2;
    - at most 2 failures on the 10 A-class replays;
    - successor first-turn median at most 10 requests, rework at most 10k tokens;
    - the eval's A/A noise floor under 10 points (est.: Wilson half-width ≈ 10 at n=100).
- **S1:** 10%, at least 3 d, ending at 20 recycles, at most 14 d (about 16 recycles a week, est.: 161/wk [A d1_perreq] × 0.1).
  - It trips on any of:
    - one G1 kill or G4 violation;
    - 2 or more judge-confirmed wrong actions in the first 20;
    - the G6 medians exceeded;
    - 2 or more recycles that do not engage within 10 min;
    - any double wake.
- **S2:** 50%, to 60 recycles or 28 d. ADVANCE iff all hold:
  - the CI lower bound on net per recycle > 0 at both read ends;
  - fleet-scaled net at least 4.0 pp/wk (the SIA);
  - the model check within ±25%;
  - the re-ask Newcombe CI does not exclude 0 on the harmful side.
- **S3:** 90%, with a 10% holdback kept for calibration.
- **Kill:** `cc-lever off D1` (recycles in flight finish; no new ones start). Harder: `CC_LEVER_D1=off` (c10).

**Shared guards:**
- Ratio guards run hourly from the scorer, at a one-sided 99% bound with Holm correction, and at 95% at each look:
  - T1 tool errors per 100 requests. Hook denies are excluded and treatment denies are counted separately. Baseline 2.86 [NF].
  - T2 failed lands per land. Exits 6/5/11/143 count as failed and 42 is excluded; an unknown exit code is PLUMBING. Baseline 0.605 [NF].
  - T4 CRASH rows in claude-crashes.jsonl.
  - T5 the judged re-ask rate.
- T3 is a count alarm without Holm: prompt-too-long main-session deaths in treated sessions, scanned over all four roots. It trips at 2 or more a week at S1 and 3 or more at S2/S3. False-trip rate is 0.27% / 0.67% / 4.1% at 10 / 50 / 100% [C: Poisson at the 0.087/100 bound].
- The lever invariants above trip on a single occurrence, checked by the 10-min daemon.

**Plumbing gate.** Any of these means PLUMBING and no verdict:
- SRM p < 0.001, overall or on any account; arm × account χ² p < 0.001;
- logged arm ≠ recomputed arm on more than 0.5% of rows;
- any of the four projects roots unread;
- parse failures above 0.1%;
- flag_src ≠ file on more than 1% of rows;
- treatment exposure below 80%;
- arms differing on join coverage, imputed-output share, or outcome-missing rate by more than 3, 5 or 3 points respectively;
- covariate imbalance;
- placebo-salt A/A significant in more than 3 of the last 20 runs;
- bootstrap SD vs A/A SD more than 20% apart;
- weekly fleet meter/wpp outside [1.1, 1.5] (measured 1.20-1.36 [NF]);
- the fingerprint (CC 2.1.293 pin, model, effort, weights) or the thresholds sha changing mid-stage;
- eval rows in production arms;
- an account with eligible events but zero lever rows.

### 3. Shared pieces
| Piece | Paths | Contract |
|---|---|---|
| Flag file and arm lib | `~/.claude/state/levers/flags.json` (runtime); `hooks/lib/lever_flags.py`; `hooks/lib/lever-flags.sh` (bash 3.2) | Per lever: stage, pct, holdback, mode, salt, split_salt, params_id, candidate, thresholds_sha, trip. Precedence: existing hook kills > `CC_LEVER_ALL` / `CC_LEVER_Dn` = off or control (can only lower; new sessions) > flags.json (next hook call) > pct 0. An unreadable file gives pct 0 with flag_src=unreadable. A heartbeat older than 1800 s gives pct 0. u = int(sha256(salt:unit)[:13],16)/16^13. |
| Operator CLI | `bin/cc-lever` | status, stage, off, candidate, promote, `ack <trip_id>`, history. A raise needs --confirm, the latest ADVANCE, a fresh heartbeat and no un-acked trip. Writes under flock with tmp+rename and audits to lever-flags.jsonl. |
| Session stamp | `hooks/lever-arm-start.sh`, a child of `hooks/session-start-dispatch.sh:61` | Writes a kind=session arm row. No settings edit needed. |
| Telemetry rows | `~/.claude/logs/lever-{arms,flags,ledger,score,guard,judge,rounds}.jsonl` | arms: one row per eligible decision in both arms, written before acting. ledger: per session (sid, lineage, acct, arms, tokens by class, pp lo/mid/hi, tool errors without hooks, lands, PTL deaths, eval flag). Rows ≤ 2 KB in one write(), UTC Z. Shadow logs bump to keepalive v2/v3, IRS v2, subagent v3, workflow + acct/arm/follows_deny. |
| Scorer | `bin/cc-lever-score`; `scripts/lib/{lever_events,lever_stats,lever_guards,lever_chain}.py`; `config/levers.json` (pre-registration, sha pinned) | score [--split train/test --unseal --write], guards (≤ 60 s, no transcript scan), ledger --write, aa --reps 200, failures --split train (refuses test), report, plumbing, selftest (planted effect; the same sha twice). Tokens come from cc-token-ledger scan(): message.id dedupe, earliest file, all four roots. |
| Evals | `bin/cc-lever-eval`; `tools/lever-evals/{lib/hc.py,d1_recycle,d1_successor,d2_lean,d3_keepalive,d4_pollloop}/`; state in `~/.claude/hillclimb/<flow>/` (SCHEMA v2) | build, split, run, score, check (oracle, null, A/A, served model, truncation), round, report. Harness-sha approval, 8-gram leak check, the analyzer sees train rows only. Eval runs set CC_LEVER_EXCLUDE=1 and use a /tmp/lev-eval cwd. |
| Judge | `bin/cc-lever-judge`; `config/lever-rubrics.json` | `claude -p --model sonnet --tools "" --setting-sources ""` in a neutral cwd; the init-line model is asserted ≠ claude-opus-5-5. Seeded blind order, 20 anchors per batch, 10% re-judged in swapped order. κ < 0.8 voids the batch (PLUMBING). Known negatives must fail 3/3. At most 40 dossiers a day. |
| Auto-rollback | `bin/cc-lever-guard`; `launchd/staged/com.claude.lever-guard.plist` (600 s, ≤ 60 s, Standard); `launchd/staged/com.claude.lever-score.plist` (3600 s, `exec /usr/bin/python3 -I`, ≤ 540 s) | Demotes to pct 0 with mode=shadow and latches the trip. Pages `~/.claude/autonomy/pages/lever-<L>.page`. Two NO-DATA ticks demote the lever as "blind". Never raises, never edits settings or code. |

**Hillclimb loop:**
- **Offline first; one change per round.** Each round targets the top cause from `failures --split train`.
- **Split:** test iff sha1(case_id) % 5 == 0. The test split is sealed and stratified by account.
- **decide():**
  - KEEP iff train > NF_train, the test CI95 lower bound > 0, and the point ≥ MIN_ACT. MIN_ACT is 1.0 pp/wk for pp flows, 10 points for d1-successor, and 10 points for compliance.
  - Train up, test flat → REVERT. Either half below −NF → REVERT.
  - 3 non-KEEP rounds → STALL: sort the train failures (artifact / grader / harness / structural / variance) and make no edit that round.
  - At most 6 rounds per flow, then confirm on the next 7 d of fresh production cases.
- **Online candidate:** only inside S2/S3, and only if the offline gain is at least the test-half MDE at 28 d or less: D3 1.48 with return_s or 5.7 context-only; D4 2.55; D1 never [C].
- **Tunable:**
  - D1: k, n_min, the G4 regex, the brief.
  - D2: the message, the markers.
  - D3: wake_s, skip_watcher, min_ctx_k.
  - D4: the message, the pattern.
- **Never tunable:** resume pass-through, the headless exemption, one wake per gap.
- **Report:** test vs baseline with CI; anything within noise is marked NOT-MERGED.

### 4. Implementation waves (S = one dispatched session; sizes estimated from the B/C wave estimates)
| S | Builds | Out | Needs | Parallel with |
|---|---|---|---|---|
| S1 | Control plane, arms, lineage: lever_flags.py, lever-flags.sh, bin/cc-lever, lever-arm-start.sh, session-start-dispatch.sh:61, handoff-fire.sh hf_succ_stage export plus lineage file (about 20 lines), tests/lever-flags.bats under /bin/bash 3.2 | 120K | — | S7a |
| S2 | Idle shadows: idle-keepalive.sh (arm rows, flag re-read at due time); idle_gap.py (gap v2 with episode_id, ended_by, return_s, busy/watcher; wake v3); boundary-handoff.sh IRS v2; bats | 90K | S1 | S3, S4, S7 |
| S3 | Deny-candidate shadows: subagent-long-bash-shadow.sh v3 plus the wider pattern plus d4_follow rows; workflow-lean-shadow.py (acct, arm, follows_deny, UTC); validate-bash.sh follow pipe; bats | 80K | S1 | S2, S4 |
| S4 | Scorer core: lever_events.py; cc-lever-score ledger, plumbing, selftest; bin/cc-ctx-audit:72-74 adds the secondary root and bounds its loop; fixtures | 130K | S1 | S2, S3, S7 |
| S5 | Stats and guards: lever_stats.py (agg.py ports, cluster bootstrap, CUPED, SRM, KS/SMD, Haybittle-Peto, pseudo-salt A/A); lever_guards.py; config/levers.json; score, aa, report, failures | 130K | S4 | S7b |
| S6 | Guard and jobs: cc-lever-guard; both plists; launchd/fleet.manifest; migrations 0079 (jobs) and 0080 (ask rules); store-bounds and rotation (retain ≥ 35 d); bats | 120K | S1, S5 | S8 |
| S7a | Eval kernel and D3: first copy /tmp/idle-recycle-risk/b and /tmp/conv-tests/* into ~/.claude/hillclimb/; hc.py, cc-lever-eval, d3 build_cases and policy; decide() truth table | 120K | — | S1-S6 |
| S7b | D4 predicate and headroom check; D1 K/N sim port | 90K | S7a | S2-S6 |
| S8 | Judge and D1 chain: cc-lever-judge, lever-rubrics.json, lever_chain.py, D1 scoring and re-ask guard | 120K | S5 | S6, S7b |
| S9 | d1-successor eval and production brief: idle_recycle_brief.py, d1_successor/{build_cases,run.sh,capture-hook.sh,grade.py} | 140K | S7a, S8 | S10, S11 |
| S10 | d2-lean eval: d2_lean/{build_cases,keygen.js,run.js,grade.py}; wiring probes first (does a headless lead wait for the Workflow; does --agents override) | 130K | S7a, S8 | S9, S11 |
| S11 | D2 and D4 treatment at pct 0: block-once state, resume pass-through, needs-default; treatment verdict plus deny() at validate-bash.sh:83-90 | 100K | S3 | S9, S10 |
| S12 | D1 and D3 treatment at pct 0: idle-keepalive.sh exit-2 wake, D1 due time, one wake per gap; session_jobs.py state_at; handoff-fire.sh G3/G5 through the brief | 140K | S2, S9 | — |

Total about 1.61M output tokens (est.: sum of the rows). The critical path to the D2 one-day trial is S1 → S3 → S11 alongside S4 → S5 → S6, about 680K. Each session's /goal ends at "landed via /ship, suites green", never at an operator act.

### 5. Operator actions
1. After S6 lands, run `bash migrations/0079-lever-jobs-activate.sh --confirm` (loads both launchd jobs) and `bash migrations/0080-lever-raise-ask.sh --confirm` (settings.json ask rules for cc-lever stage, candidate, promote and ack).
   - Each copies settings.json to ~/.claude/backups/<name>-<N>-<ts>/. Undo with `bash scripts/c10-batch.sh --rollback <dir>` or `launchctl bootout`.
   - One edit covers all four accounts: each config dir's settings.json is a symlink to ~/.claude/settings.json [R].
   - 0078 is the top migration today [R]; renumber at land if 0079 or 0080 is taken.
2. Approve each eval harness after reading it: `cc-lever-eval approve-harness <flow>`.
3. Make every raise yourself: `cc-lever stage <Dn> S1|S2|S3 --confirm`, plus candidate, promote and `ack <trip_id> --reason`. Order: D2 S1 after S11; D4 only if its population gate passes; D1 and D3 no earlier than 2026-10-31.
4. Optional: a fleet hard kill, `CC_LEVER_ALL=off` in the settings env (c10); and about 20 pairs you label yourself to calibrate the judge.
5. Code rollback is a forward `git revert` landed through /ship; deploy-live never rolls back.

### 6. Completeness critic (each fix is already folded in above)
- A and C allowed SIA = MDE (1.49 vs 1.5, 1.99 vs 2.0). Now the MDE from the S0 A/A must be strictly below SIA, or the lever is offline-only (§2).
- C's day-7 D3 claim ignored its own |z| ≥ 3.0 bound. Interim MDEs are now ×1.37 (§2).
- C's D4 MDE assumed per-call units. It is now bracketed at 1.34-8.12 [A] and measured at S0.
- B's replays reuse the cost model that produced the claims. Replays now gate only sign and safety; D1 needs the ±25% control-arm model check, and D3 needs the online CI.
- A fail-safe pct 0 looks exactly like the control arm. flag_src is counted, and more than 1% is PLUMBING.
- cc-reaper TERMs any launchd-parented bash older than 600 s (bin/cc-reaper:574 [R]). The scorer job execs python and bounds itself at 540 s; the 60-s guard tick never scans transcripts.
- None of the four shadow logs is in store-bounds or rotation (grep found 0 [R]), and handoffs.jsonl keeps about 2.4 d [INV]. Retention is now 35 d or more, and the lineage is written at recycle time.
- Survivorship: a session that ends before an event's outcome would vanish. Outcome-missing rates are compared per arm, and intention-to-treat counts the cost up to session end.
- Mixed timestamp offsets (workflow-lean-shadow writes -0500 [INV]): rows are written in UTC from S3 on; an unparsable offset counts as a parse failure.
- Long rows lose append atomicity. Rows are capped at 2 KB in a single write(), with prompt_head at 200 chars or less.
- The D1 labels and replays exist only in /tmp (present today [R]). S7a copies them first.
- Eval sessions could pollute the arms. CC_LEVER_EXCLUDE plus the /tmp/lev-eval cwd keep them out; eval rows found in production are PLUMBING.
- Stuck sessions had no guard. A D1 recycle that does not engage, or a D3 wake with no completed turn within 10 min, is now a lever invariant.
- The post-land red rate cannot be measured (postland-verify fired 2 times vs 94 lock-held in October [INV]). No guard claims it; T2 uses ship-land exit codes only.
- Savings could come from doing less work. Quality stays a guardrail (D2 pass rate, re-asks, lands per arm shown descriptively), never a pp-per-work headline.
- Trips clear by occurrence (`ack <trip_id>`), never because the condition went away. Pages go to ~/.claude/autonomy/pages, which operator-readout reads, not to launchd stderr.

### 7. Wave progress (lead: session 2b3becea, recycled from b287d693; briefs in /tmp/lev-fire/)
- **S7a — DONE** (`f4d626ba9`, landed + converged 2026-10-24). hc.py, cc-lever-eval, D3 build_cases/policy; tests/lever-eval.bats 1..15, 0 not ok. The /tmp sources (idle-recycle-risk/b, conv-tests, lev-design, plus lean-idle-rv, which recompute.py needs) are copied under `~/.claude/hillclimb/_imports/`. D3 replay reproduces recompute.out 3.79/2.67/5.07/4.23 within 0.17%. **Finding for D3 before S2:** on the current 28 d the busy-scoped replay prices 2.80/2.18 pp/wk and the one-wake candidate 1.84/1.64, both below SIA 3.0, so D3's expected 3.9-5.1 does not hold on fresh data; re-check at S0 before any S2 raise.
- **S1** — in flight (pane 295): committed, bats 1..10 0 not ok, landing.
- **S7b** — briefed; held once by the fire capacity gate (12 sessions mid-turn > ceiling 8), fired when a slot frees.

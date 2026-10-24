---
status: in-progress
---

# Usage levers — getting more work from the same 4 Max 20x accounts

Scope (frozen): act on the verified usage-efficiency levers surfaced by `claude -p /usage`
(research: `docs/research/usage-levers-2026-10-23/REPORT.md`, round 2 in `round2/REPORT.md`),
implementing what clears 90% conviction and running the one cheap test each remaining lever needs,
each wave landed via `/ship` and converged live.

## Phase 0 — Agent Team Orchestration — DONE (W0–W4 fired and landed 2026-10-24; remainder is W5)

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

## W6 — make the shadows measure correctly (S; behavior-neutral, no sign-off needed)
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

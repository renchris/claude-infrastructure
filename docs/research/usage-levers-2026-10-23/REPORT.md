# Usage-efficiency levers surfaced by `claude -p /usage` (2026-10-23)

Scope (frozen): persist the `/usage` efficiency research (report + analysis scripts) and land it.

Provenance: `claude -p /usage` run on all 4 accounts on 2026-10-23, then workflow `wf_cf8fce4c-910`
(6 measurers on `workflow-lean`, each re-checked by an independent skeptic, 1 synthesis; 13 agents,
~1.2M subagent tokens). `measurements.json` holds every measurer + verifier return verbatim;
`scripts/` holds the analysis scripts (they read transcripts under `~/.claude-*/projects/` and wrote
intermediate output to `/tmp/usage-audit/`, which is not persisted: re-run to regenerate).
Builds on `docs/research/token-efficiency-2026-09-23/` and `docs/research/quota-cache-freshness-2026-10-01/`.

## Next steps (agreed shape, 2026-10-24)

1. Targeted research workflow on the three open items only: (a) do cache reads count against the
   weekly quota (the two fits below disagree; levers 3-4 depend on it); (b) design of the
   `workflow-lean` enforcement hook with its allow-list for slots that legitimately need the default
   agent; (c) why idle main sessions skip the existing 55-minute wake. Output: a plan with Phase 0.
2. Implementation as dispatched sessions, one per wave, each landed via `/ship` and converged:
   A = binary pin (`bin/cc-notify:682` prefers `command -v claude`, which resolves to pnpm 2.0.5,
   over `cc-claude-bin`) + `workflow-lean` enforcement; B = idle cache-rebuild fixes;
   C = context-recycle thresholds, only if (a) says cache reads count.

## Synthesis (verbatim from the workflow)

**Verdict:** No, it won't save tokens on its own. It is a free check. The linked post is Boris Cherny asking one user who had maxed out his account to paste the output of `claude -p /usage | pbcopy` so Anthropic could debug it. The command costs 0 tokens (measured) and saves 0. Its breakdown repeats what your own transcripts already show. The real savings are in the levers below.

**Levers, ranked by verified weekly saving.** Savings are a percent of weekly usage across all 4 accounts and are estimates. "API" means weighted at list-price ratios. "Meter" means fitted to ~/.claude/logs/account-utilization.jsonl. Evidence comes from scripts in /tmp/usage-audit/.

| # | Lever | Evidence (measured) | Action | Est. saving/week | Confidence |
|---|---|---|---|---|---|
| 1 | Read-only Workflow slots that run on the default agent | A default slot starts at 47.6k tokens, against 9.2k for workflow-lean. The ~38k difference is written fresh for every slot. 1,759 of 1,938 default slots used no Skill, MCP, commit or sandbox rehearsal (sk_an1.py, sk_an3.py) | Make workflow-lean the enforced default for read-only agent() calls | 5.2% last week (4.7-6.6% depending on weighting). 2.8% recurring if the agentsync round loop stops | 75% |
| 2 | Cache rebuilt after idle gaps | 22.7% of cache writes (191.9M of 845.0M) are mid-session rebuilds. 97% follow an idle gap longer than the cache lifetime: 1h for main sessions, 5m for subagents (sk-cache-an.py) | Find out why waiting main sessions skip the existing 55-minute wake. Block subagent foreground Bash calls over 270 s | Main sessions idle 1-2h: 1.7% API, 2.5-9% meter. Long subagent Bash calls: 1.05% API, 2.2% meter | 55% |
| 3 | Main-session context size | On the 1M window: median 231k, p90 459k. 89% of main input tokens sit above 150k, and the recycle rails only act at 250k-750k (sk_bc_an1.py) | Don't force busy sessions to drain. Keep the existing 25% idle floor | 3-8.5% at most if cache reads count against quota. A 1.6-3.9% loss if they don't | 30% |
| 4 | Always-loaded instructions | ~/.claude/CLAUDE.md plus rules/10-session-close.md add about 14.7k tokens to each of about 86k main requests a week (baseline_join.py; sizes estimated as chars/4) | Run a slim round through the gate in INSTRUCTION_BUDGET.md | 0.6-1.0% per 10k tokens cut if reads count, about 0 if not | 40% |
| 5 | Watcher timeout wakes | 885 cc-await-ping timeout wakes, 1.0% of the meter (an.txt) | Lengthen the timeout. Don't remove it, because it is the deadline check | 1% or less | 50% |
| 6 | Batching peer messages | 1,470 of 1,951 peer turns arrive within 5 minutes of another message (batch.txt) | Deliver message bursts as one digest | 0.3-0.8% meter | 45% |
| 7 | Trimming the skill listing | The listing is held at its 30,001-character cap. 22 entries already cut to name-only would fill any freed space (read from the binary) | Skip | About 0 | 70% |
| 8 | Running /usage itself | total_cost_usd 0, and 0 assistant records in its 6 transcripts | Use it as an occasional check | 0 | 90% |

Two other suspects are not levers. Idle loops (/loop, cron, ScheduleWakeup) are 0.03% of the meter, and parallel sessions cost about the same per request (an.txt).

**Hazards found**
- **Wrong binary:** Bare `claude` from bash or a script resolves to ~/Library/pnpm/claude, version 2.0.5. That version rejects `/usage` ("Unknown slash command") and attempted a model call that failed with a 404. Live sessions run ~/.claude-293 (2.1.293), not the /opt/homebrew 2.1.291 the brief named. Callers that don't pin the binary: bin/cc-notify:683, scripts/research-kit/router.py:546 (the running daemon, pid 2953, uses the unpinned 2.1.291) and scripts/rm-preempt-probe.sh:47.
- **Account router in kitty:** In a kitty pane, `claude -p /usage` goes through the account router. It reports whichever account the router picks, logs a row to ~/.claude/route/route.jsonl, and is charged as a session launch after 5 s. A plain run also fires the SessionStart hooks and writes a ~14 KB transcript into the data that /usage reads. The safe form below took 14 s, used 0 tokens and left no transcript (tested on next3 only):
  `CLAUDE_CONFIG_DIR=~/.claude-quaternary "$(~/.claude/bin/cc-claude-bin)" -p /usage --safe-mode --no-session-persistence </dev/null | pbcopy`
- **Double counting:** /usage counts subagent transcripts that were copied between accounts (about 1,232-1,264 of them). 14.6% of per-account requests are such copies. next4's 7-day count is about 46% too high and next3's about 26% (sk_totals_peracct.py).
- **What ">150k context" means:** It is a price-weighted share of usage, not a share of requests. Only 38-41% of 7-day requests are above 150k (ctx_weight2.py).
- **Unresolved quota question:** Two independent fits disagree on whether cache reads count against the weekly quota. sk_bc_meter2.py puts reads at 27-40% of the meter. sk-cache-ttlfit2.py puts them at about 0, which matches the repo's August ruling. Levers 3 and 4 depend on which is right.
- **Smaller issues:** agents/workflow-lean.md says a default slot costs about 130k; the measured figure is 47.6k. ~/.claude-next4 is a leftover September probe directory, not an account, and one /usage run landed in it. The earlier collection runs left 8 transcripts in this worktree's project dirs. Nothing was deleted.

**Top 3 actions now**
1. **Enforce workflow-lean.** Add a PreToolUse check in ~/Development/claude-infrastructure/hooks/ that flags Workflow agent() calls with no agentType. It must still allow an explicit default for the 10-28% of slots that commit, use Skill or MCP, or rehearse in git clones. Fix ~/.claude/workflows/freewin-probe-t1-t2.mjs and pyramid-fans.mjs. Patch /Users/chrisren/.cache/agentsync-bring-back/b13/round26/round26-workflow.js only if ~/.claude/autonomy/decisions/e869fac7eb34.json keeps that loop running.
2. **Cut idle cache rebuilds.** Trace why waiting main sessions skip the 55-minute idle wake in ~/.claude/bin/cc-await-ping. Add a hook that denies, with a reason, subagent Bash calls with a timeout over 270 s and tells them to run the work in the background. Keep subagents on the 5-minute cache.
3. **Settle the quota question before any context-cap work.** Reconcile /tmp/usage-audit/sk_bc_meter2.py and sk-cache-ttlfit2.py against ~/.claude/logs/account-utilization.jsonl, with the copies removed and output counted from each message's final record (the 62.0M output total was undercounted; the real figure is at least 87.9M). Also change bin/cc-notify:683 to call cc-claude-bin first.

The measurement data didn't cover the tweet, so I fetched it read-only (thread: tweets 2113415102762488006 and 2113141937645769087). Sources: [reply](https://api.fxtwitter.com/bcherny/status/2113415102762488006), [request](https://api.fxtwitter.com/bcherny/status/2113141937645769087)

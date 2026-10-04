# Shard session-cost: per-session token profile and cost levers (2026-10-04)

Method: /tmp/capi-guides/shared/cost-optimization.md + prompt-caching.md. Read first, so nothing here
re-proposes something already measured and rejected: docs/research/token-efficiency-2026-09-23/ (REPORT,
measure/static-prefix.md, eval/GATE.md) and docs/plans/INSTRUCTION_BUDGET.md.

## Step 0: scope, quality bar, baseline

- **Scope.** Claude Code sessions on this machine (main threads, Agent-tool subagents, Workflow agents),
  all 5 config dirs. Platform: first-party, Max subscriptions. Cost is weekly quota, not dollars. On the
  plan meter, cache reads weigh about 0 (BASELINE.md § Weights, bounded at ≤¼ list). That leaves **cache
  writes and output** as the classes that matter, so this shard ranks levers in **write tokens**
  (1h write = 2x input, 5m = 1.25x).
- **Quality bar.** The repo has an offline blind-judged gate (eval/harness, F1 = instructions, F2 =
  workflow workers). It covers instruction text and the worker type. It does not cover cache or TTL
  behavior, which is cost-only by nature.
- **Baseline.** Measured from transcript `usage` (no API calls, no sessions spawned) over
  2026-10-01 to 10-04 (about 3.25 days):
  - main threads: 418 transcripts, **150.0M write tokens (1h)**, 18.1M output;
  - workflow agents: 1,197 contexts, **131.2M write tokens (5m)**;
  - Agent-tool subagents: 124 contexts, 22.0M write tokens (5m).
  - Scripts: /tmp/capi-audit/{miss2,idle,idle2,idle3,wf,reattach,ups}.py.

## Step 1: token profile

### Static prefix of one session (measured from this session's own first request)

Measured on 884aa5bc (a main session in this worktree, started today, after migration 0053): first
response `cache_read` 16,270 (system + tools, globally cached) + `cache_creation` 1h **64,935**. Rendered
setup is 169.6k chars, so the measured ratio is 2.61 chars/token. Before the W1/0053 dedupe, the same
repo wrote 104-105k (transcripts 762a6daa, b671b47e), so about 40k tokens per session are already saved.

| Component (main session, this repo) | chars | ≈ tokens | in workflow/sub agents? |
|---|---:|---:|---|
| ~/.claude/CLAUDE.md (slim) | 26,934 | 10.6k | yes |
| ~/.claude/rules/10-session-close.md | 30,247 | 11.9k | yes |
| ~/.claude/rules/00-mission-board.md | 2,281 | 0.9k | yes |
| project .claude/CLAUDE.md | 6,734 | 2.6k | yes |
| project .claude/rules/agent-operating-lessons.md (situational half excluded by 0036) | 9,725 | 3.8k | yes |
| MEMORY.md index | 21,071 | 8.3k | yes |
| **instructions block total** | **98,052** | **38.5k** | yes (not workflow-lean) |
| skill listing (at its 30k cap; 18 of 101 entries name-only) | 30,061 | 11.2k | yes (not lean) |
| deferred tool names (215; ms365 about 190, kept by operator ruling) | 7,129 | 3.6k | yes |
| agent listing | 4,823 | 1.9k | main only |
| SessionStart additionalContext | 4,067 | 1.8k | main only |
| MCP server instructions (motion and motion-plus carry identical text) | 3,408 | 1.2k | main (agents after response 1) |
| env/model/auto_mode/date/session_context/etc. | 3,652 | 1.4k | partly |

A default Workflow agent (a sibling slot of this run): `cache_read` 8,103 + 5m write **55,232**, made up
of the same 98k-char instructions, the 30k listing and the 7k deferred names. A `workflow-lean` slot
starts at about 9k (measured mean 9,189 over 933 slots).

### Where main-session write tokens actually go (2026-10-01 to 10-04, 150.0M)

| Class | write tokens | share | events | mean per event |
|---|---:|---:|---:|---:|
| First request (static setup + first prompt) | 27.1M | 18% | 418 | 65k |
| **Cold re-write after > 1h idle** | **49.1M** | **33%** | 159 | 309k |
| **Re-write after a limit hit or API error (account move, resume)** | **25.9M** | **17%** | 58 | 447k |
| Other cold re-writes (5-60 min, < 5 min) | 3.4M | 2% | 16 | |
| Incremental per-turn writes (healthy) | ~44M | 29% | | |

Idle > 1h re-writes, by what woke the session: a human prompt 91 (28.4M), a task-notification 44
(13.2M: 12 peer mail, about 20 hand-armed multi-hour watcher or "wait" terms, about 8 long Workflow runs
finishing), a tool_result 15 (4.7M), a meta message 10 (2.9M). Gap p10/p50/p90 = 1.2 / 3.9 / 16 h.
Re-write size p10/p50/p90 = 133k / 280k / 558k. Of the 91 human-prompt wakes, 65 (18.8M) had no
background watcher armed anywhere in the transcript; 7 (2.1M) had one with `--timeout` > 3300 (heuristic,
idle3.py).

The re-writes after a limit hit follow synthetic messages: weekly-limit hits (31), "No response
requested." (13), API unreachable (11). These are the limit-recover reconciler resuming the full
transcript on another account, where the cache is per organization and starts cold.

**Conclusion of the profile.** The size of the static prefix is no longer the dominant main-thread lever.
The dedupe already took about 40k tokens per session, and the remaining prefix is 18% of main writes.
Cold re-writes of large contexts are 52%. The static prefix also rides inside every one of those
re-writes, and it is re-written in every default-type agent context.

### Other measured items (small)

- UserPromptSubmit injections: 1,411 in about 2.5 days, 1.60M chars (about 0.6M tokens, ≈0.4% of main
  writes). The largest is the "🔔 No inbox wake path armed" nudge on 59% of human prompts (572k chars),
  which repeats identical text every prompt. Next is memory-nudge every 12th prompt (about 4k chars,
  most of which restates CLAUDE.md § Memory).
- Mid-session re-attachment of changed memory files: 42 events, 4.3M chars (about 1.65M tokens, ≈1.1%).
  All are content changes (none spurious), driven by instruction deploys and MEMORY.md edits. Fleet-wide
  deploys fan out to every live session at once (one burst at 2026-10-01T20:16Z hit 8 sessions).
- Agent contexts: cold re-writes after > 5 min gaps total 4.0M of 153M. Rank 15's "background long
  commands" fix is holding.
- Default vs lean Workflow slots since 10-01: **258 default slots at a mean first request of 97.3k vs
  933 lean slots at 9.2k**. 13 of 46 workflow runs were all-default, this audit run included.

## Ranked shortlist (ranked by savings ceiling, not application order)

| # | Lever | Type | Ceiling (write tokens / 3.25 d) | Data |
|---|---|---|---|---|
| 1 | Keep idle main sessions warm (bounded keepalive) or recycle before long idles | free win (cache) + operator call | ≤ 49.1M (33% of main writes); no-watcher human-return class alone 18.8M | measured (transcript usage) |
| 2 | Limit-hit resume: relaunch with a bridge instead of the full transcript when the context is large | operator call (ruling: "take the full session") | ≤ 25.9M (17% of main writes) | measured |
| 3 | `workflow-lean` for read-only slots of ad-hoc workflows | free win (input hygiene; gated equal-correctness 2026-09-24) | ≤ 22.7M 5m-write (17% of workflow writes; about 88k per slot) | measured |
| 4 | Cap watcher terms at 3300 s at the actuator | free win (cache) | about 6-9M (4-6% of main writes) | measured counts, estimated tokens |
| 5 | Skill listing back under its cap (launch-film, cafe-wifi) | quality (token-neutral at the cap) | 0 tokens; restores 4 own entries' descriptions | measured |
| 6 | `effort: medium` on read-only lean slots | tradeoff | output-side; published 15-30% per task on research work | needs eval (F2 harness exists) |

Where the list stops: per-prompt nudges (0.4%), re-attachment on deploy (1.1%), MCP motion duplication
(about 0.4k tokens per main session) and the SessionStart text (about 1.8k tokens per main session) are
each below the floor.

## Proposed changes (in § 2 application order)

1. **[proposed, free win] workflow-lean by default for read-only Workflow slots** (`CLAUDE.global.slim.md:110`):
   - Adds about 165 chars to the user tier, which stays under its 60k budget (59,516 measured).
   - The full file's venue rule (`CLAUDE.global.md:306-312`) should get the same clause for parity.
   - The F2 re-gate PASSed this worker type for read-only research slots. The research-subagents skill
     already says so, but ad-hoc Workflow scripts (ultracode, workflow keyword) never load that skill.
2. **[proposed, needs code] Clamp the `cc-await-ping --timeout` term to 3300 s** in a main session. Print
   one stderr line and allow an `CC_AWAIT_ALLOW_COLD_WAKE=1` escape. The C5 rationale is already in
   `bin/cc-await-ping:188-199`; today an explicit multi-hour term is honored silently.
3. **[proposed] launch-film description to ≤ 250 chars.** `tests/skill-listing-budget.bats` case 1 is red
   on this tree: running the suite's own check gives `launch-film: description 641 chars > 250`. cc-bats
   deferred the run under load, so the check was run directly. Also shorten the local-only
   cafe-wifi-optimization description (2,107 chars, truncated at the 1,536 per-entry cap). Together they
   free about 1.7k of the 30k listing, so `wrap`, `recover`, `scaffold` and `review` get their
   descriptions back.
4. **[operator decision] Idle keepalive.** This re-opens rank 6, dropped 2026-09-24 at "≥$549 (1.7%)".
   The measured class is now 33% of main write tokens.
   - Option A: a bounded 55-minute keepalive wake for idle sessions whose context is over about 100k,
     capped at N wakes. The obvious carrier is the Stop-hook asyncRewake arm (mailbox-wake-arm). Each wake
     costs a tiny output and write against a 2 × C re-write (C median 280k).
   - Option B: lower Context Stewardship's idle-recycle line from 35%/25% to about 15%, since the median
     cold re-write is 28% of a 1M window.
   - The 2026-09-24 objection still applies: a wake is a turn, and Stop hooks fire on it.
5. **[operator decision] Size-gated recycle on limit recovery.** When context > X and state is on disk,
   relaunch with a bridge (about 65k) instead of resuming the full transcript (mean 447k re-written at
   2x). This conflicts with the resume-sessions "take the full session, not the summary" preference, so
   it is the operator's call.
6. **[needs eval] `effort: medium` in `agents/workflow-lean.md` frontmatter.** Run the F2 harness at
   medium vs high: 10 briefs × 4.

## Levers skipped and why

- Moving memory into the system prompt or adding a breakpoint after setup (rank 2) is upstream or
  operator decision `46ebbf378de6`; no new evidence.
- The 1h main / 5m agent TTL split stays (N1). This profile agrees: main gaps under 1h are already warm
  (only 3 cold re-writes in 5-60 min).
- Mission board at memory position 1: within a session the first message is frozen, and no context
  reads another's setup, so the volatility costs nothing (static-prefix.md § 4).
- Shrinking the slim CLAUDE.md or session-close file: F1-gated, and close wording is where quality broke
  (8/10 false closes when cut). Re-gating is the operator's call.
- ms365 deferred names: operator ruling (email-images rule).
- MEMORY.md (8.3k tokens): already under the hook-tier design plus memory-nudge budget; no clean cut.
- Mid-session `/effort` or `/model`: none found in hooks or scripts. model-config.yaml records that a
  mid-session `/effort` on Opus 5.5 kept the cache.
- Per-prompt nudge dedupe (mailbox-drain wake-path, memory-nudge): real repetition but ≈0.5% of main
  writes together; below the floor.
- Batch API: none of this traffic is API-billed; not applicable to Claude Code sessions.

## Next step / approvals

Change 1 and the launch-film half of change 3 are agent-side text edits. Change 2 is a small code change
plus bats. Changes 4 and 5 are operator decisions with the numbers above. Change 6 needs an approved F2
run (about 80 slots).

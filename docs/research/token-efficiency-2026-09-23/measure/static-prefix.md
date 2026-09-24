# Static prefix: what every context pays before any work (CC 2.1.280 + ~/.claude layer)

Window: 2026-09-09 → 2026-09-23 (the shared extract). Prices are list prices used as quota weights; the fleet
is subscription-billed. "Own" = each response at its own model; "5.5" = the same token stream re-priced at
Opus 5.5 ($4 in, read 0.05x, write 1.25x/2x). Fleet total: $32,517 own, $18,319 at 5.5 (MEASURED, `resp_priced`, `xdup=0`).

## Headline

1. **The static prefix is ~40% of all spend.** Setup attachments cost **$10,821 own / $6,041 at 5.5 (33.3% / 33.0% of
   fleet)**. System prompt + tool schemas add **$2,155 / $1,080 (6.6% / 5.9%)**. Memory files alone are
   **$8,885 / $4,959 (27.3% / 27.1%)**. MEASURED tokens (`scripts/sp_cost.py`), per-context token conversion ESTIMATED from chars with ratios MEASURED by `/context`.
2. **The static prefix is 30% of main-thread spend, 36% of subagent spend and 40% of workflow-agent spend.** Agents
   (Agent tool + Workflow) pay **$4,184 own / $2,396 at 5.5** for memory files written for the operator's lead
   sessions, plus **$605 / $348** for a skill listing they almost never use. The Skill tool is called in **0.8%** of
   subagents and **0.2%** of workflow agents, against 17.7% of main sessions (MEASURED, `item`).
3. **The biggest single source is the global CLAUDE.md**: 36k tokens (median; 40.4k today) in 3,533 contexts,
   **$3,917 own / $2,199 at 5.5 = 12.0% of the fleet**. Next is the claude-infrastructure project rules file
   (`.claude/rules/agent-operating-lessons.md`, 74 KB / 27.9k tokens): **$1,824 / $1,001 = 5.6%**. Its own header
   says the file "now sits at ~43K chars"; it is at 74,078.
4. **Volatility costs nothing today and blocks the one structural fix.** Setup sits in the first user message with
   no cache breakpoint after it, so no context reads another's setup. First-response cache reads equal system+tools
   alone: main 14.3k (2.1.280), workflow agents 7.8k (2.1.280). Within a session the first message is frozen and
   re-read every turn, so volatility has no effect there. But 92% of workflow agents carry setup that is byte-identical
   to their run's majority, so a shared breakpoint would pay. The mission board, the most volatile memory file
   (534 versions in 14 days, changed between 22.7% of consecutive contexts), sits at **position 1** of the memory
   block, ahead of 50-200k chars of near-stable content. The `00-` filename prefix puts it there.

## 1. Headless `/context` (MEASURED, count_tokens API, no model turn)

`cd <dir> && claude -p "/context"` on the 2.1.280 launcher, CLAUDE_CONFIG_DIR = ~/.claude-secondary (inherited).
Every row is kept verbatim in `measure/static-prefix-raw/context_{tmp,infra,reso}.txt` and parsed into
`static-prefix.json` → `context_captures`.

| category | /tmp | claude-infrastructure | reso-management-app |
|---|---:|---:|---:|
| **Total counted** | **64.1k** | **103.7k** | **159.6k** |
| System prompt | 2.2k | 2.2k | 2.2k |
| MCP tools (loaded) | 629 | 629 | 629 |
| MCP tools (deferred, not sent; names only) | 367.7k | 367.7k | 368k |
| System tools (deferred, not sent) | 14.1k | 14.1k | 13.9k |
| Custom agents | 1.4k | 1.4k | 4.4k |
| Memory files | 48.2k | 87.7k | 137.8k |
| Skills (estimate; exact count below: 11.2k) | 10k | 10k | 10k |
| Messages | 1.7k | 1.7k | 4.5k |

Memory files, each row:

| type | path | /tmp | infra | reso |
|---|---|---:|---:|---:|
| User | ~/.claude-secondary/CLAUDE.md (copy of global CLAUDE.md, 105,278 chars) | 40.4k | 40.4k | 40.4k |
| User | ~/.claude/rules/00-mission-board.md (13,884 chars) | 5.5k | 5.5k | 5.5k |
| User | ~/.claude/rules/agent-operating-lessons.md (6,276 chars) | 2.4k | 2.4k | 2.4k |
| Project | claude-infrastructure/.claude/CLAUDE.md (6,245) | | 2.4k | |
| Project | claude-infrastructure/.claude/rules/agent-operating-lessons.md (74,078) | | 27.9k | |
| AutoMem | …/-Users-chrisren-Development-claude-infrastructure/memory/MEMORY.md (22,295) | | 9.3k | |
| Project | reso-management-app/CLAUDE.md (35,529) | | | 14.6k |
| Project | reso/.claude/rules/bottle-generation-ledger.md (102,885) | | | 43.3k |
| Project | reso/.claude/rules/agent-operating-lessons.md (52,130) | | | 20.6k |
| Project | reso/.claude/rules/agent-teams.md (7,828) | | | 3.2k |
| AutoMem | …/-Users-chrisren-Development-reso-management-app/memory/MEMORY.md (19,770) | | | 7.8k |

(reso has 12 `.claude/rules` files; 9 are path-scoped and did not load at the repo root.)

- **Custom agents:** deep-research 533, deep-research-sonnet 380, frontier-derivation 209,
  research-decomposition-critic 155, motion-reviewer 75. reso adds 10 project agents: code-reviewer 618,
  comment-analyzer 608, pr-test-analyzer 528, silent-failure-hunter 491, type-design-analyzer 448,
  code-simplifier 134, north-star-design-agent 66, fresh-eyes-evaluator 61, visual-design-iterator 61,
  schema-migration 58.
- **Skills:** 84 listed at /tmp and infra, 116 in reso. The listing is at its character budget:
  **40 of 84 (48%) and 69 of 116 (59%) show "< 20" tokens, i.e. no description at all**. The operator's longest
  descriptions crowd them out: limit-recover ~520, dia-agent ~490, manual-command-delivery ~480, plan-conventions
  ~480, dataviz ~480 and agent-teams ~400. In reso, manual-command-delivery and frontend-design-vue lose their
  descriptions to the extra project skills. So the 11.2k tokens buy only partial discoverability.
- **MCP:** 202 deferred tool rows (ms365 ≈ 190, claude.ai Docs 8, motion/motion-plus 5, uidotsh 1). Their schemas
  are not sent; only their names are (see deferred tool names below). Loaded MCP schema: 629 tokens.

**Exact token counts of the non-file blocks** (MEASURED: each rendered block from a real first request, passed via
`--append-system-prompt-file`, read as the change in the System prompt row; 0.1k resolution;
`static-prefix-raw/calib_counts.txt`):

| block (rendered, real first request) | chars | tokens | chars/token |
|---|---:|---:|---:|
| skill listing (infra lead session) | 30,103 | 11.2k | 2.69 |
| memory block, infra lead session (6 files) | 225,006 | 88.1k | 2.55 (/context row: 87.7k) |
| memory block, reso worktree session (8 files) | 344,089 | 138.3k | 2.49 |
| agent listing (infra / reso) | 6,437 / 16,051 | 2.5k / 5.7k | 2.57 / 2.82 |
| deferred tool names (infra / reso) | 7,602 / 7,120 | 3.8k / 3.6k | 2.0 |
| MCP server instructions | 4,311 | 1.5k | 2.87 |
| SessionStart hook additionalContext (infra / reso) | 8,220 / 9,422 | 3.6k / 4.2k | 2.26 |
| session_context (userEmail, gitStatus) | 1,300 | 0.5k | 2.6 |
| env + model + auto_mode + date + remote_session_change + total_tokens + hook_success | 1,924 | 0.8k | 2.4 |
| UserPromptSubmit additionalContext (1st prompt) | 894 | 0.4k | ~2.2 |

**System prompt + tools** is not a `/context` row: loaded built-in tool schemas are not itemized. It is measured from
transcripts instead, as the median first-response `cache_read` in the 5-30k band, i.e. the globally cached
tools+system block (MEASURED, `resp`):

| | 2.1.260 | 2.1.280 |
|---|---:|---:|
| main | 28.5k | 14.3k |
| subagent | 9.3k | 9.2k |
| workflow agent | 23.3k | 7.8k |

2.1.280 roughly halves it for main threads and cuts it by two-thirds for workflow agents, cause not verified (plausibly more
tools deferred). 12% of main contexts, 27% of subagents and 15% of workflow agents read 0 on their first request, and
re-wrote even this shared block.

## 2. First-request composition by context type (MEASURED)

Population: every context whose first response is in the window, `xdup=0` (985 main, 361 subagent, 2,401 workflow
agents). Script: `scripts/sp_first_request_items.py` (extract `item`, `resp_before=-1`) and
`scripts/sp_composition.py` → `data/sp_composition.jsonl` (sizes and sha1 only).

| setup block | main | Agent-tool subagent | workflow agent |
|---|---|---|---|
| memory files (`instructions`) | 86% (the remaining 14% are 2.1.114/2.1.183 sessions that do not record it); mean 218k chars | **91%**, 199k chars | **98%**, 213k chars |
| skill listing | yes (65% rendered + 13% unrendered on old versions), 29-30k chars | **96%**, 30k chars | **99%**, 30k chars |
| deferred tool names | yes, 5-7k chars | 96% (2.7k mean: restricted tool sets are shorter) | 99%, 6.6k chars |
| agent listing | yes, 7.6k chars (reso: 16k) | **no** | **no** |
| MCP server instructions | 61% at start, 2.1k chars | **no** at start; arrives after response 1 in 98% (race: MCP connects late) | same: after response 1 in 99% |
| SessionStart hook additionalContext | 85%, 10k chars (from 13 SessionStart hooks) | **no** | **no** |
| UserPromptSubmit additionalContext | yes, on every prompt | **no** | **no** |
| session_context, date | yes | yes | yes |
| environment + model | 65% | 19% | 14% |
| auto_mode, remote_session_change | yes | no | remote_session_change 93% |

So **agents receive the memory files and the skill listing, but not the hook context, the agent listing or (at start)
the MCP instructions.** `omitClaudeMd` agents are the exception: the `deep-research` custom agent had no memory block,
yet it still received the 30k-char skill listing.

Three real transcripts of each type. Records before the first response, sizes in chars of rendered text; hook records
without `rendered` are display-only.

- **main**
  - `wt-pool-8/54f5f8e3` (reso worktree, 2.1.280). SessionStart: 13 hook_success (1 rendered, 342 chars) +
    2 hook_system_message (display) + additionalContext 9,422; prompt 6,637; environment 965, model 161, deferred
    tools 7,120 (214 names), agent listing 16,051, MCP instructions 2,416, skill listing 30,088, auto_mode 516,
    total_tokens 86, 3 UserPromptSubmit contexts 395/334/894; **instructions 344,089** = global CLAUDE.md 104,973 +
    mission board 13,808 + rules essay 6,209 + reso CLAUDE.md 35,455 + bottle ledger 102,827 + reso lessons 52,040 +
    agent-teams 7,669 + MEMORY.md 19,769; session_context 1,413, date 64, remote_session_change 480. First response:
    cache_read 14,319, **1h write 170,010**.
  - `claude-infrastructure/eda5fec4` (the lead of this study). SessionStart additionalContext 8,220; prompt
    15,123 + a 17,613-char command body; environment 275, model 161, deferred tools 7,602 (226 names), agent listing
    6,437, MCP instructions 4,311, skill listing 30,103, auto_mode 516, workflow_keyword_request 175, UserPromptSubmit
    894; **instructions 225,006** = 104,973 + 13,808 + 6,209 + infra CLAUDE.md 6,244 + infra rules 71,158 + MEMORY.md
    21,554; session_context 1,300, date 64. First response: read 16,135, 1h write 124,026.
  - `claude-infrastructure/7d5c3981`. Same shape: SessionStart 8,957, instructions 224,832. First response: read
    14,302, 1h write 116,686.
- **Agent-tool subagent**
  - `wt-pool-5/…/agent-a1a66b45` (general-purpose): brief 3,853, deferred tools 6,909 (200 names), a 304-char
    reminder, environment 965, model 161, skill listing 30,099, **instructions 332,871** (8 reso files), session_context
    1,297, date 64. First response: read 4,740, **5m write 151,148**.
  - `wt-pool-7/…/agent-af16b7da` (code-reviewer): same shape, instructions 342,887. First response: read **0**, 5m
    write 159,002.
  - `drain-lane-infra/…/agent-a639c93a` (deep-research, omits memory): brief 1,739, deferred tools 304 (2 names),
    skill listing 30,096, session_context 1,274, date 64, **no instructions**. First response: read 9,752, write 12,861.
- **workflow agent**
  - `natural-text-to-voice-extension/wf_5580bb71/agent-afa86a00`: two brief records 988 + 5,618, deferred tools
    7,559, environment 285, model 161, skill listing 30,098, instructions 125,581 (the 3 user files only),
    session_context 1,334, date 64, remote_session_change 480. First response: read 8,002, 5m write 67,560.
  - `wt-pool-5/wf_f4d224d8/agent-ad96ffa7`: brief 487 + 14,188, skill listing 30,099, instructions 332,871
    (8 reso files). First response: read 8,229, 5m write 155,982.
  - `wt-feat-opus55-feature-adoption/wf_d6ec4924/agent-a11a72a0`: brief 21,926, skill listing 30,096,
    instructions 218,752 (6 infra files). First response: read **0**, 5m write 118,151.

**Wire order.** Transcript record order is not wire order. In transcripts the `instructions` record comes after the
prompt. In this workflow agent's own rendered context, the memory block (a system-reminder) and then
session_context (userEmail, gitStatus) come **first, ahead of the brief**. The per-turn attachments (deferred tools,
MCP instructions, skill listing, date) follow. SessionStart context is recorded before the prompt. Its wire
position relative to the memory block could not be resolved from the minified binary (gap).

## 3. Cost of each static source, 14 days (MEASURED tokens; per-context token counts ESTIMATED from chars × the measured ratios)

Method (`scripts/sp_cost.py` → `static-prefix-cost.json`):

- **Spec formula.** For every context carrying S: `tok(S) × p_in × (w + r × (n_resp − 1))`. Here w = 2.0 if the first
  response wrote 1h cache, else 1.25; r = the model's read multiplier; p_in = the first response's model.
- **"Observed" (the table below).** Per response i, the static span sits at [T0, T0+Stot], where T0 = system+tools.
  Its read fraction is `clamp((cache_read_i − T0)/Stot, 0, 1)`. The rest is (re)written at response i's own TTL
  mix, or billed as uncached input when nothing is written. Each response is priced at its own model. This catches
  re-writes after TTL expiry and first requests that hit a warm prefix (resume, fork).
- The two agree to within 10%: spec total $9,874 own / $5,157 at 5.5; observed $10,821 / $6,041. Under the spec
  formula, the first write is 26% of static cost at own prices and 39% at 5.5.

| source | tokens (median per context) | loaded where | contexts | $ / 14 d, own model | $ / 14 d, at Opus 5.5 | share of fleet $ | of which agents (own) |
|---|---:|---|---:|---:|---:|---:|---:|
| global CLAUDE.md | 35,918 | every context (main+sub+wf) | 3,533 | 3,917 | 2,199 | 12.0% | 1,937 |
| system prompt + tool schemas (T0) | 23,278 | every context (main+sub+wf) | 3,747 | 2,155 | 1,080 | 6.6% | 904 |
| project rules agent-operating-lessons.md [infra] | 25,656 | this repo only (main+sub+wf) | 1,703 | 1,824 | 1,001 | 5.6% | 813 |
| skill listing | 11,183 | every context (main+sub+wf) | 3,518 | 1,115 | 627 | 3.4% | 605 |
| project CLAUDE.md [infra] | 2,402 | this repo only (main+sub+wf) | 1,703 | 590 | 308 | 1.8% | 97 |
| MEMORY.md [infra] | 9,448 | this repo only (main+sub+wf) | 1,756 | 573 | 314 | 1.8% | 228 |
| project rules agent-operating-lessons.md [reso] | 16,313 | this repo only (main+sub+wf) | 888 | 350 | 203 | 1.1% | 215 |
| global rules essay (~/.claude/rules/agent-operating-lessons.md) | 2,379 | every context (main+sub+wf) | 3,533 | 339 | 184 | 1.0% | 178 |
| project CLAUDE.md [reso] | 14,496 | this repo only (main+sub+wf) | 888 | 314 | 180 | 1.0% | 201 |
| mission board (~/.claude/rules/00-mission-board.md) | 3,481 | every context (main+sub+wf) | 3,372 | 308 | 176 | 0.9% | 161 |
| deferred tool names | 3,543 | every context (main+sub+wf) | 3,372 | 265 | 153 | 0.8% | 151 |
| SessionStart hook context | 3,980 | main only | 839 | 238 | 128 | 0.7% | 0 |
| project rules bottle-generation-ledger.md [reso] | 19,287 | this repo only (main+sub+wf) | 330 | 215 | 138 | 0.7% | 74 |
| project rules agent-operating-lessons.md [other repos] | 8,902 | that repo only (main+sub+wf) | 606 | 142 | 78 | 0.4% | 94 |
| agent listing | 2,436 | main only | 640 | 131 | 72 | 0.4% | 0 |
| MEMORY.md [reso] | 4,320 | this repo only (main+sub+wf) | 888 | 107 | 62 | 0.3% | 63 |
| MEMORY.md [other repos] | 6,470 | that repo only (main+sub+wf) | 751 | 84 | 46 | 0.3% | 55 |
| project rules agent-teams.md [reso] | 3,130 | this repo only (main+sub+wf) | 888 | 68 | 39 | 0.2% | 43 |
| session_context (gitStatus, userEmail) | 497 | every context | 3,600 | 63 | 35 | 0.2% | 32 |
| small setup attachments (env, model, auto_mode, date, …) | 172 | every context | 3,602 | 58 | 32 | 0.2% | 9 |
| memory-block wrapper text | 424 | every context with memory | 3,533 | 45 | 25 | 0.1% | 22 |
| MCP server instructions | 814 | main only (at start) | 601 | 30 | 17 | 0.1% | 0 |
| UserPromptSubmit hook context (1st prompt only) | 389 | main only | 548 | 21 | 11 | 0.1% | 0 |
| **all static attachments (excl. system+tools)** | | | | **10,821** | **6,041** | **33.3%** | **4,789** |

Notes:

- Median tokens are over the window, while the files grew. The global CLAUDE.md median is 35.9k, but it is 40.4k today.
- "reso" includes its worktrees (`wt-pool-*`); the repo is identified by the AutoMem path, which always names the
  canonical repo.
- **By context type**, static attachments cost:
  - main: $5,839 own / $3,184 at 5.5, which is 30% of main spend ($19,747);
  - subagent: $764 / $414, 36% of $2,098;
  - workflow agent: $4,218 / $2,443, 40% of $10,673.
- **Re-writes are rare.** Only 1.1% of later main-thread responses, 0.5% of subagent responses and 0.8% of workflow
  responses re-wrote more than half of the static span (TTL expiry). Nearly all static cost is steady-state reads
  plus the one first write.
- **Mid-session re-injection** (not in the table):
  - memory files were re-attached 85 times in 73 main sessions, 135k chars each. 15 of those carried only the
    mission board, so a changed file on disk is re-appended.
  - SessionStart context was re-attached 91 times, on resume and compact.
  - MCP instructions arrive after the first response in 2,371 workflow agents (2.9k chars each).

## 4. Volatility (MEASURED, `scripts/sp_volatility.py` → `static-prefix-volatility.json`; content hashes only)

- **distinct** = distinct content versions over 14 days.
- **Δ consecutive** = share of chronologically consecutive contexts, within the same repo or context type, whose
  content differs.

| block | contexts | distinct | Δ consecutive | distinct/day | position |
|---|---:|---:|---:|---:|---|
| SessionStart hook context | 964 | 840 | **88.6%** | 56 | main only; before the prompt in transcript order |
| environment (cwd, …) | 1,049 | 546 | 57.9% | 37 | per-turn attachment |
| MCP server instructions | 722 | 18 | 44.5% | 5.7 | after the prompt; connect race |
| session_context (gitStatus) | 3,600 | 611 | 24.1% | 43 | right after the memory block |
| **mission board** | 3,375 | **534** | **22.7%** | **37** | **memory block position 1 (99.9% of contexts)** |
| skill listing | 3,518 | 139 | 21.0% | 12 | after the prompt |
| deferred tool names | 3,516 | 130 | 20.6% | 19 | after the prompt |
| project CLAUDE.md [infra] | 1,911 | 7 | 20.8% | 1.6 | memory position 3 |
| project rules [infra] | 1,704 | 101 | 10.5% | 7.6 | memory position 4 |
| agent listing | 769 | 16 | 9.7% | 3.5 | |
| MEMORY.md [infra] | 1,757 | 35 | 3.6% | 3.2 | memory position 5 (last) |
| global CLAUDE.md | 3,589 | 18 | 4.6% | 2.3 | memory position 0 |
| global rules essay | 3,589 | 6 | 2.8% | 1.3 | memory position 2 |
| date | 3,602 | 20 | 1.5% | 2.3 | last |

The project CLAUDE.md [infra] has only 7 versions, yet 20.8% of consecutive pairs differ. That points to worktrees on
different branches alternating, not frequent edits.

**Where volatile values sit relative to cache breakpoints.**

- **The system block.** It is split into a global-scope static part and an org-scope dynamic part. The dynamic part
  carries cwd, model, `<total_tokens>` and the auto-memory path, per the sibling's `binary-and-cache.md`. It is
  cached with its own breakpoint, but its volatile values restrict the hit to the same cwd and config dir. The
  global part (tools + static system) is what every first request reads.
- **The first user message** has no breakpoint until the conversation's last message. Inside it, the memory block
  comes first, and within that block files follow the binary's load order: user CLAUDE.md → user rules
  (alphabetical, so `00-mission-board.md` goes first) → project CLAUDE.md → project rules → AutoMem MEMORY.md. So
  **yes, a volatile value precedes stable content inside the cacheable span.** The mission board's
  `rendered <timestamp>` line, its day counts and its free-text rows sit at position 1. The rules essay, the
  project CLAUDE.md and the 25-43k-token project rules files follow it. gitStatus (session_context) follows the
  whole block.
- **Why it costs nothing today.** No context ever reads past T0 on its first request, and inside one session the
  first message is written once and read every turn: re-writes are ~1%.
- **Why it matters for the fix.** A breakpoint after the setup attachments (the sibling's proposal) would have a real
  population. **116 of 123 multi-agent workflow runs gave every agent a byte-identical memory block**, and 2,199 of
  2,396 agents (92%) match their run's majority full setup (memory + skill listing + deferred tools +
  session_context + date). Only 692 of 2,669 workflow agents start within 20 s of their run's first agent, the
  launch wave that would miss anyway. Across sessions, though, the mission board changes 37 times a day at
  position 1, so a cross-session hit would reach only the global CLAUDE.md. Moving the board last, or out of the
  memory block, costs nothing and preserves that option.

## Opportunities

| # | change | est. saving / 14 d (own · at 5.5) | how estimated | risk | category |
|---|---|---|---|---|---|
| 1 | Workflow and research agents run as a custom agent type with `omitClaudeMd: true` (passed as `agentType`), with the rules they need restated in the brief | ceiling **$4,184 · $2,396**; ~80% removable ⇒ **~$3,350 · $1,920** | the memory-file rows restricted to subagent + workflow contexts; the 80% leaves room for a 2-5k-token rule brief | medium: agents lose operator rules (git safety, comms) unless restated | flag |
| 2 | Drop the skill listing from agent contexts (tool restriction or agent config) | **$605 · $348** | the skill-listing row restricted to agents; Skill is called in 0.2-0.8% of agents | low | flag |
| 3 | Take the mission board out of always-loaded memory and deliver it as main-only SessionStart context (agents never get it); at minimum rename it so it sorts after the stable files | agent share **$161 · $94**, plus removing the most volatile block from memory position 1 and the mission-board-only re-injections | the mission-board row restricted to agents | low | direct |
| 4 | Trim the infra project rules file back to its own stated ~43K-char budget (it is at 74K) | **~$770 · ~$420** | 42% of its row ($1,824 · $1,001) | low-medium (content cut; others audit wording) | flag |
| 5 | Global CLAUDE.md slimming (audited separately) | each 10% cut = **$392 · $220** | 10% of its row | per-cut | flag |
| 6 | Cache breakpoint after the setup attachments, so workflow siblings read the ~95k-token setup instead of re-writing it (binary change, or the untested `--append-subagent-system-prompt-file` workaround) | **~$890 · ~$750** | 2,401 × (1 − 692/2,669) × 0.92 ≈ 1,640 agents × 95k median × (1.25 − r) × p_in | low quality risk; feasibility unproven | propose |
| 7 | Shorten the longest skill descriptions so the listing covers all skills within budget (40/84 and 69/116 now show no description) | ~0 $ (the budget is fixed); a quality gain | /context rows | low | flag |
| 8 | Keep ms365's ~190 deferred tool names out of agents (per-agent MCP config) | ≤ **$151 · $89** | the deferred-names row restricted to agents | low | flag |

1 + 2 + 3 overlap only in the mission board, which is counted in both 1 and 3. With 3 inside 1, the agent-side total
is ≈ $3.95k own / $2.27k at 5.5 per 14 days, ~12% of fleet spend.

## Gaps

- The permission check refused writing a `.claude/rules` calibration tree in the output dir. Blocks were counted
  instead via `--append-system-prompt-file` into `/context`, at 0.1k resolution. The scratch copies were deleted and
  only the counts are kept.
- The wire position of SessionStart additionalContext relative to the memory block could not be resolved from the
  minified binary. Memory-first order is inferred from this agent's own rendered context.
- The 156 main contexts on 2.1.114/2.1.183 (~$100 of spend) record no `instructions` attachment, so their memory
  tokens are uncounted.
- After a /compact (39 in 14 days), the static span is assumed to stay at the front.
- System+tools T0 is a first-response cache_read proxy; `/context` does not itemize loaded built-in tool schemas.
- Per-context tokens are chars ÷ a per-source ratio measured on one or two real instances (2.0-2.87 chars/token).
- Side requests (prompt-suggestion and away-summary forks) re-read the whole prefix, static part included, and are
  not in transcripts (EXTRACT L6), so their static-prefix share is not included here.

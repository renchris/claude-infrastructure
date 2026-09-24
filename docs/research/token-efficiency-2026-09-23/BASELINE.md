# Baseline: what this harness spends tokens on (2026-09-09 → 2026-09-23)

**Scope.** Claude Code 2.1.280 plus the `~/.claude` layer deployed from `claude-infrastructure`, all five config
dirs, 14.96 days, 162,406 API responses in 4,086 contexts and 1,052 session trees (tasks). Source of every fleet
number: `data/extract.sqlite` (`xdup=0`), built and checked against `cc-quota-price --census` to ≤0.001% on every
input class (`data/EXTRACT.md`). This file synthesizes the eight reports in `measure/`; it adds no new fleet parse
beyond the three `scripts/synth_*.py` below.

**Weights.** Dollars are **list-price weights, not charges**: the fleet is subscription-billed. Each response is
priced at its own model (`own`) and the same token stream is re-priced at Opus 5.5 (`@5.5`: $4/$20, cache read
0.05x), the default since 2026-09-22. Cache writes cost 1.25x input at 5m TTL and 2x at 1h.
🚨 **The binding meter is not list price.** The operator's own experiment (`docs/plans/USAGE_TELEMETRY_100P.md`
§2.8, cited in `model-config.yaml`) bounds cache reads at **≤¼ of list weight, plausibly 0** on the plan meter;
writes and output drive it. So every table below also carries a **meter proxy** (writes + output + uncached,
reads at 0). Where the two weightings rank a change differently, `OPPORTUNITIES.md` says so.

**Labels.** MEASURED = counted from the extract or a named instrument. ESTIMATED = derived by a named method.

**Re-derive** (from `/tmp`, under `nice -n 10`): the measure scripts named in each `measure/*.md`, then
`scripts/synth_baseline.py` (→ `data/synth_baseline.json`, the reconciled table),
`scripts/synth_opportunities.py` (→ `data/synth_opportunities.json`) and
`scripts/synth_side_requests.py` (→ `data/synth_side_requests.json`).

## Answer first

1. **Fleet: $32,517 own / $18,319 @5.5** (MEASURED). By billing type: cache read 58.4%, cache write 1h 15.8%, cache
   write 5m 12.5%, output 13.3%, uncached 0.02%. Meter proxy: **$13,512 own / $10,128 @5.5**.
2. **The biggest source is the memory files: $8,886 own (27.3%)**, loaded into every context including 2,691
   subagent and workflow-agent contexts that pay **$4,184** of it. The global CLAUDE.md alone is 12.2% of all spend.
3. **The next two are the conversation re-reading itself:** the model's own earlier turns (Bash commands, retained
   thinking, text: **19.0%**) and tool output (**18.3%**, Bash 14.4%). A main-thread result is re-read ~148 times.
4. **Cost is driven by context length, not rate.** Hit rate is 97.4%; a main thread re-reads a mean 331.5k tokens
   per response against a 123k first request. Per task: mean $30.91, median $7.33; the top 10% of tasks carry 67%.
5. **Three cross-cutting drivers** sit on top of the sources: Stop-hook forced turns ($3,623, 11.1%), cache
   rewrites after a miss ($3,316, 10.2%; idle >1h alone $2,149), and side requests the transcripts never record
   (**+$884 own / +$452 @5.5, ESTIMATED, outside the $32.5k**).

## (a) Harness map

| Layer | How it is assembled (2.1.280 binary) | What the `~/.claude` layer controls | What it cannot control | Measured size / cost (source) |
|---|---|---|---|---|
| **Request order and breakpoints** | tools → system → messages. System is split at `__SYSTEM_PROMPT_DYNAMIC_BOUNDARY__` into a global-scope static part and an org-scope dynamic part (cwd, model, `<total_tokens>`, auto-memory path, then any `--append-system-prompt`), each cached. **One message breakpoint, on the last message**; a second "fork pin" is server-gated (`tengu_basalt_spur`). | `--append-system-prompt(-file)` (lands in the dynamic system block, which has a breakpoint); `claudeMdExcludes` | Breakpoint placement; message order; that setup attachments sit in the first user message **with no breakpoint after them** | Global block shared across all sessions: 10,459 tokens (MEASURED, exp. a). Same-cwd identical prefix re-read in full (58,144 / 0 written); different cwd re-writes everything after the global block (`binary-and-cache.md`) |
| **System prompt + built-in tool schemas** | Built in; built-in tools partly deferred server-side (`tengu_non_deferrable_builtins`) | `ENABLE_TOOL_SEARCH` (all-or-nothing), per-MCP-server `alwaysLoad` | Base prompt text; per-tool deferral of built-ins | First-response cache read (proxy): main 14.3k, subagent 9.2k, workflow 7.8k tokens on 2.1.280 (28.5k / 9.3k / 23.3k on 2.1.260). **$2,155 own (6.6%)** (`static-prefix.md`) |
| **Memory files** | Attachment in the first user message, load order user CLAUDE.md → user rules (alphabetical, so `00-mission-board.md` first) → project CLAUDE.md → project rules → auto-memory MEMORY.md. HTML comments are stripped. Re-attached mid-session when a file changes (85 times) | All content; `claudeMdExcludes`; custom-agent `omitClaudeMd: true` (removes user/project/local/AutoMem memory; measured 42,275 → 1,795-token prefix) | That every Agent-tool and Workflow agent inherits them by default (`workflow-subagent` has no omitClaudeMd) | `/context`: 48.2k (`/tmp`), 87.7k (infra), 137.8k (reso) tokens. **$8,886 own (27.3%)**, agents $4,184 |
| **Listings** | Skill listing (budget = 1% × window × 3 chars/token = **30,000 chars** at 1M; greedy by per-account usage score; ~30 own skills name-only), agent listing (main only), deferred tool names (202, ms365 ~190), MCP instructions (main at start; agents after response 1). No `Skill` in an agent's tools ⇒ no skill listing | Descriptions, `skillOverrides`, `skillListingBudgetFraction`, `skillListingMaxDescChars`, `SLASH_COMMAND_TOOL_CHAR_BUDGET`, agent `tools:`, MCP config | The budget formula; server-side deferral | Skill listing 11.2k tokens (MEASURED count_tokens), in 3,518 contexts. Listings total **$1,542 own (4.7%)** at start + $339 re-sent/skill bodies (`listings.md`, `static-prefix.md`) |
| **Hooks** | 104 registrations, 82 scripts, 21 events. Model-visible: `additionalContext`, block reasons, SessionStart stdout. Output >10,000 chars is persisted with a 2,000-char preview. **Every command-hook Stop reason reaches the model twice** (2,588 of 2,588) | All hook code and text | The double send; the 10k persistence cap | Injected text **$695 own (2.1%)** in the reconciled table ($566 by the hooks report's own pricing); forced turns **$3,623 (11.1%)** (`hooks.md`) |
| **Tool results** | Bash inline cap 30,000 chars (`bashOutputMaxChars`, 4k-128k; none set), then persisted with a 2,000-char preview; Read 2,000 lines / 25k tokens, `N<TAB>` line prefix (remote flag); MCP 25k tokens; `Shell cwd was reset` note; a time-based microcompact exists behind a remote flag and is invisible in transcripts | Settings keys above; `additionalDirectories`; our CLIs' output | Read format, microcompact, WebSearch reminder text | Tool results **$5,948 own (18.3%)** in the reconciled table; Bash 84% of calls. Format overhead only **$192 (0.6%)** (`output-formats.md`) |
| **History, compaction, recycle** | History kept verbatim; **prior thinking is re-sent every turn** (coefficient 1.00 on prior output, n=90,327). Compaction is a cache-reading fork; 39/39 compactions manual; 49 context-shrink events; the ceiling is a hard refusal | When to recycle / hand off (`handoff-fire.sh --recycle`, `waiting-recycle.sh`, `boundary-handoff.sh`), `DISABLE_AUTO_COMPACT` | Microcompact | Model's own turns re-read **$6,164 (19.0%)**; carry-over after shrink $614 (`growth.md`) |
| **Subagents, workflows, teammates, dispatched sessions** | Agent tool (362 contexts), Workflow `agent()` (2,669 contexts; default type `workflow-subagent`, hard-coded `tools:["*"]`; `opts.agentType` selects a custom agent), named teammates (Agent-tool contexts), dispatched sessions (`handoff-fire.sh` → new TUI main threads, indistinguishable from human-attended ones: both `entrypoint=cli`) | Agent definitions, briefs, workflow scripts, `agentType`, fan-out policy (CLAUDE.md) | Workflow agent defaults | Workers (subagent + workflow) **39.3% of fleet $**; 106 of 1,052 tasks use them; median worker share 62% inside those; returns to the parent only **$96 (0.3%)** (`census.md`, `growth.md`) |
| **Models and caching** | TTL resolution: env `CLAUDE_CODE_(SUBAGENT_)PROMPT_CACHE_TTL` → settings `promptCacheTtl`/`subagentPromptCacheTtl` → frontmatter `experimental.cacheTtl` → `ENABLE_PROMPT_CACHING_1H` (1h for **everything**) → subscriber allowlist (1h for `repl_main_thread*`, `sdk`, `auto_mode`; 5m otherwise). Minimum cacheable prefix 512 tokens on Fable 5/5.1 (`model-config.yaml`); irrelevant here, the smallest cached block is ~7.8k | TTL settings; model per launch / per agent / per slot; effort | Per-model cache (a model switch re-writes: 45 events, $136) | Opus 5 86.1%, Fable 5.1 8.1%, Opus 5.5 5.3%, other 0.5% of $. Main writes 1h; every agent writes 5m. Validated TTL cliff: main hit rate 95.7% at 55-60 min, 24.1% at 60-65, 2.4% beyond (`cache-writes.md`) |
| **Side requests** | Forks that read the parent cache (prompt suggestion **forced on by env**, away summary forced on, compaction, `/btw`), plus fresh Haiku/Sonnet calls (titles, `/goal` evaluator, prompt hooks, auto-mode classifier) | `CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION`, `CLAUDE_CODE_ENABLE_AWAY_SUMMARY`, goals, hooks | Classifier, titles | **Not in any transcript.** ESTIMATED from cost-state minus extract over 812 sessions, fleet-scaled: **$884 own / $452 @5.5**; Opus 5 fork reads are $650 of it, Haiku $105 (`scripts/synth_side_requests.py`) |
| **Existing telemetry** | Per-response `usage` in transcripts (one record per content block: dedupe on `message.id`); per-session `cost-state`; `cc-quota-price --census`; `cc-ctx-audit`; ephemeral `/tmp/cc-telemetry` | All of it | Side-request and classifier usage | **`cc-quota-price` reads output 46% low** (first record carries a placeholder; EXTRACT.md L1); 2.1.280 agents rarely record final usage (11.1% of responses imputed, totals ±3%) |

## (b) Baseline: cost by source × billing type (reconciled)

Built by `scripts/synth_baseline.py`. **Rows sum to the fleet total and every billing column sums to the census
total** (write $9,195.5, read $19,005.8, uncached $6.8, output $4,309.3 own). Partition: input side = initial prefix
($13,419, `growth.json`) + content added after the first response ($14,789, `growth.json`, conserves to 1.0000);
initial prefix = static sources (`static-prefix-cost.json`, $12,976) + first prompt / brief ($503, priced here with
the output-formats persistence weights) + residual (−$61). The **cache-read column is the history re-read** of each
source: a source's tokens are written once, then re-read on every later turn of its context.

| Source | Cache write $ | Cache read (re-read) $ | Output $ | **Total own $** | **% of fleet** | Total @5.5 $ | % @5.5 | Meter proxy $ (write+output) | % of meter | Basis |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| System prompt + tool schemas | 438 | 1,718 | – | 2,155 | 6.6% | 1,080 | 5.9% | 438 | 3.2% | E: first-response cache-read proxy; write split E |
| Memory: global CLAUDE.md | 1,285 | 2,677 | – | **3,962** | **12.2%** | 2,224 | 12.1% | 1,285 | 9.5% | E: chars × /context ratio (2.55-2.6 c/t) |
| Memory: global rules (mission board 0.9%, rules essay 1.0%) | 209 | 438 | – | 647 | 2.0% | 360 | 2.0% | 209 | 1.6% | E |
| Memory: project CLAUDE.md + rules (infra rules 5.6%, reso 3.0%) | 1,122 | 2,391 | – | **3,513** | **10.8%** | 1,953 | 10.7% | 1,122 | 8.3% | E |
| Memory: MEMORY.md (auto-memory) | 238 | 526 | – | 764 | 2.3% | 422 | 2.3% | 238 | 1.8% | E |
| Memory files re-attached mid-session | 82 | 101 | – | 183 | 0.6% | 112 | 0.6% | 82 | 0.6% | M delta, E split |
| Listings at start: skills 3.4%, deferred names 0.8%, agents 0.4%, MCP 0.1% | 494 | 1,048 | – | 1,542 | 4.7% | 869 | 4.7% | 494 | 3.7% | E (skill listing tokens M) |
| Listings re-sent + skill bodies | 127 | 212 | – | 339 | 1.0% | 186 | 1.0% | 127 | 0.9% | M delta, E split |
| Hook injections (SessionStart, UserPromptSubmit, Stop reasons ×2, PostToolUse) | 147 | 548 | – | 695 | 2.1% | 350 | 1.9% | 147 | 1.1% | M delta, E split |
| Harness notices (`total_tokens_reminder` $263, edited-file, queued-command wrappers, env) | 221 | 472 | – | 693 | 2.1% | 373 | 2.0% | 221 | 1.6% | M delta, E split |
| User messages (first prompts/briefs $503, commands, queued, peer/teammate mail, task notices) | 310 | 576 | – | 886 | 2.7% | 486 | 2.7% | 310 | 2.3% | M/E |
| File reads (Read tool $752 + Bash sed/cat/head/tail/awk/git show = 40.8% of Bash results) | 1,000 | 1,663 | – | **2,663** | **8.2%** | 1,456 | 7.9% | 1,000 | 7.4% | M delta; Bash class share E (quote-aware program classifier) |
| Search + web results (Bash grep/find/ls 15.3% of Bash, WebFetch, WebSearch, ToolSearch) | 374 | 707 | – | 1,081 | 3.3% | 588 | 3.2% | 374 | 2.8% | as above |
| Command + other tool output (other Bash 43.9%, MCP, background-shell notices) | 768 | 1,435 | – | 2,204 | 6.8% | 1,189 | 6.5% | 769 | 5.7% | as above |
| Subagent / workflow returns (incl. async acks) | 41 | 55 | – | 96 | 0.3% | 52 | 0.3% | 41 | 0.3% | M |
| Re-read of the model's own Bash commands (incl. heredoc scripts) | 760 | 1,896 | – | **2,657** | **8.2%** | 1,373 | 7.5% | 761 | 5.6% | M delta, E split |
| Re-read of retained thinking | 937 | 1,610 | – | **2,548** | **7.8%** | 1,387 | 7.6% | 938 | 6.9% | M (coef 1.00), E split |
| Re-read of other tool inputs (Write, Edit, Agent/Workflow briefs) + text | 358 | 599 | – | 959 | 2.9% | 523 | 2.9% | 358 | 2.6% | M delta, E split |
| History carry-over after 49 context shrinks (composition unknown) | 268 | 346 | – | 614 | 1.9% | 337 | 1.8% | 268 | 2.0% | M |
| Output generated: tool calls | – | – | 2,077 | 2,077 | 6.4% | 1,557 | 8.5% | 2,077 | **15.4%** | M total, E split by appended-token share |
| Output generated: thinking | – | – | 2,033 | 2,033 | 6.3% | 1,523 | 8.3% | 2,033 | **15.0%** | same |
| Output generated: visible text | – | – | 200 | 200 | 0.6% | 150 | 0.8% | 200 | 1.5% | same |
| Reconciliation residual (uncached $4 + method gap) | 15 | −10 | – | 9 | 0.0% | −229 | −1.3% | 19 | 0.1% | the two pricing methods differ by $61 own / $264 @5.5 on the initial prefix |
| **Total** | **9,195** | **19,006** | **4,309** | **32,517** | 100% | **18,319** | 100% | **13,512** | 100% | uncached $6.8 is inside the rows |
| *Side requests (not in transcripts; not in the total)* | *≈0* | *≈700* | *small* | *+884* | *+2.7%* | *+452* | *+2.5%* | *≈180* | | *E: cost-state − extract* |

**Cross-cutting drivers.** These are not extra rows: each is a cause whose cost is already spread across the rows.

| Driver | $ own | % | $ @5.5 | Source |
|---|---:|---:|---:|---|
| Worker contexts (subagent + workflow agents) | 12,771 | 39.3% | 7,652 | `census.md` |
| Stop-hook forced continuation turns (3,029; 1,973 waste-likely = $939) | 3,623 | 11.1% | 1,649 | `hooks.md` |
| Cache rewrites after a miss (36% of write $) | 3,316 | 10.2% | 2,404 | `cache-writes.md` |
| of which main thread idle >1h (517 wakes, mean 390k prefix) | 2,102 | 6.5% | 1,528 | `cache-writes.md` |
| Tool errors incl. recovery turns ($636 preventable) | 1,184 | 3.6% | 642 | `tool-errors.md` |
| Agent START writes (setup re-written by every sibling) | 1,760 | 5.4% | 1,362 | `cache-writes.md` |

**Billing type by context type** (MEASURED, `census.md`):

| ctx_type | contexts | $ own | share | cache read | cw 5m | cw 1h | output | $ @5.5 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| main | 1,055 | 19,747 | 60.7% | 64.8% | 0.0% | 26.0% | 9.2% | 10,666 |
| workflow_agent | 2,669 | 10,673 | 32.8% | 47.5% | 33.2% | 0 | 19.3% | 6,388 |
| subagent | 362 | 2,098 | 6.5% | 54.5% | 24.9% | 0 | 20.6% | 1,264 |

## (c) Static tokens, cache hits, turns, tools

**Static tokens per request** (MEASURED from rendered first requests; tokens ESTIMATED from chars with measured ratios):

| ctx_type | static attachments, median (p90) | system + tools (2.1.280) | static total | mean prefix per response | static share of a mean request | static share of that ctx's $ |
|---|---:|---:|---:|---:|---:|---:|
| main | 101.9k (140.8k) | 14.3k | ~116k | 331.5k | ~35% | 30% |
| subagent | 94.2k (117.3k) | 9.2k | ~103k | 167.9k | ~61% | 36% |
| workflow_agent | 95.0k (124.3k) | 7.8k | ~103k | 187.4k | ~55% | 40% |

Headless `/context` totals (MEASURED, count_tokens): 64.1k from `/tmp`, 103.7k in claude-infrastructure, 159.6k in reso.

**Cache hit rate** (MEASURED, `census.md`): read / (read + write + uncached).

| ctx_type | overall | first request | later requests | mid-session misses (≥50% of a ≥20k prefix re-written) |
|---|---:|---:|---:|---:|
| main | 98.3% | 17.1% | 98.6% | 702 ($2,655) |
| workflow_agent | 95.5% | 14.6% | 97.7% | 366 ($656) |
| subagent | 96.8% | 7.0% | 97.9% | 61 ($66) |
| fleet | 97.4% | | | |

**Turns (responses) per task** (MEASURED; task = one session tree):

| | mean | median | p75 | p90 | p99 |
|---|---:|---:|---:|---:|---:|
| responses | 154 | 42 | 112 | 303 | 1,772 |
| $ own | 30.91 | 7.33 | 21.72 | 70.39 | 385.49 |
| $ @5.5 | 17.41 | 4.38 | 12.04 | 39.34 | 217.75 |
| contexts | 3.88 | 1 | 1 | 2 | 58 |
| human prompts | 2.61 | 1 | 2 | 7 | 25 |

Responses per context: main 79.5, subagent 42.7, workflow agent 23.6. $ per human prompt: $11.8. Headless `-p` runs are
22% of tasks and 0.5% of $.

**Per tool** (MEASURED, `tool-errors.md`; share of contexts calling it at least once; 181,127 results):

| tool | calls | share of calls | main / subagent / workflow reach | error rate | note |
|---|---:|---:|---|---:|---|
| Bash | 152,775 | 84.3% | 78.2% / 94.5% / 88.4% | 2.6% | 75% of tool-result tokens; 2,571 of its 3,967 errors are informational non-zero exits |
| Read | 8,150 | 4.5% | 27.9% / 32.0% / 39.8% | 0.9% | 54% of results are images; files are mostly read through Bash |
| WebSearch | 4,823 | 2.7% | 7.0% / 27.6% / 19.0% | 0.4% | |
| WebFetch | 4,309 | 2.4% | 5.2% / 20.7% / 10.5% | 0.7% | |
| Edit | 3,435 | 1.9% | 19.0% / 12.4% / 5.3% | 4.7% | 79 of 109 read-first errors hit files read via Bash |
| StructuredOutput | 2,172 | 1.2% | – / – / 78.0% | 4.2% | 78 missing required fields |
| ToolSearch | 1,519 | 0.8% | 41.3% / 32.9% / 24.2% | 0.0% | 1,011 ToolSearch-only responses, $230 |
| Write | 1,332 | 0.7% | 21.9% / 55.8% / 10.1% | 2.2% | |
| Agent | 675 | 0.4% | 10.5% / 0.3% / – | **18.4%** | mostly capacity-admit refusals (Opus 5.5 29%, Fable 28%) |
| SendMessage / Monitor / TaskStop / Skill / Workflow | 332 / 277 / 258 / 237 / 156 | ≤0.2% each | Skill 17.3% / 0.8% / 0.2% | 4.3% / 2.2% / 5.4% / 0% / 8.3% | |
| ms365 (all tools) | 748 | 0.4% | 3.0% of main sessions | 5.5% | |
| Grep / Glob | 11 / 10 | ~0 | | 6 and 3 "No such tool" | effectively unused |

## (d) The five biggest sources

| # | Source | $ own (%) | $ @5.5 (%) | Meter proxy (% of meter) | Why it is big |
|---|---|---:|---:|---:|---|
| 1 | **Memory files** (global CLAUDE.md 12.2%, project files 10.8%, MEMORY.md 2.3%, global rules 2.0%, re-attach 0.6%) | 9,069 (27.9%) | 5,071 (27.7%) | 2,936 (21.7%) | ~85-140k tokens in every context, re-read every turn; agents pay $4,184 for rules written for the lead |
| 2 | **The model's own earlier turns, re-read** (Bash commands 8.2%, thinking 7.8%, other inputs + text 2.9%) | 6,164 (19.0%) | 3,283 (17.9%) | 2,057 (15.2%) | Heredoc scripts and retained thinking ride every later request. Thinking is reasoning continuity: **keep it** |
| 3 | **Tool output, re-read** (file reads 8.2%, command output 6.8%, search/web 3.3%) | 5,948 (18.3%) | 3,233 (17.6%) | 2,143 (15.9%) | Bash results in main threads are re-read ~148 times each; `sed -n` slices alone are ~$1.05k |
| 4 | **Output generation** (tool calls 6.4%, thinking 6.3%, text 0.6%) | 4,309 (13.3%) | 3,230 (17.6%) | 4,309 (**31.9%**) | The largest single item on the binding meter |
| 5 | **System prompt + tool schemas and listings** (6.6% + 5.8%) | 4,036 (12.4%) | 2,135 (11.7%) | 1,059 (7.8%) | Fixed per context; the skill listing is capped at 30,000 chars in every context, agents included |

On the meter proxy the order changes: **output first (32%), then memory files (22%)**, and the write classes
matter most: START 32%, incremental 32%, rewrites 36% of write $ (`cache-writes.md`).

## Where the reports disagree, and which number this file uses

| Quantity | Reports | Used | Why |
|---|---|---|---|
| Static / setup prefix | census $12.2k upper bound (37.5%); static-prefix $12,976 (40%); growth initial $13,419 | static-prefix per source, growth for the total | Growth conserves to 1.0000 against input-side spend; static-prefix prices each source with a count_tokens-measured ratio. The census figure excludes rewrites and includes the first prompt. Residual between methods: −$61 own, −$264 @5.5 (shown) |
| Skill listing | listings $866 own (chars/3); static-prefix $1,115 | static-prefix | 30,103 chars = 11.2k tokens by count_tokens (2.69 c/t), not 10.0k; different reader rule too. Listing savings in `listings.md` are ~12% low |
| Hook text | hooks $566 own; reconciled table $695 | table for the partition, hooks for per-script attribution | Hooks prices at 2.5 c/t and drops items at a shrink; growth uses measured deltas. The $129 gap is within ratio error |
| omitClaudeMd saving | static-prefix ~$3,350 own / $1,920 @5.5; binary-and-cache ≈$1.3k @5.5 (first writes only, all retained history); census ~$2k (ratio) | static-prefix | Window-bounded, counts re-reads, per-source measured |
| Shared-setup breakpoint | cache-writes ≤$1,011 @5.5; static-prefix ~$890 own / $750 @5.5; binary-and-cache ~$1.7k (all history) | range $750-1,011 @5.5 | cache-writes requires a warm same-session same-model sibling within 5 min; static-prefix excludes the launch wave. Both window-bounded |
| Main at uniform 5m TTL | census +$4.1k own (+23%); cache-writes +$3,547 own / +$2,841 @5.5 | cache-writes | It keeps the shared system+tools block warm and validates the TTL cliff empirically; census is an upper bound. Same verdict |
| Bash file-read share | growth ≥32.3% (120-char heuristic); output-formats program classifier | 40.8% (this file) | The quote-aware classifier skips `cd`/`export` preambles, which hide 13-20% of commands from the heuristic |
| Read line numbers | growth $23 (0.44 t/c); output-formats $27 / $15 (tokenizer probe, 0.568 t/c per removed char) | output-formats | Measured with the tokenizer. Both negligible |
| Tool-result $ | output-formats $5,114 (ignores rewrites); growth-based $5,948 | growth-based | Includes rewrites after misses; output-formats says its own weight is biased low |
| Wire order of memory vs first prompt | hooks: prompt precedes memory in 851/858 transcripts; static-prefix: memory first on the wire | static-prefix + binary-and-cache | Transcript order is not wire order; either way no breakpoint follows the setup, so siblings read only the ~10-19k global block (MEASURED 13.2% first-request read share) |

## Gaps

- **The meter weighting is bounded, not measured per class.** Cache reads are ≤¼ of list weight and plausibly 0;
  write and output meter coefficients relative to each other are not separated. Both weightings are shown.
- **Side requests** are estimated from a cost-state delta over 812 sessions; per-feature frequencies (prompt
  suggestion vs away summary vs compaction) and the auto-mode classifier's cost are not separable or not recorded.
- **Output is imputed** for 11.1% of responses (2.1.280 agents): totals ±3%, per-task $ for agent-heavy trees is noisy.
- **No tokenizer on transcripts.** Source splits inside measured deltas use fitted chars-to-tokens ratios (2.2-2.7
  c/t); group totals are exact. The output split by kind (tool calls / thinking / text) is an appended-token share.
- **Time-based microcompact** (remote flag) may clear old tool results at request build; if active, re-read costs of
  old tool output are overstated. Not observable in transcripts.
- **`entrypoint=cli` merges human-attended and dispatched sessions**; typed and keystroke-injected prompts share
  `promptSource=typed`. "Human prompt" counts are upper bounds.
- **The `total_tokens_reminder` trigger** ($263) and why memory files re-attach mid-session were not established.
- **Not measured:** hook latency, the goal evaluator's actual cache behaviour, per-agent turn counts for the
  omitClaudeMd experiment, and 156 main contexts on 2.1.114/2.1.183 (~$100) whose memory files are not recorded.
- The first-prompt/brief row prices items with the output-formats persistence weights (no rewrites), then the
  billing split is forced to the census totals; the per-row write/read split of static sources is ESTIMATED.

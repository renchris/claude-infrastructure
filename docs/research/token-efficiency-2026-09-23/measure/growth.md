# Conversation growth: what fills the context after the first request (persistence-weighted)

Window: 2026-09-09 to 2026-09-23, the shared extract (`data/extract.sqlite`, `xdup=0`). Dollars are **list-price
weights**. The fleet is billed by subscription quota, not dollars. Every figure is labelled MEASURED (with the script
that produced it) or ESTIMATED (with the method). Machine-readable companion: `growth.json`.

## Headline

1. **Growth is 52% of input-side spend and 45% of all spend** (MEASURED, `growth_cost.py`). Content appended after
   the first response costs **$14,789** of $28,208 input-side spend, against a fleet total of $32,517. Re-priced at
   Opus 5.5 it is **$7,949** of $18,319. Main threads carry $10,630 of it. The by-source split inside that total is
   ESTIMATED, from the fitted chars-to-tokens ratios.
2. **Three sources take two-thirds of growth dollars:**
   - **Bash tool results:** 31.7% ($4,684).
   - **The model's own Bash commands (tool_use inputs), re-read on every later turn:** 18.0% ($2,657). Inline heredoc
     scripts and file writes are a large part of these.
   - **Retained thinking:** 17.2% ($2,548).

   Everything the harness injects mid-run adds up to about 6%: hooks, Stop-hook feedback, the per-turn
   `total_tokens_reminder`, queued commands, edited-file notices, re-attached memory files, MCP deltas and the skill
   listing.
3. **Prior-turn thinking stays in context** (MEASURED from the deltas; the thinking test is below). This is the
   reasoning continuity the spec says to protect. The $2,548 is the price of that continuity. It is not an
   opportunity.
4. **Sparse Read line numbers are not worth building here.** The `N<TAB>` prefixes are 4.8% of Read-result
   characters, and numbering only every 10th line would save ~1.0M tokens, about **$23 over 15 days** (0.07% of spend,
   ESTIMATED). The reason is that the Read tool carries only 5.1% of growth. The model reads files through Bash `sed`
   and `cat` instead, which is ≥32% of Bash result characters and has no line numbers.
5. **Subagent and workflow returns are small fleet-wide.** Returns are **0.8%** of main-thread growth dollars, and the
   Agent/Workflow/SendMessage briefs are 1.75%. The 46%-of-a-window incident in `context-ceiling-397428c4` was one
   outlier session, not the fleet pattern.

## Method

**Population and sample.**
- Full population: every file in the extract, 4,298 files with usage. All dollar and token totals below are computed
  directly over it, so nothing is extrapolated from the sample.
- Stratified sample, as the task asked: 180 files, 60 per context type (main, subagent, workflow agent). Each type is
  split into size quartiles by `n_resp`, and files are drawn round-robin across projects: 84 projects, 3-1,306
  responses each (`growth_work/sample.tsv`, seed 20260923).
- The sample is used for the calibration fit and as a check on extrapolation. Scaling sample per-file growth dollars
  by stratum size (context type x size quartile) reproduces the direct population sum within about 13%:

| context type | sample-extrapolated | direct | ratio |
|---|---:|---:|---:|
| main | $11,615 | $10,619 | 1.09 |
| subagent | $712 | $818 | 0.87 |
| workflow agent | $2,968 | $3,336 | 0.89 |

  Source shares in the sample track the fleet for the big sources: Bash results 31% vs 32%, Bash inputs 20% vs 18%.
  They diverge for rare ones: one sample file with a context shrink puts `context_rewrite_carryover` at 14% vs 4%.
  **Use the direct figures.**

**Calibration** (MEASURED, `growth_pairs.py` then `growth_fit.py`).
- Two consecutive real responses s, s+1 form a pair. For each pair, the prefix delta D = P(s+1) - P(s), where
  P = input + cache_creation + cache_read, is the exact token count appended between the two requests.
- There are 136,265 clean pairs: no images, no compaction, no API errors, and response s recorded its final output.
- Each pair's delta was regressed on the model-visible characters of the items appended in between, by class, plus a
  per-item overhead. The fit is robust OLS: fit, drop residuals beyond 6 MAD, refit.
- Predicted over observed on all rows: 0.989. Fitted tokens per character:

| class | all pairs | sample (9,364 pairs) |
|---|---:|---:|
| tool_result Read | 0.441 | 0.454 |
| tool_result Bash | 0.434 | 0.437 |
| tool_result WebFetch/WebSearch | 0.381 | 0.392 |
| tool_result MCP | 0.541 | 0.513 |
| tool_result other | 0.396 | 0.355 |
| attachments (rendered) | 0.377 | 0.398 |
| user prompts | 0.440 | 0.590 (few prompts in sample) |
| meta user messages | 0.393 | 0.392 |
| assistant text (fit on output tokens, no-thinking responses) | 0.364 | 0.376 |
| tool_use input JSON | 0.416 | 0.425 |
| + per tool_result | 32 tok | 35 |
| + per prompt/meta message | 44 tok | 30 |
| + per tool call (output side) | 65 tok | 69 |
| + per assistant message | 20 tok | 12 |
| image block (median residual, 3,889 groups) | 1,022 tok | |

- **Independent cross-check:** headless `/context` counts `~/.claude-secondary/CLAUDE.md` at 40.4k tokens for
  105,278 characters, which is 0.384 tokens per character. The mission board gives 0.396 and
  agent-operating-lessons 0.382. The fitted attachment ratio is 0.377.
- These models tokenize at **~2.3-2.7 characters per token**, not the ~4 people usually assume.

**Does prior-turn thinking stay in context?** Yes. Test: D = b·output(s) + a·visible assistant chars + user-side
terms. If thinking were stripped, b would be about 0 and the visible-character coefficients would carry about 0.4. If
the whole message is re-sent, b is about 1 and those coefficients are about 0. Results by subset (MEASURED):

| subset | n | b (output) | a (text) | a (tool input) |
|---|---:|---:|---:|---:|
| thinking responses inside tool loops | 90,327 | 1.004 | -0.010 | -0.002 |
| thinking responses followed by a new human prompt | 1,047 | 0.984 | 0.059 | 0.036 |
| no-thinking responses | 44,891 | 1.014 | -0.014 | -0.006 |

Thinking is re-sent on every later request, including across human turns. Only 41 of 157,789 consecutive pairs
shrink at all (MEASURED).

**Attribution.** Each group of items arriving before response a occupies prompt positions [P(a-1), P(a)), and its
token total is the MEASURED delta.
- The split inside that total uses the fitted ratios.
- Thinking tokens:
  - When the output is final (151,131 groups), thinking = the recorded output minus the predicted visible text and
    tool-call tokens.
  - Otherwise (20,081 groups, mostly 2.1.280 agents), thinking = the residual of the delta.
- 49 context-shrink events (P drops by more than 1,000 tokens, e.g. server-side clearing of old tool results) start a
  new segment. The surviving prefix is charged to `context_rewrite_carryover`.

**Cost of an item** = its tokens x the exact per-token billing of its positions. For every later response k in the
same file (xdup=0 readers only), the item's positions are charged by where they fall in k's prompt:
- inside k's cache_read span: k's read price;
- inside k's cache_creation span: k's write price, at k's own 5m/1h mix;
- after both: the uncached input price.

So the first reader writes the item, later readers read it, and a cache miss re-writes it.

**Conservation check** (MEASURED): initial-prefix dollars + growth dollars = input-side dollars to 1.0000 for every
context type and at both price sets. The input-side totals equal `resp_priced`: $17,932 main, $1,666 subagent, $8,610
workflow.

## Totals

| context type | files | input-side $ | initial prefix $ | growth $ | growth share | growth $ @Opus 5.5 | growth tokens appended |
|---|---:|---:|---:|---:|---:|---:|---:|
| main | 1019 | 17,932 | 7,303 | 10,630 | 59.3% | 5,552 | 160.1M |
| subagent | 409 | 1,666 | 847 | 819 | 49.1% | 468 | 49.5M |
| workflow_agent | 2870 | 8,610 | 5,269 | 3,341 | 38.8% | 1,929 | 217.4M |
| **all** | 4298 | 28,208 | 13,419 | **14,789** | 52.4% | **7,949** | 427.1M |

Across all contexts, a growth token is carried by about **50 later responses on average**: 21,502M token-reads over
427M tokens appended (MEASURED readers x ESTIMATED split). By source it ranges from about 13
(`bash_output_audience_note`) to about 270 (Stop-hook feedback).

## Growth by source

The dollars are in list-price weights. The tokens appended are the ESTIMATED split of MEASURED deltas.

| source | tokens appended | token-reads | $ | share | write $ | read $ | $ @Opus 5.5 |
|---|---:|---:|---:|---:|---:|---:|---:|
| tool_result:Bash | 154.76M | 6,938M | 4,684 | 31.7% | 1,610 | 3,073 | 2,537 |
| tool_use_input:Bash (the model's commands, incl. heredoc scripts) | 59.90M | 4,042M | 2,657 | 18.0% | 760 | 1,896 | 1,373 |
| assistant_thinking (retained) | 76.01M | 3,606M | 2,548 | 17.2% | 937 | 1,610 | 1,387 |
| tool_result:Read (54% of results are images) | 32.75M | 972M | 752 | 5.1% | 343 | 409 | 416 |
| context_rewrite_carryover (after 49 shrink events) | 16.33M | 864M | 614 | 4.2% | 268 | 346 | 337 |
| assistant_text | 7.47M | 629M | 415 | 2.8% | 118 | 296 | 216 |
| attachment: hooks (additional_context + blocking_error) | 3.66M | 427M | 269 | 1.8% | 69 | 200 | 137 |
| attachment:total_tokens_reminder (165k items, ~35 tok each) | 5.72M | 407M | 263 | 1.8% | 73 | 190 | 138 |
| tool_result:WebFetch | 10.64M | 289M | 207 | 1.4% | 70 | 137 | 111 |
| attachment:queued_command | 3.07M | 320M | 200 | 1.4% | 49 | 151 | 100 |
| attachment:edited_text_file | 3.65M | 286M | 195 | 1.3% | 66 | 129 | 107 |
| meta_user:stop_hook_feedback | 1.12M | 302M | 167 | 1.1% | 18 | 150 | 74 |
| attachment:instructions (memory files re-attached mid-session, 85x) | 3.55M | 227M | 166 | 1.1% | 76 | 90 | 102 |
| tool_use_input:Write | 9.61M | 166M | 156 | 1.1% | 91 | 65 | 96 |
| meta_user:command_body (slash-command files) | 1.92M | 141M | 119 | 0.8% | 57 | 62 | 67 |
| tool_use_input:Edit | 2.51M | 167M | 119 | 0.8% | 46 | 73 | 65 |
| tool_result:WebSearch | 6.55M | 151M | 114 | 0.8% | 43 | 70 | 63 |
| attachment:skill_listing (re-sent after start) | 2.90M | 151M | 113 | 0.8% | 44 | 69 | 64 |
| tool_result: MCP (ms365 77, uidotsh 15) | 2.77M | 111M | 92 | 0.6% | 40 | 53 | 52 |
| tool_use_input:Agent (subagent briefs) | 0.99M | 128M | 88 | 0.6% | 31 | 58 | 46 |
| user_prompt:task_notification (all kinds) | 1.52M | 112M | 87 | 0.6% | 36 | 51 | 48 |
| tool_use_input:Workflow (workflow scripts/briefs) | 1.01M | 114M | 87 | 0.6% | 36 | 51 | 46 |
| attachment:mcp_instructions_delta (3.3M of it in workflow agents) | 4.26M | 125M | 86 | 0.6% | 31 | 55 | 48 |
| residual (no-thinking responses; modelling error) | 1.33M | 115M | 69 | 0.5% | 15 | 54 | 35 |
| meta_user:other | 1.21M | 94M | 66 | 0.4% | 24 | 42 | 37 |
| attachment:deferred_tools_delta | 1.01M | 95M | 62 | 0.4% | 16 | 46 | 31 |
| meta_user:skill_body (Skill loads) | 0.76M | 63M | 52 | 0.3% | 26 | 26 | 28 |
| tool_result:ToolSearch | 0.83M | 61M | 43 | 0.3% | 14 | 29 | 23 |
| everything else (prompts, Edit/Write results, Agent returns and acks, ...) | | | ~299 | 2.0% | | | |

- **User prompts are negligible** as persistence cost:
  - plain prompts: 948 of them, $7.7;
  - pasted prompts: 83, $13;
  - teammate messages: 63, $2.5;
  - command prompts: 264, $2.5;
  - peer messages: 90, $20;
  - bash_mode: 522, $8.7;
  - task notifications, all kinds: $87.
- **Uncached input is about $3 of the $14,789.** Growth is billed almost entirely as cache writes (35%) and cache
  reads (65%).

### Per context type (share of that context type's growth dollars)

- **Main ($10,630):**
  - Bash results 27.1%, Bash commands 20.4%, thinking 17.3%;
  - rewrite carryover 5.3%, assistant text 3.6%, Read 2.9%;
  - total_tokens_reminder 2.0%, queued_command 1.8%, edited_text_file 1.7%, Stop-hook feedback 1.6%;
  - re-attached instructions 1.6%, command bodies 1.1%, skill listing 1.1%;
  - UserPromptSubmit hooks 1.0%, Stop blocking errors 0.9%.
- **Subagent ($819):** Bash results 49.8%, thinking 14.9%, Bash commands 11.6%, Read 9.2%, WebFetch 2.3%,
  WebSearch 2.2%.
- **Workflow agent ($3,341):** Bash results 41.8%, thinking 17.5%, Bash commands 11.8%, Read 11.1%, WebFetch 5.3%,
  WebSearch 2.4%, `mcp_instructions_delta` 1.5%.

## What Bash carries

MEASURED character shares, `growth_bash_classes.py`. Command classes are a HEURISTIC on the first 120 characters of
the command.

**Results: 299M characters.**
- File reads (`sed -n`, `cat`, `head`, `tail`, `wc`): 32.3%. This is a lower bound: another 13.4% begin with a
  `cd <path> &&` prefix too long to see past.
- Search and listing (`grep`, `find`, `ls`): 12.3%.
- `echo`/`printf`: 6.0%.
- git: 4.2%.
- inline scripts: 2.8%.

In workflow agents, file reads are 36%. For comparison, the Read tool returned 54M characters.

**Commands (tool_use input): 108M characters.**
- Heredoc Python/Node scripts: 9.4%.
- Heredoc file writes (`cat > f <<EOF`): 9.5%.
- Other classes are hidden behind truncated `cd` prefixes (20%) and variable assignments (14%).

The `cd <path> &&` prefix itself is 2.8M characters over 53k commands, about $41 (small).

**Bash results by size** (MEASURED count and characters; $ is the ESTIMATED persistence cost):

| result size | results | chars | tokens | $ | $ @Opus 5.5 |
|---|---:|---:|---:|---:|---:|
| <1k | 97,379 | 31.4M | 16.1M | 746 | 388 |
| 1-5k | 52,932 | 127.6M | 57.8M | 1,782 | 968 |
| 5-20k | 18,116 | 159.2M | 68.3M | 1,848 | 1,010 |
| 20-50k | 1,215 | 29.4M | 12.6M | 308 | 171 |
| ≥50k | 1 | 0.1M | 0.0M | 0 | 0 |

The ~30k-character Bash output cap already truncates the tail. Results of 5k characters and up are 19.3k calls and
**$2,156 of persistence cost**. Roughly a third of those characters are deliberate file reads.

## Read tool: per-line number prefix

MEASURED over all 8,150 in-window Read results, `growth_raw.py`.

**What the prefixes cost:**
- 673,502 numbered lines. Each prefix is `N<TAB>` with no padding.
- 2.58M prefix characters, **4.8% of Read-result characters** (53.8M).

**What numbering only every 10th line would save:**
- It leaves 0.26M prefix characters, so it saves 2.32M characters (4.3%).
- That is **~1.0M tokens** at the fitted 0.44 tokens per character, or 0.6-1.2M at 1-2 tokens per dropped prefix.
- Priced at Read's persistence cost per token, it is **~$23 at own-model prices, $13 at Opus 5.5, over 15 days**.
  That is 0.07% of fleet spend (ESTIMATED).

**Other facts about Read:**
- 4,407 of the 8,150 Read results contain an image, and the median Read result has no text at all.
- 179 `<system-reminder>` blocks, 17k characters in total, ride inside Read results.

## Subagent and workflow returns

MEASURED sizes; token totals ESTIMATED with the fitted ratios. Per-return sizes are in characters.

| return kind | n | total chars | p50 | p90 | p99 | max |
|---|---:|---:|---:|---:|---:|---:|
| task_notification: workflow completed (the result JSON) | 107 | 985k | 9,748 | 12,769 | 36,824 | 38,173 |
| task_notification: background agent completed | 191 | 721k | 3,014 | 7,538 | 25,662 | 28,501 |
| Agent tool_result, inline (foreground) return | 331 | 394k | 291 | 2,865 | 2,908 | 2,913 |
| Agent tool_result, async-launch acknowledgement | 344 | 373k | 1,082 | 1,091 | 1,108 | 1,108 |
| Workflow tool_result, async-launch acknowledgement | 143 | 197k | 1,395 | 1,475 | 1,571 | 1,583 |
| task_notification: background shell | 1,555 | 797k | 425 | 742 | 784 | 1,233 |
| task_notification: peer mail / goal check-in / monitor | 235 | 396k | | | | 100,039 |

- **Returns in main-thread growth:** subagent and workflow returns, acknowledgements included, are $86.7, 1.23M
  tokens, **0.8% of main-thread growth dollars**. The briefs the parent writes (Agent, Workflow and SendMessage
  inputs) are $186, 1.75%.
- **Acknowledgements are a fixed per-launch cost:** each async Agent acknowledgement is 1.08k characters and each
  Workflow acknowledgement 1.4k. Together they are 570k characters, which is more than the inline returns.

## Skill bodies injected

MEASURED from `meta_user:skill_body` plus `growth_raw.py` names.
- 90 loads in the window. Size: median 14.1k characters, p90 55.3k, max 108k.
- The `Skill` tool_result itself is tiny: 237 results, 6.4k characters in total.

| skill | loads | mean chars | ~tokens | growth $ |
|---|---:|---:|---:|---:|
| research-subagents | 13 | 55,721 | 22.3k | 21.9 |
| agent-teams | 7 | 27,980 | 11.2k | 9.5 |
| outbound-drafting | 13 | 15,339 | 5.7k | 5.0 |
| pyramid-principle-full | 6 | 14,161 | 5.4k | 2.9 |
| claude-api | 3 | 106,394 | 41.0k | 2.7 |
| plan-conventions | 9 | 8,146 | 3.1k | 1.8 |

All skill bodies together are $52 of growth (0.35%). Their size matters per session: one research-subagents load
carries 22k tokens into every later turn. It does not matter at fleet scale.

## Hooks, by message

MEASURED from `hook_signatures.json`. The signature is the first 60 characters after the hook header.
- **session-continue.sh Stop block** ("🔧 Loose ends remain"): 1,511 x, 431k tokens, **$74**. The paired
  `stop_hook_feedback` meta messages add $167 more.
- **PostToolUse:Bash peer-mail relay:** 398 x, $29.
- **UserPromptSubmit "No inbox wake path armed":** 894 + 1,810 x, $40.
- **UserPromptSubmit "MEMORY INDEX BUDGET":** 428 x, $29.
- **"HANDOFF-INTENT PARITY":** $8. **"parked watcher holding your LIVE /goal":** $8.
- **"PROMPT CACHE EXPIRED":** 1,007 x, $7.
- **AGENT-TEAMS skill nudge (PreToolUse:Agent):** $5.5.
- **"PLAN DEFAULTS" (PreToolUse:Edit):** $4.8.
- **completion-assert:** $4.7.

All hook-originated context, including Stop feedback, is about **$436, 2.9% of growth dollars**.

## Biggest single items

MEASURED (`top_items.json`, `bash_classes.json`).

**By dollars:**
- The top 13 items are almost all **memory-file `instructions` attachments re-attached mid-session.** Each is
  56-92k tokens, carried by 39-236 later responses, costing $4-12.5 apiece. There are 85 such re-attachments over 73
  files, $166 in total.
- Then a 77-skill `skill_listing` re-sent at 11.6k tokens and read by 804 responses ($4.8).
- Then one `ps` Bash result of 11.9k tokens read 757 times ($4.6).

**By characters:** the largest is an **813k-character plain prompt** (~358k tokens). The next two responses were
API errors, so it was never billed as context. Next come memory attachments of 200-333k characters.

## Opportunities from growth

The savings are ESTIMATED, as a share of the 15-day window.

| # | change | est. saving (15 d) | quality risk | category |
|---|---|---|---|---|
| 1 | Offload large non-file-read Bash output to a file (path + size + head/tail) instead of inlining. Results of 5k+ characters are $2,156 of growth, and about 2/3 of that is not deliberate file reads. | $0.4-1.4k (1.3-4.4% of spend): the upper bound assumes no follow-up read, the lower bound that 2/3 of the content is re-read | medium | propose (Claude Code's Bash tool is in the vendor binary; the only lever is a wrapper/hook convention) |
| 2 | Trim the Stop-hook feedback and nudge text: session-continue.sh "Loose ends", the inbox-wake nudges, the memory-budget line. These are about $436 of growth and very persistent (240-270 reads per token). | $0.2-0.3k (0.6-0.9%) at a 50-70% text cut | low | flag |
| 3 | Find and remove the per-turn `total_tokens_reminder` attachment (165k items, $263) if it is optional. | up to $263 (0.8%) | low-medium | flag (trigger not identified: gap) |
| 4 | Stop re-attaching memory files mid-session, or shrink them. There are 85 re-attachments of 56-92k tokens each ($166 of growth). The memory-file size work covers this too. | $0.1-0.17k (0.3-0.5%) | low | flag |
| 5 | Keep MCP servers off workflow agents that do not use them: `mcp_instructions_delta` is $86, about 3.3M of its 4.3M tokens in workflow agents. | about $50-86 (0.2%) | low | flag |
| 6 | Sparse Read line numbers (every 10th line) | ~$23 ($13 at Opus 5.5), 0.07% | low | not worth it (the Read tool is 5% of growth) |
| 7 | Do not strip retained thinking ($2,548, 17% of growth): it is reasoning continuity, a named trap | 0 | high if touched | none |
| 8 | Subagent returns and acknowledgements (0.8% of main growth): no fleet-level action. Returns are already short. | <$50 | low | none |

## Gaps

- **Split vs total:** the by-source split inside each measured delta is ESTIMATED with fitted average ratios, and
  tokenization varies by content (code, JSON, prose, CJK). Totals per group are exact.
- **Agent thinking is a residual:** for 2.1.280 agents the final output is not recorded (EXTRACT L2), so their
  thinking is the delta's residual. Any mis-fit lands in "thinking" there. For no-thinking responses the residual
  totals 1.3M tokens (0.5%), which bounds that error.
- **Carryover is a mix:** `context_rewrite_carryover` ($614) is the surviving prefix after 49 context-shrink events.
  Its composition is unknown, but it is presumably proportional to earlier content.
- **Images:** priced at a MEASURED median of 1,022 tokens per block. Actual size varies with resolution.
- **Bash classes:** the classes are heuristic, and 13-20% of commands hide their verb behind a `cd` prefix longer
  than the 120-character `detail`.
- **Hook signatures:** they come from the 300-character snippet, which does not always name the hook script.
- **Unidentified triggers:** what triggers `total_tokens_reminder`, and why memory files are re-attached mid-session
  (resume, `/clear` or compaction), was not established.
- **Out of scope:**
  - Side queries such as prompt suggestion and away summaries are invisible in transcripts (EXTRACT L6).
  - The system prompt and tool schemas are part of the initial prefix, not of growth.
- **Read-prefix token cost:** estimated from the character ratio, not tokenized.

## Re-derive

Run from `/tmp` with `nice -n 10 python3 <dir>/scripts/...`, in this order:

```
growth_pairs.py        # pairs.npz + sample.tsv (~3 s)
growth_fit.py          # fit.json: ratios + thinking test
growth_raw.py          # raw_labels.tsv, raw_read.json (streams only needed lines, ~16 s)
growth_cost.py         # cost_by_source.json, cost_by_size.json, per_file.tsv, top_items.json, hook_signatures.json, skill_bodies.json (~15 s)
growth_bash_classes.py # bash_classes.json
growth_report.py > measure/growth_work/tables.md   # growth.json + tables
```

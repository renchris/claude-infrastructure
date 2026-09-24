# Binary, side requests, cache layout — what transcripts cannot show (CC 2.1.280)

Source: read-only extraction from `~/.claude-280/node_modules/@anthropic-ai/claude-code/bin/claude.exe`
(`scripts/binctx.py <pattern>` prints ±N bytes around a string; the function names below are minified
and only meaningful inside this build). Experiments: 7 headless runs (budget 8), `scripts/exp_run.sh`.
Prices are list prices used as quota weights (the fleet is subscription-billed): Opus 5.5 $4 in /
$20 out / $0.20 cache read / 1.25x write at 5m / 2x write at 1h; Haiku 4.5 $1/$5, read $0.10.

**Exclude these 7 experiment sessions from any census** (they live in `~/.claude-secondary/projects/-private-tmp-tokeff-*`):
ba4f2f52, 01175ecd, 39b591d4, c955125b, fe39becc, f8bf934e, 37f47d43.

## Headline

1. **Workflow agents almost never share their big prefix with their siblings.** Over 5,293 workflow-agent
   first requests (MEASURED, `scripts/wf_first_request_cache.py`, all retained transcripts in the 5 config dirs,
   realpath-deduped, `<synthetic>` excluded): only **13.2 %** of first-request prefix tokens were cache reads; 24.7 %
   read nothing at all; agents that did read got a mean **18.9k** tokens (median 21.2k), which is just tools + system
   prompt. 495.4M tokens were written at 5m TTL on first requests alone (≈ **$2,490** re-priced at Opus 5.5).
   Agent-tool subagents: 628 agents, 9.0 % read, $241.
   Cause (binary): the harness puts exactly **one** message breakpoint, on the last message (`Hxt`), plus one on the
   system block. Memory files, the skill listing and the agent listing are attachments in the FIRST USER MESSAGE,
   ahead of the per-agent brief and with no breakpoint after them, so a sibling can only hit the system breakpoint.
2. **omitClaudeMd works and is large**: the same one-word subagent cost **1,795** prefix tokens with
   `omitClaudeMd: true` against **42,275** without it (MEASURED, experiment b). A Workflow `agent()` can use it
   through `opts.agentType` pointing at a custom agent that sets it; the default `workflow-subagent` does not.
3. **Prompt suggestion is ON because the operator's env forces it** (`CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=true`
   bypasses the server gate `tengu_chomp_inflection`, which defaults to false). It re-reads the whole main context
   once per interactive main-thread turn: ≈ **$0.032 per turn at 150k context** (ESTIMATED).

## 1. Side requests

`Vw` = runForkedAgent: same model, same system prompt, same tools, parent messages + one new user message. With
`skipCacheWrite:true` the message breakpoint moves back one message (`Hxt`: `if(r)he=j(he-1)`), so the fork
**reads** the parent's cached prefix, writes only the parent's last assistant message (which the parent's next turn
reuses), and pays the fork's own prompt as uncached input. `jR` = side query on the small fast model (`Wh()` →
Haiku 4.5 unless `ANTHROPIC_SMALL_FAST_MODEL`), new prompt, caching off by default.

| Side request | When it fires | Model | Prefix | Max out | Off switch | ≈ $ per firing, 150k ctx |
|---|---|---|---|---|---|---|
| Prompt suggestion (`prompt_suggestion`) | end of every **interactive main-thread** turn (`repl_main_thread*`), terminal not blurred, ≥2 assistant msgs, not plan mode, last response cache-warm (its uncached in+out+cache_creation ≤ 10k, `Vt`) | main | fork, cache READ of whole context | "2-12 words" | `CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false` or `promptSuggestionEnabled:false`; env `true` forces it on, overriding the server gate and non-interactive checks, and keeps it running at quota status `allowed_warning` | read 150k×$0.20/M = $0.030 + ~350-token prompt uncached $0.0014 + out $0.0003 ≈ **$0.032** |
| Away summary / recap (`away_summary`) | TUI only: terminal blurred for min(server delay, default 180 s, floor 30 s; 0.8×cache TTL) after a turn ends; needs ≥3 real user msgs and ≥2 since the last recap, no pending bg agents/workflows, no draft, cache younger than 0.9×TTL, quota `allowed`. Also `/recap` on demand | main | fork, cache READ | "<40 words", capped at 400 chars | `CLAUDE_CODE_ENABLE_AWAY_SUMMARY=false` or `awaySummaryEnabled:false` (/config). Env `true` also enables it for non-interactive sessions, though the blur timer lives only in the TUI | ≈ **$0.032**, at most once per absence |
| Session title (`generate_session_title`, `ai-title` records) | early in a session from ≤1,000 chars of user/assistant text (min 10) | Haiku 4.5 (`jR`) | new prompt, not cached | JSON title | the title setting ("Set to false to keep auto-generated topic titles"), `CLAUDE_CODE_DISABLE_TERMINAL_TITLE` | ~1k in + ~20 out ≈ **$0.001** |
| /goal evaluator | every Stop while a goal is armed (a session Stop hook `{type:"prompt"}` with no model) | **Haiku 4.5** (`e.model ?? Wh()`) | NEW prompt: its own evaluator system prompt + the transcript, truncated to 0.5 × evaluator window (≈100k tokens for Haiku; `Dpr`, `_At=0.5`); caching on, 5m TTL | JSON {ok,reason} | clear the goal | under 100k: mostly read, ≈ $0.01 + delta. **Over 100k the kept window slides each Stop, so the prefix changes and is rewritten**: 100k×1.25×$1/M ≈ **$0.125 per Stop** (×4 if re-priced at Opus 5.5 = $0.50) |
| Prompt-type hooks (`hook_prompt`) | per configured event | `hook.model ?? Haiku` | same as goal (new prompt + transcript for Stop/SubagentStop) | JSON | remove hook | same as goal |
| Agent-type hooks (`hook_agent`) | per configured event | `hook.model ?? Haiku` | new query: own system prompt + all tools, reads the transcript FILE by path, ≤50 turns | structured output | remove hook | depends on turns, fresh context each time |
| Compaction (`compact`, `reactive-compact`) | manual `/compact` or auto at threshold (fleet: 39/39 manual) | main (fallback allowed) | fork, cache READ (`tengu_compact_cache_prefix` default true), maxTurns 1 | summary | `DISABLE_AUTO_COMPACT`, `DISABLE_COMPACT` | read $0.03 + summary output (2-8k × $20/M = $0.04-0.16) + new-prefix write |
| Side question `/btw` (`side_question`) | on demand | main | fork, cache READ, no tools | answer | don't use | ≈ $0.03 + output |
| Agent progress summary (`agent_summary`) | every **30 s** per running async agent whose transcript changed, only when enabled: SDK `agentProgressSummaries`, coordinator mode, or an agent-view gate (`ZY()`) | agent's model | fork of the AGENT's context, cache READ | 3-5 words | not enabled by default in a plain TUI (the gate was not resolved) | agent ctx×$0.20/M per 30 s (100k ctx: $0.02 each, $0.40 per 10 min) |
| Extract memories (`extract_memories`) | end of main turns when `SHe()` (server gate) is on | main | fork, cache READ, ≤5 turns | memory writes | server-gated | unknown frequency |
| Auto-mode classifier (`auto_mode`) | per tool call that needs classification while auto mode is on (this operator uses auto mode) | server-configured, else Sonnet 5 (external default), else main (`eRe`) | NEW prompt: classifier system prompt (includes the user's auto_mode allow/deny rules) + transcript of user prompts and tool calls + the action; breakpoints on the last transcript block and on the action; **1h TTL** (`auto_mode` is on the 1h allowlist) | stage 1: 64 tokens; stage 2 (only if stage 1 blocks): 8,192 with thinking | leave auto mode | append-only transcript, so mostly reads; not in transcripts, unmeasured |
| Tool-use summary label (`tool_use_summary_generation`) | mobile/remote UI labels | Haiku | new prompt, caching explicitly off | ~30 chars | n/a | < $0.001 |
| Narration (`narration`) | `CLAUDE_CODE_ENABLE_NARRATION`, focused terminal | main | new prompt, no cache | 2,560 | env off | n/a |

Transcripts record **none** of these usages: forks run with `skipTranscript:true`; `jR`/hook/classifier calls
have no transcript. The only trace is `ai-title` records (the title text, no usage).

## 2. Request assembly and caching

Wire order: **tools → system → messages** (the Messages API order). What the build does:

- **System prompt** (`TSe`) is split at the literal `__SYSTEM_PROMPT_DYNAMIC_BOUNDARY__` marker into:
  an attribution-header block (no cache) · a CLI-prefix block · the **static** part → `cache_control{scope:"global"}`
  (shareable across orgs/sessions) · the **dynamic** part → `scope:"org"`. MEASURED layout from a
  `prompt_snapshot` attachment (`scripts/exp_snapshot_layout.py`): static 1,584 chars; the dynamic part includes the
  `# Memory` auto-memory instructions (with the config dir and project slug in a path), `# Environment` (cwd, model),
  `<total_tokens>`, and then the `--append-system-prompt` text, last.
- **Messages**: one breakpoint on the last cacheable message (`Hxt`/`Epr`); an optional second "fork pin"
  breakpoint is behind server gate `tengu_basalt_spur`. No breakpoint between the setup attachments and the conversation.
- **Memory files, skill listing, agent listing, MCP instructions, deferred-tool names, hook additionalContext,
  date, session_context** are all **attachments in user-role messages** (the first user message at session start),
  not in the system prompt. Only the auto-memory *instructions* block is in the system prompt.
- **TTL** (`URt` → `Fxt`), first match wins:
  1. `FORCE_PROMPT_CACHING_5M` → 5m.
  2. env `CLAUDE_CODE_PROMPT_CACHE_TTL` (main sources) / `CLAUDE_CODE_SUBAGENT_PROMPT_CACHE_TTL` (everything else).
  3. settings `promptCacheTtl` / `subagentPromptCacheTtl`.
  4. agent frontmatter `experimental: { cacheTtl: "5m"|"1h" }` (a 1h value is ignored while on overage).
  5. `ENABLE_PROMPT_CACHING_1H` → **1h for every query source**, subagents and workflow agents included.
  6. otherwise: not a subscriber, or using overage → 5m; subscriber → 1h if the query source is on the server
     allowlist `tengu_prompt_cache_1h_config`, default `["repl_main_thread*","sdk","auto_mode","memdir_relevance"]`, else 5m.
  That is why the lead's main session wrote 1h and a workflow agent (`agent:*` source) wrote 5m. MEASURED: the
  headless runs (`sdk`) wrote 1h; both Agent-tool subagents wrote 5m.
- **`--append-system-prompt(-file)` lands in the org-scoped dynamic system block**, after cwd-dependent content.
  Experiment (a), MEASURED:

| run | flags / dir | cache_read | cache_creation (TTL) |
|---|---|---|---|
| x1 | `/tmp/tokeff-x1` | 10,459 | 7,210 (1h) |
| x2 | `/tmp/tokeff-x2` | 10,459 | 7,210 (1h) |
| y1 | `--append-system-prompt-file ~/.claude/CLAUDE.md`, `/tmp/tokeff-y1` | 10,468 | 47,676 (1h) |
| y2 | same, `/tmp/tokeff-y2` | 10,468 | 45,767 (1h) |
| y1b | same, repeated in `/tmp/tokeff-y1` | **58,144** | **0** |

  All runs: `claude -p --output-format json --model claude-opus-5-5 --setting-sources project,local "Reply OK"`,
  `CLAUDE_CONFIG_DIR=~/.claude-secondary` (inherited). `--setting-sources project,local` also dropped the **user**
  memory files (x-runs had no CLAUDE.md), so the x-rows are a no-memory baseline. **Result:** across *different*
  cwds only the ~10.46k global block (tools + static system) is reused; the appended CLAUDE.md is re-written. In the
  *same* cwd (same config dir, same day) the whole 58k prefix, first user message included, was read from cache.
  So the appended block is cacheable across sessions only when everything before it matches, i.e. same cwd.
- **Non-deterministic prefix across sessions:** y1 vs y2 differed by 1,909 tokens because the claude.ai MCP
  connectors connected after the first request in y2 (14 vs 26 deferred tool names, `mcp_instructions_delta`
  missing). The same race showed in b_lean, where the delta arrived mid-session and was written on the 2nd request.

## 3. omitClaudeMd

- Read from custom-agent frontmatter (`omitClaudeMd: true|"true"`), from plugin agents, from JSON `--agents`, and
  from `$.agent.register`. Built-in `Explore` and `Plan` already set it (and also `omitGitStatus`).
  "No effect on the main session agent."
- Effect (`$l` + `vd`): `claudeMd` is deleted from userContext. Built-in/policy agents get nothing back; custom
  agents get only **Managed** policy memory (`managedInstructionsOnly`), filtered by `type==="Managed"`. That removes
  every User/Project/Local memory file: `~/.claude/CLAUDE.md`, `~/.claude/rules/*.md`, project CLAUDE.md,
  `.claude/rules/*.md`, and **AutoMem** (MEMORY.md is a memory-file type in the same list). It does **not** remove
  the skill listing, the agent listing, MCP instructions, deferred-tool names, gitStatus, the date, or hook context.
  Those are separate attachments; a restricted `tools:` list is what removed the listings in the experiment.
- Workflow: `agent(prompt, {agentType})` "uses a custom subagent type … resolved from the same registry as the
  Agent tool; composes with schema". The default `workflow-subagent` (source built-in) has no omitClaudeMd.
- Experiment (b), MEASURED (`scripts/exp_subagent_usage.py`; dir `/tmp/tokeff-agent` holds a copy of the
  global CLAUDE.md as **project** memory, because user memory is not loaded under `--setting-sources project,local`):

| agent | subagent 1st request: read / create (TTL) | prefix | attachments |
|---|---|---|---|
| lean (`omitClaudeMd: true`, `tools: Read`) | 0 / 1,793 (5m) | **1,795** | environment, model, session_context, date |
| fat (same, without omitClaudeMd) | 1,357 / 40,916 (5m) | **42,275** | + instructions [CLAUDE.md 104,973 chars] |

## Opportunities (estimates, for the ranked list)

- **omitClaudeMd on workflow and research agents** (flag): a custom agent type with `omitClaudeMd: true`, passed as
  `agentType` in workflow scripts, with the needed rules moved into the brief. It removes the ~48k user-level memory
  (plus ~26k project memory in claude-infrastructure) from every such agent: the first write saves 48k×1.25×$4/M = $0.24,
  and every later turn saves 48k×$0.20/M ≈ $0.01. Over the corpus's 5,293 workflow agents that is
  ≈ $1.3k on first writes alone (ESTIMATED; turn count per agent not measured here). Risk: the agents lose operator rules.
- **Put the shared setup behind a breakpoint** (propose; needs the binary or a flag): siblings would read the
  ~70-90k memory/listing prefix instead of re-writing it. Workaround inside today's build: move CLAUDE.md into the
  system block. Main sessions: `claudeMdExcludes` + `--append-system-prompt-file`. Subagents:
  `CLAUDE_CODE_ENABLE_APPEND_SUBAGENT_PROMPT=1` + `--append-subagent-system-prompt-file` (flag found in the binary,
  untested). The system block carries a breakpoint, and same-cwd siblings match byte-for-byte (y1b). Upper bound
  ≈ 70k×(5.00−0.20)/M ≈ $0.34 per sibling, about $1.7k over the corpus, before losses to concurrent-launch races.
- **Prompt suggestion off** (direct, env): ≈ $0.032 per interactive main-thread turn at 150k context. Removes a
  feature that is off by default server-side.
- **Goal evaluator on long sessions:** past ≈100k tokens each Stop rewrites ≈100k Haiku tokens (≈$0.125).
- **1h vs 5m:** ENABLE_PROMPT_CACHING_1H would make every workflow agent write at 2x instead of 1.25x. Do not set it
  fleet-wide; `subagentPromptCacheTtl` / `experimental.cacheTtl` exist for targeted use.

## Gaps

- The first experiment command, a compound that scrubbed the parent-session env vars and deleted `/tmp` dirs, was
  refused by the permission check. Reran without the env scrub, so the children inherited `CLAUDECODE=1` and the
  session vars; outputs looked normal.
- No side-request usage is recorded anywhere this pass could read (suggestion, away summary, goal, classifier,
  titles), so the frequencies behind the per-firing $ are unmeasured. Main-thread turn counts from the shared extract
  would turn them into totals.
- The agent_summary gate `ZY()`/`$2n()` and the extract-memories gate `SHe()` were not resolved, and the goal
  evaluator's cache behaviour is inferred from code, not measured.
- The corpus time window of `wf_first_request_cache.py` is "all retained transcripts", not bounded by date.

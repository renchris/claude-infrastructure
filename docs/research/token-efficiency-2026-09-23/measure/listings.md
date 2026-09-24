# Listings: skills, custom agents, MCP servers, deferred tools

Window 2026-09-09 to 2026-09-23 (the extract build of record, `xdup=0` everywhere). Dollar figures are
**list-price weights**: the fleet is billed by subscription quota, not dollars. Each figure is given at
each response's own model, then re-priced at Opus 5.5. Machine-readable companion: `listings.json`,
which also holds the proposed descriptions. Raw inputs are in `listings_raw/`, and every script is in `../scripts/listings_*`.

## Headline

**The skill listing sits at its budget ceiling in every context. It is the largest listing cost, and
nearly half of that cost is paid by agents that almost never use a skill.**

- **At the ceiling everywhere.** The listing budget is 30,000 chars: 1% of a 1M window × 3 bytes/token.
  All 3,882 initial listings measured were at the ceiling (median 30,080 chars, p90 30,097 chars; MEASURED,
  `listings_skill_render.py`).
- **Name-only skills.** Listing every skill with its description would take 49,335 chars
  (ESTIMATED, `listings_simulate.py`). The binary therefore lists about 30 of our own skills by name
  only.
- **Cost.** The listing costs **$866 at each response's own model and $451 at Opus 5.5 over 14 days**,
  which is 2.7% of total spend (ESTIMATED, `listings_cost.py`, at 3 chars/token).
- **Agents pay half.** $426 of the $866 is paid in 3,155 subagent and workflow-agent contexts. Those contexts made
  **8 Skill calls** in 14 days (MEASURED).
- **Unused skills and unused triggers.** 36 of our 67 skills and commands had zero invocations. Only 9 of the
  169 quoted trigger phrases in the descriptions ever appeared in a typed prompt (MEASURED,
  `listings_triggers.py`).
- **The proposed descriptions.** The 20 proposed ≤250-char descriptions make the whole set fit
  (29,121 chars), so all 75 skills get their descriptions. Rewriting every own description to ≤250 chars cuts
  the listing to about 20.6k chars. That saves about 3.1k tokens per context, **up to $267 own-model and
  $139 Opus 5.5 per 14 days** (ESTIMATED).

## 1. How the listing is built (Claude Code 2.1.280 binary, byte-searched)

Sources: `claude.exe` functions `nUe` (budget), `JBt` (render), `yCn` (attachment), `LYe` (priority),
`qke` (overrides) and `xf` (bytes/token), at byte offsets ~178.77M, ~180.34M and ~180.44M. They were read with
`python3` byte search (`/tmp/binsearch_skill*.py`, reproduced in `listings.json.binary_listing_logic`).

- **Budget.** `SLASH_COMMAND_TOOL_CHAR_BUDGET` if set. Otherwise
  `floor(contextWindow × bytesPerToken × skillListingBudgetFraction)`.
  - `skillListingBudgetFraction` defaults to 0.01 (a settings key).
  - `bytesPerToken` (`xf`) is **3** for Opus 5.x, Fable and Sonnet 5, and **4** for the pre-5 model list.
  - `contextWindow` defaults to 200k when unknown.
  - The result is **30,000 chars** at 1M on Opus 5.x/Fable, 6,000 at 200k, and 8,000 at 200k on a pre-5
    model.
  - The measured subagent minimum was 8,079 chars, which matches the 8,000 case.
- **Entry format.** `- name: <description>[ - <when_to_use>]`. The description is cut at
  `skillListingMaxDescChars` (default **1536**) with an ellipsis. `skillOverrides[name]="name-only"`
  renders the entry as `- name`.
- **Over budget ("priority" mode).**
  1. Bundled prompt skills and name-only overrides keep their entries.
  2. Every other skill starts as `- name`.
  3. In descending usage-score order, each skill gets its full text if the increment still fits
     (greedy, so a long description is skipped while a shorter one after it can still fit).
  - The score is `usageCount × max(0.5^(days/7), 0.1)`, from `<configdir>/.claude.json skillUsage`.
    It is per account, so each account lists a different set.
  - The binary also logs a warning: "Skill listing over budget … Run /skills to disable some, or raise
    skillListingBudgetFraction".
- **No listing at all** when a context's tool set does not include the `Skill` tool (`yCn` returns `[]`).
  This is the lever for agents.
- **Settings that act on the listing:** `skillListingBudgetFraction`, `skillListingMaxDescChars`,
  `skillOverrides` (`on|name-only|user-invocable-only|off`, which also applies to bundled prompt skills) and
  `disableBundledSkills`. None of them is set in any of the 5 config dirs (MEASURED).
- **The budget only rations descriptions.** The listing fills to the budget, so shortening descriptions
  saves tokens only once the whole set fits under it. Before that point, the freed room goes to
  skills that are currently listed by name only.

## 2. What the model actually sees

**Headless `/context` from `/tmp`** (MEASURED: `listings_raw/context_tmp.txt`, free count_tokens):

| category | tokens |
|---|---|
| Skills | 10k |
| Custom agents | 1.4k |
| MCP tools (loaded) | 629 |
| MCP tools (deferred) | 367.7k (names only are sent) |
| System tools (deferred) | 14.1k |

With `SLASH_COMMAND_TOOL_CHAR_BUDGET=1` (`context_tmp_budget1.txt`), Skills drops to **2.4k tokens**. That
remainder is the bundled skills, which always keep their text: dataviz ~480, claude-api ~360, code-review
~280, update-config ~240 and others. The per-skill figures `/context` prints are Claude Code's own
chars/3 estimates. Memory files measure 2.6 chars/token, so token figures here use 3.0 with 2.6 as a
bound.

**Rendered listings** (MEASURED, `listings_skill_render.py`, 3,882 initial listings):

| ctx_type | listings | median chars | described | name-only |
|---|---|---|---|---|
| main | 872 | 30,080 | 47 | 31 |
| subagent | 346 | 30,083 | 46 | 33 |
| workflow_agent | 2,664 | 30,088 | 47 | 36 |

**Why skills show no description.**

- **Budget, for all of our own skills.** Every one has a description source. Six commands have no
  frontmatter (deploy-check, fix-lint, pr, review, scaffold, ship), and Claude Code derives a description from
  their body (for example ship's 76-char one).
- **Never described in any listing:** cafe-wifi-optimization (2,107 chars), frontier-routing (1,628),
  permission-harvest (1,528), recover (1,148), repo-wiki (1,056), grok-wiki-audit (911), visual-direction
  (647), outlook-cleanup (480), desk (453), evolve-skill (334) and review. Each is long, has a usage score
  of 0, or both, so the greedy fill never reaches it.
- **Always name-only for another reason:** `anthropic-skills:*` (8 skills synced from claude.ai) and the built-ins
  `init` and `security-review`. The reason is unknown (see gaps).
- **Strict YAML rejects 8 frontmatters, but Claude Code reads them.** The files are cc-upgrade-gate,
  frontier-run, limit-recover, recover, and 4 agents. Each has an unquoted `: ` inside a value. Their
  descriptions still appear in live listings, so this is not a cause of missing descriptions.
- **The simulator reproduces the binary.** It is fed the latest real claude-infrastructure listing
  (30,103 chars, 85 entries) and the ~/.claude-secondary usage scores. It predicts all 44 skills that were
  actually described, plus 4 short ones that the binary did not describe. The binary measures
  `Bun.stringWidth`, not `len`.

## 3. Invocation frequency (MEASURED, `listings_usage.py`, 1,052 main sessions)

- **Skill tool.** 237 calls: 229 in main threads, 3 in subagents, 5 in workflow agents, 0 errors.
  183 main sessions (17.4%) made at least one Skill call.
- **Slash commands.** 467 command prompts. Of these, 73 are unnamed local-command output, and effort, model,
  goal, context and clear are built-ins.

| skill / command | Skill calls | /slash | main sessions | share |
|---|---|---|---|---|
| ship | 108 | 0 | 108 | 10.3% |
| limit-recover | 11 | 110 | 77 | 7.3% |
| are-we-done | 0 | 70 | 57 | 5.4% |
| accounts | 0 | 69 | 51 | 4.9% |
| handoff | 21 | 1 | 21 | 2.0% |
| qa-commits (reso) | 0 | 14 | 14 | 1.3% |
| outbound-drafting | 13 | 0 | 13 | 1.2% |
| research-subagents | 12 | 0 | 12 | 1.1% |
| workflow-authoring (bundled) | 12 | 0 | 12 | 1.1% |
| plan-conventions | 9 | 0 | 9 | 0.9% |
| pyramid-principle | 7 | 1 | 8 | 0.8% |
| keep-laptop-alive | 0 | 13 | 8 | 0.8% |
| agent-teams | 7 | 0 | 7 | 0.7% |
| pyramid-principle-full | 6 | 0 | 6 | 0.6% |
| read-twitter | 2 | 3 | 5 | 0.5% |
| all others | ≤4 each | | ≤4 | ≤0.4% |

**Zero invocations in 14 days: 36 of 67 own skills and commands.** Their listing text totals 22,248 chars when
capped at 1,536 each. The group includes:

- the longest descriptions: cafe-wifi-optimization, frontier-routing, permission-harvest, demo-recording,
  browsermcp, codex-security, coding-standards, self-explaining-artifact, repo-wiki,
  autonomous-authenticated-web-access and grok-wiki-audit;
- the bundled skills dataviz, keybindings-help, fewer-permission-prompts, loop, schedule, run,
  claude-in-chrome and simplify.

**Triggers.** Across all descriptions, 169 phrases are quoted as triggers. Only **9** appeared in any of
the 2,659 typed main-session prompts, and **1** of those came from a session that invoked the skill. Where
invocations happen, the name is what gets typed: limit-recover's name appears in 74 of its 77 invoking sessions.
The proposals therefore keep the name and the behaviour, and drop the quoted trigger lists.

## 4. Custom agents (MEASURED; `/context` tokens are Claude Code estimates)

| agent | desc chars | /context tokens | main listing median chars | Agent spawns | workflow files | in repo |
|---|---|---|---|---|---|---|
| deep-research | 1,358 | 533 | 1,564 | 374 | 143 | yes |
| deep-research-sonnet | 878 | 380 | 992 | 0 | 0 | yes |
| frontier-derivation | 527 | 209 | 603 | 0 (5 experiment variants) | 0 | yes |
| research-decomposition-critic | 339 | 155 | 398 | 4 | 0 | yes |
| motion-reviewer | 212 | 75 | 250 | 0 | 0 | **no** (only in ~/.claude/agents) |

- **The agent listing.** It is the `agent_listing_delta` attachment, main sessions only, with a median of
  6,577 chars. Besides ours it lists built-ins (claude-code-guide 1,091 chars, Explore 539, Plan 364,
  general-purpose 309) and, in 116 contexts, plugin agents (code-reviewer, type-design-analyzer and others).
  It costs **$113 own / $57 Opus 5.5 per 14 days**.
- **Spawns by type.** general-purpose accounts for 197 Agent spawns and 213 workflow files, and
  `workflow-subagent` for 2,313 workflow files.
- **Agent types in the binary.** The built-in `workflow-subagent` is hard-coded as `tools:["*"]`, so it
  always receives the skill listing and every MCP block.

## 5. MCP servers and deferred tools (MEASURED unless marked)

Motion, motion-plus and ms365 are user-scoped in all 5 `.claude.json` files. The claude.ai connectors
(Claude Docs, uidotsh, Gmail, Google Drive, Google Calendar) come from the account.

| server | deferred names | name chars | instruction chars | full schemas (tokens) | calls 14d | main sessions | error rate |
|---|---|---|---|---|---|---|---|
| ms365 | 188 | 6,361 | 1,757 | 363,449 | 748 | 32 (3.0%) | 5.5% |
| claude.ai Claude Docs | 8, 3 of them **always loaded (629 tokens)** | 275 | 1,895 | 1,982 | **0** | 0 | — |
| claude.ai uidotsh | 1 | 38 | — | 266 | 31 | 5 | 6.5% |
| motion | 1 | 32 | 257 | 641 | 9 | 4 | 22% |
| motion-plus | 4 | 152 | 262 | 1,668 | 7 | 4 | 0% |
| mac-messages (project) | 11 | — | 795 | — | 2 | 1 | 0% |
| Gmail / Drive / Calendar | 2 each (auth tools) | — | — | — | 0 | 0 | — |

- **The instruction and name blocks.** The `mcp_instructions_delta` median is 2,335 chars in main
  threads and 2,416 in agents. It is sent to subagents whose `tools:` list excludes every MCP tool
  (deep-research): 354 of 354 subagent contexts carry the ms365 instructions, but their deferred-name list
  holds a median of 2 names. The `deferred_tools_delta` median is 7,113 chars (211 names) in main threads.
- **Claude Docs appeared recently.** It was in no context before 2026-09-16, and in 46-91% of new contexts
  per day since then (`listings_docs_presence.py`).
- **ToolSearch.** 1,519 calls, 0 errors. Main threads made 658 calls in 436 of 1,052 sessions (41%),
  subagents 132, workflow agents 729. What they loaded:

  | target | loads |
  |---|---|
  | WebSearch | 748 |
  | WebFetch | 581 |
  | ms365 | 410 |
  | Monitor | 265 |
  | SendMessage | 140 |
  | TaskStop | 115 |
  | keyword queries | 44 |

  There were 1,011 responses whose only tool call was ToolSearch. Together they cost $230 own / $150 Opus 5.5.
  The WebSearch/WebFetch loads alone are 412 such turns, $99 / $69, and 383 of them were in research agents
  whose own `tools:` list names WebSearch and WebFetch (`listings_toolsearch.sql`).
- **The deferral switch.** Built-in deferral is set server-side (GrowthBook `tengu_non_deferrable_builtins`,
  `kc().non_deferrable_builtins`). `ENABLE_TOOL_SEARCH` only switches deferral on or off wholesale. A
  per-server `alwaysLoad` exists, but no user setting un-defers a single built-in.

## 6. Cost of the listings (ESTIMATED, `listings_cost.py`; list-price weights, 14 days)

**Method.** A token in the prefix is paid on every later response of its context. When the response
reads the cache (`cache_read ≥ 20k`), it is paid at the cache-read rate. Otherwise it is paid at the
response's 5m/1h write mix. Tokens = chars/3; the 2.6 chars/token bound is in the json.

| block | own model | Opus 5.5 | share of $32.5k |
|---|---|---|---|
| skill_listing | $866 (main $440 · workflow $334 · subagent $92) | $451 | 2.7% |
| deferred_tools_delta | $178 | $92 | 0.5% |
| agent_listing_delta | $113 | $57 | 0.3% |
| mcp_instructions_delta | $73 | $36 | 0.2% |
| **all listings** | **$1,231** | **$636** | **3.8%** |
| ToolSearch-only round trips | $230 | $150 | 0.7% |

**Static-token value.** One token added to every context's initial listing position costs **$85.1 per 1k
tokens per 14 days** at each response's own model, and $44.4 at Opus 5.5. By context type: main $42.8,
workflow $33.2, subagent $9.2.

**Skill listing by agent type (own model):**

| agent type | cost | Skill calls in 14 days |
|---|---|---|
| workflow-subagent | $285 | 6 |
| deep-research (subagent and workflow) | $102 | 3 |
| general-purpose | $38 | 0 |

## 7. Proposed descriptions and what they buy

Each proposal is at most 250 chars and says what the skill does plus when to load it. The full text is in `listings.json` →
`proposed_skill_descriptions` and `proposed_agent_descriptions`, and in `scripts/listings_simulate.py`
as `PROPOSED`.

| skill | listed chars now | proposed | saved |
|---|---|---|---|
| cafe-wifi-optimization | 1,536 (capped; 2,107 raw) | 218 | 1,318 |
| limit-recover (command) | 1,536 (1,838 raw) | 247 | 1,289 |
| frontier-routing | 1,536 (1,628 raw) | 227 | 1,309 |
| permission-harvest | 1,528 | 215 | 1,313 |
| dia-agent | 1,462 | 223 | 1,239 |
| manual-command-delivery | 1,412 | 226 | 1,186 |
| plan-conventions | 1,407 | 233 | 1,174 |
| demo-recording | 1,398 | 227 | 1,171 |
| research-subagents | 1,256 | 244 | 1,012 |
| browsermcp | 1,247 | 180 | 1,067 |
| agent-teams | 1,175 | 242 | 933 |
| recover (command) | 1,148 | 242 | 906 |
| codex-security | 1,125 | 206 | 919 |
| coding-standards | 1,093 | 221 | 872 |
| self-explaining-artifact | 1,060 | 229 | 831 |
| repo-wiki | 1,056 | 214 | 842 |
| autonomous-authenticated-web-access | 985 | 228 | 757 |
| resume-sessions (the skill wins over the same-named command) | 981 | 228 | 753 |
| grok-wiki-audit | 911 | 227 | 684 |
| model-upgrade | 874 | 235 | 639 |
| **20 skills** | **24,726** | **4,512** | **20,214** |

| agent | now | proposed | saved |
|---|---|---|---|
| deep-research | 1,358 | 197 | 1,161 |
| deep-research-sonnet | 878 | 171 | 707 |
| frontier-derivation | 527 | 192 | 335 |
| **3 agents** | | | **2,203 chars (~734 tokens per main context, ~$31 own / $15 Opus 5.5 per 14 days)** |

**Simulation** (`listings_scenarios.py`, on the latest real claude-infrastructure listing, ESTIMATED).
Savings assume every context's skill set fits. Contexts with extra project or plugin skills stay at the
ceiling, which makes these figures upper bounds.

| scenario | entry chars | mode | described | tokens saved per context | $ per 14 days, own / Opus 5.5 |
|---|---|---|---|---|---|
| S0 today | 29,996 (real: 30,103) | priority | 48 (real 44) | — | — |
| S1: the 20 proposals | 29,121 | **fits**, 879 chars of headroom | **75** | 292 | $25 / $13 |
| S2: S1 + every other own description ≤250 | 20,606 | fits | 75 | 3,130 | **$267 / $139** |
| S3: S2 + name-only for the 8 unused bundled skills | 16,994 | fits | 67 | 4,334 | $369 / $192 |
| S4: S1 + `skillListingBudgetFraction: 0.005` | 14,996 | priority | 36 | 5,000 | $426 / $222 |
| S5: S2 + fraction 0.005 | 14,976 | priority | 48 | 5,007 | $426 / $222 |

**Do the budget-dropped skills fit after the change? Yes.**

- **After S1**, every skill fits and the 31 own skills listed by name only in the real listing (27 in the simulation) (for example
  cafe-wifi-optimization, frontier-routing, permission-harvest, recover, repo-wiki, desk, wrap and
  review) get their descriptions.
- **The S1 headroom is thin.** It is only 879 chars, so one new long skill tips the listing back into
  priority mode.
- **S2 leaves 9.4k chars of headroom.**

## 8. Opportunities, ranked by saving × removable ÷ risk

1. **[flag] Rewrite every own skill and command description to ≤250 chars.** 20 are drafted here and 38
   remain. Estimated saving: up to $267 own / $139 Opus 5.5 per 14 days (S2).
   - Quality: likely better, because all 75 skills become visible to the model instead of 44.
   - Validate: re-run `listings_skill_render.py` and `listings_usage.py`. The model-initiated Skill-call
     rate per main session (17.4% today) must not drop.
   - Roll back: `git revert` of the frontmatter edits.
2. **[flag] Remove `Skill` from the `tools:` of deep-research and deep-research-sonnet.** The binary then
   sends no listing to those contexts: **$102 / $55 per 14 days**.
   - Cost: 3 Skill calls (all agent-browser) in 14 days. The agent-browser CLI stays reachable through Bash.
3. **[propose] A lean custom agent type for Workflow slots.** Explicit `tools:` without Skill and without
   MCP, used by workflow scripts instead of the built-in `workflow-subagent` (`tools:["*"]`).
   - Estimated saving: $285 / $158 on the skill listing, plus up to $95 / $51 on MCP blocks.
   - Risk: 6 Skill calls, and whatever MCP use workflow agents make (41 ms365 ToolSearch loads came from agents).
4. **[flag] `skillOverrides: name-only` for the 8 bundled skills with 0 uses:** dataviz, keybindings-help,
   fewer-permission-prompts, loop, schedule, run, claude-in-chrome and simplify.
   - Saving: about 1.2k tokens per context beyond S2, $103 / $53. They stay invocable by name.
5. **[propose] Scope ms365 out of the user MCP config.** It is used in 3.0% of main sessions, but its
   ~2.7k tokens per context (6,361 name chars plus 1,757 instruction chars) cost about $200 / $100 per 14 days.
   - Conflict: the global rule on reading email images, so this is a decision for the operator.
6. **[propose] Disable the claude.ai Claude Docs connector.** It had 0 calls, yet costs ~1.35k tokens per
   context: 629 always-loaded tool tokens, 1,895 instruction chars and 8 names. Since 2026-09-16 it is in
   50-90% of new contexts, about $69 / $36 per 14 days from now on.
   - How: an account-level toggle, or `ENABLE_CLAUDEAI_MCP_SERVERS=false`. The env var also drops uidotsh,
     which had 31 calls.
7. **[flag] The 3 agent descriptions:** $31 / $15.
8. **[propose, upstream] Stop deferring WebSearch/WebFetch for agents that name them in `tools:`.** 412 extra
   turns cost $99 / $69. No user-side switch was found.

## Gaps

- **No tokenizer.** Tokens = chars/3, which is Claude Code's own estimate for Opus 5.x and matches
  `/context` (30.1k chars ≈ 10k tokens). Memory files measure 2.6 chars/token, so costs could be up to 15%
  higher (both are in the json).
- **Why some entries are always name-only is unresolved.** This covers `anthropic-skills:*` and the
  built-ins init and security-review.
- **The tool-describe path is unverified.** A tool-describe resolver seam (`resolveToolDescription` /
  `recordDeferral`) can override deferral, but no user-facing configuration for it was confirmed.
- **Savings upper bounds.** The "fits" savings assume every context's skill set fits. Contexts with
  extra project or plugin skills stay capped, so realized savings are lower. Presence is measured
  (29% of listings carry reso-only skills); its effect was not modelled per project.
- **Per-account priority.** Usage scores differ by account. The simulation uses ~/.claude-secondary only.
- **Unmeasured effect of dropping trigger phrases.** Model-initiated Skill calls cannot be attributed to
  the listing text itself.

## Reproduce

```
cd /tmp; S=<dir>/scripts; R=<dir>/measure/listings_raw; X=<dir>/data/extract.sqlite
claude -p "/context" > $R/context_tmp.txt; SLASH_COMMAND_TOOL_CHAR_BUDGET=1 claude -p "/context" > $R/context_tmp_budget1.txt
python3 $S/listings_frontmatter.py > $R/frontmatter.json
nice -n 10 python3 $S/listings_skill_render.py $X $R/skill_render.json
python3 $S/listings_usage.py $X $R/usage.json
nice -n 10 python3 $S/listings_mcp_blocks.py $X $R/mcp_blocks.json
nice -n 10 python3 $S/listings_triggers.py $X $R/frontmatter.json $R/triggers.json
nice -n 10 python3 $S/listings_cost.py $X $R/cost.json
python3 $S/listings_latest_entries.py $X claude-infrastructure $R/latest_listing_entries.json
python3 $S/listings_simulate.py $R ~/.claude-secondary/.claude.json $R/simulate.json
python3 $S/listings_scenarios.py $R ~/.claude-secondary/.claude.json $R/cost.json $R/scenarios.json
sqlite3 $X < $S/listings_toolsearch.sql; python3 $S/listings_docs_presence.py $X
python3 $S/listings_assemble.py <dir>/measure
```

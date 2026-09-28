# CC 2.1.280 → 2.1.284: background subagents / Dynamic Workflows / model and cost defaults / Explore / daemons

Source: `/tmp/s55/cl.md` lines 3-471 (2.1.284 at L3, 2.1.283 at L106, 2.1.282 at L203, 2.1.281 at L292). All four
sections were read in full. "L<n>" means a line of that file. The rows below are the entries that touch this
axis or a standing hazard. Entries not listed (VSCode, Claude Tag, cloud, gateway, vim, TUI list polish,
plugins, Windows) are NEUTRAL for this fleet.

Evidence labels:
- **grep**: repo grep, run 2026-09-28.
- **strings**: `strings` over `~/.claude-280/.../bin/claude.exe`.
- **settings**: `python3 json.load` of `~/.claude{,-next}/settings.json`.

## Standing hazards (checked explicitly)

| hazard | finding in 281-284 | rating |
|---|---|---|
| Spawn/concurrency cap or depth limit restored or removed | No entry mentions depth, spawn limit or concurrency. A grep for `depth\|concurren\|spawn` over L3-471 finds nothing (grep). Our `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1` export at `~/.zshrc:484` and `CLAUDE_CODE_WORKFLOW_MAX_CONCURRENT_AGENTS=12` (settings env, migration `migrations/0035-workflow-concurrency.sh:40`) are untouched. It still needs checking that they REACH 284: run `lib/cc-upgrade-gate/check06_depth.sh` and `check15_depth_effect.sh`. | NEUTRAL |
| Symlink-following cleanup/GC | The only symlink entries are **284 L38** (rules symlinked into a *project* `.claude/rules` from outside, or a symlinked project `.claude` dir, now ask for external-import approval) and **282 L221** (`/Network`, `/.vol`). Neither is GC. No project under `~/Development/*/` has a symlinked `.claude` or symlinked rules (find, 2026-09-28). `~/.claude` is the *user* dir, not a project `.claude`. **281 L385** deletes Bash edit-diff snapshot dirs in temp, not under `~/.claude`. | NEUTRAL |
| Write-without-read | Only **281 L334** (Write accepts duplicated identical params) and **281 L333** (NUL in path fails the call, not the turn). The read-before-write rule is unchanged. | NEUTRAL |
| Permission-mode defaults | **284 L66** / **283 L170**: auto mode is the default when no mode is configured. We set `permissions.defaultMode: auto` (settings) and pass `--permission-mode "$_perm"` (`~/.zshrc:498,502`), so nothing changes. | NEUTRAL |
| Hook I/O schema (Stop, additionalContext, systemMessage) | No schema change. **284 L41** adds a failed-hook stderr and status code to the debug log. **284 L42** is Elicitation `decision:block` only. **281 L345**: `mcp_tool` hooks now wait for their server; we have 0 `mcp_tool` hooks and 106 of type `command` (settings). | NEUTRAL (L41 IMPROVEMENT for diagnosis) |
| /effort persistence | See the Ultracode row (284 L67) and the keybinding actions (284 L8). **281 L372** fixes a stale effort level on burst input. Nothing changes whether `effortLevel` persists; ours is `high` (settings). | NEUTRAL |
| Model defaults (default Sonnet → 5.5) | **284 L5**. See the table below. | CAUTION |
| Account switching / preserved thinking | **282 L211-L214** and **281 L305, L309**: fixes for resumed or continued sessions dropping earlier reasoning. **282 L219-L220**: the login-refresh lock no longer stalls up to 60 s after a peer process dies. | IMPROVEMENT |
| Cross-session SendMessage / ListAgents | Only **284 L43**: sessions launched *without* SendMessage are no longer told to use it. Our sessions have the tool. | NEUTRAL |
| Workflow tool | **284 L56** hardens the sandbox against errors from async script hooks. **283 L125** fixes the fallback-model leak. **281 L386, L417, L419, L439** and **283 L177** are /workflows UI only. There is no `agent()` opts, schema, effort or model change in 281-284. | IMPROVEMENT |

## Axis table

| version | change | rating | why (our file:line) |
|---|---|---|---|
| 2.1.284 L5 | Sonnet 5.5 (`claude-sonnet-5-5`) is the **default Sonnet** on the Anthropic API, at $2/$10 with $0.20 cache reads | CAUTION | The `sonnet` alias moves to 5.5, and two agents pin it: `agents/deep-research-sonnet.md:4` and `agents/research-decomposition-critic.md:4`. Both would silently run an unbenched model. `deep-research-sonnet.md:13` also calls itself "Sonnet 5 tier". Explicit pins such as `skills/research-subagents/SKILL.md:426` (`model:'claude-sonnet-5'`) stay on Sonnet 5. The SSOT has no row for the new model: `model-config.yaml:127` `sonnet_latest: claude-sonnet-5`, and pricing at `:772` has no `claude-sonnet-5-5`. The comment at `:785` ("sonnet alias still resolves to 4.6") is stale. The price is the same as Sonnet 5, and the fleet has zero dollar exposure (`model-config.yaml:762-770`), so this is a behaviour risk, not a cost risk. A teammate spawned with the full id `claude-sonnet-5-5` would be DENIED by `hooks/agent-teams-enforce.sh:535-559` until the id is added to the SSOT allowlist (`model-config.yaml:799-802`). The alias still passes that check. |
| 2.1.284 L67 | Ultracode becomes its own `/effort` toggle, no longer forces xhigh, and stays on at any effort | NEUTRAL | On 2.1.280 the `ultracode` *effort level* meant "xhigh + dynamic workflow orchestration" (strings: `- ultracode: xhigh + dynamic workflow orchestration`). The *keyword* was a separate per-turn trigger: "including the keyword in a prompt opts that turn into the Workflow tool" (strings). We use only the keyword (`commands/handoff.md:200,409`), and `handoff.md:409` already says it changes orchestration, not effort. No script, `~/.zshrc` or settings sets ultracode as an effort level (grep). Unverified: whether 284's keyword path still behaves this way. A one-turn probe would settle it. |
| 2.1.284 L47 | Explore no longer switches to Opus when the session model id is unrecognized; it inherits that model | NEUTRAL | We run the recognized `claude-opus-5-5` (`~/.zshrc:498,502`). Retrieval pins `model:"haiku"` (`skills/research-subagents/SKILL.md:611-613,680`). The measured unpinned-Explore-inherits-lead behaviour on 280 is unchanged. |
| 2.1.284 L56 | Workflow tool sandbox hardening for errors thrown by async script hooks | IMPROVEMENT | Affects every Dynamic Workflow run. No opt or schema change. |
| 2.1.284 L68 | Retries after a mid-response dropped connection now share one budget with the request's other retries, so a failing request gives up sooner | CAUTION | Long workflow and background agents on flaky links may now fail where they used to grind through. Workflow scripts should keep treating a null `agent()` result as retryable. |
| 2.1.284 L14-L16 | Damaged streams are retried. An overload right after a thinking block is retried. Compaction runs a second time if the request is still too long. | IMPROVEMENT | Directly helps long background and workflow agents on Opus 5.5 with thinking. |
| 2.1.284 L70 | Safety-flag model switches in sessions that pin Opus via `ANTHROPIC_DEFAULT_OPUS_MODEL`/`modelOverrides` are now picked by the API | NEUTRAL | We set neither variable (grep: no hits). `switchModelsOnFlag` is set in settings, and its behaviour for an unpinned session is not changed by this entry. |
| 2.1.284 L71 | The non-interactive first turn waits up to 2 s for MCP servers named in `--allowedTools` or by an `mcp_tool` hook | NEUTRAL | We have 0 `mcp_tool` hooks, and no `--allowedTools mcp__…` in scripts/bin/hooks/lib (grep). |
| 2.1.284 L43 | Sessions launched without SendMessage are no longer told to use it | NEUTRAL | — |
| 2.1.284 L48 | `/loop` self-paced updates are written as visible text | IMPROVEMENT | Minor, for loop-style monitors. |
| 2.1.284 L62 | Auto-memory neutralizes invisible characters and markup-imitating tags in MEMORY.md and recalled notes | NEUTRAL (off-axis) | Only matters if a memory note embeds harness-like tags. Not audited here. |
| 2.1.284 L8 | `toggleUltracode` / effort keybinding actions | NEUTRAL | — |
| 2.1.283 L125 | Dynamic workflows started during a model fallback no longer run every agent on the fallback model | IMPROVEMENT | This was a silent model downgrade of whole waves. `agent()` calls pin models such as `workflow_synthesis_worker: claude-opus-5-5` (`model-config.yaml:901`), and during a fallback window those pins were being overridden. |
| 2.1.283 L112, L163 | `/doctor prompt-audit` audits CLAUDE.md, skills, agents and commands for prompting patterns written for older models | IMPROVEMENT | This is the tool the Sonnet 5.5 utilization goal needs. Run it over `agents/`, `skills/` and `CLAUDE.global.md` after the bump. |
| 2.1.283 L109-L110 | `availableModelsMatch`, `deniedModels` managed settings | NEUTRAL | Managed settings are not in use. The only `availableModels` mention is prose at `skills/agent-teams/SKILL.md:238`. |
| 2.1.283 L126, L124 | `DISABLE_PROMPT_CACHING_HAIKU` fix; Haiku price in /model | NEUTRAL | Neither is used (grep). |
| 2.1.283 L118 | MCP progress is kept when a long tool call moves to the background | IMPROVEMENT (minor) | — |
| 2.1.283 L174 | `--system-prompt` and its `-file` form accepted together | NEUTRAL | `commands/evolve-skill.md:24,35` uses `--append-system-prompt` only. |
| 2.1.282 L211-L214 | Resumed or continued sessions keep extended thinking. A bad `redacted_thinking` block triggers a drop-and-retry. | IMPROVEMENT | Our long-lived leads are resumed through `cc()` / `_cc_resume_pin` (`~/.zshrc:470-474, 510-530`). |
| 2.1.282 L215 | A refused compaction summary is retried on a fallback model | IMPROVEMENT | — |
| 2.1.282 L216 | Fixes the "xhigh isn't available with thinking off" failure after a safety switch | NEUTRAL | We do not run thinking-off sessions at xhigh. |
| 2.1.282 L219-L220 | The login refresh lock no longer blocks for up to 60 s after the refreshing process dies. Policy fetch is retried. | IMPROVEMENT | Four-account fleet with many processes per config dir. |
| 2.1.282 L262 | Server-side auto-mode classifier is the default on direct API **when telemetry is off** | NEUTRAL | Telemetry is on: no `DISABLE_TELEMETRY`/`DO_NOT_TRACK` in `~/.zshrc` (grep). |
| 2.1.282 L264 | Project/local settings ignore OTEL export variables | NEUTRAL | No `OTEL_*` in config (grep). |
| 2.1.282 L266-L268 (reverted in part by 283 L182) | `anthropic-skills` / `claude-ai` namespace reservation | NEUTRAL | We have no skills in those namespaces. |
| 2.1.282 L269 | Plain ultracode visuals; dynamic-workflows spinner tip removed | NEUTRAL | — |
| 2.1.281 L304 | A turn no longer retries indefinitely past `--max-turns` | IMPROVEMENT | `scripts/handoff-fire.sh:10483` probes with `--max-turns 1`. |
| 2.1.281 L321 | `-p`/SDK sessions no longer fail after their start directory is deleted mid-session | IMPROVEMENT | Headless children run inside worktrees that worktree-gc (`launchd/com.claude.worktree-gc-infra.plist`) can remove. |
| 2.1.281 L332 | `--setting-sources` is forwarded to spawned sessions (teammates, `/bg`, `claude agents`) | NEUTRAL | We use it only in leaf headless children that spawn nothing: `hooks/model-permission-decider.py:422`, `bin/cc-memory-extract:318`. |
| 2.1.281 L327, L430 | `rm -rf "$(…)"` now prompts even with an allow rule. In auto mode the dangerous-rm prompt waits 2 min, then denies with a rewrite hint. | CAUTION | Unattended workflow and background agents that emit such a Bash command stall for 2 min, then get a deny. That is safe, but it is lost time. `CLAUDE_CODE_DISABLE_DANGEROUS_RM_TIMEOUT` is not set (grep). |
| 2.1.281 L428-L429 | Where the classifier is server-side, read-only and sandboxed shell commands also wait for it | NEUTRAL | We run the local classifier path: telemetry is on and `CLAUDE_CODE_AUTO_MODE_SERVER` is unset (grep). |
| 2.1.281 L331 | `claude --bg` asks for workspace trust first, or exits when not interactive | NEUTRAL | `scripts/handoff-fire.sh:3939` only *detects* `--bg-pty-host` and does not launch `--bg`. |
| 2.1.281 L339 | Scheduled tasks and `/loop` wakeups are no longer re-fired every second on failed delivery | IMPROVEMENT | Removes a possible exit-at-turn-end for loop monitors. |
| 2.1.281 L427 | Send-now moves running tools to the background instead of cancelling | NEUTRAL | Interactive only. |
| 2.1.281 L298 | `"attribution": false` form | NEUTRAL | We keep the object form `{commit:"",pr:"",sessionUrl:false}` (settings), which the changelog recommends for mixed-version files. |
| 2.1.281 L405 | `--agents` accepts a JSON file path | NEUTRAL | Unused. |

## Bump mechanics (not changelog-driven, found while grepping)

- `bin/cc-memory-extract:55` hard-codes `DEFAULT_CLAUDE = "/Users/chrisren/.claude-280/node_modules/.bin/claude"`. It must move with `~/.zshrc:496` `_bin`, or memory extraction stays on 280.
- `model-config.yaml:47` records the 280 activation. The SSOT needs `claude-sonnet-5-5` in three places: `models`, pricing (`:772` neighbourhood), and the teammate allowlist (`:799-802`). This only matters once anything pins the full id.
- The installed candidate reports `2.1.284 (Claude Code)` (measured: `~/.claude-284/node_modules/.bin/claude --version`). It was published hours ago, so run the gate's `check06_depth`, `check08_workflow`, `check09_subagent` and `check15_depth_effect` against it before flipping `_bin`.

# CC 2.1.280 -> 2.1.284 — axis: hooks / permission modes / auto-mode classifier / launchers / settings keys / MCP / resume / account+auth

Source: `/tmp/s55/cl.md` lines 3-471 (2.1.284 L3-104, 2.1.283 L106-201, 2.1.282 L203-290, 2.1.281 L292-470). I read every entry.
The `L<n>` numbers below are changelog line numbers. Our live settings file is `~/.claude/settings.json`, a real file
that is mirrored to `-next/-secondary/-tertiary/-quaternary`. The launcher is `~/.zshrc:451-503`.

## Verdict for this axis
**ADVANCE-to-2.1.284.** I found no BLOCKER. No hook input/output schema change touches our events: Stop,
SessionStart, UserPromptSubmit, PreToolUse, PermissionRequest and WorktreeCreate have no field changes, and
additionalContext and systemMessage are untouched. I read the spawn-depth knob in both binaries and it is
byte-for-byte the same logic. Our settings and launcher already pin every changed default. The CAUTIONs below
are things to verify, not reasons to hold.

## Standing-hazard checklist

| hazard | finding | evidence |
|---|---|---|
| Spawn/concurrency cap or depth limit restored or removed | **None in 281-284.** Both binaries contain the same resolver: `let n=a.CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH;if(n!==void 0)return n;...GrowthBook...; var o=3` (default 3). `CLAUDE_CODE_WORKFLOW_MAX_CONCURRENT_AGENTS` is still read as "workflow: concurrent agent gate". | Measured: python mmap scan of `~/.claude-{280,284}/node_modules/.bin/claude`. `~/.zshrc:484` export (=1) and `~/.claude/settings.json:12` (=12) still apply. |
| Symlink-following cleanup/GC | No new GC of config dirs. Only 281 L385: Bash edit-diff snapshot dirs in temp are deleted on abandonment or exit. That is temp-only. | NEUTRAL |
| Symlinked `.claude` / `.claude/rules` from outside the project (284 L38 now prompts) | No project `.claude` or `.claude/rules` entry is a symlink. Repo `.claude/rules/*.md` are real files. `~/.claude` is user scope, not project. | Measured: `find ~/Development -maxdepth 4 -path '*/.claude*' -type l` returned only `.claude-plans`/`.claude-tasks` links. A per-project `-L` check found nothing. |
| Write-without-read | 281 L333 (null-byte path now fails the call, not the turn) and L334 (duplicate identical params accepted). Neither loosens read-before-write. | NEUTRAL/IMPROVEMENT |
| Permission-mode defaults (284 L66, 283 L170 → auto when unset) | We always set the mode. The launcher passes `--permission-mode "$_perm"` (default auto), and every config dir has `defaultMode: auto`. | `~/.zshrc:494,498,502`; `~/.claude/settings.json:415` (same in -next/-tertiary/-quaternary, measured with python json read) |
| Hook schema changes (Stop / additionalContext / systemMessage) | **None.** The hook items are: 284 L41 (debug log), L42 (Elicitation `decision:block`, and we have no Elicitation hooks), 281 L345 and 284 L71 (`mcp_tool` hooks, and we have none), 282 L232 (cosmetic SessionStart flash). | Measured: all our hooks are `type: command` (python walk of settings.json hooks) |
| /effort persistence | No persistence change. 284 L67 makes Ultracode its own toggle that no longer forces xhigh. The launcher always passes `--effort "$_eff"`, and settings has `effortLevel: high`. | `~/.zshrc:495`; see the CAUTION row for 284 L67 |
| Model defaults (default Sonnet → 5.5) | 284 L5. This reaches us through the `model: sonnet` alias. | CAUTION row below |
| Account switching / preserved thinking | Fixes only (282 L211-214, L219-220; 281 L305-309, L342, L344). | IMPROVEMENT rows below |
| Cross-session SendMessage / ListAgents | 284 L43 only: sessions without SendMessage are no longer told to use it. | NEUTRAL (the decider child disallows SendMessage, `hooks/model-permission-decider.py:426-427`) |
| Workflow tool | 284 L56 (sandbox hardening for async script-hook errors), 283 L125 (workflows started during fallback now retry the configured model), 282 L269 and 281 L386/L417/L439 (UI). No cap change. | IMPROVEMENT/NEUTRAL |

## Change table

| version | change (changelog line) | rating | why / where it touches us |
|---|---|---|---|
| 2.1.284 | Sonnet 5.5 is now the default Sonnet on the Anthropic API (L5) | CAUTION | The `model: sonnet` alias now resolves to claude-sonnet-5-5 at `agents/research-decomposition-critic.md:4` and `agents/deep-research-sonnet.md:4` (the frontier-campaign skill text, `skills/frontier-campaign/SKILL.md:29`, also uses the alias). The price is the same as sonnet-5 ($2/$10). `model-config.yaml:127` still says `sonnet_latest: claude-sonnet-5`, and `model-config.yaml:785-808` records that auto mode once refused a new Sonnet id. Auto-mode acceptance of claude-sonnet-5-5 under `--permission-mode auto` needs a live check. |
| 2.1.284 | Interactive/VS Code sessions start in auto when no mode is configured (L66) | NEUTRAL | The mode is always configured (`~/.zshrc:498,502`; `settings.json:415`). `claude -p` is unaffected. |
| 2.1.284 | Ultracode is its own `/effort` toggle, no longer forces xhigh, and stays on at any effort (L67) | CAUTION | `commands/handoff.md:200,409` relies on the `ultracode` payload keyword and already says the keyword "changes ORCHESTRATION, not effort", so 284 matches our doc. Verify on 284 that the keyword still arms Dynamic Workflows (nothing in the changelog says it doesn't). |
| 2.1.284 | Auto mode gets a "Yes, but ask again next time" answer for reads outside the working dirs (L6) | IMPROVEMENT | Our PermissionRequest hooks only notify and beacon (`settings.json:609`: notify.sh, cc-permission-beacon.sh). They make no answer, so there is no conflict. |
| 2.1.284 | Failed hooks log stderr and status code in the debug log (L41) | IMPROVEMENT | ~70 command hooks across 21 events. Easier diagnosis. |
| 2.1.284 | Elicitation/ElicitationResult `{"decision":"block"}` honored (L42) | NEUTRAL | We have no Elicitation hooks. |
| 2.1.284 | MCP tool calls in a resumed session wait up to 10s for a connecting server (L19); `/mcp reconnect all` (L10) | IMPROVEMENT | We resume heavily (`_cc_resume_pin`, `~/.zshrc:469-474`; `cc`). |
| 2.1.284 | Non-interactive first turn waits up to 2s for MCP servers named in `--allowedTools` or an `mcp_tool` hook (L71) | NEUTRAL | A grep found no `--allowedTools mcp__…` in scripts/bin/hooks, and there are no `mcp_tool` hooks. |
| 2.1.284 | Safety-related model switches with pinned `ANTHROPIC_DEFAULT_OPUS_MODEL`/`modelOverrides` go to an API-picked model (L70) | NEUTRAL | This applies to the Anthropic API only. We pin that variable only in `bin/claude-kimi:91,308`, which is a third-party provider. Settings has `switchModelsOnFlag: false`. |
| 2.1.284 | Tags in MEMORY.md that imitate Claude Code markup are neutralized (L62) | NEUTRAL | A grep of `~/.claude/projects/*/memory/*.md` found no `<system-reminder>`/`<command-*>`/`<task-notification>`-style tags. Peer mail reaches sessions through hook additionalContext, not memory. |
| 2.1.284 | Sessions without SendMessage are no longer told to use it (L43) | NEUTRAL | The decider child disallows SendMessage (`hooks/model-permission-decider.py:426-427`). |
| 2.1.284 | `/recap` declines when it arrives relayed from a chat, routine or webhook (L72) | NEUTRAL | A grep found no `/recap` relay in scripts/bin/hooks. |
| 2.1.284 | Retry after a dropped connection now shares one retry budget (L68); stream-damage and thinking-block retries fixed (L14-L16) | IMPROVEMENT / NEUTRAL | Failing requests give up sooner. That is fine for unattended fleets, and `StopFailure` (`stop-failure-marker.sh`) already catches terminal failures. |
| 2.1.284 | Explore subagent inherits an unrecognized session model instead of switching to Opus (L47) | NEUTRAL | Our model ids are recognized. |
| 2.1.284 | Rules symlinked into `.claude/rules`, or a `.claude` dir symlinked from outside the project, now prompt (L38) | NEUTRAL | No such symlinks exist (see checklist). Re-check if a worktree setup ever starts symlinking `.claude`. `hooks/worktree-setup.sh` does not do this today. |
| 2.1.284 | Workflow tool sandbox hardening (L56); settings-schema startup change (L57) | NEUTRAL | — |
| 2.1.283 | Auto mode default extended to third-party providers and telemetry-off sessions (L170) | NEUTRAL | Same as 284 L66. We pin the mode. `bin/claude-kimi` passes through the launcher. |
| 2.1.283 | Dynamic workflows started during a model fallback retry the configured model (L125) | IMPROVEMENT | Our Workflow runs pin per-slot models (`model-config.yaml:901`). |
| 2.1.283 | stdio MCP servers are no longer left running when the session ends mid-start (L119); a stateless 404 no longer bricks a server (L120); MCP images saved to file (L156); `/context` counts MCP instructions (L137) | IMPROVEMENT | Fewer leaked processes across the 4-account fleet. `deniedMcpServers`/`enabledMcpjsonServers` are unchanged. |
| 2.1.283 | `--system-prompt`/`--append-system-prompt` accept text and `-file` together (L174) | NEUTRAL | `~/.zshrc:183` (`claude-plan --append-system-prompt "ultrathink"`) is unaffected. |
| 2.1.283 | `Skill(anthropic-skills:…)`/`Skill(skill:…)` deny matching widened (L175); `claude-ai` reservation reverted (L182) | NEUTRAL | We have no Skill rules with those namespaces (checked with a python scan of allow/deny/ask). |
| 2.1.283 | `deniedModels` / `availableModelsMatch` managed settings (L109-110) | NEUTRAL | These are managed-only, and we have no managed settings. |
| 2.1.283 | Auto-memory edits no longer blocked as sensitive when started in a repo subdir (L148) | IMPROVEMENT | Sessions start in worktree subpaths. |
| 2.1.283 | `/doctor prompt-audit` (L112, L163) | IMPROVEMENT | Directly useful to the Sonnet 5.5 prompt-migration work (CLAUDE.global.md, agents/, skills/). |
| 2.1.282 | Bash rules with a mid-pattern `:*` are now honored in settings files (L222) | NEUTRAL | The python regex `:\*[^)]` over 344 allow + 41 deny + 3 ask rules found 0 mid-pattern rules, so no rule silently changes meaning. |
| 2.1.282 | Server-side auto-mode classifier is the default on the direct API when telemetry is off (L262) | NEUTRAL | Telemetry is on. There is no `DISABLE_TELEMETRY`/`DO_NOT_TRACK`/`CLAUDE_CODE_AUTO_MODE_SERVER` in env, `~/.zshrc` or settings (grep). |
| 2.1.282 | Project/local settings ignore OTEL export variables (L264); telemetry-ignored notice (L206) | NEUTRAL | No project settings set OTEL variables (grep of `~/Development/*/.claude/settings*.json`). |
| 2.1.282 | Resume and continue no longer re-send changed history or drop thinking; thinking kept across immediate slash commands and `--tools` relaunch; redacted_thinking recovery (L211-214) | IMPROVEMENT | This is the "preserved thinking" hazard, fixed in our favour. It matters for cc/`--resume` and cross-account resume (`~/.zshrc:469-474`). |
| 2.1.282 | Login-refresh lock no longer sticks for ~1 min after another process dies; org-policy fetch retried (L219-220) | IMPROVEMENT | Many concurrent processes per config dir across 4 accounts (`_cc_sync_account`). |
| 2.1.282 | xhigh-with-thinking-off failure after a safety model switch fixed (L216) | NEUTRAL | `switchModelsOnFlag: false`. |
| 2.1.282 | Managed `permissions`/`autoMode` blocks survive one invalid nested value (L225); allowed-tools pre-approval closed under `allowManagedPermissionRulesOnly` (L226) | NEUTRAL | Our `autoMode.soft_deny` is user scope, not managed. |
| 2.1.282 | `anthropic-skills`/`claude-ai` namespaced skills and MCP servers stop loading (L266-268; `claude-ai` reverted at 283 L182) | NEUTRAL | We have no skills or MCP servers with those names. |
| 2.1.281 | "Send now" (ctrl+enter) moves running tools to the background instead of cancelling (L427) | CAUTION | This is operator-behavior only. A send-now during a foreground Bash now leaves a **non-terminal background Bash**, and Claude Code skips `/goal` evaluation at every Stop while one exists (`hooks/validate-bash.sh:342`, `hooks/lib/goal-state.sh:10`). That silently disables a live /goal. validate-bash cannot see this path because no new Bash call is made. |
| 2.1.281 | Where the classifier runs server-side, read-only and sandboxed commands also wait for its review (L428); `CLAUDE_CODE_AUTO_MODE_SERVER` now applies on the direct API (L429) | NEUTRAL (estimated) | Estimated from the L262 wording: server-side is the default only with telemetry off, and ours is on, so the latency hit probably does not apply. If it did, read-only Bash would wait on a round-trip. |
| 2.1.281 | `rm -rf "$(…)"` now prompts in auto/skip mode even with an allow rule (L327); broader dangerous-rm detection (L403); the dangerous-rm prompt times out to deny after 2 min (L430) | IMPROVEMENT | `hooks/rm-safe-allowlist.sh` already refuses substitution targets. The 2-minute deny keeps unattended sessions moving rather than hanging. `scripts/cloud-bundle-probe.sh:279` runs as a script, not as a Bash tool command, so it is unaffected. |
| 2.1.281 | `--setting-sources` forwarded to spawned teammates, `/bg`, `claude agents` (L332) | NEUTRAL | Only `hooks/model-permission-decider.py:422-423` uses `--setting-sources ''`, and its child disallows Agent/SendMessage/Workflow. `scripts/lib/mcp-noinherit.sh` avoids `--setting-sources` on purpose. |
| 2.1.281 | `claude --bg` asks for workspace trust before running project hooks (L331) | NEUTRAL | — |
| 2.1.281 | `/batch` works with a WorktreeCreate hook outside git (L406) | IMPROVEMENT | We have a WorktreeCreate hook (`settings.json:554` → `hooks/worktree-setup.sh`). |
| 2.1.281 | `"attribution": false` added; **older CLIs skip the whole settings file that contains it** (L298) | NEUTRAL (trap if adopted) | We use the object form (`{commit:'',pr:'',sessionUrl:false}`) in all config dirs. Keep it. 280 and 284 will share the mirrored settings during the A/B, and the boolean form would make 280 drop our entire settings.json, hooks included. |
| 2.1.281 | Resume fixes: history re-sent in changed form, huge sessions partially restored, pending-permission cache break, tool call mid-resume (L305-309) | IMPROVEMENT | Same resume surface as 282 L211. |
| 2.1.281 | macOS keychain-locked credential writes no longer drop MCP OAuth tokens (L342); login from another process clears the stale footer (L344) | IMPROVEMENT | Machine sleeps and wakes, and there are 4 accounts. |
| 2.1.281 | `mcp_tool` hooks on blocking events wait for their server (L345); `MCP_CONNECTION_NONBLOCKING=0` honors the timeout (L347); duplicate-URL dedupe (L346) | NEUTRAL | We have none of these. |
| 2.1.281 | Auto-mode classifier reuses its prompt cache after resume (L401); denial covers the outcome (L402) | IMPROVEMENT | Cheaper auto mode across `cc` resumes. |
| 2.1.281 | `--agents` accepts a JSON file path (L405); `/agents` stub removed (L444) | NEUTRAL | — |
| 2.1.281 | Self-hosted runner `--system-prompt-file` requirement (L433) | NEUTRAL | We have no self-hosted runners. |

Items not listed (UI/vim/keybindings, VSCode, Claude Tag, cloud, gateway, plugin, artifact) are NEUTRAL for this axis.
I checked them by reading every line in the range.

## Observation outside the brief (data, no action taken)
During this run a PostToolUse peer-mail injection reported that a
`~/.claude-284/... claude --model claude-sonnet-5-5 --print --output-format json` process sent SIGTERM to a
`cc-await-ping` watcher. The most likely explanation is a 2.1.284 `-p` eval run tearing down its own background
Bash on exit, but I did not verify it. The owner of the 284 eval should confirm this before advancing.

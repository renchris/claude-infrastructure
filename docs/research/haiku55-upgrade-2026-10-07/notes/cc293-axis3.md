# cc293 axis 3: hooks, permission modes, auto mode, launchers (2.1.285 to 2.1.293)

Read-only audit, 2026-10-07. Source: `pack/cc-changelog.md` lines 3-815, read in full (every line,
three Read calls). "L" numbers are line numbers in that file. Fleet facts were read from
`~/.zshrc` (claude() pins `~/.claude-284/node_modules/.bin/claude`, `--permission-mode auto`,
`DISABLE_AUTOUPDATER=1`, `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1`), `~/.claude/settings.json`
(defaultMode `auto`, 361 allow / 41 deny / 3 ask rules, `autoCompactEnabled: false`, no `sandbox`
key, `remoteControlAtStartup: true`, `teammateMode: iterm2`; counts measured with a python3 json
read), and the worktree's hooks, bin, scripts, skills and agents.

**Verdict for this axis: no BLOCKER found. Twelve CAUTIONs must be re-verified on the 2.1.293
binary before the pin moves; four of them can only be settled by a live probe, not by reading.**

What was not done: no live session was started on 2.1.293, no pane was captured, no gate was run.
`bats tests/pane-modal.bats` ran to completion in the background (slow: over 2 minutes, most of it
the two greps of a 236 MB binary): **25 of 25 ok**, including `ok 24 ANTI-ROT: every enumerated
fragment is present in the shipping claude binary` and its positive control. The test picks the
highest-numbered `~/.claude-N` track, and `~/.claude-293` (package.json version 2.1.293) is
installed, so the anti-rot result is for the candidate. Direct `grep -caF` counts against the
2.1.293 binary (below) agree. That test proves the strings exist; it does not render a prompt, so
it says nothing about where "2 of 5" is drawn.

## Rated changes

| Ver | L | Change | Rating | Why it matters here | What to re-verify |
|---|---|---|---|---|---|
| 2.1.293 | 42 | Reverted the 2.1.281 auto-mode denial message that told Claude a denial covers the outcome, not only the exact command | CAUTION | After a classifier denial the model is again told only that this command was refused, so it may retry a variant spelling. Our `autoMode.soft_deny` list (35 entries) and `permission-denied.sh` hook are the only backstop. A revert in the candidate release has zero soak. | Trigger one soft-deny (for example a force push) on 293 and read whether the next tool call is a respelling; confirm `PermissionDenied` hook still fires. |
| 2.1.293 | 43 | Reverted the 2.1.290 fix for cloud sessions staying asleep after a container restart | CAUTION (cloud lane only) | Only binary dependency is the `-p ... --cloud <id>` send in `bin/cc-notify`; a cloud `/loop` wakeup can be lost silently again. | Do not rely on cloud `/loop` wakeups on 293. |
| 2.1.293 | 13-14 | Claude no longer told to use SendMessage / told a built-in tool is disabled session-wide when a `--tools` list or permission rule removed it only for a subagent | IMPROVEMENT | Agent definitions with narrow `tools:` (5 of 5 in `agents/`) stop receiving wrong guidance. | None. |
| 2.1.293 | 11 | `/model` effort arrows no longer wrap and save Low as a model default | IMPROVEMENT | `modelSettings.claude-opus-5-5.effortLevel` could have been silently overwritten. | None. |
| 2.1.293 | 16 | `claude logs/stop/kill/rm` and `claude daemon status/stop/uninstall` could sign you out when login was near expiry | IMPROVEMENT (churn) | Four-account fleet; any spurious sign-out feeds the revoked-login path. Last fix of the sign-out cluster lands in the candidate itself. | Watch `authentication_failed` StopFailure rows for 7 days after the flip. |
| 2.1.293 | 31 | Esc / No on a permission prompt did not stop the turn if `←` had just been pressed | NEUTRAL | Panes are scraped, not driven with `←`. | None. |
| 2.1.293 | 33 | Path-scoped rules and nested CLAUDE.md now load on single-file `cat/head/tail/sed -n/grep` in Bash | CAUTION (small) | More rules load mid-session, so `InstructionsLoaded` fires more often; our hook is registered with matcher `session_start` only, so cost is context, not hook time. | Check one retrieval subagent's context size after a `cat` of a scoped file. |
| 2.1.293 | 34-35 | Pasted text that begins and ends with the same words, or a skill name followed by an accent, no longer treated as typed | IMPROVEMENT (churn) | `scripts/handoff-fire.sh` pastes whole briefs into panes; "paste read as typed" lets a `/skill` name in a brief fire as a command. Fifth fix in this cluster across 290-293. | Fire one handoff brief containing a `/skill` token on 293. |
| 2.1.293 | 37 | `claude purge` no longer stops silently on an undeletable file; deletes the rest, exits 1 | NEUTRAL (read carefully) | No fleet script calls `claude purge` or `claude project purge` (grep of bin, scripts, hooks, skills: 0 hits). The line does not say whether purge follows symlinks. | Keep it uncalled; never run it against a symlink-farm config dir. |
| 2.1.293 | 6 | `agentType` added to `subagentStatusLine` payload | NEUTRAL | We set `statusLine`, not `subagentStatusLine`. | None. |
| 2.1.293 | 9 | HTTP MCP connection memory leak fixed | IMPROVEMENT | Long sessions with ms365 / remote connectors on a 16 GB box. | None. |
| 2.1.293 | 50 | MCP servers announced to the model in a new order when names contain non-ASCII | NEUTRAL | All fleet server names are ASCII, so the prompt prefix does not move. | None. |
| 2.1.292 | 126 | `<system-reminder>` tags in hook output are escaped before reaching Claude | NEUTRAL | No fleet hook emits a literal `<system-reminder>` tag (grep of `hooks/`: one hit, a regex in `lib/transcript_norm.py` that strips them). | None. |
| 2.1.292 | 127 | Write, WebFetch and Read ignore stray parameters instead of failing | CAUTION (small) | A silently ignored parameter is the "dropped, not rejected" class. `backup-before-write.sh` and `check-edit-boundary.sh` read `tool_input`; they key on `file_path`, which is not a stray. | Confirm `backup-before-write.sh` fires on a Write carrying an extra key. |
| 2.1.292 | 77 | A skill's `allowed-tools` rule no longer comes back in a later turn after leaving auto or plan mode mid-turn | IMPROVEMENT (churn) | Second `allowed-tools` lifecycle bug in the band; the other (#99353) is still open. See holds answer. | See #99353 below. |
| 2.1.292 | 70 | `permissionMode: auto` in a subagent definition no longer enters auto mode when auto is unavailable | NEUTRAL | No file in `agents/` sets `permissionMode` (grep: 0 hits). | None. |
| 2.1.292 | 81 | One-shot `claude -p` now waits for background commands and scheduled wakeups instead of stopping them 5 s after the result | CAUTION | Headless fires can now run far past the final result (bounded by the 30-minute unattended limit, L461/L763). Any launcher that wraps `-p` in `timeout` or reads exit as "done" sees longer runs. | Time one `-p` fire that leaves a `run_in_background` shell; check the wrappers in `scripts/` that use `--bare -p`. |
| 2.1.292 | 123 | `-p`/SDK first turn no longer waits for HTTP/SSE MCP servers' `resources/list` | CAUTION | Same family as the standing landmine "`-p` + `--mcp-config` not connected before first turn" (fixed 2.1.221). Tools are still awaited; resources are not. Users: `scripts/handoff-fire.sh`, `scripts/mcp-ssot-wire.sh`, `scripts/lib/mcp-noinherit.sh`. | Run `scripts/mcp-modal-e2e-probe.py` on 293; confirm the first turn makes a real tool call, not literal text. |
| 2.1.292 | 134-135 | stdio MCP servers now negotiate protocol 2026-07-28 by default; a server that ignores the check costs one slow connect, then is remembered for 7 days; `MCP_PROTOCOL_NEGOTIATION=legacy` opts out | CAUTION | Every local server (mac-messages, motion, motion-plus, ms365, agent-browser) connects a new way. `MCP_TIMEOUT` is 30000 in settings; a slow first connect in a headless fire can exceed it. holds.md: check13 passes on any one connected server. | Compare each server's connect state against the 2.1.284 run, per server, on a fresh config dir. Opt-out env is present in the 293 binary (`grep -caF`: 6). |
| 2.1.292 | 79 | An MCP tool name over 128 chars is dropped with a named error instead of failing every request | IMPROVEMENT | Loud instead of fatal. | None. |
| 2.1.292 | 82 | Plan mode restored on `/resume` and the session picker | IMPROVEMENT | `claude-plan` alias; second fix after L260. | None. |
| 2.1.292 | 65 | Agent tool gains an `effort` parameter | CAUTION (hook input) | `PreToolUse(Agent)` hooks `agent-teams-enforce.sh` and `frontier-spawn-gate.sh` now see a new `tool_input.effort`. They must not treat an unknown key as an error, and the frontier gate should decide whether effort is part of its budget. | Read both hooks' jq against a payload carrying `effort`. |
| 2.1.292 | 102 | Write/Edit/Read rows now show why a mod denied the call | NEUTRAL | Mods are off here. | None. |
| 2.1.292 | 139 | Agent names capped at 256 chars; longer `name` in a skill is ignored | NEUTRAL | No fleet name is near that. | None. |
| 2.1.291 | 159-160 | Fixed 2.1.290 cloud permission-answer drop and the 2.1.288 loss of a session's last messages on quit | IMPROVEMENT | Discharges the "nothing below 2.1.291" correction in holds.md. | None beyond the cluster note. |
| 2.1.290 | 279 | Permission rules and safety checks are now applied to a tool call AFTER a PreToolUse hook rewrote its input | CAUTION (top) | Four fleet hooks emit `updatedInput`: `qos-rewrite.sh`, `coldcompile-admit.sh`, `curl-gate.py`, `backup-before-write.sh`. The rewritten command (for example a QoS-wrapped one) is now what the 361 allow rules, 3 ask rules and the classifier see. A rule that matched the original spelling may no longer match, which turns an allowed call into a prompt or a classifier round trip; in an unattended pane a prompt is a wedge. | On 293, run one command through each rewriting hook under `auto` and under `default`; confirm no new prompt and that deny rules still bite on the rewritten text. |
| 2.1.290 | 288 | Edits to the file a symlinked settings file points at now raise the settings-file permission question | CAUTION (top) | `~/.claude-next/settings.json` and `~/.claude-secondary/settings.json` are symlinks to `~/.claude/settings.json` (measured: `ls -l`). Any session or script path that edits the target through the Edit/Write tool now gets a question that only a person can answer. | Edit a scratch key in the target from a 293 session launched with `CLAUDE_CONFIG_DIR=~/.claude-next`; record whether auto mode answers or a modal appears, and whether `pane-modal.sh` names it. |
| 2.1.290 | 239, 241, 267, 306, 311 | Bash permission checks now prompt for `rg` / `git grep` with shell-expandable arguments, zsh-divergent variable names, wildcard option values, `pyright`, and more forms of `ps` | CAUTION | Retrieval subagents (the Haiku role) live on `rg` and `git grep`. Under `auto` these go to the classifier (quota and latency per call); under any non-auto mode they prompt. `smart-bash-allowlist.sh` may already allow them, but its allow now meets L279 and L559. | Run an Explore-style subagent on 293 with an unquoted-glob `rg` and count prompts and classifier calls. |
| 2.1.290 | 215 | A deny or ask rule no longer misses a command named through a `declare`/`export` prefix | IMPROVEMENT | Closes a bypass of our 41 deny rules. | None. |
| 2.1.290 | 227 | Auto-mode denials no longer suggest a rule that skips the classifier for a whole tool | IMPROVEMENT | Stops the model proposing `Bash(*)`-style rules. | None. |
| 2.1.290 | 185 | Plan mode no longer lets the classifier approve non-read-only connector tools | IMPROVEMENT | ms365 send tools under `claude-plan`. | None. |
| 2.1.290 | 186 | A project CLAUDE.md, rule or AGENTS.md symlinked outside the working directories no longer loads when a Read deny rule (or the outside-read block) is in force | CAUTION | We carry 11 `Read(...)` deny rules and `hooks/setup-plan-symlinks.sh` creates project symlinks. The worktree has 0 committed symlinks (measured: `git ls-files -s`), and the deny rules are all `./`-relative secrets patterns, so the expected effect is none, but a rule that silently stops loading is the worst failure shape on this axis. | Diff the `InstructionsLoaded` list for one project session on 284 vs 293. |
| 2.1.290 | 268 | `CLAUDE_CODE_USER_DIALOG_TIMEOUT_MS=5m` was read as 5 ms; unit suffixes now fall back to `dialogExpiry` | NEUTRAL | The variable is not set anywhere in `~/.zshrc`, hooks, bin, scripts or skills (grep: 0 hits). The landmine row "set the AskUserQuestion idle-timeout in launcher profiles" is therefore still not done; if it is ever set, use plain milliseconds. | None for the upgrade. |
| 2.1.290 | 276 | Background workers no longer honor `--allow-dangerously-skip-permissions` on respawn without the disclaimer | NEUTRAL | Fleet is `auto`, not bypass. | None. |
| 2.1.290 | 290 | Permission prompts from background agents now show a "Ctrl+X Ctrl+K" stop-all line | CAUTION | One more restyle of the prompt body that `pane-modal.sh` scrapes; an added line does not break a per-line anchor, but it is in the restyle cluster. | Covered by the live-pane capture below. |
| 2.1.290 | 281, 266 | File names with line breaks render correctly in permission prompts; no freeze on long token-like text | NEUTRAL | Restyle cluster. | None. |
| 2.1.290 | 317 | In-process teammate `agent_id` in Agent results is now its agent ID (address stays in `teammate_id`); `TeammateIdle` no longer fires from a teammate's subagents or forks | CAUTION | `hooks/teammate-auto-shutdown.sh` (TeammateIdle) builds `agent_id="${5:-$2@$TEAM_NAME}"`; `teammateMode` is `iterm2`, not in-process, so the changed field should not reach us, and fewer TeammateIdle fires is what we want. | Run `tests` for teammate-auto-shutdown on a 293 payload; confirm the hook still gets one idle event per teammate. |
| 2.1.290 | 184 | Headless `--json-schema` runs no longer exit non-zero after the structured output was delivered | IMPROVEMENT | Workflow workers return through StructuredOutput. | None. |
| 2.1.290 | 256 | Bash tool no longer loses aliases, functions and PATH for a session on a new config dir | IMPROVEMENT | Fresh `~/.claude-NNN` tracks and per-account dirs. | None. |
| 2.1.290 | 280, 283 | First launch no longer re-asks the login method when a credentials file exists; macOS `/login` no longer reports success when the keychain kept the old login | IMPROVEMENT | Four accounts, keychain-backed; the second is the exact "login looked fine, token was stale" shape. | None. |
| 2.1.290 | 277 | Endless reply loop from a plugin async Stop hook with an unquoted spaced path | NEUTRAL | Our 13 Stop hooks are settings hooks with unspaced paths. | None. |
| 2.1.290 | 285 | Linux: sandboxed Bash ran `ConfigChange` hooks mid-command | NEUTRAL | macOS, no sandbox. | None. |
| 2.1.290 | 309 | Skills and commands refuse a `!` shell command containing raw control characters | CAUTION (small) | Loud, not silent. | `grep -rlP '[\x00-\x08\x0b-\x1f]' skills` before the flip. |
| 2.1.290 | 275 | Sessions backgrounded while idle no longer reopen as "no saved transcript" after "a restart or idle cleanup" | NEUTRAL (read carefully) | The only cleanup wording in 290. It fixes a lost transcript; nothing says cleanup follows symlinks. | See symlink landmine answer. |
| 2.1.290 | 237, 318 | Background sessions survive a Homebrew upgrade; sessions waiting on a wakeup are left running through updates | NEUTRAL | npm tracks, `DISABLE_AUTOUPDATER=1`. | None. |
| 2.1.289 | 357, 370, 371 | Deny/ask rules hold on nested compound commands and behind env-var prefixes | IMPROVEMENT | The sandbox auto-allow cases do not apply (no sandbox); the compound-command one does. | None. |
| 2.1.289 | 359 | Read deny rules now apply through symlinks for @-mentions | IMPROVEMENT | Secrets patterns. | None. |
| 2.1.289 | 363 | Installed mods did not load in the first session after an upgrade | NEUTRAL | Mods off (`tengu_plugin_hooks_modules:false` per holds.md). | None. |
| 2.1.288 | 443 | PreToolUse and PermissionRequest hooks that were SKIPPED when matching failed or the input could not be serialized now BLOCK the call | CAUTION (top) | This turns a silent skip into a hard block, which is the right direction, but our registrations include matchers that are not valid regex on their own (`*` for `research-block.sh`, the empty string for `cc-permission-beacon.sh`) and one anchored form (`^Bash$`). If any is counted as "matching failed", every tool call is blocked. Loud, so the gate would catch it, but it is the single change that could stop the whole fleet. | First check on 293: one Bash, one Write, one Agent, one MCP call; confirm each runs and that `research-block.sh` and `cc-permission-beacon.sh` logged a fire. |
| 2.1.288 | 442 | `idle_prompt` Notification hooks no longer fire while background agents are still running | CAUTION | `push-critical.sh` is registered on `idle_prompt`. Fewer false "idle" pushes is good; but any consumer that reads `idle_prompt` as "the lead stopped" now gets nothing while a subagent runs. | Confirm no watchdog (`goal-inert-watch.sh`, `lead-crash-watchdog.sh`) depends on that notification. |
| 2.1.288 | 451 | Auto mode: when the conversation is too long for the client-side classifier, it is now compacted instead of prompting or failing each call | CAUTION | `autoCompactEnabled` is `false` on this fleet on purpose. This is a second path to compaction that the setting may not govern. | Read whether `PreCompact`/`PostCompact` hooks (`dod-persist.sh`, `post-compact.sh`) fire on this path; watch for compactions in long `auto` sessions. |
| 2.1.288 | 462 | The client-side auto-mode classifier ignores an `ANTHROPIC_DEFAULT_SONNET_MODEL` pin naming Sonnet 5.5 or Opus 5.5 and uses Sonnet 5 | NEUTRAL | We do not set that variable; classifier quota stays on Sonnet 5. | None. |
| 2.1.288 | 440; 2.1.287 L495 | A dangerous `rm` inside `bash -c`/`sh -c`, or combined with a redirect to `~`, keeps its always-ask safeguard | IMPROVEMENT + CAUTION | Strengthens the destructive-command rules. Each is also a new must-ask prompt that an unattended pane cannot answer. | Covered by the rm probe in holds answers. |
| 2.1.288 | 401 | Auto-mode denials no longer point at a Bash rule when the blocked tool was not Bash | IMPROVEMENT | Cleaner `permission-denied.sh` input. | None. |
| 2.1.288 | 417-418 | `tool_decision` events now emitted for asks that end unanswered in `-p` | NEUTRAL | OTel not consumed. | None. |
| 2.1.288 | 447 | `InstructionsLoaded` now carries `agent_id`, `agent_type` and effort for subagent loads | IMPROVEMENT | `instructions-loaded.sh` gets fields it lacked; additive. | None. |
| 2.1.288 | 439 | Path-scoped rules and nested CLAUDE.md load on Write/Edit, not only Read | CAUTION (small) | More mid-session context for code-writing teammates; same note as L33. | Same as L33. |
| 2.1.288 | 436 | npm auto-updater no longer reports success when only the placeholder stub was installed | IMPROVEMENT (partial) | Addresses the symptom of #85154 (stub, no rollback) by failing loudly. Does not touch #84224. | See holds answer. |
| 2.1.288 | 425 | Headless sessions no longer ignore SIGTERM when a supervisor sends SIGCONT with it | IMPROVEMENT | `timeout`-wrapped `-p` fires. | None. |
| 2.1.288 | 437 | Remote Control cleanup no longer archives a session that is still connected | IMPROVEMENT | `remoteControlAtStartup: true` on every session. | None. |
| 2.1.288 | 461; 2.1.285 L763 | Background Bash time limit (30 min default, 2 h max) now applies only to unattended sessions | CAUTION | Terminal panes are exempt again, so the 3300 s `cc-await-ping` arm survives in panes. It is still cut in `-p`, SDK and cloud sessions. | Confirm no `-p` rail arms `cc-await-ping` or any background shell over 30 min. |
| 2.1.288 | 390, 466 | New re-authenticate prompt when an MCP server asks for more OAuth scope; URL prompts wait for "I'm done, continue" | CAUTION | Two new dialogs that `pane-modal.sh` does not enumerate. `Notification(elicitation_dialog)` is registered, so they should at least page. | Check the `elicitation_dialog` notification fires for both. |
| 2.1.288 | 458 | Shorter reason text on Bash permission prompts | NEUTRAL | We anchor on the question and the refusal option, not the reason. | None. |
| 2.1.288 | 463 | `claude project purge` renamed `claude purge` | NEUTRAL | Not called. | None. |
| 2.1.288 | 446 | `/login` in a `--bare` session no longer replaces the saved login | IMPROVEMENT | Six scripts use `--bare`. | None. |
| 2.1.287 | 520 | A revoked claude.ai login now shows "OAuth token revoked" instead of `API Error: 401`; in `-p` the error starts with "Failed to authenticate" | CAUTION (top) | See "revoked-login consumers" below. Two consumers lose their text match. | Force one revoked-token turn on 293 and capture the transcript record and the StopFailure payload. |
| 2.1.287 | 564 | Waiting permission prompts show oldest first | CAUTION | With stacked prompts the visible one is no longer the newest, so a `cc-permission-beacon.sh` row written for the newest request can describe a prompt that is not on screen. | Stack two asks; compare beacon content with the visible prompt. |
| 2.1.287 | 549-550; 2.1.286 L630-631 | MCP, fetch, skill, file-read, Bash and Monitor prompts restyled with the tool call between dashed lines | CAUTION | Restyle cluster. Dashed rules are non-alphanumeric, so the anchor eats them; the question line could have moved or been reworded per tool. | Live capture; see pane-modal answer. |
| 2.1.287 | 559 | Whole-tool `Bash` allow rules and ALLOWING HOOKS now prompt for, rather than run, shell writes to the Anthropic profile store and the host credentials file | CAUTION (top) | `smart-bash-allowlist.sh`, `rm-safe-allowlist.sh` and `ship-rail-push-allow.sh` return allow; account tooling (`bin/claude-accounts`, `bin/cc-config-slot`) writes credential files. Run from a session's Bash tool, those writes now stop at a prompt. | Run the account-slot path from a 293 session; confirm whether it prompts. Prefer running it outside the Bash tool. |
| 2.1.287 | 556 | A shell write through a repo-committed symlink onto a sensitive file or out of the tree waits for a person | NEUTRAL | 0 committed symlinks in this repo (measured). `~/.claude` links are not repo-committed. | Re-check per project repo that commits symlinks. |
| 2.1.287 | 488 | `asyncRewake` hooks with a missing script no longer wake Claude repeatedly | IMPROVEMENT | Our SessionStart inbox watcher uses `asyncRewake` with `rewakeMessage`/`rewakeSummary`; a moved script would have looped. | Confirm the rewake still delivers once on 293. |
| 2.1.287 | 530 | "N hooks ran" no longer counts internal callbacks | NEUTRAL | Any test that pins a hook count from the debug log shifts by one. | Grep tests for pinned counts if a gate reds. |
| 2.1.287 | 483, 561 | URL prompts from MCP servers on the 2025-11-25 protocol ("if a server no longer connects, add `bareElicitationCapability: true`"); `alwaysLoad: false` now defers all of a server's tools | CAUTION | The changelog itself warns a server may stop connecting. We set neither key (grep: 0 hits). | Same per-server comparison as L134-135. |
| 2.1.287 | 535, 551; 2.1.286 L599, L609 | Headless MCP: no false "needs authentication", transient connect retried, no day-long empty tool list | IMPROVEMENT | Headless-heavy fleet. | None. |
| 2.1.287 | 514 | `claude agents` sometimes hid the permission prompt a background session was waiting on | NEUTRAL | Panes, not `claude agents`. | None. |
| 2.1.287 | 479 | Claude Mods added | NEUTRAL | Off here; holds.md bans `$.agent.spawn` in fleet mods until probed. Nothing in the band changes that. | None. |
| 2.1.286 | 588 | A count such as "2 of 5" on the permission prompt when requests stack | CAUTION (top) | See pane-modal answer: placement decides whether the anchor survives. | Live pane capture with two stacked prompts. |
| 2.1.286 | 592 | No more API 400 after a hook returned an object, number or boolean | IMPROVEMENT | Hooks that print bare JSON scalars. | None. |
| 2.1.286 | 596 | When the API refuses the model an alias or default resolves to, Claude Code retries once on the previous model of the same tier | CAUTION | A `--model claude-haiku-5-5` or `model: "haiku"` spawn that is refused runs on Haiku 4.5 with no failure. A role assignment could be measured on the wrong model. | Read the model id from the transcript, not the launch flag, when evaluating Haiku 5.5. |
| 2.1.286 | 642 | `--bare` now connects only MCP servers named on the command line, sends no system reminders, starts no background tasks; a timed-out shell command stops instead of backgrounding | CAUTION | Six scripts use `--bare`: `bin/cc-cloud`, `scripts/postland-verify.sh`, `public-publish.sh`, `automode-land-probe.sh`, `memory-store-snapshot.sh`, `wrap-ledger-memo-bench.sh`. Any that relied on an inherited MCP server or on a long command moving to the background changes behavior. | Run each once on 293. |
| 2.1.286 | 636, 648 | `/hooks` UI reworked | NEUTRAL | Not scraped. | None. |
| 2.1.286 | 650 | `/exit` Remove worktree runs after servers and shells are stopped | NEUTRAL | Worktrees are removed by our rails. | None. |
| 2.1.285 | 704 | Hooks no longer see a missing or stale plan on ExitPlanMode | IMPROVEMENT | `plan-pin-session.sh` (PostToolUse) and `notify.sh plan` (PermissionRequest). | None. |
| 2.1.285 | 708 | Synchronous hooks no longer hang while a background child holds output open | IMPROVEMENT | `notify.sh`, `session-end.sh`, `session-register.sh`, `plan-version-commit.sh`, `session-beat.sh` all background work and redirect by hand to avoid this. | Keep the redirects. |
| 2.1.285 | 726 | A cancelled shell command or hook no longer starts anyway | IMPROVEMENT | Hooks with side effects. | None. |
| 2.1.285 | 698 | Fork subagents keep the parent's plan or `dontAsk` mode | IMPROVEMENT | Narrows #85264's surface; does not close it. | None. |
| 2.1.285 | 700, 754 | Background subagents in auto mode: no redundant second reply; run ends on hand-back | IMPROVEMENT | Quota. Watch `SubagentStop` timing. | None. |
| 2.1.285 | 769 | `claude -p` with telemetry off or on third-party providers starts in auto mode when no mode is configured | NEUTRAL | `defaultMode: auto` and `--permission-mode` are already set. A bare `-p` on an empty config dir now gets auto, not manual. | None. |
| 2.1.285 | 768 | The one-time "make auto your default" offer shows more widely | NEUTRAL | `skipAutoPermissionPrompt: true`. | None. |
| 2.1.285 | 695 | `-p --permission-prompt-tool` background subagent requests reach the tool | NEUTRAL | Flag not used (grep: 0 hits). | None. |
| 2.1.285 | 736 | A reply from `claude agents` could approve a pending command | NEUTRAL | Not used. | None. |
| 2.1.285 | 737 | `claude attach/logs/stop/respawn/rm` with options first (as from a shell alias) started a new session | IMPROVEMENT | claude() injects `--permission-mode --model --effort` before `"$@"`, exactly this shape. | None. |
| 2.1.285 | 745 | Approved Edit on a device-symlinked file now goes through | NEUTRAL | Not our symlink shape. | None. |
| 2.1.285 | 703 | A plugin install can no longer land in another plugin's cache folder | NEUTRAL | No third-party plugins enabled. | None. |
| 2.1.285 | 687 | Unreadable managed settings: warn and start; unparseable: stop every session | NEUTRAL | No managed settings file. | None. |

## holds.md items answered (axis 3 only)

| Item | Verdict | Evidence |
|---|---|---|
| **#84224** auto-updater installs into the PATH-resolved npm prefix | **Still open.** | `gh issue view`: OPEN on 2026-10-07. Nothing in L3-815 mentions the npm prefix. Keep `DISABLE_AUTOUPDATER=1`. Note the `claude-latest` branch of the launcher (`~/.zshrc:179-181`) does not set it. |
| **#85154** npm update leaves a stub and no rollback | **Symptom narrowed, not discharged.** | Closed NOT_PLANNED (a closure, not a fix). 2.1.288 L436 makes the stub case report failure instead of success; there is still no rollback. |
| **`rm -rf "$(...)"` asks, then denies after 2 min (2.1.281)** | **Left open, unchanged.** | No line in the band touches it. `CLAUDE_CODE_DISABLE_SUBSTITUTION_RM_PROMPT` is still in the 293 binary (`grep -caF`: 4, was 5 on 284). The band adds two more always-ask rm shapes (L440, L495). What 293 L42 reverts is the other 2.1.281 line (the denial message), not this rule. |
| **Transcript-tamper rules** | **Silent.** | No line in L3-815 mentions transcript tampering. Treat as unchanged and unprobed. |
| **#97888** trust flag reverting | **Still open.** | `gh issue view`: OPEN. No fix line. `workspace-trust-modal` in `pane-modal.sh` stays load-bearing; its four fragments are present in 293 (counts below). |
| **Revoked-login text (2.1.287 L520)** | **Confirmed; one more consumer than holds.md lists.** | See next section. |
| **Restyled permission prompts (2.1.286-287)** | **Left open: static check passes, live capture not done.** | See pane-modal section. |
| **#99353** skill `allowed-tools` dropped when the Skill tool finishes before the stream ends | **Still open; fleet exposure is real but small.** | `gh issue view`: OPEN. 2.1.292 L77 fixes a different `allowed-tools` bug (rule returning later). Nine fleet skills declare `allowed-tools`: `model-upgrade`, `cc-version-audit`, `cc-upgrade-gate` (each `Skill`), `cc-upgrade`, `agent-browser` (`Bash`), `read-twitter`, `dia-agent`, `plan-update`, `frontend-design-vue`. In `auto` mode a dropped rule costs classifier calls rather than a prompt, because 361 allow rules and the classifier cover the same tools. The exposed ones are the three thin wrappers whose only grant is `Skill`, and `agent-browser`, which fan out or run unattended; under a non-auto mode a dropped grant becomes a prompt. No skill uses `allowed-tools` as a restriction, so nothing becomes less safe. |
| **check13 passes on any one connected MCP server** | **Made worse by the band.** | Three connection-behavior changes (L483, L134-135, L123) each can leave one server down while another is up. Compare per server. |
| **"Shared agents" is not a feature / ban `$.agent.spawn` in mods** | **Unchanged.** | 2.1.292 L69 adds workflow agents to the `agent.spawn` mod hook; mods stay off, ban stands. |
| **Landmine: default permission-mode flip** | **No new flip for us.** | L769 changes the unconfigured `-p` default to auto on telemetry-off installs; we pin `auto` in both settings and the launcher. Gate #3/#11 still need to prove it on 293. |
| **Landmine: hook matchers** | **Non-issue stands, with one new check.** | No matcher-syntax change. But L443 makes a failed match block instead of skip; verify the `*` and empty matchers (first row to test on 293). |
| **Landmine: Write may overwrite an unread file (2.1.228)** | **Left open.** | Nothing in the band restores read-before-write for Write. `backup-before-write.sh` is still the only guard; it is registered on `Write\|Edit\|MultiEdit` with a 10 s timeout and emits `updatedInput`, so it now also meets L279 and L127. Verify it fires on 293 before advancing. |
| **Landmine: session cleanup / cache GC following symlinks** | **No new symlink-following cleanup announced; not proven absent.** | Cleanup lines in the band: L37 and L463 (`claude purge`, not called here), L275 (idle cleanup lost a transcript, fixed), L437 (Remote Control cleanup, fixed), L703 (plugin cache collision, fixed), L650 (`/exit` worktree removal order). None says it follows links. `cleanupPeriodDays` is 365. A silent band is not a proof: run the canary (a throwaway config dir with a symlinked file, one session start and end on 293, then `ls -l`). |
| **Landmine: `-p` + `--mcp-config` first turn** | **Re-opened for re-verification.** | L123 changes what the first turn waits for. |
| **Landmine: AskUserQuestion stopped auto-continue (2.1.200)** | **Left open.** | No idle-timeout is set in any launcher (grep: 0 hits). `cc-unattended-ask-guard.sh` (PreToolUse on AskUserQuestion) remains the guard. L268 only fixes unit parsing of the dialog timeout. |
| **Landmine: effort override** | **Non-issue stands.** | L11 and L199 are fixes in our favor. |
| **Spawn ceiling (grep restored / limit / cap / ceiling / depth / budget)** | **Still uncapped.** | 40 keyword hits in the slice (measured: awk + grep -niE), none restores a subagent-per-session cap or changes depth. The only "ceiling" lines are a mod `tool.check` field (L166) and an org per-tool permission ceiling (L502). `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` is still in the binary (5 hits on both). The per-agent token budget text is present in 293 (`has a budget of`: 284 = 0, 293 = 2 by `grep -caF` line count) with no changelog line; enforcement unprobed. #84974 is now CLOSED NOT_PLANNED (not a fix); #85264 OPEN. |

### Revoked-login consumers (grep for "has been revoked" over the worktree)

| Consumer | What it does | Goes blind on 293? |
|---|---|---|
| `docs/plans/MASTER_ACCOUNT_FACTS.md:141-142` | The reopen trigger: `grep -h 'has been revoked'` over `isApiErrorMessage` transcript rows, three in 7 days | **Yes.** Re-key on `"error":"authentication_failed"`. |
| `hooks/stop-failure-marker.sh:583-584` (`_sf_fact_scope`) | Writes the `auth` fact when `ERR` is `authentication_failed` OR the last message matches "not logged in", "401", "invalid api key", "token has expired" and similar | **Text arm yes, field arm no.** "OAuth token revoked" and "Failed to authenticate" match none of the phrases, and the `401` the old generic text carried is gone. The hook still works only if the StopFailure `error` field stays `authentication_failed`. Not found by the "has been revoked" grep; found by reading the matcher. Add `*"token revoked"*` and `*"failed to authenticate"*`. |
| `bin/cc-config-slot:27,33` | Comments that quote the old text and point at the trigger above | Documentation only; update the wording. |
| `docs/research/claude-code-mods-2026-10-03/REPORT-289.md:115`, `skills/cc-upgrade/holds.md:61` | Already describe the change | No. |

Consumers already keyed on the field and unaffected: `scripts/limit-recover/lr_predicate.py`,
`tests/stop-failure-marker.bats`, `tests/lr-predicate.bats`, `tests/handoff-recycle-remote-resume.bats`.
Binary strings (measured, `grep -caF` line counts): "OAuth token revoked" 284 = 2, 293 = 4;
"has been revoked" 10 and 10; "Failed to authenticate" 9 and 12. The old phrase still exists in
the binary, so only a live revoked turn shows which one reaches the transcript.

### pane-modal anchor and the "2 of 5" header

The anchor at `hooks/lib/pane-modal.sh:160` is
`^[^[:alnum:]]*([0-9]+\.)?[[:space:]]*(<fragment>)`. It tolerates box chrome and a menu index
before the fragment, and nothing alphanumeric. Whether "2 of 5" defeats it depends only on where
the count is drawn. Measured by sourcing the library and feeding four synthetic screens to
`pane_modal_reason`:

| Count placement | Result |
|---|---|
| On the title line, question on its own line (`Bash command (2 of 5)` ... `Do you want to proceed?`) | detected, `tool-permission-modal` |
| After the question (`Do you want to proceed? (2 of 5)`) | detected |
| Before the question, same line (`2 of 5 · Do you want to proceed?`) | **missed, rc 1** |
| Before the question in parentheses (`(2 of 5) Do you want to proceed?`) | **missed, rc 1** |

A miss is a false OK, the expensive direction: `verify_engagement` falls through to the INC-4
resend and pastes a brief into a live dialog. The changelog does not say where the count is drawn.
Static evidence on 293 (measured, `grep -caF`): every enumerated fragment is still in the binary:
"Do you want to proceed" 6 (same as 284), "No, and tell Claude what to do differently" 3,
"Deny, and tell Claude what to do differently" 2, and all MCP-trust, workspace-trust,
background-work and feedback-draft fragments at 2 or more. So the anti-rot half holds; the layout
half needs one live pane with two stacked asks on 293. If the count leads the question line, the
fix is one optional group in the anchor, `([0-9]+ of [0-9]+[^[:alnum:]]*)?`, plus a bats case.
`bats tests/pane-modal.bats`: 25 of 25 ok against the 293 track (strings only, not layout).

## Regression clusters (churn rule: safe floor is the last fix)

| Cluster | Broken in | Fixes / reverts in band | Last fix | 2.1.293 after it? |
|---|---|---|---|---|
| Session tail lost on quit | 2.1.288 | L160 | 2.1.291 | Yes, two releases later |
| Resume drops earlier thinking | 2.1.287 | L399 (288), L178 (290) | 2.1.290 | Yes |
| Background Bash time limit | 2.1.285 (L763) | L461 (288), L81 (292) | 2.1.292 | Yes, by one release |
| Slow or failed startup under SDK hosts | 2.1.285 | L251 | 2.1.290 | Yes |
| Plan mode not restored on resume | before band | L260 (290), L82 (292) | 2.1.292 | Yes, by one release |
| Cloud permission answers dropped | 2.1.290 | L159 | 2.1.291 | Yes (cloud only) |
| Cloud sessions asleep after container restart | before band | L245 (290), then **reverted** L43 (293) | none: the fix was withdrawn | **No. Open at 293.** Cloud lane only. |
| Auto-mode denial message | 2.1.281 | **reverted** L42 (293) | 2.1.293 | **At it, zero soak.** |
| Sign-out / login state | 2.1.288 (VSCode `auth status`) | L360 (289), L280 and L283 (290), L16 (293) | 2.1.293 | **At it, zero soak.** |
| Permission-prompt restyle | n/a (feature churn) | L588, L630-631 (286); L549-550, L564, L500 (287); L458 (288); L290, L281 (290); L31 (293) | 2.1.293 | **At it.** The scraper must be re-pinned to 293 specifically. |
| Bash permission-check tightening | n/a (security churn) | 285 L697; 287 L495, L559; 288 L414, L440; 289 L357, L370-371; 290 L215, L239, L241, L267, L279, L306, L311 | 2.1.290 | Yes, three releases quiet |
| `allowed-tools` lifecycle | before band | L77 (292); #99353 still open | 2.1.292, with a known open bug | Partly: one fix behind us, one bug not fixed |
| MCP connect and protocol negotiation | n/a | 286 L599, L609; 287 L483, L528, L535, L551, L561; 288 L427; 292 L123, L134-135; 293 L9 | 2.1.293 | **At it.** Default behavior changed one release ago. |
| Paste treated as typed | before band | 290 L270, L282; 292 L94; 293 L34-35 | 2.1.293 | **At it.** Five fixes in four releases. |
| Scheduled tasks / `/loop` wakeups | before band | 290 L182-183, L245, L318; 292 L83-84; 293 L43 (revert) | still moving | **No.** Do not build on `/loop`. |
| Background daemon and `claude agents` | standing landmine | 290 L192, L237, L308; 293 L16, L29-30 | 2.1.293 | **At it.** The standing rule says blocker until the last fix; the fleet does not route work through the daemon, so it stays a landmine, not a blocker. |
| Mods / plugin hooks worker | new in 2.1.287 | every release 287-293 (293: L25-28) | 2.1.293 | At it; mods are off here |
| Auto-updater | standing | L436 (288), L237 (290) | 2.1.290 | Yes, but #84224 is unfixed; stay on `DISABLE_AUTOUPDATER=1` |

Reading: 2.1.293 clears the two hard floors holds.md named (never 285-287; nothing below 291). It
sits exactly on the last change of six clusters on this axis and one day old, so it fails the
7-day churn bar and can advance only under the same operator override used for 2.1.280 and
2.1.284, after the re-verify list above reads clean.

## Order of re-verification on the 2.1.293 binary

1. L443: one call of each tool class runs; `*` and empty matchers still fire (fleet-stopping if wrong).
2. L279 + L559: each `updatedInput` hook and each allowing hook, under `auto`, no new prompt.
3. `backup-before-write.sh` fires on Write to an unread file.
4. Live pane with two stacked asks: where "2 of 5" is drawn; `pane_modal_reason` returns `tool-permission-modal`.
5. Revoked-token turn: transcript text and StopFailure `error` field.
6. Per-server MCP connect comparison against 2.1.284, interactive and `-p --mcp-config`.
7. L288: edit of the settings.json symlink target from `~/.claude-next`.
8. Symlink canary for cleanup.

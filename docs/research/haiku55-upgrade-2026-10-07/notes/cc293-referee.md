# Claude Code 2.1.285-2.1.293: audit referee (2026-10-07)

Role: try to refute every BLOCKER and CAUTION in `cc293-axis1.md`, `cc293-axis2.md`,
`cc293-axis3.md` and `cc293-adversary.md`, catch wrongly NEUTRAL ratings, and name what all four
missed in three classes (removed cap, changed default, cleanup that deletes or follows symlinks).

What I did, and how each number below was obtained:

- Read `pack/cc-changelog.md` lines 1-819 in full (four Read calls). "L" numbers are lines of that file.
- Read the four audit notes, `bin293-probes.md`, `skills/cc-upgrade/holds.md`, `UPGRADE.md`, the
  four gate outputs in `gate/`, the `claude()` launcher in `~/.zshrc`, and `~/.claude/settings.json`.
- **Binary reads** are my own `python3 mmap.find` passes over
  `~/.claude-284/.../bin/claude.exe` (OLD) and `~/.claude-293/.../bin/claude.exe` (NEW), JS region
  only (offset above 150,000,000). `@N` is a byte offset in NEW unless marked OLD. Neither binary was run.
- **Fleet reads** are `grep`, `ls -l`, `find`, `jq`/python reads of the worktree and of `~/.claude*`.
- **Issue reads** are `gh issue view <n> -R anthropics/claude-code --json title,state,body,comments`.
- Nothing was launched on 2.1.293 by me. This session itself runs 2.1.284 (measured: `ps` shows
  `~/.claude-284/node_modules/.bin/claude`), so my own tool calls prove nothing about 2.1.293.
  Every "probe" below is still owed unless the row cites gate output or a log written by the gate runs.

Fleet facts the verdicts lean on (all measured today):

- Launcher: `~/.zshrc:457-509`, binary `~/.claude-284`, `--permission-mode auto`,
  `--model claude-opus-5-5`, `--effort high`, `DISABLE_AUTOUPDATER=1`, `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1`.
- Settings: `defaultMode auto`; 361 allow, 41 deny, 3 ask; whole-tool allows are Edit, Write, Read,
  MultiEdit, Glob, Grep, SendMessage, WebSearch (no whole-tool Bash); `switchModelsOnFlag false`;
  `enableArtifact false`; `autoCompactEnabled false`; `teammateMode iterm2`;
  `modelSettings = {"claude-opus-5-5": {"effortLevel": "high"}}`.
- Every account config dir (`~/.claude-next`, `-secondary`, `-tertiary`, `-quaternary`) holds
  `CLAUDE.md`, `rules`, `settings.json`, `skills`, `agents`, `hooks` as symlinks into `~/.claude/`.
  `~/.claude-next/projects` is itself a symlink to `~/.claude/projects`; the other three are real directories.
- 62 sessions on 2.1.293 started between 22:00Z and 22:31Z today, the window of the gate runs
  (measured: 66 session ids in `~/.claude/logs/instructions-loaded.log` in that window, joined to
  the `"version"` field of each transcript; 62 read 2.1.293, 4 read 2.1.284). That log is the only
  live 2.1.293 evidence used here besides the gate JSON.

## Bottom line

**No BLOCKER survives unconditionally (0 of 2).** Both adversary blockers are downgraded, one of
them only on a condition the activation must meet. One item the adversary filed as NOISE is raised
and could become a blocker when probed.

- R1 (`next3` not entitled): the same account failed the same way under `claude-opus-5-5`, so it
  is a login, not a Haiku 5.5 entitlement gap. Downgraded to CAUTION.
- R2 (per-agent token budget): the claim "no setting or env var disables it" is wrong. The 2.1.293
  code reads a local switch before the server flag. Downgraded to CAUTION **only if** the switch is
  set fleet-wide and proven by one forced-on probe before the flip. Without that it stays a blocker
  for Agent-tool fan-outs.
- Raised: upstream #98899 (`--resume` finds nothing behind a symlinked session folder, 2.1.287+).
  The adversary's check looked for symlinked entries inside `projects/` and found none; it missed
  that `~/.claude-next/projects` (account 1, the launcher default) is itself a symlink. Unprobed.
  If it reproduces, resume on account 1 is broken and that is a blocker.

Verdict counts (measured by counting rows in the table below): 47 rated items; 14 STAND,
20 DOWNGRADED, 13 REFUTED.

## Verdict table

Sources: A1/A2/A3 = axis notes, ADV = adversary. "Low" means it should not hold the flip.

| # | Item (source, original rating) | Verdict | Evidence | What is still owed |
|---|---|---|---|---|
| V01 | ADV R1: gate RED, `next3` not entitled for Haiku 5.5 (BLOCKER) | **DOWNGRADED to CAUTION** | `gate/gate-293-opus55.stderr` shows `next3: NOT entitled (is_error=True)` for `claude-opus-5-5` too, a model that account is entitled to. Same failure on two models means the account, not the model. `UPGRADE.md:18` records `claude-accounts` auth `login-required` for `next3`. The 3-account reruns are GREEN 14/0/1 for both models. | `next3` entitlement for Haiku 5.5 is unproven until it is logged in. With L596 an unentitled account would silently run Haiku 4.5 under the alias. |
| V02 | ADV R2, A1 budget row, A2/A3 notes: per-agent token budget, server-switched, "not configurable" (BLOCKER / CAUTION) | **DOWNGRADED to CAUTION with an activation precondition** | NEW @194075643-194077400, read directly: mode comes from `CLAUDE_CODE_TOTAL_TOKENS_REMINDER` or settings key `totalTokensReminder` before any server value (`TKt()`); `sQe()` returns no budget unless the mode is `padded-countdown` or `off`, and for an env/settings `off` it logs "off by CLAUDE_CODE_TOTAL_TOKENS_REMINDER/settings; not reading tengu_rippling_tulip for this subagent". `SWt(e,n){return n??...}` puts env `CLAUDE_CODE_RIPPLING_TULIP` ahead of the server flag. Upstream #99949 reports `"CLAUDE_CODE_TOTAL_TOKENS_REMINDER": "infinite"` in the settings `env` block removed the sentence and the countdown in a live session (on 2.1.291, Linux). The adversary read issue bodies truncated and missed that workaround. The risk itself is real: #99949 shows subagents stopping themselves near 100K and hours of respawns, so "advisory" in code is not "harmless". Flags are absent today: `tengu_rippling_tulip`, `tengu_streamed_bumblebee`, `tengu_calm_mochi` have 0 occurrences in all five account `.claude.json` files. But server experiments in this family do land here: `~/.claude-secondary/.claude.json` carries `tengu_lapis_anchor: "off"` in three `claude-opus-5-5` client-data slots, and the one slot I printed in full names `experimentKey: "claude_code_redstart_lunette_experiment"`. | Set the switch before the flip and prove it with the forced-on command in the final list (item 1). The gate never ran a Fable 5.1 lead, the one cohort upstream saw the budget on. Per the binary probe (inferred, not re-read by me) Workflow `agent()` and in-process teammates do not carry the budget; Agent-tool subagents do. |
| V03 | L5: `haiku` alias moves to Haiku 5.5 (A1, A2, ADV: CAUTION) | **STANDS** | NEW @184407645 `haiku:{default:"claude-haiku-5-5",per_provider:{...4-5}}`; OLD @178331605 `haiku:{default:"claude-haiku-4-5"}`. Every `model: "haiku"` spawn changes model at the flip. Correction to A1 and ADV: the Agent tool `model` enum is `sonnet, opus, haiku, fable` (probe section 7), so a spawn cannot "pin `claude-haiku-4-5` by id". The levers are `ANTHROPIC_DEFAULT_HAIKU_MODEL=claude-haiku-4-5` (resolver NEW @186758432 reads it first) or an agent definition whose frontmatter names the id. | The gate never spawned `model: "haiku"` from an Opus lead (check #9 modelUsage carries one model only). Read the served id from a real retrieval subagent transcript after the flip. |
| V04 | Binary-only: Haiku 5.5 takes effort, 1M window, 128K output, 5x price over 100K tokens (A1: CAUTION) | **STANDS** | Probe section 3 precedence: env, then per-agent effort, then the session's explicit level, then the model default. The launcher always passes `--effort` (`~/.zshrc:501-508`), so a Haiku 5.5 subagent with no effort of its own runs at the lead's `high` (or `xhigh` under `claude-x`), not at the catalog `medium`. No fleet agent definition used for retrieval sets effort (measured: only `deep-research-sonnet.md` and `research-decomposition-critic.md` carry `effort:`). | Read `effort.level` from one SubagentStop payload at each lead level; then set effort per role explicitly. |
| V05 | L65: Agent `effort` parameter, no hook caps it (A1, A3, ADV R10: CAUTION; A2: IMPROVEMENT) | **STANDS (low)** | `hooks/agent-teams-enforce.sh:39-45` and `hooks/frontier-spawn-gate.sh:102` read name, team_name, run_in_background, subagent_type, model via `jq -r`; an extra key cannot break them and neither looks at `effort`. The tool text tells the model to set it only on explicit instruction (NEW @199976871). | Decide whether `frontier-spawn-gate.sh` should bound `tool_input.effort`. Update the stale comment at `~/.zshrc:196`. |
| V06 | L11: `/model` effort arrows could save Low (A1: CAUTION; A3: IMPROVEMENT) | **REFUTED as a caution** | It is a fix. `modelSettings` holds only `claude-opus-5-5: high` (measured), so no stray `low` exists. The effort question A1 attached to it is V04. | None. |
| V07 | L596: refused alias target retries once on the previous model of the tier (A1, A2, A3: CAUTION) | **STANDS** | Changelog text read. It makes a refused Haiku 5.5 spawn run Haiku 4.5 with no error, so any role evaluation must read the served model. The gate does assert `modelUsage` carries the model. | Keep "model from transcript, never from the spawn argument" in every Haiku 5.5 trial. |
| V08 | L317: in-process teammate `agent_id` changes; TeammateIdle no longer fires from a teammate's subagents (A1, A2, A3: CAUTION) | **DOWNGRADED to NEUTRAL** | No fleet consumer parses the Agent result's `agent_id` as `name@team`. `hooks/teammate-auto-shutdown.sh:771-772` reads `.teammate_name` and `.team_name`; `bin/cc-blockers:907-955` splits an id it takes from the `--agent-id` argument in `ps` output (read at lines 907-910), and `scripts/handoff-fire.sh:7590` builds its id from a tty, so both concern pane teammates; `teammate_id` is already known to `bin/cc-agent-harvest`, `scripts/reap-guard.sh`, `hooks/lib/transcript_norm.py`. Fewer TeammateIdle events is the direction the reaper wants. | `scripts/reaper-safety-gate.sh` on 2.1.293 and one live TeammateIdle payload. |
| V09 | L693: SSH passphrase prompts from worktree fetches now fail fast (A1: CAUTION) | **REFUTED for this repo** | `git remote -v`: origin is `https://github.com/...`; `ssh-add -l`: no identities. Worktrees are made by the launcher and the `WorktreeCreate` hook, not by the binary's own fetch. | Re-check only for a project whose remote is SSH. |
| V10 | L685: fork subagent's own Agent call under `-p` with `CLAUDE_CODE_FORK_SUBAGENT=1` (A1: CAUTION; A2: NEUTRAL) | **REFUTED** | The variable is set nowhere (0 hits in `~/.zshrc`, settings, bin, scripts, hooks, lib, skills, agents). In both builds the fork gate is disabled in non-interactive sessions unless the env is true (OLD @186199988, NEW @194079439: `if(env===!0)return"env";if(nonInteractive)return"disabled";return"default"`). Correction to A1/A2: in interactive sessions the same function returns `"default"` (enabled) in **both** builds unless one more condition I did not trace (`wAe()` in OLD, `CHe()` in NEW) disables it, so fork exposure (#85264) may exist today without the env and is not a delta. | Standing hold #85264; gate #15 is a static read and does not exercise a fork. |
| V11 | Silence: no spawn ceiling restored (A1: CAUTION) | **STANDS as a standing condition, not a delta** | My own read of L3-815 agrees: no line restores a per-session or concurrency cap. Gate #6 and #15 PASS on 2.1.293. Cached `tengu_hazel_trellis` is 3 on every account, so the env value 1 is the only thing holding depth. | Keep `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1` in the launcher and in `gate_headless`. |
| V12 | L90, L416: native cross-session delivery fixes (A1: CAUTION) | **DOWNGRADED to NEUTRAL as a delta** | Both are fixes to a subsystem the fleet has not adopted; 2.1.293 is better than 2.1.284 on each. The double-delivery hazard is standing and unchanged. | Keep "assess, do not adopt". |
| V13 | L549-550, L630-631, L290: restyled prompts, held-message prompt, stop-all line (A1, A3: CAUTION) | **DOWNGRADED (low)** | A3 measured `bats tests/pane-modal.bats` 25 of 25 against the 2.1.293 track, including the anti-rot case. Added lines do not defeat a per-line anchor. | One live capture, shared with V14. |
| V14 | L588: "2 of 5" count may defeat the anchor at `hooks/lib/pane-modal.sh:160` (A1: CAUTION; A3: CAUTION top) | **DOWNGRADED (low)** | Read from NEW @212714910 (inferred from minified code): the count comes from `positionLabel()` (@202520413, "N of M") and is passed as `aside` to the permission title component, which draws it dimmed at the right end of the **title row** (`justifyContent:"space-between"`), and only when it fits. The question line is a separate child row. A3's own synthetic test shows that placement is detected; the two placements that were missed (count before the question on the same line) are not what this frame draws. | One live pane with two stacked asks to confirm, since other dialog frames were not traced. |
| V15 | L564: waiting prompts show oldest first (A1, A3: CAUTION) | **STANDS (low)** | `cc-permission-beacon.sh write` runs on each PermissionRequest (settings, matcher empty), so with stacked asks the newest beacon row can describe a prompt that is not the one on screen. | Stack two asks; compare the beacon row with the visible prompt. |
| V16 | L758: `--resume` on a background session opens it instead of refusing (A1: CAUTION) | **DOWNGRADED (low), folded into missed item M1** | No fleet script keys on the binary's refusal: the fleet refuses on its own evidence (`hf_bg_hosted`, `scripts/handoff-fire.sh:5300-5309`, argv `--bg-pty-host`). The behavior did change for a session the daemon hosts. | See M1. |
| V17 | L81: one-shot `-p` now waits for a background command (A1, A2, A3, ADV R5: CAUTION) | **STANDS, with a correction** | Changelog text read. Correction: the wait is bounded by 10 minutes by default in a one-shot print session, not 30. NEW @191288805: `var uoe=600000;function OVt(){return JJ()?Math.max(uoe,cte()):xts()}` and `JJ()` is `singleShotPrintSession()` (@184044291). 30 minutes applies to other headless sessions; the ceiling is 2 hours when the call passes its own `timeout`. | Time one `-p` run that leaves `sleep 900` in the background; compare with caller timeouts (`scripts/meter-experiment/run.sh:65,72`). |
| V18 | L763, L461, ADV R4 (#99965): background command deadline in unattended sessions (CAUTION) | **STANDS for `-p` and SDK rails only** | Interactive panes, and subagents inside them, are exempt: the predicate is session-level (`uz()` reads `launchOptions.isInteractive()`). `tengu_cosmic_shore` is cached `true` on all accounts. `BASH_DEFAULT_TIMEOUT_MS` and `BASH_MAX_TIMEOUT_MS` are set nowhere (0 hits). The rail it reaches is the headless pane driver: `bin/cc-pane-headless` runs resident `claude -p --input-format stream-json` agents, which are headless but not one-shot, so they get the 30-minute default and a 3300 s `cc-await-ping` arm there is cut at 1800 s unless the call passes a `timeout` of at least 3,300,000 ms. `bin/cc-wake-headless:8-13` says that watcher is defence in depth and not the wake path, which is why this stays a CAUTION. Six files mention both a headless launch and `cc-await-ping` (measured with `comm -12` over two `grep -rl` lists: `bin/cc-bats`, `bin/cc-notify`, `bin/cc-pane-headless`, `bin/cc-reaper`, `bin/cc-wake-headless`, `scripts/handoff-fire.sh`); I read only the two headless drivers. | Same timing probe as V17, plus one resident headless agent armed with `cc-await-ping --timeout 3300`. |
| V19 | L321: WebSearch budget refills; may throttle a research lead (A2: CAUTION) | **REFUTED as a throttle risk** | NEW @189982110: capacity is `CLAUDE_CODE_MAX_WEB_SEARCHES_PER_SESSION ?? 200` and `tryConsume()` refuses only at capacity; refill is added on top (`tengu_memoized_turtle` cached 100 per hour). With the fleet's 1000, a session gets at least what 2.1.284 gave. It is a loosened cap; see missed item A-1. | None for the flip. |
| V20 | L318: background sessions waiting on a `/loop` wakeup survive low memory (A2: CAUTION; A3: NEUTRAL) | **DOWNGRADED (low)** | It only affects daemon-hosted sessions with a pending wakeup. The fleet treats background jobs as an exception path (M1), not a normal lane. | `claude agents --json` per account for jobs with a wakeup before blaming memory on it. |
| V21 | L43: revert of the cloud wakeup fix (A2, A3, ADV: CAUTION) | **DOWNGRADED to NEUTRAL as a local delta** | Inferred: the sleeping session runs in Anthropic's container on whatever build the cloud deploys, so the local pin does not select this behavior. The fleet's only local dependency is the send at `bin/cc-notify:120`. | Do not rely on cloud `/loop` wakeups, on either local build. |
| V22 | L70: `permissionMode: auto` in agent definitions; does Haiku 5.5 support auto mode (A2: CAUTION low) | **REFUTED** | Gate #3 on 2.1.293: auto mode drove a Bash turn on `claude-haiku-5-5` with `permission_denials=[]`. None of the five `agents/*.md` sets `permissionMode` (measured). | None. |
| V23 | L42: revert of the 2.1.281 denial message (A3, ADV R11: CAUTION) | **STANDS (low)** | Changelog text read. `hooks/permission-denied.sh` only records the event and never changes the outcome. The reverted wording is what the fleet ran before 2.1.281. Zero soak on a revert. | One soft-deny on 2.1.293; read whether the next call is a respelling. |
| V24 | L33, L439: path-scoped rules and nested CLAUDE.md load on Bash views and on Write/Edit (A3, ADV R13: CAUTION small) | **REFUTED for this repo** | None of the four rule files has `paths:` frontmatter; the worktree has one instruction file (`.claude/CLAUDE.md`) within depth 3. Nothing new can load. | Re-check a project that has nested instruction files. |
| V25 | L127: Write, WebFetch, Read ignore stray parameters (A3: CAUTION small) | **DOWNGRADED to NEUTRAL** | The Write hooks key on `file_path`; a dropped stray key cannot change what they see. Not probed. | Covered by item 6 in the final list. |
| V26 | L123: `-p` first turn no longer waits for MCP `resources/list` (A3, ADV R12: CAUTION) | **DOWNGRADED to NEUTRAL** | Tools are still awaited. No rail uses MCP resources (grep for the resource tools and `resources/list` finds only `hooks/lib/turn-scan.sh`, a transcript scanner). | `scripts/mcp-modal-e2e-probe.py` on 2.1.293 if cheap. |
| V27 | L134-135: stdio MCP negotiates protocol 2026-07-28 by default (A3, ADV R12: CAUTION) | **DOWNGRADED (low)** | Gate #13 detail on 2.1.293 lists `ms365` (the only stdio server in `~/.claude-next/.claude.json`) as Connected, with the four claude.ai connectors and `motion`. | Servers defined in other scopes (mac-messages, agent-browser) were not in that list; compare per account and per project. |
| V28 | L279: rules and safety checks now apply after a PreToolUse hook rewrites the input (A3: CAUTION top) | **STANDS (cost, not a wedge under auto)** | Three hooks rewrite Bash commands with `updatedInput` and deliberately no decision (`hooks/qos-rewrite.sh:118-122`, `coldcompile-admit.sh:175-178`, `curl-gate.py:192-201`). No allow rule names the rewritten prefixes (`taskpolicy`, `cc-admit`, `cc-cpubound`, `cc-bats`: 0 matches in 361 rules). So a rewritten command that used to ride an allow rule on its original spelling may now go to the classifier. Under `auto` that is latency and classifier quota; under `claude-plan` it is a prompt. | Run one command through each rewriting hook on 2.1.293 under `auto`; read `permission_denials` and wall time. |
| V29 | L288: edits to the target of a symlinked settings file now ask (A3: CAUTION top) | **DOWNGRADED (low)** | The symlinks exist (four account dirs point at `~/.claude/settings.json`). But the fleet forbids the edit that would trigger the question (`skills/permission-harvest/SKILL.md:169`), and settings changes go through operator-run scripts. The new question guards a path sessions are already told not to take. | Make sure the activation script does not edit `~/.claude/settings.json` through the Edit tool from a 2.1.293 session. |
| V30 | L239, L241, L267, L306, L311: more Bash forms ask (rg and git grep with expandable args, zsh-divergent names, pyright, ps) (A3: CAUTION) | **STANDS (quota)** | Changelog text read. `Bash(rg:*)`, `Bash(ps:*)`, `Bash(grep:*)` are allow rules, and these lines say such commands "now prompt" in the listed shapes, which under `auto` means a classifier call. Retrieval subagents live on these commands. | Count classifier calls for one Explore-style run with an unquoted glob on 2.1.293. |
| V31 | L186: symlinked CLAUDE.md or rule may stop loading under a Read deny rule (A3: CAUTION) | **REFUTED** | Measured on 2.1.293: gate sessions logged `session_start` loads of `~/.claude-next/CLAUDE.md`, `~/.claude-secondary/CLAUDE.md`, `~/.claude-tertiary/CLAUDE.md` (all symlinks) and both `~/.claude/rules/*.md` (reached through a symlinked `rules`), with the fleet's 11 Read deny rules in force. Project side: `find ~/Development -maxdepth 4` finds two symlinked CLAUDE.md, both pointing at `AGENTS.md` in the same folder. | None. |
| V32 | L309: skills refuse a `!` command with raw control characters (A3: CAUTION small) | **REFUTED** | 94 skill markdown files scanned; 0 raw control characters other than tab and newline; 0 files with CR. | None. |
| V33 | L443: hooks whose matching "failed" now block; `*` and the empty matcher might count (A3: CAUTION top) | **REFUTED** | NEW @195061207: the matcher function `W3(e,n,...)` opens with a test that returns true when the matcher `n` is empty or equals `"*"` (the minified text is `if(!n` OR `n==="*")return!0;`, written here without the pipe characters), so the empty matcher and `*` return before any regex is built; an invalid regex is caught and returns false. All other fleet matchers are valid regex. Gate #3, #9 and #11 ran Bash and Agent calls on 2.1.293 under the account config dirs, which carry the fleet hooks, with no denial. | The "input could not be serialized" arm is untested and rare. |
| V34 | L442: `idle_prompt` no longer fires while background agents run (A3: CAUTION) | **DOWNGRADED to IMPROVEMENT** | `idle_prompt` has no consumer besides the `push-critical.sh` registration (0 hits in hooks, bin, scripts, lib). No watchdog reads it. | None. |
| V35 | L451: auto mode compacts when the conversation is too long for the classifier (A3: CAUTION) | **DOWNGRADED (low)** | The served classifier for Opus 5.5 leads is `claude-sonnet-5[1m]` (measured: `tengu_auto_mode_config.modelByMainModel` in `~/.claude-next` and `~/.claude-secondary`), so the trigger sits at the lead's own 1M limit, where the old behavior was a prompt or failure on every call. | Watch for PreCompact rows in long `auto` sessions. |
| V36 | L440, L495: more always-ask `rm` shapes (A3: IMPROVEMENT + CAUTION) | **DOWNGRADED to NEUTRAL** | The shapes are `rm` on `/` or the home directory, which the deny list already refuses in their plain form. | None. |
| V37 | L390, L466: two new MCP dialogs (A3: CAUTION) | **STANDS (low)** | `pane-modal.sh` does not enumerate them; `Notification(elicitation_dialog)` is registered twice in settings and should page. | Confirm the notification fires for both. |
| V38 | L520: revoked-login text changes (A3: CAUTION top) | **STANDS (monitoring goes blind, nothing breaks)** | `hooks/stop-failure-marker.sh:583-584` matches "not logged in", a bare 401, "invalid api key" and similar; neither "OAuth token revoked" nor "Failed to authenticate" matches. The field arm (`authentication_failed`) still exists in the binary (25 and 25 hits). `docs/plans/MASTER_ACCOUNT_FACTS.md:141-142` greps for `has been revoked`. | Add the two phrases; re-key the reopen trigger on the error field. |
| V39 | L559: allowing hooks now prompt on shell writes to the credentials file (A3: CAUTION top) | **REFUTED** | Account tooling stores logins in the macOS Keychain (`bin/claude-accounts:488-491`, `bin/cc-config-slot:10`); neither script has a shell write to `.credentials.json` (0 hits), and no skill or agent text mentions the file. The check reads the command text, so a script called by name would not trip it either. | None. |
| V40 | L483, L561: URL prompts on the 2025-11-25 protocol; `alwaysLoad: false` (A3: CAUTION) | **DOWNGRADED to NEUTRAL** | Neither key is set; all servers in the account config connected on 2.1.293 (gate #13 detail). | Same per-scope comparison as V27. |
| V41 | L642: `--bare` changes; "six scripts use `--bare`" (A3: CAUTION) | **REFUTED** | All six cited hits are `git init --bare` or `git clone --bare` (`bin/cc-cloud:1552`, `scripts/postland-verify.sh:4516`, `public-publish.sh:151-152`, `automode-land-probe.sh:82`, `memory-store-snapshot.sh:104`, `wrap-ledger-memo-bench.sh:58`). No script launches `claude --bare` (0 hits). A2 had this right. | None. |
| V42 | ADV R3 (#99833, #100065): resume rewrites history to the prompt cache (CAUTION high) | **DOWNGRADED: not shown to be a version delta** | #100065: "Before that date the prefixes were read correctly, including on 2.1.289, which fails now", observed 2026-10-06. That points at the server, so 2.1.284 may already have it. It is a weekly-quota cost either way. | One `-p --resume` A/B on 2.1.284 and 2.1.293 reading `cache_read_input_tokens`. |
| V43 | ADV R6 (#100005): bypass flags do not suppress Write prompts in `-p` (CAUTION) | **REFUTED for fleet reach** | No launch site passes a bypass flag: `bin/reso-resume-one:95` is an input-validation list and `hooks/unit-gate.sh:9` is a comment. | It exposes a gate gap: no gate check runs a Write in `-p` (final list item 6). |
| V44 | ADV R7 (#100117): hook input lacks `run_in_background` when the schema strips it (CAUTION) | **REFUTED as a delta** | The same omission is in the 2.1.284 binary: OLD @192018314 applies `n.omit({run_in_background:!0})` when `xl()` or `XZ()` (the fork gate) is true; NEW @199978976 does the same on `kmr()` or `ZZ()`. `hooks/agent-teams-enforce.sh:42` has lived with it. | None for the flip. |
| V45 | ADV R8, R9 (#100013, #100003, #100004): teammates bound to an old team; queued messages lost on resume (CAUTION) | **DOWNGRADED to standing hazards** | Filed on 2.1.291/2.1.292; nothing shows 2.1.284 is free of them and the adversary says so. | Covered by the resume probes in the final list. |
| V46 | ADV R15 (#97763, #100154): subagent `output_tokens` undercount (CAUTION low) | **STANDS as a measurement caveat** | Not a delta. Any Haiku 5.5 cost figure taken from subagent transcripts is too low on both builds. | Price roles from the parent's `modelUsage`. |
| V47 | ADV R21, R22 (#99849, #100033, #100034) (CAUTION low) | **DOWNGRADED to standing, low** | No version tie to the band. | None for the flip. |

## Ratings that were wrongly low

- **W1. ADV R19, #98899, rated NOISE. Raise to CAUTION, unprobed, blocker if it reproduces.** The
  issue: since 2.1.287 `claude --resume` finds no sessions when the session folder under
  `projects/` is a symlink. The adversary counted symlinked entries inside `~/.claude/projects` and
  `~/.claude-secondary/projects` (0, and I measure 0 in all five). But `~/.claude-next/projects`
  is itself a symlink to `~/.claude/projects` (measured: `ls -ld`), and `~/.claude-next` is the
  launcher's default config dir. The issue describes a symlinked child, the fleet has a symlinked
  parent; whether the same code path trips is unknown. Gate #12 only checks that `cc` routes a
  resume to the launcher; it does not resume anything on 2.1.293. The gate runs did write
  transcripts through that symlink on 2.1.293, so writing works. Reading on resume is untested.
- **W2. "The fleet does not use the daemon or `claude agents`" (A2 clusters 3 and 4, A3 daemon row).
  The premise is wrong.** See missed item M1.
- **W3. A2 L462 NEUTRAL** is right for the line as written, but the same function changed in a way
  no changelog line states. See missed item B-2.
- **W4. A1 and A2 "exposure to forks only if a session sets the env".** In interactive sessions the
  fork gate's default branch is "enabled" in both builds, subject to one condition I did not trace
  (V10). Not a delta; the hold on #85264 may be stronger than the notes say.

## What all four missed, by class

### (a) A removed limit or cap

- **A-1. WebSearch has no session lifetime stop any more (L321).** A2 rated it only as a throttle
  risk. Measured in NEW @189982110: an interactive session gets a bucket of
  `CLAUDE_CODE_MAX_WEB_SEARCHES_PER_SESSION` (1000 here) that refills at 100 per hour. On 2.1.284
  a runaway research loop ended at 1000 searches; on 2.1.293 it continues at 100 per hour for as
  long as the session lives. `CLAUDE_CODE_WEB_SEARCH_REFILLS_PER_HOUR=0` restores the hard stop.
  Low risk; say which behavior is wanted.
- **A-2. WebFetch no longer cuts a page at 100,000 characters without saying so (L179).** It now
  reports the unread amount and takes an `offset`. Nobody rated it. A research or synthesis worker
  will now page through long documents, which is more tokens per fetch, and with Haiku 5.5's 1M
  window nothing else stops it. Estimated effect: small per fetch, unbounded per page count.
- **A-3. The one-shot `-p` background deadline is 10 minutes, not 30 (V17).** All four notes carry
  the changelog's "default 30 min". The binary applies 600,000 ms to single-shot print sessions.
- Already covered by A1 and listed here only for completeness: the `haiku` alias goes from a 200K
  window and 32K output to 1M and 128K.

### (b) A changed default

- **B-1. The small/fast helper model becomes Haiku 5.5 on first party, and its thinking cannot be
  turned off.** Probe section 2 has the code; no audit table rates it. `Yw()` resolves through the
  same alias (NEW @186749718), so session titles, summaries, WebFetch page summaries, prompt
  suggestions and the away summary (both enabled in settings `env`) move to Haiku 5.5 in every
  session at the flip; four helper call sites are pinned to 4.5. Haiku 5.5 carries
  `rejects_disabled_thinking`, so these calls now always think. API price per token is lower
  (L5: $0.10/$0.50 against Haiku 4.5), but plan-quota weight and added latency are not stated
  anywhere. The built-in `claude-code-guide` agent (`model:"haiku"`) moves too.
  `ANTHROPIC_SMALL_FAST_MODEL` pins the helper alone.
- **B-2. A Haiku-led session in auto mode is now judged by Sonnet 5, not by Haiku.** OLD
  @180084431 returns early for any `claude-haiku-*` main model, so the classifier fell through to
  the main model itself; NEW @186755345 drops that test. The server config agrees on one account:
  `~/.claude-secondary/.claude.json` maps `claude-haiku-5-5` to `claude-sonnet-5[1m]` in
  `tengu_auto_mode_config.modelByMainModel` (measured). The classifier follows the session's main
  model, so this does not touch a Haiku subagent inside an Opus session (already Sonnet 5 on both
  builds). It does touch every role run as its own session: a Haiku 5.5 pane teammate or a
  `claude -p --model claude-haiku-5-5` extraction slot pays a Sonnet 5 call for each action the
  allow rules do not cover. Gate `modelUsage` shows no classifier model at all, so the gate cannot
  see this cost.
- **B-3. A server flag can lower subagent effort without notice.** NEW @199940512: when the agent
  has no effort of its own and `CLAUDE_CODE_EFFORT_LEVEL` is unset, `tengu_harmonic_riddle` (env
  `CLAUDE_CODE_HARMONIC_RIDDLE`) may step a subagent below the session's effort. 0 hits in OLD.
  Not cached on any account today (0 occurrences). The probe mentions it as a side finding; no
  table rates it. The fix is the same as V04: give each role an explicit effort.
- **B-4. Server experiments keyed by account and main model already reach this fleet.** Measured:
  the `next2` slot for `claude-opus-5-5` names `claude_code_redstart_lunette_experiment` and, in
  the same slot, `tengu_lapis_anchor: "off"`, two values holding prompt text
  (`tengu_heron_brook`, `tengu_brook_heron`), and a model map
  `breezy_horizon: {"claude-opus-5-5": "claude-opus-4-8"}` whose use I did not trace. Client-data slots for
  `claude-haiku-5-5` carry `per_turn_effort: true`. So one account can behave differently from the
  other three on the same binary. Any Haiku 5.5 role trial must name the account it ran on.
- **B-5. Retry budget is smaller (L641, L746).** One limit now covers a whole model call, at most
  14 requests with default settings, where a failing streamed call could reach 21. Nobody rated
  it. `CLAUDE_CODE_MAX_RETRIES` is not set here. Expect StopFailure to arrive sooner in an overload,
  which is what `limit-recover` keys on. Low.
- **B-6. First request waits up to 1.5 seconds for the server's output limit and auto-compact
  window (L444).** Nobody rated it. Each fresh `-p` worker can pay it; the server-supplied output
  limit is 128000 for both Opus 5.5 and Haiku 5.5 on these accounts (measured: `heather_vale`).
- Checked and found not to reach the fleet: L626 (no skill named `verify`, measured in the repo
  and in `~/.claude/skills`); L563 and L199 (`switchModelsOnFlag` is false); L769, L304, L322
  (`DISABLE_TELEMETRY`, `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`, `CLAUDE_CODE_DISABLE_ATTACHMENTS`
  set nowhere); L138 (`enableArtifact` false); L557 and L765 (first party, no `ANTHROPIC_BASE_URL`
  outside `bin/claude-kimi`).

### (c) Cleanup that deletes files or follows symlinks

- My read of L3-815 agrees with A3: no line announces a cleanup that follows symlinks. Cleanup
  lines are L37 and L463 (`claude purge`, called by no fleet script: 0 hits), L275, L437, L703,
  L650, and L228 (a `/teleport` stash that deleted files, fixed; nobody rated it; teleport is not
  used here). L437 matters in the fleet's favor because `remoteControlAtStartup` is true.
- **C-1. One new, dormant switch in the binary that no changelog line names.** NEW @201738371:
  a non-interactive, non-remote session with `CLAUDE_CODE_TRANSCRIPT_LOCAL_GC` set to true calls
  `setLocalGcEnabled(true)`. OLD has one read of that name, NEW has two. It is opt-in by env only
  and is set nowhere here (0 hits). What it removes was not traced. Never set it on this box.
- **M1. The fleet's background-job rails were measured against 2.1.284 internals, in the one
  subsystem where 2.1.293 is itself the last fix.** `scripts/handoff-fire.sh:5280-5345` recycles a
  background job by parsing `claude --bg` output (`backgrounded · <short>`), reading
  `<config>/jobs/<short>/state.json` (`cwd`, `name`, `respawnFlags`), and calling `claude stop`;
  `scripts/limit-recover/lr-upgrade.sh:692-700,1305-1312` reads `<cfg>/sessions/<pid>.json` and the
  detach behavior "read off the 2.1.284 binary"; `bin/cc-queue`, `bin/cc-reaper`,
  `hooks/lib/session-kind.sh`, `hooks/mailbox-drain.sh` also touch it. Static anchors are
  unchanged (measured OLD and NEW): the `backgrounded` line is byte-identical in shape,
  `respawnFlags` 60 and 60, `--bg-pty-host` 4 and 4, `CLAUDE_JOB_DIR` 42 and 42. Behavior did
  change: L758 (resume of a hosted session now opens it and delivers the prompt), L558, L313,
  L275, and three fixes in 2.1.293 itself (L10, L30, L31). L16 is a gain: `claude stop` could sign
  an account out near login expiry on 2.1.284. Rate this CAUTION, not NEUTRAL.

## What the gate does not cover and a human or probe must re-verify before activation

Each item names the exact command or file. "293" is `~/.claude-293/node_modules/.bin/claude`.

1. **Per-agent budget switch (V02).** Add `"CLAUDE_CODE_TOTAL_TOKENS_REMINDER": "infinite"` to the
   `env` block the fleet's settings deploy writes (the env name exists in 2.1.284 too: 9 hits; its
   accepted values on 2.1.284 were not read). Then force the feature on and show the switch wins:
   `CLAUDE_CODE_RIPPLING_TULIP=100000 CLAUDE_CODE_STREAMED_BUMBLEBEE=true CLAUDE_CODE_TOTAL_TOKENS_REMINDER=infinite CLAUDE_CONFIG_DIR=~/.claude-next 293 -p --model claude-opus-5-5 "launch one general-purpose sub-agent that reads a file and reports any text it was shown about tokens left"`.
   Expect "Infinite tokens left" and no "budget of" sentence. Run it once without the third
   variable as the control (expect the 100,000 countdown), and once with `--model claude-fable-5-1`.
   Standing check afterward:
   `grep -c -E 'tengu_rippling_tulip|tengu_streamed_bumblebee' ~/.claude-next/.claude.json ~/.claude-secondary/.claude.json ~/.claude-tertiary/.claude.json ~/.claude-quaternary/.claude.json`.
2. **Resume behind the symlinked `projects` (W1).** `ls -ld ~/.claude-next/projects`. In a scratch
   directory: `CLAUDE_CONFIG_DIR=~/.claude-next 293 -p --output-format json "reply ok"`, take
   `session_id`, then `CLAUDE_CONFIG_DIR=~/.claude-next 293 -p --output-format json --resume <id> "reply ok2"`.
   A "No conversation found" is a blocker for account 1. Then resume one 2.1.284-born session
   through `scripts/limit-recover/lr-upgrade.sh` and confirm thinking survives (L399).
3. **`next3` login, then entitlement (V01).** After the operator logs the account in:
   `scripts/cc-upgrade-gate.sh ~/.claude-293/node_modules/.bin/claude claude-haiku-5-5 next3`.
4. **What `model: "haiku"` serves and at what effort (V03, V04).** From an Opus 5.5 lead on 293,
   spawn one Explore subagent with `model: "haiku"`; read the model id from its transcript
   (`jq -r 'select(.message.model) | .message.model' <subagent>.jsonl | sort | uniq -c`) and
   `effort.level` from the SubagentStop payload (A1 cites `hooks/subagent-stop.sh:27`; I did not
   open that file). Repeat from a `claude-x` lead and with an explicit Agent `effort`. If retrieval
   is to stay on Haiku 4.5, the lever is `ANTHROPIC_DEFAULT_HAIKU_MODEL=claude-haiku-4-5` in the
   launcher, not a per-spawn id.
5. **Classifier cost of a Haiku-led session (B-2).**
   `jq '.cachedGrowthBookFeatures.tengu_auto_mode_config.modelByMainModel' ~/.claude-next/.claude.json ~/.claude-secondary/.claude.json`,
   then one `293 -p --model claude-haiku-5-5 --permission-mode auto` run with a command no allow
   rule covers; read the classifier's usage from the debug log, since `modelUsage` did not show it.
6. **A Write and an Edit in `-p` under auto (V25, V43, holds landmine "Write may overwrite an unread
   file").** Gate #3 and #11 run Bash only. In a scratch git repo:
   `CLAUDE_CONFIG_DIR=~/.claude-next 293 -p --permission-mode auto --output-format json "Use the Write tool to create probe.txt containing OK"`;
   check the file, `permission_denials`, and that `hooks/backup-before-write.sh` logged a fire.
7. **Rewriting hooks under the new rule order (V28).** One command through each of
   `hooks/qos-rewrite.sh`, `hooks/coldcompile-admit.sh`, `hooks/curl-gate.py` on 293 under `auto`;
   read `permission_denials` and wall time against the same command on 2.1.284.
8. **Revoked-login readers (V38).** Edit `hooks/stop-failure-marker.sh:583-584` to add
   `*"token revoked"*` and `*"failed to authenticate"*`; change the trigger at
   `docs/plans/MASTER_ACCOUNT_FACTS.md:141-142` to key on `"error":"authentication_failed"`.
9. **Stacked permission prompts (V14, V15).** `bats tests/pane-modal.bats`, then one live pane on
   293 with two stacked asks; confirm the count is on the title row and that
   `pane_modal_reason` (`hooks/lib/pane-modal.sh:160`) returns `tool-permission-modal`.
10. **Background-job rails (M1, V16).** On 293, repeat the measurements in
    `docs/research/bgjob-recycle-2026-10-03/README.md` and
    `docs/research/bg-session-semantics-2026-09-25.md`: `293 --bg "reply ok"` prints
    `backgrounded · <short>`; `jq '.cwd,.name,.respawnFlags' <cfg>/jobs/<short>/state.json`;
    `293 stop <short>` keeps the conversation; `293 --resume <sid>` against a daemon-hosted session
    (L758). Then `scripts/session-lifecycle-safety-gate.sh` and `scripts/reaper-safety-gate.sh`.
11. **`-p` with a live background command (V17, V18).**
    `time 293 -p "run 'sleep 900' with run_in_background true, then reply done"`; expect the stop
    near 600 seconds, not 1800. Compare with `scripts/meter-experiment/run.sh:65,72`.
12. **MCP per scope (V27, V40).** `CLAUDE_CONFIG_DIR=<each account dir> 293 mcp list` against the
    same command on 2.1.284, and once from a project that defines mac-messages or agent-browser.
13. **Prompt cache on resume (V42).** The two-command repro in #99833 on 2.1.284 and on 293 with
    `--model claude-opus-5-5`; compare `cache_read_input_tokens` on the resume.
14. **Cleanup canary (holds landmine, C-1).** A throwaway config dir holding one symlinked file, one
    293 session start and end, then `ls -l`. Also `grep -rn CLAUDE_CODE_TRANSCRIPT_LOCAL_GC ~/.zshrc ~/.claude/settings.json bin scripts hooks lib` must stay empty.
15. **Bash forms that now ask (V30).** One Explore-style subagent on 293 running `rg` with an
    unquoted glob and one `ps` form; count classifier calls.
16. **Spawn depth with a fork (V10, V11).** Gate #15 is a static read. In an interactive 293
    session, ask a subagent to spawn another and confirm "Subagent nesting limit reached (depth 1 of 1)".

## Limits of this note

- Issue bodies were read to 2,600-3,800 characters; later detail may be missing.
- Minified code was read at the quoted offsets only. "Inferred" rows (V14, V21, and the scope of
  the budget in V02) rest on code paths I did not trace end to end.
- Server flag values are snapshots of `.claude.json` read shortly before 23:02Z (`date -u` after
  the reads); they can change without a binary change, which is the point of V02 and B-3.
- A-1 compares against 2.1.284 on the changelog's wording ("instead of ending after 200 calls")
  and the OLD cap function at @184441991; I did not read OLD's consume logic.
- I did not open `census-haiku.md`, the card or docs fact files, or `hooks/subagent-stop.sh`.

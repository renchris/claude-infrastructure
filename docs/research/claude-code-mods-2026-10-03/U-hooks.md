# U — Existing-hook inventory vs Claude Code mods

Repo `/Users/chrisren/Development/.worktrees/wt-cc-231454-86805` was read-only throughout. The per-hook table (every registered script) is at `/tmp/mods-research/U-hooks-inventory.tsv`.

## 0. Facts that change the question

- **Mods cannot run on the fleet today.** `~/.claude-284/node_modules/.bin/claude --version` prints `2.1.284` (MEASURED). Mods need 2.1.287 or later (`claude_dev_blog…txt:38`). Nothing below applies until the pin moves.
- **The brief says hooks cannot rewrite. That is false here.** `qos-rewrite.sh:122` and `coldcompile-admit.sh:178` already emit `updatedInput`. `bash-output-offload.sh:98` emits `updatedToolOutput` (MEASURED by grep). What a mod adds is a **composable** rewrite (see rank 2).
- **The live registrations are not the template.** `~/.claude/settings.json` has 108 hook registrations. `settings-templates/settings.example.json` has 78 (MEASURED, jq). The live file splits as PreToolUse 20, SessionStart 18, PostToolUse 15, Stop 13, UserPromptSubmit 7, SessionEnd 7, and 28 more across 15 other events. Live-only, not in repo: `net-context-stamp.sh`, `web-entrypoint-ladder.sh`; `subagent-stop.sh` is template-only.
- **Many hooks sit on events mods do not have.** The blog lists the mod events as "tool calls, the prompt as submitted, turns starting and finishing, the session starting and ending, slash commands, and ui.render" (`…txt:71`). It names no mod event for WorktreeCreate, TeammateIdle, TaskCompleted, PreCompact/PostCompact, Permission{Request,Denied}, Notification, StopFailure, FileChanged, CwdChanged, ConfigChange, InstructionsLoaded or PostToolBatch. That covers 25 live registrations (MEASURED count from the event tally). Whether the `.claude-plugin/types/` of 2.1.287+ declare more is UNVERIFIED (no such binary here).
- **Two semantics are unverified.** (a) The blog documents a deny answer (`{ deny }`, `…txt:69,446`) but no permission **allow**. (b) It does not show a `turn.complete` hook forcing the turn to continue, which is what a Stop `decision:block` does. Eleven hooks use `decision:block` (MEASURED, grep). Any rank below marked "conditional" depends on (b).

## 1. Measured hook overhead

| Figure | Value | Source |
|---|---|---|
| PreToolUse/Bash, 7 hooks | **397 ms serial, 179 ms burst wall (p95 233)** | `docs/research/memory-econ-rearchitecture-2026-08-10/hook-forks.md:96` |
| Per hook | validate-bash 174 ms/23 execs · qos-rewrite 126/15 · git-worktree-guard 49 · keychain 34 · curl-gate-scope 28 · ship-rail 22 · rm-safe 21 | same file :112-120 |
| PostToolUse Bash + match-all | 331 ms serial / 151 ms wall · waiting-recycle 127 · mailbox-drain 75 · log-bash 46 · teammate-checkpoint 36 (p95 656) | :97, :128-132 |
| Whole Bash call | **330 ms latency, 728 ms CPU, ~86 processes** | :221 |
| Share of turn time | **1.2%** (5.1 s of hook wall in a 443 s median turn) | :248 |
| Fleet CPU | 0.197 cores mean (2.0%), about 0.7 cores at peak | :226-234 |
| One-process collapse | **measured worse:** 174 ms serial vs ~180 ms dispatcher; validate-bash got slower when sourced, 94→142 ms | `hooks/hook-chain.sh:27-31,40-42` |
| Floors | bash -c : 7.35 ms · jq 9.29 · python3 31.45; about 2–4 ms marginal per exec | `docs/plans/HOOK_CHAIN_COST.md:65-77` |
| Trivial `*` hook | p50 2.85 ms | `docs/research/oversight-at-scale-2026-08-19.md:133` |
| Where the cost is | ~81% is external commands **inside** the hooks, not the hook fork | `docs/research/function-hooks-91870-2026-09-03.md:160` |
| Stop group | 2,202 ms serial / 934 ms wall | `hook-forks.md:99` |
| Stop timeout | session-continue took 5,479 ms against a 5,000 ms budget; 23 Stop `hook_cancelled` | `docs/research/context-ceiling-397428c4-2026-09-22.md:177` |

**Bash PreToolUse count today is 11 per Bash call** (MEASURED from live settings.json): 10 hooks match `Bash` and `research-block.sh` matches `*`. The 7 measured above sum to 397 ms serial. **Four have no measurement:** smart-bash-allowlist, coldcompile-admit, pr-gate and research-block. ESTIMATED from the floors: research-block's fast path ("one jq parse", `research-block.sh:12`) is about 3–10 ms. Applying hook-forks' 2.2× recovery factor, the 11-hook wall is probably 200–260 ms. I have not measured that.

**What this means for mods (INFERRED):** latency is a weak reason to build a mod. The repo has already measured the whole hook layer at 1.2% of turn time and called it third-order. It also built an in-process collapse and measured it as a loss. The only large single target is validate-bash, a 2,306-line safety gate; porting it to save about 170 ms per call is not worth the risk.

## 2. Ranked: where a mod does the job strictly better

Capability codes: **AUTH** = authoritative session state the hook now infers · **STATE** = in-process state across events · **REWRITE** = composable middleware rewrite · **UI** = drawing · **LAT** = hot-path latency.

| # | Hook (event) | Winning capability | Evidence |
|---|---|---|---|
| 1 | `waiting-recycle.sh` (PostToolUse Bash) | **AUTH**: `$.session.usage()` gives context fill "the same figures as the status line", and the call is free (`…txt:182`) | It reads fill from the statusline's telemetry file. That file "renders ZERO times while a session sits inside one long operation", so the hook falls back to stale lower bounds plus transcript-age checks (`waiting-recycle.sh:896-913`). Also 127 ms on every Bash call, with no timeout set (`hook-forks.md:128`). |
| 2 | `qos-rewrite.sh` + `coldcompile-admit.sh` (PreToolUse Bash) | **REWRITE**: `next({...e, command})` chains, so two rewrites compose in a defined order (`…txt:68`) | Today they are kept disjoint on purpose, because two non-empty `updatedInput` emitters "have no documented resolution… order and chaining are undocumented" (`coldcompile-admit.sh:33-40`). Also qos-rewrite costs 126 ms. |
| 3 | `boundary-handoff.sh` (Stop) | **AUTH + STATE**: usage per turn, burn history in `$.state` (the Token Weather pattern, `…txt:203-215`) | Same stale-telemetry assumption as #1, named as the sibling at `waiting-recycle.sh:898-899`. Velocity samples come from `lib/context-econ.sh`. |
| 4 | `cache-expiry-tracker.sh` (Stop) + `cache-expiry-warning.sh` (UPS) | **STATE + UI**: a timestamp in `$.state` and a countdown band before the operator types | Today two processes hand off through a file, and the warning only fires *after* the prompt is submitted (headers, `cache-expiry-*.sh:1-4`). |
| 5 | `research-precognition-nudge.sh` (UPS) → `research-block.sh` (PreToolUse `*`) | **STATE**: the turn label stays in memory from `prompt.submit` to `tool.call` | The label is written to disk for research-block (`research-precognition-nudge.sh:14`). research-block re-resolves it on every tool call (`research-block.sh:12`). |
| 6 | `agent-teams-enforce.sh` (PreToolUse Agent) | **AUTH**: `e.agentId` marks subagent turns (`…txt:196,494`) | It derives depth from the *shape* of `transcript_path` and says this "cannot be answered from disk today" (`agent-teams-enforce.sh:343-350`). It timed out at 5 s (`docs/research/sonnet55-utilization-2026-09-28/notes/probe-teammate-classifier.md:39`). |
| 7 | `anti-deference-nudge.sh` (Stop) — conditional | **AUTH**: `turn.complete` carries the answer (`answer: "ok"` in the test, `…txt:371`) | It streams the transcript to find the last assistant text. The older tail-1 read had a "74% no-assistant-text blind rate" (`anti-deference-nudge.sh:156-161`). |
| 8 | `completion-assert.sh` (Stop) — conditional | **AUTH**, same as #7 | 1,403 lines. Transcript and pane reads (grep counts 2 and 3). |
| 9 | `dispatch-assert.sh`, `handoff-claim-assert.sh` (Stop) — conditional | **AUTH**, same as #7 | Both parse the transcript for the final message. |
| 10 | `operator-readout.sh` (Stop) | **UI**: a persistent Pane or AbovePrompt list of operator steps, instead of a systemMessage that scrolls away | 1,887 lines. Headless is not a render surface (`function-hooks-91870…md:158`), so the text path has to stay as well. |
| 11 | `session-continue.sh` (Stop) — conditional | **STATE**: the loop sentinel and counters live in memory, not files | It went over its 5 s budget (5,479 ms). The script has 27 stamp/counter references (MEASURED, grep). |
| 12 | `mailbox-drain.sh` (UPS/PostToolUse `*`/SessionStart) | **STATE + UI**: drained ids in `$.state`, an unread-count band, and an `/inbox` command or tool via `$.command.register` (`…txt:487`) | 75 ms on *every* tool call (`hook-forks.md:131`). Its SessionStart path once blocked turn 1 for 5,134 ms (`docs/research/startup-2026-08-16/COLD_START_100P.md:342`). |
| 13 | `accounts-board.sh` (SessionStart) | **UI**: a live band or `$.ui.status`, refreshed each turn from `$.session.usage().rateLimits` | It prints once at start and is stale by turn 2. INFERRED: other accounts' limits still need `$.process.run`. |
| 14 | `teammate-checkpoint.sh` (PostToolUse `*` + Stop) | **STATE + LAT**: an in-memory every-Nth counter, so no fork on most tool calls | 36 ms, p95 656 ms, on every tool call (`hook-forks.md:132`). The git-plumbing work itself does not change. |
| 15 | `memory-nudge.sh` (UPS) | **STATE**: the prompt counter goes in `$.state` | Today it keeps a counter in a file plus 5 transcript references (MEASURED, grep). |

Also minor: `backup-before-write.sh` (before-image replay pane), `bash-output-offload.sh` (in-process result rewrite, marginal), `frontier-status.sh` (`$.ui.status`).

**Scope caveats (INFERRED):** Agent Teams teammates are separate `claude` processes, so each would load the plugin, which means installing it in all 4 `CLAUDE_CONFIG_DIR`s through the config mirror. Mod UI does nothing in headless `handoff-fire.sh` sessions. `session.start` exposes `isInteractive` (`…txt:361`), so a mod can at least detect that case.

## 3. Hooks that should stay shell

**Safety and permission gates.** These are smart-bash-allowlist, curl-gate-scope, validate-bash, git-worktree-guard, keychain-guard, rm-safe-allowlist, ship-rail-push-allow, check-edit-boundary, workflow-script-edit-allow, enforce-email-formatting.py, frontier-spawn-gate and pr-gate. Reasons:
1. The blog itself says a Bash mod guard "is a safety net, not a permission system… Use permission rules for a hard block" (`…txt:460`).
2. Four of them return `permissionDecision: allow` (`rm-safe-allowlist.sh:141`, `ship-rail-push-allow.sh:80`, …), and no mod allow answer is documented.
3. Fail-open versus fail-closed was explicitly undecided in the design (`function-hooks-91870…md:27`).
4. A mod is a plugin that hot-reloads or can be disabled. The settings.json gate cannot silently disappear, and `hook-chain.sh:70-72` sets a "no skip mode" law for exactly these gates.

**Hooks that must outlive the session or act on other processes.** These are lead-crash-watchdog (spawns a detached daemon that must survive the lead dying), mailbox-wake-arm (14,400 s timeout, a long-lived watcher; a mod hook gets 10 s of its own time per dispatch, `…txt:453`), session-register, session-deregister, live-session-registry, session-end, stop-failure-marker, cc-permission-beacon and teammate-auto-shutdown. Their consumers are the reaper, the supervisor and the pane registry, all outside the session. A mod adds nothing there and dies with the process it is meant to watch.

**Hooks that guard the substrate a mod needs.** pre-session-validate rolls back a broken CC version, so it must run on binaries that may predate or break mods. config-mirror-assert repairs the very config dir a plugin would load from.

**Hooks that reach a human off-terminal.** notify.sh and push-critical.sh (Pushover). `$.ui.toast` only shows in the terminal, which nobody is watching in unattended runs.

**Hooks on events mods lack (no-event).** worktree-setup, task-quality-gate, dod-persist on PreCompact, post-compact, permission-denied, file-changed, cwd-changed, config-change, instructions-loaded, post-tool-batch and the inline `date` PreCompact loggers.

**Deliberately env-only.** cc-unattended-ask-guard decides "ONLY on the env var, never on stdin" (`cc-unattended-ask-guard.sh:13-15`).

**Neutral** (either works): log-bash, session-beat, plan-*, session-index-*, setup-*-symlinks, handed-off-session-guard and the rest marked NEUTRAL in the TSV.

## 4. Bottom line (INFERRED)

One mod would deliver most of the value. It would hold `$.session.usage()` readings and turn/agent state in `$.state`, and give waiting-recycle, boundary-handoff and the Stop asserts **authoritative** context fill, the turn's answer text and `agentId`. Today these hooks scrape the transcript and statusline telemetry, and that is the documented failure mode. That mod would also hold the cross-event pairs: cache TTL, research label and prompt counters. The second-best target is the composable rewrite chain for qos-rewrite and coldcompile-admit. Latency alone does not justify a port. All of this is gated on moving the 2.1.284 pin and on confirming the deny/allow/continue semantics from a 2.1.287+ `.claude-plugin/types/`.

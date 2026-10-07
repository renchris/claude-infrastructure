# Claude Code 2.1.285 to 2.1.293, axis 2: background subagents, Dynamic Workflows, model and cost defaults

Source: `pack/cc-changelog.md` lines 3-815, read in full (not grepped). Line numbers below are
lines of that file. Read-only audit; no binary was run. No 2.1.284, 2.1.291 or 2.1.293 binary was
found at `~/.local/share/claude/versions/` or `~/.claude-versions/` (measured: `ls`), so nothing
here is a binary probe; every claim is changelog text unless marked "repo".

Verdict on this axis: **no BLOCKER in 2.1.293.** Nine CAUTIONs, listed first in the table.

## Rated changes

| Version | Line | Change | Rating | Why it matters here | What to re-verify |
|---|---|---|---|---|---|
| 2.1.293 | 5 | Added Claude Haiku 5.5 (`claude-haiku-5-5`), "now the default Haiku model on the Anthropic API", 1M context, $0.10/$0.50 per Mtok, $0.50/$2.50 for prompts over 100K | CAUTION (and the reason to upgrade) | 2.1.293 is the first version in the band that names the id; no line in 2.1.285-2.1.292 mentions Haiku. "Default Haiku model" is the same wording 2.1.284 used when the `sonnet` alias moved (line 818), so read it as: the `haiku` alias now resolves to Haiku 5.5. Every `model: "haiku"` Explore spawn (repo: `skills/research-subagents/SKILL.md:610-612`, measured there as `claude-haiku-4-5` on 2.1.280) and the `haiku_latest` fallback in `scripts/research-kit/router.py:311` change model silently on the binary flip. Hard-pinned ids stay on 4.5: `hooks/model-permission-decider.py:129`, `scripts/headless-precondition-probe.sh:26`, `scripts/handoff-fire.sh:13816,17071`. Prompts over 100K tokens cost 5x, which matters for a 1M-context extraction slot. | On 2.1.293, spawn Explore with `model: "haiku"` and read the model id from the subagent transcript. Confirm which model the small/fast background calls use (the changelog does not say). Check `hooks/lib/read-before-write-parity.sh:168` (`RBW_ENFORCED_MODELS` lists `claude-haiku-4-5`, not 5.5) before giving Haiku 5.5 a code-writing role. |
| 2.1.286 | 596 | When the API refuses the model a default or alias resolves to, Claude Code retries once on the previous model of the same tier | CAUTION | An account that cannot use Haiku 5.5 will run Haiku 4.5 under the `haiku` alias with no failure. Any Haiku 5.5 role evaluation can be measuring 4.5 without knowing. Same family as held issue #97687 (silent older-opus fallback). | Read the served model id per run in every Haiku 5.5 trial; pin `claude-haiku-5-5` by id, not alias, where the role depends on 5.5. Test on each Max account. |
| 2.1.285 / 2.1.288 | 763 / 461 | 285: background Bash and PowerShell commands stop after a time limit (their `timeout` with `run_in_background`, default 30 min, max 2 h). 288: the limit applies "only in unattended sessions (`-p`, Agent SDK, CI, cloud); terminal, desktop app and VS Code sessions have no limit" | CAUTION for `claude -p`; cleared for interactive panes | State in 2.1.293 per the text (no later line changes it): **capped** = `claude -p`, Agent SDK, CI, cloud sessions. **Not capped** = terminal (interactive pane), desktop app, VS Code. The 3300 s `cc-await-ping` arm in an interactive pane is not cut. In a `-p` session it is stopped at 1800 s by default unless the call passes a `timeout` of at least 3,300,000 ms (allowed, under the 2 h max). Not stated: sessions started with `claude --bg` or run by the daemon, and subagents inside an interactive session. | In a `-p` session on 2.1.293, arm `cc-await-ping --timeout 3300` in the background with and without an explicit Bash `timeout`; record when it is stopped and the notice text. Repeat once in a `--bg` session. |
| 2.1.292 | 81 | One-shot `claude -p` and Agent SDK runs used to stop a background command 5 seconds after the final result and drop a scheduled wakeup; "both are now waited for" | CAUTION | Combined with line 461: a `-p` run that leaves a background command running (a `cc-await-ping` watcher, a dev server) no longer exits 5 s after its result. It waits for the command, up to the 30 min default cap or 2 h max. Callers with a short wall clock will kill it instead (repo: `scripts/meter-experiment/run.sh:65,72` use `timeout 1200` and `300`; `handoff-fire.sh:13853` uses a perl alarm). | Time a `-p` run that starts `sleep 600` in the background on 2.1.293. Make headless prompts not arm `cc-await-ping`, or stop it before the final message. |
| 2.1.290 | 317 | An in-process teammate's `agent_id` in Agent results is now its agent ID (`name@team` moves to `teammate_id`); TeammateIdle hooks no longer fire from its subagents or forks | CAUTION | Repo: five hooks handle TeammateIdle (`teammate-auto-shutdown.sh`, `teammate-checkpoint.sh`, `session-continue.sh`, `completion-assert.sh`, `lib/cc-interactive.sh`) and `hooks/*.sh` has 21 `agent_id` references (measured: `grep -c`). Anything that parsed `agent_id` as `name@team` breaks. | Run the teammate hook tests against a 2.1.293 payload; capture one live Agent result and one TeammateIdle payload. (Shared with the hooks axis.) |
| 2.1.290 | 321 | Interactive session WebSearch budget now refills over time (100 calls/hour; `CLAUDE_CODE_WEB_SEARCH_REFILLS_PER_HOUR`, 0 turns it off) instead of ending after 200 calls | CAUTION | Repo: `~/.claude/settings.json` sets `CLAUDE_CODE_MAX_WEB_SEARCHES_PER_SESSION=1000`. The changelog does not say how the two variables interact. A research lead that bursts past the bucket may be throttled where it was not before. | On 2.1.293, check whether the 1000 setting still applies, and what a research fan-out sees when the bucket is empty. |
| 2.1.290 | 318 | Background sessions waiting on a scheduled wakeup (`/loop`) are "left running through updates and low memory" instead of being restarted or shut down | CAUTION | This removes a memory-pressure relief valve on a box with four memory-storm kernel panics on record (holds.md). Only bites if the fleet runs `/loop` in background sessions. | Count `/loop` background sessions in normal use; if any, watch memory under a fan-out. |
| 2.1.293 | 43 | Reverted the 2.1.290 fix (line 245) for cloud sessions staying asleep after a container restart lost a pending `/loop` wakeup or scheduled task; "the session stays asleep" | CAUTION | Cloud wakeups are less reliable in 2.1.293 than in 2.1.290-2.1.292. The fleet's only cloud dependency is the `claude -p ... --cloud <id>` send in `bin/cc-notify` (repo: line 120); a send to a sleeping cloud session is a queue ack, not a delivery. | Run the `cc-notify --cloud` send on 2.1.293 and confirm the flag still exists (the script notes it is version-dependent). |
| 2.1.292 | 70 | Subagent definitions with `permissionMode: auto` no longer enter auto mode when auto mode is unavailable, including "a model that doesn't support it" | CAUTION (low) | Repo: no `agents/*.md` sets `permissionMode` (measured: `grep`), so no definition changes behavior. It matters if a Haiku 5.5 teammate is expected to run in auto mode: the changelog does not say whether Haiku 5.5 supports auto mode. | Start one Haiku 5.5 subagent under an auto-mode lead and see whether it prompts. |
| 2.1.292 | 65 | Added an `effort` parameter to the Agent tool | IMPROVEMENT | This is what makes "Haiku 5.5 at effort X per role" expressible per spawn. The launcher comment "no per-spawn effort (GH #25591)" at `~/.zshrc:196` is now stale. Workflow `agent()` already passes `effort: 'low'` (repo: `scripts/research-kit/workflows/round.workflow.js:46`). | Confirm Haiku 5.5 accepts an effort value (the skill table at `SKILL.md:446` says Haiku 4.5 has none), and that PreToolUse(Agent) hooks pass an input with the new key. |
| 2.1.290 | 250 | Fixed background agents failing with "Agent stalled" and Workflow tool subagents restarting from their prompt when a Mac woke from sleep | IMPROVEMENT | Direct hit for a Mac fleet: a restarted Workflow subagent re-spends its whole prompt. | Sleep and wake the Mac during a 3-agent workflow on 2.1.293. |
| 2.1.286 | 617 | Fixed Workflow tool subagents being restarted from their original prompt when a connection stalled for a few minutes mid-response | IMPROVEMENT | Same failure, different trigger; first fix of the cluster. | Covered by the test above. |
| 2.1.285 | 707 | Fixed a failed `agent()`, `parallel()` or `pipeline()` call that a workflow script awaits later, or not at all, ending a background session as an unhandled rejection | IMPROVEMENT | One failed worker no longer kills the run. | None beyond a normal workflow smoke run. |
| 2.1.290 | 184 | Fixed headless `--json-schema` runs exiting non-zero with `is_error: true` on a `success` result when the connection dropped after the structured output was delivered | IMPROVEMENT | Fewer false failures in schema-returning headless workers. | None. |
| 2.1.290 | 178 | Fixed resumed subagents and teammates losing earlier thinking and prompt cache after receiving a message mid-run | IMPROVEMENT | Quota: a lost prompt cache is a full re-write of the worker's context. | None. |
| 2.1.290 | 272 | Fixed background subagents losing write and Bash access in their worktree after the main session enters or exits a different worktree | IMPROVEMENT | The fleet is worktree-heavy. | None. |
| 2.1.285 | 754 / 700 | Subagents in auto mode end as soon as they hand their report back; background subagents in auto mode no longer prompt a second redundant reply | IMPROVEMENT | Fewer wasted turns per spawn, at N of about 10 per fan-out. | Confirm a subagent that reports early is not expected to keep working afterward. |
| 2.1.286 | 616 / 615 | Worktree-isolated subagents no longer load the project CLAUDE.md twice; foreground subagents no longer miss the task tools | IMPROVEMENT | Token savings per worktree subagent. | None. |
| 2.1.288 | 394 / 420 / 425 | Non-interactive sessions and subagents continue from a partial response after a mid-response timeout; unattended retry gives up after three timeouts; headless sessions no longer ignore SIGTERM sent with SIGCONT | IMPROVEMENT | Headless runs fail less and stop when `timeout` tells them to. | None. |
| 2.1.292 | 88 / 123 | Usage limit alert no longer repeats once per background agent; `-p` first turn no longer waits for HTTP/SSE MCP `resources/list` | IMPROVEMENT | Quota-bound fleet with many headless starts. | None. |
| 2.1.287 | 496 | Fixed `-p` and SDK sessions repeating a model fallback on every later message after a mid-reply model switch | IMPROVEMENT | Model routing in headless runs. | None. |
| 2.1.293 | 13 / 14 / 16 | Claude no longer told to use `SendMessage` where it was removed; subagents no longer told a tool is disabled session-wide; `claude logs/stop/kill/rm` and `claude daemon status/stop/uninstall` no longer sign you out near login expiry | IMPROVEMENT | Subagent prompt accuracy and daemon reliability. | None. |
| 2.1.288 | 462 | Client-side auto mode classifier ignores an `ANTHROPIC_DEFAULT_SONNET_MODEL` pin naming Sonnet 5.5 or Opus 5.5 and uses Sonnet 5 | NEUTRAL | The fleet pins auto mode; the classifier draws Sonnet 5 quota whatever the pin says. No such pin in `settings.json` env (measured). | None. |
| 2.1.287 | 492 | Picking Fable in `/model` now saves an alias that follows the newest Fable | NEUTRAL | The launcher pins by id. | None. |
| 2.1.287 | 479-480 | Claude Mods; "You should know" side agent (opt in with `/plugin enable`) | NEUTRAL | Off unless enabled; a side agent would be extra quota. | Confirm it is not enabled. |
| 2.1.289 / 2.1.292 | 373 / 69 | `agent.spawn` mod hook now fires for teammates (289) and workflow agents (292) | NEUTRAL | Lets a mod refuse a spawn. Loosens no cap. | None unless mods are adopted. |
| 2.1.285 | 685 / 698 | In `-p` with `CLAUDE_CODE_FORK_SUBAGENT=1`, a subagent's own Agent call runs in the foreground; fork subagents keep the parent's plan or `dontAsk` mode | NEUTRAL | Line 685 confirms a fork subagent can still call Agent; it changes how, not whether. | See #85264 below. |
| 2.1.286 | 642 | `--bare` starts no background tasks; a shell command that hits its timeout stops instead of moving to the background | NEUTRAL | Repo: no script passes `--bare` (measured: `grep`). | None. |
| 2.1.285 | 764 | Code Review and `/ultrareview` run when `disableWorkflows` is on | NEUTRAL | `disableWorkflows` is unset (measured). | None. |
| 2.1.293 | 6 | `agentType` added to the `subagentStatusLine` payload | NEUTRAL | No `subagentStatusLine` in `settings.json` (measured: 0 hits). | None. |
| 2.1.292 | 139 | Agent names limited to 256 characters | NEUTRAL | No fleet agent name approaches that. | None. |

Not found anywhere in lines 3-815: any change to the Explore subagent's model, to
background-by-default for subagents, to Workflow concurrency, or to a per-agent token budget.

## holds.md items answered

**Held-open issues (changelog evidence only; `gh issue view` was not run, so issue state is unverified).**

- **#84974, spawn depth off by one / a restored spawn ceiling:** left open. Grep of the slice for
  restored / limit / cap / ceiling / depth / budget returns 40 lines (measured: `awk 'NR>=3&&NR<=815' | grep -ciE`);
  none restores a subagent-per-session cap or changes spawn depth. Lines 166 and 502 use "ceiling"
  for organization tool-approval ceilings, not spawns. Per the rule in holds.md, the band is
  silent, so the fleet is **still uncapped**: `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1` and
  `CLAUDE_CODE_WORKFLOW_MAX_CONCURRENT_AGENTS=12` remain the only bounds. Gate #15 must be rerun.
- **#85264, fork subagents spawn nested agents:** left open. Line 685 (2.1.285) makes a fork
  subagent's Agent call run in the foreground under `-p`; line 698 keeps a fork in its parent's
  permission mode. Neither stops the nested spawn.
- **#85015, two background workers reach 46 GiB:** left open. No line names it. Memory fixes in the
  band are elsewhere: HTTP MCP leak (line 9), unbounded memory on a large HTTP MCP response
  (line 257), large MCP results (line 554). Line 318 (2.1.290) pushes the other way: `/loop`
  background sessions are no longer shut down under low memory.
- **#84224 / #85154, auto-updater:** not this axis. Line 436 (2.1.288) is the only related line.
- **#85497 / #85764, cross-session inbox race:** left open. Lines 416 (2.1.288), 90 (2.1.292) and
  274 (2.1.290) fix delivery notices and `--restricted`; no line mentions the bind race. The
  subsystem is still being patched in three of nine releases, so keep the "assess, do not adopt" stance.
- **#97687, opus subagent falls back to an older opus:** left open, and line 596 (2.1.286) makes
  same-tier fallback a general rule for any refused default or alias.
- **#97763, subagent `output_tokens` undercount:** left open; no line mentions it.

**Carried cautions.**

- **`sonnet` alias moved in 2.1.284, pin by id:** still true, and the `haiku` alias now moves the
  same way in 2.1.293 (line 5). Repo: `agents/deep-research-sonnet.md:4` and
  `agents/research-decomposition-critic.md:4` use `model: sonnet`; `agents/deep-research.md:4` and
  `agents/frontier-derivation.md:5` use `model: opus`.
- **`ultracode` no longer forces xhigh:** no line in the band changes it.

**Pre-audit of the band.**

- **"Never 2.1.285-2.1.287" (background Bash cap):** confirmed by lines 763 and 461. In 2.1.293 the
  cap is gone for interactive panes and remains for `-p`, Agent SDK, CI and cloud.
- **"Nothing below 2.1.291":** confirmed by line 160. 2.1.293 is above it.
- **Per-agent token budget ("has a budget of", upstream #99932):** left open and **unprobed**. No
  line in 2.1.285-2.1.293 mentions a per-agent or Workflow token budget. No candidate binary was
  on disk to run `strings` against. This must be probed on the 2.1.293 binary before any Haiku 5.5
  worker is sized, because a silent budget would truncate long extraction or synthesis runs.
- **Cloud rows:** now written (lines 43, 159, 245, 22/191, 103-106). Net: 2.1.293 fixes the 2.1.290
  dropped-permission-answer regression and withdraws the 2.1.290 wakeup fix.
- **"Shared agents is not a feature":** confirmed. Lines 373 and 69 only extend the `agent.spawn`
  mod hook. The suspected bypass of PreToolUse(Agent) budgets by a mod's `$.agent.spawn` is not
  addressed; keep the ban.

**Standing landmines.**

- **Default model flip:** none in the band for a pinned lead. Bare teammate spawns: the `haiku`
  alias moved (line 5).
- **Explore model (lead's model, capped at opus):** left open. No line touches it. Keep
  `model: "haiku"` on retrieval spawns; after the upgrade that pin buys Haiku 5.5.
- **Background-daemon regression window:** see clusters 3 and 4 below; 2.1.293 itself carries
  daemon and backgrounding fixes, so it is not yet a settled floor.
- **Subagent-per-session cap removed (2.1.224):** not restored. Still uncapped.
- **Native cross-session SendMessage/ListAgents:** still churning (lines 416, 90, 13).
- **Effort override:** line 65 adds per-spawn effort; lines 199 and 563 keep the current effort
  across automatic model switches. No leader-inherit change stated.

## Regression clusters

| # | Cluster | Fixes in the band | Last fix | Is 2.1.293 after it? |
|---|---|---|---|---|
| 1 | Background Bash time limit | Introduced 2.1.285 (763); narrowed 2.1.288 (461); `-p` now waits for background commands 2.1.292 (81) | 2.1.292 | Yes, by one release. Behavior for `-p` changed twice in eight releases; re-verify. |
| 2 | Workflow subagents restarting from their prompt | 2.1.286 (617, stalled connection); 2.1.290 (250, Mac wake); 2.1.285 (707, unhandled rejection) | 2.1.290 | Yes, by three releases. |
| 3 | Background sessions, `←` hand-off, scheduled wakeups | 2.1.290 (183, 275, 313, 318); 2.1.292 (83, 84); 2.1.293 (10, 30, 31) | 2.1.293 | No margin: 2.1.293 is the last fix. Treat `←` backgrounding and `/loop` in background sessions as unsettled. |
| 4 | Daemon and `claude agents` control path | 2.1.290 (192, 223, 225, 234, 235, 237, 308); 2.1.293 (16, 29) | 2.1.293 | No margin. Line 237 says its fix "takes effect from the upgrade after this one". |
| 5 | Cloud sessions | 2.1.285 (705, regression from 2.1.283); 2.1.290 (245, 191); 2.1.291 (159, regression from 2.1.290); 2.1.292 (103-106); 2.1.293 (22 re-fix of 191; 43 revert of 245) | 2.1.293, and it is a revert | No margin, and one fix was withdrawn. Cloud is the least settled subsystem in the band. |
| 6 | Session persistence on quit and resume | 2.1.286 (591); 2.1.288 (396-399); 2.1.291 (160, regression from 2.1.288) | 2.1.291 | Yes, by two releases. (Reported for the floor; owned by another axis.) |
| 7 | Model fallback and alias resolution | 2.1.285 (716, 748); 2.1.286 (596, 598); 2.1.287 (496); 2.1.290 (199) | 2.1.290 | Yes, by three releases, but 2.1.293 adds a new alias target (line 5) on top of it. |
| 8 | Subagent prompt and tool-list correctness | 2.1.286 (615, 616); 2.1.290 (178, 272); 2.1.293 (13, 14) | 2.1.293 | No margin; these are prompt-text fixes with low blast radius. |

Summary of the churn rule on this axis: 2.1.293 sits after the last fix for clusters 1, 2, 6 and 7,
and is itself the last fix for clusters 3, 4, 5 and 8. The fleet's exposure to 3, 4 and 5 is small
(it uses its own mailbox and panes, not `claude agents`, and one cloud send), so none is a blocker.

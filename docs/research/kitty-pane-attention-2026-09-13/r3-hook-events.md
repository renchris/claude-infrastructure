# R3 — Claude Code hook-event surface, measured on the LIVE binary (2026-09-13)

**Method.** Everything below is read out of the running binary
(`/Users/chrisren/.claude-260/node_modules/@anthropic-ai/claude-code/bin/claude.exe`,
Mach-O arm64, `strings -a`) and the live config dirs, cross-checked against
<https://code.claude.com/docs/en/hooks>. Nothing was edited; no hook was registered.
Binary-extracted strings kept at
`…/6d54cd37-…/scratchpad/cc260a.strings` (re-derive: `strings -a -n 6 <claude.exe>`).

## 0. Versions

| | Version | Note |
|---|---|---|
| **This session runs** | **2.1.260** | `ps` on my own PPID → `~/.claude-260/…/bin/claude.exe`; `package.json` = `2.1.260` |
| `/opt/homebrew/bin/claude` | 2.1.269 | newer, NOT what the fleet launches |
| `claude` in an interactive shell | shell **function** (`_cc_route_config_dir` → `_claude_pinned`) | `claude --version` is unreliable; real binaries are `claude-latest` / `$CLAUDE_CODE_EXECPATH` |

`CLAUDE_CODE_EXECPATH=/Users/chrisren/.claude-260/…/claude.exe`, `CLAUDE_CONFIG_DIR=~/.claude-tertiary`.

## 1. The canonical event set — 33 events

Read verbatim from the binary's own event registry (one object literal, function `Ko`):

```
PreToolUse PostToolUse PostToolUseFailure PostToolBatch PermissionDenied
Notification UserPromptSubmit UserPromptExpansion SessionStart SessionEnd
Stop StopFailure SubagentStart SubagentStop PreCompact PostCompact
PreModelSwitch PostModelSwitch PermissionRequest Setup TeammateIdle
TaskCreated TaskCompleted Elicitation ElicitationResult ConfigChange
WorktreeCreate WorktreeRemove InstructionsLoaded CwdChanged FileChanged
DirectoryAdded MessageDisplay
```

🚨 **`SubagentStart` exists and is NOT in this fleet's settings.json.** Neither are
`TaskCreated`, `MessageDisplay`, `PostToolUseFailure`, `UserPromptExpansion`,
`DirectoryAdded`, `Elicitation`, `ElicitationResult`, `PreModelSwitch`,
`PostModelSwitch`, `Setup`, `WorktreeRemove`. 20 of 33 are wired today.

### Common payload (every event) — binary zod schema, authoritative

```jsonc
{ "session_id": "…", "transcript_path": "…", "cwd": "…",
  "hook_event_name": "…",
  "scratchpad_dir": "…",        // optional
  "prompt_id": "…",             // UUID stable from one user prompt until the next
  "permission_mode": "default|plan|acceptEdits|auto|dontAsk|bypassPermissions",
  "agent_id": "…",              // present ONLY inside a subagent
  "agent_type": "…",
  "effort": { "level": "low|medium|high|xhigh|max" } }
```

`agent_id` is the documented discriminator for "am I on the main thread or in a subagent".

⚠️ **The docs page's FIELD NAMES are wrong in ≥6 places; the binary and this repo's
working hooks agree against it.** Docs say `previous_cwd`, `triggered_by`,
`ended_because`, `notification_text`, `prompt_text`, `started_from`, `error_type`.
The binary's zod schemas say `old_cwd`, `trigger`, `reason`, `message`, `prompt`,
`source`, `error` — and `hooks/cwd-changed.sh` parses `.old_cwd`/`.new_cwd`,
`hooks/post-compact.sh` `.trigger`, `hooks/session-end.sh` `.reason`,
`hooks/notify.sh` `.message`. **Trust the binary, not the docs page.**

### Full event table

| Event | Fires when | Payload (beyond common) | Blocking / return | Usable for our 5 states |
|---|---|---|---|---|
| **SessionStart** | session begins. matcher: `startup\|resume\|clear\|compact\|fork` | `source`, `model?`, `session_title?`, `seconds_since_last_response?`, `context_tokens?`, `prompt_cache_likely_expired?`, `estimated_cache_write_usd?` | exit 0 stdout→Claude; exit 2 stderr→user | ✅ **(5) paint initial state** |
| **SessionEnd** | session terminating. matcher: `clear\|resume\|logout\|prompt_input_exit\|other` | `reason` | non-blocking. **All SessionEnd hooks share a 1.5 s total budget** (raised to your `timeout`, cap 60 s) | ✅ **(5) clear the indicator** — but see §6 caveat |
| **UserPromptSubmit** | a prompt is submitted, before processing | `prompt`, `source` ∈ `user\|sdk\|system\|loop_wakeup\|schedule_wakeup\|poll_event`, `session_title?` | **default timeout 30 s** (lowered). stdout→Claude. exit 2 erases the prompt | ✅ **(1) working** — the canonical turn-start |
| **Stop** | right before Claude concludes its response (main thread only) | `stop_hook_active`, `last_assistant_message?`, **`background_tasks[]`**, **`session_crons[]`** | exit 0 = **no effect**. exit 2 / `decision:"block"` / `additionalContext` force another turn | ✅ **(2) idle** — and `background_tasks` separates "done" from "paused on background work" |
| **StopFailure** | turn ended on an API error. matcher: `rate_limit\|overloaded\|authentication_failed\|oauth_org_not_allowed\|account_on_hold\|billing_error\|invalid_request\|model_not_found\|server_error\|max_output_tokens\|unknown` | `error`, `error_details?`, `last_assistant_message?` | **fire-and-forget by contract** — "hook output and exit codes are ignored" | ✅ **(2)/error state** — fires *instead of* Stop, so a Stop-only indicator sticks on "working" forever after a rate limit |
| **Notification** | a notification is sent. matcher = `notification_type` | `message`, `title?`, `notification_type` | exit 0 stdout/stderr **not shown**; cannot block | ✅ **(3) blocked-on-permission** — see §2 |
| **PermissionRequest** | **"when a permission dialog is displayed"**. matcher: tool name | `tool_name`, `tool_input`, `permission_suggestions?` | can return `hookSpecificOutput.decision: allow\|deny`. exit 2 **not honoured**. exit 0 with no JSON ⇒ dialog proceeds untouched | ✅ **(3) — the IMMEDIATE, un-debounced signal** |
| **PermissionDenied** | auto-mode classifier denied a call | `tool_name`, `tool_input`, `tool_use_id`, `reason` | `hookSpecificOutput.retry:true` | ○ auto-mode only |
| **PreToolUse** | before a tool executes. matcher: tool name | `tool_name`, `tool_input`, `tool_use_id` | exit 2 blocks; `permissionDecision` allow/deny/ask/defer | ✅ **(1) working** (highest-frequency heartbeat) |
| **PostToolUse** | after a tool succeeds | `tool_name`, `tool_input`, `tool_response`, `tool_use_id`, `duration_ms?` | exit 2 → stderr to model | ✅ **(1) working** heartbeat |
| **PostToolUseFailure** | after a tool fails | + `error`, `is_interrupt?`, `duration_ms?` | same | ○ |
| **PostToolBatch** | once after every call in a batch resolves, before the next model request | `tool_calls[{tool_name,tool_input,tool_use_id,tool_response}]` | exit 2 **stops the agentic loop** | ✅ **(1) working** — cheapest heartbeat: one fire per model round-trip, not per tool |
| **SubagentStart** | a subagent (Agent tool) is spawned. matcher: `agent_type` | `agent_id`, `agent_type` (docs add `agent_task`) | exit 0 additionalContext→subagent | ✅ **(4) subagent started** |
| **SubagentStop** | right before a subagent concludes | `agent_id`, `agent_type`, `agent_transcript_path`, `stop_hook_active`, `last_assistant_message?`, `background_tasks[]`, `session_crons[]` | exit 2 → keeps the subagent running | ✅ **(4) subagent finished** |
| **TaskCreated** | a task is being created | `task_id`, `task_subject`, `task_description`, `teammate_name`, `team_name` | exit 2 **prevents creation** | ✅ **(4)** — gated behind `CLAUDE_CODE_ENABLE_TODO_TOOLS` |
| **TaskCompleted** | a task is being marked complete | same | exit 2 **prevents completion** | ✅ **(4)** |
| **TeammateIdle** | a teammate is about to go idle | `teammate_name`, `team_name` | exit 2 prevents idle | ✅ **(2) for teammate panes** |
| **PreCompact / PostCompact** | around compaction. matcher `manual\|auto` | `trigger`, `custom_instructions\|compact_summary` | PreCompact exit 2 blocks | ○ |
| **PreModelSwitch / PostModelSwitch** | model changes | `from_model`,`to_model`,`requested_model`,`source`,`context_tokens`, re-cache cost | **30 s** timeout; Pre can block, and a **timed-out Pre hook BLOCKS the switch** | ○ |
| **InstructionsLoaded** | a CLAUDE.md / rule loads. matcher: `session_start\|nested_traversal\|path_glob_match\|include\|compact` | `file_path`, `memory_type`, `load_reason`, `globs?`, `trigger_file_path?`, `parent_file_path?` | **"observability-only, does not support blocking"** | ○ |
| **ConfigChange** | a settings/skills file changes mid-session | `source`, `file_path` | exit 2 blocks the change | ○ |
| **CwdChanged** | after cwd changes | `old_cwd`, `new_cwd`; `CLAUDE_ENV_FILE` set; may return `watchPaths[]` | non-blocking | ○ |
| **FileChanged** | a watched file changes | `file_path`, `event` ∈ `change\|add\|unlink`; may return `watchPaths[]` | non-blocking | ○ |
| **DirectoryAdded** | `/add-dir` or `register_repo_root` | `directory`, `source` | non-blocking | ○ |
| **WorktreeCreate / WorktreeRemove** | worktree lifecycle | `name` / `worktree_path` | **any non-zero exit ABORTS the operation** | ○ |
| **MessageDisplay** | while assistant text is displayed | `turn_id`, `message_id`, `index`, `final`, `delta` | **10 s** timeout; may return `displayContent` to replace the delta | ⚠ finest-grained "working" tick, but fires per delta — too hot for a per-fire shell-out |
| **Elicitation / ElicitationResult** | MCP asks for user input / user answers | `mcp_server_name`, `message`, `requested_schema` / `action`, `content`, `mode`, `elicitation_id` | can accept/decline | ✅ **(3)** for MCP-originated blocks |
| **UserPromptExpansion** | a slash command expands | `expansion_type`, `command_name`, `command_args`, `command_source`, `prompt` | exit 2 blocks | ○ |
| **Setup** | `--init-only` / `--init` / `--maintenance` | `trigger` | — | ○ |

## 2. `Notification` — does it distinguish a permission prompt? YES, and there is a trap

**The 14 `notification_type` values, verbatim from the binary** (`Xor`):

```
permission_prompt · idle_prompt · auth_success · elicitation_dialog ·
agent_needs_input · agent_completed · elicitation_url_dialog ·
worker_permission_prompt · push_notification · computer_use_enter ·
computer_use_exit · quota_auto_resume_fired · quota_auto_resume_stale ·
quota_auto_resume_disabled
```

`notification_type` is BOTH the matcher field and a payload field, so
`"matcher": "permission_prompt"` gives you a dedicated hook — which this fleet already
registers (`notify.sh permission`, `push-critical.sh`). So states (2) and (3) are cleanly separable.

🚨 **TRAP 1 — `permission_prompt` is on a 6-SECOND DEBOUNCE.** Binary emission site:

```js
if (…CLAUDE_CODE_DISABLE_PERMISSION_PROMPT_NOTIFY_HOOKS) return () => {};
let o = setTimeout(…{ message:`Claude needs your permission to use ${l}`,
                      notificationType:"permission_prompt" }…, M4e, …);
o.unref(); return () => clearTimeout(o);
```
`var M4e = 6000`. The timer is **cancelled when the prompt is answered**. So a prompt
answered inside 6 s emits **NO Notification at all** — a permission-state indicator built
only on `Notification` is blind to every fast prompt. ⇒ **use `PermissionRequest` for the
"blocked" edge** (it fires the moment the dialog is displayed) and `Notification` only as
the "still blocked after 6 s" escalation. Kill switch exists:
`CLAUDE_CODE_DISABLE_PERMISSION_PROMPT_NOTIFY_HOOKS`.

🚨 **TRAP 2 — `idle_prompt` is a 60 s timer, not "the turn ended".** Binary:
`messageIdleNotifThresholdMs: 60000` (settings-overridable), and the emitter is gated on
`!isDialogOnScreen() && !hasPendingLoopWakeup() && !hasArmedQuotaAutoResume() &&
elapsed >= threshold`. Message: `"Claude is waiting for your input"`. It is also gated on
`inputNeededNotifEnabled` — **measured `true` in all four config dirs**
(`~/.claude`, `-tertiary`, `-next`, `-quaternary`).
⇒ `idle_prompt` is a *deep-idle* signal, 60 s late, and **never fires while a permission
dialog is up** (that `isDialogOnScreen` guard is what keeps states 2 and 3 from colliding).
For "turn just ended", use **`Stop`**, which is instantaneous.

## 3. `Stop` — semantics for a fire-and-forget indicator

- Fires **right before Claude concludes its response**, i.e. the session is now idle awaiting
  the human. Correct edge for state (2).
- **A hook that runs a command and exits 0 does NOT alter control flow.** Binary contract:
  `Stop: Exit code 0 - stdout/stderr not shown`. Only exit 2, `decision:"block"`,
  `continue:false`, or `hookSpecificOutput.additionalContext` force another turn.
  ⚠️ Per this repo's own CLAUDE.md correction: **`additionalContext` on Stop is NOT advisory** —
  it forces a turn and increments the same counter as `decision:"block"` (capped by
  `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`). A pane-painter must emit **no JSON on stdout** (or only
  `{"suppressOutput":true}`). Precedent: `notify.sh complete` is already on Stop today and exits 0.
- **`Stop` and `SubagentStop` are mutually exclusive at one call site.** Binary:
  `ue = d ? {…hook_event_name:"SubagentStop", agent_id:d…} : {…hook_event_name:"Stop"…}`
  where `d` = agentId. **An in-process subagent finishing does NOT emit `Stop`** — no spurious
  "idle" while the parent is still working. (A *teammate* is a separate `claude.exe` process and
  has its own real `Stop` in its own pane — correct for a per-pane indicator.)
  Separately, a `Stop` hook declared in **agent frontmatter** is silently rewritten:
  `"Converting Stop hook to SubagentStop for <agent> (subagents trigger SubagentStop)"`.
- **`Stop` does not fire when the turn dies on an API error — `StopFailure` does, instead.**
  Without a `StopFailure` arm, a rate-limited pane stays painted "working" indefinitely.
- `Stop.background_tasks[]` (`{id,type,status,description,command?,agent_type?,server?,tool?,name?}`)
  and `Stop.session_crons[]` exist precisely to "distinguish *session is done* from *session is
  paused waiting for background work to wake it*" (binary's own `.describe()`).

## 4. Turn-START events other than `UserPromptSubmit`

**There is no separate one — `UserPromptSubmit` IS the wake event, and its `source` field
names the waker.** Binary enum + descriptions:

| `source` | meaning |
|---|---|
| `user` | the interactive composer |
| `sdk` | `-p` / Agent SDK |
| `loop_wakeup` | dynamic `/loop` wakeup |
| `schedule_wakeup` | scheduled task / CronCreate |
| **`system`** | **"other machine-injected turns (peer/channel messages, task notifications, auto-continuation)"** |
| `poll_event` | poll-event channel enqueue-time pass |

So "a background task completes and wakes the session" and "a task-notification wakes it"
both arrive as `UserPromptSubmit` with `source:"system"`. Caveat in the binary itself:
*"Payloads may omit it while the field rolls out."* Treat a missing `source` as `user`.

Higher-frequency "still working" ticks, cheapest first: **`PostToolBatch`** (once per model
round-trip) → `PreToolUse`/`PostToolUse` (per tool) → `MessageDisplay` (per streamed delta).

## 5. Latency and blocking

| Property | Value | Source |
|---|---|---|
| Execution | **all matching hooks run in parallel**, and the session **waits** for them | docs; binary |
| Default timeout | **600 000 ms** (`var Ef=600000`) for `command`/`http`/`mcp_tool`; 30 s `prompt`; 60 s `agent` | binary + docs |
| Lowered defaults | **30 s** on `UserPromptSubmit`, `PreModelSwitch`, `PostModelSwitch`; **10 s** on `MessageDisplay` | docs |
| `SessionEnd` | **1.5 s shared budget across ALL SessionEnd hooks**, raised to your `timeout` (cap 60 s) | docs |
| Per-hook override | `"timeout": <seconds>` on the hook object — this fleet already uses 5 / 10 / 120 / 180 | live `settings.json` |
| Timeout ≠ block | a timed-out `command` PreToolUse hook does **not** block the call; a timed-out **PreModelSwitch** hook **does** block the switch | docs |
| Backgrounding | **safe, and already done here.** `hooks/mailbox-wake-arm.sh` (SessionStart) detaches `bin/cc-await-ping` — live right now as pid 3663 with a 14 340 s timeout while its session runs normally | measured `ps` |

⇒ For a pane painter: keep the foreground path to a `printf`/`kitty @` (single-digit ms),
set an explicit `"timeout": 5`, and detach anything slower. **Do not** background the whole
hook under a live `/goal` in the *firing* pane — this repo's `hooks/validate-bash.sh` denies
that, and it silently disarms the goal's Stop hook.

## 6. Can a hook learn its own kitty window id? **YES — three ways, all live**

**Measured** (env of a direct child of this session's `claude.exe`):

```
KITTY_WINDOW_ID=320          KITTY_LISTEN_ON=unix:/tmp/kitty-97084
KITTY_PID=97084              ITERM_SESSION_ID=w0t0p0:320
TERM=xterm-kitty             WINDOWID=101581
CC_PANE_CMD_DIR=/Users/chrisren/.claude/run/kitty-pane-cmd
CC_PANE_RUNNER=/Users/chrisren/Development/claude-infrastructure/bin/cc-pane-runner
CLAUDE_PID=2475              CLAUDE_EFFORT=high
```

`CC_PANE_ID` is **not** set on a pane-backed session — it is the *headless* spelling
(`bin/cc-pane-headless:197` runs `export CC_PANE_ID="$id" && unset ITERM_SESSION_ID`).

**Independent, hook-side proof that this env reaches a HOOK.** `hooks/session-register.sh` is a
`SessionStart` hook; line 127 is `pane="${CC_PANE_ID:-${ITERM_SESSION_ID:-}}"; pane="${pane##*:}"`.
Its output, `~/.claude/cc-registry/<pane>.json`, currently holds rows written **today at 20:36**:

```json
{ "paneUUID": "324", "name": "claude-infrastructure-324",
  "cwd": "/Users/chrisren/Development/claude-infrastructure",
  "account": "claude-tertiary", "pid": 18848, "surface": "pane",
  "session_id": "e7050036-…", "lstart": "Mon Sep 14 01:36:12 2026" }
```

`scripts/kitty-setup.sh:305` synthesises `ITERM_SESSION_ID="w0t0p0:$KITTY_WINDOW_ID"`, so
**`paneUUID` 324 *is* the kitty window id** — a hook demonstrably learned it.
`hooks/lead-crash-watchdog.sh:1390` reads the chain directly:
`LEAD_PANE="${CC_PANE_VERDICT_PANE:-${CC_PANE_ID:-${KITTY_WINDOW_ID:-${_lcw_isid##*:}}}}"`.

**Recommended addressing scheme** (matches every existing consumer):
`pane="${CC_PANE_ID:-${KITTY_WINDOW_ID:-${ITERM_SESSION_ID##*:}}}"` — and per the repo's own
`cc-pane-id-lint`, make the precedence *structural* rather than a bare inline default.
Target kitty with `kitty @ --to "$KITTY_LISTEN_ON" … --match "id:$KITTY_WINDOW_ID"`.

⚠️ **Residual I could not close read-only.** macOS `ps -E` refuses another process's environ,
and registering a probe hook was out of scope, so the env dump above is from a *Bash-tool*
child rather than from a *hook* child. The two are spawned by the same process and the binary
*adds* vars (`CLAUDE_ENV_FILE`, `CLAUDE_PROJECT_DIR`, `CLAUDE_EFFORT`, `CLAUDE_SESSION_ID`)
rather than filtering; the registry rows above are the hook-side corroboration. If you want the
direct reading, a one-line `SessionStart` probe (`env | grep KITTY > /tmp/x`) settles it in one session.

⚠️ **Volatility.** `hooks/lib/origin-identity.sh` records that the pane id is **not durable** —
a resume, crash-recreate or kitty restart renumbers it, and ids are **reused**. A transplanted or
resumed session has *no* `ITERM_SESSION_ID` at all
(MEMORY: `transplanted-session-loses-dispatch-identity`). Key durable state on `cwd` or
`session_id`; use the pane id only as the paint target, and re-read it at every fire.

### Sanctioned alternative: `terminalSequence`

Any hook may return `{"terminalSequence": "<esc seq>"}` — *"a terminal escape sequence
(e.g. OSC 9 / OSC 777 desktop-notification) for Claude Code to emit on your behalf."*
**Allowlisted to OSC 0, 1, 2, 9, 99, 777 and BEL only** (binary rejects the rest:
*"OSC 9 bodies may not begin with a digit unless in the 9;4 progress form"*).
That covers **window/tab title (OSC 0/1/2)** and desktop notifications (9/99/777) — enough for a
title-based indicator with zero subprocess — but **not** arbitrary colour. For colour you must
shell out to `kitty @`. Note `StopFailure` discards all hook output *"except for side-effect
fields like `terminalSequence`"`, which makes it the only usable channel on that event.

## 7. How this repo registers hooks

**Registry shape** — `~/.claude-tertiary/settings.json` → `"hooks": { "<Event>": [ { "matcher": "…",
"hooks": [ { "type": "command", "command": "~/.claude/hooks/x.sh", "timeout": 5 } ] } ] }`.
20 events wired; `PreToolUse` alone has 6 matcher groups / 9 Bash hooks. Tilde paths are stored
**literally** and expanded by CC at hook-run time (migration 0019 comments — do not expand `$HOME`
into a file mirrored across five config dirs).

🚨 **Measured in migration 0019: the user-level `settings.local.json` is NOT read as a hook source.**
Two zero-quota `--init-only` runs with in-run controls: user `settings.json` 1 row, user
`settings.local.json` **0** rows; a project's `settings.json` *and* `settings.local.json` both 1.
A fleet-wide hook must go in **`<config-dir>/settings.json`, in every config dir**
(`~/.claude`, `-next`, `-tertiary`, `-quaternary`) — registering elsewhere yields a hook that is
registered and never fires.

**The procedure — `migrations/README.md`.** One executable file `migrations/NNNN-<slug>.sh`,
landed **in the same diff as its subject**, run in lexical order by
`scripts/deploy-migrations.sh` from `scripts/deploy-live.sh` at every converge, exactly once, ledgered.

```bash
#!/bin/bash
# migration-class: c10          # settings.json / plist / credentials ⇒ c10, ALWAYS. No default —
#                               # an undeclared class is recorded FAILED and paged.
# migration-step:  <one line naming the operator-owned step, filed to cc-backlog needs>
# migration-run:   bash ~/Development/claude-infrastructure/migrations/NNNN-<slug>.sh
# migration-subject: ~/.claude/hooks/<the arm>.sh
# migration-verify: jq -e '[.hooks.<Event>[]?.hooks[]?.command] | any(test("<slug>"))' \
#                     "${CC_CLAUDE_DIR:-$HOME/.claude}/settings.json" >/dev/null
set -uo pipefail
```

Rules that bind: **`c10` is staged, never run** — the runner files one operator step and stops
(the C10 rescope is unratified, so the converger will not self-authorize a `settings.json` edit).
`migration-verify` is **mandatory** and must assert the **effect, not the paperwork**; a tautology
(`true`, `:`, `exit 0`) is rejected by `tests/deploy-migrations.bats` case 9. Idempotent by its own
construction. Bounded at `CC_MIGRATION_TIMEOUT_S` = 120 s. Never write repo-side.
`registration-state.sh` re-runs each verifier once **per config dir** with `CC_CLAUDE_DIR` re-aimed —
so use that variable, or the oracle manufactures a permanent `partial`.
Operate with `scripts/deploy-migrations.sh --status | --dry-run | --selftest`.
Next free number: **0028**.

## 8. Recommended event set for the 5 states

| State | Primary | Corrective arm |
|---|---|---|
| **(1) working** | `UserPromptSubmit` (turn start; `source` names the waker) | `PostToolBatch` as the cheap keep-alive |
| **(2) idle awaiting human** | **`Stop`** (instant, exit 0, no stdout) | **`StopFailure`** — else an API-error turn sticks on "working"; `Notification/idle_prompt` = deep-idle ≥60 s |
| **(3) blocked on permission** | **`PermissionRequest`** (fires as the dialog is displayed, un-debounced; exit 0 + no JSON is inert) | `Notification` matcher `permission_prompt` (6 s later) · `Elicitation` for MCP asks · `Notification/agent_needs_input` |
| **(4) background task / subagent** | `SubagentStart` / `SubagentStop`; `TaskCreated` / `TaskCompleted` | `Stop.background_tasks[]` to tell "done" from "paused on background work"; `TeammateIdle` for teammate panes |
| **(5) exit** | `SessionEnd` (matcher tells `clear\|resume\|logout\|prompt_input_exit\|other`) | mind the **1.5 s shared budget**; a crash/SIGTERM emits nothing — pair with `hooks/lead-crash-watchdog.sh`'s pane-settle detector |

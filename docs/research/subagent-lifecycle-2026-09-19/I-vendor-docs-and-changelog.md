# I — Vendor docs and CHANGELOG: the documented lifecycle of subagents and teammates

Research slot I of the subagent-lifecycle wave. 2026-09-19. Read-only; sources are
`code.claude.com/docs`, `raw.githubusercontent.com/anthropics/claude-code/CHANGELOG.md`, and the
GitHub issues API.

**The headline, stated before the evidence:** the vendor does not document a teammate that ends
itself. It documents a teammate that goes **idle and stays running**, a `TeammateIdle` hook whose
only documented power is to **prevent** that idle, and cleanup that is bound to **session exit**,
not to task completion. The fleet's expectation — *a teammate that is done, idle, or has returned
its result closes down gracefully by itself* — is not a degraded form of the documented contract.
It is the **opposite polarity** of it.

---

## Instrument caveat, stated first

Three classes of source, with different trust:

| Source | Fidelity |
|---|---|
| `https://code.claude.com/docs/en/<page>.md` | **Literal.** Reproduced verbatim by the fetcher; code blocks and tables came back intact. Every quote below marked *(verbatim, .md)* is trustworthy to the word. |
| `https://code.claude.com/docs/en/<page>` (HTML) | **Literal but TRUNCATED.** `agent-teams` returned in full; `settings-reference` and `settings` truncate mid-table (alphabetically at `strictPluginOnlyCustomization`), which is exactly where `teammateMode` would sit. See § teammateMode for the consequence. |
| CHANGELOG via WebFetch | **Filtered by a summarizing model, not grepped.** Bullets are reproduced as quoted strings but a long bullet may have been clipped at the tail. The load-bearing bullet (2.1.250) should be re-verified by hand before anything is built on it: `curl -s https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md \| grep -n -i -E 'teammate\|pane\|idle'`. |

The CHANGELOG exceeds the fetcher's window, so the 2.1.220→2.1.278 range was covered in **three
overlapping reads** against pinned tags — `v2.1.245` (covers 220→245), `v2.1.266` (246→266), and
`main` (267→278). No gap; no version read only once at a boundary.

---

## 1. Subagent lifecycle (unnamed / ordinary subagents)

### Completion is a RETURN, not an exit the caller manages

> "When Claude encounters a task that matches a subagent's description, it delegates to that
> subagent, which works independently and returns results."
> — <https://code.claude.com/docs/en/sub-agents>

> "Each subagent invocation creates a new instance rather than continuing an earlier one."
> — <https://code.claude.com/docs/en/sub-agents>

> "Subagents | Own context window; results return to the caller"
> — <https://code.claude.com/docs/en/agent-teams>, § Compare with subagents

There is **no documented teardown step for a subagent**. Its lifecycle terminates by returning. The
docs describe only the *UI row* being cleaned up:

> "When a subagent finishes successfully, Claude Code removes its row immediately and, except in
> [screen reader mode], shows `/tasks to see subagents` in the footer for 30 seconds. During those
> 30 seconds, run `/tasks` and press `Enter` on the subagent to open its transcript. Before
> v2.1.232, Claude Code kept the row for 30 seconds after the subagent finished, the same as a
> failed one, and showed no footer hint."
> — <https://code.claude.com/docs/en/sub-agents.md> *(verbatim, .md)*

> "When a subagent fails or you stop it, Claude Code keeps its row for 30 seconds. To clear the row
> sooner, select it and press `x`."
> — <https://code.claude.com/docs/en/sub-agents.md> *(verbatim, .md)*

### Background subagents notify; the main agent waits for the notification

> "A background subagent's results reach Claude as a completion notification in a later turn.
> Claude waits for that notification before reporting the subagent's results, and if you ask about
> progress first, it reports that the subagent is still running. Before v2.1.211, Claude sometimes
> reported results for a background subagent that hadn't finished."
> — <https://code.claude.com/docs/en/sub-agents.md> *(verbatim, .md)*

### The documented way to STOP one is `TaskStop`

> "`TaskStop` | Stops a running background task by ID. It also accepts an [agent-team teammate] or a
> named background agent by agent ID or name. Before v2.1.198, it accepted only a background task
> ID. When no task matches the ID, the error lists the running background agents by ID and
> description. Before v2.1.203, the error listed running teammates and named agents but not
> background agents another agent spawned, so those couldn't be identified or stopped from the main
> conversation | Permission required: No"
> — <https://code.claude.com/docs/en/tools-reference.md> *(verbatim, .md)*

**This is the one vendor-documented mechanism by which an agent can end a teammate rather than ask
it to end itself.** It is a *tool the lead calls*, not a hook and not a self-close. It is
**undocumented** whether `TaskStop` on a split-pane teammate closes the pane — the entry says
"stops a running background task", nothing about pane disposal. Issue #74638 (open) alleges it
reports success while the process survives; see § 6.

### `maxTurns` ends a subagent with PARTIAL output, not a failure

> "Set `maxTurns` to the maximum number of agentic turns before the subagent stops. When the
> subagent reaches the limit, Claude Code returns its output marked as partial, and Claude can
> resume it to continue."
> — <https://code.claude.com/docs/en/sub-agents>

Matches the fleet's already-recorded lesson `in-process-agent-stops-at-100-turns` — the vendor
confirms the harness reports a *normal completion carrying partial work*.

### Resume re-opens a finished subagent

> "Resuming starts a new run of the agent under the same ID, so a subagent that had already failed
> or completed shows as running again in the task list and in the Agent SDK's task events."
> — <https://code.claude.com/docs/en/sub-agents>

So "completed" is **not terminal** in the vendor's model. A completed agent ID is re-enterable.
This is the structural reason a "finished" agent can reappear as running.

### Concurrency and depth caps (teammates are explicitly OUT of scope of the subagent cap)

> "By default, when 20 subagents are running in a session, spawning another with the Agent tool
> fails with `Concurrent subagent limit reached`, and the error tells Claude not to retry."
> — <https://code.claude.com/docs/en/sub-agents.md> *(verbatim, .md)*

> "Agents that other features run, such as workflow agents and agent team teammates, follow their
> own limits instead."
> — <https://code.claude.com/docs/en/sub-agents.md> *(verbatim, .md)*

> "**v2.1.217 through v2.1.218**: the limit defaulted to one, so a subagent couldn't spawn its own
> unless you raised it; v2.1.219 raised the default to three."
> — <https://code.claude.com/docs/en/sub-agents.md> *(verbatim, .md)*

> "Set `1` to turn nesting off."
> — <https://code.claude.com/docs/en/sub-agents.md> *(verbatim, .md)*

This **independently confirms** the corrected reading in `agents/deep-research.md`: depth-1 is a
switch we hold (`~/.zshrc:484`), not a product incapacity. The vendor documents `1` as the
off-position of a knob whose default is `3`.

---

## 2. Teammate finish / idle / shutdown / cleanup

### (a) What the vendor says happens when a teammate finishes — quote it

The single most load-bearing sentence in this whole report:

> "**Idle notifications**: when a teammate finishes and stops, it automatically notifies the lead
> and includes its final answer in the notification. A teammate whose turn ends on an API error
> notifies the lead that it failed and includes the error text."
> — <https://code.claude.com/docs/en/agent-teams>, § Context and communication

"finishes and stops" reads like termination. **It is not**, and the same page says so two sections
earlier:

> "As of v2.1.199, an idle teammate's row stays in the panel while any teammate or subagent is
> still working, so you can select it to review its transcript or send it more work. Once every
> agent in the panel is idle, idle rows hide after 30 seconds and reappear on the teammate's next
> turn; **the teammate stays running and addressable while hidden.**"
> — <https://code.claude.com/docs/en/agent-teams>, § Start your first agent team *(emphasis added)*

> "A teammate row that disappeared after sitting idle has been **hidden, not stopped**. Idle rows
> hide 30 seconds after the whole panel goes idle and reappear on the teammate's next turn. … Send
> the teammate a message by name to bring a hidden row back."
> — <https://code.claude.com/docs/en/agent-teams>, § Troubleshooting → Teammates not appearing
> *(emphasis added)*

**Verdict on question (a): the vendor documents IDLE, not EXIT.** "Stops" in the idle-notification
sentence means *stops taking turns*, and the troubleshooting section exists precisely because
readers mistake the hidden row for a stopped process. There is **no sentence anywhere in the
agent-teams page** saying a teammate exits, terminates, or closes its own pane on finishing a task.

A third sentence puts it past doubt — self-claim is the documented behaviour of a finished
teammate, i.e. it is expected to still be alive and looking for work:

> "**Self-claim**: after finishing a task, a teammate picks up the next unassigned, unblocked task
> on its own"
> — <https://code.claude.com/docs/en/agent-teams>, § Assign and claim tasks

And a fourth, from the CHANGELOG, confirms finished teammates persist as session state long enough
to block an unrelated operation:

> 2.1.273: "Fixed `/tui` refusing to restart because of an agent-team teammate that had already
> finished its work and was no longer shown"
> — CHANGELOG (via WebFetch, `main`)

### (b) The prescribed cleanup: a request the teammate may REFUSE

> "**Shut down teammates** — To gracefully end a teammate's session, refer to it by name. For
> example, with a teammate named researcher: `Ask the researcher teammate to shut down`.
> The lead sends a shutdown request. **The teammate can approve, exiting gracefully, or reject with
> an explanation.**"
> — <https://code.claude.com/docs/en/agent-teams>, § Shut down teammates *(emphasis added)*

Three things follow, all of which matter to the fleet:

1. Shutdown is **operator- or lead-initiated in natural language**, not automatic on completion.
2. The teammate holds a **veto**. A "rejected" shutdown is documented, expected behaviour — not a
   malfunction. The fleet's structured `shutdown_request` is the same protocol message; the docs do
   not name a JSON schema for it, only the English-language trigger.
3. `TeamDelete` is **gone**:

> "With `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` set, spawning a teammate no longer needs a setup
> step, and cleanup happens automatically when the session exits. Before v2.1.178, you asked Claude
> to create and name a team first, and Claude used the `TeamCreate` and `TeamDelete` tools to set it
> up and remove it. **Both tools no longer exist.** The `team_name` input on the Agent tool is
> accepted but ignored, and the `team_name` field in `TaskCreated`, `TaskCompleted`, and
> `TeammateIdle` hook payloads carries the session-derived name and is deprecated."
> — <https://code.claude.com/docs/en/agent-teams>, top Note *(emphasis added)*

### (c) Cleanup is bound to SESSION EXIT, not to teammate completion

> "The team's shared directories are cleaned up automatically when the session ends, so there's no
> separate cleanup step."
> — <https://code.claude.com/docs/en/agent-teams>, § Shut down teammates

> "Claude Code generates both of these automatically at session startup and updates them as
> teammates join, go idle, or leave. **The team config directory is removed when the session ends.**
> The task list directory persists locally and is never uploaded, so resumed sessions keep their
> tasks."
> — <https://code.claude.com/docs/en/agent-teams>, § Architecture *(emphasis added)*

Note "as teammates join, go idle, or **leave**" — the vendor's state machine has a *leave*
transition, but the page never says what causes it other than a shutdown request or session end.

### (d) Shutdown is documented as SLOW, and that is a listed limitation

> "**Shutdown can be slow**: teammates finish their current request or tool call before shutting
> down, which can take time."
> — <https://code.claude.com/docs/en/agent-teams>, § Limitations

### (e) Orphaned panes are documented as a thing the OPERATOR cleans up by hand

> "**Orphaned tmux sessions** — If a tmux session persists after the Claude Code session ends, it
> may not have been fully cleaned up. List sessions and end the one created by the team:
> `tmux ls` / `tmux kill-session -t <session-name>`"
> — <https://code.claude.com/docs/en/agent-teams>, § Troubleshooting

The vendor ships a manual remedy for exactly the failure the fleet automates around. There is **no
equivalent paragraph for iTerm2 panes** — undocumented.

### (f) Teammates may stop early and STAY stopped; the documented remedy is human

> "Teammates may stop after encountering errors instead of recovering. Check their output by
> selecting the teammate in the agent panel and pressing Enter in in-process mode, or by clicking
> the pane in split mode, then either: Give them additional instructions directly / Spawn a
> replacement teammate to continue the work."
> — <https://code.claude.com/docs/en/agent-teams>, § Troubleshooting → Agents stopping early

> "The lead can stop early too, deciding the team is finished before all tasks are actually
> complete. If that happens, tell it to keep going."
> — same section

### (g) A stopped in-process teammate is RESURRECTED by a message

> "When Claude messages an in-process teammate that is no longer running, Claude Code brings it back
> in the same session, restores any conversation saved for it, and gives it the message as its next
> prompt. After you resume a session, teammates aren't brought back this way, per the resume
> limitation."
> — <https://code.claude.com/docs/en/agent-teams>, § Use subagent definitions for teammates

So *"no longer running"* is a real state the vendor models — but it is reached by stopping, not by
finishing, and the design intent is that it is **reversible**.

### (h) Nothing outlives the lead (in-process), and the lead cannot be replaced

> "**No background subagents from in-process teammates**: an in-process teammate's own subagents run
> in the foreground, **because a teammate's background work can't outlive the lead's process.**"
> — <https://code.claude.com/docs/en/agent-teams>, § Limitations *(emphasis added)*

> "**Lead is fixed**: the main session is the lead for its lifetime. You can't promote a teammate to
> lead or transfer leadership."
> — same

> "**No nested teams**: teammates cannot spawn their own teammates. Only the lead can manage the
> team."
> — same

**Undocumented:** whether a *split-pane* teammate (a separate process in its own pane) dies when
the lead exits. The quoted sentence reasons only about in-process teammates' background work.

---

## 3. Hook contracts

All four sections below are *(verbatim, .md)* from <https://code.claude.com/docs/en/hooks.md>
unless marked otherwise.

### 3.1 `TeammateIdle` — the decisive finding

> "When an agent team teammate is about to go idle, Claude Code fires `TeammateIdle`. Use this to
> prompt the teammate to continue work, hand off to another teammate, or notify you of progress.
>
> Your hook receives the teammate's status and can return `shouldContinue: true` to tell the
> teammate to keep working, or `additionalContext` to give it more information. **Exit code 2
> blocks the idle, preventing the teammate from stopping.**"
> *(emphasis added)*

Input schema, verbatim:

```json
{
  "session_id": "abc123",
  "hook_event_name": "TeammateIdle",
  "agent_type": "code-reviewer",
  "agent_id": "agent_xyz",
  "cwd": "/home/user/my-project",
  "permission_mode": "default",
  "last_assistant_message": "Code review complete. All items addressed.",
  "suggested_continuation": "Continue reviewing test coverage"
}
```

From the exit-code-2 table:

> "| `TeammateIdle` | Can block? **Yes** | Blocks the idle state; the teammate continues working |"

Cross-checked against the agent-teams page, which says the same thing in the opposite direction:

> "`TeammateIdle`: runs when a teammate is about to go idle. Exit with code 2 to send feedback and
> keep the teammate working."
> — <https://code.claude.com/docs/en/agent-teams>, § Enforce quality gates with hooks

**🚨 `TeammateIdle` has exactly one documented power, and it is to KEEP THE TEAMMATE ALIVE.**

- Exit 2 → teammate keeps working.
- `shouldContinue: true` → teammate keeps working.
- `additionalContext` → teammate keeps working, with more context.
- Exit 0 with no JSON → idle proceeds (the teammate goes idle and **stays running**, per § 2a).

There is **no documented exit code, JSON field, or `decision` value on `TeammateIdle` that ends the
teammate, closes its pane, or frees its slot.** The hook fires *before* the idle and can only veto
it. A fleet hook that closes panes on `TeammateIdle` is operating entirely outside the documented
contract — not against it, but beside it, in a space the vendor has not specified.

**Named uncertainty:** the common-JSON-output table's row for `shouldContinue` came back as
`[Field mentioned in content but specific details truncated in source material]`. The field is
named in the `TeammateIdle` prose (quoted above) and appears in the common-fields list, but **its
schema row is not reproducible from the fetch**. Whether it is nested under `hookSpecificOutput` or
sits at top level is **undocumented as far as this pass could reach**. Do not guess it; test it.

Matcher support:

> "`TeammateIdle`, `SubagentStop`, `TaskCreated`, `TaskCompleted`, `WorktreeCreate`,
> `WorktreeRemove`, `MessageDisplay` | no matcher support | always fires on every occurrence"
> — <https://code.claude.com/docs/en/hooks>

`TeammateIdle` fires on **every** idle of **every** teammate, with no filter. A per-teammate or
per-agent-type gate must be implemented inside the hook body by reading `agent_id`/`agent_type`.

### 3.2 `SubagentStop`

> "When a subagent finishes, Claude Code fires `SubagentStop`. Your hook receives the subagent's
> final state and response. **Exit code 2 is not honored on this event.**" *(emphasis added)*

```json
{
  "session_id": "abc123",
  "hook_event_name": "SubagentStop",
  "agent_type": "Explore",
  "agent_id": "agent_xyz",
  "cwd": "/home/user/my-project",
  "permission_mode": "default",
  "last_assistant_message": "I've explored the codebase and found three potential areas for optimization.",
  "stop_reason": "end_turn",
  "input_tokens": 2500,
  "output_tokens": 1200
}
```

Exit-2 table row:

> "| `SubagentStop` | No | Exit code 2 isn't honored; the subagent already finished |"

**This contradicts the common-JSON-output table on the same page**, which says:

> "| `continue` | For `UserPromptSubmit` and `UserPromptExpansion`, set to `false` to block. For
> `Stop` and `SubagentStop`, set to `false` to prevent stopping and continue the conversation |"

> "| `stopReason` | For `Stop` and `SubagentStop`, a string describing why Claude should continue
> instead of stopping |"

> "| `suppressOutput` | For `Stop` and `SubagentStop`, set to `true` to suppress Claude's response
> from the transcript |"

**Named contradiction, unresolved by this pass:** the exit-code table says exit 2 is not honored on
`SubagentStop` *because the subagent already finished*, while three JSON fields are documented as
able to *prevent it stopping*. Either exit 2 and `continue:false` have different powers on this
event, or one of the two tables is stale. **Do not build on `continue:false` at `SubagentStop`
without measuring it.** Note the fleet already holds the general form of this hazard:
`gate-default-decides-failure-direction` and `two-producers-one-moment-different-cadences`.

Matcher: agent type name, "same values as `SubagentStart`". Recent fix worth knowing:

> 2.1.274 / 2.1.269: "Fixed `SubagentStop` hooks with a specific `matcher` firing for every stopping
> subagent whose agent type was empty" — CHANGELOG

A `matcher`-scoped `SubagentStop` hook on a binary **before 2.1.274** fires for every empty-type
subagent. The fleet at 2.1.260 is **inside** that window.

### 3.3 `TaskCompleted` and `TaskCreated`

> "When a task is being marked as completed, Claude Code fires `TaskCompleted`. Your hook receives
> the completed task details."

```json
{
  "session_id": "abc123",
  "hook_event_name": "TaskCompleted",
  "cwd": "/home/user/my-project",
  "permission_mode": "default",
  "task": {
    "id": "task_123",
    "title": "Fix login bug",
    "description": "Users unable to reset password",
    "status": "completed",
    "completed_at": "2024-01-15T11:45:00Z"
  }
}
```

> "| `TaskCompleted` | No | Exit code 2 isn't honored; the task is already completed |"
> "| `TaskCreated`   | No | Exit code 2 isn't honored; the task is already created |"

**🚨 This directly contradicts the agent-teams page**, which says:

> "`TaskCreated`: runs when a task is being created. Exit with code 2 to prevent creation and send
> feedback.
> `TaskCompleted`: runs when a task is being marked complete. Exit with code 2 to prevent completion
> and send feedback."
> — <https://code.claude.com/docs/en/agent-teams>, § Enforce quality gates with hooks

Two vendor pages, fetched the same day, give **opposite answers** on whether exit 2 blocks
`TaskCompleted`. The hooks page's per-event table is the more specific instrument and its wording
("is being marked as completed" vs "the task is already completed") is itself internally
inconsistent within the same page. The fleet's `task-quality-gate.sh` is registered on
`TaskCompleted` and **REJECTS the task on typecheck failure** — i.e. the fleet's live code depends
on the agent-teams page being right and the hooks table being wrong. **This is measurable in one
run and should be measured, not argued.**

Note also: the `task` payload carries **no `agent_id`**. An earlier HTML fetch of the hooks page
reported `agent_id`/`agent_type` for `TaskCompleted`; the `.md` literal does not. Trust the `.md`.

### 3.4 `SessionEnd`

> "When a session terminates, Claude Code fires `SessionEnd`. Your hook receives the reason the
> session ended and final session details. This is useful for cleanup, logging, or archiving work."

```json
{
  "session_id": "abc123",
  "hook_event_name": "SessionEnd",
  "cwd": "/home/user/my-project",
  "permission_mode": "default",
  "end_reason": "clear",
  "session_duration_seconds": 1847,
  "total_turns": 12
}
```

> "| `SessionEnd` | No | Exit code 2 isn't honored; the session is already ending. Hooks can't
> prevent it |"

Matcher values: `"clear"`, `"resume"`, `"logout"`, `"prompt_input_exit"`, `"other"`.

`SessionEnd` is the vendor's *named* cleanup seam — and it fires per-session. A **teammate** is a
full session, so `SessionEnd` should fire in the teammate's own process on its exit; that is the
natural reading but it is **not stated anywhere**. Undocumented.

### 3.5 Which process runs these hooks

This is the brief's sharpest question and the docs answer it **only for subagents**:

> "Hooks from settings files, managed policy settings, and plugins also run inside subagents. When a
> subagent calls a tool, tool events such as `PreToolUse` and `PostToolUse` fire the same configured
> hooks as in the main conversation, and the input carries the `agent_id` and `agent_type` common
> input fields that identify the subagent."
> — <https://code.claude.com/docs/en/hooks.md> *(verbatim, .md)*

> "**Subagent hooks**: Claude Code runs them only while that subagent is running and removes them
> when it finishes."
> — <https://code.claude.com/docs/en/hooks.md> *(verbatim, .md)*

> "**In `settings.json`**: define session-wide hooks that also fire inside subagents."
> — <https://code.claude.com/docs/en/sub-agents.md> *(verbatim, .md)*

**For TEAMMATES: undocumented.** The agent-teams page lists what a teammate inherits —

> "When spawned, a teammate loads the same project context as a regular session: CLAUDE.md, MCP
> servers, and skills. It also receives the spawn prompt from the lead. The lead's conversation
> history does not carry over."
> — <https://code.claude.com/docs/en/agent-teams>, § Context and communication

— and **hooks are not in that list.** Neither is `settings.json`. Whether a `TeammateIdle` hook
executes in the lead's process or the teammate's is **never stated on any page fetched in this
pass**. The `agent_id`/`agent_type` fields in the payload identify *the subject*, which is
compatible with either. Do not infer it; the fleet's pane-closing hook's correctness depends on
which process's cwd, env, and PATH it inherits. **Measure it** (e.g. have the hook write `$$`,
`$PPID`, `$PWD` and `$CLAUDE_CONFIG_DIR` to a file and compare against the known lead pid).

The fleet's own memory already names the general hazard:
`symlinked-0-splits-sibling-sources` and `launcher-runs-the-live-layer` both turn on *which
process, resolved from where*.

### 3.6 The `Notification` event — the only documented handle near idle spam

Matcher values include `"idle_prompt"`, `"agent_needs_input"`, `"agent_completed"`.

> "| `Notification` | No | Exit code 2 isn't honored; the notification is already sent |"

So notifications can be **observed** and side-effected (`terminalSequence`) but **not suppressed**.
That is precisely what open issue #92891 asks for; see § 6.

---

## 4. `teammateMode`: values, default, auto-detection, and the pane

### The canonical text (from the agent-teams page; see the caveat below)

> "The default is `"in-process"`. Set `"auto"` to enable split panes when you're already running
> inside a tmux session, or when your terminal is iTerm2 with the `it2` CLI installed, falling back
> to in-process otherwise. The `"tmux"` setting enables split-pane mode and auto-detects whether to
> use tmux or iTerm2 based on your terminal.
>
> As of v2.1.186, set `"iterm2"` to use iTerm2 native split panes explicitly. **This mode requires
> the `it2` CLI and shows an error with the install command if `it2` is missing.** The setup prompt
> that offers to install `it2` or switch to tmux appears under `"auto"` or `"tmux"` when your
> terminal is iTerm2 and tmux is available as a fallback."
> — <https://code.claude.com/docs/en/agent-teams>, § Choose a display mode *(emphasis added)*

| Value | Behaviour | Since |
|---|---|---|
| `"in-process"` | **DEFAULT.** All teammates inside the main terminal; navigate with arrow keys in the agent panel. "Works in any terminal, no extra setup required." | — |
| `"auto"` | Split panes **iff** already inside tmux, **or** terminal is iTerm2 with `it2` installed. Silent fallback to in-process otherwise. | — |
| `"tmux"` | Forces split-pane; auto-detects tmux vs iTerm2 from the terminal. | — |
| `"iterm2"` | iTerm2 native split panes, explicitly. Hard-requires `it2`; errors with an install command if absent. | v2.1.186 |

CLI form:

> "To set the mode for a single session, pass it as a flag: `claude --teammate-mode auto`.
> **The `--teammate-mode` flag is experimental and doesn't appear in `claude --help`.**"
> — <https://code.claude.com/docs/en/agent-teams> *(emphasis added)*

Independently confirmed: `--teammate-mode` is **ABSENT** from
<https://code.claude.com/docs/en/cli-reference.md>. The only agent-related flags documented there
are `--agent`, `--agents`, and `--append-subagent-system-prompt`.

### 🚨 `settings-reference#teammatemode` is CITED BUT UNREACHABLE

The agent-teams page links `teammateMode` to `/docs/en/settings-reference#teammatemode`. That
anchor **could not be resolved in this pass**: both `settings-reference` and `settings-reference.md`
truncate mid-table at `strictPluginOnlyCustomization` (alphabetically immediately before
`teammateMode`), and `settings.md` contains no `teammateMode` entry at all (grep over the full
57.8 KB persisted fetch: 10 hits for "teammate", **all** of them prose about a human colleague).
So the type, the schema, and any per-key version note for `teammateMode` in the settings reference
are **not verified here** — the table above is sourced from the agent-teams narrative, which is
vendor documentation but not the settings SSOT. Flagging rather than papering over: the fetcher's
truncation is the cause, not an absence in the docs.

### What happens to the PANE on shutdown — per mode

**Undocumented for every mode.** No sentence on any fetched page says the pane is closed, left
open, or reused when a teammate shuts down. What exists instead:

- The **manual tmux remedy** quoted in § 2e (`tmux kill-session`), which only makes sense if panes
  can survive.
- One CHANGELOG line, which is the closest the vendor comes to a statement of intent:

> 2.1.250: "Fixed agent-team teammates in tmux/iTerm2 panes sometimes staying open after
> acknowledging a shutdown request"
> — CHANGELOG (via pinned tag `v2.1.266`)

That bullet establishes that **panes closing on shutdown-ack is the intended behaviour** and that a
defect against it was fixed at **2.1.250** — *ten releases below the fleet's 2.1.260*. The word
**"sometimes"** is doing real work: the fix is against an intermittent failure, not a categorical
one, and the corresponding issue #24385 is **still open** (§ 6).

### kitty is undocumented, and that is a hard finding not a soft one

> "**Split panes require tmux or iTerm2**: the default in-process mode works in any terminal.
> Split-pane mode isn't supported in VS Code's integrated terminal, Windows Terminal, or Ghostty."
> — <https://code.claude.com/docs/en/agent-teams>, § Limitations

kitty is named **nowhere** — neither as supported nor as an explicit exclusion. The fleet's
`teammateMode: "iterm2"` routed through a kitty shim is therefore a configuration the vendor has
never specified, on a mode whose documented contract is *"requires the `it2` CLI"*. The community
prior art is explicit that it works by impersonation, not support:

> "Run Claude Code's split-pane agent-team mode in kitty with no tmux — a shim that translates tmux
> calls to kitty remote control … Claude Code's teammate mode drives panes via a subset of tmux
> commands; kitty has no tmux, so a tiny 'fake tmux' (Python 3, stdlib) provides the translation."
> — <https://github.com/jLAM-ERR/kitty-extensions>

**Consequence to state plainly:** the 2.1.250 fix operates on whatever pane-closing call path
Claude Code uses for tmux/iTerm2. Whether that call path reaches a kitty shim at all is
**undocumented and unverifiable from the docs.** A shim that implements the *spawn* subset of tmux
commands but not the *kill-pane* subset would produce the fleet's exact symptom, post-2.1.250, with
the vendor fix present and correct. That hypothesis costs one grep of the shim to test and is not
tested here (out of scope for this slot: docs-only).

Adjacent open feature requests confirm the backend list is a closed, hand-maintained set:
#24384 (Windows Terminal backend), #24189 (Ghostty backend).

---

## 5. CHANGELOG deltas 2.1.220 → 2.1.278

Newest version at the top of `main`: **2.1.278**. Everything matching
*teammate|team|subagent|idle|shutdown|pane|tmux|iTerm2|spawn|TeammateIdle|SubagentStop|TaskStop*:

| Version | Entry | Bearing on the fleet |
|---|---|---|
| **2.1.250** | "Fixed agent-team teammates in tmux/iTerm2 panes sometimes staying open after acknowledging a shutdown request" | **THE match.** Intended behaviour = pane closes on ack. Fixed *below* the fleet's 2.1.260. "Sometimes" ⇒ intermittent. |
| **2.1.251** | "Fixed agent teams: a teammate's final answer not reaching the team lead" | Matches issue #76500's "lost final reports (idle_notification arrives instead)". Also below 2.1.260. |
| 2.1.251 | "Fixed in-process agent-team teammates re-sending their first-turn tool and skill announcements" | — |
| 2.1.251 | "Fixed background subagents being unable to reply to a message from an unnamed sibling or parent agent" | — |
| **2.1.257** | "Fixed agent teams: an in-process teammate's transcript losing messages, or going blank" | Below 2.1.260. |
| 2.1.257 | "Fixed a subagent that resumed another agent via SendMessage never being woken by that agent's completion" | Wake-on-completion is a known-broken class. |
| **2.1.266** | "Fixed agent teammates and resumed subagents moving SubagentStart hook context" | **ABOVE 2.1.260** — fleet does not have it. |
| **2.1.268** | "Fixed a respawned in-process teammate picking up tools or a system prompt from a same-named agent file in a folder you have not trusted" | Above 2.1.260. |
| **2.1.273** | "Fixed `/tui` refusing to restart because of an agent-team teammate that had already finished its work and was no longer shown" | Above 2.1.260. **Direct evidence that finished teammates persist as blocking session state.** |
| **2.1.274** | "Fixed `SubagentStop` hooks with a specific `matcher` firing for every stopping subagent whose agent type was empty" | Above 2.1.260 ⇒ **the fleet is inside the broken window** for matcher-scoped `SubagentStop`. |
| 2.1.275 | "Fixed resumed subagents and teammates re-rendering the MCP tool definitions they had loaded, which broke prompt caching for that agent" | Above 2.1.260. |
| 2.1.275 | "Changed subagent results to reach the main agent under a header marking them as subagent output, with the result indented, so text in a subagent's result cannot pass as the session's own instructions" | Above 2.1.260. Prompt-injection hardening on the return path. |
| 2.1.271 | "Added click-to-expand for collapsed teammate and agent messages in fullscreen mode" | Cosmetic. |
| 2.1.269 | "Fixed background agent notifications claiming the agent had no live background work when it was still waiting on its own background task and would resume" | Idle-vs-alive misreporting. |
| 2.1.269 / 2.1.271 | "[VSCode] Added an agent map: an 'N agents' footer pill opens a map of the session's sub-agents with per-agent cards, **Stop agent**, and read-only transcripts" | Vendor's answer to "how do I stop one" is a **manual UI affordance**, VSCode-only. |
| 2.1.243 | "Added the model (and effort level) each subagent ran on to `/tasks` and the agent detail dialogs" | — |
| 2.1.243 | "Fixed background subagents not waking when their last background Bash task completes" | — |
| 2.1.232 | "Subagent forking is now on by default: a `subagent_type: 'fork'` subagent inherits the full conversation" | — |
| **2.1.224** | "**Removed the 200-subagent-per-session spawn cap**" | Confirms `CLAUDE.global.md` § Research Subagents verbatim: depth is the only remaining runaway bound. |
| 2.1.224 | "Added cross-session `SendMessage`: Claude Code sessions can now message each other" | — |
| 2.1.224 | "Fixed `SendMessage` reporting 'Message sent' when the write had actually failed" | Precedent for the class in #74638 (reports success, didn't happen). |
| 2.1.222 | "Fixed worktree-isolated sessions and their subagents being able to run destructive git commands" | — |
| 2.1.222 | "Fixed PreToolUse auto-allow hooks bypassing tool restrictions in background agent tasks" | — |
| 2.1.221 | "Changed sessions forked with `/fork` to create a new worktree" | — |
| 2.1.220 | *(none matching)* | — |
| 2.1.276 / 2.1.277 / 2.1.278 | *(none matching)* | Nothing on teammates in the three newest releases. |

**Pattern worth naming:** every fix in the 2.1.250–2.1.257 band is a *message-delivery or
pane-disposal* fix, and every one of them is **already in** the fleet's 2.1.260. The fixes the
fleet is **missing** (2.1.266+) are hook-context, trust-scoping, `/tui` restart, and
`SubagentStop` matcher — **not** the shutdown/pane path. So "upgrade past 2.1.260" is **not**
supported by the CHANGELOG as a remedy for a pane that will not close. The fleet already has that
fix.

---

## 6. Matching open GitHub issues

State and dates from the GitHub issues API, 2026-09-19.

### Direct hits on the fleet's exact configuration

| # | State | Opened | Title |
|---|---|---|---|
| **24385** | **OPEN** | 2026-02-09 | **Agent team iTerm2 panes not closed on teammate shutdown** |

Labels: `bug`, `has repro`, `platform:macos`, `area:tui`, `area:core`, `area:agents`. Body,
verbatim first paragraph:

> "When using `--teammate-mode tmux` with the iTerm2 backend, teammate panes are not closed when
> agents shut down. The agent process exits, the shutdown is acknowledged (including the `paneId`),
> but the iTerm2 split pane remains open with a dead shell.
>
> This also causes a cascading issue: if the orphaned pane is closed manually (or via AppleScript),
> Claude Code's internal pane tracking becomes stale. Subsequent team spawns fail with
> `Session '<old-pane-id>' not found` because it tries to split from the now-deleted pane. The only
> recovery is restarting Claude Code entirely."

🚨 **Read the second paragraph against the fleet's design.** The fleet's `TeammateIdle` hook closes
panes. This issue documents that closing a pane out-of-band **corrupts Claude Code's internal pane
tracking**, and that the failure mode is *the next spawn fails with a stale pane id, recoverable
only by restarting Claude Code*. If the fleet's hook closes a pane that the harness still believes
it owns, the fleet is executing the second half of this issue's repro **deliberately, every time**.
That is the single highest-value finding in this report and it was not in the brief's question set.

**Tension to record honestly:** #24385 is still OPEN (never closed, `state_reason: null`) while
CHANGELOG 2.1.250 claims the pane-close-on-ack defect was fixed. Three readings, all live:
(i) the fix was partial and the issue rightly stays open; (ii) the issue is stale-open and nobody
closed it — Anthropic's tracker visibly carries stale-closed/successor chains (see #92244's title);
(iii) the fix addressed the tmux path and not the iTerm2 path, or vice versa. **The CHANGELOG and
the tracker are different populations** — the fleet's own memory says so
(`changelog-and-tracker-are-different-populations`: "changelog lists what was FIXED, tracker what
is BROKEN"). Do not resolve this from the docs; it is resolvable only by running the repro.

### Idle teammates never ending

| # | State | Opened | Title |
|---|---|---|---|
| 89515 | OPEN | 2026-08-25 | Agent teams: idle teammates are never evicted — mailbox poll loop ran ~143k times (~20h), wedging session |
| 27639 | (open per search) | — | Idle team agents cannot be cleaned up and accumulate over time |
| 79016 | **CLOSED** | 2026-07-19 | Background panel: finished teammates linger as idle indefinitely, no bulk dismiss (22 agents drown out the active shell) |
| 29271 | (open per search) | — | Agent Teams: No distinction between idle-but-alive and dead teammates — lead spawns duplicates, destroying context |
| 85047 | OPEN | 2026-08-08 | Agent teams: idle-notification ping-pong on acknowledgment |

#29271 is the conceptual match for the fleet's problem: **idle-but-alive and dead are
indistinguishable**, which is the same shape as the fleet's own
`clean-worktree-cannot-distinguish-never-worked-from-landed` and
`liveness-proxy-cannot-be-output-age`.

### Shutdown request ignored / handshake incomplete

| # | State | Opened | Title |
|---|---|---|---|
| **81807** | **OPEN** | 2026-07-27 | **Opus subagents ignore `shutdown_request` while emitting `idle_notification`** |
| **74638** | **OPEN** | 2026-07-02 | **[BUG] Background agents/teammates never terminate: `shutdown_request` unanswered, `TaskStop` reports success while process survives** |
| **76500** | **OPEN** | 2026-07-10 | **[BUG] Agent Teams mailbox: 5–62 min turn-boundary delays, lost final reports (`idle_notification` arrives instead), `/clear` queue leak, shutdown handshake never completes** |
| 81464 | OPEN | 2026-07-26 | [BUG] Teammate `shutdown_request` registers against team lead; routing error causes self-termination |
| 77076 | **CLOSED** | 2026-07-13 | [BUG] Lead session exits when teammate emits unsolicited `shutdown_approved` |
| 38116 | (open per search) | — | `TeamDelete` fails after agents approve shutdown — 'active members' not cleared |

**#81807 is the fleet's symptom named exactly**, and it is **model-scoped** — *Opus* subagents
ignore `shutdown_request` while emitting `idle_notification`. The fleet runs Opus 5 by default
(`model-config.yaml` `opus_latest`). This is an axis the brief did not name and that nothing in the
fleet's config would surface: **the shutdown non-response may be a property of the MODEL, not of
the terminal, the mode, or the version.** It is cheaply testable — spawn one Sonnet teammate and one
Opus teammate into the same team and send both a shutdown request.

#76500's summary, from the search result: *"Teammates process shutdown_requests but their
shutdown_response never reaches the lead, and the teammates do not terminate: they go idle and emit
more idle_notifications. This occurred with three teammates simultaneously; all three had to be
killed via `tmux kill-pane`."* — i.e. **the operator's documented recovery is to kill the pane from
outside**, which is what the fleet automated.

#38116 is historical: `TeamDelete` no longer exists (§ 2b).

### Idle-notification spam, and the absence of a suppression handle

| # | State | Opened | Title |
|---|---|---|---|
| **92891** | **OPEN** | 2026-09-08 | **Hooks: no way to intercept or suppress teammate `idle_notification` messages** |
| 92244 | OPEN | 2026-09-05 | [BUG] Agent teams: one teammate message or `idle_notification` is delivered to the lead up to 4 times with an identical timestamp (successor to #74112, stale-closed) |
| 28627 | (open per search) | — | [BUG] Agent Teams: teammate idle notifications rendered … |
| 88503 | OPEN | 2026-08-21 | Idle notification gives no signal that teammate's finished output … |

#92891, opened 11 days ago, is the **vendor-side confirmation of § 3.6**: there is no hook that can
suppress an idle notification, because `Notification` cannot block. The fleet cannot fix
idle-notification spam with a hook; the docs and the tracker agree.

### tmux / iTerm2 / backend

| # | State | Opened | Title |
|---|---|---|---|
| 24108 | (open per search) | — | Agent teams: teammates stuck at idle prompt in tmux split-pane mode (mailbox never polled) |
| 24292 | (open per search) | — | `teammateMode: "tmux"` does not create iTerm2 split panes despite all prerequisites met |
| 24301 | (open per search) | — | iTerm2 native split pane not working with `teammateMode auto` — silently falls back to in-process |
| 24384 | (open per search) | — | [FEATURE] Add Windows Terminal as a split-pane backend for agent teams (`teammateMode`) |
| 24189 | (open per search) | — | [Feature Request] Add Ghostty as a split-pane backend for agent teams (`teammateMode`) |
| 26244 | (open per search) | — | Split-pane agent teams blocked on Windows by isTTY gate overriding `teammateMode: "tmux"` |

### Spawn-side

| # | State | Opened | Title |
|---|---|---|---|
| 88849 | OPEN | 2026-08-22 | Agent tool: passing `name:` creates teammate that never runs … |
| 93624 | OPEN | 2026-09-11 | [Bug] macOS: teammate spawn 'fork failed: Device not configured' … |
| 90332 | OPEN | 2026-08-28 | [BUG] `--resume` sessions register the agent-team hub under stale … |
| 90453 | OPEN | 2026-08-28 | [DOCS] agent-teams Limitations: `/rewind` does preserve in-process teammates, contradicting documented claim |

Population sizes, for calibration of how systemic this is:
`teammate in:title` → **299**; `"agent teams" in:title` → **293**; `"shutdown_request"` → **95**;
`idle in:title` → **512** (mostly unrelated).

---

## 7. Documented expectation vs the fleet's expectation

**The fleet's expectation**, as stated in the brief and in `skills/agent-teams/SKILL.md`: *a
teammate that is done, idle, or has returned its result closes down gracefully by itself.*

| Axis | What Anthropic DOCUMENTS | What the FLEET expects | Verdict |
|---|---|---|---|
| Teammate finishing a task | Goes **idle**; "the teammate stays running and addressable while hidden"; self-claims the next task | Closes down by itself | **CONTRADICTED.** Idle is a resting state by design, not a pre-exit state. |
| Who initiates shutdown | The **lead or operator**, by name, in natural language. "The lead sends a shutdown request." | The teammate self-closes on completion | **CONTRADICTED.** Shutdown is always externally initiated in the docs. |
| Whether shutdown is guaranteed | No. "The teammate can approve, exiting gracefully, **or reject with an explanation.**" | Graceful close-down is the expected outcome | **CONTRADICTED.** Refusal is documented, expected behaviour. |
| Shutdown latency | "Shutdown can be slow: teammates finish their current request or tool call before shutting down" — a listed **Limitation** | Prompt close-down | **DOCUMENTED AS SLOW.** A teammate that hasn't closed yet may be behaving correctly. |
| `TeammateIdle` hook's power | **Only to PREVENT idle.** Exit 2 → "Blocks the idle state; the teammate continues working". `shouldContinue: true` → keeps working. | Hook closes the pane | **OPPOSITE POLARITY.** No documented field or exit code on this event ends a teammate. Pane-closing is outside the specified contract. |
| Documented way to end a teammate programmatically | **`TaskStop`** — a tool the LEAD calls, taking an agent id or name. Not a hook. | `shutdown_request` + a `TeammateIdle` hook | **A DOCUMENTED PATH EXISTS AND THE FLEET DOES NOT USE IT.** Worth a trial. #74638 (open) disputes that it works. |
| Cleanup trigger | **Session exit.** "cleanup happens automatically when the session exits"; "The team config directory is removed when the session ends." | Per-teammate cleanup at completion | **CONTRADICTED.** No documented per-teammate cleanup event. |
| Pane disposal on shutdown | **Undocumented in prose.** Intent recoverable only from CHANGELOG 2.1.250 ("Fixed … panes sometimes staying open after acknowledging a shutdown request"). Vendor ships a **manual** `tmux kill-session` remedy. | Pane closes automatically | **UNDOCUMENTED; INTENT AGREES.** Fleet's expectation matches vendor *intent*, matches no vendor *sentence*. |
| Closing a pane from outside | Documented (#24385) as **corrupting** Claude Code's internal pane tracking; next spawn fails with `Session '<old-pane-id>' not found`; recovery = restart Claude Code | Fleet's `TeammateIdle` hook closes panes | **ACTIVELY HAZARDOUS.** The fleet's remedy is the repro's second step. Highest-value finding here. |
| kitty as a pane backend | **Named nowhere.** Supported list is tmux + iTerm2; explicit exclusions are VS Code, Windows Terminal, Ghostty. `"iterm2"` mode "requires the `it2` CLI". | `teammateMode: "iterm2"` via a kitty shim | **UNSUPPORTED CONFIGURATION.** The 2.1.250 pane-close fix operates on a call path whose reach into a shim is unverifiable from docs. |
| `TeammateIdle` scoping | "no matcher support — always fires on every occurrence" | A fleet hook that closes panes | **NO FILTER.** Every idle of every teammate. Gating must be in the hook body on `agent_id`/`agent_type`. |
| Which process runs `TeammateIdle` | **UNDOCUMENTED.** Stated for subagents ("Hooks from settings files … also run inside subagents"); teammates' inherited context is listed as "CLAUDE.md, MCP servers, and skills" — **hooks not named**. | Assumed (implicitly, by having the hook close a pane) | **UNDOCUMENTED — MEASURE IT.** |
| Suppressing idle notifications | **Impossible.** `Notification` exit 2 "isn't honored; the notification is already sent". Open issue #92891 asks for exactly this. | — | **NOT AVAILABLE.** No hook-level remedy exists. |
| Version remedy | The shutdown/pane fixes (2.1.250, 2.1.251, 2.1.257) are all **BELOW** 2.1.260. Fixes above 2.1.260 touch hook context, trust, `/tui`, `SubagentStop` matcher — not shutdown. | — | **UPGRADING WILL NOT FIX THE PANE.** The fleet already has that fix. |
| A teammate marked "complete" being final | No. Resume "starts a new run of the agent under the same ID, so a subagent that had already failed or completed shows as running again" | Done = done | **CONTRADICTED.** Completion is re-enterable by design. |
| Model as a variable | Open issue **#81807: "Opus subagents ignore `shutdown_request` while emitting `idle_notification`"** | Not considered | **UNEXAMINED AXIS.** Fleet defaults to Opus 5. Cheapest untried experiment in this whole report. |

---

## 8. Documented-silence register

Stated as *undocumented* rather than inferred, per the brief:

1. **Which process executes `TeammateIdle`** (lead vs teammate). Stated for subagents only.
2. **Whether a teammate's own `SessionEnd` fires** in its process on shutdown. A teammate is "a
   full, independent Claude Code session", so it is the natural reading — but unstated.
3. **What happens to a split-pane teammate when the lead exits.** The "can't outlive the lead's
   process" sentence reasons only about *in-process* teammates' background work.
4. **Whether `TaskStop` on a split-pane teammate closes its pane.**
5. **`shouldContinue`'s schema position** — top-level or under `hookSpecificOutput`. Named in the
   `TeammateIdle` prose, row truncated in the common-fields table.
6. **Any idle timeout or eviction policy for teammates.** No setting containing `idle` exists
   besides `askUserQuestionTimeout` (a question timeout, unrelated). #89515 confirms the absence.
7. **kitty**, in any capacity.
8. **The `shutdown_request` / `shutdown_approved` wire format.** The docs describe the English
   trigger and call them "structured protocol message[s] such as a plan approval or shutdown
   request", but publish no schema.
9. **`teammateMode`'s settings-reference entry** — cited by anchor, not reachable in this pass (see
   § 4); the truncation is the fetcher's, so treat this as *unverified here*, not *absent upstream*.

## 9. Two internal contradictions inside the vendor docs

Recorded because the fleet has live code depending on one side of each:

1. **`TaskCompleted` exit 2.** agent-teams: *"Exit with code 2 to prevent completion and send
   feedback."* hooks.md per-event table: *"Exit code 2 isn't honored; the task is already
   completed."* The fleet's `task-quality-gate.sh` rejects tasks on typecheck failure and therefore
   depends on the agent-teams reading. **One run decides it.**
2. **`SubagentStop` stopping control.** Per-event table: *"Exit code 2 isn't honored; the subagent
   already finished."* Common-fields table on the same page: `continue: false` *"for `Stop` and
   `SubagentStop` … prevent stopping and continue the conversation"*, plus `stopReason` and
   `suppressOutput` both scoped to `SubagentStop`. Either exit 2 and `continue:false` differ in
   power on this event, or one table is stale.

## 10. The three cheapest experiments this pass could not run

Docs-only slot; these are handoffs, not omissions.

1. **Does the kitty shim implement pane *kill*?** `grep -n -iE 'kill-pane|kill_window|close' <shim>`
   against the tmux-command subset it translates. If spawn is implemented and kill is not, the
   fleet's symptom is fully explained post-2.1.250 with the vendor fix present and correct.
2. **Which process runs `TeammateIdle`?** Have the hook append `$$ $PPID $PWD $CLAUDE_CONFIG_DIR`
   to a file; compare against the known lead pid.
3. **Is it the model?** (#81807) One Sonnet teammate and one Opus teammate in one team; send both a
   `shutdown_request`; compare. The fleet runs Opus 5 by default and has never varied this.

---

### Sources

- <https://code.claude.com/docs/en/agent-teams>
- <https://code.claude.com/docs/en/sub-agents> and <https://code.claude.com/docs/en/sub-agents.md>
- <https://code.claude.com/docs/en/hooks> and <https://code.claude.com/docs/en/hooks.md>
- <https://code.claude.com/docs/en/tools-reference.md>
- <https://code.claude.com/docs/en/cli-reference.md>
- <https://code.claude.com/docs/en/settings-reference> / <https://code.claude.com/docs/en/settings.md> (both truncate before `teammateMode`)
- <https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md>, plus pinned tags `v2.1.245` and `v2.1.266`
- GitHub issues API, `repo:anthropics/claude-code`: [#24385](https://github.com/anthropics/claude-code/issues/24385), [#74638](https://github.com/anthropics/claude-code/issues/74638), [#76500](https://github.com/anthropics/claude-code/issues/76500), [#81807](https://github.com/anthropics/claude-code/issues/81807), [#81464](https://github.com/anthropics/claude-code/issues/81464), [#89515](https://github.com/anthropics/claude-code/issues/89515), [#92891](https://github.com/anthropics/claude-code/issues/92891), [#92244](https://github.com/anthropics/claude-code/issues/92244), [#29271](https://github.com/anthropics/claude-code/issues/29271), [#27639](https://github.com/anthropics/claude-code/issues/27639), [#79016](https://github.com/anthropics/claude-code/issues/79016), [#24108](https://github.com/anthropics/claude-code/issues/24108), [#38116](https://github.com/anthropics/claude-code/issues/38116), [#85047](https://github.com/anthropics/claude-code/issues/85047), [#88503](https://github.com/anthropics/claude-code/issues/88503), [#24292](https://github.com/anthropics/claude-code/issues/24292), [#24301](https://github.com/anthropics/claude-code/issues/24301), [#24384](https://github.com/anthropics/claude-code/issues/24384), [#24189](https://github.com/anthropics/claude-code/issues/24189), [#26244](https://github.com/anthropics/claude-code/issues/26244), [#90453](https://github.com/anthropics/claude-code/issues/90453)
- <https://github.com/jLAM-ERR/kitty-extensions> (community tmux→kitty shim; the class of thing the fleet runs)

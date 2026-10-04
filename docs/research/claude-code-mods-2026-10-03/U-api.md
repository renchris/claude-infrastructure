# U-api: Claude Code mods API, ground truth for 2.1.287-2.1.289

Labels: **M** means measured (the command is named). **I** means inferred (the method is named). **D** means the official docs or source say it, without a run here.

## 0. Toolchain probe: binaries, validate, test
- Binary used (M): `/tmp/mods-research/cc289/node_modules/@anthropic-ai/claude-code/bin/claude.exe`. `--version` printed `2.1.289 (Claude Code)`. It came from `npm install --prefix /tmp/mods-research/cc289 @anthropic-ai/claude-code@2.1.289`. On npm, `latest` is 2.1.289 and `stable` is 2.1.285 (`npm view … dist-tags`).
- Probe: `/tmp/mods-research/probe/token-weather`. It holds the guide's manifest, hooks.json, module, types contract and test, copied verbatim.
- `CLAUDE_CONFIG_DIR=/tmp/mods-research/cfg-probe <bin> plugin validate …` gave **exit 0** (M). Output is in `/tmp/mods-research/probe-validate.out`:
  ```
  ❯ types ./types/index.d.ts declares on $: nothing (no EngineInterface member)
  ❯ types ./types/index.d.ts declares state: token-weather.readings
  ❯ ./token-weather.mjs hooks: session.start, turn.complete, ui.render{component=AbovePrompt}
  ❯ ./token-weather.mjs calls: $.session.usage (via takeReading), $.state.get, $.state.set (via takeReading), $.ui.resolve
  ❯ ./token-weather.mjs state writes/reads: token-weather.readings
  ✔ Validation passed
  ```
- `… plugin test …` gave **exit 0** (M): `(pass) token-weather > the band follows the context window [42.81ms] / 1 pass 0 fail`. Output is in `probe-test.out`.
- Both commands work **unauthenticated and headless**: an empty config dir, no login, stdin `/dev/null` (M).
- `claude -p "say hi" --plugin-dir … --debug-file …`, unauthenticated, exited 1 with "Not logged in" (M). Even so, the debug log `/tmp/mods-research/probe-p.debug` shows the mod working in the `-p` path. It shows `hooks module token-weather@inline loaded (worker, environment 1, tier user)`, `session.start settled in 10.6ms`, and `turn.complete settled in 3.6ms`. So mods load and fire under `-p` (M).
- Side effect (M): loading the mod **writes into the plugin folder**. It wrote `.claude-plugin/types/{claude-code,claude-code-tools,claude-code-mcp}/index.d.ts`, `types/tsconfig.json`, and `types/.gitignore` (which contains `*`). It also wrote **`tsconfig.json` at the plugin root**, which is not gitignored. A copy of the 2.1.289 declarations (15,197 lines) is at `/tmp/mods-research/types-289/`.

### The pinned fleet build (2.1.284) already contains the engine
These runs used `/Users/chrisren/.claude-284/…/claude.exe` with fresh mktemp dirs. Logs are in `/tmp/mods-research/probe284*/p.debug`.
- With no env var (M): `installed plugins' hooks modules not loaded: rollout flag (tengu_plugin_hooks_modules) is off … (early access: set CLAUDE_CODE_ENABLE_FUNCTION_HOOKS=1 …)`. The built-ins (agents-md, telemetry) still load.
- With `CLAUDE_CODE_ENABLE_FUNCTION_HOOKS=1` (M): the mod loads in the user tier, and `session.start` and `turn.complete` fire. `plugin validate` passes. `plugin test` passes, but only with the env var. Without it, it prints "hooks modules are not turned on in this build yet".
- The bundle code differs by version (M, read from the binaries):
  - 2.1.284: `hooksModulesFlagDefault=()=>!1`, overridable through `CLAUDE_CODE_ENABLE_FUNCTION_HOOKS`.
  - 2.1.289: `var _K="tengu_plugin_hooks_modules";var IIe=!0;XD=()=>!Nt()&&k(_K,IIe)`, so the default is **on**.
- API added in 289 over 284 (M, by diffing the two d.ts files): `mcp.connect`, `prompt.compose`, `session.append`, `ui.fault`, `ui.selection`. The 289 CHANGELOG adds `agent.spawn` for teammates, one agent id across all events, and the idle and waiting states.

## 1. What a mod is and how one is enabled
- A mod is a plugin whose `hooks/hooks.json` contains `"modules": ["./x.mjs"]` (exactly one module; the same file may also hold settings `hooks`). The module exports `register(on, options)` and registers hooks with `on(pattern, matcher?, ($, e, next) => …)`. A pattern can be an event name, `*`, `classic.*`, or `!name` (index.d.ts PluginRegisterUses). Each hook can observe (`await next(e)`), rewrite (`next({...e})`), or answer (return without calling `next`).
- Ways to enable a mod (D, reference.md §Settings/§Commands):
  - Installed plugins through `enabledPlugins` or `/plugin` (marketplace plus install).
  - `--plugin-dir <dir>`, which can be repeated and is hot-reloaded on save. It is provenance `@inline`, user tier.
  - `CLAUDE_CODE_PLUGIN_DIRS=/a:/b`, in the env or in `env` in settings.json. It acts like `--plugin-dir`.
  - `CLAUDE_CODE_PLUGIN_DIR_WATCH=1`, which reloads mods on save in long-running non-interactive sessions.
  - A per-session "dev-mods" folder (`join(<dir>,"dev-mods")`). It is used when Claude writes a mod for you. This path needs a person-only consent prompt, "Enable hot reloading for this session?". In headless runs that prompt resolves to `no_one_to_ask` (strings in the binary). Do not use this path unattended.
- What turns mods off (2.1.289 refusal list, M from the binary). Each item is a `refusal:` tag:
  - `diskless`
  - `hooks_modules_off` (the GrowthBook flag)
  - `all_hooks_disabled` (policy `disableAllHooks`)
  - `sideload_disabled`
  - `local_dirs_blocked`
  - `managed_hooks_only`
  - `hooks_disabled_in_settings` (user `disableAllHooks` also counts)
  - `safe_mode` (`--safe-mode` or `CLAUDE_CODE_SAFE_MODE`)
  - `bare_mode` (`--bare`)
  - `untrusted` (a workspace the user has not trusted)
- Built-in mods are not affected by any of these switches (D). Anthropic can also turn installed mods off remotely with the flag (D).
- The repo's settings-templates, `lib/` and `handoff-fire.sh` set none of the gating keys: no `disableAllHooks`, `enabledPlugins`, `--bare` or the others (M, grep).

## 2. Load order, tiers, and sec-default
- The chain has five tiers, outermost first: `prepend` (managed `prependPlugins`), `user` (anything a person installs or adds with `--plugin-dir`), `append` (managed `appendPlugins`), `builtin`, `core` (index.d.ts `TIERS`).
  - Within the user tier, a mod runs before the plugins it lists under `dependencies`. Within one module, hooks run in the order `on` was called (D, events.md).
  - On a machine with no managed settings, a non-Team/Enterprise user may set `prependPlugins` and `appendPlugins` in user settings (D, reference.md).
- Settings hooks in the chain (D, events.md):
  - **Managed** PreToolUse hooks run above every mod, and their block is final.
  - **All other settings and plugin PreToolUse hooks run inside core**, below the last mod's `next`. So a mod that answers `tool.call` without calling `next` skips them entirely.
  - A `tool.check` hook can **approve a call that those hooks blocked**.
  - This is relevant to the fleet's ~98 shell hooks: with no sec-default seated, a user mod outranks them.
- sec-default:
  - When it loads (M): `cc-plugin-sec-default@builtin not seated: no managed settings and not a Team or Enterprise organization`. `/Library/Application Support/ClaudeCode/` does not exist (M), so it is not seated on these Max accounts (I, based on that debug line).
  - What it does (source: `github.com/anthropics/claude-code/blob/2bfb629/mods/sec-default/hooks/register.ts`):
    - It forwards past the user tier with `next.to(e,'append')` on `classic.*`, `prompt.section/context/compose`, `skill.prompt`, `attribution.text` and `settings.read`.
    - It guards `tool.describe/command.describe/agent.offer/agent.spawn` for subjects the organization provides.
    - It refuses a user-tier `tool.register` while there is an MCP allowlist.
    - It re-runs `tool.check` without the user tier so that settings **deny rules hold** over a user mod's allow.
    - It refuses user-tier modules at `plugin.register` when `allowManagedModsOnly` is set.
    - Its two options live under managed `pluginConfigs["cc-plugin-sec-default@builtin"].options`.
  - Everything else passes through it, including `tool.call`, `prompt.submit`, `fs.*`, `http.fetch`, `process.run` and `model.*` (sec-default/README.md).
- Built-ins in 2.1.289 (M, strings): `cc-plugin-{agents-md, diff, telemetry, sec-default, plugin-authoring, mods-guide, you-should-know, claude-test, mermaid, responsive-mode, tips}`. The diff mod loads only in interactive terminals (D). It did not load in the `-p` probe (M).

## 3. Events (2.1.289 `EngineEventOf`, index.d.ts:3838-4320)
- **Tools**
  - `tool.call` carries `{tool, tool_use_id, …tool input fields, agentId?}`. It can return `{deny}`, `{result}`, `{result, context[]}`, or a rewritten `e`. Core's result has `{result, text, isError, isReadOnly, ref}`.
  - `tool.check` carries `{tool, input, tool_use_id?}` and returns `{decision:'allow'|'ask'|'deny', reason?, rule?}`. It fires after `tool.call` and PreToolUse, before the mode settles an ask.
  - `tool.describe` returns `{description, isDeferred}` (cached).
- **Prompt**
  - `prompt.submit` carries `{text, attachments?, context?[], turnId?, wait, origin}`. It returns a rewrite, `{drop}`, or adds `context`.
  - Also: `prompt.fill`, `prompt.suggest`, `prompt.edit` (keystrokes), `prompt.section` (each system-prompt section; `{text:null}` drops it), `prompt.context` (first-message context blocks), `prompt.compose` (the whole system-prompt section list), `prompt.attachment` (system reminders; `{text:null}` drops one).
  - `skill.prompt`, and `attribution.text` (with `kind`: commit / pr / …).
- **Turns**
  - `turn.start` carries `{text, turnId}`. It is observe-only and its type has **no `agentId`**. The guide's `e.agentId` check on turn.start is therefore dead (I, from the type).
  - `turn.step` is a streaming generator for each model request, main or subagent (`agentId`). It can swap `model` or `effort` per request, or answer without calling the API.
  - `turn.complete` carries `{answer, durationMs, isAborted, turnId, agentId?, usage?, reason:'answer'|'aborted'|'refusal'|'error'}`. Returning `{text}` shows a line under the answer.
- **Session**
  - `session.start` carries `{cwd, surface|null, isInteractive}`. It fires per mod load or reload, not on `/clear`.
  - `session.end` carries `{reason, sessionId, resume}`. All its hooks together get 1.5 s.
  - `session.compact` carries `{trigger, instructions, messages}`. It can rewrite, or skip with `{skip}`.
  - `session.measure` carries `{context, rateLimits[{kind, percentUsed, resetsAt}], cost{usd}, changed[]}`. It fires after each main turn and on every whole-point rate-limit move. **This is the push form of usage.**
  - Also: `session.receive` (a peer or relay message; `{consumed}` swallows it), `session.send` (SendMessage; rewrite or refuse), `session.append` (every transcript row before it is stored, so rows can be **scrubbed for the model and the transcript file**), `session.attach`, `session.detach`.
- **Agents**
  - `agent.offer` returns `{isOffered:false}`.
  - `agent.spawn` carries `{tool_use_id, prompt, description, subagentType, model?, isTeammate?, …}`. It returns `{model}` or `{deny}`.
- **Commands and config**: `command.run` (answer with `{text}`), `command.describe` (`isHidden`), `config.set` (`{deny}` or clamp), `config.describe`.
- **UI**: `ui.render`, `ui.resolve`, `ui.press`, `ui.input`, `ui.select`, `ui.message` (Client posts), `ui.fault`, `ui.scroll`, `ui.focus`, `ui.close` (see the reference).
- **Meta**:
  - `plugin.register` carries `{name, tier, root, version, provenance, uses{events, calls, env, state}}`. It returns `{refuse}`.
  - `engine.create` can add or withhold `$` nouns.
  - `telemetry.log` and `telemetry.mark` (a user mod must use the `{to:'collector'}` filter).
- **Every `$` method is also an event** (`OpEventOf`: `fs.read`, `http.fetch`, `process.run`, `model.complete`, `ui.toast`, …). A mod placed above another mod can audit, deny (`{deny}`) or answer (`{value}`) that mod's calls.
- **Classic events** (`classic.<Name>`, `e` is the settings hook's stdin JSON; result is `ClassicResult` at index.d.ts:1160-1320). There are 33:
  - Tools: PreToolUse, PostToolUse (`updatedToolOutput`), PostToolUseFailure, PostToolBatch.
  - Permissions: **PermissionRequest** (`decision:{behavior:'allow'|'deny', updatedInput, updatedPermissions}`), PermissionDenied (`retry`).
  - **Notification**.
  - Prompt: UserPromptSubmit, UserPromptExpansion.
  - Session: SessionStart, SessionEnd, Setup.
  - Stop and subagents: Stop, StopFailure, **SubagentStart, SubagentStop**.
  - Compaction: **PreCompact, PostCompact**.
  - Model: **PreModelSwitch, PostModelSwitch**.
  - Teams and tasks: **TeammateIdle**, TaskCreated, TaskCompleted.
  - MCP elicitation: Elicitation, ElicitationResult.
  - Config and files: ConfigChange, InstructionsLoaded, CwdChanged, FileChanged, DirectoryAdded.
  - Worktrees: WorktreeCreate, WorktreeRemove.
  - Display: MessageDisplay.
  - Classic events fire "whether or not any settings hook is configured".

**Answers to the specific questions:**
- Permission event: yes, through `tool.check` and `classic.PermissionRequest` / `classic.PermissionDenied`. Notification: only `classic.Notification`. Compaction: `session.compact` plus `classic.Pre/PostCompact`. Subagent start/stop: `agent.spawn` and `classic.SubagentStart/Stop`, plus `turn.complete` with `agentId`.
- Idle: **there is no session-idle event.** The closest are `classic.TeammateIdle`, `classic.Stop`, `turn.complete`, and the `AbovePrompt.props.isWorking` / `PromptHint.props.isWorking` render props (I).
- Model/effort change: `classic.Pre/PostModelSwitch`, plus a per-request rewrite in `turn.step`. Usage: `session.measure` (push) and `$.session.usage()` (pull).

## 4. `$` namespaces (CoreEngineInterface, index.d.ts:2232-3509)
- `plugin` `{name, root}`.
- `ui`: notice(tool_use_id, text), invalidate, blit, resolve, log(`{to:'debug'}`), ask, toast, status, open, close, panes, scroll, focus, copy, selection.
  - `ask` uses AskUserQuestion and **rejects in `-p`**.
- `model`: complete(`{model, prompt, system, maxTokens, effort}`, using the session's own credentials), fork (reuses the main transcript's cache prefix), classify(text, labels).
- `audio`: play (afplay), speak (`say`).
- `mcp`: call(server, tool, args), with **no permission prompt**; connect.
- `session`: messages(`{agentId?, as:'api'?}`), cwd, root, model, turns, id, repo, surfaces, usage(`{breakdown}`), version, compact, send(`{to:{sessionId}|{agentId}|name, text}`), append, authorize (an opaque credential handle for first-party `$.http`).
- `turn.abort({turnId})`.
- `prompt`: submit (starts a turn when idle), read, fill, suggest, compose.
- `tool`: list, call (goes through the hooks and the permission dialog), check, **register(`{name, description, inputSchema}`) → `mcp__<plugin>__<name>`**. You serve it with a `tool.call` hook. It is available from the next prompt and must be called in or after `session.start`.
- `command`: list, run, register(`{name, description, argumentHint, immediate}`).
- `config`: list, set.
- `telemetry`: log, mark.
- `agent`: spawn (always background; returns `{agentId}`), list (`{id, teammateId, type, status, parentId, …}`), **register** (defines an agent type `<plugin>:<name>`).
- `fs`: read (text or bytes), **write(path, text)** (any absolute path, creates directories), list, exists, stat(`{resolve}`), ancestors.
  - Each read or write is capped at 4 MiB. Network paths are refused. The only scoping is whatever an `fs.*` hook above the mod enforces.
- `store`: get, set, delete, keys. It is persistent JSON (4 MiB total) under the user's config dir, so with one config dir per account it is **per account** (I).
- `state`: get, set. Host-held per session, survives a hot reload. A get made while rendering subscribes that drawing to redraws. Keys must be declared in `PluginState`.
- `clock`: now, sleep (counts against the budget), after, every.
- `http.fetch(url, {method, headers, body, auth, socketPath})`. It goes through the host, any host, subject to the organization's web-fetch policy.
- `process`:
  - `run(argv, {cwd, env, stdin, timeoutMs})` runs with no shell. Default timeout 30 s, max 10 min, 4 MiB per output stream. "Git runs with repo hooks off". CLI only.
  - `spawn` streams the child and keeps it alive as long as the loop runs.
- `settings.read({source})`, read-only.
- `env.get` / `env.set`. Names must be literals. `set` changes the env of the CC process and of every child started afterwards.

Can a mod write files outside its folder, or run processes? **Yes to both.** It can also register **a tool the model calls**, and **a subagent type**.

## 5. Render sites
`RenderComponent` (index.d.ts:8841): `AskUserQuestion, UserMessage, AssistantMessage, ToolUse, ToolResult, ToolGroup, ToolProgress, CommandOutput, Spinner, TurnDuration, InfoNotice, SessionMode, PromptHint, AbovePrompt, Pane`.
- A hook can wrap, replace, or rewrite the props of tool rows, tool results, messages, the spinner word, and footer mode labels. It can add a `tail` to the hint line or replace it.
- **The permission dialog cannot be drawn by a mod**: "drawn by the engine alone". The most a mod can do is add one line under it with `$.ui.notice`.
- The **settings `statusLine` is not a render site.** `$.ui.status` adds one pinned line per plugin under the prompt, so `statusline.sh` cannot be replaced or restyled through mods (I, from the component list).
- Element tables (M, binary `Nz`):
  - terminal: Box, Text, Button, Input, Select, Link, Code, Markdown, Client, Raster, Image.
  - desktop: the same set without Raster and Image, plus Svg.
  - mobile and vscode: smaller sets.
- Panes are docked from 110 columns in fullscreen and placed unasked from 144 columns. In `-p` every pane counts as placed, but nothing draws.

## 6. Limits and runtime
- Budgets (index.d.ts HookBudget; reference.md §Limits):
  - 10 s of the hook's **own** time per dispatch. Time inside `next` or any `$` call does not count, except `$.clock.sleep`.
  - `.catch` handler: 1 s. Linger after an abort: 5 s. All `session.end` hooks together: 1.5 s.
  - A hook that times out is treated as absent: `next(e)` runs on its behalf, so it **fails open**.
- Environment: a separate worker ("worker, environment 1", M). ES modules only, **no Node, no DOM, no `require`, no dynamic `import()`**. Web APIs only (URL, TextEncoder, crypto.subtle). Every fs, network or process call goes through `$`.
- The announcement says mods are "not sandboxed", meaning that `$` has the same access to the machine as CC.
- `plugin test` runs its tests with no fs, network or process access, and 5 s per test.

## 7. Where mods run
- Hooks run in the terminal, in Desktop, in VS Code (no drawing there), in `claude -p` and the Agent SDK (no drawing), in Remote Control, and in cloud sessions (D, overview.md §Where mods run). For `-p`, M on both 284 (with the env var) and 289.
- **Subagents, forks, and in-process teammates** run in the same process. Their `tool.call`, `turn.step` and `turn.complete` events carry `agentId` (index.d.ts AgentLoop).
- A **teammate in a terminal pane "runs no loop here"** (index.d.ts:131-132). It is its own process, and it gets mods only if that process loads the plugin (I).
- Every account process loads mods from its own `CLAUDE_CONFIG_DIR` settings and plugins, and from `CLAUDE_CODE_PLUGIN_DIRS` (I).

## Concerns and deviations
- The fleet is pinned to 2.1.284. Mods would run there only with `CLAUDE_CODE_ENABLE_FUNCTION_HOOKS=1`, and that build lacks the 285-289 fixes, including "installed mods not loading in first session after upgrade" and several crashes from UI errors (CHANGELOG).
- Live behaviour in authenticated, interactive, Agent Teams sessions was **not** tested. That would need a real session, which the brief forbids.
- I did not read the repo's `.claude/rules`, because this task was about the external API.
- The `tsconfig.json` written at the plugin root would show up as an untracked file if a mod lives inside a git repo.

Sources:
- Docs: `/tmp/mods-research/docs/*.md` (from code.claude.com/docs/en/plugins/mods/*).
- Built-in mod source: `/tmp/mods-research/cc-repo/mods`.
- Changelog: `/tmp/mods-research/changelog-285-289.md`.
- Binary strings: `/tmp/mods-research/cc289-strings.txt`.

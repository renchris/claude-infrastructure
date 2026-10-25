# S10: hooks and preservation (CC 2.1.293)

Slot: S10-hooks-and-preservation · 2026-10-25 · read-only. Nothing was written except this file and
helper scripts under /tmp/mtam/S10/. No keychain reads, no pane interaction, no claude launch.

## Method

- Source: `/tmp/mtam/cc293-src.js` (52,710,919 bytes, `ls -la`). Every read used `python3 -I`
  with `re.finditer` and printed byte windows. The helper is `/tmp/mtam/S10/g.py PATTERN [ctx] [limit]`.
- Repo: `grep -n` and bounded `sed -n` ranges only. handoff-fire.sh is 21,855 lines, lr-handoff.sh
  2,464, lr-team.sh 95, lr-move-worker.sh 579, and bin/cc-lr 3,295 (measured with `wc -l`).
- Hook registrations: `jq` over `~/.claude/settings.json`, printing event, matcher, script basename,
  timeout and async flags only. No env or secret fields were printed.
- Rules read: `.claude/rules/agent-operating-lessons*.md`, grepped for hook, recycle and teammate
  lessons. The relevant ones are "A deny is a turn boundary" (situational:65), "Lead can't exit
  unattended" (:161) and "Clean+landed is not nothing in hand" (:167).

Commands run, with their key output:

1. `g.py '"PreToolUse","PostToolUse"' 600 5` found 10 hits. The canonical event array is `lh` at
   byte 2271130, duplicated as `JH` at 2939166.
2. Printed the window `d[8687263-9000 : +300]`. It holds the full hook-output zod schema `wQ`
   (`continue`, `suppressOutput`, `stopReason`, `decision`, `reason`, `systemMessage`,
   `terminalSequence`, `hookSpecificOutput` union) plus the async form `Bee`
   (`{async:true, asyncTimeout}`).
3. Grepped `describe("…Timeout…")` and found the command/prompt/mcp/http/agent hook schemas at
   2296564–2301349. `timeout: v().positive().optional()` is in seconds, and I found no upper bound
   in the schema.
4. `g.py '[,; ]sd=…'` found `var sd=600000,bVe=30000,T2t=6000,wVe=30000,Uon=5000` at 12575678.
   `sd` is the default command-hook timeout.
5. `g.py 'timeout\*1000:'` gives the per-type defaults: command `Jn=e.timeout?e.timeout*1000:sd`
   @12631966, prompt `:30000` @12560190, agent `:60000` @12571101, http `:g` (g defaults to sd)
   @12579520, async hook `asyncTimeout:e.timeout?…:sd` @12628639, and the generic dispatcher
   @12676351.
6. `hook_event_name:"PreToolUse"` @12714698 is `lOe()`, which builds the input and runs `ZA()`.
   `hook_event_name:"PostToolBatch"` @12716338 is `lSn()`.
7. `preventContinuation:!0` @12694040 is the dispatcher path that yields
   `{preventContinuation, stopReason}` from `continue:false`, and `blockingError` turns into a
   "deny". The Stop-loop consumer @18090583 shows `continue:false` ending the loop with
   `hook_stopped_continuation`.
8. `hook_event_name:"ConfigChange"` @12592983, `FileChanged`/`CwdChanged` @12594983 (these return
   only watchPaths and systemMessages), and `PreModelSwitch` @12597210 (its result can block a
   model switch, default timeout `wVe`=30 s).
9. `CLAUDE_ENV_FILE` @10229580. The session-env script it loads is a shell prefix for Bash-tool
   commands, not a mutation of the CC process's own env.
10. Settings-change handler @18402674:
    `if(e.settings!==i.settings){ wst(),Une(),vst(),TTt(), e.settings.env!==i.settings.env&&ms()&&zP() …}`
    with the log text "Failed to apply settings change (clear auth caches / re-apply env)".
    `wst` @4635146, `Une` @4643524, `vst` @4643744 and `TTt` @4648692 clear the apiKeyHelper,
    AWS/GCP and refresh caches. `zP()` is `applyConfigEnvironmentVariables`, which does
    `Object.assign(process.env, filterSettingsEnv(...))` @5273605.
11. Hooks config snapshot: `M1(o){Eo(o),e().store(n()),nQ()}` @5539380 (export
    `updateHooksConfigSnapshot`). `M1({userLayer:"retain"})` is called from `YHt`, "Settings
    changed from ${a}, updating app state", @19649759.
12. `wA()` @4658281. The non-backend path stats `<configDir>/.credentials.json`. On failure it calls
    `Jf()`, which clears the cache and re-reads via `Ya()`. A changed mtime calls `ox()` and `Xf()`,
    which emits credentialsChangedOnDisk.
13. "Background work is running" modal @33564794. Its subtitle is "The following will stop when you
    exit:".
14. The resume-time orphan notice `${e} didn't finish before the previous session ended` @26050341
    sits beside `iAr(e,{carriedCrons:n=!1})`.
15. The hooks registered in `~/.claude/settings.json` (the same file is symlinked into
    `~/.claude-next` and `~/.claude-quaternary`, per `ls -la`) are listed in the appendix.

## Part A: hook events and what each can return

The event list comes from `lh` @2271130, which matches `JH` @2939166. There are 33 events:
PreToolUse, PostToolUse, PostToolUseFailure, PostToolBatch, Notification, UserPromptSubmit,
UserPromptExpansion, SessionStart, SessionEnd, Stop, StopFailure, SubagentStart, SubagentStop,
PreCompact, PostCompact, PreModelSwitch, PostModelSwitch, PermissionRequest, PermissionDenied,
Setup, TeammateIdle, TaskCreated, TaskCompleted, Elicitation, ElicitationResult, ConfigChange,
WorktreeCreate, WorktreeRemove, InstructionsLoaded, CwdChanged, FileChanged, DirectoryAdded,
MessageDisplay.

Every hook may return the common fields of `wQ` @~8684000–8687263: `continue` (false stops Claude
after the hook and sets `preventContinuation`), `stopReason`, `suppressOutput`,
`decision: approve|block`, `reason`, `systemMessage` (a warning shown to the user), and
`terminalSequence` (notification and title OSCs only). A hook can also answer
`{async:true, asyncTimeout}` (`Bee`). Exit code 2 is a blocking error.

| event | hookSpecificOutput fields (schema @8687263 region) | live effect |
|---|---|---|
| PreToolUse | permissionDecision allow/deny/ask/defer, permissionDecisionReason, **updatedInput**, additionalContext | gates or rewrites ONE tool call. A deny comes back as that call's tool_result. |
| PostToolUse | additionalContext, classifierContext, updatedToolOutput, updatedMCPToolOutput | rewrites the result or adds context. `decision:block` feeds the reason back. |
| PostToolUseFailure | additionalContext | context only |
| PostToolBatch | additionalContext | fires once after a batch of tool calls, before the next model request |
| UserPromptSubmit | additionalContext, sessionTitle, suppressOriginalPrompt | can block the prompt or add context |
| UserPromptExpansion | additionalContext, suppressOriginalPrompt | same |
| SessionStart | additionalContext, initialUserMessage, sessionTitle, watchPaths, reloadSkills | runs at start, resume and clear only |
| Setup | additionalContext | — |
| PreModelSwitch | permissionDecision allow/deny/ask, reason | can block a /model switch (default 30 s, `wVe`) |
| PostModelSwitch | additionalContext | — |
| SubagentStart | additionalContext | — |
| Stop, SubagentStop | additionalContext | `decision:block` keeps the turn going (/goal is built on this). Capped by CLAUDE_CODE_STOP_HOOK_BLOCK_CAP (handoff-fire.sh:3250). |
| StopFailure | (none) | observational |
| PermissionRequest | decision {allow + updatedInput + updatedPermissions} or {deny + message + interrupt} | answers a permission prompt. `interrupt` aborts the turn. |
| PermissionDenied | retry | — |
| Notification | additionalContext | — |
| Elicitation, ElicitationResult | action accept/decline/cancel, content | MCP elicitation answers |
| CwdChanged, FileChanged | watchPaths | can only extend file watching |
| WorktreeCreate | worktreePath | — |
| MessageDisplay | displayContent | display-only rewrite |
| SessionEnd, PreCompact, PostCompact, TeammateIdle, TaskCreated, TaskCompleted, ConfigChange, WorktreeRemove, InstructionsLoaded, DirectoryAdded | no specific output; common fields only | ConfigChange can block a non-policy settings change (`s3r` @12592983) |

### Timeouts (measured from source)

- Command hook: `timeout` is in seconds and optional, with a positive-number schema and no maximum
  found. The default is `sd = 600000` ms, i.e. 10 min (@12575678, used @12631966).
- Prompt hook: 30 s default (@12560190). Agent hook: 60 s (@12571101). HTTP hook: `sd` (@12579520).
- Async hooks use `asyncTimeout = timeout*1000 or sd`. The fleet already runs `asyncRewake` hooks
  with timeout 14400 (mailbox-wake-arm.sh, idle-keepalive.sh in settings.json).
- On timeout the hook is cancelled (`hook_cancelled`, `timedOut:true` @12679015). For PreToolUse a
  cancelled hook is non-blocking, so the tool proceeds.
- SessionEnd has its own budget (`CLAUDE_CODE_SESSIONEND_HOOKS_TIMEOUT_MS`, @1835925).
- The hooks the fleet registers today on the boundaries that matter carry short timeouts:
  UserPromptSubmit `mailbox-drain.sh prompt` 5 s, PostToolBatch `post-tool-batch.sh` 10 s,
  PreToolUse `research-block.sh` (`*` matcher) 5 s. A script BODY can change without any settings
  edit because the file is re-exec'd on every fire. A longer timeout needs a settings edit. The
  hooks snapshot does appear to be refreshed on a settings change (`YHt` → `M1({userLayer:"retain"})`
  @19649759), but this was not tested live.

### Can a hook move this session at the next tool boundary without a restart?

The verdict is that a hook can be the trigger and the sequencing point, but not the mechanism.

1. **No hook output touches credentials, the config dir, or the CC process env.** The full output
   union is above. It has no `env`, credential, `configDir` or "re-read auth" field.
   `CLAUDE_ENV_FILE` and SessionStart env files only prefix Bash-tool subprocesses (@10229580). A
   hook is a child process and cannot set its parent's `process.env`.
   `CLAUDE_CODE_OAUTH_TOKEN` (which `m$()` reads first) and the FD token `eM()` can only change
   through CC's own code: the 401 handler `y$()` sets `process.env.CLAUDE_CODE_OAUTH_TOKEN` from
   the store @4662683, and so does the SDK `getOAuthToken` callback @4661783.
2. **What a hook CAN do is write the store CC already watches.** A command hook runs as the user
   with the session's `CLAUDE_CONFIG_DIR` in its env (`Xn={...as(),…}` @12631966), so it could
   rewrite the session's keychain item or `.credentials.json`. CC's own change-check then adopts the
   new token: `wA()` @4658281 (version probe, mtime, or stat-fail followed by `Jf()` clear and
   re-read), with the 401 recovery `y$()` as the backstop.
   - This is a store-level swap. It moves every session that shares that config dir's store, not
     "this session".
   - It also creates the refresh-token sharing hazard. Two stores holding one refresh token means
     the first refresh rotates it, the other store's refresh gets invalid_grant, and `jhr()` CLEARS
     that stored credential.
   - Whether `wA()` runs before every request is another slot's question. This slot only confirms
     the stat-fail path re-reads.
3. **The boundary itself buys little safety.** While a synchronous PreToolUse hook runs, the main
   loop is parked between the streamed assistant message and tool execution, so the main thread has
   no inference request in flight. But:
   - in-process subagents, background agents and workflows keep issuing requests in parallel, and
     PreToolUse also fires for subagent tool calls (`sN()` @11896963 attributes them by agent id);
   - a request in flight carries its bearer at send time, so a store swap at ANY moment only
     affects the next request. Pausing at a tool boundary is not needed for request integrity.
   - PreToolUse only fires if the model calls a tool. A text-only turn never reaches it.
     UserPromptSubmit (fires on every operator reply, which comes within seconds tonight),
     PostToolBatch (once per batch, before the next request) and Stop are denser boundaries.
4. **Limits.** The default command timeout is 600 s, and a per-hook value is uncapped by the schema.
   Concurrent tool calls each fire PreToolUse in parallel, so a swap hook must be idempotent and
   locked. A hook that blocks stalls only the main thread's tool loop, not subagents.
   `continue:false` ends the turn, so it must NOT be used. A deny would make the model see a
   failed tool call, which is visible disruption.
5. **Net.** A hook-triggered move is feasible only as "a hook performs, or signals a helper to
   perform, a store write that CC re-reads". Its quality is bounded by that re-read path (other
   slots) and by the shared-store and refresh-token hazards in (2). It needs no restart. The prompt
   cache is lost on any account change regardless (estimated: the cache is scoped to the
   organization, so it does not follow a token to another account).
   - Side lead found while reading: a settings.json change clears several auth caches and re-applies
     `settings.env` into `process.env` (@18402674 → `zP()` @5273605). This was NOT verified for
     `CLAUDE_CODE_OAUTH_TOKEN`, since `filterSettingsEnv` may strip credential vars
     (OF/dJt lists @2241119/@2242892). It also has no refresh token and would hit every session
     sharing that settings file. Recorded as a candidate only.

## Part B: what a restart kills and what the repo re-arms

The incumbent move is `/exit` followed by `claude --resume <same uuid>` on the target config dir, in
the same pane.

| state item | survives restart? | repo restores it? (file:line) | loss if not |
|---|---|---|---|
| Conversation/transcript | yes, via same-uuid `--resume` after transplant | yes: lr-handoff.sh:1972 `RCY_ARGS=(--recycle --transplanted-source --resume-launcher …)` | none |
| Turn in flight (streaming or tool loop) | NO, `/exit` aborts it | no. The repo WAITS instead: `hf_transcript_at_rest` handoff-fire.sh:3202, `wait:mid-turn` | the partial turn. Tonight it never comes to rest. |
| Composer draft (typed text) | no | yes: lr-move-worker.sh:314-358 `draft_gate`, handoff-fire.sh:5838 `hf_rcy_carry` (retyped unsent) | a pasted block `[Pasted text #N]` is NOT carryable: HELD:draft (lr-move-worker.sh:353) |
| /goal (session-scoped Stop hook) | yes when unmet on a same-uuid resume (comment handoff-fire.sh:20784-20786, "measured on 2.1.220") | new-uuid recycle: `inherit_recycle_goal` handoff-fire.sh:10709, called at :20789 and :7808. The move lane HOLDS a live goal: bin/cc-lr:1398 `hold:goal-live` | the goal could drive the session mid-move. The hold is the reason tonight's moves never fire. |
| Background Bash (`run_in_background`) | NO. The exit modal lists it as "will stop when you exit" (src @33564794). Resume appends "didn't finish before the previous session ended" (src @26050341). | partly. Held as `wait:background-job`. On a REJECTED source, `rcy_jobs_capture` + `rcy_jobs_mail` (handoff-fire.sh:4136-4183) record each job's command and cwd and MAIL them to the successor. Never re-launched automatically. | the job's run, plus anything it was waiting for |
| cc-await-ping inbox watcher | NO (killed with the process) | yes, automatically: `mailbox-wake-arm.sh` on SessionStart and Stop (hooks/mailbox-wake-arm.sh:5, settings asyncRewake 14400). The killed watcher also writes WAKE-PATH-DOWN mail (bin/cc-await-ping:1226). The recycle answers `stop-if-watcher` when the watcher is the only job (handoff-fire.sh:12728-12781). | none beyond a short deaf window |
| In-process subagents (Agent tool) in flight | NO | no. Gate: handoff-fire.sh:4329-4336 (`HF_LR_REASON=subagents`), counted as `killed_inflight` in lr-handoff.sh:1527-1545. `wait:subagents-in-flight` in the lane. | their unfinished work. Their transcripts remain, but they are not resumed. |
| Workflows / monitor tasks (local_workflow, monitor_mcp, monitor_ws, local_agent) | NO (task types listed by the bg-work census near src @18402674) | no. They trigger the bg-work modal. bin/cc-lr:1356 `hold:bg-work-dialog` pages the operator and never answers it. | the running workflow |
| "Background work is running" exit modal | n/a (raised BY the restart) | handled: handoff-fire.sh:12605-12820. Esc/Stay for teams and agent-view-off menus. Self-call retry (W7c, :7546-7560). `CC_RECYCLE_BGWORK_ANSWER` = cancel / stop-if-watcher (forced by lr-handoff.sh:1997-2006). "Move to background" is never chosen because it forks a second live copy (handoff-fire.sh:8268-8282). | a stuck modal holds the move |
| Agent-team teammates (separate claude, `--parent-session-id`) | the processes live, but a lead `/exit` raises the modal or runs cleanupSessionTeams | no relaunch by the move. Detected by `lr_has_live_teammate` (scripts/limit-recover/lr-team.sh:42-56), `hf_team_live` handoff-fire.sh:3510, and held at :4339-4345 and :12611-12625. A teammate is relaunched only by the team procedure with its `--agent-id` (handoff-fire.sh:4737-4762). | members killed or orphaned from their lead |
| Unread mailbox | yes (file on disk) | same uuid uses the same inbox. A new sid gets `mailbox_migrate` (handoff-fire.sh:10127-10190) | none |
| Task board | yes when the id is passed | yes: `CLAUDE_CODE_TASK_LIST_ID` is exported in the launcher (lr-handoff.sh:1820) | none |
| cwd | — | yes: `--resume-cwd` (lr-handoff.sh:1972) | none |
| Pane/registry binding | — | SessionStart hooks session-register.sh and live-session-registry.sh (settings.json) | none |
| Session-scoped permission grants (`destination:"session"`, the enum near @8687263) | NO (held in memory) | no | re-prompts. Mostly moot under the allowlists. |
| MCP server connections and stateful MCP sessions | NO (reconnected) | no | MCP-side session state |
| Prompt cache | lost on ANY account change, restart or not (estimated) | the warm-cache hold exists only as the `--cold-only` skip, bin/cc-lr:1402 | one full cache write on the next request |
| Session crons | probably carried: `iAr(…,{carriedCrons})` @26050341 | not handled | unverified |
| /model, permission mode, effort | unverified | unverified | open question |

## Conclusion

The restart is what costs the move its preconditions. Every `wait:*` and `hold:*` that is stalling
tonight's moves (mid-turn, background-job, subagents-in-flight, goal-live, self, bg-work-dialog,
team) protects an item a process restart kills. An in-process credential adoption, store write plus
CC's own re-read, would keep all of them; only the prompt cache is lost to the account change
itself.

A hook does not implement the adoption. It can only fire at a known boundary and run the store
write, under its own timeout (600 s default, 5–10 s on the hooks registered today).

## Appendix: hook registrations (settings.json, names only)

- SessionStart: pre-session-validate (async), lead-crash-watchdog (async), session-register (async),
  dod-persist, desk-brief-inject, mailbox-wake-arm (asyncRewake, 14400 s),
  live-session-registry (async), mailbox-drain session-start, net-context-stamp (async),
  session-start-dispatch (20 s).
- Stop: 15 hooks, including mailbox-wake-arm and idle-keepalive (asyncRewake, 14400 s).
- PreToolUse: 21 hooks, including keychain-guard.sh on Bash and research-block.sh on `*` (5 s).
- PostToolBatch: post-tool-batch.sh (10 s).
- UserPromptSubmit: 7 hooks of 5–10 s, including mailbox-drain.sh prompt.
- ConfigChange: config-change.sh.
- SessionEnd: 7 hooks.

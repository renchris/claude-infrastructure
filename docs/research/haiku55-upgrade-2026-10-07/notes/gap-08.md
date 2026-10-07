# Gap G8: how 2.1.293 delivers hook output and harness reminders to Haiku 5.5

Method: static read of the two binaries with Python mmap (never executed), plus `pack/prompting.md`
and `pack/cc-changelog.md`. Binary: `~/.claude-293/node_modules/@anthropic-ai/claude-code/bin/claude.exe`
(236,330,608 bytes, measured with `ls -la`). Offsets below are byte offsets into that file
(measured with `mmap.find`). Nothing here was observed on the wire; every claim is "the code says".

## Answer

**As separate mid-conversation system messages, not inside tool results.** For `claude-haiku-5-5`
on a first-party login, 2.1.293 turns "system turns" on by default. Hook `additionalContext`, hook
blocking errors and almost all harness reminders are then stripped of their `<system-reminder>`
wrapper and sent as a `{role:"system"}` message placed directly after the user message they follow
(which, for PreToolUse/PostToolUse hooks, is the user message that carries the `tool_result`).

Three things follow for the decision:

1. **This is the channel the prompting guide tells harnesses to use for notices.** The guide's
   warning is about *user-typed* text arriving in a `tool_result` or in a system message right
   after one; for "harness notices, such as reminders" it says to keep them "in a separate
   mid-conversation system message" (`pack/prompting.md:100-104`). Claude Code 2.1.293 does that.
2. **It is a different channel from the one Haiku 4.5 gets today.** `claude-haiku-4-5` is on the
   binary's legacy list, so system turns are off for it and the same hook text arrives as
   `<system-reminder>` text folded into the user message, including into the `tool_result` block.
   Moving the retrieval role from Haiku 4.5 to 5.5 therefore moves fleet guardrail text out of the
   tool result and into a system message. On the guide's reading that is the safer direction.
3. **The position is still "right after a tool result".** The guide's sentence names that position
   as one where the model "can then treat it as untrusted text and ignore it", but only says so
   about a user's mid-task message. Whether Haiku 5.5 obeys a *hook-injected guardrail* in that
   position as reliably as Haiku 4.5 or Opus 5.5 obey theirs is NOT STATED in any source.

Also relevant: on 2.1.293 the alias `haiku` resolves to `claude-haiku-5-5` on first-party
(`haiku:{default:"claude-haiku-5-5",per_provider:{bedrock:"claude-haiku-4-5",...}}`, @184407645);
on 2.1.284 it is `haiku:{default:"claude-haiku-4-5"}` (@178331605). So every subagent the fleet
spawns with model "haiku" changes both model and reminder channel on the day the binary moves,
with no fleet edit.

## Evidence

### 1. The gate: system turns are on for Haiku 5.5, off for Haiku 4.5

2.1.293 @186797569:

```js
function GN(e){if($a("hipaa"))return!1;if(a.CLAUDE_CODE_FORCE_MID_CONVERSATION_SYSTEM)return!0;
let n=sAe(e,"mid_conversation_system");if(n!==void 0)return n;let r=Be(e);
if(pr(jO(r),"claude-opus-4-8"))return!1;return Zy(r,"mid_conv_system",e)??!0}
```

`pr` and its list, @186792156:

```js
var Iv=["claude-opus-4-0","claude-sonnet-4-0","claude-opus-4-1","claude-sonnet-4-5","claude-haiku-4-5",
"claude-opus-4-5","claude-opus-4-6","claude-sonnet-4-6","claude-opus-4-7","claude-opus-4-8"];
function pr(e,n){if(e.includes("claude-3-"))return!0;let r=Iv.indexOf(e);return r!==-1&&r<Iv.indexOf(n)}
```

- `claude-haiku-4-5` is in `Iv` before `claude-opus-4-8`, so `GN` returns false: no system turns.
- `claude-haiku-5-5` is not in `Iv`, so `GN` falls to `Zy(...)??!0`. `Zy` (@184412128) checks the
  `CLAUDE_CODE_MODEL_CAPABILITIES` env override, a server-served capability, then the model
  table; it returns `true` or `undefined`, never `false`, unless the env override says `-mid_conv_system`.
  The Haiku 5.5 table entry (@184392108) lists capabilities `effort, max_effort, xhigh_effort,
  adaptive_thinking, mid_conv_tool_change, context_management, rejects_disabled_thinking,
  per_turn_effort, lean_prompt, org_locked_thinking, haiku_5_5_early_stopping_guidance`; it does
  not list `mid_conv_system`, and neither does Opus 5.5 or Fable 5.1, so the result is
  `undefined ?? true` = **true**. Haiku 5.5 is treated exactly like the current lead models here.
- The beta header follows the same gate: `{beta:pS,when:(e)=>B7(e.model)}` (@186800175), with
  `pS=y("mid_conversation_system","mid-conversation-system-2026-04-07")` (@185323056).
- 2.1.284 has the same legacy list (`Wh=[...]`, @180120416) and the same system-prompt sentence
  (@77389134), so the mechanism is not new in 293; what is new is that 293 knows the Haiku 5.5 id
  and points the `haiku` alias at it.

### 2. Hook text is rendered as a reminder, then promoted to a system message

Renderers, 2.1.293 @196509849:

```js
hook_blocking_error:(e)=>[Re({content:Vbe(`${e.hookName} hook blocking error from command: "${e.blockingError.command}": ${e.blockingError.blockingError}`),isMeta:!0})],
hook_additional_context:(e)=>{if(e.content.length===0)return[];return[Re({content:Vbe(`${e.hookName} hook additional context: ${e.content.join(`\n`)}`),isMeta:!0})]},
```

`Vbe(e)=Dl(GT(e))` and `Dl(e)` wraps in the `<system-reminder>` open/close strings (@196482976).
`hook_additional_context` attachments are created for PreToolUse, PostToolUse, PostToolUseFailure,
PostToolBatch, UserPromptSubmit, UserPromptExpansion, SessionStart, Setup, SubagentStart,
Stop/SubagentStop and PostModelSwitch (@194338568, @194329197, @194331309, @200620381, @214329381,
@214334191, @194570199, @194571294, @199911588, @200507354, @200567615).

The message builder `Pk` (@196451540) sets `w = B7(model)` and, in its attachment branch (@196461535):

```js
kr=RAn(er.attachment)?"user":"system", As=kr==="system"&&(Ao?Cr!=="user":Cr==="system");
...
if(w&&As){let Ti=_Xe(zr);if(Ti!==null){let ds=M?Dl(Ti):Ti; ... zn.push(ds), ... continue}}
let cs=Ce()&&!Us?zr.map(qUr):zr, ... Pi=DF(Jt);
if(Pi?.type==="user"){Jt[Jt.length-1]=cs.reduce((Ti,ds)=>la?_I(Ti,ds):Xxn(Ti,ds,Ce(),w,xe),Pi);continue}
```

- `RAn` (@196439759) is the short list of attachment types that stay in the user role
  (`relevant_memories`, `dir_sync_notice`, `unknown_command_fallback`, `session_context`,
  `instructions`, `coordinator_context`, `context_sections`, `remote_session_change`,
  `fork_briefing`, `poll_events`, `cowork_memory_context`, `account_memory_recall`,
  `artifact_opening_prefetch`, some `queued_command`). No `hook_*` type is on it, so hook text is
  system-role.
- With `w` true, `_Xe` (@196485345) strips the `<system-reminder>` wrapper (`Cee`) and the text
  goes into `zn`; `Ho()` flushes `zn` into an `api_system` entry (`gQ`, @192252610:
  `{type:"api_system",message:{role:"system",content:e}}`) pushed after the current user message.
- On the wire (@194972417): `if(Rt.type==="api_system"){... return{role:"system",content:...}}`.
- `ujr` (@196468064) keeps an `api_system` entry as a system message only when the entry before
  it is a user message and the entry after it is an assistant message, another `api_system`, or
  the end; otherwise it is demoted to a user-role meta message re-wrapped in `<system-reminder>`.
  So the system message always sits immediately after a user message. For PreToolUse/PostToolUse
  context that user message is the `tool_result` message (`WUr`, @196436481, re-orders attachments
  to after the `tool_result` user message).
- With `w` false (Haiku 4.5), the last line above runs instead: `Xxn` -> `GAn` -> `TXe`
  (@196470308, @196470974) merge the reminder text into the preceding user message, and when its
  last block is a `tool_result` they append the text **into that tool_result's content**. This is
  today's Haiku 4.5 channel on both 284 and 293.

### 3. The system prompt tells the model which channel to trust

2.1.293 @194098321:

```js
var LLo="The system may send updates, reminders, or modifications to rules via mid-conversation system turns. These are system-controlled, unlike function results.";
function NLo(e){return B7(e)&&!Ahr(e)&&!tis(Be(e))}
function OKt(e,n){if(NLo(e))return LLo;return n==="standard"?"Tool results and user messages may include <system-reminder> or other tags. Tags contain information from the system. They bear no direct relation to the specific tool results or user messages in which they appear.":"`<system-reminder>` tags in messages and tool results are injected by the harness, not the user."}
```

`Ahr` is `claude-sonnet-5` only (@186797569 context) and `tis` is `claude-opus-4-8` only
(@187977648), so Haiku 5.5 gets the `LLo` sentence and Haiku 4.5 gets the `<system-reminder>` one.
Consequence: under Haiku 5.5 the harness tells the model that system turns are system-controlled
"unlike function results". If system turns are ever switched off for a Haiku 5.5 conversation
(section 5), hook text falls back to `<system-reminder>` text in the user message or tool result,
which is the placement the guide warns about.

### 4. Mid-turn user messages follow the guide's rule

In the same attachment branch, a human `queued_command` typed mid-turn is not folded with
reminders when system turns are on:

```js
Fr=w&&er.attachment.type==="queued_command"&&er.attachment.humanTurn===!0&&er.attachment.commandMode==="prompt"&&er.attachment.isMeta!==!0&&sx(er)&&!Xne(er.attachment)&&Ue()
... cr.push({...ds,message:{...ds.message,content:typeof Ri==="string"?Cee(Ri):Ri.map(...)}})
```

`ur()` then appends `cr` to the last user message as plain text blocks. That matches
`pack/prompting.md:103` ("Append the user's words as a text block after the last `tool_result`
in the same user message"). The gate `Ue()` is `CLAUDE_CODE_PARSED_WILLOW ?? tengu_parsed_willow`
default true (@196439759 context), so it is server-flag dependent.

### 5. Fallbacks that put hook text back into the user/tool_result channel

- API refusal: `[mid-conv-system] server rejected role:"system" — falling back to a body with no
  {role:"system"} turn, sticky-rejecting the beta until /clear or /compact` (@194900330), event
  `tengu_mid_conv_system_fallback_retry`. After that, `w` is false for the conversation.
- `$a("hipaa")` returns false from `GN`; `sAe(e,"mid_conversation_system")` and
  `CLAUDE_CODE_MODEL_CAPABILITIES` are env overrides; a served capability or feature gate can also
  change the answer (`Zy` -> `eJt`, @184412128).
- Third-party providers: the `haiku` alias stays on `claude-haiku-4-5` for bedrock, vertex,
  foundry, mantle, gateway (@184407645). Not the fleet's case (Max-plan first-party).

### 6. Changelog line 126 (2.1.292)

`pack/cc-changelog.md:126`: "Improved hook output handling: `<system-reminder>` tags written in a
hook's output are escaped before they reach Claude". The escape functions are at @188028541
(`replaceAll(/<(?=\s*(?:\/\s*)?system-reminder\b)/gi,"&lt;")`). This stops a hook's output from
closing or forging the wrapper; it does not change which channel the text travels in. The NEUTRAL
rating in `notes/cc293-axis3.md:39` stands for that line, but that row does not cover the channel
change described above, which comes from the model id, not from a changelog entry. No line in
`pack/cc-changelog.md` 3-815 mentions the mid-conversation system role (measured:
`grep -n "mid-conversation\|mid_conv"`, first hit is line 1123, outside the band).

### 7. Fleet exposure (measured in the worktree)

- 36 files under `hooks/` contain `additionalContext` (`grep -rIc additionalContext hooks`, non-zero
  count). By `hookEventName` literal the heaviest events are PreToolUse and PostToolUse, then
  SessionStart and UserPromptSubmit (`grep -rIhoE hookEventName...`, counts are of literals, not of
  distinct hooks).
- 23 files under `hooks/` contain `exit 2` and 23 contain `permissionDecision` (`grep -rIl`). A
  block from these is enforced mechanically (the tool does not run), so it does not depend on the
  model reading anything. Only the *advice* in the reason text depends on the channel.

## What remains unknown

1. **NOT STATED: whether Haiku 5.5 obeys hook-injected text in a system message that follows a
   tool result.** The guide describes the risk only for user-typed text and recommends the system
   message for notices; the System Card pages were not found to address this harness channel.
   Measurement: an A/B on 2.1.293 with one PreToolUse or PostToolUse hook that emits a harmless,
   checkable instruction via `additionalContext` (for example "end your final answer with the token
   X"), N retrieval-style subagent runs each on `claude-haiku-4-5` and `claude-haiku-5-5`, score
   compliance. Add an Opus 5.5 arm as the positive control.
2. **Not observed on the wire.** Everything above is static code reading. A served capability,
   feature gate or API refusal could turn system turns off for Haiku 5.5 at run time.
   Measurement: one `claude -p --model claude-haiku-5-5 --debug` fire on 293 and grep the debug log
   for `[mid-conv-system]`, or read the request body through a logging proxy and check for a
   `role:"system"` entry after the first `tool_result`.
3. **Subagents specifically.** `Pk` is model-keyed, not session-keyed, and SubagentStart context
   uses the same attachment type (@199911588), so subagents should behave as above, but a subagent
   transcript was not inspected. The measurement in item 2, run through a Task-spawned agent with
   model "haiku", settles it.
4. **PreToolUse deny reason and plain hook stdout.** The renderer for `hook_success` (plain stdout
   on SessionStart/UserPromptSubmit) and the code path that puts a PreToolUse deny reason into the
   `tool_result` error were not extracted. `hook_success` is not on the user-role list (`RAn`), so
   if it renders it is system-role; a deny reason is expected to arrive inside an `is_error`
   `tool_result`, which is the channel Haiku 5.5 is trained to distrust. Measurement: read the
   transcript JSONL of one denied tool call under Haiku 5.5 and check whether the next action
   follows the reason's advice.
5. **Demotion frequency.** `ujr` demotes a system message to `<system-reminder>` user text when it
   is not directly between a user and an assistant message. How often fleet hook text hits that
   path was not measured.

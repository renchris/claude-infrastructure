# Gap G1: client-side off switch for the per-agent token budget, and which spawn surfaces carry it

Date: 2026-10-07. Source: the 2.1.293 binary
`/Users/chrisren/.claude-293/node_modules/@anthropic-ai/claude-code/bin/claude.exe`, read with Python
`mmap.find` / `re.finditer`; neither binary was executed. `@N` is a byte offset in that file. Every
count below is measured that way unless marked otherwise.

## Answer

**Yes, there is a client-side off switch, and the adversary's R2 sentence "No setting, env var, or
frontmatter disables it" is wrong for 2.1.293.**

1. **Narrow switch: `CLAUDE_CODE_RIPPLING_TULIP=0`** in the environment of every session that spawns
   subagents. The env var is read before the server-sent value and the feature flag, and a
   non-positive (or non-numeric) value makes the resolver return no budget. The same resolver feeds
   the parent-side "Each agent you launch has a budget of N tokens" sentence, so that sentence
   disappears too. The general 15,000,000-token countdown that 2.1.284 already has is left as is.
2. **Broad switches (also work, wider side effects):** `CLAUDE_CODE_TOTAL_TOKENS_REMINDER` set to
   `infinite`, `fixed` or `countdown` (or the settings key `totalTokensReminder`) makes the resolver
   return before it reads anything; `off` does the same as long as `CLAUDE_CODE_RIPPLING_TULIP` is
   unset. `CLAUDE_CODE_DISABLE_ATTACHMENTS` and `CLAUDE_CODE_SIMPLE` also return early. These change
   or remove the reminder for the whole session, not just the per-agent budget.
3. **Surfaces.** The budget is attached at exactly two call sites: Agent-tool launch and Agent
   resume. Workflow `agent()` and the in-process teammate runner do not pass it, and the shared
   runner does not inherit it for them. Coordinator mode and remote (cloud) agents are skipped.
   Fork subagents get it only when `tengu_calm_mochi` / `CLAUDE_CODE_CALM_MOCHI` is `forks` or `all`.

**Consequence for the decision.** R2 stops being "a server-side risk with no control". The hold
argument reduces to one operator-staged env line, `CLAUDE_CODE_RIPPLING_TULIP=0`, which is inert on
2.1.284 (0 hits for the name in that binary) and can therefore be staged before the binary move.
What is still open is a live confirmation and one resume edge case (see "What remains unknown").

## Evidence

### E1. The env var is read first; a non-positive value yields no budget

Resolver, 2.1.293 @194076564 (full text, not trimmed):

```js
function sQe(e,n){if(a.CLAUDE_CODE_DISABLE_ATTACHMENTS||a.CLAUDE_CODE_SIMPLE)return;
let r=bWt();if(r!=="padded-countdown"&&r!=="off")return;
if(r==="off"&&n===void 0&&a.CLAUDE_CODE_RIPPLING_TULIP===void 0&&TKt()==="off"){t("[total_tokens reminder] off by CLAUDE_CODE_TOTAL_TOKENS_REMINDER/settings; not reading tengu_rippling_tulip for this subagent");return}
let s=n===void 0?dZn("tengu_rippling_tulip",a.CLAUDE_CODE_RIPPLING_TULIP,e):Number(n.findLast((g)=>wKt.test(g))?.match(wKt)?.[1]);
if(typeof s!=="number"||!Number.isSafeInteger(s)||s<=0)return;
if(r==="off"&&n===void 0)return s;
return s<E5()?s:void 0}
```

Value lookup, @194073474:

```js
function SWt(e,n){return n??Qc()?.[e]??$r(e,null)}
function dZn(e,n,r){let s=SWt(e,n),g=typeof s==="string"?gt(s,!1)??s:s;return ls(g)?Wje(g,r):g}
```

- `n` is the env value. `??` only falls through on `null`/`undefined`, so any set env value wins over
  `Qc()?.[e]` (server-sent client data; the neighboring log line at @194075293 calls it
  "clientData") and over `$r(e,null)` (flag lookup with default `null`).
- The env var is declared as a string: `Ns=M.str()` @184235740, exported as
  `CLAUDE_CODE_RIPPLING_TULIP:()=>Ns` @184230236. `M.str()` is `trim()` and returns `undefined` for
  an empty string (@184200979), so the value must be non-empty: `0`, not an empty assignment.
- Env values are read live from `process.env` on each access (`Elt` @~184269900:
  `get:()=>{let C=process.env[r];if(C!==n)e=s.parse(C),n=C;return e}`), so an `env` entry in
  settings works as well as a shell export, provided it is in place before the spawn.
- With `"0"`: `dZn` returns either the number `0` or, if the parse helper `gt` rejected it, the string
  `"0"`. Both fail the next line (`typeof s!=="number" || ... || s<=0`) and `sQe` returns
  `undefined`. The same holds for any non-numeric word. (`gt` itself was not traced; the result does
  not depend on it.)
- The explicit log string in the third line shows the vendor intends a client-side off: reminder mode
  `off` from env or settings skips the server flag entirely unless the env var forces a budget.

Mode resolver, @194075643, env and settings before server:

```js
function eLo(){let e=TKt();if(e!==void 0)return e;let n=Qc()?.[Gje], ... let s=C(Gje,"padded-countdown");...}
function TKt(){let e=a.CLAUDE_CODE_TOTAL_TOKENS_REMINDER;if(ufe(e))return e;let n=ut().totalTokensReminder;return ufe(n)?n:void 0}
var XDo=["off","infinite","fixed","countdown","padded-countdown"]
```

`bWt()` caches the mode in session state (`e.totalTokensReminderMode??=eLo()`), so it is fixed at
first use in a process.

### E2. The parent-side sentence uses the same resolver

@199974625:

```js
function Io(){if(SWt("tengu_streamed_bumblebee",a.CLAUDE_CODE_STREAMED_BUMBLEBEE)!==!0)return null;
let n=sQe(y5n(len()),void 0);if(n===void 0)return null; ...}
```

`sQe(` appears 4 times in the JS region (measured): the definition @194076573, `Gpn` @199940233,
`Io` @199975234, and the resume fallback @208409838. There is no other producer.
`CLAUDE_CODE_STREAMED_BUMBLEBEE` is a tri-state boolean (`Ms=M.triBool()` @184235773); setting it
false also removes the sentence, but `CLAUDE_CODE_RIPPLING_TULIP=0` already does.

### E3. Where the budget is attached

`Gpn`, @199939913, the only producer of `totalTokensBudget`:

```js
if(ua()||Tw(e))return t?void 0:d;          // coordinator mode or Tw(agent): no budget
if(t&&COe()==="none")return;               // fork: only if calm_mochi is "forks" or "all"
let p=sQe(l,m); ...
```

`Gpn(` has 3 hits (measured): definition, Agent launch @199992334, Agent resume @208409653.

```js
// launch: he = remote agent, skipped
let ce=he?void 0:Gpn({agentDefinition:s,isFork:Y,model:ee,...,recordedBudgetText:void 0});
// resume
V=n?.isObserver||A!==void 0?void 0:Gpn({agentDefinition:b,isFork:_,...,recordedBudgetText:_?w1o(C):_e});
b=V?.agentDefinition??b;let Ze=V===void 0&&_e?sQe(void 0,_e):void 0;
```

Surfaces without it:

- Workflow `agent()`, @205384064: the options passed to the runner are `agentDefinition,
  promptMessages, toolUseContext, session, canUseTool, isAsync, querySource, ..., transcriptSubdir,
  spawnedByWorkflowRunId, description, workflowPhase, override:{agentId,agentContext},
  persistedToolResultFiles, model, onModelRestricted, onQueryProgress, worktreePath`. No
  `totalTokensReminderBudget`.
- In-process teammate runner, @218412316: `override:{abortController,agentContext,onRetryStatus,...},
  ..., model, preserveToolUseResults, availableTools, allowedTools, contentReplacementState,
  stickyBetas, isTeammate:!0, teammateContext`. No `totalTokensReminderBudget`.
- The shared runner inherits a parent's budget only for forks, @199918953:
  `...J===void 0&&j?.parentSystemPrompt?{totalTokensReminderBudget:n.options.totalTokensReminderBudget,...}:{totalTokensReminderBudget:J,...}`.
  Neither surface above sets `override.parentSystemPrompt`, so both get `undefined` and fall back to
  the session default `h??E5()` (15,000,000; `bKt=15000000` @194073619).

`totalTokensReminderBudget` has 17 whole-file hits in 2.1.293 (measured); all were read. They are
schema text, the session-state field, `E5`, the reminder builder call (@195706080), runner
parameter passing, two accounting calls (@200565844, @200609552), and the launch and resume sites.
None compares usage against the budget or stops the agent; the budget only changes the
`<total_tokens>N tokens left</total_tokens>` text.

### E4. Presence by version

Measured, whole file: `CLAUDE_CODE_RIPPLING_TULIP` 2.1.284 0 / 2.1.293 4 (1 in the bytecode string
table @78566796, 3 in the JS region, which matches the "3 hits" in the brief); `tengu_rippling_tulip`
0 / 4; `CLAUDE_CODE_STREAMED_BUMBLEBEE` 0 / 7; `tengu_calm_mochi` 0 / 2; `CLAUDE_CODE_CALM_MOCHI`
0 / 3; `has a budget of` 0 / 6; `totalTokensBudget` 0 / 11.

Changelog `pack/cc-changelog.md` lines 3-815: NOT STATED. `grep -n -i budget` returns only lines 321
(WebSearch refill) and 746 (retry budget) in that range; neither the budget nor these env vars are
documented.

### E5. Notes compared

- `notes/cc293-adversary.md` line 48 (R2): "No setting, env var, or frontmatter disables it". Refuted
  by E1.
- `notes/bin293-probes.md` lines 16-97: confirmed, with one omission. Its `sQe` snippet replaces the
  third line (the `off` branch with the log string) by `...`. That branch is the second off switch.
- `notes/cc293-referee.md` line 222 recommends `CLAUDE_CODE_TOTAL_TOKENS_REMINDER=infinite`. It works
  (second line of `sQe`), but it also changes the reminder every agent in the session sees to
  "Infinite tokens left". `CLAUDE_CODE_RIPPLING_TULIP=0` is narrower: it leaves 2.1.293 behaving
  like 2.1.284 on this point.

## What remains unknown

1. **Live behavior: NOT MEASURED.** Everything above is a code read. Settling measurement, per
   account and lead model on 2.1.293: run one `-p` session with `CLAUDE_CODE_RIPPLING_TULIP=100000
   CLAUDE_CODE_STREAMED_BUMBLEBEE=true` and one with `CLAUDE_CODE_RIPPLING_TULIP=0`, each launching
   one Agent-tool subagent; check the Agent tool description for "has a budget of" and the
   subagent transcript for the `<total_tokens>` value. Expected: 100,000 in the first, about
   15,000,000 and no sentence in the second.
2. **Resume of an agent that already recorded a budget.** On resume the budget is parsed from the
   recorded transcript text (`recordedBudgetText`), not from the env. An agent launched with a
   budget before the env line was staged would keep it when resumed. Agents launched with the env
   line in place record none. Not exercised.
3. **Nested spawns.** A Workflow agent or teammate that itself calls the Agent tool goes through
   the Agent-launch site, so its child can get the budget; out-of-process teammates and `-p`
   workers are their own sessions and need the env line in their own environment. Whether every
   fleet launcher passes the env through was not checked (the repo has 0 references to the name
   outside `docs/research`, measured by `grep -rIl`).
4. **Why reporters saw agents stop.** No enforcement code was found, so the "budget exhausted"
   stops in #99932 / #99949 are most likely the model reacting to a countdown at 0; that is an
   inference, not a measurement.
5. **Server state.** Whether `tengu_rippling_tulip` is on for any fleet account today is not in
   the binary. With the env line staged it no longer matters for fresh Agent-tool launches.
6. `Tw(e)`, `ua()`, `Qc()`, `$r()` and `gt()` were identified by context and by the probe note, not
   traced to their definitions.

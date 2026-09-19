# C — Vendor in-process subagents: lifecycle, `name:` dispatch, hook surface (2.1.260)

Method: `python3` over `cc260.strings` / `cc220.strings`
(`/private/tmp/claude-501/-Users-chrisren-Development-claude-infrastructure/e442434c-1a96-4c04-b06e-ac89c2f9891a/scratchpad/`),
dumped from `~/.claude-260/node_modules/@anthropic-ai/claude-code/bin/claude.exe` and the 2.1.220
sibling. **Every `@N` below is a byte offset into the STRINGS DUMP, not into the binary** — re-read with
`python3 -c "d=open(PATH,errors='replace').read(); print(d[N-2000:N+2000])"`. Minified identifiers are
quoted as they appear (`CSo`, `Z9`, `Iq`, …); they are chunk-local and will be renamed by any rebuild,
so the durable anchors are the **string literals** cited alongside them.

Marked **[E]** = empirical (read off disk / off the shipped bytes verbatim), **[I]** = inferred from
code paths not executed here.

---

## 0. Headline findings, answer-first

1. **"Foreground unnamed Agent" is largely a fiction on both 2.1.220 and 2.1.260.** The spawn-mode
   decision `CSo` (`cc260.strings@18175641`) forces `shouldRunAsync` whenever the caller is not an
   in-process teammate and `run_in_background !== false` — and *also* when `forceAsync` is set, which
   at the Agent tool's call site is `xz() && !callerIsTeammate`, i.e. the fork-subagent gate being
   on. In an ordinary interactive non-coordinator session that gate reads `"default"`, so **even
   `run_in_background: false` still routes to the async branch.** [I — code-path reasoning; see §9
   for the one arm I could not execute]
2. **`task_type: "in_process_teammate"` does NOT mean "no pane".** The registrar `te(…)`
   (`@30781000`) is called from *both* the iTerm2 pane path and the tmux path, carrying
   `paneTeardown`. A pane-backed `claude --agent-id …` child is represented in the parent by an
   `in_process_teammate` task record whose `paneTeardown` closure kills the pane. The real in-process
   case is `Brn`/`z` (`@30756359`), which registers the *same* type with **no** `paneTeardown`. [E]
3. **`isolation:"worktree"` still silently demotes a named Agent to a plain subagent on 2.1.260.**
   The teammate branch condition is `if(Ne&&E&&!Wt&&!PF(f,je)&&!C&&!ye)` (`@19027900`) where
   `C = isolation`, `ye = cwd`. 220's is `if(b&&i&&!L&&!s&&!a)` (`@19994150`) — same shape. The only
   260 addition is `!PF(f,je)` (web-fetch agent type). F-a is **unfixed**. [E]
4. **SubagentStart cannot deny a spawn**; its `blockingError` is converted into a `hook_blocking_error`
   message *inside the new agent's own context* (`@18888700`). Denying a spawn is the *plugin*
   `agent.spawn` hook's job (`subagent_spawn_denied_by_hook`, `@8558772`). [E]
5. **SubagentStop can block**, but only from the `"blockable_turn_end"` call site; the `"loop_tick"`,
   `"turn_end_reactions"` and interrupted-query sites explicitly log and **discard** the block
   (`"[end-turn] Stop hook block discarded"`, `@19641600`). [E]
6. **`TaskCompleted` and `TeammateIdle` only fire when `Ji()`** — i.e. only inside a session that *is*
   a teammate (`dynamicTeamContext` has both `agentId` and `teamName`). They never fire in a lead
   session and never for a plain unnamed subagent (`@19650900`). [E]
7. **Something does persist after an unnamed agent ends** — see §4. The strongest refuters of a
   "nothing persists" claim are the on-disk transcript, the `<taskId>.output` **symlink**, and
   `everRegisteredTaskIds`, which is a `Set` with no removal path.

---

## 1. Task-type registry and id shape

`cc260.strings@15725150`, one contiguous literal:

```js
var k={local_bash:"b",local_agent:"a",remote_agent:"r",in_process_teammate:"t",local_workflow:"w",
       monitor_mcp:"m",monitor_ws:"s",mcp_task:"k",dream:"d",auto_mode_scan:"e"},
    d="0123456789abcdefghijklmnopqrstuvwxyz";
function kh(e){let t=k[e]??"x",o=m(8),i=t;for(let n=0;n<8;n++)i+=d[o[n]%d.length];return i}
function Id(e,t,o,i){return{id:e,type:t,status:"pending",description:o,toolUseId:i,
  startTime:Date.now(),outputFile:pl(e),outputOffset:0,notified:!1}}
```

- `kh(type)` mints `<letter> + 8 base36` — used for `in_process_teammate` (`t…`), `remote_agent`,
  `local_workflow`.
- **`local_agent` does NOT use `kh`.** Its task id *is* the agentId, minted by `fh()` (`Ts` at the
  Agent-tool call site) — 17 chars, `a` + 16 hex. [E] confirmed on disk: `agent-a14a8631ad321a371`.
- Terminal statuses: `vs(e)` = `completed | failed | killed` (`@15724650`).
- "live agent-ish work" set: `w = {local_agent, remote_agent, in_process_teammate, local_workflow}`,
  with `Zjt` excluding idle teammates and long-running remotes (`@15724754`).

---

## 2. Lifecycle state machine — unnamed `Agent()` (task type `local_agent`)

### 2.1 Admission gates, in execution order (Agent tool `call()`, `@19024660`)

| # | Gate | Refusal code / literal | Offset |
|---|---|---|---|
| 1 | `ac(agentContext) >= $S()` | `subagent_depth_cap`, *"Subagent nesting limit reached (depth N of M)"* | `@19025300` |
| 2 | spawner's stop still settling | `subagent_spawner_stop_pending` | `@19025500` |
| 3 | `name` present && caller is a teammate | `subagent_nested_teammate`, *"Teammates cannot spawn other teammates — the team roster is flat."* | `@19025900` |
| 4 | teammate + `run_in_background:true` | `subagent_teammate_background_denied` | `@19026050` |
| 5 | agent-type resolution: denied / missing / ambiguous / not-found / tools-denied / not-offered | `subagent_type_{denied,missing,ambiguous,not_found,tools_denied}`, `subagent_teammate_not_offered` | `@19026500`–`@19029500` |
| 6 | agent def has `background:true` and caller is a teammate | `subagent_teammate_background_denied` | `@19029900` |
| 7 | concurrency slot | `subagent_concurrency_cap`, *"You can run N subagents at once. Do not retry."* (`CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS`) | `@19026800` |
| 8 | required MCP servers absent (30 s wait for `pending` first) | `subagent_mcp_required_missing` | `@19030700` |
| 9 | plugin `agent.spawn` hook `deny` | `subagent_spawn_denied_by_hook` | `@19031200` |
| 10 | hook rewrote the spawn into one a rule denies/asks | `subagent_spawn_hook_rewrite_ruled` | `@19031600` |
| 11 | hook set `cwd` on a worktree-isolated spawn | `subagent_spawn_hook_cwd_worktree` | `@19031900` |
| 12 | resolved tool list empty | *"would be spawned with zero tools — refusing"* (`tengu_subagent_zero_tools`) | `@18890200` |

Note gate 7's cap counts **concurrent** subagents; 220 additionally had a *cumulative*
`subagent_count_cap` / `CLAUDE_CODE_MAX_SUBAGENTS_PER_SESSION` (`cc220.strings@19993000`) which is
**absent from 260's Agent tool** — consistent with the fleet note that 2.1.224 removed the
200-per-session ceiling.

### 2.2 States

```
                       ┌────────────────────────────────────────────────┐
  Agent() call         │ (gates 1-12 above; any failure = tool error,    │
        │              │  NO task record is created, NO transcript)      │
        ▼              └────────────────────────────────────────────────┘
  REGISTERED ── ONn() (sync) / rV() (async) @19989395 / @19988011
     │  record: {id=agentId, type:"local_agent", status:"running", agentId, ownerAgentId,
     │           parentAgentId, spawnDepth, prompt, model, effort, cwd, selectedAgent, agentType,
     │           abortController, spawnedSubagent, retrieved:false, isBackgrounded:<false|true>,
     │           isIdle:false, pendingMessages:[], retain:false, diskLoaded:false,
     │           keepaliveReasons:Set(), outputFile:pl(id), outputOffset:0, notified:false}
     │  side effects: PV(id, Md(id))  → symlink <sid>/tasks/<id>.output → <sid>/subagents/agent-<id>.jsonl
     │                agentBackgroundSignalResolvers.set(id, …)   [sync only]
     │                everRegisteredTaskIds.add(id)               [sFt, @16477815 — NEVER removed]
     ▼
  RUNNING ── Z9() @18987319 drives the stream; per chunk it does
     │   • taskRegistry.updateTranscript(id, …) (in-memory mirror)
     │   • Sne([msg], agentId, …) → APPEND to agent-<id>.jsonl on disk
     │   • Zit(id, progress, registry) → {tokenCount, toolUseCount, recentActivities}
     │   • isIdle recompute (En)
     │   • stall watchdog Nn(): no progress for nLo() ms ⇒ abort + status "failed"
     │       ("Agent stalled: no progress for Ns (stream watchdog did not recover)")
     │   • optional auto-background timer (ONn's `D`) flips isBackgrounded via t7()
     ├──► BACKGROUNDED (isBackgrounded=true; backgroundSignal resolved; sync caller returns
     │                  {status:"async_launched"} immediately and stops awaiting)
     ├──► max_turns_reached attachment ⇒ loop `break` (see §7) — NOT an error state
     ▼
  FINALIZED ── _Nn() @19986951
        {status:"completed", result:<tat() report>, endTime, terminal, finalizing:true,
         evictAfter: qut(...), abortController: undefined, selectedAgent: undefined}
     │  siblings: _0e() → status "failed"; jO() → status "killed" (+ killedBy: user|parent|system)
     ▼
  NOTIFIED ── Iq() @19981013 (async path only) or the Agent tool's finally-block ai() (sync path)
     │  notified:true
     ▼
  EVICTED ── sMo/iMo @18712634, @18713760
        requires: terminal ∧ notified ∧ evictAfter ≤ now ∧ keepaliveReasons.size === 0 ∧ !retain
        effect:  delete AppState.tasks[id] AND AppState.transcripts[id]; taskEvicted.emit(id)
```

`Xw = 30000` (`@18708740`) is the eviction grace. `qut(e,{park})` (`@19978852`):
`retain ⇒ never evict`; `park && keepaliveReasons.size>0 ⇒ never evict`; else `now + 30_000`.

### 2.3 How the result reaches the parent — **both channels, and they are not equivalent**

| | Synchronous branch (`else` at `@19041700`) | Async branch (`if(Nn)` at `@19040900`) |
|---|---|---|
| Agent tool returns | `{status:"completed", prompt, ...Ul}` where `Ul = tat(msgs, agentId, meta)` — **a real `tool_result`** | `{isAsync:true, status:"async_launched", agentId, description, resolvedModel, prompt, outputFile, canReadOutputFile}` |
| Report body | in the tool_result content | in a **task notification** injected later as a synthetic user message |
| maxTurns marker | **absent** — the tool_result is an ordinary `status:"completed"` | present: *"stopped at its N-turn limit (partial result; … to task-id to continue)"* (`@19981500`) |
| usage | not in the tool_result | `<usage><subagent_tokens>N</subagent_tokens><tool_uses>N</tool_uses><duration_ms>N</duration_ms></usage>` |
| registry entry afterwards | `NNn(id, reg)` **removes it at once** unless backgrounded or an `agent:` keepalive is held (`@19990831`) | survives ~30 s post-notify, then evicted |

The notification envelope is built by `ua({taskId,toolUseId,taskType,outputFile,status,summary,body,trailing})`
(`@17040080`) and delivered via `ca({… mode:"task-notification", skipAttachments:true, priority:"next",
agentId, taskId}, {turnAttribution:"inherit"})`. Its body carries, verbatim:

> `<note>A task-notification fires each time this agent stops with no live background children of its own. The user can send it another message and resume it, so the same task-id may notify more than once.</note>`

plus `<result>…</result>` and the `<usage>` block. `Iq` **short-circuits if the task was already
notified or is not in the registry** — it logs `[enqueueAgentNotification] skipped taskId=… reason=already-notified|task-not-in-registry`.

**Owner routing.** `gLe({ownerAgentId, keepaliveReason:"agent:<id>", delivering, taskRegistry})`
(`@19982400`) decides whether the notification is addressed to the spawning agent or to the main
session, and releases the `agent:<id>` keepalive. A parent that has already finished gets the
notification routed to `ze()` (main). There is a dedicated message for the re-parented case:
*"Agent \"X\" was resumed by another agent and now reports to it; its completion will not be delivered here."*
(`cKn`, `@19982900`).

### 2.4 Keepalive parking — the reason a finished agent can stay in the registry

`keepaliveReasons` is a `Set<string>` of `agent:<id>` / `workflow:<id>` / `bash:<id>` / `monitor:<id>`
(`xv`/`Hv`/`pE`, `@18714646`). If a completed agent still holds an `agent:` reason (`C1`, `@19979456`),
`Z9` logs `[AsyncAgent <id>] parked on keepalive — deferring owner notification until resume` and
**does not notify** (`@18993200`). `ym(e)` = `completed && keepaliveReasons.size > 0` is the
"parked" predicate. `pE()` sets `evictAfter` only when the set empties.

---

## 3. The foreground/background decision (`CSo`) — verbatim

`cc260.strings@18175641`:

```js
function CSo(e){let{agent:n,wantsBackground:r,callerIsInProcessTeammate:o}=e,
  d = e.isCoordinator&&!o || e.forceAsync || !o&&r!==!1,
  f = jwn(e),
  _ = r===!0 || n.background===!0 || !qb(n)&&d,
  E = f==="remote";
  return{effectiveIsolation:f,isRemoteLaunch:E,shouldRunAsync:E||_&&!e.backgroundTasksDisabled}}
```

Call site (`@19030200`): `Mt = xz() && !De` is `forceAsync`; `hn = wi()` is `isCoordinator`;
`bn = vl()` is `backgroundTasksDisabled`; `De` is `!!n.teammateContext`.

Resolved predicates:

| symbol | definition | offset |
|---|---|---|
| `qb(a)` | `a.source==="built-in" && a.agentType===_y` — **the built-in web-fetch agent, nothing else** | `@17215675` |
| `vl()` | `AK().backgroundTasksDisabled \|\| CLAUDE_CODE_DISABLE_BACKGROUND_TASKS` | `@14495240` |
| `wi()` | `CLAUDE_CODE_COORDINATOR_MODE` truthy, and not (interactive ∧ not-remote) | `@14935994` |
| `xz()` | `cLo() !== "disabled"`; `cLo()`: `"disabled"` if coordinator-mode or `CLAUDE_CODE_FORK_SUBAGENT===false`; `"env"` if `CLAUDE_CODE_FORK_SUBAGENT===true`; `"disabled"` if **not interactive** (`ke()`); else `"default"` | `@18998300` |
| `ke()` | `!host.launchOptions.isInteractive()` | `@11344518` |
| `jwn(e)` | effective isolation: `isolation ?? agent.isolation`, **ignored entirely for the web-fetch agent** (logs *"[web-fetch agent] isolation:'X' ignored; the built-in web-fetch agent always runs as a local agent"*), and `"remote"` degrades when ineligible | `@18175101` |

**Consequence.** In an interactive, non-coordinator session with the fork gate at its default:
`forceAsync = true` ⇒ `d = true` ⇒ `_ = true` for every agent except web-fetch ⇒
`shouldRunAsync = true` unless background tasks are disabled. `run_in_background:false` removes only
the third disjunct of `d`, not `forceAsync`. **The sync branch is reachable only when the fork gate is
off (headless, coordinator mode, or `CLAUDE_CODE_FORK_SUBAGENT=0`), or for the web-fetch agent, or
when `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS` is set.** [I]

220 has the same shape (`cc220.strings@19997500`): `V = z || (o===!0||W.background===!0||G||B||!C&&o!==!1) && !j`
— two unconditional disjuncts `G||B` where 260 has `isCoordinator&&!o || forceAsync`. So the
async-by-default behaviour is **not new in 260**; what 260 added is the `!qb(n)` guard that keeps the
web-fetch agent synchronous.

---

## 4. Teardown and persistence — "what is left when an unnamed agent ends"

### 4.1 Torn down

`Z9`'s `finally` (`@18996200`): `bNn(id, reg)` (clears `finalizing`), `un()` (stall timer),
`ue()` (loop-settle + `onRunSettled` → concurrency slot released), `ut.setTurnEffort(null,null)`,
`Oke(agentId)` (forget invoked skills, `@11360562`), `ZRn(agentId)` (`dumpPrompts.stateByAgent.delete`, `@18600338`).

`runAgent`'s own cleanup array (`@18900900`–`@18902300`) runs these **named stages**, each wrapped so a
throw only logs `[runAgent cleanup] stage '<name>' failed: …`:

```
SubagentStop · mcp · sessionHooks · promptCacheTracking · propagateNestedMemory · readFileState ·
sentSkillNames · initialMessages · liveMessages · replHydrationSnapshot · perfetto ·
otelSubagentSpan · transcriptSubdir · todos · replContext · sandboxWriteGrant ·
nonShellMonitors[keepaliveGated] · shellTasks[keepaliveGated]
```

The two `keepaliveGated` stages are **skipped** when the agent still has live backgrounded children —
so an agent that parks leaves its monitors and background shells alive on purpose. `EIn` otherwise logs
`killShellTasksForAgent: killing orphaned shell task <id> (agent <id> exiting)` (`@18694800`).

Also released: `sFt`'s loop entry (`loopsByTaskId.delete`), the abort controller (`abortController: undefined`
on the finalized record), `selectedAgent: undefined`, `Own(agentId)` (transcript-subdir map entry),
`agentLifecycle.clearTodos(agentId)`, and the concurrency slot.

### 4.2 **Persists** — adversarial list, i.e. what refutes "nothing persists"

| What | Where | Lifetime | Evidence |
|---|---|---|---|
| Agent transcript JSONL | `<projects>/<proj>/<sessionId>/subagents/agent-<agentId>.jsonl` | **forever** (never deleted by any path read here) | `Pwt()`/`Md()` `@14004198`; on disk [E] |
| Agent meta sidecar | `…/subagents/agent-<agentId>.meta.json` | forever | on disk [E], shape below |
| `<taskId>.output` **symlink → the JSONL** | `<projects>/<proj>/<sessionId>/tasks/<taskId>.output` | forever | `PV` = `initTaskOutputAsSymlink` `@14418125`; TaskOutput's own prompt says *"it is a symlink to the full subagent conversation transcript (JSONL) and will overflow your context window"* `@19237900` |
| `everRegisteredTaskIds` (Set) | in-process (`Lb()`) | process lifetime — **no removal path exists** | `@16477815` |
| `outputPathBindings` / `linkedOutputs` | in-process | cleared only by `reset()` | `@13117798`, `@14402345` |
| `agentNameRegistry` name→agentId | AppState | survives the agent; `allocateName` renames on collision with a *live* holder only | `@30757400` |
| Task record + in-memory transcript | AppState | 30 s after notify (`Xw`); **indefinitely** if `retain` or any keepalive reason is held | `sMo` `@18712634` |
| Agent worktree + its metadata | disk | kept unless `V9(...)` reports `removed`; `Bzn()` writes `worktreeCleanlyRemoved:true` metadata when it does. Logs *"Agent worktree kept at: <path>"* | `@19039500`, `@18905000` |
| Stop marker (`stoppedByUser`) | disk (agent metadata) | consulted at resume | `MX(...)` `@29561974` |
| Spawn counters / telemetry | `cTe.of(session).recordSpawn/recordRefused` | session | `@19025350`, `@19039900` |

**Empirical meta.json shape** [E] (`…/e442434c…/subagents/*.meta.json`, 2026-09-19):

```json
{"agentType":"deep-research","description":"L: false-positive close rate",
 "toolUseId":"toolu_01RFRsKm1nyvQgXLUNjYUNdo","spawnDepth":1}
{"agentType":"deep-research","description":"K: red-team remedy classes",
 "toolUseId":"toolu_01Fg8cxmV6WZngNwDrJpVXKR","spawnDepth":1,"model":"fable"}
```

Keys observed: `agentType`, `description`, `toolUseId`, `spawnDepth`, optional `model`. The writer's
wider key set (seen in `Bzn`'s `spawnMetadata`) additionally carries `isFork`, `isBuiltIn`, `cwd`,
`name`, `parentAgentId`, `stoppedByUser`, `pluginSteered`, `worktreeCleanlyRemoved`,
`worktreePath`/`worktreeBranch` — i.e. a *named* or worktree-isolated agent writes strictly more.

### 4.3 `TaskOutput` / `TaskStop` semantics for a `local_agent`

`TaskOutput` (`QFn`, `@19236500`):
- Tool description, verbatim: *"[Deprecated] — for bash and remote_agent tasks, prefer Read on the output file path; for local_agent tasks, use the Agent tool result directly"*.
- `validateInput` returns `errorCode:2` when `getAppState().tasks[task_id]` is absent. **After eviction (or immediately, for the sync branch) TaskOutput on that id is unusable** — the transcript is still on disk but the tool will not reach it.
- For `local_agent` it returns `{task_id, task_type, status, description, prompt, result, output, isRawTranscript, error, harnessHead?, webFetchSavedFiles?, omitOutputPath?}` — `result` is the *report* (`rse`/`B$t` split the harness notes off the body); if no report exists it falls back to `mSt(id)` = **the raw transcript**, and flags `isRawTranscript:true`.
- Any successful retrieval sets `notified:true`, which arms eviction.

`TaskStop` (`$0e`, `@19146067`): returns `{message, task_id, task_type, command?}`; `task_type` is read
straight off the record, which is why stopping a *named* agent answers `in_process_teammate` (§5).
Its prompt says, verbatim: *"To stop an agent-team teammate, pass its agent ID (\"name@team\") or bare
teammate name as task_id"* and *"To stop a background agent spawned with a name, pass that name as
task_id"* (`@8759751`). Kill is `killedBy:"parent"` (`@19147739`).

---

## 5. `name:` — the decision function, with offsets

### 5.1 Branch point (Agent tool, `cc260.strings@19027880`)

```js
if(Ne && E && !Wt && !PF(f,je) && !C && !ye){
  … const {spawnTeammate:Yi}=import.meta.require("/$bunfs/root/chunk-817d3h37.js");
  const zi = await Yi({name:E, prompt:re, description:ue, use_splitpane:!0,
                       plan_mode_required:xe==="plan", model:…, modelSource:…,
                       agent_type:fs?.agentType??f, invokingRequestId:…}, n, d);
  return {data:{status:"teammate_spawned", prompt:re, ...zi.data}};
}
```

| symbol | meaning | if truthy/falsy |
|---|---|---|
| `Ne` | `zr() ? appState.teamContext : undefined` — **team feature gate × team context** | absent ⇒ plain subagent, `name` silently ignored |
| `E` | the `name` argument | absent ⇒ plain subagent |
| `Wt` | agent type is the built-in **fork** and fork is available | fork ⇒ plain subagent |
| `PF(f,je)` | requested type is (or normalizes to) the built-in **web-fetch** agent (`@18878540`) | **260-only guard** ⇒ plain subagent |
| `C` | `isolation` argument | **set ⇒ plain subagent (silent demotion)** |
| `ye` | `cwd` argument | **set ⇒ plain subagent (silent demotion)** |

No telemetry, no warning, no notification is emitted on the `C`/`ye` demotion — it is a
fall-through, not a branch with a message. That is the whole of F-a and it is present in 2.1.260.

### 5.2 `spawnTeammate` dispatcher (`ce`, exported as `spawnTeammate`, `@30784400`)

```js
async function ce(n,e,o){
  if(n.prompt && _H(n.prompt)) throw … "subagent_teammate_protocol_frame_prompt";
  if(Cqe()) return z(n,e);                       // in-process
  try{ await Ndt(); }                            // resolve a pane backend
  catch(_){ if(MPe()!=="auto") throw … "subagent_teammate_pane_unavailable";
            t("[handleSpawn] No pane backend available, falling back to in-process: "+l(_));
            dln(); _e(e.toolState.get(ne),o); return z(n,e); }
  if(n.use_splitpane!==!1) return pe(n,e);       // iTerm2 pane
  return ue(n,e);                                // tmux window
}
```

`Cqe()` = `isInProcessEnabled` (`@27458127`), logs its own decision:
- **non-interactive ⇒ always in-process** (`"isInProcessEnabled: true (non-interactive session)"`);
- `teammateMode` `"in-process"` ⇒ true, `"tmux"`/`"iterm2"` ⇒ false;
- otherwise (auto): true if a prior pane failure latched `inProcessFallbackActive`, else
  `!insideTmux && !inITerm2`.

The auto-fallback surfaces a user notification: *"Couldn't open a teammate pane — running in-process
instead."* plus a mode hint (`@30785193`).

**Decision function, collapsed:**

```
Agent({...})
├─ no name ─────────────────────────────────► local_agent  (sync|async per CSo)
└─ name
   ├─ caller is a teammate ────────────────► THROW subagent_nested_teammate
   ├─ no team context / gate off ──────────► local_agent (name recorded via agentLifecycle.registerName only)
   ├─ subagent_type is fork or web-fetch ──► local_agent
   ├─ isolation set OR cwd set ────────────► local_agent   ◄── SILENT DEMOTION (F-a, still live)
   └─ else spawnTeammate
      ├─ Cqe() ─────────────────────────► in-process teammate   (task in_process_teammate, no paneTeardown)
      ├─ pane backend unavailable
      │   ├─ teammateMode !== "auto" ──► THROW subagent_teammate_pane_unavailable
      │   └─ auto ────────────────────► in-process teammate + notification
      ├─ use_splitpane !== false ──────► iTerm2 pane child      (task in_process_teammate + paneTeardown)
      └─ else ─────────────────────────► tmux window child      (task in_process_teammate + paneTeardown)
```

### 5.3 Child process argv (pane and tmux paths, `@30778700` and `@30780500`)

```
cd <cwd> && env <ENV…> <claude…> \
  --agent-id <teammateId> --agent-name <sanitizedName> --team-name <teamName> \
  --agent-color <color> --parent-session-id <parentSessionId> \
  [--plan-mode-required] [--agent-type <type>] \
  [<permissionMode/proactivity/effort flags>] [--model <model>]
```

Delivered by `backend.sendCommandToPane(paneId, cmd, …)` (iTerm2) or via a tmux
`new-window -t <session> -n teammate-<name> -P -F '#{pane_id}'` then the same command string.
The teammate's *first instruction is written to its inbox before launch*, not passed on argv:
`Ym(name, {from, text: prompt, timestamp}, teamName, storageV5)`; a write failure aborts the spawn
(`subagent_teammate_prompt_write_failed`). All of `--team-name --agent-id --agent-name --agent-color
--parent-session-id --agent-type` are in the CLI's own flag table (`@12673251`) — so `team_name`
exists on 260 as a **CLI flag and hook field**, while the *hook* schema marks `team_name` as
`@deprecated`: *"Sessions have a single implicit team; this carries the session-derived team name and
will be removed in a future release."* (`@13258500`). It is **not** an `Agent()` tool parameter.

### 5.4 The parent-side record — why `TaskStop` says `in_process_teammate`

`te(taskRegistry, {teammateId, sanitizedName, teamName, teammateColor, prompt, plan_mode_required,
paneId, insideTmux, backendType, toolUseId, cwd})` (`@30781150`) is invoked by **both pane paths**:

```js
let E=kh("in_process_teammate"), C=new AbortController,
    k = Cyt(c) ? () => h ??= Aqe(c).killPane(T,!f) : undefined;      // paneTeardown
let D={...Id(E,"in_process_teammate",w,d), type:"in_process_teammate", status:"running", cwd:s,
       identity:{agentId:e,agentName:o,teamName:i,color:_,planModeRequired:r??!1,parentSessionId:K()},
       prompt:m, abortController:C, awaitingPlanApproval:!1, permissionMode:r?"plan":"default",
       isIdle:!1, …, pendingUserMessages:[], paneTeardown:k};
n.register(D); if(k) C.signal.addEventListener("abort",()=>{k()},{once:!0});
```

The true in-process spawner `Brn` (`@30756359`) registers the identical `type` **without**
`paneTeardown`, and additionally carries `identity.resumableAgentId` and a `teammateContext`.

`k2t` — the kill handler `{name:"InProcessTeammateTask", type:"in_process_teammate"}` (`@19134100`) —
races member-removal against `paneTeardown()` with a 10 s bound (`VLn=1e4`) and, on failure, logs the
sentence that settles the whole question:

> `[killInProcessTeammate] pane teardown for <id> reported failure — the backend could not find/kill the pane; its separate \`claude --agent-id\` process may still be running`

**Discriminators available to a caller**: `task.paneTeardown !== undefined` (in-process only, not
serialized), and the team-file member's `backendType` (`"iterm2" | "tmux" | "in-process"`) /
`tmuxPaneId` (`"in-process"` for the in-process case). The *task_type alone cannot tell them apart.*

---

## 6. Hook table

Base fields: every hook input is `ye().and({…})` — `ye()` is the common envelope
(`fa(session, cwd, mode, ctx)`: session_id, transcript_path, cwd, permission_mode, hook_event_name).
Event list (30 events, `@12142516`, identical literal at `@13248786`).

| Event | Payload beyond the envelope | Fired by / when | Can block? |
|---|---|---|---|
| **SubagentStart** | `agent_id: string`, `agent_type: string` (`die`, `@13256300`) | `cgn(...)` inside `runAgent`, before the first turn, once per agent (`@18888700`). Skipped when `Xi(agentContext)` (delegated observation). `managedHooksOnly` for the web-fetch agent. | **No.** A `blockingError` is wrapped by `WLe("SubagentStart", …, "SubagentStart:<agentType>")` and **pushed into the new agent's message list** — the agent starts anyway and sees the block as an attachment. Output schema is `{hookEventName:"SubagentStart", additionalContext?}` only (`@13264814`) — there is no `permissionDecision` field. `additionalContexts` become one `hook_additional_context` attachment. To actually refuse a spawn use the plugin `agent.spawn` hook (`subagent_spawn_denied_by_hook`). |
| **SubagentStop** | `stop_hook_active: boolean`, `agent_id`, `agent_transcript_path` (= `Md(agentId)`), `agent_type`, `last_assistant_message?`, `background_tasks?: Task[]`, `session_crons?: Cron[]` (`pie`, `@13256400`) | `KX(...)` with `d = agentId` (`@20841340`). Real call sites: `"blockable_turn_end"` (`@19646844`), `"loop_tick"` (`@19640565`), `"turn_end_reactions"` (`ex`, `@19653979`), and a 5000 ms best-effort pass in `runAgent`'s cleanup **only when the query was interrupted** (`@18900700`). | **Yes, at `"blockable_turn_end"` only.** `blockingError` ⇒ the message is pushed and the model is re-invoked; `preventContinuation` ⇒ hard stop; `additionalContext` ⇒ `hook_additional_context` **and sets the continue flag** (it is not a whisper). At the other three sites the block is discarded with `[end-turn] Stop hook block discarded …` / `[stop-hooks] Turn-end reaction hook block discarded`. Block chain bounded by the agent's `maxTurns` *and* `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` (default **8**, `@19769400`), whose override message is *"A hook blocked the turn from ending N consecutive times — overriding and ending turn. For Stop/SubagentStop hooks, check stop_hook_active in the input and return su…"*. |
| **TaskCompleted** | `task_id`, `task_subject`, `task_description?`, `teammate_name?`, `team_name?` (deprecated) (`Tie`, `@13259700`) | `c_t(...)` at turn end, **only inside `if(Ji())`** — a session that IS a teammate — once per task the teammate owns with `status === "in_progress"` (`@19650900`). Never in a lead session; never for an unnamed subagent. Requires the task-list store. | **Yes**: `blockingError` ⇒ message pushed; `preventContinuation` ⇒ `hook_stopped_continuation` with `hookName:"TaskCompleted"`. |
| **TaskCreated** | same shape as TaskCompleted (`Sie`, `@13259300`) | `dgn(...)` | same as TaskCompleted |
| **TeammateIdle** | `teammate_name`, `team_name` (deprecated) (`Eie`, `@13259000`) | `ugn(...)`, immediately after the TaskCompleted sweep, same `Ji()` gate | **Yes**, `preventContinuation` ⇒ `hookName:"TeammateIdle"` |
| **StopFailure** | `error`, `error_details?`, `last_assistant_message?` | `CKe` | not a continuation gate |

`background_tasks` on SubagentStop is `Hlr(taskRegistry.all())` (`@20841400`) — per task:
`{id, type: <display name>, status, description}` plus type-specific `command` / `agent_type` /
`server` / `tool` / `name`. The display map is
`{local_agent:"subagent", local_workflow:"workflow", local_bash:"shell", monitor_mcp:"monitor",
monitor_ws:"monitor", mcp_task:"MCP task", in_process_teammate:"teammate", dream:"dream",
auto_mode_scan:"auto-mode scan", remote_agent:"cloud session"}` (`@18708000`) — i.e. **the `type`
field a SubagentStop hook sees is the display label, not the internal task type.**

Non-blockable event set (run under the hooks cgroup, no continuation): `Dge` at `@16523353` includes
`SubagentStart` — a second, independent confirmation of the SubagentStart verdict.

---

## 7. The turn cap

- Source of the limit: `maxTurns: H ?? e.maxTurns` where `H` is the explicit param and `e` the agent
  definition (`@18898028`). Frontmatter/plugin schema: `maxTurns: int().positive().optional()`,
  described as *"Maximum number of agentic turns (API round-trips) before stopping"* (`@13274682`).
- Built-in values found: **fork = 200** (`cI`, `@18998352`), **web-fetch = 15** (`@17220713`),
  agent-summary fork = 1, plugin model fork / memory extraction = small constants. **No literal 100
  appears as an agent default in 2.1.260's strings.** The fleet lesson
  `docs/lessons/in-process-agent-stops-at-100-turns-…` describes a *frontmatter* `maxTurns: 100`, not
  a harness default. [E — negative result; the harness has no default at all, `maxTurns` is `undefined`
  unless a definition sets it, and the query loop's `if(N && …)` guards are all `N`-conditional.]
- **At the cap** (`@19779101`): `yield cn({type:"max_turns_reached", maxTurns:ff, turnCount:Hs})`,
  then `LD(…)`, then `ex(...)` (the non-blocking turn-end reaction pass), then
  `return {reason:"max_turns", turnCount}`. There is also a stop-hook-specific arm at `@19768938`:
  if a Stop/SubagentStop block would push the turn count past `N`, the same attachment is emitted and
  `tengu_stop_hook_block_count` is logged with `hit_max_turns:true`.
- **In `runAgent`** (`@18898979`): logs `[Agent: <type>] Reached max turns limit (<N>)`, emits
  `tengu_agent_max_turns_reached {query_source, is_built_in_agent, max_turns, turn_count, is_async}`,
  yields the attachment and `break`s. **This is a normal exit**, not an error: the agent then
  finalizes as `status:"completed"`.
- **How the partial result is marked:**
  - `gNn(msgs)` (`@18977449`) scans backwards and returns `attachment.maxTurns` **only if nothing but
    meta-user messages follows it** — one assistant message after the attachment and the marker is lost.
  - That value becomes `maxTurnsReached` on the **async notification only**, rendering as
    `stopped at its <N>-turn limit (partial result; <SendMessage> to task-id to continue)` (`@19981500`).
  - The attachment→message mapper renders `max_turns_reached: () => []` (`@21045590`) — it puts
    **nothing** in the conversation.
  - ⇒ **On the synchronous branch a cap-truncated result is indistinguishable from a complete one**
    in the tool_result. The only signals are the log line, the telemetry event, and (if the caller
    reads it) the transcript's trailing attachment.

---

## 8. Spawn depth (`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1` on this box)

```js
var o=3,_="tengu_hazel_trellis";
function $S(){let n=a.CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH; if(n!==void 0)return n;
  let t=Ci(); if(t.maxSubagentSpawnDepthFromGrowthBook===void 0){
    let{getFeatureValue_CACHED_MAY_BE_STALE:r}=…; let e=r(_,o);
    t.maxSubagentSpawnDepthFromGrowthBook = typeof e==="number"&&Number.isInteger(e)&&e>=1 ? e : o;}
  return t.maxSubagentSpawnDepthFromGrowthBook}                       // @14883400
function ac(e){if(e.agentType==="main")return 0; return e.depth??0}   // @13538635
```

Gate: `let de=ac(n.agentContext), be=$S(); if(de>=be) throw … subagent_depth_cap` (`@19025300`).
Depth assigned to the child: `Ks = ac(n.agentContext)+1`. [E] `spawnDepth:1` on every meta.json on disk.

With the env var at 1: main (`ac=0`) may spawn (`0>=1` false); the child runs at depth 1 and
`1>=1` refuses. **No `Agent` call from a subagent succeeds.** Confirmed as a *configuration* effect,
not a product limit — the product default is 3 from GrowthBook `tengu_hazel_trellis`.

### 8.1 A second, less obvious consequence of the cap

`Rq(tools, permCtx, {depth, allowedAgentTypes, activeAgents})` (`@18878900`) ends with `… && r<$S() && …`
and gates the "web pages can only be fetched through the web-fetch agent" affordance. At depth 1 with
`$S()===1`, `1<1` is false, so **a subagent on this box cannot reach WebFetch through the built-in
web-fetch agent either** — the depth cap is not only about fan-out. [I — the predicate is read
correctly; I did not execute the consumer.]

### 8.2 Does a nested agent inherit teardown from its parent's end?

Yes, by three independent mechanisms — none of which is "cascade delete":

1. **Abort linkage.** A backgrounded child registers with `rV({… parentAbortController:D …})`, and
   `ue = D ? Uh(D) : fr()` derives the child's controller from the parent's (`@19988011`). The
   synchronous branch links them explicitly via `Fm = GXe(n.abortController, Ru)` (`@19042100`).
2. **Keepalive back-pressure.** The parent takes `Hv(ownerAgentId, "agent:<childId>", reg)` when it
   spawns, so the **parent's own completion is parked** (`ym`) until the child notifies and
   `pE(owner,"agent:<childId>")` releases it (`gLe`, `@19982400`). This is the *opposite* of teardown:
   a live child keeps the parent's record alive.
3. **Kill cascade on explicit kill.** `jO(id, reg, "parent"|"user")` (`@19983000`) aborts, sets
   `killedBy`, empties `keepaliveReasons`, then kills the agent's monitors
   (`or().killAgentMonitors?.(agentId, reg)`) and every `local_bash` task whose `agentId` matches
   (`killAsyncAgent: killing orphaned shell task <id> (parked owner <id> killed)`).
   `dKn(tasks, reg, reason)` does this across the whole registry.

So: a nested agent **does** die with its parent's abort, but a parent does **not** silently drop a
running child on normal completion — it parks instead.

---

## 9. 2.1.220 → 2.1.260 deltas relevant to this question

| Area | 220 | 260 | Evidence |
|---|---|---|---|
| Named-agent teammate branch | `if(b&&i&&!L&&!s&&!a)` | `if(Ne&&E&&!Wt&&!PF(f,je)&&!C&&!ye)` | `cc220@19994150`, `cc260@19027880` |
| `isolation`/`cwd` demotion | present | **still present** — unchanged | same |
| Async decision | `V = z||(o===!0||W.background===!0||G||B||!C&&o!==!1)&&!j` | adds `!qb(n)&&d`, keeping the **web-fetch agent synchronous**; coordinator arm gains `&&!o` | `cc220@19997500`, `cc260@18175641` |
| Cumulative spawn cap | `subagent_count_cap` / `CLAUDE_CODE_MAX_SUBAGENTS_PER_SESSION` present | **absent** from the Agent tool | `cc220@19993000`; 0 hits for `MAX_SUBAGENTS_PER_SESSION` in the 260 Agent-tool region |
| `in_process_teammate` string count | 118 | 76 | `s.py count` |
| `TaskOutput`/`TaskStop` string count | 53 / 23 | 75 / 41 | `s.py count` |
| Hook event list | same 30 events incl. SubagentStart/Stop, TaskCreated/TaskCompleted, TeammateIdle | unchanged | `cc220`/`cc260` both carry the literal list |

---

## 10. Uncertainties, named

1. **The async-by-default claim (§3) is [I], not [E].** `xz()`/`ke()`/`wi()` were each resolved to a
   definition, but I did not execute a spawn to observe which branch a live 2.1.260 REPL takes, and
   `Ci()` caches `forkSubagentEnabledSource` per host, so a session that once ran headless can carry
   `"disabled"`. **Cheapest refutation:** in a 2.1.260 session, call `Agent({subagent_type:"…",
   run_in_background:false, prompt:"echo"})` and look at whether the tool_result is
   `status:"completed"` or `status:"async_launched"`. A second arm: `CLAUDE_CODE_FORK_SUBAGENT=0` and
   repeat — it should flip to `completed`.
2. **220's `G`/`B` identities** (`By()`, `TSe()`) were not resolved; I assert only that 220's
   expression has the same *shape*, not that the gates are the same functions.
3. **`zr()` (the team feature gate)** was not resolved. If it is false on this box, `Ne` is `undefined`
   and **no `name:` ever reaches `spawnTeammate`** — every named Agent would be a plain subagent
   regardless of isolation/cwd. That would make §5.1's demotion finding moot in practice while leaving
   it true in code. This is the single largest open question and it is cheap to settle: spawn one
   named agent and read whether the result is `status:"teammate_spawned"`.
4. **The `.output` symlink target** is asserted from `PV` + the TaskOutput prompt text. I did not
   `ls -l` a `tasks/*.output` to confirm, because the live session's own task dir was in flight.
5. **`ai(taskId, status, {…})`**, the sibling of `ca(...)` used in the Agent tool's synchronous
   `finally`, was not resolved to a definition — it is imported into the task chunk and I did not
   locate the exporter. What it *does* is therefore inferred from its call shape
   (`ai(sd, "completed"|"failed"|"stopped", {toolUseId, summary, usage:{total_tokens, tool_uses,
   duration_ms}})`) and from sibling call sites that pair it with `ca(...)`. **The claim "the sync
   branch also emits a lifecycle event" is [I]; the claim "the sync branch returns a tool_result" is [E].**
6. **`maxTurns` default:** a negative result. I searched `maxTurns:`, `maxTurns??`, `maxTurns=` and
   `Maximum number of turns` and found no harness-level default. If one exists it is computed, not a
   literal.

### Adversarial pass — what would refute "nothing persists after an unnamed agent ends"

Run in a session that has spawned at least one subagent:

```
ls -l ~/.claude*/projects/<proj>/<sid>/subagents/          # jsonl + meta.json, both survive
ls -l ~/.claude*/projects/<proj>/<sid>/tasks/*.output      # symlinks into subagents/
```

Anything found there refutes it — and on this box the first command already does (§4.2 [E]). The
in-process refuters are `everRegisteredTaskIds` (no removal path), `outputPathBindings`,
`linkedOutputs`, `agentNameRegistry`, and — for up to 30 s, or indefinitely under `retain`/keepalive —
`AppState.tasks[id]` itself, still holding the full `result`.

---

## 11. Re-derivation

```bash
cd /private/tmp/claude-501/-Users-chrisren-Development-claude-infrastructure/\
e442434c-1a96-4c04-b06e-ac89c2f9891a/scratchpad/
python3 s.py count in_process_teammate SubagentStart SubagentStop TaskCompleted subagent_depth_cap
python3 -c "import s; d=s.load('260'); print(d[19024660:19034000])"   # Agent tool call()
python3 -c "import s; d=s.load('260'); print(d[18175101:18176400])"   # jwn + CSo
python3 -c "import s; d=s.load('260'); print(d[30781000:30785300])"   # teammate dispatcher
python3 -c "import s; d=s.load('260'); print(d[13256050:13260000])"   # hook input schemas
python3 -c "import s; d=s.load('260'); print(d[18987319:18999400])"   # Z9 run wrapper
```

Bash `grep` in this environment is rewritten to `ugrep`; use `/usr/bin/grep -F` or the python
helpers above. Offsets are into the strings dumps and will shift if the dumps are regenerated —
re-anchor on the quoted string literals, which are stable within a binary version.

# B — The vendor idle/shutdown protocol re-verified on Claude Code 2.1.260

**Subject**: re-verification of `docs/research/SUBAGENT_LIFECYCLE_SIGNAL_DISCONNECT_2026-08-04.md`
(measured on 2.1.220) against **2.1.260**, plus the mechanism by which an *idle* teammate fails to
process a queued `shutdown_request` (measured 2026-08-26: mid-turn 3/3 reaped, idle 0/4 —
`skills/agent-teams/SKILL.md:361-372`).

**Instrument.** All offsets below are byte offsets into the `strings -a` dumps, not into the Mach-O:

```
strings -a ~/.claude-260/node_modules/@anthropic-ai/claude-code/bin/claude.exe > cc260.strings   # 44,711,007 B
strings -a ~/.claude-220/node_modules/@anthropic-ai/claude-code/bin/claude.exe > cc220.strings   # 37,315,427 B
python3 -c "d=open(P,errors='replace').read(); i=d.find(N); print(d[i-1200:i+1200])"
```
Dumps live at `/private/tmp/claude-501/-Users-chrisren-Development-claude-infrastructure/e442434c-1a96-4c04-b06e-ac89c2f9891a/scratchpad/{cc260,cc220}.strings`.
Every claim marked **[code]** is read from the dump at the cited offset; **[inferred]** is reasoning
over those reads; **[measured-elsewhere]** cites the fleet's own logs/skills.

**Name map (260 ← 220).** The 2026-08-04 doc's identifiers were remangled by the 260 build:

| 220 | 260 | meaning (from the module's own export map, 30823502) |
|---|---|---|
| `Yze` | `P3` | zod schema for `idle_notification` |
| `cdr` | `iNe` | `createIdleNotification` — sole constructor |
| `tvd` | `Ae` | in-process send-idle wrapper (30738852) |
| `mdr` | `Q_n` | `getLastPeerDmSummary` |
| `JSb` | *(gone)* | the `Agent idle · Task X resolved` string renderer — **removed on 260** |
| `xwr` | `Na` | the panel renderer actually used (34681564) |
| `$Eb` | `Oy`→`Na` dispatch | mailbox frame router (34678883, 34704431) |
| — | `SSe`/`ko` | **NEW on 260**: `{result, summary}` extractor (30728985) |
| — | `ct` | **NEW on 260**: `sanitizeReceivedIdleFrame` (15185024) |

---

## 1. (a) The `idle_notification` schema and every producer of the completion channel

### 1.1 Schema — unchanged except one added field

`P3` at **15182536** (cc260):

```js
var P3=m(()=>c({type:k("idle_notification"),from:s(),timestamp:s(),
  idleReason:Y(["available","interrupted","failed"]).optional(),
  summary:s().optional(),completedTaskId:s().optional(),
  completedStatus:Y(["resolved","blocked","failed"]).optional(),
  failureReason:s().optional(),result:s().optional()}))
```

`result: s().optional()` is **new on 260** (220's `Yze`, cc220 6278158/18145740, has no `result`).
Everything else is byte-identical to the 2026-08-04 transcription.

### 1.2 `completedTaskId` — 17 occurrences on 260, all accounted for, **zero assignments**

| offset(s) (cc260) | what | producer? |
|---|---|---|
| 6319338 | constant/string table | no |
| 15182664 | the `P3` zod schema | no |
| 15185024 · 15185054 · 15185075 · 15185097 · 15185435 | inside `ct` (`sanitizeReceivedIdleFrame`) — reads `n.completedTaskId`, re-emits it | **pass-through only** |
| 15187402 | the `mur` sanitisation spec map (`completedTaskId:{kind:"id"}`) | no |
| 15189597 · 15189615 | inside `hur` (drain-budget truncator) — copies the field while rewriting `result` | pass-through |
| 15190389 · 15190408 | inside `iNe` — `completedTaskId:n?.completedTaskId` | **pass-through of the caller's arg** |
| 34678883 · 34678902 · 34704431 · 34704450 | two renderer call sites passing it into `Na` | reader |
| 34681564 | `Na`'s destructure | reader |

`completedStatus` — 8 occurrences: 7394293 (string table), 15182695 (schema), 15187430 (spec map),
15189631/15189649 (`hur` pass-through), 15190424/15190443 (`iNe` pass-through), and **30754778, the
one and only assignment**:

```js
// 30754758 — inProcessRunner agent_loop_failed
await Ae(e.agentName,e.color,e.teamName,
  {idleReason:"failed",completedStatus:"failed",failureReason:K,result:x},d.storageV5)
```

⇒ **`completedTaskId` is assigned nowhere in 2.1.260. `completedStatus` is assigned once, to
`"failed"`, on the in-process crash path.** The success-terminal values `resolved` / `blocked` are
produced by nothing. **The 2026-08-04 headline finding holds unchanged on 260.** [code]

The three `iNe` lifecycle call sites are the complete producer set (the other four `iNe(` hits —
19269398, 19271050, 19271144 — are an unrelated same-named file-IO helper):

| offset | caller | payload |
|---|---|---|
| 30738852 | `Ae(n,e,s,_,o)` wrapper | whatever its caller passes |
| **35334617** | the TeammateInit `Stop` function hook | `{idleReason:"available",summary:jt,result:st}` |
| **35335286** | `r6e`, the pane-teammate API-failure path | `{idleReason:"failed",failureReason:Se,summary:Ee,result:xe}` |

All three pass **object literals** — no spread can smuggle `completedTaskId` in. [code]

### 1.3 Correction to the 2026-08-04 enumeration *method*

That doc reported `idleReason:"available"` as "a hardcoded literal" with one site, and (by the same
grep shape) would have found zero producers of `"interrupted"`. Both are artifacts of literal search.
At **30753150** (inside the in-process turn-end block) the reason is a **ternary**:

```js
let N=await Ae(e.agentName,e.color,e.teamName,
  {idleReason: ae?"interrupted": Ie!==void 0?"failed":"available",
   summary:r.summary,failureReason:Ie,result:f,senderReachable:Ie===void 0||re}, d.storageV5)
```

⇒ `"available"` has **two** producers on 260, and `"interrupted"` has **one** — not zero.
A literal grep for `idleReason:"X"` under-counts a ternary. (Fleet memory:
`lookup-miss-is-not-absence`.) [code]

There is also a **fourth** frame shape the 2026-08-04 doc could not have seen, at **30752160**: a
*turn-end mailbox check* that fires `Ae(...)` with **`idleReason: undefined`** purely to carry a
`result`. `Na` maps `undefined` through the same `wa==="failed"?…:wa==="interrupted"?…:"success"`
ternary, so it renders as **`✓ Teammate @X finished`** in green too. [code]

### 1.4 The renderer — `JSb` is gone; the dead branch went with it

`Na` (34681564) destructures `{displayName,inkColor,idleReason,failureReason,summary,completedTaskId,
result,expanded}` and computes:

```js
rC = wa==="failed"?"error":wa==="interrupted"?"warning":"success"
nC = wa==="failed"?"failed":wa==="interrupted"?"was interrupted":"finished"
```

`✓ Teammate @X finished` in success green, at every turn boundary — **unchanged from 220**. New on
260: `Na` renders `result` (expanded: in full; collapsed: a one-line condensation via `iC`), and
renders `(task #<completedTaskId>)` **only when `expanded`** — still dead, because nothing assigns
the field. 220's `JSb` (the `Agent idle · Task N resolved` formatter) no longer exists in the 260
dump; the completion channel is now dead in one way rather than two. [code]

---

## 2. The one real 260 change: a `result` channel that partially closes mode 5

`SSe(e,r)` → `ko(e,r)` at **30728985** walks the turn's live messages backwards to the last turn
boundary (`oSt` = a non-meta user message carrying no tool_result) and returns `{result, summary}`:

- if the turn contains a **successful** `SendMessage` tool_use addressed to the lead
  (`f.input.to===ms || f.input.to===ip`, `c.get(f.id)===true`), it returns `{result: undefined}` and
  emits `swarm_idle_result_delivery / suppressed_lead_dm` — a deliberate de-dupe;
- otherwise it takes the last assistant message's **text blocks**, joined, sanitised, and returns
  them as `result`.

That text is carried to the lead in `idle_notification.result`, capped at `NI = 4000` chars per frame
(`fur` = `capIdleResult`) and `EXn = 16000` chars per mailbox drain (`hur`, 15188894), with overflow
replaced by `[result truncated — ask the agent for the rest via SendMessage]`. Telemetry
`swarm_idle_result_delivery` reports `ok / per_frame_truncated / budget_truncated /
mailbox_write_failed / suppressed_lead_dm` (`oAe` = `logIdleResultDeliveryOutcome`, 15190520ish). [code]

⇒ **On 2.1.260, the 2026-08-04 mode-5 claim — "a subagent's prose is not visible to anyone; only a
tool call transmits" — is FALSE for a named teammate.** The last assistant message of each turn is
now transmitted to the lead automatically, bounded. The claim remains true for text beyond 4 KB, for
text that is not in the final assistant message of the turn, and (by construction) it is *not* a
completion signal — it fires at every turn boundary exactly as `idleReason` does.

The SendMessage tool description still asserts the old rule verbatim —
*"Your plain text output is NOT visible to other agents — to communicate, you MUST call this tool"*
(29603204) — which is now an over-statement of its own runtime. Keep the fleet's Delivery-contract
discipline anyway: `result` is a 4 KB tail, not a deliverable.

---

## 3. (b) How a teammate waits, and what starts a new turn

**There are two entirely different wait mechanisms, selected by teammate shape.** Conflating them is
the single largest hazard in this area. `rMt()` (36402040) computes the identity:

```js
function rMt(){ if(WN())return{kind:"in-process"}; if(Ji())return{kind:"teammate",agentName:kp()}; return{kind:"session"} }
function mse(w,H){ switch(w.kind){ case"in-process": return;            // <-- undefined
  case"teammate": return w.agentName;
  case"session": { if(LC(H.teamContext)){...return "team-lead"} return } } }
```

`Ji()` (12829109) = `Xy() || !!(dynamicTeamContext?.agentId && dynamicTeamContext?.teamName)` — **"I
am a team member"**. `LC(e)` (12830257) = **"I am the lead"**. `kp()`/`ri()` (12828888) = self agent
name / team name. [code]

### 3.1 Out-of-process (pane) teammate → the `InboxPoller`, a React-hosted 1 Hz timer

Class `n1e`, hook `r1e`, both at **36402291–36419400**. Wired from the main REPL render at
**36575699**:

```js
jOo={enabled:VDt,isLoading:eT,visibleDialogKind:qDt,onSubmitMessage:Ui.submitIncomingPrompt,requestDialog:Fu}; r1e(jOo)
```

- Transport is a **file**, not a socket: `sNe()` (15174388) → `<CLAUDE_CONFIG_DIR>/teams/<team>/inboxes/<agent>.json`
  (plus an optional storage-v5 mirror via `Ae.mailbox(team,agent)`). `CLAUDE_CODE_MESSAGING_SOCKET`
  is the *cross-session peer* channel, not the team mailbox.
- `#f()` starts a `setTimeout` chain at **`fIo = 1000`** ms (36402287) iff `enabled && mse(identity,state)`.
  For `kind:"in-process"` `mse` returns `undefined` ⇒ **the InboxPoller never runs for an in-process
  teammate**.
- `#y()` (the tick) reads unread messages (`mpe` = `readUnreadMessages`), sorts them into buckets by
  type, and decides delivery:

```js
if(_o.length>0&&Ji()){ t(`[InboxPoller] Found ${_o.length} shutdown request(s)`); for(let ko of _o)Co.push(ko) }   // 36415200ish
...
if(Co.length===0){Yt();return}
let Eo=fre(Co,{recipientIsLead:LC(Xe.teamContext)}),
    Vo=()=>{ Se((ko)=>({...ko,inbox:{messages:[...ko.inbox.messages,...Co.map(b=>({...,status:"pending"}))]}})) };
if(!Ee&&!Oe){ t("[InboxPoller] Session idle, submitting immediately");
              if(!He(Eo)) t("[InboxPoller] Submission rejected, queuing for later delivery"), Vo() }
else t("[InboxPoller] Session busy, queuing for later delivery"), Vo();
Yt()       // <-- markMessagesAsRead, UNCONDITIONAL
```

`Ee`=`isLoading`, `Oe`=`visibleDialogKind`, `He`=`onSubmitMessage`. **Which message types start a new
turn**: everything that lands in `Co` — ordinary messages, `shutdown_request` (when `Ji()`),
`plan_approval_request` (lead only), `shutdown_approved` (lead only), and any protocol frame the
router could not place. Explicitly **dropped and never delivered**: `team_permission_update`
("permission rules are never accepted from the inbox") and `mode_set_request`. [code]

Three structural hazards, all citable:

1. **`Yt()` marks the on-disk messages read unconditionally**, whether or not `onSubmitMessage`
   accepted them. A refused delivery consumes the durable copy. (Fleet lesson:
   `a-reader-that-cannot-prove-delivery-must-not-consume`.)
2. **`submitIncomingPrompt` can refuse, and refuses silently** (36331905):
   ```js
   submitIncomingPrompt=(w,H)=>{ if(this.guard.isActive)return!1;
     let{mainLoopModel:ne,messageQueue:pe}=this._requireHost();
     if(pe.getCommandQueue().some((xe)=>xe.mode==="prompt"||xe.mode==="bash"))return!1;
     ... return this.run([Se],fe,!0,[],ne),!0 }
   ```
   `this.guard` is the turn guard; `isQueryActive: this.guard.isActive` (36299024). So delivery is
   refused while **a query is in flight**, or while **any queued prompt/bash command is pending**.
3. **The in-memory pending queue has exactly ONE drain, and it is edge-triggered.** `#w()` runs only
   from `start()` and from `setInputs` when one of `{enabled,isLoading,visibleDialogKind,
   onSubmitMessage}` changes identity; it bails immediately on `if(pe||fe)return` (isLoading or a
   dialog). The 1 Hz timer only ever re-reads **disk**, which `Yt()` has already emptied. ⇒ a message
   refused at a moment after which no input-identity change occurs is **stranded permanently, with
   the disk record showing it delivered**. [code]

   (`#w()` also cleans up messages with `status==="processed"` "that were delivered mid-turn" — but
   `status:"processed"` is assigned nowhere in the dump; only `status:"pending"` is written, at
   36416422 and 36417869. That branch is dead.)

### 3.2 In-process teammate → the runner's own poll loop `Ye`, which prioritises shutdown

`Ye(n,e,s,_,o,m,T,d,w,C=!1,M)` at **30742622**, called at **30753226** immediately after the turn-end
idle notification (`… finished prompt, waiting for next`). Per tick (interval `be`) it:

- returns any `pendingUserMessages[0]` first;
- calls `Se(...)` (30740020), the mailbox check, which **scans for the first unread
  `shutdown_request` and returns it ahead of every other unread message**, logging
  `received shutdown request from <x> (prioritized over N unread messages)`, after first flushing
  held non-protocol messages (`delivering N held message(s) ahead of a shutdown_request`) and marking
  the request read with `g9t` (`markSingleMessageAsRead`);
- `ke()` then re-enters the agent loop with the request as a user message.

`if(T)continue;` skips the mailbox check entirely — `T` is the `standalone` flag (`standalone: l=!1`
in `Je`'s destructure at 30747400ish), so it does not apply to teammates. [code]

**There is still no idle timeout.** `{type:"idle_timeout"}` is constructed **0 times** in cc260 (and
0 in cc220); only the `case "idle_timeout":` arm at 30746972 exists, and its body is unreachable.
The loop's `c = Date.now()` is assigned in four branches and **compared to nothing** — re-verified on
260. `evictAfter` remains a UI-list filter, pushed forward by `Xw` while any sibling is busy. [code]

---

## 4. (c) `shutdown_request` on the teammate side — model-mediated, with a new in-band instruction

**Approval is never runtime-level.** [code]

### 4.1 The request is delivered as an ordinary user message, wrapped with explicit instructions

`cNe` = `withShutdownReplyInstructions` (**15197634**) and `Sur` = `shutdownRequestReplyInstructions`
(**15197141**) — both **new on 260**:

```js
function Sur(e){let n=un.test(e),r=S({to:ms,message:{type:"shutdown_response",request_id:n?e:ln,approve:!0}});
  return `To approve it, call ${Vr} with exactly this input, where "message" is a JSON object rather than a string`
   +`${n?"":" and request_id is the request's requestId value, copied verbatim"}: ${r}. `
   +`Approving ends your process; a plain-text acknowledgment does not shut you down. `
   +`To decline, for example because you're mid-task, send the same input with "approve": false and a "reason".`}
function cNe(e,n){ if(n!==ms||!e.includes('"shutdown_request"'))return e;
  let r=sAe(e); return r?`${e}\nThis is a shutdown request. ${Sur(r.requestId)}`:e }
```

Two consequences worth naming:

- **The vendor now says out loud, in-band, that a prose answer does nothing.** That sentence exists
  because prose answers are the observed failure.
- **`cNe` only fires when `n === ms`** (the sender is the literal `team-lead` id). A `shutdown_request`
  from any other sender is delivered with **no instructions at all**. `fre` applies `cNe` only on the
  non-lead branch (`n.recipientIsLead ? i : {...i,text:cNe(i.text,i.from)}`, 15174900ish). [code]

The tool prompt also carries a **`## Protocol responses (legacy)`** section (29603204) — the word
*legacy* is the vendor's — gated on `Ge(zr())` where `zr` is the agent-teams-enabled flag
(`!a.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS && !argv.includes("--agent-teams") ⇒ false`, 31329000ish).
With agent teams on, the section is present. [code]

### 4.2 What the model must emit, and what happens if it does

`SendMessage`'s structured form is still a **closed 3-member discriminated union** `Ds` (29605541):
`shutdown_request` · `shutdown_response` · `plan_approval_response`. `idle_notification` is not
constructible through it, and the plain-string form still refuses lifecycle frames with errorCode 9
(*"message text must not be a teammate lifecycle/task frame … send plain text instead"*, 29627900).
New validation on 260: `shutdown_response` must go to `team-lead`; `approve:true` with a `reason` is
**rejected**; `approve:false` without a `reason` is **rejected**. [code]

The actuator `zs` (**29616090**) — materially stronger than 220's `oJ_ → abortController.abort()`:

```js
async function zs(e,n){ ...look up own tmuxPaneId+backendType from the team file...
  let _=z_n({requestId:e,from:d,paneId:b,backendType:i}),
      j=await Ym(ms,{from:d,text:S(_),...},f,n.storageV5);     // write shutdown_approved to the lead
  if(i==="in-process"){ ...W.abortController.abort()... }
  else { if(r){...fallback abort if an in-process task is found...}
         setImmediate(async()=>{ await Rn(0,"other") }) }        // <-- OUT-OF-PROCESS: process exit(0)
  return {data:{success:!0,message:`Shutdown approved. ${C} Agent ${d} is now exiting.`,request_id:e}} }
```

- **in-process** → `abortController.abort()`;
- **pane/tmux** → the teammate writes `shutdown_approved{paneId,backendType}` to the lead's inbox and
  then **exits its own process**; the *lead's* InboxPoller `So` branch closes the pane
  (`killPane(Bo.paneId, !Go)`, 36416000ish) and calls `yIo` to drop the member from `teamContext` and
  mark its tasks completed.

**If the model answers in prose:** nothing at all happens. No confirmation is written, the turn ends,
a fresh `idle_notification{idleReason:"available"}` goes to the lead (rendering as
`✓ Teammate @X finished`), and the wait resumes. There is no timeout, no retry, no escalation, and no
runtime fallback on any path. [code]

---

## 5. TeammateIdle hook contract on 2.1.260

### 5.1 Locus — **teammate-side, not lead-side**. This contradicts two fleet documents.

`executeTeammateIdleHooks` = `ugn` (**20842361**) has **exactly one call site in the whole binary**,
at **19651537**, inside `p2n` — the Stop-hook pass — behind `if(Ji())`:

```js
// 19650875 → 19651537, inside p2n (the Stop pass)
if(Ji()){                                   // Ji() === "I am a team member"
  let Mt=kp()??"", bn=ri()??"", un=xE(),
      $n=(await aC(un,f.storageV5)).filter((Cn)=>Cn.status==="in_progress"&&Cn.owner===Mt);
  for(let Cn of $n){ let Un=c_t(Cn.id,Cn.subject,Cn.description,Mt,bn,…);   // TaskCompleted hooks
      … if(wn.blockingError){ let Et=Re({content:Ojt(wn.blockingError),isMeta:!0}); xe.push(Et),yield Et }
        if(wn.preventContinuation) Oe=!0, yield cn({type:"hook_stopped_continuation",hookName:"TaskCompleted",…}) }
  let lr=ugn(Mt,bn,Ke,f.abortController.signal,void 0,f);                    // TeammateIdle hooks
  for await(let Cn of lr){ … same three consumers … }
  if(Oe) return yield*ex(f,U.messages,{stopHookActive:E}),{blockingErrors:[],preventContinuation:!0};
  if(xe.length>0) return {blockingErrors:xe,preventContinuation:!1} }
```

and the payload is built from **self**: `{...fa(session,cwd,r), hook_event_name:"TeammateIdle",
teammate_name:e, team_name:n}` with `e = kp()` (20842361). The vendor's own hook documentation
agrees (**10107734**):

> **When a teammate is about to go idle** · Input to command is JSON with `teammate_name` and
> `team_name`. · Exit code 0 — stdout/stderr not shown · **Exit code 2 — show stderr to teammate and
> prevent idle (teammate continues working)** · Other exit codes — show stderr to user only

"show stderr **to teammate**" is the vendor naming the recipient. The same structure is present on
**220** (cc220 18427857), so this was never a 260 change. [code]

⇒ **Two fleet documents are wrong about the locus:**
`docs/research/SUBAGENT_LIFECYCLE_SIGNAL_DISCONNECT_2026-08-04.md:577` — *"`TeammateIdle` — **NO —
fires in the LEAD**; the teammate never sees it"* — and `hooks/teammate-auto-shutdown.sh:3` — *"Fires
(LEAD-side) when a teammate goes idle"*.

**And here is the reconciliation, which matters more than the correction.** For an **in-process**
teammate the agent loop runs *inside the lead's `claude.exe`*, so the hook process's ancestry really
is `lead-claude → /bin/sh -c → bash` — exactly what `teammate-auto-shutdown.sh:34-38` observed when
it retired `kill -TERM $PPID`. The observation was true; the *cause* attached to it ("this is the
lead's hook") was not. The hook fires in the **teammate's agent context**, executed by whichever
**process** hosts that context. This is the fleet's own
`wrong-cause-corroborated-by-true-metric` shape. [code] + [measured-elsewhere]

### 5.2 Exact effect of each return, on 2.1.260

The output mapper is `nme(...)` at **20850304**; the exit-2 path is the script runner at **20919750**
(`Zt = ct.status===2 || !!fn || Wt`, with `Ct = stderr` when status ≠ 0).

| Hook output | Mapped to | Effect in the TeammateIdle consumer (19651537) |
|---|---|---|
| **exit 0, `{"continue": false}`** (the fleet's hook) | `preventContinuation:true` (+`stopReason`) | `Oe=true` → yields `{type:"hook_stopped_continuation",hookName:"TeammateIdle"}` → `p2n` returns `{preventContinuation:true}` after running `ex(...)` → the query returns `{reason:"stop_hook_prevented"}`. **The turn ends. The process does NOT exit.** The idle notification still goes out, because `ex()` runs on this path. |
| **exit 0, plain (no JSON)** | nothing | no effect; stdout/stderr not shown |
| **exit 2** | `blockingError{blockingError:stderr,command}` | `xe.push(Re({content:`TeammateIdle<sep><stderr>`,isMeta:true}))`, yielded to the transcript, then `return {blockingErrors:xe,preventContinuation:false}` → the query loop appends them and **`continue`s: the teammate takes another turn**. `ex()` is **not** run on this path ⇒ **no `idle_notification` is emitted that cycle.** |
| **exit 0, `{"decision":"block","reason":"…"}`** | `permissionBehavior:"deny"` **and** `blockingError{blockingError:reason\|\|"Blocked by hook"}` | identical to exit 2 — another teammate turn, seeded with `reason`. |
| **`{"systemMessage":"…"}`** | `N.systemMessage` | surfaced to the user; the TeammateIdle consumer loop does not read it. |
| **`hookSpecificOutput.additionalContext`** | survives `nme`/`D2r` into the hook answer | **uncertain**: the TeammateIdle consumer at 19651537 reads only `.message`, `.blockingError`, `.preventContinuation`. It would have to arrive as an `attachment` `message` from `ky` to reach the model. I did not find an `additionalContext`→attachment conversion keyed on `TeammateIdle`. Treat as **not delivered** until someone runs the positive control. |
| **`{"async": true}`** | `{json:{async:true}}` (`mgn`, 20849500ish) | hook detaches; no blocking, no context. |

### 5.3 Ordering — a blocking settings `Stop` hook *suppresses* TeammateIdle entirely

Inside `p2n`, settings `Stop` hooks are evaluated **before** the `Ji()` block, and:

```js
if(Me) return yield*ex(f,U.messages,{stopHookActive:E}),{blockingErrors:[],preventContinuation:!0};
if(Ce.length>0) return {blockingErrors:Ce,preventContinuation:!1};      // <-- NO ex(), NO TeammateIdle
if(Ji()){ …TaskCompleted… …TeammateIdle… }
if(!D()) yield*ex(f,U.messages,{stopHookActive:E});
```

⇒ Whenever any registered `Stop` hook blocks — `hooks/session-continue.sh`, `completion-assert.sh`,
the ship floor — **`teammate-auto-shutdown.sh` is never invoked on that Stop, and no
`idle_notification` is emitted either.** [code]

### 5.4 `ex()` is where the idle notification actually fires

```js
// 19653927
async function*ex(e,n,{stopHookActive:r}){ try{
  let o=KX(ce(e).mode,e.abortController.signal,void 0,r,e.agentId,e,n,e.agentType,"turn_end_reactions");
  for await(let d of o){ if(d.message)yield d.message;
    if(d.blockingError||d.preventContinuation)
      t(`[stop-hooks] Turn-end reaction hook block discarded: …`) } } catch(o){…} }
```

`"turn_end_reactions"` selects `sessionFunctionHooksOnly` (20842000ish) — i.e. exactly the
`addFunctionHook(…,"Stop",…, {id:"teammate-idle-notification"})` registered by TeammateInit at
**35334617**:

```js
if(xe===He){ t("[TeammateInit] This agent is the team leader - skipping idle notification hook"); return }
H.addFunctionHook(ne,"Stop","",async(Xe,it)=>{ N5e(Se,Ee,!1,fe);                       // team file isActive=false
  let{result:st,summary:jt}=SSe(Xe,{emitTelemetry:!0});
  let At=iNe(Ee,{idleReason:"available",summary:jt,result:st}),io;
  try{ io=await Ym(Je,{from:Ee,text:S(At),timestamp:…,color:Qy()},void 0,fe) } finally{ oAe(At,st,io) }
  return …,!0 }, "Failed to send idle notification to team leader",{timeout:1e4,id:"teammate-idle-notification"})
```

Two things follow. **(i)** Any `blockingError` or `preventContinuation` a *session function* hook
returns at turn end is explicitly **discarded** with a debug line — so a function hook cannot hold a
turn. **(ii)** The `idle_notification` is emitted **only on Stop passes that reach a non-blocking
outcome (or a `preventContinuation`)** — never on a pass a settings hook blocked. [code]

---

## 6. (e) Does a blocking Stop hook start a new turn without draining the inbox? — **Yes.**

A blocking Stop hook does **not** return to the REPL. At **19769076** the query generator does:

```js
Oe={messages:[...kr,...Ts,...dm.blockingErrors], toolUseContext:Et, …,
    stopHookActive:!0, stopHookBlockingCount:qd, turnCount:Ac, transition:{reason:"stop_hook_blocking"}};
continue;                                     // <-- same generator, same query
```

bounded only by `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP ?? 8` (and `maxTurns`). Therefore, for the whole
chain:

- `guard.isActive` stays **true** and `isLoading` stays **true** ⇒ `submitIncomingPrompt` refuses
  every inbox delivery (`if(this.guard.isActive)return!1`);
- `#y()` takes the `"[InboxPoller] Session busy, queuing for later delivery"` branch — and still
  calls `Yt()`, so the durable inbox record is consumed;
- `#w()` bails at `if(pe||fe)return`;
- no `idle_notification` is emitted for those cycles (§5.3).

So a blocked chain *does* start new turns without draining the inbox, and it does so **silently in
both directions** — the lead hears nothing, and the teammate never sees the message. The recovery is
the `isLoading` true→false edge at the end of the chain, which fires `#w()`. [code]

---

## 7. (f) TaskCompleted — two producers, no link to termination

| offset | producer | behaviour on a blocking hook |
|---|---|---|
| **19415818** | `TaskUpdate` when `status` transitions to `"completed"` | the blockingErrors are joined and returned as `{success:false, error:…}` — **the task update fails**. |
| **19650875** | the teammate's own Stop pass, for **every task with `status==="in_progress"` and `owner===self`** | `blockingError` → another teammate turn; `preventContinuation` → turn ends. |

The second is worth flagging on its own: on 260 `TaskCompleted` fires at **every teammate turn end**
for each *still-in-progress* task it owns — i.e. it doubles as a "you are going idle holding this
task" hook. The fleet has `task-quality-gate.sh` registered on `TaskCompleted` with a **120 s
timeout** (`~/.claude/settings.json`), which on this path runs a typecheck once per open task per
turn boundary. [code] — I did not measure how often that actually fires; the filter is read directly
from the dump and is unambiguous, but the *intent* is not, so treat the label "going-idle hook" as
[inferred].

**Nothing about `TaskCompleted` terminates anything.** The only path from a task to a teammate's death
is the reverse: `yIo` (36417869), run by the **lead** on receipt of `shutdown_approved`, marks the
departed member's tasks `completed` and injects a `teammate_terminated` frame. [code]

---

## 8. VERDICT — Why an idle teammate ignores a queued `shutdown_request`

**There is no single code path that "ignores" it. There are two disjoint failure modes, selected by
teammate shape, and the 2026-08-26 measurement lands squarely on the second.**

### The named code path

`skills/agent-teams/SKILL.md:368` records that `TaskStop` reaped all four idle survivors and that
each returned **`task_type: in_process_teammate`**. That fact settles which mechanism was in play:

- the four survivors were **in-process** teammates ⇒ `mse()` returned `undefined` for them (36402040)
  ⇒ **the `InboxPoller` never ran in their context at all**; their wait was `Ye`/`Se`
  (30742622 / 30740020), which **explicitly prioritises `shutdown_request` over every other unread
  message** and marks it read only as it hands it to the model;
- so the frame was **delivered**, wrapped by `cNe`+`Sur` with a verbatim approval command
  (15197141 / 15197634);
- the approval is **model-mediated with no backstop**: only `SendMessage{type:"shutdown_response",
  approve:true}` → `zs` (29616090) → `abortController.abort()` / `Rn(0)` terminates anything. There
  is no runtime auto-approval, **no idle timeout anywhere in the binary** (`{type:"idle_timeout"}`
  constructed 0×), no retry, and no escalation;
- each unanswered request cost exactly one turn; each turn end re-ran the emitter (35334617 /
  30753150) ⇒ a fresh `{"idleReason":"available"}` to the lead, rendered `✓ Teammate @X finished`
  (34681564). **That is precisely the observed "kept emitting `idle_notification` for 20-40 minutes
  with a queued shutdown."**

⇒ **Primary verdict (in-process teammates, the measured population): the runtime delivers the
`shutdown_request` correctly and then has nothing to enforce it with. The failure is at the
model/compliance layer — a prose acknowledgment — and the protocol has no producer for the terminal
state, so a non-answer is indistinguishable from an answer that has not arrived yet.** The vendor's
own new in-band sentence — *"Approving ends your process; a plain-text acknowledgment does not shut
you down"* — is the vendor patching this same failure with more prompt. [code] + [measured-elsewhere]

**Why mid-turn 3/3 and idle 0/4 under this reading** [inferred, and this is the weakest link in the
chain]: mid-turn, the frame is appended to a turn already in tool-calling mode, where the natural
continuation of "call SendMessage with exactly this input" is a tool call. Idle, the frame **starts**
a turn in an agent whose last act was a report; the natural continuation is prose. Nothing in the
runtime distinguishes the two cases — the payload is byte-identical — so the split has to be
behavioural. I have no code-level mechanism for it and I did not find one.

### The second, structurally worse path (pane teammates — our fleet's `teammateMode: "iterm2"` shape)

For an out-of-process teammate the delivery layer itself can strand the request, invisibly:

1. `#y()` finds the `shutdown_request`, calls `submitIncomingPrompt`, which returns `false` because
   `guard.isActive` (a blocked-Stop chain, §6) or because the command queue holds a `mode:"prompt"`
   entry (36331905);
2. the frame is appended to the **in-memory** queue with `status:"pending"`;
3. `Yt()` marks it **read on disk** regardless (36406100);
4. the only drain for that in-memory queue is `#w()`, which is **edge-triggered on an input-identity
   change** and is never reached by the 1 Hz timer.

⇒ If no `{enabled,isLoading,visibleDialogKind,onSubmitMessage}` change follows, the request is
**permanently lost while the inbox file shows it delivered**. This mode has *not* been measured on
this fleet; it is a code-read hazard, and it is the one that would survive any amount of model
compliance work.

### What would refute this verdict

| Claim | Observation that refutes it |
|---|---|
| The survivors were in-process, so `Ye`/`Se` delivered the frame | a survivor's transcript containing **no** user message carrying `"shutdown_request"` / `"This is a shutdown request."` — that would move the fault back to delivery |
| Approval is model-mediated with no backstop | any teammate observed terminating on a `shutdown_request` **without** a `SendMessage{shutdown_response}` tool_use in its transcript |
| No idle timeout exists | a `[inProcessRunner] … idle timeout — exiting loop` line in any debug log (the `case` exists; only its constructor is missing) |
| The delivery layer is sound for in-process | `[inProcessRunner] … could not mark N message(s) read` streaks, or `swarm_inbox_poll / worker_mark_read_failed_streak` telemetry |
| The pane-teammate stranding path is real | `[InboxPoller] Submission rejected, queuing for later delivery` **never** appearing in any teammate debug log under load |
| TeammateIdle is teammate-side | a `TeammateIdle` hook invocation in a session where `Ji()` is false, or one whose `teammate_name` differs from that session's own `kp()` |

### Named uncertainties

- **The mid-turn/idle split has no code-level mechanism in my reading.** Everything I can cite says
  the payload and the delivery path are identical. If a mechanism exists, it is in how the
  in-process runner re-enters the agent loop (`hMt`, 30746400ish) versus how a mid-turn message is
  spliced — I did not read `hMt`'s body.
- **`additionalContext` on TeammateIdle**: schema-valid, consumer not found. Untested.
- **`Ji()` for an in-process teammate**: `rMt()` checks `WN()` (in-process) *before* `Ji()`, so the
  two are distinguished for the poller — but the `if(Ji())` gate in `p2n` does not make that
  distinction, which is why an in-process teammate's TeammateIdle hook runs in the lead's process.
  I did not read `WN()`.
- **Offsets are into `strings -a` dumps**, so they are stable only for these two dump files. Re-derive
  with the command at the top; do not port an offset to a differently produced dump.

---

## 9. Corrections this pass produces (for whoever integrates)

| Document | Line / claim | Status on 2.1.260 |
|---|---|---|
| `SUBAGENT_LIFECYCLE_SIGNAL_DISCONNECT_2026-08-04.md` §"completion channel has zero producers" | `completedTaskId` never assigned; `completedStatus` only `"failed"` | **HOLDS**, re-verified (17 + 8 occurrences enumerated) |
| same, `:577` table | *"`TeammateIdle` — NO — fires in the LEAD"* | **WRONG**, on 220 as well as 260. One call site, in the teammate's Stop pass, `teammate_name = kp()` (self). The lead-process observation is explained by in-process teammates sharing the lead's process. |
| same, mode 5 (*"a subagent's prose is not visible to anyone"*) | | **SUPERSEDED on 260** by the `result` field — last assistant message text, ≤4 KB/frame, ≤16 KB/drain, auto-transmitted |
| same, *"`idleReason:'available'` is a hardcoded literal"* / implied 1 producer | | **UNDER-COUNTED** — 2 producers; `"interrupted"` has 1 (both via a ternary a literal grep misses) |
| same, *"the lead sees it through `JSb`"* correction note | | `JSb` no longer exists on 260; `Na` is the only renderer |
| same, *"`shutdown_request` is advisory / the only actuator is `abortController.abort()`"* | | **STRENGTHENED**: out-of-process approval now calls `Rn(0,"other")` — a real process exit — and writes `shutdown_approved{paneId}` so the lead closes the pane. Still 100% model-initiated. |
| `hooks/teammate-auto-shutdown.sh:3` | *"Fires (LEAD-side)"* | **WRONG locus**, right process for in-process teammates. Its `{"continue":false}` ends the *teammate's turn* (which its line 42 already says correctly). |
| `hooks/teammate-auto-shutdown.sh` deferral design | dirty-tree + `.teammate-busy` gating | additionally: it is **never invoked at all** on any Stop where a settings `Stop` hook blocked (§5.3) — `session-continue.sh`, `completion-assert.sh` and the ship floor all suppress it |
| `skills/agent-teams/SKILL.md:370-372` | *"`TaskStop` is the authoritative actuator"* | **CONFIRMED by code** — it is the only non-cooperative path; `shutdown_request` has no timeout, no retry and no escalation anywhere in the binary |

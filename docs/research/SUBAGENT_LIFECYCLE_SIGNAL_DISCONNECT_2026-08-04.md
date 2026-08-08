# Subagent lifecycle: the idle/working signal is wrong in BOTH directions, and nothing self-closes

**Captured 2026-08-04 from a 12-agent research wave** (reso bottle-image fidelity, landed
`9d06ee831`). This is the best specimen of the problem we have had — every state transition is
in one session's transcript with timestamps. Written down because a handoff would lose it.

**The operator's framing, and it is the right one:** *"we still have a disconnect between our
subagents when it's working or idle, and thinking it's vice versa, and not gracefully
self-closing. I thought we did this just now, and numerous times over."* Repeated fixes that
did not hold is the signature of a wrong frame, not a wrong implementation.

---

## The specimen — four distinct failure modes, all in one wave

### 1. `idleReason: "available"` fired while ACTIVELY working with undelivered results

`G1-decode` emitted "available" at **10:04:53, 10:07:39, 10:11:04, 10:17:43** — and then
delivered **two substantial reports**, one of which refuted the wave's central premise. It was
never idle. `D-bitdepth` did the same ~8 times while producing two reports, one of which
overturned the lead's committed recommendation.

⇒ **A lead that trusted "available" would have torn down the two agents that mattered most.**

### 2. `idleReason: "available"` fired repeatedly while PERMANENTLY stuck

`A1-knee` emitted "available" at **10:09:23, 10:10:08, 10:55:48, 10:56:11, 10:57:06, 10:57:25,
10:59:08, 11:00:06** — eight times across 50 minutes — and **never delivered a report at all**,
then exited. Its axis had to be reconstructed by the lead from its landed raw data.

⇒ Identical signal to mode 1. **"available" carries zero information**: it is emitted by the
agent that is about to deliver gold and by the one that will never deliver anything.

### 3. `idleReason: "failed"` fired for a RECOVERABLE condition

`F2-precision` reported `failed` / *"Not logged in · Please run /login"* at **10:17:20, 10:17:21,
10:24:00, 10:24:01** — and then **recovered on its own** and delivered two of the three most
important findings in the entire wave (the 1020/1023 padding defect; the deep16-is-a-dither
control). The lead had already spawned a replacement (`F2b-colour`) on the strength of "failed",
duplicating work.

⇒ **"failed" is also non-terminal**, so it cannot be trusted to trigger replacement either.

### 4. No graceful self-close — agents persist indefinitely after completion

At the point of writing, **four agents were alive at 1h23m–1h28m uptime** with all work
delivered and acknowledged: `A2-perwidth`, `C-effort`, `E-chroma`, `RED-team`. They do not
terminate on completion; the lead must notice and intervene, using the same unreliable signal.

---

## Why more detectors cannot fix this

The signal is wrong in **both directions simultaneously** — false-idle (modes 1, 3) and
false-alive (mode 2). Any detector added on top inherits that ambiguity: there is no threshold
on "available" that separates G1-decode from A1-knee, because they emit the identical event.

This matches a previously-recorded finding (memory `reference-spawn-dispatch-ack-is-not-a-start-ack`):
*"'Spawned successfully' is a DISPATCH ack, never a START ack… `TaskList` said 'No tasks found'
while a live agent was mid-run, so it mislabels BOTH directions. Fix at the spawn chokepoint
(fail-closed start-ack + deadline), NOT as a prose ping duty — that class is closed under adding
detectors."*

**The same conclusion is now confirmed at the other end of the lifecycle.** The prior finding
covered START; this covers COMPLETION. The recurrence across both ends is the reason to suspect
the frame rather than the detectors.

## The hypothesis worth attacking (not the answer — the thing to attack)

`idleReason` appears to report **"this agent's turn ended"**, not **"this agent has finished its
task."** Those coincide only for single-turn agents. Every multi-turn agent — which is every
research agent that measures, reads a result, and measures again — ends turns constantly while
being nowhere near done. If true:

- the event is not broken, it is **correctly reporting a different fact than the one consumed**;
- no amount of tuning fixes it, because the fact the lead needs (**task complete**) is not
  observable from turn boundaries at all;
- the fix is a **completion contract the agent asserts** (deliverable handed over → terminate),
  with the lead's teardown driven by that assertion, not by inferred idleness.

## What a session on this must not do

- **Do not add another detector or heartbeat.** The class is closed under that; two independent
  findings now say so.
- **Do not fix it in prose** ("leads should ping agents that look idle"). That is what this wave
  did — repeatedly, by hand, and it is why the operator is asking.
- **Do read the actual event source** rather than reasoning about it: where `idle_notification`
  is emitted, what `idleReason` is computed from, and whether a distinct terminal state exists.

## Cost of the status quo, measured in this wave

- One axis (A) lost entirely and reconstructed by the lead from raw data.
- One duplicate agent spawned (`F2b-colour`) on a false-terminal signal.
- ~10 lead interventions chasing reports by hand, each a full round trip.
- Four agents idling ~1.5h after completion.
- The lead cannot distinguish "wave done" from "wave stalled" without reading every artifact.

---

# ANSWER (2026-08-04, read from the binary) — the frame

**The hypothesis above is correct but understates the defect.** `idleReason` does report "a turn
ended" rather than "the task finished". But the reason repeated fixes never held is one level
deeper, and it is visible in the message schema:

> `idle_notification` is a **two-channel protocol**. It has a LIVENESS channel (`idleReason`) and a
> COMPLETION channel (`completedTaskId` + `completedStatus`). The liveness channel is fully
> implemented. **The completion channel has no producer at all.** The lead has been reading the
> liveness channel as if it were the completion channel *because it is the only one that ever
> arrives.*

Every prior fix treated this as a **signal-quality** problem — the idle signal is noisy, so detect
harder, threshold better, ping when unsure. That frame cannot succeed, because the signal is not
noisy. **`idleReason` is a completely accurate report of a different fact.** The producer is not
broken and there is nothing in it to fix. Channel B is not a function of channel A, so no
threshold, heartbeat, poll or detector over A can ever recover B.

## The code

Verified against `~/.claude-220/node_modules/@anthropic-ai/claude-code/bin/claude.exe`
(Mach-O arm64, Bun-compiled). Reproduce with:

```sh
strings -a ~/.claude-220/node_modules/@anthropic-ai/claude-code/bin/claude.exe > /tmp/cc.strings
python3 -c "d=open('/tmp/cc.strings',errors='replace').read(); i=d.find('NEEDLE'); print(d[i-2000:i+2000])"
```
(Use python slicing — a `grep -o '.\{2000\}NEEDLE'` regex over a 650k-line blob hangs.)

**1. The wire format already has the field the lead needs.** Zod schema (`Yze`):

```js
type: literal("idle_notification"), from: string, timestamp: string,
idleReason:      enum(["available","interrupted","failed"]).optional(),
summary:         string.optional(),
completedTaskId: string.optional(),
completedStatus: enum(["resolved","blocked","failed"]).optional(),
failureReason:   string.optional()
```

`completedStatus`'s enum — `resolved` / `blocked` / `failed` — is exactly the terminal-outcome
vocabulary a lead needs. The lead-side renderer is written to display it:

```js
function JSb(e){ let t=["Agent idle"];
  if(e.completedTaskId){ let r=e.completedStatus||"completed"; t.push(`Task ${e.completedTaskId} ${r}`) }
  if(e.summary) t.push(`Last DM: ${e.summary}`);
  return t.join(" · ") }
```

**2. The completion channel has zero producers.** This is *"it does not exist"*, not *"I could not
find it"*. `completedTaskId` and `completedStatus` are **property names**, which esbuild does not
mangle, so any producer would have to contain the literal token. Every occurrence in the 38.5 MB
blob is enumerated and accounted for — 6 each:

| offsets | what |
|---|---|
| 7247025 / 7247041 | the binary's constant/string table (not code) |
| 19357699 · 19357718 / 19357734 · 19357753 | inside `cdr`, the sole constructor — key + pass-through read |
| 19362765 / 19362803 | the zod schema |
| **21162702** | **the one and only assignment**: `completedStatus:"failed"` |
| 27230175 · 27230246 / 27230200 | inside `JSb`, the sole reader |

⇒ **`completedTaskId` is assigned nowhere in the binary.** `type:"idle_notification"` occurs
exactly once (19357588), so `cdr` is the only thing that can mint the frame; it has four call sites
(21160979 normal turn-end, 21162646 agent-loop-crash, 29615492 the teammate Stop hook, 29616014 the
pane-teammate failure path) and **all four pass object literals — no spread can smuggle the field
in**. The single `completedStatus` write is the crash path:

```js
// agent_loop_failed — the crash path
await tvd(t.agentName,t.color,t.teamName,{idleReason:"failed",completedStatus:"failed",failureReason:Y})
```

⇒ **`resolved` and `blocked` — the two success-terminal values — are emitted by nothing.** The only
completion status that can ever reach a lead is `failed`, and only when the agent loop crashes.
`JSb`'s `if (e.completedTaskId)` branch is dead code.

**3. `idleReason:"available"` is a hardcoded literal in a Stop hook.** In `enl` (TeammateInit),
the runtime registers a *session* hook (`z0u`, id `teammate-idle-notification`) on the `Stop`
event inside every teammate:

```js
w(`[TeammateInit] Registering Stop hook for teammate ${i} to notify leader ${u}`),
z0u(e,t,"Stop","",async(d,p)=>{
  Zur(n,i,!1);                                              // team file: isActive = false
  let f=cdr(i,{idleReason:"available",summary:mdr(d)});     // <-- string literal
  return await VC(u,{from:i,text:Ie(f),...}),!0
},"Failed to send idle notification to team leader",{timeout:1e4,id:"teammate-idle-notification"})
```

`Stop` fires at **every turn boundary**. `"available"` is computed from nothing — not from tool
state, not from task state, not from whether anything was produced. The same call also writes
`isActive:false` into the team file, so the team-file view is likewise just "a turn ended".

**4. The one field that could have carried information is filtered to exclude the lead.** `mdr()`
walks the turn's messages backwards for a `SendMessage` tool_use — but only counts it if
`to !== "*"` **and** `to.toLowerCase() !== zf.toLowerCase()`, where `` zf = "team-lead" ``.

⇒ A teammate that reports *to the lead* — the normal case — gets `summary: undefined`.

**5. What the lead literally sees — and it is worse than "no information".** The TUI does *not*
render these frames through `JSb`. The mailbox renderer `$Eb` routes an `idle_notification` to the
panel component `xwr`, which destructures **only** `{displayName, inkColor, idleReason,
failureReason}` and maps them (offset 27237697):

```js
Jqp = Awr==="failed" ? "error"  : Awr==="interrupted" ? "warning"         : "success"
Xqp = Awr==="failed" ? "failed" : Awr==="interrupted" ? "was interrupted" : "finished"
```

⇒ `idleReason:"available"` is rendered to the lead, in **success green**, as:

```
✓ Teammate @G1-decode finished
```

**The string "available" never appears in the UI. The word the lead is shown is `finished`.** It is
shown at *every turn boundary*. `A1-knee` told the lead it had "finished" eight times over fifty
minutes without ever producing anything; `G1-decode` said "finished" four times while mid-analysis.

This reframes the operator's whole experience: **the lead was never misreading an ambiguous
signal — it was being told, in green, that the agent had finished.** Acting on that is correct
behaviour on false input, which is why no amount of lead-side discipline or prose ever fixed it.

⚠️ *Correction to an earlier draft of this section, which stated the lead sees the string
`Agent idle` via `Mda`→`JSb`. That is wrong: `$Eb` returns the `xwr` panel before `Mda` is reached
(and when a `summary` is present it returns the raw JSON text instead). `JSb` — the only reader of
`completedTaskId` — is unreachable for idle frames, so the completion channel is dead **twice
over**: no producer, and no reachable renderer even if one existed.*

## Why this explains all five modes, exactly

| Mode | Explanation from the code |
|---|---|
| **1** working agent emits "available" | Stop fires at every turn boundary; `"available"` is a literal. G1-decode ending turn 3 of 12 emits it identically to an agent that is finished. |
| **2** stuck agent emits "available" | Identical payload — `{idleReason:"available", summary:undefined}`, rendered `Agent idle`. Modes 1 and 2 are **the same event, byte for byte** (bar the timestamp). Not a threshold problem: there is no bit to threshold on. |
| **3** "failed" for a recoverable condition | `ulp(msgs) = BLs(msgs)?.reason`. `BLs` returns `{reason, errorKind, **isTransient**}` — and `ulp` **discards `isTransient`**. The runtime *computes* whether the error is transient and throws that bit away one call before emission. `failed` means "the last assistant message was an API error", which the next turn retries. |
| **4** no self-close | Nothing in the emit path is terminal. `Agent idle` at turn 1 is the same event as `Agent idle` after everything is delivered. There is no "done" to fire on. |
| **5** report written, never delivered | `mdr()` proves the runtime *does* inspect SendMessage tool_uses — but only to build a cosmetic summary, and it explicitly excludes messages to the lead. Nothing anywhere asserts "a deliverable was handed over". |

Modes 3 and 5 are the same defect as 1/2 in different clothes: in each case a richer fact is
computed and then **narrowed to a constant or dropped at the emit site**. That is the frame — not
"the signal is unreliable" but "**every channel that could carry completion is either unproduced or
lossily collapsed before it is sent**".

## What this rules in and out

- **Rules out** (and explains the ten-times-fixed history): any detector, heartbeat, poll, liveness
  probe, or idle threshold. All of them consume channel A. Confirmed independently at the *start*
  of the lifecycle by `reference-spawn-dispatch-ack-is-not-a-start-ack`; this is the same closure
  at the *end*.
- **Rules out**: filling the *existing* completion channel ourselves. It is unreachable from any
  supported agent-side action, and verified adversarially:
  - `SendMessage`'s structured form is a **closed 3-member discriminated union** (`shutdown_request`,
    `shutdown_response`, `plan_approval_response`) — `idle_notification` is not constructible
    through it.
  - `SendMessage`'s plain-string form **explicitly refuses** hand-crafted lifecycle frames:
    *"message text must not be a teammate lifecycle/task frame … send plain text instead"*
    (errorCode 9), with `idle_notification` named in the blacklist.
  - No tool wraps `cdr`, and it is never reached by property access.
  - Even out-of-band inbox injection buys nothing, because `JSb` is unreachable for idle frames.
- **Rules out**: `task_completed`, the obvious alternative. It has **zero producers too** —
  `type:"task_completed"` occurs zero times; only the schema and a SendMessage blacklist entry
  exist. And the task-status enum is `["pending","in_progress","completed"]`, so `completedStatus`'s
  success values `resolved`/`blocked` have **no source vocabulary anywhere in the model**. Marking a
  task complete fires a local `TaskCompleted` hook and writes a tool result into the agent's own
  transcript; **nothing reaches the lead as a structured completion event.**
- **Rules in**: the lead must obtain completion from a channel **we** produce. And per mode 5 it
  cannot be a bare assertion — an agent that *believes* it delivered is exactly the failure that
  cost the wave its most consequential finding. **Completion must be assertion ∧ artifact**,
  checked where the assertion is made.

## Mode 5 (added after capture) — an agent finished, wrote its report, and the report never left

`H-failures` **completed its axis at 03:11 and its report did not reach the lead until 11:15** —
**70 minutes late, and only because the lead chased it by hand on a final-call sweep.** Cause: it
emitted the report as **plain text in its own turn** instead of calling `SendMessage`. A subagent's
prose is not visible to anyone; only a tool call transmits.

Meanwhile it emitted `idleReason: "available"` throughout — so from the lead's side it was
indistinguishable from mode 2 (permanently stuck, nothing to deliver). The lead had already
**reconstructed the entire axis by hand** from its landed raw data.

**Why this mode matters more than the other four:** its report contained the wave's single
most consequential finding — that a **paid** photography regen would make the defect *worse*
(the 4k master cohort bands **10.7× worse** post-encode than the 2k cohort, and every FAIL is 4k).
A silently-undelivered report is not a lost status update; it is a lost decision. Had the lead
not swept, that money decision would have gone the wrong way on no evidence.

It also caught a **real bug in the lead's own harness** — `cambiOfAvif` decodes to `yuv444p10le`,
so a 12-bit encode is downconverted through **swscale's default-on dither**, inflating bd12 scores
~25× — which had already produced (and nearly shipped) a false headline recommendation.

**What this adds to the frame.** The other four modes are about a *signal* the lead cannot trust.
This one is about a *delivery channel the agent can silently fail to use* — and the two compound:
the unreliable signal is exactly what stops a lead noticing the undelivered report. Any fix that
addresses idleness without also making **delivery** an asserted, checkable act leaves this mode
fully intact.

Corollary for the completion contract: "task complete" must mean **deliverable handed over**, not
"turn ended" and not "agent believes it is done". A contract the agent asserts, with nothing
delivered, is the same failure wearing a new name.

---

# The consumer side — and why the existing reaper made it worse

The protocol finding above is only half the story. `~/.claude/hooks/teammate-auto-shutdown.sh`
(wired live on the `TeammateIdle` event) is the mechanism that has been "fixed numerous times". It
ran during the specimen wave. **Its own log refutes it**, and the refutation is the mode-1-vs-mode-2
discriminator test in observable form.

## What it keys on

Its gate is a **dirty-tree proxy for busy-ness**, refined over many iterations into per-file
attribution:

```
3. DEFER on dirty tree — if git status shows uncommitted work, skip the reap this cycle.
   TeammateIdle fires 3-4× per teammate; we wait until the teammate actually quiesces
   (this IS the final-idle gate). Max defers: 3 (backstop).
4. COOPERATIVE MARKER — if <worktree>/.teammate-busy exists, defer unconditionally.
```

Both halves consume channel A. The defer counter is a **threshold on an event that carries no
completion information**, and `.teammate-busy` is an *inverted* contract — the agent asserts BUSY,
so forgetting to write it is silently fatal.

## What actually happened, from `~/.claude/logs/teammate-lifecycle.log`

Specimen wave = `team: session-039b0ae2`. The reaper's verdicts:

**`G1-decode` — mode 1, actively working, about to deliver the report that refuted the wave's
central premise.** Cleared for shutdown **five times while working** (03:07:49, 03:11:07, 03:11:15,
03:17:45, 03:17:54):

```
↳ G1-decode: shared cwd is dirty, but NOTHING this member wrote is — a sibling's dirt is not its own
Auto-shutdown idle teammate: G1-decode (team: session-039b0ae2)
```

⇒ **The gate's verdict was wrong five times on the agent that mattered most.** Precisely what the
log does and does not show, because the distinction matters:

- In the 03:07–03:17 working window the reaper reached its `Auto-shutdown idle teammate` decision
  five times and **no `✓ closed pane` line followed** — so something downstream held the actuation,
  and nothing in the log names what. The pane survived.
- The only close of pane 476 came at **04:15:28**, after G1-decode had delivered. That one is
  defensible on timing.

So the correct claim is about the **decision, not the outcome**: a working agent holding the wave's
premise-refuting finding was cleared for shutdown five times, and its survival depended on an
unlogged downstream hold rather than on the gate. A guard whose verdict is wrong and whose actuation
silently disagrees with it is not a guard that happened to work — it is two defects cancelling.

**`A1-knee` — mode 2, permanently stuck, never delivered anything.** Protected indefinitely:

```
↳ A1-knee: shared cwd dirty AND this member's own files are among the dirty ones — defer stands
defer A1-knee (1/3): dirty tree
defer A1-knee (2/3): dirty tree
⚑ SURFACE A1-knee ... Pane NOT closed. ... A shared cwd is NORMAL ... there is no spawn-side fix
~ page suppressed (damped) [SHARED-CWD-NEVER-REAPS:session-039b0ae2:A1-knee]
```

⇒ The dead agent was held open, its alarm fired to exhaustion, and was then **damped to silence**.

## The polarity is exactly inverted, and the reason is structural

| | wrote files? | reaper verdict | truth |
|---|---|---|---|
| `G1-decode` | no (reports went out as messages) | **REAP** (5×) | working, held the wave's key finding |
| `A1-knee` | yes (scratch files, then died) | **PROTECT** (forever) | dead |

A research agent's work product is a *report*, not a tracked file. So "did this member write files"
is not merely a weak proxy for completion — **for the entire research-agent population it is
anti-correlated with it.** The agent that finishes cleanly and hands off leaves no dirt and looks
reapable; the agent that dies mid-scratch looks busy forever.

This is the frame at the consumer end. Every iteration of this hook — per-file attribution, shared-
cwd detection, defer counting, own-footprint holds — has been a **more sophisticated way of guessing
busy-ness**. The fact it needed (did this agent finish and hand over its deliverable?) was never in
its input, because, per the protocol finding, nothing emits it.

Two corroborating measurements from the same log:
- `Auto-shutdown idle teammate: agent-a-agg` appears **4707 times**. The hook re-fires forever;
  `MAX_DEFERS` bounds the defer *counter*, not re-entry. An alarm that always fires carries the
  same zero bits as one that never does.
- The mode-4 agents are **still alive as of this writing** — `C-effort` and `E-chroma` at
  **8h13m** uptime, ~8 hours past delivery. `ps -eo pid,etime,command | grep -- --agent-name`.

## Why nothing self-closes (read from the binary)

⚠️ **Two teammate shapes exist and they must not be conflated.** `--teammate-mode` accepts
`tmux | iterm2 | in-process | auto`. **This fleet runs `teammateMode: "iterm2"`** (kitty panes) —
each named teammate is a *separate `claude.exe` process* with its own session id and transcript,
verified by process ancestry. So:

- **Modes 1/2/3 are fully explained by our shape.** The producers on the out-of-process path are
  the TeammateInit `Stop` hook (29615492, hardcoded `"available"`) and `M7f` (29616014, the
  `"failed"` path). Those are exactly the frames the specimen wave emitted.
- **The bullets below about `evictAfter`, `idle_timeout` and `Qsn` describe the `in-process`
  runner**, which we do **not** run. They are recorded because they show the design intent has no
  terminal state *either* way — but the mechanism that keeps *our* agents alive is simply that a
  pane teammate's process outlives its turn and only the pane reaper can end it.

- **There is no idle timeout.** `{type:"idle_timeout"}` is **never constructed anywhere in the
  binary** — only a `case "idle_timeout":` label exists, and its body is unreachable. The poll loop
  computes a last-activity timestamp `c` and compares it to nothing.
- **`evictAfter` never kills anything.** For a live idle teammate the 1 Hz sweeper only sets
  `evictAfter: 0`, which is a **UI list filter**. An agent vanishing from the task list is not an
  agent stopping. And while *any* sibling is still working, every idle teammate's `evictAfter` is
  pushed forward `+30s` each tick — so a wave stays listed indefinitely by design.
- **`shutdown_request` is advisory.** It is injected into the teammate as an ordinary user message;
  the dispatcher case has no loop-exit flag (compare `case "aborted": B=!0`). It is a prompt, not
  an actuator — confirming memory `shutdown-request-is-not-an-actuator` at the code level.
- **The only actuator is the teammate's own model** calling `SendMessage {type:"shutdown_response",
  approve:true}` → `oJ_` → `abortController.abort()`. If the model ignores or misformats it,
  **nothing happens at all** — no timeout, no escalation, no reaper.
- A lead receiving `shutdown_approved` from an *in-process* teammate does **nothing mechanical**:
  the handler branches on `paneId`, which in-process teammates do not have.

⇒ Self-close is possible, but it is **entirely voluntary and model-mediated**, with no backstop.

---

# THE FIX — produce the channel that has no producer

The fix is not a better inference and not a better proxy. It is to **emit the completion fact
ourselves**, as an artifact that is falsifiable from disk, and to move every consumer off idleness
and onto it.

## The one rule that makes this not-another-detector

> **Idleness may be a TRIGGER. It may never be a PREMISE.**

`TeammateIdle` is still a fine moment to *wake up and look*. It is never evidence of anything. Every
decision — reap / don't reap, done / not done, replace / don't replace — reads the receipt, never the
event that woke it. That is what keeps this out of the class that is closed under adding detectors:
the mechanism has no opinion about idleness, and cannot be wrong in either direction, because it
never renders a verdict on liveness at all. It only ever validates a claim the agent itself made.

## The completion receipt

Per wave, a receipt directory. Each agent, as its **last act**, writes two things:

```
<wave>/<agent>.md               the deliverable itself
<wave>/<agent>.receipt.json     {"agent","status":"resolved|blocked|failed","artifact","summary","ts"}
```

Three properties, and all three are load-bearing:

1. **Asserted, not inferred.** The agent states its own terminal status. Nothing guesses.
2. **Falsifiable.** The receipt names an artifact; the artifact either exists and is non-empty or
   it does not. A receipt whose artifact is missing is a *failed* receipt, not a completion. This is
   what stops the fix from being mode 5 in new clothes — the doc's own corollary demanded it.
3. **Absence is never interpreted.** No receipt ⇒ the mechanism says nothing and does nothing. It
   does not mean "still working" and it does not mean "dead". It means *not yet asserted*, which is
   the truth, and it is resolved at the wave level by the ledger, not per-agent by a threshold.

## Where each consumer moves to

| Consumer | today (channel A) | after |
|---|---|---|
| "is the wave done?" | lead reads every artifact and judges | `ls <wave>/*.receipt.json` — a count, not a judgment |
| "which axis is stalled?" | unanswerable until the lead sweeps by hand | spawn-set minus receipt-set, **by name** |
| reaper gate | dirty-tree proxy → inverted for research agents | verified receipt present, else **fail-closed (defer)** |
| replace a failed agent | `idleReason:"failed"` → duplicate spawn (mode 3) | receipt absent past an explicit deadline |
| self-close | never happens | on receipt, lead sends `shutdown_request`; agent approves → aborts; `ps`-verify |

## Verification against the specimen's five modes

This is the acceptance test the brief demanded — a fix that cannot separate mode 1 from mode 2 has
fixed nothing.

| Mode | Specimen behaviour | Under the receipt |
|---|---|---|
| **1** `G1-decode` working, emitted "available" 4× | **cleared for shutdown 5× while working**; survived on an unlogged downstream hold, not on the gate's verdict | no receipt ⇒ **reaper defers, fail-closed**. Protected *because* it had not asserted, not because it looked busy — and the protection is in the verdict, not in a hold nobody can see. |
| **2** `A1-knee` stuck, "available" 8× over 50 min | protected forever, alarm damped to silence | no receipt ⇒ also not reaped — **but the ledger lists axis A as OPEN, by name, from minute one.** The lead's hand-reconstruction happens immediately and deliberately instead of 50 minutes later by accident. |
| **1 vs 2 — the discriminator** | identical event, no bit to separate them | **mode 1 eventually produces a receipt; mode 2 never does.** Separated by a *different bit*, not a better threshold. The reaper does not distinguish them at all — the ledger does, at wave level, at a deadline. |
| **3** `F2-precision` "failed" 4×, then recovered | replacement spawned on a false terminal ⇒ duplicated work | `failed` is not a receipt. Replacement gates on **receipt-absence past a deadline**, so a transient error cannot trigger it. F2 recovers and files its receipt; no duplicate. |
| **4** four agents alive at 1h23m (now 8h13m) | nothing self-closes; no timeout exists in the binary | receipt present ⇒ lead sends `shutdown_request` ⇒ agent approves ⇒ `abortController.abort()`. Voluntary, so **`ps`-verify and escalate** — never trust the ack (memory `shutdown-request-is-not-an-actuator`). |
| **5** `H-failures` report written, never delivered | 70 min late, found only by a manual sweep | the **artifact file is the delivery**. Prose in a turn cannot satisfy a receipt, and a receipt naming a file that does not exist fails validation at the moment it is written. |

## Live evidence that the contract half works

Every subagent spawned by *this* session was given the artifact clause verbatim — *"writing the file
is MANDATORY — a report that exists only as prose in your turn is invisible to me"*. `T1-terminal`
honoured it: it wrote `report-T1-terminal.md` (17 KB) and its process then exited on its own. The
lead knew it was done by the **file existing**, having never once consulted an idle signal. That is
the whole mechanism in miniature — and it is the direct countermeasure to mode 5, which is the mode
that cost the specimen wave its most consequential finding.

Sharper still: **all four subagents delivered their file; zero of their `SendMessage`s ever reached
the lead's context.** Every report in this investigation was collected by polling the filesystem.
The disk half of the contract scored 4/4; the message half scored 0/4. That is a one-wave sample,
but it points the same way as `lr-audit.py:15`'s recorded premise — *"the ONLY dependable source is
disk"* — and it is why field 7 names a **path**, not a recipient.

---

# What already exists — this is a ROUTING problem, not a build problem

The prior-art census (`T2`) changes the fix materially, and searching the graveyard first was the
right call: **the completion classifier we would have built already exists, landed and tested.**

`scripts/limit-recover/lr-audit.py` (1,478 LOC) classifies every subagent / workflow slot / team
assignee **from disk truth** as `COMPLETE · COMPLETE_UNDELIVERED · COMPLETE_SALVAGED ·
VACUOUS_SUSPECT · TAINTED_COMPLETE`, with an explicit `delivered_to_lead` boolean (`:418`,
`:511-513`).

> **`COMPLETE_UNDELIVERED` *is* mode 5 — already named, already computed, already correct.**

Its only invocation path is the `limit-recover` skill: it runs *after a usage-limit crash* and never
routinely. It is the **one signal class in the whole repo that can distinguish *delivered* from
*finished-but-silent*, and it is the only one nothing runs on a cadence.**

That is the shape of the whole domain, and it is the honest answer to "fixed numerous times, never
held". Three independent instances, all found in this census:

| | Sensor | State |
|---|---|---|
| `lr-audit.py` | the completion taxonomy | LIVE code, trigger fires only after a crash |
| `teammate-reap-alarm` + `assignee-pane-residency.sh` | "does the close path still close anything?" | selftests, symlinked live, **plist never bootstrapped** — its activation script is REPO-ONLY, so it never entered the operator's queue and *cannot* be paged for |
| `hooks/subagent-stop.sh` | per-subagent completion record | **`SubagentStop` is not registered in settings at all** — a green test suite exercising a hook nothing invokes |
| `assignee-chain-state.py` | per-member lead-done / identity / ladder state | zero callers |

**The sensor exists; the cadence does not.** Every past fix built another way of *knowing*, and the
decision kept being made from the one signal that arrives by itself — the turn-boundary event that
renders as `✓ finished`. That is the frame restated at the consumer end, and it is why the remedy is
to route what exists rather than to add a fifth sensor.

One more inventory correction worth recording, because designing off the stale doc would re-fix a
fixed thing: `docs/plans/TEAMMATE_SELFCLOSE_INVESTIGATION.md:681-699` still carries a `⛔ NOT LIVE`
section for the reap-guard tree-scope work. **It is live** — content-verified, and 21 panes closed
today. (Memory: `parked-blocker-obsoleted-by-later-fix`.)

### The `subagent-stop.sh` row is inert but NOT a data-loss path (measured 2026-08-07)

Backlog item `7ea31ffa1a08` parked the wiring decision behind a blocking question: *"an UNNAMED
`Agent()` is in-process and may leave no durable transcript (`isSidechain:true` = 0 of 799,606
records at 2.1.220, so the 2026-08-02 tell is not reproducible). If unnamed subagents really leave
no harvestable trace, this unwired hook is a live DATA-LOSS path, not a tidiness gap."*

**That zero is a glob miss, not an absence** (memory: `lookup-miss-is-not-absence`). Nameless
subagents do not write into the top-level transcript — they get their **own file one directory
down**, which `projects/*/*.jsonl` cannot reach:

| Tier | Glob | Files | Records | `isSidechain:true` |
|---|---|---|---|---|
| top-level sessions | `~/.claude/projects/*/*.jsonl` | 716 | 262,008 | **0** |
| nameless subagents | `~/.claude/projects/*/*/subagents/*.jsonl` | **165** | 14,289 | **14,289 (100%)** |

So every nameless subagent leaves a complete, durable, deterministically-pathed transcript
(`agent-<id>.jsonl` + `agent-<id>.meta.json`; specimens here run 437 KB–735 KB). The unwired hook is
therefore a **harvest/routing gap, not data loss** — which is the same verdict this document already
reaches for the fleet as a whole ("this is a ROUTING problem, not a build problem", § above), and it
is consistent with the two rows above rather than a correction to them. `7ea31ffa1a08`'s stated
precondition for wiring is now settled, and settled in the direction that *lowers* its urgency: the
reports are on disk either way, so wiring `subagent-stop.sh` buys an index over data that was never
at risk. The wiring call stays with that item; nothing here should be read as pre-empting it.

---

# The lever we actually control (verified, not assumed)

Measured on this fleet's shape (out-of-process kitty-pane teammates), with a self-evidencing
positive control:

| Hook event | Fires inside a named teammate? | Consequence for the fix |
|---|---|---|
| `Stop` | **YES** — the settings chain runs in full, in the teammate's own child session | a hook can **validate a completion assertion at the moment it is made**, and `decision:block` works (observed 8× in one teammate) — so it can refuse to let an agent stop on an undelivered report |
| `PreToolUse` | **YES**, and the deny verdict is *enforced* | proven first-hand: `keychain-guard` denied a tool call inside a teammate mid-report |
| `PostToolUse` / `SessionStart` | YES | — |
| `SessionEnd` | **YES — at TERMINATION, not turn end** | a genuine terminal event we own. Clean negative control: 22/26 past teammates have the row; the 2 live ones have `SessionStart` and **zero** `SessionEnd` |
| `TeammateIdle` | **NO — fires in the LEAD** | it is the lead's *trigger*, exactly as the rule requires; the teammate never sees it |
| `SubagentStop` | not registered in settings at all | nothing fires; `hooks/subagent-stop.sh` is inert |

⇒ Both halves of the receipt design are reachable: **assert-and-validate** in the teammate's `Stop`,
**terminal fact** at its `SessionEnd`. Neither reads `idleReason`. (Indeed *nothing in the repo
reads `idleReason` — grep returns one comment* — so the "no more detectors on that field"
constraint is satisfied by construction, with nothing to remove.)

---

# Landed this session · and what remains, with the reason

**Landed.**

1. **The doc.** Root cause from the code + the restored specimen body (lost in revert `3725e543`;
   the four modes survived only inside `b3f72885`'s commit message).
2. **`skills/research-subagents/SKILL.md` — the canonical brief goes 6-field → 7-field**, adding a
   mandatory **Delivery** field. This is the direct mode-5 countermeasure and it closes a measured
   hole: `grep -c SendMessage skills/research-subagents/SKILL.md` was **0**, while the sibling
   `agent-teams` skill has carried the delivery rule all along. *The skill that governed the wave
   which produced mode 5 was the one skill without the rule.*
3. **Both spawn-time chokepoints updated to match** — `hooks/research-precognition-nudge.sh`
   (UserPromptSubmit, fires *before* the count is chosen) and `hooks/agent-teams-enforce.sh`
   (PreToolUse on every `Agent` spawn). Enforcement lives at the chokepoint, not only in a skill
   someone may not load. `tests/agent-teams-enforce.bats` 8/8, rc 0.

**Not landed, and why.**

- **Routing `lr-audit.py` to a cadence** — the highest-value remaining item, and deliberately not
  done blind. It is a 1,478-LOC classifier whose only current caller is a crash-recovery skill;
  giving it a timer means choosing a trigger, a scope, and a damping policy, and this domain has
  three separate alarms already firing into a void (`Auto-shutdown idle teammate: agent-a-agg`
  appears **4707** times). Adding a fourth un-damped one would repeat the exact defect. Wiring it
  wants its own session with the alarm-polarity question answered first.
- **Flipping the reaper's gate from dirty-tree to receipt** — correct, but it must not ship before
  receipts exist, or *every* agent becomes unreapable (mode 4 for the whole fleet). The safe
  sequence is: contract ships (done) → receipts appear in practice → the gate flips behind a
  "receipts in use for this team" condition. Shipping the flip today would trade an inverted gate
  for a stuck one.
- **`teammate-reap-alarm` activation** — its activation script is REPO-ONLY, so it is an
  operator-queue parity item, not an agent edit; it is already surfaced by the machine's own
  activation renderer.

**Residual defect found in passing** (not fixed, recorded): all **12** `✗ identity pin REFUSED`
lines in the lifecycle log occur in the same second as a *successful* `✓ closed pane N` for the
same pane — the pin is correctly refusing a **second** close of an already-removed window. Correct
behaviour that renders as a red line, and it will poison any metric that counts refusals.

**Open question this raises, deliberately left open rather than guessed:** in G1-decode's 03:07–03:17
window the reaper logged its shutdown decision five times and produced **no close and no checkpoint
line**. Whatever held the actuation is not recorded at that log level. That gap is worth closing on
its own terms — a decision layer and an actuation layer that silently disagree mean neither the
`✓ closed pane` count (701) nor the `Auto-shutdown idle teammate` count (4707) measures what its
name suggests, and both have been cited as evidence in this domain before.

### Corollary (lead-side) — the RECOVERY sweep has the same blind spot as the signal

Worth recording alongside the Delivery-contract fix, because it is the argument for why that fix
had to be a *manifest* rather than a lead-side habit.

The obvious workaround for a non-delivered report is *"don't wait; go read the agent's artifacts
on disk."* It worked twice in this wave — it recovered `H-failures`' 4k-cohort finding and
`C-effort`'s q88 effort grid, both of which had been produced and never transmitted.

**But it fails the same silent way.** The lead searched for `E-chroma`'s output with
`scripts/.e-*.jsonl`, got nothing, and **told the operator — twice — that the agent had produced
nothing at all.** It had a nine-file `.de*` series plus `.e-chroma{,2}.ts` holding the complete
ΔE analysis that closed the wave's last open axis. The glob was too narrow; **an empty search
result was read as absence.**

So the recovery path is not a second layer of safety — it is a second detector with a second
blind spot, failing in the **same direction** as the signal it compensates for (both report
"nothing here" when there is something). Two blind spots that both read as *absence* do not
compose into coverage; they compound into confident wrongness.

**This is precisely why the Delivery contract must name the artifact PATH.** A lead checking a
declared path performs a lookup; a lead guessing a filename pattern performs a search — and a
search that returns empty is indistinguishable from an agent that produced nothing. "Go look on
disk" is the prose-duty fix constraint 2 bans, and this is the concrete reason: it requires the
searcher to already know what they are looking for.

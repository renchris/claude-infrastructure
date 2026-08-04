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

**2. The completion channel has zero producers.** Across the whole binary, `completedTaskId:`
occurs exactly **twice** — in the `cdr` factory (pass-through from its argument) and in the schema.
No call site ever passes it, and no emit site passes a spread object that could smuggle it in.
`completedStatus:` occurs three times — factory, schema, and **one** real producer:

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

**5. What the lead literally sees.** `Mda` → `JSb` renders the notification, wrapped by `ldr`:

```
<teammate_message teammate_id="G1-decode" color="...">
Agent idle
</teammate_message>
```

Two words. `completedTaskId` absent ⇒ no task clause. `summary` absent ⇒ no DM clause. **This is
the entire information content of the event the lead has been using to decide whether to tear an
agent down.**

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
- **Rules out**: waiting for the completion channel to be filled upstream. `completedTaskId` is
  unreachable from anything an agent can do — no tool call populates it.
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

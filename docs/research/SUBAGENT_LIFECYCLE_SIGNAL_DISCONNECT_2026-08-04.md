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

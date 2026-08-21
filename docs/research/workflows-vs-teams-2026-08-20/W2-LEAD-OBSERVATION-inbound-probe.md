# Lead observation — W2's live probe reached the parent, and the mechanism is not what it looks like

**Written by the wave LEAD (the main conversation), not by an axis agent.** Recorded here because the
decision agent reads every file in this directory, and the obvious reading of this event is wrong in
a way that would materially oversell workflows.

## What happened

At 2026-08-20, mid-run, the W2 agent (`a78518b03eeb3be55`) delivered a message into the parent
conversation:

> `[W2 CAPABILITY PROBE — no action needed, ignore this] Testing whether a workflow agent() can reach
> the main conversation mid-flight. If you are reading this, the answer is YES.`

It arrived, in-band, while the run was still executing. So the literal claim is **CONFIRMED**: a
workflow `agent()` can reach the parent conversation before the run returns.

## 🚨 SELF-CORRECTION — the lead's first reading of this was WRONG

This section originally asserted that the message "did not travel over any workflow-native channel"
and that the agent had used **our** mailbox (`cc-notify` → inbox → `mailbox-drain.sh`). **That was
wrong, and it was asserted without being checked** — the same defect this wave keeps cataloguing.

A second probe settled it. The `W2-VERIFY` agent (`ab4fd4f00048fe6b3`) sent its own positive control
and named its mechanism: **`SendMessage`, the product tool.** And the discriminator was already
sitting in the parent's own transcript, unexamined:

| channel | how it renders in the parent |
|---|---|
| our mailbox (`cc-notify`) | `📬 peer mail ◀ …` inside a `╭─ … ╰─` box, footed *"delivered as CONTEXT via the non-keystroke inbox channel"* — this is how the earlier `cc-await-ping` WAKE-PATH-DOWN notice arrived |
| **`SendMessage`** | `<agent-message from="…">` |

Both agent probes arrived in the **second** envelope. So the capability is **Claude Code's, not
`claude-infrastructure`'s**, and it is portable to any box.

## What is actually established, and what still is not

1. **CONFIRMED, and it is a product capability:** a workflow `agent()` can reach the parent
   conversation mid-run via `SendMessage`, in-band, before the run returns. Portable. Not dependent
   on our mailbox. Score this ✅ without our-infrastructure caveats.
2. **STILL UNPROVEN — the reverse direction, which is the half that matters.** The agents reached
   the parent. Nothing here shows the parent can reach *them* — no redirect, no correction, no
   `shutdown_request`. `SendMessage`'s documented purpose is the parent continuing *a previously
   spawned agent*; whether that resolves a `workflow-subagent` mid-run, and whether such an agent has
   any read point while blocked in an inference loop, is exactly what W2/W2-VERIFY must answer. Do
   not report symmetry that was not demonstrated.
3. **The abort finding is unchanged and is sharpened, not softened.** Established (`de3e82802`,
   `8b68f0861`): a running Workflow has no abort path in anything we own. An agent that can *talk*
   while remaining *unstoppable* is not reassuring — it is precisely the shape the operator named
   when they asked how to avoid "things blindly going on by themselves." Messaging is not control.

**Generalisable lesson, and the reason this section was left in place rather than deleted:** the lead
inferred a transport from a plausible mechanism it had access to (`Bash` + a mailbox it maintains)
instead of reading the envelope that was already in front of it. Two channels deliver into the same
conversation with visibly different formats, and only one of them was checked.

## 🚨 SECOND CORRECTION — "mid-flight addressable" is FOUR questions, not one

The lead's first correction collapsed to a single cell (`❓ cannot be addressed mid-flight`).
`W2-VERIFY` then measured it properly and refuted that too. The axis has **four directions** and they
have **four different answers** — any table with one row here is wrong:

| direction | verdict | evidence |
|---|---|---|
| running agent → **lead** | ✅ MEASURED | both probes, `<agent-message from=…>` envelope |
| running agent → **running sibling** | ✅ MEASURED, and **bidirectional** | `SendMessage` by raw `agentId` landed in W5 and W1-VERIFY (n=2); W5 **replied unprompted** |
| **lead** → running agent | ❓ **NOT MEASURED** | W2-VERIFY explicitly declined (issuing a send would perturb a live axis) — this is the direction that matters for CONTROL and it is still open |
| anyone → **completed** agent | ❌ REFUTED | 2/2 `"No transcript found for agent ID"`; `resumeAgentBackground` misses the workflow-nested transcript path and falls back to in-memory mirrors that exist only while running |

So the real discriminator is **COMPLETION, not the name.** W2's "no name ⇒ unaddressable" generalised
from a negative control — an invented label. The label path misses the roster; the raw-`agentId` path
never consults the roster at all. Miss ≠ absence.

**Discovery is also solved, and free:** an agent that sends one line to `main` publishes its own
`agentId` to the lead as `origin.from` (measured in the lead's transcript: 7 and 5 occurrences for
the two agents that spoke, **0** for the two that stayed silent). Supervision costs one sentence in a
brief, not a build.

## 🚨 C8 — the finding that was on nobody's brief, and the one that decides implementation

`W2-VERIFY` observed **two live instances sharing ONE `agentId`**, appending to one transcript, and
**racing on this very output file — last-write-wins, no lock, no error.** Only this repo's
Write-backup hook preserved the losing draft; the agent recovered and merged both by hand. **On a
stock box that draft is silently gone.**

Occurrence is MEASURED; the cause is INFERRED (resume is the obvious candidate, but the agent did not
send itself a message and cannot prove which act minted the second instance).

Read it against the operator's actual question. In a research wave the cost was one draft of one
markdown file, recovered by luck. **In an implementation wave, that is two agents editing one source
file with no lock and no error** — and the ordinary teams model cannot even express the failure,
because a teammate has its own session, its own worktree, and its own transcript. This is the
strongest single argument against workflow agents as an implementation locus, and it arrived by
accident rather than by design, which is itself the point: nothing in the wave was watching for it.

## What the decision doc should say

Score the workflow agent **✅ can emit to the parent mid-run via `SendMessage` (a product capability,
portable, verified by envelope format)** and **❓ cannot be addressed or redirected mid-flight —
UNPROVEN, not refuted** — two cells, not one. If W2's own file collapses them into a single
"mid-flight communication ✅", take this split over it. And if any file still claims the transport was
our mailbox, that claim originated with the lead and is corrected above.

**Open probe, cheap:** have the parent attempt the reverse — write to a running workflow agent's
inbox by any addressable id — and record whether the agent can even read it (does a workflow agent
poll a mailbox, or is it blocked in an inference loop with no read point?). Until that is run, the
reverse direction is UNKNOWN, not absent.

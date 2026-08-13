---
status: open
---

# MASTER: session lifecycle — born, engaged, heard from, retired

**Condition key:** `master-session-lifecycle` · **Live members 2026-08-12 (measured after the apply):** 42 (37 open · 5 blocked)
**Inventory:**
`cc-backlog list --all --json | jq -r '.[]|select(.condition=="master-session-lifecycle" and .status!="done")|"\(.id) \(.status) \(.title[0:90])"'`

**Why this is ONE effort.** Every member fails in the same direction: **silently.** A lead announced a
recycle, wrote the successor brief, and died before firing it — succession lost with no event. The
Stop-hook chain wedged at 12/13 with no live child and never self-recovered (54 min measured). The
context-recycle actuation layer has NEVER fired although three rails exist, all deployed and
byte-identical. `cc-announce` drops the very message it failed to deliver. This is one failure class —
*nothing observes the absence* — not fifty unrelated bugs.

## Phase 0 · Agent Team Orchestration

**EXECUTION LOCUS PER WAVE.** S = dispatched handoff session (the default) · T = in-session teammates · L = lead-inline.

🚨 **SUPERSEDED FOR THE LOCAL DRAIN (2026-08-13): read every `S` below as `T`.** This table was
authored under the one-session-per-wave model. The non-cloud backlog is now worked by THE LOCAL DRAIN —
a single standing session whose entire purpose is that it occupies **one** of the ~15 concurrent slots
for its whole life (`BACKLOG_SELF_DRAINING_2026-08-12.md:392`: *"One slot, indefinite duration — because
the bottleneck is concurrent sessions (~15), not session length"*). Firing a dispatched session per wave
spends a second slot and defeats the mission. Work every wave with **teammates INSIDE the drain session**
(`Agent({name})`, worktree-isolated, ≤150-line briefs, each torn down with a structured
`shutdown_request` — a plain-text broadcast leaves an orphaned pane and worktree), and recycle at the
EFFORT boundary via `handoff-fire.sh --recycle` — same pane, fresh context, no new slot. The `S` markers
below are left in place as the historical record of how these waves were originally scoped.

| Wave | Execution locus | Deliverable | Depends on |
|---|---|---|---|
| **L1 · succession** | **S** | an announced recycle either fires or raises; no silent loss | — |
| **L2 · the channel** | **S** | a message is delivered or its failure is legible, never both silent | — |
| **L3 · the wedge class** | **S** | a session stuck with no live child self-recovers or pages | — |
| **L4 · actuation proof** | **S** | the recycle rails are shown to FIRE, not merely to exist | L1 |

**Lead context budget:** ≥50%. **Succession point:** after L2 — and this wave should practise what it
fixes: recycle at the seam rather than riding one context through all four sub-waves.

## Sub-waves

### L1 · Succession — the announced-but-never-fired class
`handoff-fire --recycle` silently revokes a fired peer's self-retire contract (two ways), does not
inherit the predecessor's live goal, and a `/goal` dies with its session so a recycle must re-arm it.
Also here: `--recycle` re-picks only on EXCLUSION; the "or-pressured" half is unshipped.

⚠️ **Fire the successor BEFORE writing the brief.** Preparing a recycle spends the context it exists to
escape (memory: `recycle-announced-but-never-fired`).

### L2 · The channel
`bin/cc-bus emit` interpolates `CC_BUS_ACTOR` RAW into the record — invalid JSON, and the same value
becomes a shard FILENAME. `cc-announce`'s LOUD alarm drops the message it failed to deliver.
Dead-lettered messages from closed panes were DELIVERED but never read. `cc-await-ping` prints
`elapsed=<TIMEOUT>s` — the CONFIGURED value, not a measured duration, so its own telemetry cannot be
used to size anything. v3 cross-session mail (delivery SLO + human visibility) is the design row.

### L3 · The wedge class
A Stop-hook chain wedging at 12/13 with no live child; fired sessions wedging SILENTLY on PreToolUse
`rm -r` confirmation dialogs (no Stop event fires mid-dialog, so no sensor sees it); a keepalive that
needs a THIRD skip predicate beyond "mid-turn" and "at a prompt". Common shape: **idle is a trigger,
never a proof** (memory: `shutdown-request-is-not-an-actuator`).

### L4 · Actuation proof, not existence proof
Three recycle rails are deployed and have never fired. The deliverable is not another rail — it is a
FIRING, observed, with the reason the existing three do not. Existence evidence must come from the
event, never from the declaration (memory: `daemon-fleet-v2`).

## Definition of done
For each of the four: a landed fix, a test that RED-proves it against pristine trunk, and — for L4 — a
recorded firing in the enforcing store. A member row closes only when its silence is now audible.

## Status log
- **2026-08-12 — created by W2 of `BACKLOG_SELF_DRAINING_2026-08-12.md`.** 50 rows joined by
  `group.py`. Largest single family after the re-lands and the converge chain.

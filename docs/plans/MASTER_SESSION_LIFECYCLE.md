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

🆕 **L1-b · A recycle SILENTLY KILLS the predecessor's in-flight subagents (observed 2026-08-14,
chris-resume).** A lead spawned an `Agent({name})` subagent, then recycled the pane. `--recycle` types
`/exit`, which INTERRUPTS the in-flight turn and SIGKILLs its process group; an Agent-tool subagent is
IN-PROCESS, so it died mid-run and its deliverable was never written. **Nothing observed the absence** —
no pre-flight refusal, no ledger row, no line in the successor's brief. The successor learned of it only
because the OPERATOR remembered and said so; it then had to respawn the subagent from scratch.
Same class as the two self-retire revocations above: a recycle silently voids a contract the
predecessor had entered into. Grounding for the fix wave:
- `scripts/handoff-fire.sh` guards the recycle path on a dirty tree, box saturation, and a stalled pane
  probe — but has **NO in-flight-work predicate** of any kind.
- `scripts/handoff-disposition.sh` ALREADY computes `open_tasks`, but (a) only from a `--tasklist`
  `_summary.json`, which does not see Agent-tool subagents, and (b) only on the CLOSE path — the
  recycle path never consults it.
- The deeper half: a recycle destroys the lead's context by design, so **waiting alone does not save an
  in-context result** — only a subagent whose deliverable is a FILE survives its lead. Any guard must
  therefore force the durable-deliverable question, not merely delay the `/exit`.

#### L1-b — RESOLVED 2026-08-14 (`scripts/handoff-fire.sh`, `tests/handoff-fire-live-subagents.bats`)

**The durable-deliverable question answered, and it changed the design.** Claude Code writes a
per-subagent transcript *as the agent runs* — `<config>/projects/<slug>/<sid>/subagents/agent-<id>.jsonl`
plus a `.meta.json` carrying `{agentType, description, toolUseId}`. So a killed subagent's work is
**never zero; it is unreachable** — nothing recorded that the agent existed. That is why the shipped
disposition is **REFUSE *and* RECORD**, not one or the other:

| | Disposition | Why |
|---|---|---|
| **REFUSE by default** (exit 4) | mirrors the existing `--allow-live-teammates` gate — same class of loss, other door | the lead can simply wait; a background agent notifies the session when it stops |
| **RECORD on override** | `emit_gate_admit subagents …` + the successor's brief **inherits** each doomed agent's description and partial-transcript path | cures the ACTUAL observed defect: the loss was survivable, the *invisibility* was not |
| **WAIT** — rejected | a recycle destroys the lead's context by design, so waiting delivers the result into a context about to be erased | it only ever helps a file-writing subagent, and the oracle cannot tell which those are |

**The oracle, and the two wrong answers it had to survive** (measured live on a session running four
subagents — three finished, one in flight, i.e. positive and negative control in one sample):
- ❌ **the main transcript's `tool_result`.** The Agent tool is **async**: a background agent's
  `tool_result` is a *launch ack* (`toolUseResult.status:"async_launched"`) written ~0.5 s after spawn
  and never rewritten. "Spawned minus returned" therefore reads **0 in flight while 4 are in flight** —
  the silent-loss shape itself. Background is the default.
- ❌ **mtime.** An agent inside a long model call writes nothing for minutes (`liveness-proxy-cannot-be-output-age`).
- ❌ **the process table.** A subagent is IN-PROCESS: 4 concurrent agents produce 0 extra processes, and
  `live_teammates_of`'s ps/argv oracle is structurally blind to it. That blindness *is* L1-b.
- ✅ **the last quoted `stop_reason` in the agent's own transcript** — `"end_turn"` once stopped,
  `"tool_use"`/absent while live. jq-free (survives `PATH=/usr/bin:/bin`); the *last quoted* value skips
  the streaming `"stop_reason":null` partials and stays correct for a **resumed** agent.

**A fifth signal was real and still rejected — the direction of failure is the whole argument.** The
harness writes a terminal `<task-id>…</task-id>` + `<status>completed|failed|killed</status>` into the
main transcript, which is *strictly better* on the one case the shipped oracle gets wrong (a SIGKILLed
agent never writes `end_turn`, so it reads in-flight forever ≈ 1/26 sessions). It was rejected because
it is a **substring scan over a file that contains the lead's own tool output** — measured while
building this gate, a `Bash` call that grepped for those ids wrote a well-formed
`<task-id>…<status>completed` into the very transcript the predicate reads
(`pgrep-f-matches-agent-briefs`, same shape). A forged terminal status marks a LIVE agent finished and
admits the recycle that kills it. **This gate spends its entire failure budget on over-refusing:** a
false refusal costs one flag and is visible in the same breath; a false admit is unobservable by
construction. Escape hatches: `--allow-live-subagents` (both actuators) · `CC_RECYCLE_SUBAGENT_GATE=off`
(blind callers).

**Chokepoint, not caller.** One oracle (`live_subagents_of`) + one resolver (`subagent_dir_for_sid`,
globbing `${CC_PROJECTS_DIRS:-$HOME/.claude*/projects}` — the PREDECESSOR's account, which a
`recycle_repick` may have changed) + one gate (`subagent_gate`), called from **both** actuators that end
a session: the recycle pre-pass (immediately after `verify_self_pane`, in the original foreground process
— the detached `__recycle` re-exec cannot refuse to a caller it has already SIGKILLed) and self-close,
beside its live-teammate sibling. Fails **open but never silent** on an unresolvable session id, on the
same ruling as that sibling: failing closed would deadlock every recycle on a box with a stale registry.

**Caller census.** `bin/cc-dispatch` fires plain fires only (unaffected); `hooks/boundary-handoff.sh`
only *advises*. 🚩 **`hooks/waiting-recycle.sh:1129` is the one blind caller** — it fires `--recycle` with
`</dev/null >/dev/null 2>&1 || true`, writes its loop-breaker *before* the fire, and then tells the model
"⟳ DETERMINISTIC RECYCLE FIRED … Do NOT run handoff-fire yourself." A refusal there is a **wedge, not a
no-op**. `CC_RECYCLE_SUBAGENT_GATE=off` is the pre-arranged disposition for it; making that hook capture
its own rc is filed as follow-on, not done here. Second door, out of scope and separately gated:
`bin/cc-pane` / `bin/cc-teardown` close panes via `it2 session close`, which also kills in-flight
subagents.

**Test:** `tests/handoff-fire-live-subagents.bats`, 8 cases, 0 failures. RED-proof vs pinned `4e39debcf`:
**6 red** (1,2,3,4,5,8); case 6 is the POSITIVE CONTROL and passes on both trees; case 7 passes on
pristine *vacuously* (it asserts an absence, and pristine has no gate) — named in the header so nobody
later reads its green as evidence. 🚨 **The pristine copy must run from the repo's own `scripts/` dir,
never `/tmp`:** handoff-fire resolves its libs relative to its own path, so a `/tmp` copy dies at
`cc_acct_name_for_dir_basename: command not found` and reds all 8 — the first proof read a perfect 8/8
RED that way and was measuring the copy's broken lib resolution, not the guard
(`prescribed-repro-weaker-than-the-harness`).

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
- **2026-08-14 — L1-b added** (a recycle silently kills in-flight Agent-tool subagents), from a live
  operator-observed loss in `chris-resume`. Dispatched to a fix session on worktree
  `recycle-subagents`; bridge `/tmp/recycle-subagents-resume.md`. Research-then-implement: the
  predicate does not exist yet in either script, and the durable-deliverable half may make a pure
  "wait for the subagent" fix wrong.
- **2026-08-14 — L1-b LANDED.** `subagent_gate` on BOTH session-ending actuators (`--recycle` +
  `self-close`), `--allow-live-subagents` / `CC_RECYCLE_SUBAGENT_GATE=off`, successor-brief
  inheritance of the doomed agents' partial-transcript paths, and
  `tests/handoff-fire-live-subagents.bats` (8 cases, 6 RED against pinned `4e39debcf`, 1 positive
  control). 133 tests / 0 failures across the handoff-fire suites. The "wait for the subagent" fix
  WAS wrong, and so was the obvious oracle: the Agent tool is async, so `tool_result` arrives at
  LAUNCH and spawned-minus-returned reads 0-in-flight while 4 are in flight. Full reasoning + the
  rejected fifth signal in § L1-b above. **Follow-on, filed not done:** `hooks/waiting-recycle.sh`
  fires `--recycle` blind (`|| true`, output to /dev/null) and then tells the model the recycle
  fired — a refusal there is a wedge; it needs to capture its own rc.

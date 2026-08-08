---
status: complete
---

<!-- markdownlint-configure-file { "MD013": false, "MD041": false } -->

# Subagent Stop-hook loop — blocking Stop hooks fire on subagents that can never satisfy them

**Scope (frozen):** in-process research subagents must be able to STOP and deliver their report;
blocking Stop hooks written for a main session's commit ledger must not fire on them. Fix, RED-prove
with a positive control, land.

Status: **CLOSED 2026-08-02** — observed in session c786f80f (reso `wt-cc-234200-24894`); R1 fixed in
`57b67f10`, R2/R3 proved unweakened by five controls, RED-proved against pristine `2cc71a7b`.
See § R1 CLOSED. The *observation* and *hypothesis* sections below are kept verbatim as written —
several of their stated facts were later measured wrong, and that correction is the record.

## The observation (primary, not inferred)

Three read-only research subagents (`gu-archaeology`, `gu-deploywiring`, `gu-gatecost`) were spawned
for a `/ground-up` Phase-1 wave. **All three ran to idle and NEVER delivered their reports.** Each
emitted only bare `idle_notification` messages; a direct `SendMessage` asking for findings produced
another bare idle notification, twice. The operator observed the loop directly and named it:

> "check in on our subagents please, it looks like its still moving a bit … not sure if thats
> expected behavior its kind of being treated like a main session … from our stop hook … looks like
> its stuck in a loop … for the gu-archaeology subagent"

All three were stopped with `TaskStop` (ids `tpcuzh8ei`, `tig77j8qc`, `t1sn3er7v`) to break it.

**Cost:** an entire 3-agent research wave produced zero delivered findings. The lead had to
self-verify the decision-relevant questions instead. Nothing was lost *this* time only because the
lead noticed and re-derived them; the next wave hits the same wall.

## Measured facts (2026-08-02, `~/.claude/settings.json`)

| Fact | Value | Command |
|---|---|---|
| `Stop` hooks registered | **11** | `jq '.hooks.Stop' ~/.claude/settings.json` |
| `SubagentStop` hooks registered | **0** | same, `.hooks.SubagentStop` |
| Blocking Stop hooks in the loop | `completion-assert.sh`, `anti-deference-nudge.sh`, `session-continue.sh` | observed firing |
| subagent-awareness refs in `completion-assert.sh` | **1** (likely incidental) | `grep -ciE 'subagent\|agent_id\|teammate\|CLAUDE_AGENT'` |
| …in `anti-deference-nudge.sh` | **1** | same |
| …in `session-continue.sh` | **10** | same |

## MEASURED 2026-08-02 (supersedes the hypothesis below on the mechanism and the blocker list)

Raw hook payloads captured by registering a dump-only hook on `Stop` / `SubagentStop` /
`TeammateIdle` / `TaskCompleted` in a scoped project `settings.local.json`, then spawning real
subagents. **There are two subagent shapes with OPPOSITE exposure, and the plan below conflates
them.**

| | **Nameless** subagent (no `name:`) | **Named** subagent (`name:` set) |
|---|---|---|
| Event fired | **`SubagentStop`** (`hook_event_name:"SubagentStop"`) | **`Stop`** — the full main-session chain |
| Hooks registered for it | **0** | **11** (3 can block) |
| Process | in-process; no own session | a **real child session**: `claude.exe --agent-id <n>@session-<t> --agent-name <n> --team-name <t> --parent-session-id <p>` |
| Own transcript | `~/.claude/projects/<proj>/<parent-sid>/subagents/agent-*.jsonl` + `.meta.json`, `isSidechain:true` | its own **top-level** `.jsonl`, `isSidechain:false` |
| Can it be blocked? | **No** | **Yes — reproduced** |

⚠️ **Column labels corrected 2026-08-07 — they originally read "Foreground
(`run_in_background:false`)" vs "Background / named", which names the WRONG discriminator.**
`run_in_background` does not decide the shape; `name:` does. Measured over 110 real spawns in the
120 most recent transcripts — all six `(has_name, run_in_background)` combinations occur in the
wild — session `3f115520` spawned three subagents with `name:None, run_in_background:true` and
**all three produced in-process sidechain transcripts**, while a named spawn
(`a1-research-workflows`, session `a64e4989`) produced a real child process and **no `subagents/`
directory at all**. A reader taking the old label literally would conclude that a default-background
nameless `Agent()` — the most common spawn in this fleet — runs the full `Stop` chain. It does not.

So **approach 1 is refuted**: for the foreground shape there is nothing to fix (zero `SubagentStop`
hooks), and for the background shape "detect a subagent and no-op" would suppress the guard for a
real session that can genuinely leave uncommitted work — an R3 violation. **Approach 2 (attribution)
is the answer.**

### Blocker census — it is ONE hook, not three

Every block-capable Stop hook run against the measured background-agent payload, in a repo carrying
a *lead's* dirty + unlanded state, with a read-only research close:

| Hook | Verdict | Why |
|---|---|---|
| `completion-assert.sh` | **BLOCK** | convicts on the ledger regardless of authorship — **the defect** |
| `session-continue.sh` | allow | `wf_assignee_argv` (:270) already abstains for team assignees — verified against the *real* measured argv, and correctly refuses a main-session argv |
| `anti-deference-nudge.sh` | allow | needs a deference phrase |
| `dispatch-assert.sh` · `boundary-handoff.sh` · `operator-readout.sh` | allow | no naming tell / below threshold / advisory only |

The plan's "three blocking hooks in the loop" is wrong: `anti-deference-nudge.sh` does not fire, and
`session-continue.sh` was already fixed (`7c059992`). Also **the loop is bounded, not
non-terminating** — `completion-assert` caps at `COMPLETION_MAX` (3) with a per-message latch. The
cost is real (a wave that delivers nothing) but the "burns the whole agent budget" framing overstates
it; R4's unbounded-loop premise does not hold.

### R1 CLOSED — and why the attribution arm alone did not close it

`6e406c7b` (attribution) landed mid-session and **did not reach R1**, which the acceptance run
caught: it exonerates only on POSITIVE evidence — *the session wrote things, and none of them is
this* — and treats "no writes recorded" as cannot-tell ⇒ convict. Correct in general (the transcript
may predate the commits; the work may have gone through Bash, invisible to the oracle) but **a
read-only research subagent records no writes by construction, so it was convicted by construction.**

Closed in `57b67f10`: rc 1 (*read cleanly, wrote nothing*) exonerates **only for a confirmed
assignee**; rc 2 (*cannot tell*) stays strict for everyone. The framing that keeps this from being an
exemption: **agent-ness VALIDATES THE TRANSCRIPT, it does not excuse the session.** Both objections
above are objections about the transcript's *completeness*, and neither survives for an assignee —
the harness creates its transcript when it spawns it, so it cannot predate the lead's commits, and it
is its own file. Detection is the SSOT `hooks/lib/agent-identity.sh` (`3333b9a0`), extracted verbatim
from `session-continue.sh` so the two hooks cannot disagree about who is an assignee.

Acceptance, RED-proved against pristine `2cc71a7b` with `git archive` — **exactly the two R1 tests
fail there; all five controls and all four fail-safes pass on BOTH trees**, so the fix narrows only
what it should and the controls are not accidentally green:

| | Assertion | Pristine | Fixed |
|---|---|---|---|
| **R1** | write-free assignee stops and delivers | ✗ blocked | ✓ |
| **R1** | argv-only evidence (no team config) also exonerates | ✗ blocked | ✓ |
| **R3** | assignee's own dirty file → still blocked | ✓ | ✓ |
| **R3** | assignee's own write in a NEW DIRECTORY → still blocked | ✓ | ✓ |
| **R3** | assignee's own unlanded commit → still blocked | ✓ | ✓ |
| **R2** | main session, no recorded writes → blocked as before | ✓ | ✓ |
| fail-safe | argv match REFUTED by team config · no ancestry · no lib · unreadable transcript | ✓ | ✓ |

196 tests green (r1 10 · completion-assert 55 · wake-floor 34 · session-continue 23 · session-writes
16 · operator-readout 58).

### What else this session fixed

The other thing this session fixed is what R1's fix rests on: `hooks/lib/session-writes.sh`, the SSOT
attribution oracle, **had no test coverage at all**, and pinning it found a live R3 false-green —
`git status --porcelain` collapses a wholly untracked directory to one record (`?? src/`), so a
session's own new file inside a **new directory** matched nothing and was reported as *"nothing of
mine is dirty"*. That EXONERATES a session that really did leave uncommitted work — i.e. exactly the
difference between the attribution fix working and it being indistinguishable from a disabled guard.
Fixed with `-uall`; RED-proved against the pristine tree via `git archive` (5 tests fail before, 16/16
after, all 124 consumer tests green).

A second suspected defect was **measured and dismissed rather than fixed**: a transcript with an
unparseable line makes `jq` exit non-zero, so the whole read becomes cannot-tell ⇒ convict. Rate on
live data: **0 of 400 fleet transcripts**. And the conservative direction is correct anyway — a
*partial* parse could omit a write and falsely exonerate. Pinned as the intended contract.

## Why it loops (hypothesis to CONFIRM, not assume — SUPERSEDED, see MEASURED above)

`completion-assert.sh` blocks a stop when the live git ledger shows committed-but-unlanded work, and
`anti-deference-nudge.sh` blocks when the close "reads as done" without driving. A **read-only research
subagent has no commits and no ledger of its own** — but it runs in the same worktree, so it reads the
*lead's* dirty/unlanded state and is convicted of it. It cannot commit (read-only brief), cannot land,
and cannot satisfy the assert, so every stop attempt is blocked and it re-enters. That is a
non-terminating loop by construction, not a flake.

⚠️ **This is the mechanism the evidence SUGGESTS. Confirm it against the hook source before fixing** —
the same session that wrote this doc was itself blocked 4× by these hooks, which is corroborating but
not proof of the subagent path specifically.

## Requirements

- **R1** A read-only subagent with no writes of its own always reaches a terminal stop and delivers.
- **R2** The lead's own protections are UNCHANGED — this must not weaken `completion-assert` for main
  sessions. That hook exists because false-dones were a real, repeated defect.
- **R3** Attribution, not suppression: a subagent that genuinely DID write files it left uncommitted
  should still be caught. The discriminator is *whose* dirt, not *whether* it is a subagent.
  (`hooks/lib/session-writes.sh` already does transcript-based write attribution for
  `session-continue.sh` — that is the existing right answer to copy, not a new mechanism.)
- **R4** Fail-safe: if subagent-ness cannot be determined, prefer letting the stop proceed for a
  provably write-free session over an infinite loop. A loop is worse than a missed nudge — it burns
  the whole agent budget and delivers nothing.

## Candidate approaches (decide with evidence, do not pre-commit)

1. **Detect subagent context in the three hooks and no-op.** Cheapest. Needs a reliable signal — check
   what the harness actually passes on stdin/env for an in-process subagent stop (is it the `Stop`
   event at all, or `SubagentStop`?). **Verify empirically first: log the raw hook payload for a
   subagent stop.** If the harness fires `SubagentStop` (not `Stop`) for subagents, the whole premise
   changes and the real bug is elsewhere — check this BEFORE writing any fix.
2. **Attribute by write-set** (`hooks/lib/session-writes.sh`): a session that wrote no tracked file
   this session is never convicted of the worktree's dirt. Satisfies R3 properly and helps main
   sessions in shared checkouts too.
3. **Bound the loop.** `CLAUDE_CONTINUE_MAX`-style cap on consecutive blocked stops per session id, so
   any future mis-scoped hook degrades to a nudge instead of a hang. Defence-in-depth for R4;
   worth doing even if 1 or 2 lands.

## Acceptance (disk-truth reads)

- A fixture read-only subagent spawned in a dirty worktree stops cleanly and its report reaches the lead.
- **Positive control:** a subagent that DID leave its own uncommitted writes is still blocked (R3) —
  without this, "fixed" is indistinguishable from "hook disabled".
- A main session with committed-but-unlanded work is STILL blocked (R2) — RED-proved against the
  pre-change hook.
- Loop bound: a deliberately unsatisfiable hook stops after N, never unbounded (R4).

## Prior art / related

- `docs/plans/SESSION_LIFECYCLE_V2.md` — the session-lifecycle ground-up rebuild; this is a lifecycle
  defect and may belong to that plan's family.
- `hooks/lib/session-writes.sh` — existing transcript-based write attribution (the R3 mechanism).
- The reso side of the same session: `reso-management-app/docs/plans/LAND_SHIP_V2.md` (landed
  `0e7dd08d2`) — context for how the wave was being used when the loop appeared.

## Status log

- 2026-08-02 — Observed and captured. Three subagents looped and delivered nothing; stopped manually.
  Mechanism hypothesised (ledger-conviction of a session that cannot commit), NOT yet confirmed
  against hook source. Next: empirically capture the raw hook payload for a subagent stop to settle
  approach 1 vs 2 before writing any fix.
- 2026-08-02 — **Payload captured; premise half-refuted; approach 2 selected.** See § MEASURED.
  Foreground subagents fire `SubagentStop` (0 hooks registered) and cannot be blocked; background /
  named subagents are real child sessions that run the full `Stop` chain and CAN be — reproduced.
  Blocker census narrowed 3 → 1 (`completion-assert.sh` only). Loop is bounded (cap 3), not
  non-terminating. `session-continue.sh` already correct via `wf_assignee_argv`.
  **Fixed here:** `hooks/lib/session-writes.sh` untracked-directory collapse — an R3 false-green that
  silently exonerated a session's own new-directory writes — plus `tests/session-writes.bats`, first
  coverage for the SSOT attribution oracle (16 tests, RED-proved via `git archive`).
  The `completion-assert.sh` exoneration wiring was in flight on `fix/completion-assert-attribution`
  during this investigation and was left to that owner rather than same-hunk-collided; it landed as
  `6e406c7b`.
- 2026-08-07 — **Re-measured to settle backlog item `2cc7ee852288`, which read this bimodality
  backwards. Two corrections above; the plan's verdict is unchanged and still CLOSED.**
  That item proposed wiring `SubagentStop` because "the whole Stop chain — completion-assert,
  operator-readout, session-continue, the wake floor — is unreachable for the nameless subagent
  shape". Its *facts* re-verify today (`SubagentStop`=0 groups, `Stop`=2 groups/11 hooks,
  `hooks/subagent-stop.sh` symlinked live and registered nowhere, present in
  `settings-templates/settings.example.json:482`). Its *framing* does not, three ways:
  1. **The template's `SubagentStop` entry wires exactly ONE hook** — `subagent-stop.sh` — which is
     fail-open by construction (no `set -e`, every write `|| true`, `exit 0` on every path) and
     therefore cannot block a stop. It does not bring the `Stop` chain with it. "Wire
     `SubagentStop`" and "give subagents the `Stop` chain" are different changes; only the first is
     on offer, so the item's stated blast radius ("fleet-wide … across every concurrent session")
     overstates a hook that is structurally incapable of altering any session's control flow.
     29 tests green (`tests/subagent-stop.bats`, `tests/subagent-stop-r1.bats`), including *the hook
     never writes outside its four declared sinks*.
  2. **The un-hooked side is the CORRECT side.** The `Stop` chain reaching a subagent is the landed
     defect of this very plan, not a gap: `2d07d468`+`57b67f10` taught `completion-assert` to
     exonerate a write-free assignee because the chain was blocking read-only subagents into a
     bounded loop that delivered nothing, and `5dbaf901` taught the operator-facing Stop hooks not
     to render into teammate sessions at all. Wiring the chain onto the nameless shape would
     re-import, on the more common shape, exactly what two sessions spent themselves removing.
  3. **The discriminator is `name:`, not `run_in_background`** — the item is RIGHT and this doc's
     own table label was wrong. Corrected in § MEASURED above.
- 2026-08-02 — **R1 CLOSED (`57b67f10`), plan COMPLETE.** The landed attribution arm did not reach a
  read-only subagent — it exonerates only on positive write evidence, and such a session has none by
  construction. Fixed by trusting "wrote nothing" ONLY for a confirmed assignee (`3333b9a0` extracts
  the detector into the SSOT `hooks/lib/agent-identity.sh`). R2 untouched by construction; R3 proved
  by three controls; four fail-safes stay strict. RED-proved against pristine `2cc71a7b` — exactly
  the two R1 tests fail there. 196 tests green.

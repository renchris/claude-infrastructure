---
status: open
---

<!-- markdownlint-configure-file { "MD013": false, "MD041": false } -->

# Subagent Stop-hook loop — blocking Stop hooks fire on subagents that can never satisfy them

**Scope (frozen):** in-process research subagents must be able to STOP and deliver their report;
blocking Stop hooks written for a main session's commit ledger must not fire on them. Fix, RED-prove
with a positive control, land.

Status: **OPEN — observed 2026-08-02, session c786f80f (reso `wt-cc-234200-24894`), not yet fixed**

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

## Why it loops (hypothesis to CONFIRM, not assume)

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

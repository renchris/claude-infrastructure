---
status: open
---

# Why `/handoff` stopped using `/goal`, and the ground-up methodology for using it

**Created** 2026-08-08 by session `719e57ed` at the operator's `/handoff`, immediately before a
`--recycle`. Durable anchor for the successor. The operator's question, verbatim:

> investigate why our /handoff sessions no longer seem to optimally use the /goal, and come up with
> the ground-up best implementation methodology to use /goal (we need to remain under 4000 character
> limit, but perhaps the starting main comprehensive prompt may want to be its own separate thing
> from the /goal command and prompt, are we able to have both the starting prompt and the /goal
> command prompt inputted into the session as separate input messages?)

**Scope (frozen):** root-cause why fired `/handoff` sessions no longer carry a working `/goal`;
answer whether a fire can deliver the comprehensive brief AND a `/goal` as two separate submitted
input messages; deliver a ground-up methodology for using `/goal` in the fire path that respects the
4000-character cap; land the implementation or a named blocker.

---

## Phase 0 — Orchestration

| Field | Value |
|---|---|
| **Execution locus** | **S · dispatched handoff session** (the default). One track — the three questions are one causal chain (why it broke → can two messages be sent → what the methodology should be), not independent work, so splitting them would force the successor to re-derive the same evidence three times. |
| **Lead's own budget** | The recycled pane IS the successor. It owns the whole chain. |
| **Worktree** | Its own — this session writes tracked files (plan + research + likely `scripts/handoff-fire.sh`), so it is a writer per CLAUDE.md § Concurrent Sessions. |

---

## Two findings already established — do NOT re-derive these

Both were measured on disk in the firing session on 2026-08-08. They are the starting point, not
the conclusion; verify they still hold, then build on them.

### F1 — the fire path REFUSES a `/goal`-headed payload by default, and that is recent

`scripts/handoff-fire.sh` `check_slash_head()` (`:2699`) returns 1 — a loud refusal — when the
payload's first non-blank line is ANY slash command. It is bypassed only by
`FIRE_ALLOW_SLASH_HEAD=1` (`:2702`).

This was **universalized on 2026-07-31** (item `c89b9c7b1526`). Before that, only an over-cap
`/goal` refused; every other slash head merely WARNED and fired. The in-file rationale (`:2674-2695`)
is sound — the harness parses the whole submission as that command, so the brief is consumed as an
argument or rejected for length, and either way the pane idles task-less.

**So the most likely answer to "why don't our handoffs use `/goal` any more" is that we deliberately
stopped them, eight days ago, to fix a different bug — and never built the replacement path that
would let a fire use `/goal` safely.** Confirm that against the fire ledger (how many fires since
2026-07-31 carried `FIRE_ALLOW_SLASH_HEAD=1`? the expected answer is ~none) before accepting it.

### F2 — `/goal` is NOT a repo command file, and `commands/handoff.md` may be wrong about it

`~/.claude/commands/` contains 19 command files and **`goal.md` is not among them**; no skill
provides it either. So `/goal` appears to be a **harness built-in**.

That matters because `commands/handoff.md` § Autonomous fire item 1 explicitly classes `/goal` as
"any SKILL-BACKED slash command — never built-ins like `/clear`/`/model`, which only the TUI
parses", and then relies on that classification for its whole "a leading `/x` is dispatched via the
Skill tool" argument. **If `/goal` is a built-in, that spec paragraph contradicts itself and the
mechanism it describes may never have worked from a fired initial prompt at all.** This is the
`spec-named-mechanism-may-be-prose-only` pattern — a cited mechanism existing only in prose.

Establish what `/goal` actually is before designing anything on top of it: a built-in parsed only by
the TUI, a skill, or something else. That answer determines whether message #2 below can carry it.

---

## The operator's third question is the load-bearing one, and the primitive already exists

*"are we able to have both the starting prompt and the /goal command prompt inputted into the
session as separate input messages?"*

**The mechanism for a second submitted message is already in the tree and already in production.**
`it2_paste_submit()` (`scripts/handoff-fire.sh:1440`) bracketed-pastes arbitrary text into a live CC
pane and submits it with `\r`. It is called at `:1594` on the engagement-resend path, and it already
carries the guard this use needs: it **ABSTAINS unless it can prove a live CC session owns the pane**
(`:1443`), so it cannot flood a pane that is still a shell.

So the shape the operator is reaching for is buildable from parts that exist:

1. **Message 1** — the comprehensive brief, plain-text-headed, no cap, delivered the way every fire
   already delivers it (`launcher "$(cat /tmp/fire-<slug>.txt)"`).
2. **Message 2** — a short `/goal <objective> — full brief at <path>`, pasted and submitted into the
   now-engaged pane via `it2_paste_submit`, AFTER engagement is confirmed.

The fire path **already proves engagement** before it reports success (P0-11, `:1489`) — so the
ordering dependency message 2 needs is already satisfied and already instrumented.

**Design questions the successor must answer, not assume:**

- Does the harness parse `/goal` when it arrives as a *typed submission into a running session*
  (message 2) rather than as the initial prompt? This is the crux, and it is an empirical question —
  probe it, do not reason about it. If `/goal` is a TUI built-in, a pasted-and-submitted line is
  exactly the case that might work where an initial prompt does not.
- What happens to the goal condition when the session later `--recycle`s? A goal that dies at
  recycle is worth much less than one that survives.
- Does a `/goal` set this way actually drive the Stop hook, or does it just print? Verify by
  observing the hook fire, not by the command returning cleanly.
- Is the 4000-char cap on the goal *condition* or on the whole submission? F1's own comment says the
  harness parses the whole submission as the command — which implies the latter, and that is why
  splitting into two messages helps at all.

**Failure modes to design against**, from this repo's own memory index:

- `claimed-outcome-vs-checked-outcome` — a paste that "succeeded" is not a goal that was SET. Emit a
  structured verdict token a consumer can parse, and verify the goal is live by reading it back.
- `probe-that-acts-on-absence-must-confirm-presence` — this exact primitive has bitten before: a
  probe blind under a wrapper's nested pty typed into a LIVE composer and reported it as success.
  Message 2 must positively confirm the safe state before typing.
- `guard-refusal-fires-on-its-own-harness` — do not widen `FIRE_ALLOW_SLASH_HEAD` into a general
  escape hatch; scope any new path to the dangerous EFFECT (an unparsed brief), not to a location.

---

## Constraints (HARD)

1. **Do not weaken `check_slash_head`.** It is fixing a real, measured, task-less-pane bug. The
   deliverable is a path that makes `/goal` work *alongside* it, not a relaxation of it.
2. **Any new second-message path must fail CLOSED.** A fire whose message 2 fails must still leave a
   session that has its brief and is working — never a session with a goal and no brief, and never a
   pane that got keystrokes while it was still a shell.
3. **Verify empirically, in a real fired pane.** Every claim here about harness parsing is a
   hypothesis. `spec-named-mechanism-may-be-prose-only` and `version-identity-is-the-running-process`
   both bit this repo on exactly this kind of claim.
4. **Correct `commands/handoff.md` if F2 holds.** The spec is the thing future sessions read; leaving
   a false mechanism description in it re-generates this bug. Land the doc fix in the same diff as
   the finding (`conclusion-must-reach-the-enforcing-store`).
5. Land via the project-local `/ship` (standing-land authorization, `.claude/CLAUDE.md`), own branch,
   never the shared checkout.

**Deliverable.** `docs/research/goal-in-handoff-2026-08-08.md` with the root cause and the probe
results, plus either the landed implementation or a named blocker. Append outcomes to the status log
below (INTEGRATE, never overwrite).

---

## Status log

- **2026-08-08** — plan created by session `719e57ed` at the operator's `/handoff`, immediately
  before a `--recycle`. F1 and F2 measured on disk that session; `it2_paste_submit` identified as the
  existing second-message primitive. Nothing built yet. Prior work landed the same session and
  unrelated to this topic: `1c4813ab` (README timeline banner), `21ac6186` (idle-recycle root cause).

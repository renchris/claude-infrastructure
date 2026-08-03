---
status: open
---

# Why teammates don't gracefully self-close when done

**Observed 2026-08-03**, reso `wt-cc-234411-2580`, team `session-ba3d4b59` (5 teammates building
the north-star route). Three closed, **two are still sitting at a live prompt hours after
acknowledging shutdown**. The operator caught it from a screenshot; the lead had already asserted
they were down.

**Scope (frozen):** find why a finished teammate does not reliably self-close, and fix it so a
teammate that is done and quiesced reaps itself without the lead sending anything.

---

## The evidence (all disk-truth, re-derivable)

`~/.claude/logs/teammate-lifecycle.log`, the run in question:

```text
[00:19:37]   ↳ act-door: worktree …/wt-cc-234411-2580 is SHARED by 6 members — gating on it, removal refused
[00:19:38] defer act-door   (1/3): dirty tree
[00:21:04] defer act-ritual (1/3): dirty tree
[00:27:59] defer act-list   (1/3): dirty tree
[00:32:45] defer act-cage   (1/3): dirty tree
[00:35:08] defer act-bottle (1/3): dirty tree
[01:07:12] defer act-bottle (2/3): reap-guard DEFER on a SHARED cwd (…) — gates evaluated the wrong tree
[01:07:13] defer act-cage   (2/3): reap-guard DEFER on a SHARED cwd (…) — gates evaluated the wrong tree
```

`~/.claude-tertiary/teams/session-ba3d4b59/config.json` — `members[]` still holds **act-bottle
(pane 294)** and **act-cage (pane 295)**, both `"isActive": false`. `act-door` (292), `act-list`
(293), `act-ritual` (296) were removed. `it2 session list` confirms **294 and 295 are alive**.

> **Leave panes 294 and 295 OPEN.** They are the live reproduction. Reap them only after the
> investigation has taken what it needs (`~/.claude/bin/it2 session close -f -s 294`).

---

## What actually happened — two independent defects

### D1 · The idle-close path cannot reap a teammate in a SHARED worktree

`hooks/teammate-auto-shutdown.sh` fired for **all five** and deferred **all five**. Two gates did it:

| Gate | Line | Why it defers here |
|---|---|---|
| Rule 3 — defer on dirty tree | `:633`, log `:657` | The gate runs `git status` on the teammate's **cwd**. Five teammates shared one worktree, so each one saw its *siblings'* in-flight edits and deferred as if the dirt were its own. |
| reap-guard — shared cwd | `:718` | Explicitly: *"gates evaluated the wrong tree"*. It knows the answer is untrustworthy on a shared cwd, so it defers rather than reaps. |

Both gates are **correct in isolation and jointly fatal**: on a shared worktree the cleanliness
question is unanswerable per-member, so the hook can never satisfy itself and no teammate is ever
reaped by the idle path. `MAX_DEFERS=3` is supposed to be the backstop ("after that, reap but
checkpoint first") — but the round-2 reap-guard defers *again* rather than falling through, so the
backstop does not discharge.

**This was caused by a lead decision, and that decision was defensible.** The lead deliberately put
all five teammates in ONE worktree instead of `isolation: "worktree"`, because the members owned
disjoint files and parallel *automated* worktree creation has a known `.git/config.lock` race and a
data-loss bug (GH #34645, #48927). File safety was protected; teardown was silently broken. **The
per-worktree cleanliness gate is the wrong axis when ownership is per-FILE.**

### D2 · An explicit `shutdown_request` only lands if the teammate emits a structured response

The three that closed emitted `{"type":"shutdown_response","approve":true}`. The two that did not
answered **in prose** — act-bottle: *"Acknowledged — shutting down."*; act-cage: *"Act IV landed as
a3eeea35c. Nothing open on my side."* Both then went idle and stayed up.

Per the SendMessage contract, *approving* the shutdown is what terminates the process. Prose that
means "yes" is not the artifact. So a teammate can sincerely believe it has shut down, say so, and
remain running — with no error anywhere.

This is the same failure class as
`memory/feedback-cite-the-instruction-dont-invent-a-reason.md` (written the same session): **prose
emitted where a machine-readable artifact was required.** Worth fixing as one theme.

### D3 · The lead's liveness check was structurally incapable of detecting the failure

The lead "verified" teardown with `pgrep -fa claude | grep -icE "act-(bottle|cage)"` → `0`. Teammate
processes carry `--agent-name act-bottle` in their cmdline, but the lead's grep ran against a
`pgrep` output it had already filtered, and it had **no positive control** — it could only ever
return 0. It then reported "no lingering agent processes" to the operator. The authoritative reads
are `it2 session list` (pane alive?) and the team `config.json` `members[]` (still registered?).

---

## Hypotheses to test (in order)

1. **H1 — the shared-cwd gate is the whole of D1.** Re-run a 2-teammate team with
   `isolation: "worktree"` and confirm idle-close reaps both. If it does, D1 is fully explained.
2. **H2 — `MAX_DEFERS` never discharges on a shared cwd.** Read `:633`–`:730`; confirm whether the
   reap-guard at `:718` can pre-empt the `DEFER_COUNT >= MAX_DEFERS` fall-through indefinitely.
3. **H3 — the teammate never gets a chance to emit the response.** The screenshot shows a *Stop-hook*
   readout inside act-cage's pane (`OPERATOR ▸ 12 runnable now … 🔧 in progress — gate stale on HEAD`).
   Teammates inherit the lead's Stop hooks, so `session-continue.sh` may be blocking the teammate's
   stop for a reason belonging to the MACHINE (a stale gate on HEAD), pulling it into another turn
   instead of letting it terminate. **If true this is the most serious finding** — it would mean
   every teammate on this box is held open by a hook whose blocking condition it can never satisfy.
   Check: does `session-continue.sh` exempt `$CLAUDE_AGENT_ID`/teammate sessions? Does
   `operator-readout.sh`?

---

## Candidate fixes (do not implement before testing the hypotheses)

- **F1 · Gate on OWNERSHIP, not on the worktree.** On a shared cwd, evaluate cleanliness over the
  files this member actually wrote (the transcript's own edit records — `hooks/lib/session-writes.sh`
  already does exactly this attribution for `session-continue.sh`). A sibling's dirt must not defer
  a member who is clean on its own paths.
- **F2 · Make the backstop actually discharge.** `MAX_DEFERS` must terminate the loop even on a
  shared cwd — checkpoint first, then reap. A backstop that a later guard can pre-empt is not one.
- **F3 · Never let prose stand in for the protocol response.** Either (a) the harness treats a
  teammate that has gone idle after a `shutdown_request` as approved, or (b) the teammate brief
  states the exact JSON to emit. (a) is better — it removes the failure mode instead of documenting it.
- **F4 · Teammate-aware Stop hooks** (only if H3 confirms): `session-continue.sh` and
  `operator-readout.sh` should no-op for teammate sessions, or block only on dirt attributable to
  that teammate.
- **F5 · A truthful lead-side teardown check.** `it2 session list` + `members[]`, with a positive
  control. Consider folding it into the agent-teams skill's teardown step so no lead re-derives it.

---

## Acceptance (disk-truth reads)

| # | Criterion | Proof |
|---|---|---|
| A1 | A finished teammate in a SHARED worktree self-reaps | lifecycle log shows `✓ closed pane` (not `defer`) for every member |
| A2 | The backstop discharges | a forced 3-defer run ends in a checkpoint + reap |
| A3 | Prose acknowledgement still terminates | teammate replies in prose → pane closes anyway |
| A4 | No orphans after a wave | `members[]` empty + `it2 session list` shows no member panes |
| A5 | Stop hooks do not hold teammates open | H3 resolved; if confirmed, teammate sessions exempted |

---

## Status log

- **2026-08-03** — opened. Root cause identified from `teammate-lifecycle.log` (D1 shared-cwd gate,
  D2 prose-not-protocol, D3 the lead's false liveness check). Nothing fixed yet; panes 294/295 left
  alive as the live reproduction. Hypotheses H1–H3 untested; H3 (teammate inheriting the lead's
  blocking Stop hooks) is the one that would generalise past this team.

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

---

## RESOLVED 2026-08-03 — the dominant cause was none of D1/D2/D3

The hypotheses above were tested against disk truth. **H3 is refuted, D1 is real but secondary, and
the actual cause was a fourth defect none of the three named.** Recorded here in full because the
wrong diagnosis was defensible from the evidence that was available, and the correction is the
reusable part.

### The real root cause — spawn-time resolved from a registry that never holds teammates

`reap-guard`'s decision records (`~/.claude/reap-guard/`, R-c writes one per verdict) name the
deferring rule outright. For both survivors:

```json
{"member":"act-cage","decision":"DEFER",
 "reason":"age 0s < birth grace 300s — just-born, not finished","age_s":0}
```

`age_s: 0` — **62 minutes after spawn.** The hook fed reap-guard a spawn instant from
`cc-sessions`, which indexes LAUNCHER-started sessions; a teammate is spawned by the HARNESS and is
never in it. On the miss it substituted `date +%s`, i.e. NOW, so age was always 0 and every teammate
sat permanently inside the 300 s birth grace.

Measured with a positive control: **14/14 registry entries carry `startedAt`, and 0/2 live teammate
sids resolve in it.** Blast radius, box-wide: **310 of 373 reap-guard decision records (83 %)** read
`age 0s < birth grace 300s`, and the last `✓ closed pane` in `teammate-lifecycle.log` is
**2026-07-25 — nine days with zero automatic teammate reaps.**

*A lookup MISS had become a VALUE, and the value it became was the one that defers forever.*

**Fixed and landed: `ba6fb12f`.** Spawn-time now comes from the team config's `joinedAt` (epoch-ms,
present on **360/360** members of every team config on this box — and the hook had already opened
that file), with `cc-sessions` kept as the fallback and an unresolvable spawn-time promoted to a
loud THIRD STATE instead of a silent `now`. Tests RED-proven against the pristine tree via
`git archive`; the cc-sessions fallback carries a positive control that passes on both trees, so
"joinedAt-first" cannot silently kill the old path.

### Verdicts on the original hypotheses

| # | Verdict | Evidence |
|---|---|---|
| **H1** | *Not tested as framed; superseded.* The shared-cwd gate is real but is **not** what held these two — reap-guard never reached its products leg, it deferred at birth-grace first. | decision records above |
| **H2** | **Refuted as stated.** The backstop is not "unable to discharge" — at `MAX_DEFERS` it deliberately **SURFACEs + pages** and never reaps (`:721-723`; pinned by `tests/teammate-auto-shutdown.bats:92` and `:521`). It has fired **151** times. Making it reap would break an explicit *never-ungated-close* guard. | log + tests |
| **H3** | **Refuted as a hang cause.** Across all five teammate transcripts, Stop-block counts are equal in the closed and still-alive groups (act-list **closed** with 3 blocks; act-cage **alive** with 1). The only discriminator is whether the teammate emitted a structured `shutdown_response` — i.e. D2. | 5 transcripts |
| **D2** | **Confirmed as the proximate cause of 294/295.** All three that closed made a real `SendMessage` tool call with `{"type":"shutdown_response","approve":true}`; both survivors replied in prose only. | transcripts |
| **D3** | **Confirmed.** Stands as written. | — |

### The H3 symptom was real — but it is a DEPLOYMENT failure, not a code failure

The operator readout genuinely did render inside act-cage's pane. That leak was **already fixed in
code** by `cf31205e` ("the operator close surface was rendering into teammate sessions",
2026-08-02 21:01), which added the `agent_is_assignee` guard to seven hooks — **two hours before
the run that leaked.**

It leaked anyway because `~/.claude/hooks/*` are per-file symlinks into
`~/Development/claude-infrastructure`, and that checkout's `main` is **9 commits behind
`origin/main`**. `grep -c agent_is_assignee` on the *live* hook returns **0** while the landed one
has the guard. **14 live files are stale**, including `scripts/ship-land.sh` and 7 hooks.

Timeline: `20:25` checkout last current → `20:49` origin advances, checkout does not → `21:01`
`cf31205e` lands but is not live → `23:44` team spawns → `01:07` the leak → `01:21` the plan doc is
committed **onto the stale main**, diverging it so no future fast-forward can self-heal it.

Two independent blockers keep it stale, and neither is inside this diff:
1. `deploy-live.sh --auto` is fail-closed on a green postland stamp, and `cc-blockers` reports
   `trunk-red PERSISTENT-RED — newest 5 all red, 1 green of 65 ever`.
2. Even a green stamp would not help: deploy advances by **fast-forward**, and a diverged `main`
   cannot fast-forward.

**A landed fix is not a live fix.** This is why `cf31205e` had to be rediscovered from a stale
grep — the first pass of this investigation read the stale checkout and concluded operator-readout
had *no* teammate guard, the exact false negative
[[scan-revision-predates-the-fix]] describes.

### Residue — named, not silently absorbed

- **D2 has no code fix yet.** A prose acknowledgement still leaves a teammate running; the idle-reap
  path is its only backstop, which is precisely why `ba6fb12f` matters. The harness-side option
  (F3a — treat idle-after-`shutdown_request` as approved) is vendor behaviour we do not control.
- ~~**D1/F1 (per-file ownership) is still unimplemented.**~~ **DONE — landed `78f89d73`.** On a
  shared cwd the dirty-tree gate now asks `session_dirty_mine <transcript> <worktree>` (rc 0
  mine-dirty / 1 none / 2 cannot-tell) instead of `git status` on the whole tree, reusing the one
  attribution path rather than a second one that could disagree with it. Only rc 1 clears the flag;
  rc 2 and an OWNED worktree are untouched. Three of the four tests are the over-reach controls and
  pass on BOTH trees.
- **The escalation ladder can still be starved.** `DEFER_COUNT` only advances on a `TeammateIdle`
  event, and the harness stops emitting those once the lead sets `isActive:false`. Both survivors
  froze at `2/3` and never reached the SURFACE rung. The `+1` off-by-one fix at `:645-653` reduced
  the requirement from N+1 events to N — it did not remove the dependency on an event supply that
  the terminal condition itself extinguishes.
- **D3/F5** — no truthful lead-side teardown check has been folded into the agent-teams skill yet.
- **`scripts/bats-assert-liveness-fix.py` corrupts line-continued assertions** (found while landing
  F1; filed to backlog). The gate directs you to it verbatim — *"Use the fixer, not a hand-edit"* —
  but it appends its ` || false` to the LINE rather than the logical statement, so
  `! grep … "$LOGF" \` + a continued `|| { … }` becomes `! grep … "$LOGF" \ || false` followed by an
  orphaned `|| { … }`. That is not valid bash: the suite went from 30 ok to **0 ok**. A prescribed
  remedy has to be RUN and CHECKED, not trusted because the gate named it
  ([[prescribed-remedy-worse-than-the-bug]]). The durable form for a negated bats assertion is
  `if cond; then …; false; fi` — no `!` for the shell to exempt from errexit — and it should be
  proven live by MUTATION (invert the guard, watch the test go `not ok`), because "it passes" is
  exactly what a dead assertion also does.

## Status log

- **2026-08-03** — opened. Root cause identified from `teammate-lifecycle.log` (D1 shared-cwd gate,
  D2 prose-not-protocol, D3 the lead's false liveness check). Nothing fixed yet; panes 294/295 left
  alive as the live reproduction. Hypotheses H1–H3 untested; H3 (teammate inheriting the lead's
  blocking Stop hooks) is the one that would generalise past this team.
- **2026-08-03 (same day, later)** — investigated. H3 **refuted** as a hang cause, H2 refuted as
  stated, D2 confirmed as the proximate cause of 294/295, and a fourth defect found that dominates
  all of them: spawn-time read from a registry that never contains teammates, so reap-guard's
  birth-grace gate could never open (83 % of all defers; 9 days of zero reaps). **Fixed + landed +
  content-verified: `ba6fb12f`.** The H3 *symptom* traced to a 9-commit-stale live symlink layer,
  blocked by a persistently-red postland verifier and a diverged `main` — surfaced to the operator,
  not driven (it is neither in this diff nor safely self-healable: the unstick is a `reset --hard`
  on a shared checkout). Panes 294/295 reaped and **pid-verified** dead with a positive control.
  Residue above.

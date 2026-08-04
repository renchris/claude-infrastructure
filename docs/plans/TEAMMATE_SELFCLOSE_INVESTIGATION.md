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

---

## REOPENED 2026-08-03 (evening) — the outcome metric had never moved, and nobody was reading it

The operator reopened this: *"we've attempted a few times to resolve this, and considered this
resolved, over the past few days, but evidently it is not."* They are right, and the reason every
prior pass looked complete is that each one measured a **mechanism** and none measured the
**outcome**.

### The outcome metric, stated once so it cannot be argued with

`~/.claude/logs/teammate-lifecycle.log`, `✓ closed pane` lines per day:

```text
2026-07-21   28        2026-07-24   17
2026-07-22   23        2026-07-25   37   ← last one at 15:45:49
2026-07-23   26        2026-07-26 … 2026-08-03   0
```

**680 automatic closes all-time; 0 since 2026-07-25 15:45:49.** The log writer is NOT dead — it
wrote 193 lines today. The closer is.

### The discontinuity is a single commit, and it is twelve minutes wide

```text
[2026-07-25 15:45:49]   ✓ closed pane 3190E3C1-… (r8-async-net)          ← the last close, ever
[2026-07-25 15:58:01] defer r4-runtime-profile (1/3): WORKTREE unresolved —
                        no safety gate could run, refusing ungated close  ← the first refusal
```

That refusal string is introduced by **`f9f2ed06` (2026-07-24 16:31) — "fail-closed on unresolved
worktree + operator-adoption hold"**. Its own commit message states the pre-existing condition
exactly:

> *"Every safety gate (busy-marker, dirty-defer, reap-guard, checkpoint) is conditioned on
> `-n "$WORKTREE"` — when worktree resolution misses, ALL of them no-op and the close proceeds
> **ungated** with no checkpoint."*

### The finding that reframes every prior pass: worktree resolution was ALREADY broken

The pre-cliff log proves it. A successful close in the working era reads, in full:

```text
Auto-shutdown idle teammate: r8-async-net (team: session-a3f68174)
  PPID-forensic: $PPID=93203 cmd=[… --agent-name r8-async-net …] pane=[3190E3C1-…]
  ✓ closed pane 3190E3C1-… (r8-async-net)
```

**No gate line at all.** Across 2026-07-20 → 07-25, the word `worktree` appears in **3 of 635**
lines. The 680 historical closes were not gated closes that later regressed — they were
**ungated closes**, produced by the very fail-open no-op `f9f2ed06` was written to forbid.

So the causal chain is:

1. Teammate worktree resolution has **never worked** on this box.
2. Until 2026-07-24 that defect was **masked** by fail-open: unresolved ⇒ every gate no-ops ⇒
   close proceeds. The system looked perfect and closed 680 panes.
3. `f9f2ed06` correctly converted fail-open to fail-closed. It did not introduce a bug; it
   **removed the mask**, and the pre-existing resolution defect became a 100 % refusal that day.
4. Nobody fixed resolution. **`f9f2ed06` is therefore not the thing to revert** — reverting it
   restores silent ungated closes, i.e. it re-hides the defect and re-arms the data-loss risk the
   commit exists to prevent.

### Why four subsequent fixes each looked correct and moved nothing

Every defer reason since the cliff, censused:

| n | Reason | Attacked by |
|---|---|---|
| 203 | `dirty tree` | `78f89d73` (per-file attribution) |
| 128 | `WORKTREE unresolved — no safety gate could run, refusing ungated close` | *nothing* |
| 112 | `reap-guard DEFER on a SHARED cwd — gates evaluated the wrong tree` | `1cd4e23b`, `ac15bf8d` |

All three are the same question — *"is this member's tree clean?"* — and it is **unanswerable**,
because the member has no resolvable tree of its own. Each fix correctly cleared one reason and the
next reason took over, so the log kept changing while the outcome stayed at zero. `ba6fb12f`
(birth-grace) is the clearest case: it genuinely worked — defers now advance *past* birth-grace —
and it bought exactly nothing, because they die one gate later.

**The generalisable lesson:** *a fix verified against the reason it was written for, in a chain of
fail-closed gates over one unanswerable question, cannot be distinguished from no fix at all. Only
the terminal outcome distinguishes them.* Nothing on this box watched `✓ closed pane`, so nine days
of total failure passed unremarked — and each pass could honestly report the defect it had named
was gone.

### What this makes the actual fix

Not another gate repair. Either:

- **give the member a resolvable tree of its own** (per-member cwd at spawn — backlog item #140,
  still open, and the SURFACE message itself now prescribes it verbatim: *"Fix at spawn (give the
  member its own cwd)"*); or
- **stop conditioning the close on a tree question the member cannot answer** — gate on what IS
  attributable (the member's own transcript writes, which `hooks/lib/session-writes.sh` already
  resolves) and let an unresolvable tree be a *checkpoint-then-close*, not a permanent refusal.

Plus, independently of which: **an outcome-level alarm.** "Zero `✓ closed pane` in N days while
TeammateIdle events are still arriving" is a one-line check that would have refuted all four
premature victories on the day each was declared.

### Status log

- **2026-08-03 (evening)** — reopened by the operator. Outcome metric established (0 closes in 9
  days, 680 before). Cliff pinned to a 12-minute window on 2026-07-25 and attributed to `f9f2ed06`
  un-masking a pre-existing worktree-resolution defect. Defer-reason census taken. Eight-agent
  research wave dispatched on the remaining axes (reap-guard reachability · cwd-at-spawn truth ·
  kitty actuator under a daemon PATH · subagent-vs-teammate close shapes · never-reap backstop
  policy · prose-vs-protocol base rate · fix archaeology · baseline-blind derivation). Findings
  integrate below as they land.

---

## The eight-axis wave — findings, and two corrections to the section above

Eight read-only agents, disjoint axes, dispatched 2026-08-03 evening. Two of them refuted parts of
my own framing above; those corrections lead, because a wrong premise left standing is how this
class survived four fixes.

### CORRECTION 1 — the shared cwd is TRUTHFUL, and it is NOT the 2026-07-25 regression

I wrote above that "the member has no resolvable tree of its own", and the live `⚑ SURFACE` string
says *"this member records the lead's cwd… Fix at spawn (give the member its own cwd)"*. **The
record is truthful and the prescription is a hardcoded misdiagnosis.**

`.members[].cwd` is written exclusively by `claude.exe` (our repo has zero writers, six readers),
at join, from the lead's cwd — `handleSpawnInProcess` and `resumeInProcessTeammate` both hardcode
`cwd: xt()`. The teammate really does run there. Proven three ways: `lsof` on 10 live teammate pids
across 2 teams (every REAL_CWD identical to its config value and to its lead's), the members' own
transcripts, and the configs themselves.

And the decisive fact: **shared cwd has been 100% invariant since 2026-04-06, and the last
successful reaps on 2026-07-25 happened on a team whose cwd was 100% shared.** A constant cannot
explain a step change. Backlog #140 ("teammates inherit the lead's cwd… so no per-member gate can
read their real tree") is therefore half right — the gates ARE ownership-blind — and wrong about
the remedy: there is nothing to correct at spawn.

### CORRECTION 2 — D2 is not teammates answering sloppily. The protocol accepts 3.2%.

The earlier reading was that two teammates replied in prose where JSON was required. Read from the
binary and measured over **188 unique `shutdown_request` deliveries** (2026-07-10 → 08-03, 49 teams,
CC 2.1.183–2.1.220), classified on the *tool_result* rather than the tool_use:

| Terminal outcome | N | % |
|---|---|---:|
| PROSE reply only | 85 | 45.2 |
| NO_REPLY (no assistant turn at all) | 48 | 25.5 |
| **STRUCTURED_REJECTED — emitted the artifact, the tool refused it** | **48** | **25.5** |
| **ACCEPTED (process actually exited)** | **6** | **3.2** |
| plain text via SendMessage | 1 | 0.5 |

**On 2.1.220: 0 accepted out of 58.** A quarter of teammates did exactly what the contract asks and
were refused anyway, so "state the JSON in the brief" (F3b) could at best move 45% into a bucket
that already fails 25% of the time. Exactly one code path ends a teammate process — `oJ_`, the
`approve:true` handler — and in interactive mode it has **no timeout and no auto-approve**; the only
deadline in the binary is on the headless `-p` path. Also, background subagents are *structurally
barred* from the protocol: *"Structured team-protocol messages … cannot be sent by a background
subagent."*

### The chain, end to end — every link measured

A finished agent's pane disappears only if ALL of these hold. Since 2026-07-25, at least two have
been false at all times.

| # | Link | State | Evidence |
|---|---|---|---|
| 0 | The process exits on its own | **NEVER TRUE, by design** | A named agent is a full interactive REPL. `kitty @ get-text` on a "finished" pane shows `✻ Crunched for 1m 20s` then `❯` — an empty prompt, ~105 min idle. 4/4 of that team identical. Nothing self-closes; every close is externally actuated |
| 1 | A gate chain decides to close | **FALSE for ~82% of members** | Fail-closed since `f9f2ed06`; 203 dirty-tree · 128 WORKTREE-unresolved · 112 shared-cwd |
| 2 | The decision reaches an actuator | rarely | 6 reaps in 9 days |
| 3 | **The actuator reaches the terminal** | **FALSE, 3 of 3** | The kitty ancestry defect — below |
| 4 | The outcome is measured | **FALSE until today** | Nothing read `✓ closed pane` |

### Link 3 — the kitty defect the operator actually asked about

Every close that survived every gate since the kitty migration still failed: lc-accounts + lc-shell
(08-01 13:15), photo-score (08-03 10:46), all `rc=1 There was a problem connecting to iTerm2` —
**and iTerm2 is not running on this box.**

`bin/it2` picks its backend via `bin/cc-in-kitty`, which walks `$PPID` to `$KITTY_PID`. The close
runs in a detached subshell (`:1046` `) &`, `:1048` `exit 0`), so it is reparented to launchd and
that walk reaches pid 1 without meeting kitty — "DEFINITIVE no" — and `it2` routes to iTerm2.
**Env survives reparenting; lineage does not.** `KITTY_WINDOW_ID`/`KITTY_PID` are still intact in
the orphan's environment and `cc-in-kitty` is right to distrust them; the check is correct and is
being asked in the one context where it must answer wrongly. Reproduced deterministically:
attached ⇒ rc 0 *"kitty[613] is an ancestor"*; double-forked to ppid 1 ⇒ rc 1 *"INHERITED, not
ours"*; with `CC_TERM=kitty` ⇒ rc 0.

`scripts/handoff-fire.sh:715-731` diagnosed and fixed this for its own detached watcher on
2026-08-01 and the remedy was never generalised — before this session `grep -rn 'CC_TERM=' bin
hooks scripts` returned two setter lines, both inside that one function. **Fixed: `da8490f5`.**

Blast radius beyond the fix: `cc-teardown` via `lead-crash-watchdog`, and `cc-reaper sweep --reap`,
run at ppid 1 from launchd and misroute identically — and they have no attached moment to capture a
verdict from, so they need a different remedy (see Residue).

### Link 1 — why F1 (`78f89d73`) is live, ran, and cannot bind

The refusing line is **`scripts/reap-guard.sh:118`** — a whole-tree `git status --porcelain` in a
**separate process**. F1's entire effect is `TREE_DIRTY=false`, a hook-local bash variable consumed
at `:692`, one gate earlier. reap-guard is exec'd at `:760` with a four-flag CLI
(`--worktree --spawn-time --member --grace-s --session-id`) and **no flag through which attribution
could be passed**; it re-derives dirtiness from scratch on the same shared tree F1 just exonerated
the member for. The hook branches on `if !` — any non-zero — so it cannot distinguish DEFER (10)
from `die` (2) and never reads `reason_kind`.

Reason census, 432 decision records: `grace-held` 355 · `no-products` 36 · `operator-adopted` 19 ·
`dirty-tree` 16 (**first appears 2026-08-03** — `ba6fb12f` moved the wall, it did not remove it) ·
`finished` 6. Three of the four tree-keyed gates (busy-marker, dirty-tree, no-products) are
properties of `$wt`, not of the member. `no-products` asks `git log -1 > spawn` — on a shared tree
that is answered by **the lead's commits**, so it clears and blocks accidentally, uncorrelated with
the member either way.

### Why every fix looked correct — the verification defects, named

- **Population gap.** Every close-asserting test uses an OWNED/synthetic worktree
  (`tests/teammate-auto-shutdown.bats:124,202,218,233,375,413,443`). Live: **31/38 members (82%)
  across 13 team configs share a cwd**. No test builds the real shape; suite 30/30 green while the
  real population had no close path at all.
- **The symptom is pinned, then cited as evidence.** `:531` and `:543` assert
  `[ ! -s "$D/it2-calls.log" ]` — *the pane must NOT close on a shared cwd* — and the earlier H2
  verdict in this very document cites `:92`/`:521` to refute the hypothesis that this is the bug.
  Circular.
- **The outcome is stubbed out of existence.** All four F1 tests use `recording_guard`, a stub whose
  body is `echo "$*" >> guard-argv.log; exit 10` — **it replaces the exact component that undoes
  F1**, and every assertion is on a log string emitted before `:760`. No F1 test runs the real
  `scripts/reap-guard.sh`.
- **An exact-count change-detector.** `tests/reap-guard.bats:19-24` asserts `[ "$n_ok" -eq 8 ]`, so
  adding any ownership-aware selftest assertion turns that test red on its own.
- **Two self-admitted vacuous tests**, in the commit bodies of `f0e1d619` and `bbe7ebbb`.
- **`git archive`-vs-pristine + controls-on-both-trees was used correctly throughout.** The
  verification craft is good; it was aimed one layer too low.

### The alarm nobody read — and where the new one went instead

`⚑ SURFACE` fired **156 times** and was read **zero** times. It pages via `_page_desk` →
`cc-notify --role desk` → `~/.claude/cc-roles/desk`, and that role was repointed on **2026-07-26
16:32**; nothing has drained the new box since (51 SURFACE unread in one, 43 in another with **no
`.seen` file at all**). Corroborated independently: `~ pane … already gone`, the trace any
out-of-band close leaves, ran 1–17/day through 07-25 and is **0 every day since**. 156 pages → 0
manual closes. So the new outcome alarm was wired into **`cc-blockers`** (`d5964cee`), which is
pull-rendered from disk truth at close time and needs no live consumer.

Also measured: **208 of 297 defer counters (70%) are frozen mid-ladder**, 86% of them because the
`TeammateIdle` supply stopped; and `cc-reaper` has reaped **0 since 07-31** because its
`finished-teammate` class needs a spawner `cc-fired` stamp and **nothing stamps a teammate**.

### Second-order damage this was causing meanwhile

`close_and_log` wrote the teardown marker **before** the close, on the stated premise that "the
close is inevitable" — false since 08-01. Every failed close left a marker asserting *"this session
was closed on purpose"* on a **live** session, so `lead-crash-watchdog` would classify a later
genuine crash of that teammate as an intentional teardown, one corrupt record per retry. Fixed in
`da8490f5`: `✓` now requires verified pane ABSENCE, and a close that provably did not happen
retracts its own marker.

### Residue — open, named, not absorbed

1. **`reap-guard` cannot receive attribution.** It needs an ownership-aware input (a `--dirty-mine`
   flag, or moving the decision into the hook) and `:760` must stop folding rc 2 into rc 10. Its
   tests pin the current behaviour, including the exact-count detector — expect them to go red, and
   that is the fix working.
2. **Detached daemons still misroute.** `cc-teardown` (via `lead-crash-watchdog`) and `cc-reaper`
   run at ppid 1 with no attached moment; they need a durable terminal verdict, not a captured one.
3. **The vendor shutdown protocol accepts 3.2%** (0/58 on 2.1.220). Not ours to fix; the idle-reap
   path is the only backstop, which is why links 1 and 3 matter.
4. **Sticky defer counters.** No observed reset-on-clean, so members already at cap may not drain
   even after a perfect fix — the existing orphan population probably needs an explicit sweep.
5. **`session-continue.sh mechanical_arm()` has no assignee exemption** (`:487-575`, landed
   `832e286c`). The wake-floor abstain at `:377-382` was not carried over. H3 was refuted as a
   per-member discriminator but a **common-mode** hold would be invisible to that test — unresolved.
6. **Nothing stamps a teammate `cc-fired`**, so `cc-reaper`'s finished-teammate class is unreachable.

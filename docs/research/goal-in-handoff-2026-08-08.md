---
status: closed
---

# Why fired `/handoff` sessions stopped carrying a `/goal`, and the two-message methodology

**2026-08-08.** Answers the operator's three-part question (`docs/plans/GOAL_IN_HANDOFF_METHODOLOGY.md`).
Everything below is measured — against the CC 2.1.220 binary, the 1,901-transcript corpus, and four
live fired panes. Where a claim is derived rather than observed it says so.

---

## The answer, in three lines

1. **We stopped them deliberately, eight days ago, and never built the replacement.** On 2026-07-31
   `check_slash_head` was universalized to refuse ANY slash-headed payload. Goal-carrying fires fell
   from **20.0% to 3.0%**. No producer ever set the documented escape — **zero real invocations of
   `FIRE_ALLOW_SLASH_HEAD=1` exist in the entire transcript corpus.**
2. **Yes, both can be separate submitted messages, and now they are.** `handoff-fire.sh --goal
   "<condition>"` sends the brief as message 1 and pastes `/goal <condition>` as message 2 once
   engagement is proven. Landed, tested, and verified end-to-end in a real fired pane.
3. **The 4000-char cap was never the interesting constraint.** It binds the goal CONDITION, and the
   condition should be a pointer anyway. Message 1 carries the brief and has no cap at all.

---

## 1 · Root cause

### 1.1 The guard, and what it actually costs

`scripts/handoff-fire.sh` `check_slash_head()` returns 1 — a loud, telemetered refusal — when a
payload's first non-blank line is any slash command. Bypassed only by `FIRE_ALLOW_SLASH_HEAD=1`.
Universalized 2026-07-31 in `774e3ef1` (item `c89b9c7b1526`); before that only an over-cap `/goal`
refused and every other slash head merely warned.

**F1 CONFIRMED, and quantified.** Sessions whose transcript carries a `handoff-fire` engagement or
recycle marker are provably fired; sessions carrying a `goal_status` sentinel attachment provably had
a goal set. Both are parsed, not grepped, and deduplicated by session id across the five account
config dirs:

| | provably-fired sessions | carried a goal | rate |
|---|---|---|---|
| before 2026-07-31 | 70 | 14 | **20.0%** |
| on/after 2026-07-31 | 67 | 2 | **3.0%** |

The two survivors are explicable and neither is a counter-example: `fdb33b93` (2026-08-08) was a
`--recycle` whose payload was `/goal`-headed, and `96dd7ffb` (2026-08-07) had its goal set by a later
typed message. The ledger shows **zero** `payload-slash-head` refusals from real fires — every one in
`~/.claude/logs/handoffs.jsonl` is a bats fixture (`GOAL_MAX_CHARS=20`). So the guard is not even
being *hit*: producers simply stopped writing `/goal` at all, which is the more complete kind of
disappearance.

### 1.2 The guard's premise is half true, and the half that is false is the shape we wanted

`check_slash_head`'s refusal text says the harness "parses the WHOLE submission as that command, so
the body is consumed as its argument (or rejected for length) and the fired pane would idle
TASK-LESS." Measured:

- **Over-cap `/goal` → task-less. TRUE.** Live: pasting `/goal ` + 4100 chars replies
  `Goal condition is limited to 4000 characters (got 4100)`, starts no turn, and sets nothing.
- **In-cap `/goal` → NOT task-less. FALSE.** Setting a goal returns a *query* whose prompt is
  `` `A session-scoped Stop hook is now active with condition: "<cond>". Briefly acknowledge the goal,
  then immediately start (or continue) working toward it — treat the condition itself as your
  directive…` `` — so the argument **is** delivered as work, verbatim. Observed both in the binary and
  as a live `isMeta` record in probe `ad6d8d16`.

So the guard over-refuses on exactly one shape: the ≤4000 `/goal`, which is the one the operator
wants. **The fix is not to admit that shape.** A `/goal`-headed payload is capped at 4000 chars and a
real brief is not; admitting it would trade a task-less pane for a truncated one. The fix is to stop
needing one message to be two things — §3.

### 1.3 The spec was describing a mechanism that does not exist

**F2 CONFIRMED, and it is worse than the plan supposed.** `commands/handoff.md` classed `/goal` as
"any SKILL-BACKED slash command — never built-ins like `/clear`/`/model`, which only the TUI parses",
and then asserted: *"The CLI does not parse slash commands out of the initial prompt — the receiving
model dispatches a LEADING user-typed `/x` via its Skill tool."* Both are false:

- There is no `goal.md` in `~/.claude/commands/` (19 files), in `~/.claude-next/commands/` (20), or
  anywhere else; no skill provides it. `/goal` is a **harness built-in** — two command records in the
  CC 2.1.220 binary: `{type:"local-jsx",name:"goal",…}` for the TUI and
  `{type:"local",name:"goal",supportsNonInteractive:true,thinClientDispatch:"post-text",…}`.
- The CLI parses it out of the initial prompt **itself**. Fired session `fdb33b93`'s transcript
  carries the `goal_status` attachment at record 15 and the `<command-name>/goal</command-name>` user
  message at record 17 — both *before* the first model turn. No model, no Skill tool.

This is the `spec-named-mechanism-may-be-prose-only` pattern: the spec's own argument for why a
leading `/x` works described a dispatch path that never ran. Corrected in `6cc14dd0`, in the same
diff as the finding, because the spec is what future sessions read.

---

## 2 · What `/goal` is, mechanically

From the binary (`Xdr`/`Qdr`/`Pwo`/`Ydr` in CC 2.1.220) and confirmed live:

| Property | Value |
|---|---|
| Kind | Harness built-in, TUI + non-interactive variants |
| Effect | Registers a **session-scoped Stop hook** of `{type:"prompt", prompt:<condition>}` and sets `activeGoal` |
| Side effect | Returns a **query** that re-injects the whole condition as the model's directive |
| Cap | **4000 chars on the CONDITION** (`Ydr=4000`), i.e. on the command's whole argument |
| Over-cap | Text-only reply; nothing set; the pre-existing goal, if any, survives |
| Gates | Trusted workspace; refuses under `disableAllHooks` / `allowManagedHooksOnly` |
| Clear | `/goal clear|stop|off|reset|none|cancel`; auto-clears when the Stop hook judges the condition met |
| Lifetime | **Dies with the session** |
| Disk trace | `{"attachment":{"type":"goal_status","met":false,"sentinel":true,"condition":…}}` in the session transcript — the read-back oracle |

---

## 3 · The methodology: two messages, never one

**The operator's third question was the load-bearing one and the answer is yes.**

```
message 1 — the comprehensive brief. Plain-text-headed. NO character cap.
            Delivered exactly as every fire already delivers it. Unchanged.
message 2 — /goal <one-line condition>. Bracketed-pasted into the pane AFTER
            engagement is proven. Capped at 4000, and should be a pointer anyway.
```

Why this is the right decomposition rather than a workaround: the two messages have *different*
jobs and different constraints. The brief is long, structural, and read once; the goal is a
persistent Stop-hook predicate that must stay short enough to re-evaluate cheaply on every stop.
Forcing them into one submission is what created both failure modes — the 4000-char truncation and
the task-less pane. Separating them removes the cap from the brief entirely.

**Write the condition as a pointer:**
`--goal '<one-line objective> — full brief in the prompt above; DoD at <path>'`.
The detail already arrived in message 1; the goal only has to be a predicate a Stop hook can judge.

### 3.1 Ordering

Message 2 must land in a **running CC session**, never a shell. That ordering was already proven and
already instrumented: the fire path verifies engagement (P0-11) — a real assistant turn in the fired
session's transcript — before it reports success. `--goal` hangs off that existing proof and adds no
new liveness assumption.

### 3.2 Fail-closed, in the direction that matters

| Failure | Result |
|---|---|
| Condition malformed (multi-line / slash-headed / over-cap) | Refused **pre-fire**, distinct `payload-goal-arm-*` reason, nothing fires |
| Pane is not provably a live CC composer | `it2_paste_submit` **abstains** — no paste, no CR |
| Paste sent, goal never appears on disk | `verdict=unverified`, loud; never called "armed" |
| Any of the above | **The fire still succeeds.** Message 1 landed and engaged; the session has its brief and is working |

The inverse — a goal with no brief — is impossible by construction, because the goal is never the
carrier of the brief.

### 3.3 Read back, never claimed

A paste that returns 0 is not a goal that was set (`claimed-outcome-vs-checked-outcome`).
`goal_armed_for_pane` resolves pane → session id → transcript and looks for the **harness's own**
`goal_status` attachment, matched on the condition. It is deliberately `jq`-only: a `grep -F` for the
condition also matches the *pasted user message*, which is present whether or not the command was
accepted — i.e. exactly the failure the oracle exists to catch. Pinned by
`tests/handoff-goal-arm.bats` with a positive control showing the substring oracle would pass.

Every outcome prints `goal-arm verdict=set|unverified|abstained` and writes a `class:"goal-arm"` row
to `~/.claude/logs/handoffs.jsonl` — its own emitter, because `emit_fire_event` writes
`engaged:false` on non-admit rows and a goal-arm row (written only *after* engagement was proven)
would deflate the V2 M-1 engagement rate by one row per armed goal.

### 3.4 A goal does not survive a recycle

Measured: recycling probe pane 809 produced session `e5f5a0eb` with **zero** `goal_status`, while the
predecessor's goal was never cleared — it simply died with its session. Since `--recycle` is the
commonest succession on this box, `--goal` re-arms on the recycle path too (the watcher takes the
condition as a trailing positional, so an older deployed watcher just ignores it).

---

## 4 · The probes

All in real fired panes, per the plan's constraint 3. The box was at 2.0–2.6 load/core throughout, so
each fire used the capacity gate's own named single-fire override (`CC_FIRE_CAPACITY_GATE=off`) and
the pane was retired immediately.

| # | Question | Method | Result |
|---|---|---|---|
| P1 | Does a **bracketed-pasted** `/goal` parse in a RUNNING session? | Fire plain-text brief → confirm live composer → `ESC[200~ /goal … ESC[201~` + `\r` | **YES.** `Goal set: …`, `◎ /goal active`, `goal_status` on disk, and the directive re-injected as an `isMeta` turn |
| P2 | Over-cap `/goal` into a running session | paste `/goal ` + 4100 chars | `Goal condition is limited to 4000 characters (got 4100)`; no turn started; prior goal survived |
| P3 | Does a goal survive `--recycle`? | recycle pane 809 | **NO.** Successor `e5f5a0eb`: zero `goal_status` |
| P4 | Does the landed `--goal` work end to end? | fire with `--goal` | first run `verdict=unverified` (see below); after the fix, **`goal ARMED + VERIFIED on pane 815 … verdict=set`**, corroborated on disk and in the pane |

Disk-corpus corroboration for P1 (the typed case, which needed no new fire): **51 sessions** in the
corpus set a goal as a *later* typed message, at typed-turn 2 through 133. The probe closes the one
gap that corpus could not — typed vs **pasted** — which was the crux.

### 4.1 The probe earned its mandate

P4's first run returned `verdict=unverified` for a goal that was **demonstrably set** — the
attachment was on disk with the exact condition. All 18 unit tests were green. The defect: the oracle
looked for `$CC_PROJECTS_DIRS_entry/<sid>.jsonl`, but CC nests transcripts one level down, in a
per-cwd project dir. The fixture wrote to the root, so the test certified the wrong artifact
(`control-must-replay-the-real-artifact`). Fixture and lookup both corrected, plus a regression case
that asserts the file is *not* at the root and so goes red if anyone re-flattens the resolution.

Worth stating plainly: the guard behaved exactly as designed under its own defect — it said
*unverified*, not *armed*. Had it followed the paste's return code it would have reported success for
a fire whose goal it could not see, and the false-negative row would have been a false positive.
That row is still in the ledger, deliberately.

---

## 5 · What landed

| Commit | Change |
|---|---|
| `68b2e007` | `--goal` in `scripts/handoff-fire.sh` (pre-fire validation, `arm_goal` after engagement on both fire and recycle paths, read-back oracle, `goal-arm` ledger class) + `tests/handoff-goal-arm.bats` (18 cases) |
| `6cc14dd0` | `commands/handoff.md` — the built-in / initial-prompt-parsing / task-less claims corrected; the positional recipe replaced by `--goal` |

`check_slash_head` is **unchanged** (constraint 1), asserted by a test that goes red if a later change
admits a `/goal` head. Suites green this turn: `handoff-goal-arm` 18/18; `handoff-payload-gates`,
`fire-engagement`, `handoff-fire-capacity-gate`, `handoff-recycle-engagement`, `fire-autonomy`
125/125 combined. Lints green: `typed-send`, `pane-spawn-coverage`, `self-path`, `subshell-cleanup`,
`wait-contract`, `utc-stamp`, `unattended-path`, `bats-shellcheck`, `test-hermeticity`,
`test-walltime`.

**Usage:**

```
scripts/handoff-fire.sh --prompt-file /tmp/fire-<slug>.txt --worktree <branch> \
  --goal '<one-line objective> — full brief in the prompt above; DoD at <path>'
```

---

## 6 · Open

- **`recycle_engaged`'s second path looks dead for the same reason P4's oracle was.** It tests
  `[ -f "$pdir/$newsid.jsonl" ]` against the projects ROOT. Not exercised here and not this scope's
  to fix — the marker path is its primary oracle and covers the live case — but it is the same
  root-vs-nested confusion in a neighbouring function and should be checked. Filed.
- **Nothing re-arms a goal at `--recycle` unless the caller passes `--goal` again.** That is correct
  (the condition is the caller's to choose) but it means a long-horizon chain silently drops its goal
  at the first recycle that omits the flag. Whether the recycle path should *inherit* the
  predecessor's live condition is a design question, not a defect.

---

# ADDENDUM 2026-08-09 — a goal that was SET, VERIFIED, and then never EVALUATED

**This document proved a goal can be ARMED. It never asked whether an armed goal is EVALUATED.
Measured on 2026-08-09: it is not — at least not here.**

## The measurement

Session `d33abf12` (reso lead, pane `wt-cc-234834-28059-886`), goal armed by the operator typing
`/goal <1199-char condition>` at **07:13:38Z**. The harness wrote exactly **one** attachment:

```json
{"type":"goal_status","met":false,"sentinel":true,"condition":"Not done until every agent-side leg of the fly-iad …"}
```

From 07:13:38Z to 09:14:02Z — **~2 hours, ~12 assistant turns, several genuine idles** — the harness
wrote **ZERO further `goal_status` records** and **never once blocked a stop or forced a continuation**.
The goal also never auto-cleared: it still reads `met:false`, so this is not "the condition was judged
satisfied". It was armed, recorded once, and thereafter inert.

⚠️ **Methodology note that nearly produced the opposite conclusion.** `grep -c goal_status` returns
**6** on that transcript, which reads like repeated evaluation. Five are the assistant's own PROSE
discussing the goal. Only `type == "attachment"` records are the harness speaking:

```bash
python3 -c "
import json
for l in open('<transcript>.jsonl'):
    if 'goal_status' not in l: continue
    d=json.loads(l)
    if d.get('type')=='attachment': print(d['timestamp'], d['attachment'].get('met'))"
```

**Grepping a token that appears in your own discussion of a mechanism measures you talking about it.**

## Ruled OUT, with evidence — do not re-derive these

| Hypothesis | Verdict |
| --- | --- |
| claude-infrastructure interfered (that night's `2df6188e` landed cc-await-ping / cc-notify / self-close changes) | **REFUTED** — `git show --stat 2df6188e` touches **no Stop hook** |
| An operator Stop hook shadows or swallows the goal check | **REFUTED** — 11 Stop hooks are registered and **none is a goal hook**; `/goal` is a BINARY BUILT-IN (§2 of this doc), so its evaluation is internal to CC and unreachable by any operator hook |
| The goal auto-cleared because it was met | **REFUTED** — the sole attachment still reads `met:false` |
| Stop hooks were not firing at all | **REFUTED** — `session-continue.sh` fired its WAKE-FLOOR block during the window, so Stop was reached and hooks ran |

## NOT established — this is the open question

**Why it stops evaluating.** The leading hypothesis is UNTESTED and must not be written up as fact:
nearly every turn in that window ended because the operator sent a message **mid-turn** (the STEERED
path — CC's type-asymmetric queue, §Autonomous-fire item 4 of `commands/handoff.md`), rather than the
model reaching a clean Stop. The evaluator may only run on the latter. The one confirmed clean Stop
had a *different* hook return a blocking decision first, and no goal evaluation was recorded near it.

**Two variables this doc has never controlled for, and the second is new:**

1. **`sentinel: true`.** Every other field is self-explanatory; this one is not. Is a `sentinel`
   record an ARMED marker rather than a live goal? Nothing here or in `commands/handoff.md` says.
2. 🚨 **THE TERMINAL. This box runs KITTY, not iTerm2.** `$KITTY_WINDOW_ID` is set; `$ITERM_SESSION_ID`
   is a kitty-shimmed `w0t0p0:<n>`. The entire handoff/goal apparatus is iTerm2-shaped — `it2-kitty`,
   `cc-kitty-socket`, `kitty-split-launch.sh`, `it2-wrapper` exist precisely because it had to be
   retrofitted — and **kitty has already produced two silent goal/back-channel-adjacent failures**:
   a bare-integer pane id that `payload-lint` accepted and `cc-notify` could not resolve
   (`55c18e2b`), and `--recycle`'s pane probe typing into a live composer
   (`reference-recycle-probe-types-into-live-composer`). A terminal-shaped cause is PLAUSIBLE and
   has never been tested for `/goal`. **It is also falsifiable in one run:** arm an identical goal in
   an iTerm2 pane and count attachments over the same interval.

## The operational rule, which holds whatever the mechanism turns out to be

**`goal-arm verdict=set` proves a goal was SET. It is not evidence the goal is LIVE.** Verify by
counting `goal_status` attachments OVER TIME, never by the arm-time verdict — and never let an armed
goal substitute for the agent's own completion discipline. Same class as the inert-export defect
(`reference-exported-but-uncalled-passes-every-gate`): a thing that reports success at installation
and then does nothing. Assert the BEHAVIOUR, not the installation.

Filed: `11c25d8f7c55`.

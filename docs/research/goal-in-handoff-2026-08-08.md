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

---

# RESOLVED 2026-08-09 — the goal hook is REMOVED at every Stop, by CC, because a background Bash is running

**The mechanism is not kitty, not hook shadowing, and not the steered-stop path. All three are
refuted below with the binary's own code.** `/goal` evaluation is gated on the task registry being
QUIET, and this box's standing operating procedure — `cc-await-ping --timeout 14400` armed as a
background Bash so peer mail is not missed — holds a `local_bash` task open for **four hours**. For
as long as that watcher lives, CC deletes the goal's Stop hook before the Stop runner can see it,
then silently puts it back.

## The code, read out of the binary

`claude.exe` 2.1.220 (`~/.claude-220/…/bin/claude.exe`, the binary `ps -o command= -p $PPID` names
as the running process). Same technique as §2 — read the bundled JS out of the compiled Bun
executable. Offsets are for this build and will move.

**The arm path** (`Xdr`, @232982): registers the goal as a session-scoped **prompt-type** Stop hook
and appends the marker attachment:

```js
t.sessionHooksRegistry.add(n,"Stop","",{type:"prompt",prompt:e});
t.setAppState((i)=>({...i,activeGoal:{condition:e,iterations:0,setAt:Date.now(),…}}));
t.applyMessageOp({type:"append",messages:[kld(!1,e)]});
```

**The deferral** (@233098, first statements of the Stop handler, before the runner is called):

```js
let D=A.activeGoal;
if(D){
  let B=i.taskRegistry.all();
  if(_We(B)||Tio(B)){                                    // ← the gate
    if(y=Jdr(A,kt()).find((j)=>j.prompt===D.condition), y)
      i.sessionHooksRegistry.remove(kt(),"Stop",y),
      w("[goal] evaluation deferred — background work still running")
  }
}
…
finally{ if(y) i.sessionHooksRegistry.add(kt(),"Stop","",y); … }   // ← puts it back
```

and the two predicates (@229209):

```js
function Tio(e){for(let t of Object.values(e)) if(t.type==="local_bash" && !CT(t.status)) return !0; return !1}
function _We(e){for(let t of Object.values(e)) if(a1g.has(t.type) && !CT(t.status) && … ) return !0; return !1}
function CT(e){return e==="completed"||e==="failed"||e==="killed"}
a1g = new Set(["local_agent","remote_agent","in_process_teammate","local_workflow"])
```

**`Tio` is the one that fires here: any `local_bash` task not yet `completed`/`failed`/`killed`.**
A background Bash *is* a `local_bash` task. `cc-await-ping --timeout 14400` blocks for up to four
hours by design, so it is non-terminal for four hours, so `Tio` is `true` at every Stop in that
span.

## Why every prior hypothesis was looking in the wrong place

The `finally` block re-adds the hook. **The registry is therefore correct whenever anyone inspects
it** — before the Stop and after the Stop. It is wrong only during the Stop, which is the only
moment that matters and the only moment nothing can observe. That is why "11 Stop hooks registered,
none is a goal hook" (§ Ruled OUT) read as evidence of a healthy registry: the goal hook genuinely
is in the registry, as a `type:"prompt"` entry with `matcher:""` — `Jdr` is the accessor that finds
it — and it is genuinely absent at Stop time.

## The measurement, re-read against the mechanism

Session `d33abf12`, goal armed 07:13:38Z. Background Bash launches in that transcript
(`tool_use` with `run_in_background:true`):

| Time (Z) | Command |
| --- | --- |
| 07:00:58 | `cc-await-ping --timeout 14400 --interval 15` |
| 07:01:40 | `cc-await-ping --timeout 14400 --interval 15` |
| **07:13:38** | **← goal armed here** |
| 07:20:26 | `cc-await-ping --timeout 14400 --interval 15` |
| 07:44:43 | `cc-await-ping --timeout 14400 --interval 15` |
| 08:23:26 | `cc-await-ping --timeout 14400 --interval 15` |
| 08:52:01 | `cc-await-ping --timeout 14400 --interval 15` |
| 08:53:58 | `cc-await-ping --timeout 14400 --interval 15` |
| 08:58:31 | `cc-await-ping --timeout 14400 --interval 15` |

A four-hour watcher was already running when the goal was armed, and seven more were armed across
the window. **There is no Stop in 07:13:38Z → 09:14:02Z at which `Tio` was false.** Zero evaluations
is the exactly-predicted output, not an anomaly.

This also explains the two facts that made the original finding look paradoxical:

- **"Never blocked a stop."** Blocking is what the *evaluator* does on `ok:false`. The evaluator
  never ran.
- **"Never auto-cleared."** Clearing happens on `ok:true` in the same handler. Also never ran. The
  sole attachment keeps reading `met:false` forever because nothing ever writes a second one.

## `sentinel: true` — answered, and it is the tell

Undocumented anywhere in the repo, and defined at @232982:

```js
function kld(e,t){return {type:"attachment",…,attachment:{type:"goal_status",met:e,sentinel:!0,condition:t}}}
```

`kld(false, cond)` is appended by the **arm** path; `kld(true, cond)` by the **clear** path (`Qdr`).
**`sentinel:true` means "this record is a marker for the UI, not an evaluation."** CC's own readback
helper refuses to treat sentinels as results:

```js
function Kks(e){ … if(!n.met||n.sentinel) continue; … }        // skips every sentinel
```

Evaluations are the records **without** the field — written at @233099/@233100 with `iterations`,
`durationMs`, `tokens`. So the shape of a healthy goal is: one `sentinel:true` at arm, then a
non-sentinel `met:false` per unmet Stop, then one non-sentinel `met:true` at success. **A transcript
holding exactly one record, and that record a sentinel, is the signature of a goal that was armed
and never once evaluated.** The original measurement had already captured the diagnostic field; what
was missing was the dictionary.

## The three refutations, with their evidence

| Hypothesis | Verdict | Evidence |
| --- | --- | --- |
| **Kitty, not iTerm2** (addendum's flagged variable 2) | **REFUTED** | The deferral reads `taskRegistry`, `activeGoal`, and `sessionHooksRegistry`. No terminal, pane id, TTY or `$TERM_PROGRAM` value is on the path. The two prior kitty failures were pane-id resolution; this path resolves no pane. |
| **A blocking shell Stop hook shadows the goal hook** (the updated leading hypothesis) | **REFUTED** | The dispatcher `uL` (@237793) maps every resolved hook to a concurrent async generator — `let H=_.map(async function*({hook:q,…},Y)=>{…})` — and the consumer `for await` loop in the Stop handler drains **all** yielded results, checking `B.blockingError`, `B.additionalContexts` and `B.preventContinuation` per result. `preventContinuation` sets a flag `v`; the `return` that honours it is **after** the loop. One hook blocking cannot suppress another hook's result. |
| **Only a clean Stop evaluates; steered mid-turn messages skip it** | **REFUTED as the cause** | Steering changes *when* Stop is reached, not whether the handler runs — and the handler is where the removal happens. It is upstream of any ordering question. |

The 11 operator shell hooks are bystanders. `session-continue.sh` firing its WAKE-FLOOR block inside
the window is consistent with, not contrary to, this mechanism: Stop was reached, the shell hooks
ran, and the goal hook was simply not in the list handed to the runner.

## Is CC wrong here?

**No — the deferral is deliberate and defensible.** Evaluating "is the objective met?" while a
subagent or a background command is still producing its result would judge on an incomplete
transcript, and each evaluation costs a real LLM call (`querySource:"hook_prompt"`, JSON-schema
output). Deferring until the work settles is the right default.

**What is wrong is the interaction with our own standing procedure.** `cc-await-ping --timeout
14400` is not a unit of work that settles; it is an idle watcher that is deliberately long-lived,
and we tell every session to arm one — the SessionStart and UserPromptSubmit hooks both emit
*"before you go idle, run this as a Bash tool call with run_in_background=true"*. CC's predicate
cannot distinguish *"work is in flight"* from *"a watcher is parked"*, because both are
`local_bash`, non-terminal. **We built a box on which `/goal` is structurally inert by default.**
The defect is ours, and it is in the procedure, not in the binary.

## The operational rule, restated now that the mechanism is known

The rule at the end of the previous section stands and gains a second clause:

1. **`goal-arm verdict=set` proves SET, never LIVE** — count non-sentinel `goal_status` attachments
   over time. (Unchanged.)
2. **A goal and a parked background watcher are mutually exclusive on this box.** Arming
   `cc-await-ping` disables the goal for as long as it lives, silently and with no log the operator
   sees. Any long-horizon mechanism that depends on `/goal` blocking a stop must not co-exist with a
   background watcher — or must not depend on `/goal` at all.

⚠️ **Do not "fix" this by dropping `cc-await-ping`.** It is load-bearing for peer mail; removing it
trades a silent goal failure for a silent comms failure. The compensating control below keeps both.

## The live A/B — this session was the experiment

The fire that produced this section armed a `/goal` on the investigating session, deliberately, so
the investigator carried an instance of the bug. It ran with **no background Bash at any point** —
the SessionStart hook's own banner recorded *"No inbox wake path armed"*. That makes it the positive
control, and the two sessions differ in exactly the variable under test:

| | `d33abf12` (the original finding) | `1d46d9c4` (this session) |
| --- | --- | --- |
| terminal | kitty | **kitty (identical)** |
| operator Stop hooks | the same 11 | **the same 11** |
| `cc-await-ping` background watcher | live across the whole window | **none, ever** |
| sentinel attachments | 1 | 1 |
| **evaluations** | **0 over ~2 h / ~12 turns** | **1, at the FIRST Stop, 8 min after arm** |

```
09:50:38Z  goal_status  met=false  sentinel=true            ← armed
09:58:56Z  hook_blocking_error  hookEvent=Stop              ← a SHELL Stop hook blocked
09:59:10Z  goal_status  met=true  sentinel=absent  iterations=1
           reason="The condition specified two deliverables: (a) establish the mechanism…"
```

Two things are settled by those three records:

1. **The evaluator works on this box, in kitty, unmodified.** It ran, judged, wrote a non-sentinel
   record with `iterations:1`, and auto-cleared — the full healthy shape the original session never
   produced a single instance of. Terminal-shaped causation is not merely unsupported by the code
   reading; it is contradicted by a live run.
2. **A blocking shell Stop hook does not shadow the goal hook — measured, not just read.** At
   `09:58:56Z` a shell hook returned a blocking decision, and **14 seconds later, at the same
   Stop**, the goal evaluated anyway. That is the updated leading hypothesis refuted by direct
   observation, independently of the `uL` code reading.

⚠️ **A fleet-wide census was attempted and is NOT offered as evidence.** Across 351 goal-arming
sessions, "a watcher was already live at arm" showed 69% zero-eval (n=13) against a 53% base rate
(n=338) — a difference far too weak to carry a claim, and confounded three ways: task *terminal
status* is not recorded in transcripts, so "a watcher was launched" is not "a watcher was running at
that Stop"; `_We` defers on subagents and teammates too, which the census did not model; and most
zero-eval sessions simply ended before any Stop occurred with a live goal. It is reported here so
the next reader does not re-run it expecting a result. **The code is the mechanism and the A/B is
the corroboration; the census is neither.**

---

# The compensating control — landed 2026-08-09

**The cause is inside the CC binary and the deferral is correct behaviour, so there is nothing of
ours to repair in the evaluation path.** What is ours is that the skip is *silent*. Two things
landed, and deliberately nothing else:

### 1 · `hooks/goal-inert-watch.sh` — make the skip loud (`8b0dac58`)

A Stop hook that reports, on the same Stop where the skip happens, that the armed goal is not being
evaluated and names the tasks holding it off. It is possible only because CC hands every Stop hook
the very population its own predicate scans — `YTe` @237761 spreads
`{background_tasks: cip(i.taskRegistry.all()), session_crons: uip()}` into the hook input.

Fires only when **all four** hold: a goal's arm marker is the most recent `goal_status` attachment
(armed and never evaluated) · ≥1 non-terminal background task of a deferring type · the payload is a
real Stop · not damped on the condition. **Delivery is `systemMessage` only** — never
`decision:"block"`, never `additionalContext` (which on 2.1.220 forces a turn and increments the
consecutive-block counter). It informs; it structurally cannot hold a session open, which bounds the
blast radius of a regression to one unwanted line.

Two traps it is built around, each of which yields a hook that is clean, green and **permanently
silent** — the failure mode that would make shipping it worse than not:

- **`background_tasks[].type` is the DISPLAY name.** `F$o` @237760745 maps `local_bash → "shell"`,
  `local_agent → "subagent"`, `local_workflow → "workflow"`, `in_process_teammate → "teammate"`,
  `remote_agent → "cloud session"`. A hook keyed on `local_bash` matches nothing and reports
  all-clear forever — the caller-census-keyed-on-path defect, caught before it shipped only because
  the map was read rather than assumed.
- **A bare `grep goal_status` matches the assistant's own prose** — 6 hits where the truth was 1 on
  the very transcript that produced this finding. Every read filters `type == "attachment"` first.

It **abstains on `teammate` and `cloud session`**: `_We` excludes `in_process_teammate && isIdle` and
`remote_agent && isLongRunning`, and `cip()` ships neither flag, so CC's predicate is not
reproducible for those two. Under-reporting is the correct direction for an alarm — a hook that
cried inert at a healthy goal would be trained around. `shell` alone covers `cc-await-ping`, the
entire observed cause.

`tests/goal-inert-watch.bats` — 14/14, including two mutation checks that each flip a positive test:
keying on the raw type name silences the fire case (M1), and removing the sentinel discrimination
makes it nag a goal that is evaluating perfectly (M2).

### 2 · `migrations/0005-…` — the registration, STAGED (`68e3d7b4`)

Declared `c10` because it edits `settings.json`; it is staged and never self-runs. It writes **every**
config dir carrying the sibling Stop hooks — `~/.claude/settings.json` and
`~/.claude-tertiary/settings.json` are separate real files, not symlinks into the checkout, and were
already divergent when measured, so registering one would leave every session launched against the
other blind. Exercised in a sandbox `$HOME`: registers both, second run is a clean no-op, verifies
the edit by content before replacing the live file, backs up first, leaves the file untouched on any
failure.

**Until an operator runs it, the sensor is inert** — which is the honest state, and exactly what the
`c10` class exists to represent.

### What was deliberately NOT built

- **No change to `session-continue.sh`.** It already blocks stops from a hook we own, is unaffected
  by CC's deferral, and is 703 lines running at every Stop across the whole box. It is the answer to
  *"a long-running session that does not stop early"* and it needed nothing; touching it to
  duplicate `/goal` semantics would put every session in every repo at risk to re-implement a
  feature that already exists one layer down.
- **No attempt to defeat the deferral.** It is CC's, it is correct, and routing around it would mean
  evaluating a goal against a transcript whose background work has not landed yet.

### The rule for anyone arming a goal on this box

> **A `/goal` and a parked background watcher are mutually exclusive.** If a session's completion
> genuinely depends on the goal blocking its stop, do not arm `cc-await-ping` in it. If it needs the
> watcher — nearly every fired peer session does — then use
> `~/.claude/hooks/session-continue.sh set "<the ONE next step>"`, which is ours, is unaffected, and
> was already the sanctioned actuator for the 🔧 state.
>
> *(2026-08-10: this rule is now ENFORCED and mostly obsolete — see § RESOLUTION below. The
> validate-bash chokepoint refuses the arm under a live goal, the nags stopped instructing it, and
> the birth watcher covers idle wake without entering the task registry.)*

---

# RESOLUTION DEPLOYED 2026-08-10 — /goal works out of the box; the conflict set was three-deep

**Operator directive (via `/goal`, 2026-08-10): sessions sat idle with an active `/goal` — resolve
the claude-infrastructure conflict and deploy live.** The compensating control above made the skip
LOUD; this pass removes the causes. Three distinct mechanisms were putting a goal-armed session
idle, and all three are ours to fix:

## R1 — the parked watcher (the § RESOLVED mechanism), now removed at every producer

The deferral itself is CC's and stays. What changed is that **nothing of ours creates the standing
deferrer any more**:

| Surface | Before | Now |
|---|---|---|
| `mailbox-drain.sh` nag (SessionStart / UserPromptSubmit) | instructed `cc-await-ping … run_in_background=true` unconditionally | **goal-aware**: with a LIVE goal it warns AGAINST arming and carries no arm command (`hooks/lib/goal-state.sh`, one shared predicate) |
| `session-continue.sh` WAKE FLOOR | **blocked the stop** and instructed the arm — the instruction-injector | fourth abstain state: a LIVE goal IS the wake path; stands down, spends no budget |
| the model's own habit (CLAUDE.md § Agent Teams recipe) | armed it anyway | **chokepoint deny** in `validate-bash.sh`: background `cc-await-ping` under a LIVE goal is refused with the mechanism + the goal-safe alternative in the reason (command-position match, so a bg `rg cc-await-ping` is untouched; fail-open on any read failure) |
| idle wake coverage | only the model-armed watcher | **migration 0007 registered**: `mailbox-wake-arm.sh` arms at birth as an asyncRewake hook — a hook-engine Promise, **not a task-registry entry** (read from the binary: `bip()` @237768400 tracks it in a module Set and wakes via a synthesized task-notification), so it wakes an idle session WITHOUT deferring the goal |

The goal-live predicate is `hooks/lib/goal-state.sh :: goal_live_condition` — last `goal_status`
ATTACHMENT with `met==false` and not `failed` (the § sentinel dictionary; prose-decoy filtered).

**0007 shipped with a new guard it turned out to need.** The 2.1.220 dispatch gate is
`(e.async || e.asyncRewake && K) && !d` with `K = isInteractive || hasStreamingInput`
(`_n`/`r2r` @225500254). In a one-shot `claude -p`, K is FALSE — the hook would run
**synchronously and block session birth for the full ~4 h watch**, for every headless probe and
daemon on the box. `mailbox-wake-arm.sh` now resolves the harness's own argv (first claude/node
ancestor; `CC_WAKE_ARM_HARNESS_ARGV` is the test seam, set-but-empty = provably unresolvable) and
SKIPS on one-shot print mode — and on anything it cannot resolve, because under-arming restores the
status quo while over-arming wedges a birth.

## R2 — the shared consecutive-block cap force-ends autonomous goal runs at 8

Read out of the binary (@233098–233156) and corroborated in the corpus:

- An UNMET goal evaluation yields a `blockingError` — the same currency as every operator Stop
  hook's block — and each blocked stop increments ONE counter, `stopHookBlockingCount`.
- Past `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` (default **8**) the harness "overrid[es] and end[s] turn":
  the session goes idle with the goal still armed and `met:false`. **25 transcripts across the five
  config dirs carry that override message.** Infra blocks (session-continue 🔧, completion-assert)
  spend the same budget, so a goal session on this box saw fewer than 8 goal iterations per wake.
- The counter resets per external stimulus (user message / task-notification wake), so the cap is
  "consecutive autonomous continuations per wake" — exactly the /goal operating regime.

**Fix:** `bin/claude-latest` — the funnel every launcher exec's through — defaults
`CLAUDE_CODE_STOP_HOOK_BLOCK_CAP=50` when unset (operator override always wins; the binary's own
cap message names this env var as the sanctioned lever). 50 keeps a runaway bound; every blocking
hook we own also carries its own tighter latch (`CLAUDE_CONTINUE_MAX`, damping).

## R3 — the commonest succession silently dropped the goal

§3.4 measured that a goal dies with its session and `--recycle` re-arms only if the caller re-passes
`--goal`; the Open item called inheritance a design question. The operator's 2026-08-09 directive
("**`--goal` is part of that recipe, not an option**", CLAUDE.md § Agent Teams) settles it:
**`handoff-fire.sh --recycle` now INHERITS the predecessor's LIVE goal by default** —
`goal_live_for_sid` (nested-projects resolution, prose-decoy-proof) + `inherit_recycle_goal`
(explicit `--goal` wins · `CC_RECYCLE_GOAL_INHERIT=0` opts out · terminal goal inherits nothing ·
inherited conditions re-run `check_goal_arm`, so a multi-line condition is refused loudly, never
armed corrupt). Re-arm still happens only after engagement is proven, via the existing `arm_goal`.

## What deliberately did NOT change

- `check_slash_head` — untouched, still pinned by its red-if-weakened test.
- CC's deferral — correct; we removed our standing occupier instead of defeating the judge.
- `goal-inert-watch.sh` — still the backstop sensor (migration 0005 registered; its dir list gained
  `~/.claude-next`, which 0007 had and 0005 had silently omitted). Residual deferrers it still
  catches: a long background subagent/workflow parked across an idle — a correct deferral, but now a
  visible one.
- CLAUDE.md § Agent Teams' `cc-await-ping` line — left as-is deliberately (the file was under
  active operator edit 2026-08-10); the runtime guard corrects a goal-armed lead with a teaching
  deny, which is the chokepoint the memory rule prescribes anyway.

## Suites

`goal-state.bats` 10/10 (new) · `validate-bash-goal-guard.bats` 8/8 (new) · `wake-floor.bats` +3
(goal abstain, met-goal discriminator, zero-budget-spend) · `mailbox-drain.bats` +2 (goal-aware
nag both directions) · `mailbox-wake-arm.bats` 15/15 (+3 headless-guard) ·
`handoff-goal-arm.bats` 27/27 (+9 inheritance) · `claude-latest-stderr.bats` +1 (cap default +
override).


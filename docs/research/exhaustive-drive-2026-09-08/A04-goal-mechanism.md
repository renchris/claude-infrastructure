# A04 — Is `/goal` working, and should every session carry one?

Wave: exhaustive-drive 2026-09-08. Read-only. Binary: 2.1.260
(`/Users/chrisren/.claude-260/node_modules/@anthropic-ai/claude-code/bin/claude.exe`, installed
2026-09-03 19:52). Every number below carries the command and the population that produced it.

---

## VERDICT

**`/goal` is not a working "keep working until the condition holds" lever on this box, and it should
not be made the primary one. 434 of 641 goal runs in the last 30 days (67.7%) were armed and then
never evaluated even once — and the rate is unchanged across the version bump (2.1.220: 70.8%
never-evaluated · 2.1.260: 71.8%).** Among the 154 goals that *did* reach `met`, the median
iteration count is **1** — i.e. the evaluator ran once, said "met", and the goal drove nothing.
So even the working case is a *terminator*, not a drive loop. Worse, **there is no programmatic
arming path at all**: the only `CLAUDE_CODE_GOAL*` env var in the 2.1.260 binary is
`CLAUDE_CODE_GOAL_CHECKIN_MINUTES`, there is no `--goal` CLI flag, and no SDK control request — the
sole channel is a `/goal` line typed into the TUI composer, which our own dispatcher telemetry
records as **5 `set` · 6 `unverified` · 2 `unreachable`** across all 13 rows it has ever written.
Auto-arming from the frozen DoD at SessionStart, as the brief proposes, is therefore **not
implementable by a hook** — a SessionStart hook can only emit `additionalContext`, and no
`additionalContext` reaches the goal registry.

Separately: **the 375 `goal-unreadable` abstains are our own bug, not a 2.1.260 record-shape
change.** They are a `grep | jq` pipeline under `set -o pipefail` where grep's *no-match* exit 1
sinks the whole pipeline. The 2.1.260 record dictionary matches `hooks/lib/goal-state.sh`'s header
exactly — verified against the binary's own restore-on-resume reader.

---

## 1. What the 2.1.260 binary actually does

### 1.1 The evaluator (answers brief (a))

`Elr()` @165442800–165450000. For `Stop`/`SubagentStop` the user message is verbatim:

```
Based on the conversation transcript above, has the following stopping condition been satisfied?
Answer based on transcript evidence only.

Condition: ${e.prompt}
```

System prompt (Stop variant):

```
You are evaluating a stop-condition hook in Claude Code. Read the conversation transcript
carefully, then judge whether the user-provided condition is satisfied.

Your response must be a JSON object with one of these shapes:
- {"ok": true,  "reason": "<quote evidence from the transcript that satisfies the condition>"}
- {"ok": false, "reason": "<quote what is missing or what blocks the condition>"}
- {"ok": false, "impossible": true, "reason": "<explain why the condition can never be satisfied>"}

Always include a "reason" field, quoting specific text from the transcript whenever possible. If
the transcript does not contain clear evidence that the condition is satisfied, return
{"ok": false, "reason": "insufficient evidence in transcript"}.

Only use {"ok": false, "impossible": true} when the condition is genuinely unachievable in this
session — for example: the condition is self-contradictory, it depends on a resource or capability
that is unavailable, or the assistant has explicitly tried, exhausted reasonable approaches, and
stated it cannot be done. Apply your own judgment when deciding this — the assistant claiming the
goal is impossible is evidence, not proof; independently confirm the condition is genuinely
unachievable rather than deferring to the assistant's self-assessment. Do not use it just because
the goal has not been reached yet or because progress is slow. When in doubt, return {"ok": false}
without "impossible".
```

Call parameters, read out of the same site:

| property | value | consequence |
|---|---|---|
| `tools: []` | tool-less | **confirmed** — CLAUDE.md's claim is correct |
| `thinkingConfig:{type:"disabled",mechanical:true}` | no reasoning | the evaluator cannot derive; it matches text |
| `timeout` | `e.timeout ? ×1000 : **30000`** | 30 s default; on expiry `De="cancelled"`, `g("goal_met","evaluator_timeout")`, **no record written** |
| transcript window | `sas(msgs, model, Tlr)` with `var Tlr=0.5` → `floor(window × 0.5)`, `1e6` window for 1M models | **up to 500 K tokens per evaluation**; over budget it truncates with a `[Earlier conversation truncated…]` preface and emits `tengu_hook_prompt_transcript_truncated` |
| retry | `re(Tlr/2)` on `prompt_too_long`, telemetry `tengu_hook_prompt_too_long_retry` | second call at 25% |
| output | `json_schema {ok, reason, impossible}` | structured |
| model | `e.model ?? Em()` | a hook may pin its own evaluator model |

"Answer based on transcript evidence only" + the `insufficient evidence in transcript` fallback is
the binary's own confirmation of the CLAUDE.md rule that **state the session never surfaces is
unreachable**. Measured against the corpus, that fallback almost never fires: of 869 evaluation
`reason` strings across all goal runs in 30 d, exactly **1 (0.1%)** contains "insufficient evidence
in transcript" — so the evaluator is not defaulting to abstention; when it runs, it judges.

### 1.2 The record shape (answers brief (a), (c))

Written at @164281148 (`met`/`impossible`) and @164282375 (`not met`):

```js
// achieved
yield cn({type:"goal_status", met:true,  condition, reason, iterations, durationMs, tokens})   // + tengu_goal_achieved
// judged impossible — CC clears the goal
yield cn({type:"goal_status", met:false, failed:true, condition, reason, iterations, durationMs, tokens}) // + tengu_goal_failed
// judged unmet — arrives via the blockingError branch, which is what continues the turn
yield cn({type:"goal_status", met:false, condition, reason})
```

The binary's own resume-time reader (`oYt`/`s` @179084669) implements exactly the dictionary in
`hooks/lib/goal-state.sh:15-22`:

```js
for(let n=l.length-1;n>=0;n--){ let e=l[n];
  if(e?.type!=="attachment"||e.attachment.type!=="goal_status") continue;
  if(e.attachment.met||e.attachment.failed) return null;      // dead
  return e.attachment.condition }                              // live
```

**Our lib is correct for 2.1.260.** Two facts the lib does not carry, both useful:

- **A goal SURVIVES `--resume`** (`tengu_goal_restored_on_resume`, `origin:"restored"`, `iterations`
  reset to 0). CLAUDE.md § Agent Teams says "a goal dies with its session, so a recycle must re-arm
  it" — true for `handoff-fire --recycle` (a *new* session id), **false for a resume**.
- The `met`/`failed` records carry `iterations`, `durationMs`, `tokens` (session tokens consumed
  while the goal was live). `goal_liveness` discards all three; they are the only on-disk cost
  signal a goal produces.

### 1.3 The deferral gate — CHANGED in 2.1.260 (this is new since our docs)

@164279140. Our docs (`goal-in-handoff-2026-08-08.md`, `goal-inert-watch.sh:8-10`) describe the
2.1.220/2.1.231 form `if(kFe(Y)||vKo(Y)){ remove the goal hook } finally { add it back }`. **2.1.260
replaced it:**

```js
let Ne = f.agentId ? undefined : f.getAppState().activeGoal;      // subagents never carry a goal
if (Ze && ut) {                                                   // ut = !f.agentId
  let Mt = d2n(f.taskRegistry.all());
  if (Mt.length > 0) {
    de = ere(...).find(bn => bn.prompt === Ze.condition);
    if (de) { f.sessionHooksRegistry.remove(K(),"Stop",de);
              t("[goal] evaluation deferred — background work still running");
              De="deferred";
              let vn = IWn(Ze, Mt, Date.now());                    // NEW: check-in planner
              be = vn.nextGoal; bn = vn.checkinText;
              if (bn !== undefined) { ...yield an isMeta user message... } } }
  else if (Ze.deferredSince !== undefined) { ...strip deferral state... }
}
```

The deferring set (`d2n` @164287510):

```js
function d2n(e){ return Object.values(e).filter(n =>
    !cd(n) && !(n.type==="local_agent" && n.agentType==="main-session") && (Zjt(n)||eWt(n))) }
function Zjt(e){ return w.has(e.type) && !vs(e.status)
                   && !(e.type==="in_process_teammate" && e.isIdle)
                   && !(e.type==="remote_agent"        && e.isLongRunning) }   // w = local_agent, remote_agent, in_process_teammate, local_workflow
function eWt(e){ return e.type==="local_bash" && !vs(e.status) }                 // NO isBackgrounded test
```

**`eWt` still has no `isBackgrounded` filter.** Trap (c) in `goal-inert-watch.sh:50-66` — that the
deferring set is a strict superset of the `background_tasks` payload, so an ordinary *foreground*
bash still registered `running`/`pending` at Stop defers the goal invisibly — **holds unchanged in
2.1.260.** Arm 3b of our hook remains load-bearing.

New in 2.1.260, and the reason nothing above is a regression: a **deferral check-in**. Constants
@164237000:

| symbol | value | meaning |
|---|---|---|
| `BVo` | 30 | default check-in interval, minutes; `CLAUDE_CODE_GOAL_CHECKIN_MINUTES` overrides, `0` opts out |
| `Ict()` | `I("tengu_saffron_wren",true) ? mins*60000 : 0` | GrowthBook-gated, default ON |
| `xWn(i,n)` | `i * 2**min(n,UVo=2)` | backoff 30 → 60 → 120 min |
| `HVo` | 3 | idle-timer check-in cap (`kFe`), then "idle check-ins paused until your next message" |
| `Rct` / `jVo` | 60000 / 120 | min idle-timer delay 1 min · task description truncated to 120 chars |

The message (`AWn`), verbatim:

> `«<condition>» is still active, and evaluation has been deferred for N min because background work
> is still running:` *(list of `id · type · command)*
> `Check on their progress (e.g. read their output). If they are progressing, say so briefly and keep
> waiting; if they are stuck or no longer needed, fix or stop them and continue toward the goal.`

and, when the deferring set has emptied, `Goal check-in: background work no longer running … that
work is no longer running (it finished or was stopped without reporting back). Continue toward the
goal.` Telemetry `tengu_goal_checkin_injected{trigger: turn_end|idle_timer, deferredMs, activeShells,
activeAgents, checkinCount, idleCheckinCount}`.

Binary changelog @167862600 confirms both new behaviours in Anthropic's words:

> `/goal` now clears itself with a notice when a turn dies on an unrecoverable error (e.g. revoked
> auth, an exhausted credit balance, or a context overflow) instead of staying armed
> `/goal`: when background tasks keep a goal waiting for 30+ minutes, Claude now checks in on them
> instead of waiting indefinitely (set `CLAUDE_CODE_GOAL_CHECKIN_MINUTES=0` to opt out)

### 1.4 Auto-clear conditions (answers brief (a))

`h2n` @164287510+560, gated on `tengu_quartz_pipit` (default true), main session only. `xKo(reason)`
maps the turn's death to a clear class:

| turn end reason | clears the goal as |
|---|---|
| `blocking_limit`, `prompt_too_long`, `rapid_refill_breaker` | **`context_limit`** |
| api_error `authentication_failed` / `oauth_org_not_allowed` (unless `CLAUDE_CODE_REMOTE`/`Td()`/`kke()`), `account_on_hold` | `auth` |
| api_error `billing_error` | `billing` |
| api_error `model_not_found` | `model_unavailable` |
| everything else — `max_turns`, `stop_hook_prevented`, `hook_stopped`, `aborted_*`, `tool_deferred`, transient api errors, `overloaded`, `rate_limit`, … | **`null` — goal stays armed** |

On a clear it removes the Stop hook, yields the `sentinel:true, met:true` marker (so
`goal_liveness` reads `cleared`), and renders
`Goal cleared after an unrecoverable error (<label>): "<condition>". Run /goal again to continue.`

**Operationally: the goal dies exactly at the context wall** — the moment a long-horizon drive most
needs a successor to inherit it. `handoff-fire --recycle` does not carry it forward, and nothing on
this box re-arms it.

### 1.5 There is no programmatic arming path

- `grep -a -c -F 'CLAUDE_CODE_GOAL'` → 4 hits, **all four are `CLAUDE_CODE_GOAL_CHECKIN_MINUTES`**
  (offsets 75112584 / 156175526 / 164237762 / 167863048, each dumped and read).
- `grep -a -c -F 'set_goal'` → 0; `'setGoal'` → 0.
- `grep -a -b -o -F '"--goal"'` → 1 hit @162412179, which is the argument table for the **`fmt`**
  shell builtin (`fmt -g/--goal`), not a Claude Code flag.

The only writer of `activeGoal` besides the resume path is the `/goal` slash command. **A hook
cannot arm a goal.**

---

## 2. The measured outcome — 30 days, four roots

Population: every `*.jsonl` under the four transcript roots (realpath-deduped; `~/.claude-next` is a
real directory, not a symlink into them) with mtime within 30 d.
Script: `scratchpad/goalcensus.py` + `goalanalyze.py` + `goalver.py` (paths in § Provenance).

```
transcripts (mtime 30 d)                       6,134
  containing the STRING "goal_status"            792
  containing a goal_status ATTACHMENT            625     ← 167 (21%) are the trap-(b) prose/tool-result population
goal runs (arm → terminal)                       641
```

| outcome | n | share |
|---|---|---|
| **`live` — armed, never resolved** | **466** | **72.7%** |
|  … of which **zero evaluations** | **443** | 69.1% of all runs |
|  … … and the session has been dead >24 h (definitively never judged) | **434** | **67.7%** |
| `met` | 154 | 24.0% |
| `cleared` (`/goal clear` or auto-clear) | 6 | 0.9% |
| `failed` (judged impossible) | 2 | 0.3% |
| unparented records (goal restored across a resume) | 13 | 2.0% |

Evaluations per goal: **median 0, mean 1.36, max 119**; the histogram is 457 goals at 0, 142 at 1,
9 at 2, and a 19-goal tail at ≥10.

For the 434 definitively-never-evaluated goals, the session kept working after arming for a **median
0.7 h (p75 1.3 h, max 52.7 h)**, and **140 of them worked for over an hour** with the goal armed and
never once judged. Sample of the longest:

```
 52.7h  'claude-code-session-economics.html is a self-playing motion piece — proven by printing …'
 32.7h  'a postland-verify GREEN stamp exists for a trunk sha at or after the fix — proven by …'
 28.9h  'ultracode investigate improving our application performance with best practices …'
```

### 2.1 The version split — 2.1.260 did NOT fix this

`version` read from each transcript's own header record:

| version | runs | met | live: never-evaluated | live: evaluated-then-stopped | cleared | failed | **never-eval %** |
|---|---:|---:|---:|---:|---:|---:|---:|
| 2.1.220 | 586 | 142 | 415 | 22 | 6 | 1 | **70.8%** |
| 2.1.260 | 39 | 9 | 28 | 1 | 0 | 1 | **71.8%** |

Dead 2.1.260 sessions carrying a never-evaluated goal: n=22, **median 1.8 h of post-arm work, 14 of
22 over an hour.** The check-in feature surfaces the deferral to the operator; it does not make the
goal evaluate, because the same branch that injects it is the branch that *removes the hook*.

Check-in adoption, measured: `grep -rl -F 'evaluation has been deferred for'` over the four roots →
**11 transcripts** (10 for the `no longer running` variant), all dated 2026-09-04 onwards. One
sampled body names three `subagent` tasks — i.e. **a research fan-out defers its own lead's goal**,
which is precisely this wave's shape.

### 2.2 When it works, it is a terminator, not a drive loop

Of the 154 `met` goals: **median `iterations` = 1** (max 119). Median time-to-met **52.2 min**
(p25 25.7, p75 138.9, max 3542.7 = 59 h). Median session tokens consumed while the goal was live:
**82,979** (max 2,603,546).

Median 1 iteration means: the evaluator ran once, said met, done. **In the median successful case
the goal blocked zero stops.** Only 19 of 641 runs (3.0%) produced ≥10 evaluations — that tail is
the only population where `/goal` behaved as the operator's intent describes.

### 2.3 What predicts failure — and what does not

Stratified over the 623 goal runs with a resolvable arm (`goaldecorr.py`):

| stratum | n | ≥1 evaluation |
|---|---:|---:|
| ALL | 623 | 28.4% |
| condition contains "proven by" (the mandated `--goal` template) | 515 | **21.6%** |
| long freehand (>200 chars, no template) | 80 | 53.8% |
| short freehand (≤200 chars) | 28 | **82.1%** |
| template **and** (bg-bash or Agent present) | 365 | 24.1% |
| template **and neither** | 148 | 14.9% |
| freehand **and** (bg-bash or Agent present) | 94 | 63.8% |
| freehand **and neither** | 16 | 43.8% |
| — background bash present / absent | 440 / 183 | 32.3% / **19.1%** |
| — Agent/subagent present / absent | 131 / 492 | 32.1% / 27.4% |

Two results worth stating plainly:

1. **The template effect survives stratification** (24.1% vs 63.8% *within* the background-work
   stratum; 14.9% vs 43.8% within the no-background stratum). The dispatcher-mandated goal shape is
   the single strongest predictor of a goal that is never judged.
2. **Background work does NOT predict failure — it weakly predicts success** (32.3% vs 19.1%), and
   subagent presence is null (32.1% vs 27.4%). This *partially refutes* the standing explanation in
   `goal-in-handoff-2026-08-08.md` that the cc-await-ping/background-task deferral is the cause of
   goal inertness. The deferral is real and mechanically proven from the binary, but it is not what
   separates the 28% that evaluate from the 72% that do not. **Confound named:** template goals live
   on dispatched wave leads and freehand goals on interactive panes, so "template" may be a proxy for
   "session type". I could not decorrelate that further from disk.

### 2.4 The Stops were happening — this is not "the session never stopped"

Cross-referencing the 625 goal sessions against today's IDL (`~/.claude/autonomy/idl.jsonl`,
sid-keyed, 13 h of coverage) gave 9 overlapping sessions. Counting **distinct-second Stop-hook
timestamps after the arm record**:

```
NEVER-evaluated  n=7  median 476 Stop-hook instants after arming  (max 644)
evaluated        n=2  median 610                                   (max 836)
```

All 7 never-evaluated sessions had ≥3 Stops after arming; six ran 2.1.260; **none of them carries a
single check-in message.** So the mechanism is neither "no Stops happened" nor "the check-in fired
and was ignored". One of the seven (`b418b97a`) is **this wave's own lead**: goal armed, 476
Stop-hook instants, zero evaluations, zero check-ins — a live in-hand instance.

That combination is not explained by the code path I read: `d2n` non-empty ⇒ deferred (and after
30 min continuous, a check-in) · `d2n` empty ⇒ the hook is not removed and should evaluate. Neither
outcome is what the transcripts show. The remaining unobserved branches are the two that write
**nothing at all**: `De="cancelled", g("goal_met","evaluator_timeout")` (30 s expiry) and
`De="error", g("goal_met","evaluator_error")` (hook_blocking_error / hook_error_during_execution).
Both are debug-log-only; `grep -rl '\[goal\]' ~/.claude/logs` finds no CC debug log on this box, so
**this residual is not resolvable from disk** — see § 6.

### 2.5 The evaluator-timeout hypothesis is REFUTED

If the 30 s evaluator budget over up to 500 K tokens were the cause, big transcripts would fail more.
Measuring transcript size **at the arm record's byte offset** (per HARD RULE 3):

| transcript size at arm | n | ≥1 evaluation |
|---|---:|---:|
| <1 MB | 600 | 27.2% |
| 1–5 MB | 15 | 60.0% |
| 5–20 MB | 7 | 57.1% |
| ≥60 MB | 1 | 100.0% |

Median size at arm: evaluated **0.11 MB**, never-evaluated **0.13 MB**. Size does not predict
failure; if anything the relation runs the wrong way. Hypothesis dropped.

---

## 3. The 375 `goal-unreadable` abstains are OUR bug (answers brief (c))

`hooks/goal-inert-watch.sh:90` sets `set -uo pipefail`. It then sources `hooks/lib/goal-state.sh`,
whose `goal_liveness` body runs **under the caller's shell options**:

```bash
out="$(grep -a 'goal_status' "$tp" 2>/dev/null | jq -rc --slurp '…' 2>/dev/null)" || return 1
```

`grep` with **no match exits 1**. Under `pipefail` the pipeline's status is that 1 regardless of
jq's success, so `|| return 1` fires and `goal-inert-watch.sh:177` logs `goal-unreadable`. The
`"absent\t0\tnone\t0\t"` branch at `goal-state.sh:92` is **unreachable for the ordinary case** — it
can only be reached when the literal string `goal_status` appears in the transcript *without* being
an attachment (prose, or a tool_result from a session reading our own hook/test code).

Reproduced (`/tmp/gl-probe.sh`, `set -uo pipefail`, sourcing the live lib):

```
rc=1 hits=0 out=[]                                          e1f98c3d-…jsonl   ← no goal_status at all
rc=0 hits=1 out=[absent 0 none 0 ]                          8a41189c-…jsonl   ← string present, no attachment
rc=0 hits=2 out=[cleared 1 met 1786677621 update our voiceink…]               ← real goal
```

Corpus confirmation: of the 49 distinct sids that logged `goal-unreadable` today, 48 resolved to a
transcript; **47 of 48 contain zero occurrences of `goal_status`**. The single outlier
(`baedcd81…`) now reads `absent` because its one occurrence is a `tool_result` carrying the
`g_arm()` bats fixture from `hooks/lib/goal-state.sh`'s own test file — it grew after the hook ran.

So the mapping is exactly inverted from the lib's stated intent. `goal-state.sh:72-75` says:

> a failure must be legible as a failure (rc 1 ⇒ the consumer prints "unknown"), never as `absent` —
> which is a POSITIVE finding … and would launder an unreadable transcript into a clean bill of health.

The shipped behaviour is the mirror image: **the positive finding `absent` is laundered into a
failure.** Today's tally (`jq 'select(.hook=="goal-inert-watch")|.reason' idl.jsonl`):

```
375 goal-unreadable      ← should be `no-goal:absent`
 75 no-goal:absent       ← 2 distinct sids; the trap-(b) prose/tool-result population
 36 no-goal:cleared      ← 2 distinct sids
  3 goal-inert:blind     ] the hook working
  2 goal-inert:named     ]
  2 damped:never
```

**Blast radius is bounded but real:**

- **No live goal is missed.** A live goal implies the string is present implies grep exits 0. The
  hook's fire path is intact — this bug can only mislabel the *no-goal* case.
- **`goal_live_condition` has the same construct** (`goal-state.sh:38-40`) and its four consumers
  (`mailbox-drain.sh:378`, `session-continue.sh:578`, `validate-bash.sh:280`,
  `lead-crash-watchdog.sh:997`) all treat rc 1 as "no goal live" — which is the correct answer for a
  transcript with no goal. **Benign there**, but only by luck of the fail direction.
- **The diagnostic surface is destroyed.** 375 rows saying "I could not read the transcript" is what
  made the wave brief ask whether 2.1.260 changed the record shape. It did not. A blind-looking token
  over the healthiest possible state is the `fail-safe-default-mimics-the-healthy-state` /
  `wrong-cause-corroborated-by-true-metric` pattern already in MEMORY.md.
- **The abstain alarm is one step from being fooled.** `scripts/idl-abstain-alarm.sh:117-119` does
  **not** list `goal-unreadable` in `_default_blind`, so it is scored DORMANT (condition-not-met),
  not BLIND. Today that is accidentally the *right* verdict for the wrong reason. If the lib ever
  genuinely breaks, `goal-unreadable` goes to 100% of abstentions and the alarm will report
  **DORMANT-100 (green)** over a completely blind check.

---

## 4. The arming side is separately unreliable (answers brief (e))

`scripts/handoff-fire.sh` documents `--goal` as MESSAGE 2: after engagement, a `/goal <cond>` line is
pasted into the fired pane and read back for verification (`arm_goal`, `goal_armed_for_pane`), with
verdicts `set | unverified | abstained | unreachable | held | mangled` emitted to
`~/.claude/logs/handoffs.jsonl` as `class:"goal-arm"`. Measured, **all time** (the emitter is
recent; `jq 'select(.class=="goal-arm" and (.under_test|not))|.verdict'`):

```
6 unverified     submitted, no goal_status ever appeared — the harness may have refused it
5 set
2 unreachable    the fire died before message 2
```

n=13 is small, but 5/13 verified is the only number that exists. The two open rows say the rest:

- **`1d73c2fd875c`** — "2 of 3 fires on 2026-08-31 shipped without a Stop-hook goal because the
  verified paste found the composer unreadable for 30 s at load 15-20/10 cores… The fire SUCCEEDS
  and the brief lands, so the failure is silent in every surface except the fire transcript line."
- **`2ee30f87c370`** — retracts the load hypothesis: "pane 211 armed and VERIFIED (670 chars) at load
  41.35 on the same box, i.e. 2× the load at which the other two failed. Whatever gates the composer
  read, it is not load." Both rows propose the same fix — **arm through a path that does not read the
  TUI composer** — which § 1.5 now shows **does not exist**.

A third, independent silent-death mode is already guarded: `check_goal_length()`
(`handoff-fire.sh:4436-4451`) refuses a `/goal` body over the harness's **4000-char cap**, because
over-cap is "a SILENT dead fire (the pane spawns task-less and idles)".

---

## 5. Consumers, and one latent compounding risk

Four surfaces suppress or refuse behaviour on `goal_live_condition`:

| surface | what a live goal does |
|---|---|
| `hooks/session-continue.sh:575-587` | **wake floor STANDS DOWN** when a goal is live and mail is pending — "the goal-forced turns deliver it" |
| `hooks/validate-bash.sh:279-281` | **DENIES** a backgrounded `cc-await-ping` park under a live goal |
| `hooks/mailbox-drain.sh:377-378` | suppresses the park nag |
| `hooks/lead-crash-watchdog.sh:997`, `scripts/wrap-ledger.sh:649-675` | report goal state |

The premise of all four — *a live goal forces turns* — is false for 72% of armed goals. The sharpest
consequence is the pair `session-continue` (stand down the wake floor) + `validate-bash` (refuse the
watcher): a session with a live-but-inert goal can lose **both** wake paths on the strength of a
promise that never materialises.

**Honest scope: this is latent, not measured.** `wake-floor-goal-live` fired **0 times today**
(the branch needs a live goal *and* pending mail simultaneously); the ordinary `wake-floor` fired 24
times. `validate-bash` writes no IDL rows at all, so its denial rate is unmeasured. I am flagging a
mechanism, not an incident.

---

## 6. Adversarial pass — what I went looking for, and what it cost the story

| I asked | answer |
|---|---|
| Is the 2.1.260 record shape different from what the lib parses? (the brief's own hypothesis) | **No.** The binary's resume reader is a line-for-line match of the lib's dictionary. The brief's premise came from a token that means something else. |
| Is the 30 s evaluator timeout over a 500 K window the cause? | **Refuted** — size at arm does not predict failure (§ 2.5). |
| Is background/subagent deferral the cause, as our docs say? | **Partially refuted** — background work weakly predicts *success* (32.3% vs 19.1%); subagents are null. The deferral is mechanically real but is not the discriminator. |
| Did 2.1.260's new check-in fix it? | **No** — 71.8% vs 70.8%, and the 7 never-evaluated sessions I could cross-reference carry **zero** check-ins. |
| Did the sessions simply never Stop? | **No** — median 476 distinct Stop-hook instants after arming (§ 2.4). |
| Is `ENABLE_STOP_REVIEW=0` (settings.json:8) a goal-related kill switch? | **No** — the string does not exist in the 2.1.260 binary. It is inert config. (Answers a question the wave brief raised.) |
| Could a hook auto-arm the goal, as the brief's recommendation (f) proposes? | **No** — no env var, no CLI flag, no SDK control request (§ 1.5). The recommendation as written is not implementable. |
| Does a goal survive a recycle? | Survives `--resume`; **does not** survive `--recycle` (new sid). CLAUDE.md's blanket "a goal dies with its session" is half wrong. |

What I could **not** close: the exact branch that swallows the evaluation in the § 2.4 sessions.
`d2n`-empty should evaluate and `d2n`-non-empty should eventually check in; neither happened. The two
silent branches (`evaluator_timeout`, `evaluator_error`) write only to the CC debug log, and no such
log exists on this box. **The falsifiable probe is one line**: run one session with
`CLAUDE_CODE_GOAL_CHECKIN_MINUTES=1` and CC debug logging on, arm a goal, and read whether the
`[goal] evaluation deferred` line appears at every Stop. That distinguishes "deferred forever" from
"evaluator erroring silently", and nothing on disk can.

---

## 7. Recommendations

Failure direction is stated for each, per the wave's bias.

### R1 — Fix the pipefail inversion in `goal_liveness` (and `goal_live_condition`). Conviction 97%. Effort S.

`goal-state.sh:38` and `:84`. Two shapes work; the second is preferable because it also removes the
grep-exit-status coupling entirely:

```bash
# either: neutralise grep's no-match status
rec="$( { grep -a 'goal_status' "$tp" 2>/dev/null || true; } | jq -rc --slurp '…' )" || return 1
# or: keep the fast path but distinguish the three outcomes explicitly
```
Then delete the now-dead `goal-unreadable` label for that case and let `no-goal:absent` carry it.

**Fail direction: errs toward SPEAKING.** Today the hook is silent-and-mislabelled on the safe state;
after the fix it is silent-and-correctly-labelled. It cannot make the hook fire more often — the fire
path never reached this branch. The only regression risk is that a *genuinely* unreadable transcript
(corrupt JSON, jq missing) starts reporting `absent`, which is exactly the laundering the lib's
header forbids — so the fix must keep a distinct rc for "grep succeeded, jq failed". This is the one
place to be careful, and it is why I would not accept a bare `|| true` on the whole pipeline.

Add `goal-unreadable` to `_default_blind` in `scripts/idl-abstain-alarm.sh:117` **at the same time**,
so that a future genuine breakage pages INERT instead of rendering DORMANT-100 green.

### R2 — Do NOT auto-arm a goal on every session. Conviction 93%. Effort S (it is a decision, not a build).

Three independent reasons, each measured:
1. **It is not implementable by a hook** (§ 1.5). The only channel is the TUI paste that already
   returns 5 `set` / 6 `unverified` / 2 `unreachable`.
2. **It would not work if it were.** 67.7% of goals that *do* arm are never evaluated, and the rate
   did not move across a binary version.
3. **It is not free.** Each evaluation is one extra tool-less LLM call over up to 50% of the context
   window (`Tlr=0.5`, `1e6` for 1M models). At the fleet's ~901 turn-final closes/day (lead-measured),
   universal arming buys ~901 evaluator calls/day — for a mechanism whose median successful run
   blocks *one* stop.

**Fail direction: errs toward NOT nagging.** The cost of this recommendation being wrong is that we
leave a working lever unused. Given § 2.2 (median 1 iteration at met) the upside forgone is small.

### R3 — Keep `hooks/session-continue.sh` as the primary drive lever; state that in CLAUDE.md. Conviction 91%. Effort S.

It is the mechanism we own, it is not deferrable by the task registry, and today it actually fires:
**238 `fired:continue` + 24 `fired:wake-floor` + 293 `armed:cli-set`** in 13 h against **4** total
goal-inert fires and 28.4% goal evaluation. CLAUDE.md § Agent Teams currently mandates `--goal` as
"part of that recipe, not an option"; the measurement says the recipe's backstop is a coin-flip at
best. Reframe `--goal` as *the operator-visible statement of the wave's DoD* (which it is good at)
rather than *the mechanism that keeps the session working* (which it is not).

**Fail direction: errs toward MORE forced turns.** `session-continue` blocks stops, so over-relying on
it risks the nag-the-legitimate-stop failure. It is already bounded (`CLAUDE_CONTINUE_MAX`,
`CC_MECH_MAX`, the kill-switch), which is why I rate it above the goal.

### R4 — Change the mandated `--goal` condition template toward the short freehand shape. Conviction 72%. Effort M.

Template goals evaluate 21.6% of the time; short freehand goals 82.1%, and the gap survives
stratification on background work (§ 2.3). **I am under 90% because the confound is unexcluded** —
template goals live on dispatched wave leads, freehand on interactive panes, and I could not separate
"the condition shape" from "the session type" using disk evidence alone. The exhaustive research that
would move this is a controlled A/B: arm the *same* wave with a long template goal and a ≤200-char
goal on two sibling sessions and compare evaluation counts. That is a live experiment, not a corpus
read, so it is genuinely outside a read-only wave.

**Fail direction: errs toward LESS specific goals.** A shorter condition is easier for a tool-less
evaluator to judge met, so this trades false-negatives (never judged) for false-positives (judged met
too early). Given `/goal`'s only real power is *stopping* a session, a premature "met" is the more
dangerous error — which is exactly why the conviction is not higher.

### R5 — Make `goal-inert-watch` able to see the check-in, and re-anchor its arm 3b. Conviction 88%. Effort M.

The hook's header (`:4-20`, `:50-66`) is written against 2.1.220/2.1.231. Three of its statements are
now incomplete: the gate is `d2n(taskRegistry.all()).length>0` (not `kFe||vKo`); a deferral now
*may* inject a visible check-in; and CC now auto-clears the goal on context/auth/billing death.
`grep -c -F 'evaluation has been deferred for'` on the transcript is a **free, exact** signal of
"CC itself said it deferred" and should feed the hook's cause paragraph — turning arm 3b's
"NOTHING IS NAMEABLE HERE" from a guess into a two-state finding (CC said deferred / CC said nothing).

**Fail direction: errs toward SILENCE in one new case** — if a check-in is present the hook can
reasonably damp harder, which risks missing an inert goal the operator has already been told about
twice. Prefer keeping the fire and *changing the wording* over adding a new abstain.

### R6 — Record the auto-clear-at-context-limit fact where a successor will read it. Conviction 90%. Effort S.

`xKo` clears the goal on `prompt_too_long` / `blocking_limit` / `rapid_refill_breaker`. CLAUDE.md
§ Context Stewardship already says the ceiling is a hard refusal with no safety net; it should also
say that **the goal is one of the things the ceiling takes**, and that `--recycle` must re-arm while
`--resume` need not. One paragraph in `docs/research/goal-in-handoff-2026-08-08.md` plus the CLAUDE.md
§ Agent Teams sentence that currently over-generalises "a goal dies with its session".

**Fail direction: errs toward more prose in an already-long file.** Mitigate by *correcting* the
existing sentence rather than adding one.

---

## 8. Provenance

Scripts written for this axis (scratchpad, read-only, not part of the repo):
`/private/tmp/claude-501/-Users-chrisren-Development-claude-infrastructure/b418b97a-d3ec-4444-b993-4f29d55f425a/scratchpad/{goalcensus,goalanalyze,goalstale,goalver,goalsize,goalorigin,goaldecorr,goalstop}.py`
and `/tmp/gl-probe.sh` (the pipefail reproduction).

Binary reads used `LC_ALL=C /usr/bin/grep -a -b -o -F <fixed string>` to get byte offsets, then
`tail -c +N | head -c M | tr -c '[:print:]\n' '.'` (`dd` is denied by the permission layer). Offsets
cited inline. No file in the repo or any live store was modified.

Files read in full: `hooks/lib/goal-state.sh`, `hooks/goal-inert-watch.sh`; in part:
`hooks/session-continue.sh:565-600`, `scripts/handoff-fire.sh` (goal sites),
`scripts/idl-abstain-alarm.sh:100-130`, `hooks/dod-persist.sh` (SessionStart branch).

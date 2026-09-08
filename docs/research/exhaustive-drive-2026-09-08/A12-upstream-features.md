# A12 — Upstream Claude Code 2.1.260 features for "keep working until done"

Wave: exhaustive-drive 2026-09-08. Read-only. Binary under test:
`/Users/chrisren/.claude-260/node_modules/@anthropic-ai/claude-code/bin/claude.exe`
(`VERSION 2.1.260`, `BUILD_TIME 2026-09-03T19:41:35Z`, `GIT_SHA e51f681183f733dbe9a81bf35921c786ee26dbc6`
— read out of the OTEL resource block at offset 34728658).

**Sibling ownership.** `/goal`'s evaluator, its deferral gate and its 30-day outcome census belong to
**A04-goal-mechanism.md**; the Task/Todo tool gate and the task store belong to **A03-shared-task-list.md**.
This report does not re-derive either. It owns the rest of the upstream surface: the hook **type**
system, `ENABLE_STOP_REVIEW`, `ProposeGoal`, the block cap's headroom, `/loop`/`ScheduleWakeup`/cron,
the silent-turn reminder, the unregistered events, and the feasibility of an **agent-type Stop hook**
as a replacement for several of our phrase matchers.

---

## Answer first

**The single largest unused upstream lever is the hook TYPE system, not any env var.** All **105** of our
registered hooks, across **21** events, are `type:"command"` — measured. Claude Code 2.1.260 ships **five**
hook types, and four of them (`prompt`, `agent`, `mcp_tool`, `http`) have **zero** instances in our
configuration. The `agent` type is a real tool-using judge on Stop, and it can do what our phrase matchers
cannot: read the ledger and answer *"is there drivable work left?"*. **But it is not a drop-in replacement**,
for two measured reasons — it runs at permission mode `dontAsk` against an allowlist that contains no rule
for `wrap-ledger.sh`, `cc-backlog` or `cc-decide`, and it **fails open** (no structured output ⇒
`outcome:"cancelled"`, the stop proceeds). A judge that is silently denied its evidence and then fails open
is precisely the "silent in the dangerous state" defect this wave exists to find. Adopt it **narrowly and
only behind an allowlist change**, or not at all.

Two secondary findings that change what should NOT be done:

- **`ENABLE_STOP_REVIEW="0"` in all four accounts names nothing.** Not in 2.1.260, not in 2.1.220, not in
  2.1.219, not in the public docs. It is cargo, and it has been in the settings since at least 2026-08-05.
- **The Stop-hook block cap is not the binding constraint.** It was genuinely reached **6 times in 4 sessions
  over 30 days** (6,140 transcripts). Raising `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` would change essentially
  nothing today.

And one thing we cannot turn on: **`ProposeGoal`** — the tool that lets the model arm its own goal, which is
literally the operator's ask — exists in 2.1.260 and is gated behind the server-side flag
`tengu_propose_goal`, default **false**, with **no local override path in the binary**. Measured: 0
occurrences in 30 days of transcripts.

---

## 1. The hook type system — the axis's main finding

### 1.1 Five types, one union, every event

`jl()` (offset 8901000–8906200) returns five schemas assembled into one discriminated union
`Et() = Zo("type",[BashCommand, Prompt, Agent, Http, McpTool])`, and `wj() = Xvt(Y(S_), v(kt()))` maps
**every** event name in `S_` to arrays of matcher-groups whose `hooks` are that union. **There is no
per-event type restriction in the schema** — an `agent` hook on `Stop` is schema-legal.

| type | what it is (binary's own words) | default timeout | default model |
|---|---|---|---|
| `command` | shell command; JSON on stdin, exit codes + stdout back | 600 s (doc) | — |
| `prompt` | *"Prompt to evaluate with LLM. Use `$ARGUMENTS` placeholder for hook input JSON."* | **30 s** (`e.timeout?e.timeout*1000:30000`) | *"the default small fast model"* |
| `agent` | *"Agentic verifier hook type"* — *"Prompt describing what to verify (e.g. \"Verify that unit tests ran and passed.\")"* | **60 s** (`e.timeout?e.timeout*1000:60000`) | *"If not specified, uses Haiku."* |
| `http` | POST the hook input JSON to a URL | 600 s | — |
| `mcp_tool` | call a tool on an already-configured MCP server | 600 s | — |

`async` / `asyncRewake` / `rewakeMessage` / `rewakeSummary` / `shell` / `args` exist **only on the command
schema** (offset 8901095–8901700). A prompt or agent hook cannot be backgrounded.

### 1.2 What we actually run — measured

```
python3 -c "import json;j=json.load(open('/Users/chrisren/.claude/settings.json'));…"
```

| event | hooks | types present |
|---|---|---|
| PreToolUse 18 · PostToolUse 13 · SessionStart 16 · SessionEnd 7 · **Stop 12** · UserPromptSubmit 7 · Notification 5 · PermissionRequest 4 · PreCompact 3 · PostToolUseFailure 3 · FileChanged 2 · TeammateIdle/WorktreeCreate/TaskCompleted/StopFailure/InstructionsLoaded/PostToolBatch/CwdChanged/PermissionDenied/PostCompact/ConfigChange 1 each | **105** | **`command` only.** One `asyncRewake:true` (SessionStart). Zero `prompt`, zero `agent`, zero `mcp_tool`, zero `http`, zero `if`, zero `once`, zero `model`. |

Identical `env` block in all four account settings files, so this is fleet-wide.

### 1.3 Twelve of the 33 events are unregistered

Canonical list `S_` (offsets 8876694 and 9980913), 33 entries. Registered: 21. **Unregistered (12):**
`UserPromptExpansion, SubagentStart, SubagentStop, PreModelSwitch, PostModelSwitch, Setup, TaskCreated,
Elicitation, ElicitationResult, WorktreeRemove, DirectoryAdded, MessageDisplay`.

Two of those are ours to fix cheaply:

- **`SubagentStop` is in our settings TEMPLATE but not in the live settings.**
  `settings-templates/settings.example.json:507` registers `~/.claude/hooks/subagent-stop.sh`;
  `grep -c 'SubagentStop' ~/.claude/settings.json` ⇒ **0**. The hook exists, carries a documented payload
  capture, and has a bats suite (`tests/…`), and it has never fired. `SubagentStop` is in the *blocking*
  set (see §1.4), receives `last_assistant_message`, `background_tasks` and `session_crons`, and its
  matcher filters on **agent type** — so it is the natural home for "did this research subagent actually
  deliver its artifact?".
- **`TaskCompleted` IS registered (1 hook)** but the Task tools do not reach the lead, so it cannot fire.
  Corroborated: `~/.claude/autonomy/idl.jsonl` (45,824 lines, 2026-09-08 08:22Z→) has **0** records for
  `task-completed-index`, `task-mutation-index` or `task-quality-gate`, against 682 for `session-continue`.
  (A03 owns the remedy.)

The binary carries its own event-value map `xbr` (offset 13348519) labelling `Setup`, `PreCompact`,
`PostCompact`, `TeammateIdle`, `TaskCreated`, `TaskCompleted`, `Elicitation*` as `"low_value"`. **Read that
as a hint, not a verdict** — its actual job is deciding which hooks are worth forwarding to a cloud session
(`m5n`), not ranking them for local use.

### 1.4 Which events can block

`vbr` / `Cbr` (offset 13348519): `PreToolUse, PostToolUse, PostToolUseFailure, PostToolBatch,
UserPromptSubmit, UserPromptExpansion, Stop, StopFailure, SubagentStart, SubagentStop, PermissionDenied`.
Note **`StopFailure` and `SubagentStart` can block** — neither is exploited today
(`stop-failure-marker` has 2 IDL records; `SubagentStart` is unregistered).

---

## 2. `ENABLE_STOP_REVIEW` — it names nothing, in three binaries and the docs

`~/.claude/settings.json` `env` (identical in `.claude-secondary`, `-tertiary`, `-quaternary`):

```json
"ENABLE_STOP_REVIEW": "0"
```

| probe | command | result |
|---|---|---|
| 2.1.260 | `LC_ALL=C grep -a -c -F ENABLE_STOP_REVIEW <260 binary>` | **0** |
| 2.1.220 | same, `.claude-220` | **0** |
| 2.1.219 | same, `.claude-219` | **0** |
| `STOP_REVIEW`, `stopReview`, `stop_review` in 2.1.260 | grep over the extracted printable text | **0 / 0 / 0** |
| positive control | `CLAUDE_CODE_ENABLE_AWAY_SUMMARY` **4** · `…PROMPT_SUGGESTION` **7** · `…ENABLE_TODO_TOOLS` **3** · `…MAX_SUBAGENT_SPAWN_DEPTH` **5** | present |
| public docs | WebFetch `code.claude.com/docs/en/env-vars` | *"`ENABLE_STOP_REVIEW` — This variable does not appear anywhere in the documentation"* |

Origin trace: **not in the repo's git history at all** —
`git log -S'ENABLE_STOP_REVIEW' --oneline --all` in `/Users/chrisren/Development/.worktrees/exhaustive-drive`
returns only today's plan doc plus checkpoint commits. It reaches back at least to
`~/.claude/backups/settings-recap-20260805-132642/` (present in all five snapshots there), so it was
already live on **2026-08-05** and has never been in a tracked settings file.

**A07-caps-and-latches.md** independently found the 2.1.260 absence; this report adds the two older
binaries, the public-doc absence, and the origin date. **The concordant reading is that it never existed** —
not "it was removed". A gate name absent from three consecutive builds *and* the docs has no version window
left to have lived in. It is a settings-file line whose only cost is the belief, held in this wave's own
brief, that we had deliberately disabled a review feature.

*Failure direction of removing it:* zero. Nothing reads it. *Failure direction of leaving it:* a future
session reads it as evidence of a considered decision and does not look for the real one.

---

## 3. `ProposeGoal` — the feature that IS the operator's ask, and we cannot enable it

Tool `MSt = "ProposeGoal"` (offset 11651286; full definition at 27060798). Its own description:

> *"Propose a session goal condition, with one-keypress user approval; once set, Claude keeps working until
> a separate evaluator confirms it is met"*

and its prompt:

> *"Propose a completion condition for this session's work — a goal that keeps you working until a separate
> evaluator confirms it is met. Non-blocking: the proposal renders alongside your work, so keep working while
> it is handled. `ask_user` true (the default) asks the user first, with a one-keypress approval dialog. …
> Set `ask_user` false — which sets the goal directly, with no dialog — ONLY when the user's own words in
> this conversation stated this outcome as what they want … Propose only when the user has asked for an
> outcome with a verifiable end state ("make the tests pass", "migrate every call site") and the work spans
> multiple turns."* (condition cap `NSt` = 500 chars.)

`ask_user:false` is the exact shape the operator's standing directive would license: the user's own words
stated the outcome, so the agent arms the goal itself and keeps working.

**Why it is not available.** `isEnabled()` (offset 27060798):

```js
isEnabled(){ if(ke()||Dn())return!1;      // non-interactive / remote workspace
             if(ht())return!1;            // CLAUDE_CODE_SESSION_KIND === "bg"
             if(!mct())return!1;          // ← the gate
             let e=tRe(); if(e==="disabled")return!1;
             return E(e),!0 }
function mct(){ return I("tengu_propose_goal", !1) }   // offset 24137371 — DEFAULT FALSE
```

- `tengu_propose_goal` is a **server-evaluated** flag with default `false`. Searched for a local override:
  `STATSIG_LOCAL_OVERRIDE`, `gateOverride`, `statsigOverride`, `forcedGates`, `overrideGates`,
  `CLAUDE_CODE_FLAGS` ⇒ **0 occurrences each**. Unlike the Task tools (`CLAUDE_CODE_ENABLE_TODO_TOOLS`
  short-circuits `pM()`), there is no env escape hatch on this path.
- The user-facing setting exists and is **not** the blocker: `modelProposedGoals` ∈
  `{auto | alwaysAsk | disabled}`, default `auto` (`tRe()` at 9375000), *"read from trusted sources only
  (user/policy/flag) — workspace-resident project and local settings are ignored."*
- `if(a.agentId) throw Error("ProposeGoal cannot be used in agent contexts")` — never available to subagents,
  which is why it does not appear in this report's own tool inventory.
- Absent from 2.1.219 and 2.1.220 (`grep -a -c -F ProposeGoal` ⇒ 0, 0). It is new in the 2.1.234–2.1.260 band.

**Measured availability across the fleet, 30 days:**

```
find <4 realpath'd project roots> -name '*.jsonl' -mtime -30   →  6,140 files
scan for '"name":"ProposeGoal"'                                →  0 files
scan for 'ProposeGoal' (any mention)                           →  2 files, both THIS session's own transcript
```

Cross-check that the instrument works: the same scanner returns 794 files for `goal_status`, 251 for
`"name":"ScheduleWakeup"`, 46 for `TaskCreate` tool_use.

*(Instrument note: an earlier pass of this census used `xargs -a <file>`, which BSD/macOS `xargs` does not
support; with stderr suppressed every count read 0, including a positive control that should have read
5,904. Every number above was re-run with a chunked Python scanner. The house rule
`suppressed-stderr-turns-a-failed-command-into-a-zero` caught it.)*

---

## 4. The Stop-hook block cap — headroom, not a constraint

`CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` resolution (offset 16480451):

```js
let Vd = a.CLAUDE_CODE_STOP_HOOK_BLOCK_CAP ?? 8;
if (Vd > 0 && qd > Vd) { … "A hook blocked the turn from ending N consecutive times — overriding and
                              ending turn." ; return {reason:"completed"} }
```

Three facts worth having:

1. **The counter is per-turn, not per-hook.** `stopHookBlockingCount` increments by 1 on any turn where
   `dm.blockingErrors.length > 0`, however many hooks blocked. Our 12-hook Stop chain and a hypothetical
   prompt/agent hook and a live `/goal` **share one budget**; they do not multiply it.
2. **`Vd > 0` means setting the cap to `0` disables it entirely** — unbounded consecutive blocking. That is
   an available lever and a dangerous one; see the recommendation.
3. **We are nowhere near it.** Scanning 6,140 transcripts for the literal warning and then keeping only
   genuine `type:"system"` emissions (the raw string count is inflated by our own research docs quoting it):

   | | files | events |
   |---|---|---|
   | raw string `A hook blocked the turn from ending` | 36 | 67 |
   | **genuine `type:"system"` emissions** | **4** | **6** (all `9 consecutive`) |

   Six cap-hits in thirty days across four accounts. Raising the cap buys ~nothing.

The docs corroborate the mechanism and add a second terminator the binary strings hint at:
*"If Claude keeps answering the evaluator without making progress (no tool use for several turns in a row),
Claude Code stops the loop, prints a warning, and returns control to you with the goal still set."*
(`/docs/en/goal`). That **no-progress detector**, not the cap, is the ceiling on a `/goal` drive loop.

---

## 5. An agent-type Stop hook as a tool-using judge — full feasibility read

This is the brief's "pay special attention" item. `Olr()` at offset 17528798 is the whole runtime.

### 5.1 What it is

System prompt on Stop/SubagentStop, verbatim:

> *"You are verifying a stop condition in Claude Code. Your task is to verify that the agent completed the
> given plan. The conversation transcript is available at: `<path>`. You can read this file to analyze the
> conversation history if needed. Use the available tools to inspect the codebase and verify the condition.
> Use as few steps as possible - be efficient and direct. When done, return your result using the `<tool>`
> tool with: - ok: true if the condition is met - ok: false with reason if the condition is not met"*

| property | value | source |
|---|---|---|
| tools | `has(f.options.tools)` = **the session's own tool set** minus 3 (the structured-output tool, `bNe`, `mt`), plus the verifier tool | `function has(e){return e.filter(n=>!Xt(n,pi)&&!qk(n,bNe)&&!Xt(n,mt))}` |
| permission mode | **`mode:"dontAsk"`**, plus a session rule `Read(/<transcript path>)` | `getAppState()` override in `Wt` |
| max turns | **50** (`Ze=50`; `tn>=50 ⇒ abort`) | 17530xxx |
| default timeout | **60 s**, `timeout` field overrides | `e.timeout?e.timeout*1000:60000` |
| model | `e.model ?? Em()` — the small fast model, **Haiku** by default | schema + `Em()` |
| thinking | `{type:"disabled", mechanical:true}` | `Wt.options` |
| `ok:false` | `outcome:"blocking"`, message `Agent hook condition was not met: <reason>` fed back; turn continues | 17531xxx |
| no structured output / 50-turn abort | **`outcome:"cancelled"`** — **fails OPEN, the stop proceeds** | same |
| `impossible` | **not supported** (prompt hooks only) | doc + `Ype()` branch is `!N` |
| `continueOnBlock` | **no such field** on the agent schema | schema |
| telemetry | `tengu_agent_stop_hook_{success,blocking,error,max_turns}` with `durationMs, turnCount, hookEvent, agentName` | 17531xxx |

Docs confirm and add the warning: *"Agent hooks are experimental. Behavior and configuration may change in
future releases. For production workflows, prefer command hooks."*

### 5.2 Could it replace our phrase matchers?

In principle yes — it is a fresh-context judge with Bash, Read and Grep that could run `wrap-ledger.sh`,
read the task list, and read the transcript tail, which is exactly what `anti-deference-nudge`,
`completion-assert` and `dispatch-assert` approximate with lexical rules (A08/A02 own the matcher census).
**Three measured obstacles say "not as configured":**

**(a) `dontAsk` against our allowlist.** `~/.claude/settings.json` `permissions.allow` has **339** rules.
Grepping them for anything the judge would need:

```
Bash(cat:*)   Bash(git log:*)   Bash(git status:*)   Bash(jq:*)   Read
```

**No rule matches `wrap-ledger.sh`, `cc-backlog`, `cc-decide`, `cc-custody` or a bare `bash <script>`.**
Under `dontAsk` an unmatched Bash call is **denied, not prompted**. So the judge would be silently refused
the shipped renderer that computes the rung, and would answer from `git status` + `cat` + the transcript —
a strictly weaker instrument than the one `/wrap` already runs. Combined with the fail-open behaviour in
5.1, the composite failure is: *judge is denied its evidence → cannot form a verdict → returns no structured
output → `cancelled` → the session stops.* **Silent in the dangerous state.** This is the single reason the
recommendation below is conditional on a permission change landing first.

**(b) Cost.** The agent hook does **not** receive the transcript as messages (unlike the prompt hook, which
does — `sas()` at 17482xxx). It receives the prompt plus **the session's tool schemas**. Measured payload:
the largest tool-definition line in a real session transcript
(`.claude-tertiary/…/582bce15-….jsonl`) is **126,630 bytes** ≈ **30 K tokens** of schema, re-sent on every
request of the judge's loop, up to 50 turns, on Haiku. Token cost is small at Haiku rates; **latency is not**.

**(c) Latency against a chain that is already the bottleneck.** Lead-measured, one Stop, 24 MB transcript:
`anti-def 0.24 + completion-assert 0.37 + dispatch-assert 0.66 + session-continue 3.51 + goal-inert 0.33 +
operator-readout 3.61 ≈ 8.7 s` for six of twelve command hooks. A 60 s default agent hook is ~7× the entire
existing chain, on **every** turn-end. The hook `if` field is not a cost gate here: the 2.1.246 changelog
entry describes `if` conditions in permission-rule form (`Bash(cat *)`), i.e. tool-shaped, and a Stop event
has no tool call to match.

### 5.3 The prompt type, for contrast — and the `/goal` identity

`/goal` **is** a prompt-type Stop hook. `KEe()` (offset 11566xxx):

```js
o.sessionHooksRegistry.add(r,"Stop","",{type:"prompt",prompt:t});
```

confirmed by the docs: *"`/goal` is a wrapper around a session-scoped prompt-based Stop hook."* So we already
run one prompt-type Stop hook — just not a declared one. Its evaluator is **tool-less** (`tools:[]`,
`thinkingConfig:{type:"disabled"}`, `querySource:"hook_prompt"`, output pinned to
`{ok, reason, impossible}` by `outputFormat.json_schema`), gets the transcript prepended and truncated to
half the model's window with `tengu_hook_prompt_transcript_truncated`, and defaults to 30 s.

**Interaction to know before declaring a prompt Stop hook in settings.** `/goal clear` removes prompt-type
Stop hooks with `matcher===""` and no `skillRoot` — but only from `sessionHooksRegistry` (`ere()` at
11566xxx), which is a different store from settings-file hooks (`he(E)?.hooks` in `M5n`). A declared prompt
hook therefore survives `/goal clear`. The real cost is the other way round: a declared prompt Stop hook
plus a live `/goal` = **two LLM evaluations per Stop**, sharing one block-cap budget.

---

## 6. `/loop`, `ScheduleWakeup`, cron — available, essentially unused

| | mechanism | our 30-day use |
|---|---|---|
| `ScheduleWakeup` | Bound to **`/loop` dynamic mode only** — *"the user invoked /loop without an interval, asking you to self-pace iterations."* `delaySeconds` clamped `[60,3600]`. Sentinels `<<autonomous-loop-dynamic>>` (ScheduleWakeup) / `<<autonomous-loop>>` (CronCreate). `stop:true` ends the loop. | **17 tool_use blocks in 4 files**; schema present in 251 files |
| `CronCreate/Delete/List` | wall-clock re-run of a prompt; *"Jobs only fire while the REPL is idle (not mid-query)"*; jitter ≤10% of period (max 15 min); **recurring tasks auto-expire after N days** — *"This bounds session lifetime."* Durable jobs in `.claude/scheduled_tasks.json`. | **1 tool_use block, 1 file** |
| `Monitor` | *"watch a log file, process, or command output and be notified the moment something changes… streams events as they happen; cron polls on a schedule."* | **307 tool_use blocks in 117 files** — the one genuinely adopted wake primitive |
| `EndConversation` (`tengu_umber_kestrel`) | a tool that ends the conversation | **0 uses, 0 availability** |

The `ScheduleWakeup` prompt carries guidance worth importing into our own park discipline verbatim:
*"Do NOT schedule a short-interval wakeup to poll for background work you started — when harness-tracked
work finishes, you are re-invoked automatically, so polling is wasted. Instead schedule a long fallback
(1200s+) so the loop survives if the work hangs or never notifies."*

Per the docs' own comparison table, `/loop` is time-driven and `/goal` is condition-driven; the operator's
"work until done" is condition-driven, so `/loop` is the wrong primitive for the main ask and the right one
only for a watch-and-wait pane.

---

## 7. Two more surfaces the brief named

**Away summary** (`CLAUDE_CODE_ENABLE_AWAY_SUMMARY=true`, set in all four accounts). Prompt at offset
5042937: *"The user stepped away and is coming back. Recap in under 40 words, 1-2 plain sentences, no
markdown. Lead with the overall goal and current task, then the one next action. Skip root-cause narrative,
fix internals, secondary to-dos, and em-dash tangents."* This is a **recap for the human**, not a stopping
control. Worth noting only because our CLAUDE.md § close-message W3 clause ("skip root-cause narrative, fix
internals, secondary to-dos, em-dash tangents") is **verbatim this prompt** — we already imported it.

**Silent turn reminder** — an upstream nudge that pushes the *opposite* way from this wave:

```js
var Bar=5, Har=3,
Uar="The user hasn't heard from you in a while. As you continue, keep them updated when there's
     something to tell — a finding, a change of plan.";
function Gar(){ … a.CLAUDE_CODE_SILENT_TURN_REMINDER_TURNS ?? I("tengu_hushed_lark",5) }
function tis(e){ let{turnsSinceLastReminder:n,remindersInStretch:r}=eis(e);
                 if(r>=3||n<Gar())return[]; return [{type:"silent_turn_reminder",text:jar()}] }
```

Default: after **5** silent assistant turns, up to **3** reminders per stretch, gated `tengu_hushed_lark`,
text overridable with `CLAUDE_CODE_SILENT_TURN_REMINDER_TEXT`. It asks for *more chat*, which is the
Fable-5.1 quiet-pane problem our CLAUDE.md already names — not a keep-working lever. Leave alone.

**Stop payload fields we do not read.** The Stop/SubagentStop input carries `background_tasks`
(*"Lets hooks distinguish \"session is done\" from \"session is paused waiting for background work to wake
it\""*) and `session_crons` (*"Session-scoped cron tasks (CronCreate, ScheduleWakeup, /loop) that will wake
this session later"*). Repo grep: **only `goal-inert-watch.sh` reads `background_tasks`** (and only as a
payload-shape assertion at line 141 plus a deferral read at 147); **nothing reads `session_crons`**; only
`subagent-stop.sh` and `stop-failure-marker.sh` read `last_assistant_message`. The working-vs-idling sensor
backlog row `a3eaa0dc1be2` asks for exactly the discriminator `background_tasks` already ships.

---

## 8. Adversarial pass — what I did not want to be true

**"You measured availability by grepping tool names; tool names appear in transcripts for other reasons."**
Correct, and it broke one number. `"name":"ScheduleWakeup"` matched 251 files, but inspection of
`.claude-tertiary/…/582bce15-….jsonl` shows those are **tool-schema echoes**, not calls. Every "used"
number in this report is a parsed `type:"tool_use"` block, counted separately from the schema echo. The
availability column is the weaker half and is labelled as such.

**"6 cap-hits is suspiciously low — maybe the warning is not persisted."** Tested the other direction: the
raw string matched 36 files / 67 lines, and filtering to `type:"system"` cut it to 4 / 6. The **surplus** was
our own research prose quoting the message, not a missing signal. The system-message form is the one the
harness emits (`yield kt(…, "warning")`), and it is persisted — it appears in four distinct worktree
sessions on three different accounts.

**"`ENABLE_STOP_REVIEW` might be a *server-side* name the client never spells."** Possible in principle,
refuted in practice by the shape of the thing: it sits in the `env` block, which is a map of **process
environment variables** the client reads with `process.env`/`a.<NAME>`, and every other entry in that same
block (`CLAUDE_CODE_ENABLE_AWAY_SUMMARY`, `…PROMPT_SUGGESTION`, `…EXPERIMENTAL_AGENT_TEAMS`,
`MCP_TIMEOUT`, `CLAUDE_CODE_MAX_WEB_SEARCHES_PER_SESSION`) **is** a literal in the binary. A client env var
the client cannot spell cannot be read. Plus the docs' explicit absence.

**"An agent Stop hook might not actually get Bash."** Checked rather than assumed: `has(e)` filters exactly
three tools out of `f.options.tools` and `yas()` adds a *destructive-command* refusal only on the
cloud-served path (`A hook agent evaluating a call served for a cloud session may not run a destructive
command here`). Locally it gets Bash. The binding constraint is the **permission mode**, not the tool list —
which is why §5.2(a) is the load-bearing objection and not a hand-wave.

**"You claimed the block cap is shared — show it."** `dm = yield* p2n(...)` collects blocking errors from
the whole chain; `qd = go + 1` increments once per turn; the same `qd` is compared to `Vd`. One counter, one
comparison, all hook types. Also visible in the telemetry shape:
`tengu_stop_hook_block_count{count, is_subagent, hit_max_turns, hit_cap, goal_active}` — `goal_active` is a
*field* on the same event, not a separate counter.

**The gap I could not close.** I cannot observe whether `tengu_propose_goal` is currently `true` for these
four accounts from inside a subagent — the tool is unavailable in agent contexts by construction
(`if(a.agentId) throw`). The 30-day transcript census (0/6,140) is strong evidence it is off for the
interactive leads too, but it is an absence argument, and an absence argument over a flag that Anthropic can
flip server-side at any time **has a half-life**. The falsifier is one line: on a lead session, check whether
`ProposeGoal` appears in the tool inventory.

---

## 9. Recommendations

Each states which way it errs. "Nags on a legitimate stop" = trains the model to route around it.
"Silent in the dangerous state" = the defect this wave hunts.

| # | change | conviction | effort | errs toward |
|---|---|---|---|---|
| R1 | **Delete `ENABLE_STOP_REVIEW` from all four `settings.json` env blocks** (migration, `# migration-class: c10`). | 96% | S | Neither — it is inert. The only risk is losing the *record*, so the migration body must carry the three-binary + docs evidence. |
| R2 | **Register `SubagentStop` → `hooks/subagent-stop.sh` in the live settings**, matching the template. | 88% | S | Nags. A SubagentStop hook that blocks a subagent's stop costs a subagent turn; keep it advisory (exit 0 + `additionalContext`) on first landing, and gate any block on `stop_hook_active`. |
| R3 | **Do NOT adopt an agent-type Stop hook yet.** Land the allowlist rules first (`Bash(bash …/wrap-ledger.sh:*)`, `Bash(cc-backlog:*)`, `Bash(cc-decide:*)`), *then* trial it on ONE event with `timeout: 120`, on a single pane, measured against `tengu_agent_stop_hook_*`. | 84% (against adopting now) | M | **Silent in the dangerous state** if adopted as-is: `dontAsk` denies the evidence, no structured output ⇒ `cancelled` ⇒ the stop proceeds with no signal. |
| R4 | **Do not raise `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`, and never set it to 0.** Measured 6 genuine hits / 4 sessions / 30 d — there is no pressure on it, and `Vd>0` means `0` removes the only bound on consecutive blocking. | 93% | S (a no-op) | Setting it high/zero errs toward an unbounded loop with no operator-visible warning; leaving it errs toward a rare, loud, correct override. |
| R5 | **Read `background_tasks` in the Stop chain** for the working-vs-idling discriminator (backlog `a3eaa0dc1be2`) instead of building a new sensor. It ships in the payload and only `goal-inert-watch.sh` touches it. Also read `session_crons` — nothing does. | 90% | S | Nags, mildly: a "you have background work" line on a legitimate stop. Mitigate by making it a fact in the ledger, not a block. |
| R6 | **File `tengu_propose_goal` as a genuine `not-yet-true` backlog row with a falsifier**, not as agent work: the falsifier is "`ProposeGoal` appears in a lead session's tool inventory". It is the only upstream feature that implements the operator's ask directly, and there is no local override in the binary. | 92% | S | Errs toward waiting on a flag we do not control; the falsifier is what keeps the row from going stale (a filed blocker is never revalidated). |
| R7 | **Import the `ScheduleWakeup` polling guidance into our park discipline** verbatim ("do not poll harness-tracked work; schedule a 1200 s+ fallback"), and prefer `Monitor` (307 calls / 30 d, already adopted) over any new poller. | 87% | S | Neither; it is a doc change that narrows an existing practice. |
| R8 | **Do not declare a `type:"prompt"` Stop hook in settings while `/goal` is the standing mechanism.** It would be a second tool-less evaluator on the same block-cap budget, judging the same transcript. | 89% | S (a non-action) | Adopting it errs toward doubling per-Stop LLM latency for a verdict `/goal` already renders. |

---

## 10. Open questions

1. Is `tengu_propose_goal` on for any of the four accounts *today*? (Absence argument only; R6's falsifier.)
2. `ScheduleWakeup` schema present in 251 files but called 17 times — is `/loop` being started and abandoned,
   or is the schema echo unrelated to `/loop` being active? Not resolved; the schema-echo population is a
   weak instrument.
3. `CLAUDE_CODE_ENABLE_FUNCTION_HOOKS` + `HOOKS_WORKER_URL:"…/functionHooks/hooks-worker/hooks-worker.js"`
   is a sixth, in-process hook type (`type:"function"`, excluded from the settings union by
   `filter(r=>r.type!=="function")`). Not investigated; SDK-only on this read.
4. The docs describe an *escalating* goal check-in schedule (30 min → 1 h → 2 h, idle cap 3 since 2.1.246)
   that A04 measured firing 25 times on 2.1.260. Whether that changes the standing
   `hooks/validate-bash.sh` DENY of a backgrounded park under a live goal — written against 2.1.220, where
   `tengu_saffron_wren` / `CLAUDE_CODE_GOAL_CHECKIN_MINUTES` / `tengu_goal_checkin_injected` are all
   **absent** (`grep -a -c` ⇒ 0 on both older binaries) — is A04's call, not this report's.

---

## Provenance

- Binary text extracted once: `LC_ALL=C tr -c '[:print:]\n' '\n' < claude.exe`, then `awk 'length>=30'`
  (198 MB → 41 MB / 142,065 lines). Offsets in this report are byte offsets into that filtered file, so they
  are reproducible only by re-running those two commands.
- Context searches used a Python `re.finditer` helper, **not** interactive `grep` — the interactive `grep`
  is rewritten to `ugrep` by a hook and refuses `{0,N}` repetitions over 255 and chokes on binaries.
- Corpus: `find <4 realpath'd roots> -name '*.jsonl' -mtime -30` ⇒ **6,140** files, scanned with a chunked
  reader (4 MiB chunks; a token spanning a chunk boundary would be missed — negligible for the short
  literals used, and the 5,904-file positive control passed).
- Docs read 2026-09-08: `code.claude.com/docs/en/hooks`, `/docs/en/hooks-guide`, `/docs/en/goal`,
  `/docs/en/env-vars`.
- Older binaries probed directly (no extraction): `~/.claude-219`, `~/.claude-220`.

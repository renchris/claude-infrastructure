# O1 — THE STOP BUTTON

**Question:** for every unit class, can the operator STOP it — right now, from one place, mid-flight?

**Method.** Static read of the bundle the live fleet is actually running
(`~/.claude-220/.../bin/claude.exe`, v2.1.220 — MEASURED as the live one, § 2.0), plus live read-only
CLI probes in a copied `CLAUDE_CONFIG_DIR`. Nothing on the live fleet was killed, stopped, closed,
signalled or keystroked. Every load-bearing cell carries the command behind it.

---

## 1. Verdict

1. **The stop button exists, and it is `/tasks` → select → `x`.** Anthropic ships a single dialog
   (`background-tasks-dialog`) that stops *every* paneless class from inside the parent session
   without killing it — including a running **Dynamic Workflow**, via
   `killWorkflowTask → abortController.abort()`, and the run is **resumable**
   (`Workflow({scriptPath, resumeFromRunId})`, completed agents cached). The landed
   *"a running Dynamic Workflow has NO abort path"* is **true of OUR tooling and false of the
   harness** — a REACHABLE lever was sitting one keystroke away the whole time.
2. **The two stop keys you would reach for do not reach a workflow.** `Esc` never stops a background
   unit at all; `ctrl+c` and `ctrl+x ctrl+k` stop `local_agent` + `in_process_teammate` only —
   the kill-all predicate `Xrl` **excludes `local_workflow`** (§ 2.2). This is the exact shape of
   *"blindly going on by itself"*: good SEE, and a STOP that silently misses the one class with 229
   agents behind it.
3. **There is no "one place".** STOP is per-parent-session and the registry is per-config-dir:
   **21 live claude processes, 4 distinct registries, 12 rows** (§ 2.4). Stopping unit *N* means
   finding and focusing unit *N*'s parent pane. At 15 sessions that is 15 places; the cost of the
   stop grows linearly with the thing the operator wanted to scale.
4. **A kill switch IS buildable, and it is two mechanisms, not one.** A PreToolUse **brake** reaches
   every in-process class including workflow agents (§ 4.1); the only *true* programmatic stop for
   paneless units is the control-protocol `interrupt` → `mmr()`, which kills exactly
   `local_agent + local_workflow` — EXISTS, but NOT REACHABLE from a TUI session (§ 4.2).
5. **Safe for overseen work today:** pane sessions, named teammates, unnamed subagents, `--bg`
   workers. **Needs a stop mechanism built first:** Dynamic Workflows (stoppable only by a human at
   that parent's keyboard) and headless `-p` (no named stop at all).

---

## 2. The STOP matrix

### 2.0 Instrument + positive controls

```bash
# the bundle the fleet is actually running (NOT ~/.claude-versions/current, which is 2.1.114)
ps -eo pid,comm | grep -i claude | head -20
#   -> 21x /Users/chrisren/.claude-220/node_modules/{.bin/claude,...bin/claude.exe}
cat ~/.claude-220/node_modules/@anthropic-ai/claude-code/package.json | grep '"version"'   # 2.1.220

cd ~/.claude-220/node_modules/@anthropic-ai/claude-code/bin
LC_ALL=C strings -a -n 6 claude.exe > /tmp/strings220.txt     # 412,384 lines, 0.53 s
```

Positive controls on the instrument (a null from this grep would otherwise be worthless):

| token | hits | reading |
|---|---|---|
| `tengu_workflow` | 26 | instrument sees workflow telemetry |
| `Workflow` | 326 | — |
| `abortSignal` | 53 | — |
| `AbortController` | 146 | — |
| `shutdown_request` | 13 | our teammate verb is in there |
| `TaskStop` | 19 | — |
| `killWorkflowTask` | 3 | **the claimed-absent mechanism is present** |

`grep -c -F 'Kill workflow' → 0` and `'Stop workflow' → 0` are **negatives from a working
instrument**: the labels are lower-case and terser (`x stop workflow`), which is exactly why a
prose-level search for an abort path came back empty before.

### 2.1 What the harness ships — the one dialog and its keys

```bash
python3 ctx.py '"bashes"'        # slash-command registration
# {type:"local-jsx", name:"tasks", aliases:["bashes"],
#  description:"View and manage everything running in the background", immediate:!0}
```

The dialog is `background-tasks-dialog`; its footer strings and the workflow detail dialog's footer
come out of the bundle verbatim:

```
background-tasks-dialog:  select · upDown · foreground · stop all agents · kill-all · escape
                          Agents / Shells / Monitors / MCP tasks / Cloud agents /
                          Local agents / Dynamic workflows / Background
workflow-detail-dialog:   j/k scroll · prompt · select · x stop · x stop workflow ·
                          r restart · p pause · p resume · f filter · esc back · s save
```

The list-mode key handler (MEASURED, `python3 ctx.py 'Xii\('` hit 1) dispatches **one key — `x`** —
across every unit type:

```js
if(se.key==="x"&&!se.ctrl&&!se.meta){
  ne.type==="local_bash"          -> Xko.kill
  ne.type==="local_agent"         -> L(ne.id)
  ne.type==="in_process_teammate" -> N(ne.id)            // Qsn: abort + paneTeardown
  ne.type==="local_workflow"      -> Xii(ne.id,a)        // Xii = killWorkflowTask
  ne.type==="monitor_mcp"         -> Qii                 // killMonitorMcp
  ne.type==="mcp_task"            -> H2f                 // MCP_TASK.kill
  ne.type==="dream" / "auto_mode_scan" / "remote_agent"  -> P / U / Iqs|Dqs|W
}
```

### 2.2 The three global keys — and what each one actually reaches

Keybinding table, verbatim (`python3 ctx.py '"chat:killAgents"'` hit 1):

```
Global: "ctrl+c":"app:interrupt", "ctrl+d":"app:exit", "ctrl+t":"app:toggleTodos", …
Chat:   escape:"chat:cancel", "ctrl+x ctrl+k":"chat:killAgents", "ctrl+b":"task:background", …
```

The handler body (hit at offset 28396200) settles the semantics:

```js
H=(K=false)=>{
  if (i!==undefined && !i.aborted || s) { M("tengu_cancel",oe); t(); return }  // in-flight turn -> abort it
  if (NRu()) { if (a) { a(); return } }                                        // else pop queued command
  if (!K && x) { if (O()) { M("tengu_cancel",oe); return } }                   // else kill background agents
  M("tengu_cancel",oe); t();
}
Pn("chat:cancel",  () => H(true),  {context:"Chat"});     // Esc  -> K=true  -> SKIPS the kill branch
Pn("app:interrupt", z /* -> H() */, {context:"Global"});  // ^C   -> K=false -> reaches the kill branch
```

and the kill-all predicate — the single most consequential line on this axis:

```js
function Xrl(e){ return hc(e) && (e.status==="running"||sR(e))
              || e.type==="in_process_teammate" && e.status==="running" }
function hc(e){ return typeof e==="object" && e!==null && "type" in e && e.type==="local_agent" }
```

| key | reaches | does NOT reach | confirm step |
|---|---|---|---|
| **`Esc`** (`chat:cancel`) | the **in-flight turn only** | every background task, all classes | none |
| **`ctrl+c`** (`app:interrupt`) | turn first; then `local_agent` + `in_process_teammate` | **`local_workflow`**, `mcp_task`, `monitor_*`, `remote_agent` | none |
| **`ctrl+x ctrl+k`** (`chat:killAgents`) | same set as ^C | **`local_workflow`** and all of the above | **double-press within 3 s** (`I7f=3000`): first press renders *"Press ctrl+x ctrl+k again to stop background agents"*; with none running, *"No background agents running"* |
| **`/tasks` → `x`** | **everything, per unit** | — | none (immediate) |

> `FRu` in the `chat:killAgents` path is **not** a killer — `FRu = F_.clearCommandQueue`
> (`python3 ctx.py '[,;{]FRu=(?!=)'`). The killing is done by `O()`, i.e. `Xrl`. So the label
> *"stop all agents"* is accurate only for the two agent types it enumerates.

### 2.3 Per-class matrix

| Unit class | What halts it (operator lever) | Stoppable **without** killing the parent? | Work recoverable? | Latency | Evidence |
|---|---|---|---|---|---|
| **pane session** (own `claude` process) | `ctrl+c` ×2 / `ctrl+d` in its own pane · our `bin/cc-teardown` · SIGTERM to pid | **n/a — it is a parent.** Killing it takes *its* context, never the operator's | **Yes** — transcript on disk, `claude --continue` / `--resume` | keystroke-immediate | keybinding table § 2.2; `ls bin/ \| grep -iE 'teardown\|reap'` → `cc-teardown`, `cc-reaper` |
| **named teammate** `Agent({name})` (`in_process_teammate`) | `/tasks` → `x` · `ctrl+c` / `ctrl+x ctrl+k` (in `Xrl`) · `TaskStop` by agent-id `name@team` · our `shutdown_request` + `cc-teardown` | **Yes** | **Partial** — controller aborted, task marked `killed`; no resume handle | abort synchronous; **pane teardown bounded at 10 s** and *may fail open* | `function Qsn`: `d.abortController?.abort()` then `Na(l(),JEd=1e4,…)`; on failure logs *"the backend could not find/kill the pane; its separate `claude --agent-id` process may still be running"* — **a stop that reports success can leave a 382 MB process alive** |
| **unnamed subagent** `Agent()` (`local_agent`) | `Esc` **iff still inside the in-flight turn** · `ctrl+c` · `ctrl+x ctrl+k` (double-press) · `/tasks` → `x` · `TaskStop` | **Yes** | **No resume**; a `stoppedByUser` marker is persisted (`RIe` → `dG_` → `p$e`) so the transcript survives for AUDIT | immediate | `Xrl`/`hc` § 2.2; `function RIe` |
| **Workflow agent / run** (`local_workflow`) | **`/tasks` → `x`** (list) or detail dialog **`x stop workflow` / `p pause` / `r restart`**, plus per-agent **skip/retry** · `TaskStop(task_id)` from the **parent agent** · SDK `control_request{subtype:"interrupt"}` · `--max-budget-usd` (print mode only) · parent-turn abort *with pending tool uses* | **Yes** — this is the finding | **YES, best of any class.** `Workflow({scriptPath:'…', resumeFromRunId:'…'})` — *"completed agents return cached results"*. `pause` emits that resume prompt for you | `abortController.abort()` is synchronous on the controller; in-flight agent HTTP unwinds at its next await (**not measured**) | `function oEe`(=killWorkflowTask)`→GRo`, and `GRo`: `i.abortController?.abort()` … `status:r, abortController:void 0, agentControllers:void 0`; `function Rft`(=pause); `function zRo`(=buildResumePrompt); `sdk-tools.d.ts:2592` *"Stop the prior run first (TaskStop) before resuming."* |
| ↳ *per-agent inside a run* | detail dialog `skip` / `retry` | Yes | the run continues | immediate | `FSd`: `i.agentControllers?.get(t).abort(new DOMException("user-skip","AbortError"))` |
| **`--bg` worker** | **`claude stop <id>`** · `claude kill` · `claude respawn <id>\|--all` · `claude rm <id>` · `claude attach`/`logs` to look first | **Yes** — separate session | **YES, explicitly**: *"Its conversation is kept; resume it later with `claude attach <id>`"* | ⚠️ **unreliable**: landed A5 measured **3/3 survived `claude stop` by ~13 min and needed `kill -9`** | `claude stop` → `Usage: claude stop <id>`; `claude stop zzz-no-such-job` → `No job matching 'zzz-no-such-job'. Run 'claude agents' to list running sessions.` — **all six verbs are UNDOCUMENTED in `--help`** (argv-level: `Suf(e)` gates on `new Set(["logs","attach","stop","kill","respawn","rm"])`) |
| **headless `claude -p`** | **`kill <pid>` only** · `--max-budget-usd` halts *its* background agents mid-run | Yes | **No** — output is the return value; killing loses it | signal-immediate | `--max-budget-usd <amount>  Maximum dollar amount to spend on API calls (only works with --print)`; bundle: `print budget halt: … stopping background agents` → `mmr(...)` |
| **cloud / `remote_agent`** | `/tasks` → `x` (dispatches `Iqs` ultraplan / `Dqs` remote-review / `W` plain) · claude.ai UI | Yes | session persists cloud-side | not measured | detail-dialog switch, § 2.1. **No live cloud session existed during this axis — INFERRED from code only.** |

### 2.4 "One place" does not exist — measured

```bash
ps -eo pid,command | grep -E '\.claude-220/node_modules/(\.bin/claude|.*bin/claude\.exe)' | grep -vc grep   # 21
claude agents --json                       # from this repo, default config dir -> 2 rows
for d in ~/.claude ~/.claude-secondary ~/.claude-tertiary ~/.claude-quaternary; do ls $d/sessions | wc -l; done
```

| quantity | value | note |
|---|---|---|
| live claude processes | **21** | 2 of them `--agent-id` teammates |
| `claude agents --json` from one config dir | **2** | it enumerates **only its own** `CLAUDE_CONFIG_DIR` |
| distinct session registries | **4** | `.claude` (`.claude-next` is the same dir, not a symlink — identical 3 rows), `-secondary` 2, `-tertiary` 3, `-quaternary` 3 |
| registry rows, all four summed | **12** | vs 21 processes ⇒ **~43% of live processes are in no registry the operator can list** |
| `waitingFor` populated in any row | **0 of 12** | the INTERRUPT field the screenshot promises was empty at every row at census time |

So the harness's own oversight surfaces partition along **config dir** (`claude agents`) and along
**parent session** (`/tasks`), and the operator's fleet partitions along neither.

---

## 3. What I could NOT measure, and why

| Not measured | Why | The command that would settle it |
|---|---|---|
| **Whether a PreToolUse hook actually fires for a Workflow agent's tool call** (item 4's crux) | I built the probe — isolated `CLAUDE_CONFIG_DIR` + `PreToolUse matcher:"*"` logging hook + a 1-agent `probe.workflow.js` — and the run died at **`Not logged in · Please run /login`**: credentials are per-config-dir, and reading the keychain to seed a copy was correctly **denied by the permission classifier**. I did not work around it. | With an operator-blessed *copy* of a live config dir: `CLAUDE_CONFIG_DIR=$COPY claude -p --permission-mode bypassPermissions "Call Workflow with scriptPath '<probe>'"` then `jq -r '.tool_name+" "+.transcript_path' hooks.jsonl` — a row whose `transcript_path` is under the workflow's `transcriptDir` is the proof. Fixture is preserved at `/private/tmp/claude-501/…/scratchpad/wfprobe/`. |
| **How long `x` takes to actually stop a running workflow** | Requires killing a live run. Forbidden by the read-only rule. | Launch a throwaway 3-agent workflow, `date +%s%3N`, `/tasks`+`x`, then read `endTime - <keypress>` from the task record. |
| **Whether `x` on `remote_agent` reaches a cloud session** | No cloud session was live. | — |
| **Whether ctrl+c mid-workflow leaves it running** end-to-end | Same read-only constraint. The *code* says it does (`Xrl` excludes `local_workflow`), and that is a strong static claim, but it is INFERRED, not observed. | Same throwaway run: `^C ^C`, then `/tasks` and read the workflow's status field. |
| **`mmr()` on parent exit** — I found the three call sites but not an exit-path one | Ran out of static budget. Matters because it decides whether *closing the parent* is a guaranteed workflow stop. | `python3 ctx.py 'mmr\('` with a wider window, or observe a live parent exit with a workflow running. |

**Two stale premises corrected** (both were reasonable when written):

- The landed `orchestration-units-2026-08-19.md` L1 risk cell — *"no `claude stop` (not a bg job), no
  registry row … the only lever is killing the parent session"* — is **refuted for the harness**:
  `killWorkflowTask`, `pauseWorkflowTask`, `skipWorkflowAgent`, `retryWorkflowAgent` all ship, all are
  wired to keys, and `TaskStop` accepts the task id. Its *"in anything we own"* qualifier remains
  exactly true, and that is the real gap.
- `~/.claude-versions/current` → **2.1.114**, but **zero** live processes run from it; all 21 run
  `~/.claude-220`. Any capability claim read out of `current` would have been a claim about a binary
  nothing executes.

---

## 4. Is a kill switch buildable? — and for the paneless ones specifically

### 4.1 A hook-based **brake** reaches every in-process class, workflow agents included

Two independent lines of evidence that a workflow agent's tool calls traverse the ordinary
permission/hook pipeline:

- The permission-prompt labeller has a **dedicated workflow branch** keyed on the run id — meaning a
  workflow agent's tool call can raise a permission prompt *in the parent's UI*:
  ```js
  function O0s(e){ let t=e.spawnedByWorkflowRunId;
    if(t!==void 0) return {type:"workflow-agent", workflowName: …};   // vs "subagent" / "teammate"
  ```
- The workflow agent runs on a **forked `toolUseContext`** produced by the same context-derivation
  function used for subagents (`spawnedByWorkflowRunId: t?.spawnedByWorkflowRunId ?? e.spawnedByWorkflowRunId`,
  alongside `requireCanUseTool`, `agentId`, `agentType`) — not a bypass path.
- The landed doc measured the same conclusion from the other side (its § unit table: workflow agents
  get *"tool hooks only, under the parent's session id"*, while `SessionStart` does not fire).

⇒ **A `~/.claude/HALT`-style file flag checked by a `PreToolUse` matcher `*` hook that returns `deny`
reaches unnamed subagents, workflow agents, teammates and pane sessions alike.** This is the only
mechanism in the inventory that is *uniform across classes*.

🚨 **But name it correctly: that is a BRAKE, not a STOP.** A denied tool call does not abort the agent
— it returns a refusal, the agent keeps its turn, keeps thinking, keeps spending tokens, and
terminates only when it gives up. It converts *runaway action* into *runaway talk*. Against the
operator's fear ("things blindly going on by themselves") it removes the blast radius but not the
spend, and it is the correct thing to build **first** precisely because it is the only lever that is
uniform, out-of-band, and needs no keyboard at the parent.

*(Note the asymmetry the landed doc already measured: our `Agent` **PreToolUse spawn** matcher does
not fire for workflow agents — 9 agents minted, 0 `agent-tool` ledger rows. The spawn gate is blind;
the per-tool gate is not. A kill switch must therefore live at **tool** granularity, not spawn.)*

### 4.2 The true STOP for paneless units exists — and is currently unreachable

`mmr()` is the harness's own sweep, and its filter is exactly the paneless in-process set:

```js
function JTe(e){ if(e.type==="local_agent") return !Ux(e); return e.type==="local_workflow" }
function mmr({taskRegistry:t,setAppState:r}){
  for (let n of Object.values(t.all())) { … if(!Gw(n)||!JTe(n)) continue;
    aMs(n.type)?.kill(n.id, t, r, "system"); … } }
```

Three call sites, MEASURED (`python3 ctx.py 'mmr\('`):

1. **engine loop** — turn aborted (`G?.signal.aborted`) with tool results still queued;
2. **`--print` budget halt** — `--max-budget-usd` exceeded → stderr *"Budget limit reached ($X of $Y);
   stopping background agents."* → `mmr(...)`;
3. **`control_request` `subtype:"interrupt"`** (and `rewind_conversation` with `interrupt_if_running`).

Site 3 is the buildable one-place kill switch: a single control message per session kills every
`local_agent` and `local_workflow` under it. **It is EXISTS-but-NOT-REACHABLE for this fleet**: the
control channel is the SDK stream (`--input-format stream-json`) or Remote Control, and our sessions
are interactive TUIs started by `handoff-fire`. Making it reachable is a launch-flag decision, not a
new mechanism.

`TaskStop` cannot substitute: it is **agent-facing and ownership-gated** —
`Task ${u} is owned by ${…}; agent ${i} cannot stop it.` (`"not_owner"`). It lets a lead stop its own
workflow; it gives the *operator* nothing.

### 4.3 Prevention levers that are reachable today (settings/env, no code)

| lever | effect | source |
|---|---|---|
| `CLAUDE_CODE_DISABLE_WORKFLOWS` (+ a managed-settings twin) | *"Disable the Workflows feature"* — the class cannot be created | `grep -c CLAUDE_CODE_DISABLE_WORKFLOWS` → 7, with the settings-schema description alongside |
| `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS` | removes the backgrounding path | same env-name block |
| `--max-budget-usd` | hard dollar halt → `mmr()` | `claude --help` (⚠️ **`only works with --print`** — useless for the interactive fleet) |
| workflow script `budget.total` | author-time cap, per run | landed doc L1 |

---

## 5. The design constraint this axis imposes

**A unit may carry overseen work only if the operator can stop it from somewhere other than its own
keyboard.** By that test:

| | verdict today |
|---|---|
| **pane session** | ✅ safe — `cc-teardown` is out-of-band and ours |
| **named teammate** | ✅ safe, with a caveat to fix: `Qsn`'s pane teardown is bounded at 10 s and *fails open*, logging that the separate `claude --agent-id` process may still be running. A stop that returns success while a 382 MB process survives is a **false negative in the STOP column** — and it is the class we already run most. |
| **unnamed subagent** | ✅ safe — bounded by the parent's turn, and reached by ^C / ^X^K |
| **`--bg` worker** | ⚠️ conditionally safe — `claude stop <id>` is out-of-band and recoverable, but **3/3 measured needed `kill -9`**, and the verb is undocumented so nothing in our tooling calls it |
| **Dynamic Workflow** | 🚨 **NOT safe for unattended overseen work.** Its only stop is a human at that parent's keyboard pressing `/tasks`+`x`. Nothing we own, nothing scriptable, nothing cross-session. Both keys the operator would instinctively press (`Esc`, `ctrl+x ctrl+k`) miss it. It is also the class with the largest measured blast radius (229 agents / 7.2 h / 39 pp). |
| **headless `-p`** | 🚨 no named stop — `kill <pid>` and the work is gone |

**Therefore, for "more than 15 overseen sessions":**

1. **Every fan-out unit must be addressable by something other than a pane.** Today STOP is
   pane-shaped, so oversight cost is O(units) in *operator walks*. That is the mechanism that makes 15
   feel like a ceiling — not memory, not load.
2. **Build the brake before adding units.** A `PreToolUse` halt-flag is the only lever proven uniform
   across every in-process class, and it is buildable now with no harness change. Call it a brake in
   the docs, so nobody mistakes it for an abort.
3. **Make the real stop reachable, don't reinvent it.** `mmr()` already does exactly what a fleet kill
   switch should do. Reaching it costs a launch-flag decision (`--input-format stream-json` /
   Remote Control on fired sessions), not a new subsystem. Until then, `cc-halt` must drive
   `/tasks`+`x` by keystroke into each parent, which is a *simulation* of oversight, not oversight.
4. **Until 2 and 3 land, gate the Workflow class by policy.** `CLAUDE_CODE_DISABLE_WORKFLOWS` on
   unattended fired sessions, and `budget.total` mandatory on any workflow authored in a session the
   operator is not watching. A workflow started by a session nobody is sitting at satisfies SEE
   (it is in `/tasks`) and fails STOP — which is precisely the operator's stated fear, and the one
   combination this wave must not ship.

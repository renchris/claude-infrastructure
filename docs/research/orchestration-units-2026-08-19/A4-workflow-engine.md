# A4 — The Dynamic Workflow engine: what it actually does differently

Date: 2026-08-19 · Binary: Claude Code **2.1.220** (`/Users/chrisren/.claude-220/node_modules/@anthropic-ai/claude-code/bin/claude.exe`)
Method: static read of the shipped binary + reconstruction of 160 historical workflow runs across all 4 account stores. Read-only; **nothing was spawned, killed or stopped**.

---

## 1. Verdict (≤5 lines)

1. **Workflow agents take NO pane and NO OS process.** The script runs in an in-process `node:vm` context; each agent is an in-process async generator (`s6(...)`). Positive-controlled: the workflow module contains **0** occurrences of `child_process` / `spawn(` / `execFile` / `--agent-id` while the binary holds 138 / 119 / 42 / 19 of them elsewhere. **MEASURED.**
2. **"50–200 concurrent" is FALSE as concurrency, TRUE as throughput.** Largest run ever on this box: **229 agents over 7.2 h wall** — true simultaneous peak **48**, and 39 of the 40 largest runs peak at **exactly 8**. **MEASURED.**
3. **The cap is `min(16, max(2, cores−2))` PER WORKFLOW RUN — 8 on this box** — confirmed twice, independently: read out of the binary (`Xq_`/`Qq_`) and reproduced by every historical run. The lone 48 is **8 concurrent `Workflow` tool calls × 8 each**, not one run exceeding its cap. **MEASURED.**
4. **Free-hand `Agent()` fan-out is NOT ungoverned** — it is capped at **20 concurrent** (`CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS`, default `Et_=20`) and 200/session lifetime. But **named split-pane teammates bypass the concurrency cap entirely** (lifetime cap only) — and those *are* real processes with panes. **That is the ceiling-consuming path, and it is the least-governed one.** **MEASURED.**
5. **The workflow cap is NOT configurable** — no env var reads it; the only lever is `os.cpus().length`. The free-hand cap *is* configurable, and raising it is the wrong lever (see §5). **MEASURED.**

---

## 2. The numbers, with the command that produced each

### 2a. The concurrency cap, read out of the binary

| Constant | Value | Meaning | Provenance |
|---|---|---|---|
| `Xq_(e)` | `Math.min(16, Math.max(2, e-2))` | the cap formula | MEASURED |
| `Qq_` | `Xq_(os.cpus().length)` = **8** here | **local** workflow agent concurrency, per run | MEASURED |
| `Zq_` | **50** | **remote** (cloud) agent concurrency, per run | MEASURED |
| `QSd` | **1000** | lifetime `agent()` calls per workflow run | MEASURED |
| `Et_` | **20** | `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS` default | MEASURED |
| `vt_` | **200** | `CLAUDE_CODE_MAX_SUBAGENTS_PER_SESSION` default | MEASURED |
| `KSd` / `aj_` | 400 / 5 | preview truncation / StructuredOutput retry cap | MEASURED |

```
$ grep -o '.\{120\}Xq_.\{200\}' cc220-strings.txt
…function Xq_(e){return Math.min(16,Math.max(2,e-2))}…
…JSd=require("os"),XSd=require("util");Qq_=Xq_(JSd.cpus().length),ej_=`Workflow agent() call cap reached (${QSd})…
```
```
$ node -e 'const e=require("os").cpus().length; console.log(e, Math.min(16,Math.max(2,e-2)))'
10 8
```
(`cc220-strings.txt` = `strings -n 6 bin/claude.exe`, 394,254 lines. The brief's `cli.js` does not exist on 2.1.220 — see §3.)

The limiters are constructed once per run inside `tTd(...)`:
```js
B = CB(Qq_, K),   // K = LOCAL agent runner   → 8 slots
j = CB(Zq_, re)   // re = REMOTE agent runner → 50 slots
```
Excess calls **queue**; they are not dropped. `QSd`/budget breaches throw `WorkflowAgentCapError` / `WorkflowBudgetExceededError` and fire telemetry `tengu_workflow_agent_cap_exceeded` / `tengu_workflow_budget_cap_exceeded`.

The tool's own doc string agrees, and states the per-run scope explicitly (QUOTED-FROM-BINARY):
> "Concurrent agent() calls are capped at min(16, cpu cores - 2) **per workflow** — excess calls queue and run as slots free up. You can still pass 100 items to parallel()/pipeline() and they all complete; only ~10 run at any moment. Total agent count across a workflow's lifetime is capped at 1000 … A single parallel()/pipeline() call accepts at most 4096 items; passing more is an explicit error, not a silent truncation."

⚠️ **Doc bug**: "only ~10 run at any moment" is true only on a 12-core box. On this 10-core box it is **8**. The formula in the same sentence is correct; the illustrative number is not. Do not quote the "~10".

### 2b. How a workflow agent is executed — in-process, not a process

`lTd(...)` builds the sandbox with Node's `vm` module, and binds the four host functions into it:
```js
Hsn = R(require("vm"));
let T = Hsn.createContext({__proto__:null, log:…, phase:…, console:m, budget:g,
        setTimeout:y.setTimeout, clearTimeout:y.clearTimeout},
        {codeGeneration:{strings:!1, wasm:!1}});
for (let [O,H] of [["agent",p.agent],["parallel",p.parallel],["pipeline",p.pipeline],["workflow",I]])
    Object.defineProperty(T, O, {value: D(MRo(H)), …});
```
The local runner `K(...)` then drives the **same async generator the Task/Agent tool uses**:
```js
await rG(Wr, async () => { for await (let Dn of s6({
    agentDefinition: Ue, promptMessages:[zr({content:It})], toolUseContext: Vt,
    canUseTool: t, isAsync:!1, querySource: SBe(Ue.agentType, HT(Ue)),
    availableTools: xe, requiresStructuredOutput: Fe!==void 0,
    transcriptSubdir: n ? `workflows/${n}` : void 0,
    spawnedByWorkflowRunId: n, override:{agentId: yr, agentContext: Wr},
    model: Ee?.model, onQueryProgress: ni, worktreePath: gt })) { … } })
```
with `agentContext = {agentType:"subagent", isBackgroundAgent:true, depth: HI(ve)+1, …}`.

**Positive control for the "no spawn" null** (rule 5) — token counts, workflow module (29,850 B slice) vs. the whole binary:

| token | workflow module | whole binary |
|---|---|---|
| `child_process` | **0** | 138 |
| `spawn(` | **0** | 119 |
| `execFile` | **0** | 42 |
| `--agent-id` | **0** | 19 |
| `use_splitpane` | **0** | 3 |
| `require("vm")` | **1** | 7 |
| `createContext` | **1** | 77 |
| `s6(` | **1** | 11 |

The instrument can see all of those strings; it finds none of the spawn family inside the workflow engine. **INFERENCE FROM CODE, positive-controlled — not a live `ps` observation** (see §3).

Inheritance, from the same slice: model resolves via `ite(FVe(Ue, U.options.mainLoopModel), U.options.mainLoopModel, Ee?.model, ze.mode)` — i.e. **inherits the parent's main-loop model** unless `opts.model` overrides; effort via `bq(Ee?.effort)` likewise. Account is inherited absolutely — same process, same credential. There is **no pool** and no reuse: one generator per `agent()` call.

### 2c. Our own history — the direct test of "50–200 concurrent"

Corpus: **160** `wf_*` run dirs across `~/.claude{,-secondary,-tertiary,-quaternary}/projects`.
```
$ find /Users/chrisren/.claude*/projects -type d -name 'wf_*' | wc -l
160
```
Concurrency reconstructed by sweep-line over each agent's `[first, last]` transcript timestamp (`scratchpad/wfconc.py`):

| N agents | **max concurrent** | wall (s) | median agent (s) | run |
|---:|---:|---:|---:|---|
| **229** | **48** | 25,905 | 317 | `wf_0f8a38e6-82f` (doc-classifier) |
| 83 | **8** | 1,218 | 73 | `wf_d20aadf6-502` |
| 63 | **8** | 9,489 | 859 | `wf_96b0397f-c1d` |
| 62 | **8** | 6,500 | 431 | `wf_edda7d3d-3d8` |
| 59 | **8** | 1,035 | 95 | `wf_74996d36-505` |
| 58 | **8** | 27,895 | 1,696 | `wf_e16552fc-ae6` |
| … | **8** for every one of the next 35 rows | | | |

**Largest N ever attempted: 229. Largest true simultaneous: 48. Modal peak: exactly 8.**

The 48 decomposes cleanly. That dir holds **1 session, 9 promptIds** — i.e. nine separate `Workflow` tool invocations writing into one run dir:

| promptId | N | **max concurrent** | window (UTC) |
|---|---:|---:|---|
| 47a85630… | 6 | 4 | 08:49:22–08:49:29 |
| 78fb42e5… | 34 | **8** | 15:08:58–16:01:07 |
| d0c4606d… | 36 | **8** | 15:09:18–16:00:17 |
| 8442bb40… | 33 | **8** | 15:09:20–15:57:29 |
| 483aa8c0… | 40 | **8** | 15:09:36–15:58:13 |
| 86b081fa… | 39 | **8** | 15:09:44–15:58:46 |
| f1af30db… | 6 | 6 | 15:09:49–15:24:02 |
| edd72c01… | 6 | 6 | 15:09:57–15:27:41 |
| 0c5bf1d5… | 29 | **8** | 15:11:16–15:57:25 |

**No invocation ever exceeded 8.** Eight invocation spans are live at the 48-peak; the peak is their sum. Time spent above 8 across the whole 7.2 h run: **2,934 s = 11.3%**. No agent ran longer than 1,861 s, so nothing is an artefact of a hung tail.

⚠️ Method caveat, stated so it cannot flatter the result: `[first, last]` transcript timestamp is an **upper bound** on an agent's slot occupancy (the slot frees at generator end; the last write is at or before that). The estimator can therefore **over**-count and never under-count — which makes "exactly 8, 39 times out of 40" a *stronger* result, not a weaker one.

### 2d. What governs free-hand fan-out — and the hole in it

The Agent-tool gate (MEASURED, binary offset ≈ 19,845,208):
```js
let N = (lt=!1) => { …budget check…
    let gt = XYr(), Dt = l.taskRegistry.getTotalAgentSpawns();
    if (Dt >= gt) throw …`Subagent spawn limit reached (${Dt} of ${gt} …)`…;
    l.taskRegistry.incrementTotalAgentSpawns() },
  P = () => { let lt = wHu();
    if (l.taskRegistry.getConcurrentSubagents() < lt) return;
    if (Ke("tengu_amber_kestrel",!1)) return;                        // gate bypass
    let gt = l.getAppState();
    if (EK(l.rootToolSurface.mainLoopModel, gt.effortValue, gt.ultracode)) return;  // ultracode+xhigh bypass
    return …`Concurrent subagent limit reached. You can run ${lt} subagents at once.` },
  U = async () => { let lt = P(); if (lt) throw await at(), lt;
                    return l.taskRegistry.takeConcurrencySlot() };

if (b && i && !L && !s && !a) {          // b = teamContext, i = `name` param
    N();                                 // ← lifetime cap ONLY
    let et = await cvd({name:i, prompt:e, description:r, use_splitpane:!0, …}, l, d);
    return {data:{status:"teammate_spawned", …}} }
```
```js
function wHu(){return Z.CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS ?? Et_}   // Et_=20
function XYr(){return Z.CLAUDE_CODE_MAX_SUBAGENTS_PER_SESSION ?? vt_}  // vt_=200
function EK(e,t,r){return r===!0 && LA() && Goe(e,t)==="xhigh"}        // ultracode + xhigh
```

**Four findings, in descending order of consequence for the ~15 ceiling:**

1. **The named split-pane teammate branch calls `N()` but never `U()`.** It is bounded by the **200/session lifetime** cap and by budget — **not** by the 20-concurrent cap. This is the *only* branch that reaches `cvd({… use_splitpane:true})`, i.e. the only one that creates a pane and a `claude.exe` process. **The path that consumes the operator's real ceiling is the one with no concurrency governor.**
2. Plain (unnamed) `Agent()` subagents *do* take `takeConcurrencySlot()` → capped at 20 concurrent, 200/session. In-process, no pane.
3. **Two documented bypasses of the 20-cap**: the `tengu_amber_kestrel` gate, and `ultracode === true && effort === "xhigh"`. Under those, plain subagent fan-out is bounded only by 200/session.
4. **Workflow agents and free-hand subagents draw on two disjoint pools.** `takeConcurrencySlot` occurs **0** times in the workflow module (positive control: 6 occurrences in the binary overall). A workflow's 8 do not consume any of the 20; running both at once gives 28 concurrent in-process agents in one session, and no single counter sees them all.

Live corroboration that `--agent-id` = teammates, not workflow agents:
```
$ ps -Ao pid,ppid,rss,command | grep 'claude.exe' | grep -- '--agent-id'
 8435  7723 538432 …/bin/claude.exe --agent-id A9-prior-art@session-84bde2e9  --agent-name A9-prior-art …
17602 17203 466448 …/bin/claude.exe --agent-id A10-hostile-reviewer@session-84bde2e9 --agent-name A10-…
28505 27534 501712 …/bin/claude.exe --agent-id A11-redteam-widening@session-84bde2e9 --agent-name A11-…
```
`--agent-name` is the `name:` parameter of the teammate branch. No workflow has ever produced such a process — it cannot, there is no spawn site.

### 2e. The remote lane — the likely true source of "50 agents"

`agent({isolation:'remote'})` takes the `Zq_ = 50` limiter and runs `re(...)`, which calls `Use({initialMessage, source:"workflow_remote_agent", tags:["workflow-remote-agent"], branchName, …})` — it **creates a cloud session** and awaits `a0s(remoteSessionId, signal)`. These agents consume **zero local CPU, zero local RAM, zero panes**; the local process only holds an awaited promise. **50 concurrent remote agents is a real, supported number and it does not touch the box's ceiling at all.**

### 2f. Configurability

| Cap | Env var | Default | Configurable? |
|---|---|---|---|
| Workflow **local** concurrency | **none** | `min(16, max(2, cores−2))` = 8 | ❌ **No** — computed at module init from `os.cpus().length`, no `??` fallback |
| Workflow **remote** concurrency | none | 50 | ❌ No |
| Workflow lifetime agents | none | 1000 | ❌ No |
| Free-hand concurrent subagents | `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS` | 20 | ✅ Yes |
| Free-hand lifetime subagents | `CLAUDE_CODE_MAX_SUBAGENTS_PER_SESSION` | 200 | ✅ Yes |
| Subagent nesting depth | `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` | (min 1) | ✅ **set to 1 on this box** |
| Parallel tool-use | `CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY` | not resolved | ✅ Yes |
| Workflows on/off | `CLAUDE_CODE_DISABLE_WORKFLOWS`, `CLAUDE_CODE_WORKFLOWS` | — | ✅ Yes |

Full enumeration (MEASURED — regex over the binary's env-var registry) found **no** `*WORKFLOW*CONCURREN*` knob; the only workflow env vars are `CLAUDE_CODE_DISABLE_WORKFLOWS`, `CLAUDE_CODE_WORKFLOWS`, `CLAUDE_CODE_WORKFLOW_SIZE_WARNING_AGENTS`, `CLAUDE_CODE_WORKFLOW_SIZE_WARNING_TOKENS`.

Live config on this box:
```
$ grep -n 'SPAWN_DEPTH' ~/.zshrc
484:  export CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1
```
**Consequence, previously unrecorded:** workflow agents are created at `depth = HI(ve)+1 = 1`. With the depth cap at 1, a workflow agent **cannot spawn any further subagent**. Our fan-out is structurally two levels deep, by a setting in `.zshrc` that nothing in the repo documents.

**Is raising the free-hand cap safe?** Not by itself, and not as the lever you want. Per `scaling-bottlenecks-2026-08-09.md` the ranked wall is memory > active-load > self-imposed caps > quota; in-process subagents add heap to one process rather than a new ~500 MB image, so 20 → 40 costs *heap in one session* (bounded by that session's window and the Bun heap), not a new process. The dangerous knob is the un-capped one: **named teammates**, which cost a real `claude.exe` at 460–600 MB RSS **and** a pane, and have no concurrency governor at all — 200 of them is permitted by the binary and would kill the box long before it refused.

---

## 3. What I tried that did NOT work / could not be measured

1. **The brief's premise about the artifact is wrong, and it matters.** There is no `cli.js` in 2.1.220 — the package ships one 256,908,272-byte compiled Mach-O arm64 `bin/claude.exe` (Bun single-file executable); `cli-wrapper.cjs` is a documented fallback that "is never invoked". Everything here came from `grep -a` / `strings` / `dd` slicing of that binary. Any future axis that plans to `node -e` the bundle needs to know this.
2. **`maxConcurren*` is a complete red herring.** All 27 hits are Bun's HTTP/2 runtime (`maxConcurrentStreams`, `kDefaultSettings`, `ClientHttp2Session`). Reasoning from that name would have produced a confident, entirely false answer. The real symbol is `Xq_`, and only `Math.min(16` finds it.
3. **Could not locate the enforcement site of the documented 4096-item cap.** It appears only in the tool's prose. The single `4096` inside the workflow module is unrelated — a max serialized-schema length for the auto-mode permission classifier (`if(Me.length>4096) ve="output schema too large to classify safely"`). The cap is presumably enforced inside the `parallel`/`pipeline` host hooks (`KHs`/`USd`), which I did not slice. **Treat 4096 as QUOTED-FROM-DOC, not verified.**
4. **I did not run a live workflow probe.** A `claude -p` firing a workflow would have given a direct `ps` observation of "8 agents, 0 new processes" — but it spends quota and adds load to a box already carrying the 15-session fleet mid-wave. The process claim therefore rests on code + the §2b positive control, not on watching a live run. This is the one load-bearing claim in the file without a runtime observation.
5. **Could not measure the marginal memory of an in-process workflow agent.** RSS cannot be attributed per-agent when agents are generators in one heap, and `footprint -p` on the parent measures the whole session. A differential (parent RSS before/during a known-N workflow) needs the live probe in (4).
6. **`journal.jsonl` carries no timestamps** — only `{type:"started"|"result", key, agentId}`. Concurrency had to be reconstructed from the per-agent transcripts instead; the journal is a resume ledger keyed by a sha256 of (prompt, opts, script), which is how `resumeFromRunId` skips completed agents.
7. **Two `wf_edda7d3d-3d8` rows are one run**, mirrored into `~/.claude/` and `~/.claude-tertiary/`. The 160-dir census is therefore a slight over-count of distinct runs; it does not affect any concurrency figure (per-dir analysis is identical).

---

## 4. Open questions for the verifier

1. **Run the live probe I declined.** One headless `claude -p` invoking a workflow with 12 trivial agents, sampled with `ps -Ao pid,rss,command | grep claude.exe` at 2 s intervals. Predictions to falsify: (a) **zero** new `claude.exe`, (b) exactly 8 `workflow_agent` progress groups live at once, (c) parent RSS rises then falls. If (a) fails, §2b is wrong and this whole verdict inverts.
2. **Confirm the teammate branch really skips `U()`.** This is my highest-consequence claim (it says the pane-spawning path is the *least* governed one). Read the same region independently; the discriminator is whether `takeConcurrencySlot()` is reachable from the `use_splitpane:!0` branch. If it is, teammates are capped at 20 and the ceiling story changes.
3. **Find the 4096-item enforcement**, or establish that it does not exist. A `parallel()` with 5,000 items would settle it in one call.
4. **Was `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1` deliberate?** It silently forbids workflow agents from spawning anything. `.zshrc:484` has no comment and no repo doc. If unintentional, removing it changes the shape of every fan-out we can express.
5. **Do the two pools (8 workflow + 20 subagent + N teammates) interact anywhere downstream?** They are disjoint at the *admission* layer. They are certainly not disjoint at the API/quota layer or at `CC_FIRE_MAX_LOAD_PER_CORE`. Someone should establish what the aggregate looks like to the account router, which today counts sessions and is blind to all 28 in-process agents.
6. **Cross-check against A1.** A1 owns "are agents separate OS processes". My answer is *split*: workflow + plain subagents = no; named teammates = yes. If A1 concludes uniformly "yes", one of us mis-attributed the `--agent-id` population — reconcile on `--agent-name`, which only the teammate branch sets.

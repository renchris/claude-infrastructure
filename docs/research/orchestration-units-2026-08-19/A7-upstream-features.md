# A7 — Upstream feature sweep: what Anthropic ships that moves work OFF this box

Date: 2026-08-19 · Binary under test: **2.1.220** (`/Users/chrisren/.claude-220/...`) · Docs read: current (2.1.235-era)
Method labels: **[M]** measured here · **[Q]** quoted from official doc · **[I]** inferred (reasoning stated)

---

## 1. Verdict (≤5 lines)

1. **`--cloud` is the only real off-box lever, it exists in OUR 2.1.220 binary, and it costs zero local slots** — but on 2.1.220 it **refuses `--print` and requires an interactive TTY**, which is precisely the "higher friction of self-managing" the operator reported. **[M]**
2. **`isolation:"remote"` is GATED OFF and fails SILENTLY-DOWNGRADED**: when the gate is false it does not error, it **falls back to a local worktree agent** with only a debug log — so a plan that "moved work off-box" via remote isolation would in fact spend local slots. **[M]**
3. **The "50-200 agents" observation is a THROUGHPUT number, not concurrency.** 2.1.220 enforces **concurrent ≤ 20** and **total-per-session ≤ 200**; the 200 is a lifetime spawn counter, and 2.1.224 deleted it entirely. **[M]**
4. **Remote agents skip the local concurrency check; local ones do not.** One measured branch in the Agent tool proves the two loci are accounted differently. **[M]**
5. **Headless is real but smaller than hoped: ~185 MB vs ~281 MB phys_footprint (~0.66×), and that comparison is confounded by context age** — it is not a clean 2×, and I could not de-confound it. **[M]**

---

## 2. Numbers table (command → output)

### 2a. The local concurrency caps actually compiled into 2.1.220

Strings cached once: `LC_ALL=C strings -a -n 6 claude.exe > cc220-strings.txt` (412,384 lines).
Positive control on that corpus: `remote_agent` → 58 hits (present); `self-hosted-runner` → **0** hits — a feature the changelog dates to 2.1.224, correctly ABSENT from our 2.1.220. The corpus is therefore complete *and* version-accurate, so a null from it is evidence.

| Cap | Reader (from binary) | Default | Env override | Evidence |
|---|---|---|---|---|
| Concurrent subagents | `function wHu(){return Z.CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS??Et_}` | **20** (`Et_=20`) | `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS` | [M] |
| Total spawns per session | `function XYr(){return Z.CLAUDE_CODE_MAX_SUBAGENTS_PER_SESSION??vt_}` | **200** (`vt_=200`) | `CLAUDE_CODE_MAX_SUBAGENTS_PER_SESSION` | [M] |
| Subagent nesting depth | `function bee(){...}` | **3** (`aHu=3`, gated `tengu_hazel_trellis`) | `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` | [M] |

```
python3 win.py 'CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS??' 120 120 2
→ function wHu(){return Z.CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS??Et_}
  function XYr(){return Z.CLAUDE_CODE_MAX_SUBAGENTS_PER_SESSION??vt_}
  ... var zGe,Gpo,Air,Et_=20,vt_=200,wt_=200
```

**This is the direct answer to the operator's "Dynamic Workflows run 50-200 agents fine".** 200 is the literal per-session lifetime spawn cap and 20 is the concurrent cap. A workflow reporting "200 agents" ran ≤20 at a time. (Method rule 6.)

Two documented bypasses of the *concurrent* cap exist in the same function — the feature flag `tengu_amber_kestrel`, and an `EK(mainLoopModel, effortValue, ultracode)` predicate. Either returning true skips the cap entirely. **[M]** I did not determine their live values — see Open Questions.

### 2b. Remote agents are accounted differently from local ones

From the Agent tool `call()` body (deobfuscated control flow, verbatim identifiers):

```js
let z = q === "remote",
    V = z || (o===true || W.background===true || G || B || !C && o!==false) && !j;
if (!z) {                       // ← LOCAL ONLY
   ...
   let lt = P(); if (lt) throw lt;   // P() = the concurrent-subagent cap
}
N(V && !z);                     // N() = budget + TOTAL spawn cap (runs for remote too)
```

**[M] Reading:** a remote agent **skips `P()`** (the concurrency slot) but still passes through **`N()`** (budget + total spawn cap). So remote work does not consume the local concurrent-agent budget — consistent with it not consuming a local process/pane — while still being counted for spend.

### 2c. The remote-isolation gate, and its silent downgrade

```js
function ian(){
  if(!Pc()) return false;                                            // firstParty auth only
  if(Z.CLAUDE_CODE_REMOTE) return false;                             // already inside a CCR session
  if(!zv()) return false;                                            // ms()?.accessToken != null  (claude.ai OAuth)
  if(!Rd().hasUsedRemoteSession || !Rt().hasRemoteEnvironment) return false;
  return Ke("tengu_neapolitan", false);                              // server feature flag, DEFAULT FALSE
}
```
`function Pc(){return xn()==="firstParty"}` · `function zv(){return ms()?.accessToken!=null}` **[M]**

And the failure mode — this is the load-bearing finding:

```js
let q = s ?? W.isolation;
if (q === "remote" && !ian())
  q = Z.CLAUDE_CODE_REMOTE || !KLs() ? undefined : "worktree",
  w("[remote agent] isolation:'remote' is unavailable "
    + (Z.CLAUDE_CODE_REMOTE ? "(already inside a CCR session); running as a local agent"
    : q==="worktree" ? "(no claude.ai login or feature gate off); falling back to isolation:'worktree'"
    : "(no claude.ai login or feature gate off) and no git root; running as a local agent"));
```

**[M] An ungated `isolation:"remote"` does not raise — it becomes a LOCAL worktree agent, logged only via the debug channel `w()`.** Any orchestration that assumed it had offloaded work would be spending local slots and would never see an error. This is the exact "conclusion must reach the enforcing store" failure shape.

### 2d. Is cloud available to THIS account today? — decisive probe

Probe (read-only GET, my own bounded probe, disclosed): `RemoteTrigger({action:"list"})` → `GET /v1/code/triggers`.

```
HTTP 200
{"data":[{ ... "job_config":{"ccr":{"environment_id":"env_017yBYRpWo1riDX3bs6h7fkV", ...}},
   "created_via":"http_api","last_fired_at":"2026-06-10T16:01:16.773934Z",
   "ended_reason":"run_once_fired", ...}],"has_more":false}
```
*(Payload redacted here: the single routine's prompt contains the operator's personal financial details. Only structural facts are recorded.)*

**[M] Established by that 200:** the account has cloud/routines API access; **a cloud environment already exists** (`env_017y…`, satisfying `hasRemoteEnvironment`); and a cloud job **has already executed** (`last_fired_at`, `run_once_fired`), i.e. cloud compute demonstrably runs for this account.

**Still unknown:** `tengu_neapolitan`, the server-side flag that alone gates `isolation:"remote"`. It is not cached in any local file I could read (`hasUsedRemoteSession`, `hasRemoteEnvironment`, `tengu_neapolitan`, `allow_remote_sessions` → **0 hits** across `~/.claude.json` and `~/.claude/*.json`). So `--cloud`-style cloud sessions are proven available; **in-session `isolation:"remote"` is NOT proven and most likely off** (flag default false).

### 2e. Which cloud flags exist in OUR binary (2.1.220), not just in the docs

`python3` count over the cached strings corpus:

| Token | Hits in 2.1.220 | Meaning |
|---|---|---|
| `--cloud` / `"--cloud"` | 33 / 4 | **present** |
| `--teleport` | 22 | **present** |
| `"--bg"` (`I6b=["--bg","--background"]`) | 5 | **present — but LOCAL** (see below) |
| `--remote-control` | 24 | present |
| `--bare` | 29 | present |
| `web-setup` | 11 | present |
| `/v1/code/triggers` | 14 | present |
| `CCR_FORCE_BUNDLE` | 6 | present |
| `tengu_neapolitan` | 2 | present (the gate itself) |
| `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` | 9 | present |
| **`self-hosted-runner`** | **0** | **absent — arrives 2.1.224** (this is the positive control) |

**`--bg` is a LOCAL background fork, not an off-box lever. [M]** Its module exports are `spawnBackgroundFork`, `deriveBackgroundSeed`, `canBackgroundSession`, `BackgroundAndExit`, `COORDINATOR_FORK_REFUSAL` — a forked local session, supervised by the local `claude.exe daemon run` process already visible in the machine facts. It **consumes the ceiling**. Do not confuse `--bg` with `--cloud`.

**The friction the operator felt is real and is in the binary [M]:**
```js
function Shp(e){ let t="--cloud";
  if(e.print && !e.hasPool && !e.isCloudAttach)
    return `Error: ${t} cannot be combined with --print.\nCloud sessions are interactive only...`;
  if(e.nonInteractive && !e.hasPool && !e.isCloudAttach)
    return `Error: ${t} requires an interactive terminal.\nNon-interactive invocations (piped stdout, --init-only, --sdk-url) run locally and would silently ignore ${t}...`;
```
So on 2.1.220 **`claude --cloud "<task>"` cannot be fired from a headless script** — it needs a TTY. Our `handoff-fire.sh` pane machinery supplies exactly that, so the fix is to fire `--cloud` *into a pane*, not from a subshell. The **follow-up** form is exempt (`isCloudAttach`) and IS scriptable: `claude -p "msg" --cloud <session-id>` queue-and-exit. **[Q]**

### 2f. Headless vs TUI local cost — measured, and honestly confounded

RSS is not the instrument (method rule 2); `/usr/bin/footprint` used for both.

| Subject | RSS | `phys_footprint` | Command |
|---|---|---|---|
| Live TUI agent `--agent-id A10-hostile-reviewer@session-84bde2e9`, pid 17602 | 470,800 KB | **281 MB** (peak 299 MB) | `/usr/bin/footprint -p 17602` |
| Headless `claude -p ... --output-format json`, pid 47509, t≈4 s | 425,248 KB | **185 MB** | `bash fp5.sh` (poll-from-t0, marker-anchored pgrep) |
| same, t≈16 s | 432,672 KB | **189 MB** | ditto |

**Ratio 185/281 ≈ 0.66 → a headless worker is ~1.5 sessions per TUI session's memory, NOT 2×. [M]**

🚨 **This comparison is confounded and I could not de-confound it.** The headless process was **seconds old with a near-empty context**; the TUI agent was long-lived with an accumulated context. Context size, not the Ink render loop, may be most of the 96 MB gap. The honest claim is only: *a fresh headless process footprints 185 MB.* A clean test needs same-age/same-context pairs — see Open Questions.

**Incidental correction to the brief's framing [M]:** the machine facts cite "8 agents at 460-600 MB RSS each". Measured, that agent's true `phys_footprint` is **281 MB — RSS overstates by 1.67×** (and 2.3× for the headless one). Any capacity arithmetic built on those RSS figures overstates memory pressure substantially.

### 2g. Execution-locus taxonomy, straight from the binary

`a1g = new Set(["local_agent","remote_agent","in_process_teammate","local_workflow"])`, prefix map
`l1g = {local_bash:"b", local_agent:"a", remote_agent:"r", in_process_teammate:"t", local_workflow:"w", mcp_task:"m"}` **[M]**

| Task type | Locus | Consumes local ceiling? |
|---|---|---|
| `local_agent` | this box, own process | **yes** |
| `in_process_teammate` | this box, in-process | yes (no extra process) |
| `local_workflow` | this box, in-process (`Workflow` tool) | yes |
| `local_bash` | this box | yes |
| **`remote_agent`** | **CCR cloud** | **no** |

Note `in_process_teammate` vs `local_agent` are *distinct* types — relevant to A1-A6's process-census axis; the 8 observed `claude.exe --agent-id …` OS processes are `local_agent`, not `in_process_teammate`.

### 2h. Scheduling: where each scheduler actually runs

| Mechanism | Locus | Evidence |
|---|---|---|
| **`CronCreate`/`CronList`/`CronDelete`** | **LOCAL, in-memory, session-scoped** | Tool schema **[Q]**: "Jobs live only in this Claude session — nothing is written to disk, and the job is gone when Claude exits"; `durable` — "Has no effect — durable persistence is not available"; "Jobs only fire while the REPL is idle"; recurring auto-expire after 7 days. **Holds a local session open ⇒ consumes the ceiling.** Not an off-box lever. |
| **`RemoteTrigger`** (`/v1/code/triggers`) | **CLOUD** | Schema **[Q]** + live `HTTP 200` **[M]**. This is the routines API. |
| **`/schedule` (routines)** | **CLOUD** | **[Q]** "Routines execute on Anthropic-managed cloud infrastructure … so they keep working when your laptop is closed." |
| `/loop` | LOCAL (in-session) | **[Q]** docs list it under in-session scheduling |
| Desktop scheduled tasks | LOCAL (Desktop app) | **[Q]** "choosing **Local** … runs on your machine" |

---

## 3. Per-mechanism verdicts

### AVAILABLE-NOW

**A. `claude --cloud "<task>"` — the primary off-box lever.**
- *What:* creates a full Claude Code session on Anthropic-managed cloud infra. **[Q]**
- *Invoked:* `claude --cloud "Fix the auth bug"`. Parallel is explicit: **[Q]** *"each `--cloud` command creates its own cloud session… you can start multiple tasks and they'll all run simultaneously."*
- *Costs:* **[Q]** *"There is no separate compute charge for the cloud VM"* — it draws only subscription rate limits, shared with all other usage. Zero local CPU/memory/pane.
- *Friction (measured, 2.1.220):* needs a **TTY**; refuses `--print`. The cloud VM **clones your GitHub remote at your current branch, not your local checkout** — unpushed work is invisible unless you set `CCR_FORCE_BUNDLE=1` (<100 MB, tracked files only). **[Q]**
- *Available to us:* **YES** — flags in binary **[M]**, cloud env + a fired cloud job on the account **[M]**.

**B. `claude -p "msg" --cloud <session-id>` — scriptable steering.** Queue-and-exit, `--output-format json` → `{ok, session_id, url}`. **[Q]** Runs from any machine logged in; sends no local state. **This is the programmatic monitor/steer surface the operator wanted** — it is exempt from the TTY rule (`isCloudAttach`). **[M]**

**C. `--teleport` — harvest.** `claude --teleport [<id>]`, or `/teleport` / `/tp` in-session, or `t` from `/tasks`. Requires clean tree, same repo (not a fork), branch pushed, same account. **[Q]** Note: **one-way** — you can pull cloud→terminal, never push terminal→cloud. **[Q]**

**D. Routines (`/schedule`, `RemoteTrigger`, POST `/fire`).** Cloud-executed, survives a closed laptop. Triggers: schedule (min interval 1 h), API bearer token, GitHub PR/release events. **[Q]** Proven live on this account **[M]**. Daily per-account run cap applies; one-off runs are exempt. **[Q]**

**E. `--bare` — the cheap local worker.** Skips auto-discovery of hooks, skills, plugins, MCP servers, auto memory, and CLAUDE.md. **[Q]** For a fleet whose per-session cost is inflated by exactly those (this repo's hook stack + MCP servers), this is the **highest-leverage local knob available today**. ⚠️ **[Q]** bare mode *"never reads OAuth credentials or the system keychain"* → it needs `ANTHROPIC_API_KEY`, i.e. it bills the API, **not** the Max subscription. That makes it an economics decision, not a free win. I did **not** measure `--bare` footprint (see §4).

### GATED

**F. `isolation:"remote"` on the Agent tool.** Five conjunctive conditions (§2c); the binding unknown is the server flag `tengu_neapolitan`, default false. **Fails silently into a LOCAL worktree agent.** **[M]**
*Probe that would settle it in one command:* run any agent with `isolation:"remote"` under the debug channel and grep for the literal `[remote agent] isolation:'remote' is unavailable`. Presence ⇒ gated off (and names which clause failed); absence + a `remote_launched` status with a `sessionUrl` ⇒ live.

**G. Interactive cloud attach (`claude --cloud <id>` without `-p`).** **[Q]** *"rolling out gradually; if you see `Attaching to an existing cloud session is not enabled for your account`, contact your Anthropic account team."* The `-p` queue form is unaffected.

**H. Agent teams inside cloud sessions.** **[Q]** Off by default; enable by adding `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` to the cloud **environment**'s variables. Relevant: a cloud session can itself fan out, so one cloud slot ≠ one agent.

### NOT-FOR-US

**I. `claude self-hosted-runner` (2.1.224).** Turns your own machines/containers into a target for web/mobile/desktop sessions. **[Q]** **Team and Enterprise plans only**, and **absent from our 2.1.220 binary (0 string hits) [M]**. Also note it would put work back ON our hardware — the opposite of the goal.

**J. `CLAUDE_CODE_TOOL_MEMORY_LIMIT` (2.1.233).** Memory cgroups for Bash tool commands — **Linux only**. **[Q]** Irrelevant on Darwin.

**K. Zero-Data-Retention orgs.** **[Q]** cannot use `/web-setup` or cloud sessions at all. Not our situation, recorded for completeness.

---

## 4. What I tried that did NOT work / could not measure

1. **`--bare` footprint — NOT measured.** It requires `ANTHROPIC_API_KEY` (bare mode ignores OAuth), which I did not have and would not mint. So the single most promising *local* lever is **unquantified**. This is the biggest gap in this axis.
2. **De-confounding headless vs TUI.** My headless sample was seconds old; the TUI comparator was long-lived. I could not construct same-age/same-context pairs read-only, so the 0.66× ratio conflates render loop with context size. Treat 0.66× as an upper bound on the *architectural* saving.
3. **`ugrep`, not `grep`.** The repo's Bash-tool rewrite made `grep -o -E '.{0,600}…'` die with `ugrep: error … exceeds complexity limits`, and `/usr/bin/grep` caps repetition at 255 (`invalid repetition count(s)`). Both were instrument failures, not absence. Fixed by caching `strings` once and windowing in Python.
4. **`$!` and inline pipelines under the zsh Bash tool** silently produced corrupt PIDs (`ps: Invalid process id: з�k`) three times. Only a real `bash` script file with marker-anchored `pgrep -f` worked — the repo's own "durable text in a FILE" rule.
5. **Two probe runs wasted (~$1.05)** because the model declined to actually `sleep 70`, so the process exited before my t=35 s sample. Fixed by polling from t=0.
6. **`tengu_neapolitan` / `hasUsedRemoteSession` / `hasRemoteEnvironment` are not on local disk** — 0 hits in `~/.claude.json` and `~/.claude/*.json`. This is a *proven* null only for those files; a statsig cache elsewhere may hold them.
7. **The `Workflow` tool is not exposed in this session** (`ToolSearch "select:Workflow"` → *No matching deferred tools found*), so I could not probe Dynamic Workflows directly. Its type surface is still readable in `sdk-tools.d.ts`.
8. **Version-skew artifact worth flagging:** `WorkflowOutput` in 2.1.220 documents `taskType: 'remote_agent' when remote:true dispatches to CCR`, but **`WorkflowInput` on 2.1.220 exposes no `remote` field**. The output type anticipates an input the binary does not accept — so "run a workflow in the cloud" is *not* reachable on our version.

---

## 5. Open questions for the verifier

1. **Is `tengu_neapolitan` on for this account?** Everything about `isolation:"remote"` hinges on it. Settle with the debug-log grep in §3F — one command, no writes.
2. **What are `tengu_amber_kestrel` and `EK(model, effort, ultracode)` live?** Either bypasses the 20-concurrent cap entirely (§2a). If `EK` is true for Opus-5-at-high — our default — then **we may have no concurrent-subagent cap at all today**, which would change every capacity model in this repo. This is the highest-value follow-up.
3. **Does `--bare` actually cut footprint materially, and is API-key billing acceptable?** Unmeasured (§4.1). If bare halves a worker, non-interactive drain work doubles per unit RAM.
4. **Should we move off 2.1.220?** The changelog says we are behind on four things that bear directly on this box: **2.1.221** memory-leak fixes in long sessions + reduced per-tool-call CPU in print/SDK sessions with many MCP tools; **2.1.224** *removes the 200-per-session spawn cap*; **2.1.225** *"Fixed parallel Claude Code sessions all logging out simultaneously after wake-from-sleep when many sessions share one credential store"* — that is our 4-account fleet exactly; **2.1.229** staggers same-prefix workflow siblings for prompt-cache reuse; **2.1.235** cuts memory/CPU for background cloud sessions. **[Q]** Cross-check with `cc-version-audit` before acting.
5. **Does a cloud session's own fan-out change the accounting?** With `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` one cloud slot hosts a whole team — so "N cloud sessions" understates delivered parallelism. Worth measuring before sizing a cloud lane.
6. **Confirm the silent-downgrade claim end-to-end.** §2c is read from the binary, not executed. A verifier should force `isolation:"remote"` and confirm a *local* worktree agent appears in `ps` — that is the difference between "we offloaded" and "we quietly did not".

---

## 6. Bottom line for the operator's question

The hypothesis is **half right**. Local subagents/teammates are real OS processes and do spend the ceiling. Dynamic Workflows are `local_workflow` — **also local**, and their "50-200 agents" is throughput against a **20-concurrent / 200-lifetime** cap, not 200 at once. The only mechanisms that genuinely leave this box are **`--cloud` sessions and routines**, both proven available on this account, both free of local compute cost, and both gated behind a TTY (fire) that our pane machinery already provides — with `claude -p --cloud <id>` giving the scriptable steer, and `--teleport` the harvest.

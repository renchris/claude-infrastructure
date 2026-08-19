# O3 — What oversight does Claude Code already ship?

**Axis:** the CC-native control plane — the background/agent ("fleet") view, the `sessions/<pid>.json`
registry, `claude agents`, and the Task tools — scored against SEE / INTERRUPT / STOP / AUDIT.
**Box:** MacBookPro18,2 M1 Max, Claude Code **2.1.220** (`GIT_SHA 4073f595…`, `BUILD_TIME
2026-07-24T22:17:45Z`), 4 live account config dirs, **16 live sessions at measurement time**.
**Method:** read-only. Bundle read by `mmap` byte-offset windows into
`~/.claude-220/node_modules/@anthropic-ai/claude-code/bin/claude.exe` (a Bun SEA — string constants
live in a pool at ~73–190 MB, the readable minified JS at ~225–246 MB; a `strings`-only grep reads the
pool and **cannot** see the control flow, which is why every claim below quotes a JS offset). Nothing
killed, no live config edited.

---

## 1. Verdict

1. **Anthropic already built the SEE surface, and it is better than ours on fidelity but blind to
   60% of our units.** `claude agents --json` is a real, TTY-free, 0.36 s fleet read that our
   pane-keyed accounting has no equivalent of — **but it returned 10 rows against 16 live sessions**,
   and the 6 it missed are missed for one reason with **zero exceptions across 16/16**: they inherited
   `CLAUDE_CODE_CHILD_SESSION=1`.
2. **That blindness is a one-env-var fix we have never used.** The registration gate is
   `if(yB()!=null||Zkt())return!1` (@227955190) and `Zkt()` opens with
   `if(Z.CLAUDE_CODE_FORCE_SESSION_PERSISTENCE)return!1`. That variable is set on **0 of 16** live
   sessions. Exporting it in the launcher converts every fired/nested session from invisible to
   first-class in Anthropic's own surface — the cheapest oversight win found on this axis.
3. **It is per-`CLAUDE_CONFIG_DIR`, so it can never show one fleet.** The registry path is
   `path.join(fn(),"sessions")` (@227951xxx). Four accounts ⇒ four disjoint views, four invocations,
   no union. This is structural and no flag fixes it.
4. **STOP exists natively and is weaker than it looks.** The fleet view ships
   `fleet_view_stop_session` / `fleet_view_stop_job`, but their own failure strings are
   `kill_unconfirmed` / `interrupt_failed` / **"worker may still be running"**. It is a best-effort
   interrupt, not a proof of death — and it reaches only registered sessions and `--bg` jobs, never a
   teammate, subagent, or Workflow agent.
5. **The one thing it cannot do at all is AUDIT the units that scare us.** A Workflow agent has no
   pid file, no job dir, and `yB()!=null` blocks registration even if it forked — so the 229-agent /
   7.2 h run remains invisible to every native surface. Our control plane must start exactly there.

---

## 2. The numbers and the capability table

### 2.1 The registry — what it is, on disk

Writer `BDc()` @227955190; reader `GAs()`/`Bze()` (`listAllLiveSessions`) @232683044.

```bash
# the store, per config dir — NOTE the symlink trap the landed doc flagged
readlink ~/.claude-next/sessions
# → /Users/chrisren/.claude/sessions      (so ~/.claude*/sessions/*.json double-counts .claude)
```

| Fact | Value | Command / offset |
|---|---|---|
| Store path | `<CLAUDE_CONFIG_DIR>/sessions/<pid>.json`, dir mode `0700` | `U5r()=Kje.join(fn(),"sessions")`; `mkdir(…,{mode:448})` @227955190 |
| Real config dirs holding a store | **4** — `.claude`(3) `.claude-secondary`(2) `.claude-tertiary`(3) `.claude-quaternary`(3) | `ls -la ~/.claude*/sessions` |
| Symlink trap | `.claude-next/sessions → .claude/sessions` — a glob over `~/.claude*/sessions` reads 14 files / **11 unique** | `readlink ~/.claude-next/sessions` (MEASURED, reproduces the landed 14-vs-11) |
| Files on disk | 11 | `ls ~/.claude{,-secondary,-tertiary,-quaternary}/sessions/*.json \| wc -l` |
| Keys actually present | **15**: `pid sessionId cwd startedAt procStart version peerProtocol kind entrypoint name nameSource status updatedAt statusUpdatedAt bridgeSessionId` | python union over all 11 files |
| Keys the READER accepts but nothing writes | `messagingSocketPath state detail tempo needs tmux agent logPath jobId parkedJobId waitingFor` — **0 of 11 files carry any** | same union; reader schema @232683044 |
| `kind` enum | `["interactive","bg","daemon","daemon-worker"]` — all 11 rows are `interactive` | `kO_=[…]` @232684xxx |
| `status` enum | `["busy","shell","idle","waiting"]` | `IO_=[…]` @232684xxx |
| `waitingFor` values | `"sandbox request"`, `"input needed"`, `"dialog open"`, `"worker request"`, or the top dialog's own label — e.g. `approve <Tool>: <description>`, `"approve plan"` | `ERS()` @242602273; label builder @243322435 |
| Freshness model | **edge-written**, not polled: a React `useEffect(()=>{LYn({status,waitingFor})},[Ov,ef])` fires only on transition | @245824930 |
| Liveness test | `process.kill(pid,0)` **and** `LC_ALL=C TZ=UTC ps -o lstart= -p <pid>` equal to stored `procStart` | `xC()`/`Vje()`/`gB()` @227947647 |
| GC | file is `unlink`ed at `process.on("exit")`, and by the reader when `!xC(pid)`. **A reused PID is excluded from the list but the file is NEVER deleted.** | @227955190, `Bze()` @232684400 |

**PID-reuse, observed live.** `~/.claude/sessions/1378.json` (written 2026-08-13) claims
`procStart:"Fri Aug 14 03:18:33 2026"`. PID 1378 today is a **postgres walwriter** started
`Thu 13 Aug 22:44:32` local. The stored value is rendered `TZ=UTC` and `ps` renders local (−7 h), so the
naive comparison is off by exactly 7 h — the trap our own `lstart is TZ-rendered` memory entry names.
`claude agents --json` correctly excludes the row; **a naive `ps -p $pid` check reports it ALIVE.**

```bash
ps -p 1378 -o lstart=,comm=      # → Thu 13 Aug 22:44:32 2026 postgres: walwriter
```

**Status staleness, observed live** (age = now − `statusUpdatedAt`):

| cfg dir | pid | status | age (min) | name |
|---|---|---|---|---|
| `.claude` | 1378 | `idle` | 7805 | voiceink-6b (dead — PID reused) |
| `.claude-tertiary` | 43029 | **`busy`** | **3056 (50.9 h)** | chris-resume-66 |
| `.claude-tertiary` | 53709 | `shell` | 74 | personal-ae |
| `.claude` | 60323 | `shell` | 74 | claude-infrastructure-c9 |
| `.claude-quaternary` | 20435 | `shell` | 55 | lakehouse-lecture-a7 |
| `.claude` | 69257 | `busy` | 28 | wt-pool-2-64 |
| … 5 more, all < 20 min | | | | |

A session has read `busy` for **two days**. Because the write is edge-triggered, a wedged-but-alive
session latches its last status forever, and the surface renders it with **no age**.

### 2.2 Registry coverage — the 16-vs-10 measurement

```bash
# census (three ways, all agree — 16)
ps -eo pid=,comm=    | awk '$2 ~ /claude-220\/node_modules\/\.bin\/claude$/ {print $1}'
ps -eo pid=,command= | awk '{n=split($2,a,"/"); if (a[n]=="claude") print $1}'
```

| Population | n | Command |
|---|---|---|
| Live `claude` session processes | **16** | above |
| Registry files on disk | 11 | `ls …/sessions/*.json` |
| Registry rows the native reader accepts | **10** | `claude agents --json` × 4 config dirs |
| Live sessions with **no** registry row | **6** | set difference |

**The discriminator is exact, 16/16, no exceptions:**

```bash
for p in <the 16 pids>; do ps eww -p $p -o command= | tr ' ' '\n' | grep -c '^CLAUDE_CODE_CHILD_SESSION='; done
```

| | in registry | `CHILD_SESSION=1` |
|---|---|---|
| 10 sessions | YES | 0 |
| 6 sessions | NO | 1 |

`CLAUDE_CODE_FORCE_SESSION_PERSISTENCE` is set on **0 / 16**.

The gate, read out of the binary (@227951460, @227955190):

```js
async function BDc(){ if(yB()!=null||Zkt()) return !1; /* …write sessions/<pid>.json… */ }
function yB(){ let e=_B(); if(e) return e.agentId; return yde?.agentId }          // any teammate / dynamic-team context
function Zkt(){                                                                   // isNestedInteractiveClaudeSession
  if(Z.CLAUDE_CODE_FORCE_SESSION_PERSISTENCE) return !1;
  if(!(Z.CLAUDE_CODE_CHILD_SESSION && PN() && !o_())) return !1;                  // PN()=isInteractive, o_()=isTeammate
  return !Tsg() }                                                                 // Tsg(): tmux -g marker probe
```

Two independent suppressions, and they cover exactly the classes we care about:
`yB()!=null` kills registration for **anything carrying an agentId** (teammate, dynamic-workflow
agent); `Zkt()` kills it for **any interactive session launched from inside another session**, which
is every `handoff-fire` pane, every `limit-recover --resume` (3 of our 6 invisible ones are
`expect`-driven resumes), and every launcher child. The `!Tsg()` clause means the suppression is
*deliberately* relaxed under tmux — i.e. Anthropic knows nested sessions should sometimes register.
`CLAUDE_CODE_FORCE_SESSION_PERSISTENCE` is the documented-in-code escape hatch and we have never set it.

### 2.3 `claude agents` — the CLI

```bash
CLAUDE_CONFIG_DIR=$HOME/.claude-quaternary \
  ~/.claude-220/node_modules/@anthropic-ai/claude-code/bin/claude.exe agents --json
```

| Property | MEASURED |
|---|---|
| Exit / TTY | `rc=0`, works with no TTY ("does not require a TTY" — `--help`) |
| Latency | **0.36 s**, 3/3 runs identical (`/usr/bin/time -p`) |
| Side effects | **none** — `sessions/` listing byte-identical before/after, all 4 dirs (it does *not* self-register) |
| Rows returned | 2 + 2 + 3 + 3 = **10** across the 4 config dirs |
| Fields emitted | `pid cwd kind startedAt sessionId name status` (+ `waitingFor` when `status=="waiting"`) |
| **Fidelity loss** | `EMm(e)` = `e==="idle"?"idle":e==="waiting"?"waiting":"busy"` → **`shell` collapses to `busy`** (@246887562). 4 of our 10 rows are `shell` on disk and `busy` in the JSON. |
| No age emitted | `statusUpdatedAt` is **not** in the output — the 50.9 h-stale `busy` is indistinguishable from a fresh one |
| `--all` | adds completed **background jobs**: 3 rows, `kind:"background"`, `status:null`, from 2026-07-24/26 — the only `--bg` runs this box has ever done |
| `--cwd <path>` | filters; help says "background sessions" but it **also filters interactive** (2 rows → 1). Help text understates. |
| Trust prompt | 2.1.225 added a workspace-trust prompt to `claude agents` for untrusted dirs (QUOTED changelog) — a future non-interactive hazard for scripted reads |

### 2.4 The agent / "fleet" view — reach, states, actions, scale

Internally it is the **fleet view** (`[fleetview]`, `fleet_view_*`, `tengu_fleetview_*`).

| Question | Answer | Evidence |
|---|---|---|
| How reached | left arrow on an empty prompt — setting `leftArrowOpensAgents`, **default true** (`t.leftArrowOpensAgents??!0`); also `defaultToAgentsView` ("Start in agent view"), `claude agents`, `/background`, `ctrl+b` ("run in background"; `ctrl+b ctrl+b` under tmux) | @245xxx settings rows; `ctrl+b` @125173856 |
| Can be disabled | setting `disableAgentView` / env `CLAUDE_CODE_DISABLE_AGENT_VIEW` — *"Disable agent view (`claude agents`, `--bg`, `/background`, the on-demand daemon). Typically set in managed settings."* | `pXi()` @228998243 |
| Scope | the **same** per-config-dir `sessions/` store + that dir's `jobs/` store. **No cross-account union.** | `GAs()` @232683044 |
| Header (local form) | `` `${vCt.blocked} awaiting input` · `${vCt.active} working` · `${vCt.completed+aQ.length} completed` `` — **exactly the operator's screenshot** | @245547998 |
| Header (daemon form) | `N needs you · N working · N idle · "nothing running"` | @245547998 |
| Out-of-view hint | `Qdm(e) = e>0 ? "${e} awaiting input · claude agents" : "claude agents"` — the count surfaces **without opening the view** | @245434753 |
| Footer | `"Your conversation moved to the background — enter opens it · esc returns to it · ctrl+c twice quits"` | @245548306 |
| Actions (from telemetry names, complete set) | `open` · `reply` · `dispatch` / `dispatch_exec` · `new_session` · `resume_picker` · **`stop_session`** · **`stop_job`** · `delete_job` · `archive_session` · `rename_job` · `pin_toggle` · `reorder_job` · `earlier_load` · group `create/rename/delete/assign/ungroup/mode` | regex over the binary for `fleet_view_[a-z_]+` |
| STOP quality | `fleet_view_stop_session` → `tengu_bg_agent_action{action:"stop"}`; failure reasons `interrupt_failed`, `[fleet:remote] interrupt`; `stop_job`/`delete_job` carry `kill_unconfirmed` / `delete_unconfirmed` + the literal **`"worker may still be running"`** | @143898704, @143140832, @143148816 |
| INTERRUPT quality (reply) | reply → send to a live session; on `TSt` (not running) it **respawns** with the prompt as `initialPrompt`; if that fails it **queues to disk** (`queuedPrompt`) and reports *"Reply queued — will be sent when this session restarts"* | @245548306 |
| Restricted surface | `` `/${cmd} isn't available in agent view — attach to a session to run it` `` | @228xxx |
| **Scale / pagination** | **Live rows are never folded or capped.** Only the *done* bucket folds: `ofi(terminalRows, 1+needsCount+liveCount)` → `doneCap = terminalRows − const − (1+needs+live)`; if that is below a floor it returns `doneCap:Math.max(0,…)` **and `compactHeader:true`**. So as live rows grow, the done bucket is squeezed to **0** and the header goes compact; the live list itself is a plain scrolling Ink list (`onWheel → scrollBy(±3)`, `stickyScroll:false`). | `ofi()` @245434753; list @245548306 |

So at 30–50 entries there is **no cap and no pager** — one scroll list, taller than the terminal, with
history folded away first. Usable, but scanning is O(n) and there is no "show me only what needs me"
partition beyond the header counts and grouping/pinning.

### 2.5 The `jobs/` store — the real AUDIT surface, and it is nearly unused

```bash
ls -la ~/.claude-secondary/jobs/            # 3 job dirs + pins.json;  ~/.claude{,-tertiary,-quaternary}/jobs → ABSENT
```

Each job dir holds `state.json` + **`timeline.jsonl`** (append-only) + `tmp/`:

```json
{"state":"done","detail":"…","tempo":"idle","inFlight":{"tasks":0,"queued":0,"kinds":[]},
 "tokens":28896,"output":{"result":"…"},"fan":[{"id":"todo:20","kind":"todo","label":"…","startedAt":0,"doneAt":0}]}
```

`timeline.jsonl` records `{at,state,detail,text}` per transition **including the assistant's own text** —
a genuine post-hoc reconstruction of what the unit did. `fan[].kind` is rendered by
`Mum()` (@245434753) as `` `${done}/${n} agents` `` for `kind==="agent"||kind==="workflow"` — **so the
native view CAN show per-agent progress for a job's children.**

Two hard limits, both measured:
- **3 jobs total, all `state:"done"`, all from 2026-07-24/26, all in one config dir.** The `--bg` path
  is REACHABLE but effectively unused here, so this audit surface is empty for everything we run.
- Our 3 jobs carry `fan` kinds `["todo"]` and `[]` only. The `agent`/`workflow` fan is **EXISTS in
  code, NOT OBSERVED on disk** — I have no measured instance of the native view rendering a workflow
  child.

### 2.6 A shipped cross-session control channel that is dark

The bundle contains `sendToUdsSocket` (inject a `type:"user"` message into another session,
`priority:"next"`, with file attachments) and `sendControlToUdsSocket` (`type:"control", action:…`),
plus `listLivePeerSessions()` / `findLivePeerBySessionId()` (@232683998). Every one of them keys on the
registry field **`messagingSocketPath`**, and:

- `BDc()` **never writes** `messagingSocketPath` (read the writer above);
- **0 of 11** registry files on disk carry the key;
- the own-socket getter is a literal stub: `function VAs(){return}` (@232684437).

⇒ `listLivePeerSessions()` returns `[]` unconditionally and `findLivePeerBySessionId()` returns `null`
unconditionally, on this build. A first-class peer-control transport EXISTS and is **NOT REACHABLE**.
(The `messagingSocketPath` that *is* populated lives in the SDK/control `system:init` payload @239421549
— a different consumer.)

### 2.7 The Task tools — an agent's lever, never the operator's

Schemas loaded via `ToolSearch` and read (not inferred from prose):

| Tool | Observes | Controls | Whose lever |
|---|---|---|---|
| `TaskList` / `TaskGet` | the **task board** (id, subject, status, owner, blockedBy) — *not* processes | — | model, in-session |
| `TaskUpdate` / `TaskCreate` | — | board rows only | model, in-session |
| `TaskStop` | — | **"Stops a running background task by its ID… To stop an agent-team teammate, pass its agent ID (`name@team`) or bare teammate name… To stop a background agent spawned with a name, pass that name"** | model, in-session |
| `SendMessage` | — | send to a teammate by name; `shutdown_request`/`shutdown_response` protocol; **"Approving shutdown terminates your process"** | model, in-session |

`TaskStop` is the only native primitive that can kill a teammate or a *named* background agent — and it
is callable **only by the model inside the session that owns it**. There is no operator-facing CLI or
key that reaches it. It takes an id/name, so an **unnamed** `Agent()` subagent and a Workflow `agent()`
have nothing to pass. This is consistent with the landed A-axis finding that a running Dynamic Workflow
has no abort path, and locates *why*: the abort primitive exists but is name-addressed and
in-session-only.

### 2.8 CHANGELOG 2.1.220 → 2.1.235 (QUOTED; newest published = **2.1.235**, we run 2.1.220)

| Ver | Entry (verbatim) | Why it matters here |
|---|---|---|
| 2.1.232 | *"Subagent forking is now on by default: … and **non-teammate agent spawns in interactive sessions now run in the background by default**"* | **The paneless population grows by default.** Upgrading makes the SEE gap worse before it makes it better. |
| 2.1.232 | *"Interactive sessions on one machine now keep unique names: starting or renaming a session to a name another live session already uses gives it a `name-word-word` variant and tells you"* | name becomes a usable key for `TaskStop`/`SendMessage`-style addressing at fleet scale |
| 2.1.229 | *"ListAgents now marks disconnected Remote Control sessions as `offline` and labels your cloud sessions as `cloud`"* | a `ListAgents` tool exists on newer builds; **not present** in this session's tool surface |
| 2.1.227 | *"SendMessage can now start a conversation with your Remote Control sessions on other machines by name (`ListAgents` shows them as `name [ref]`)"* | cross-machine INTERRUPT, name-addressed |
| 2.1.225 | *"Added a workspace trust prompt to `claude agents` for untrusted directories"* | can block a scripted `claude agents` read |
| 2.1.224 | *"**Removed the 200-subagent-per-session spawn cap**; long-running sessions no longer refuse new agents"* | one of the few remaining implicit brakes on fan-out is gone |
| 2.1.234 | *"Fixed session-scoped permission answers (including denies) being dropped when answering background subagent tool permission prompts"* | on 2.1.220 this bug is **live**: a deny on a background subagent prompt can be dropped |

---

## 3. The honest gap table

Per unit class, what CC-native gives **the operator** for free on 2.1.220. `✅` = works today,
`◐` = partial/degraded, `❌` = nothing.

| Unit class | SEE | INTERRUPT | STOP | AUDIT |
|---|---|---|---|---|
| **Pane session, top-level** (no `CHILD_SESSION`) | ✅ `claude agents --json`, 0.36 s, name+cwd+status — **per config dir** | ◐ header counts + `N awaiting input · claude agents` hint; `waitingFor` schema exists but **nothing writes it** to disk | ◐ `fleet_view_stop_session`, best-effort (`interrupt_failed`) | ◐ transcript jsonl only; no per-session event stream |
| **Pane session, fired/nested** (`CHILD_SESSION=1`) | ❌ **not registered at all** — 6/16 here | ❌ | ❌ | ◐ transcript only |
| **`Agent({name})` teammate** | ❌ `yB()!=null` blocks registration | ◐ `SendMessage` — **model only** | ◐ `TaskStop <name>` — **model only** | ◐ transcript only |
| **Unnamed `Agent()` subagent** | ❌ | ❌ | ❌ no id to pass to `TaskStop` | ◐ inline in parent transcript |
| **Workflow `agent()`** | ❌ no pid file, no job dir, no ledger row | ❌ | ❌ — confirms the landed "no abort path" finding | ❌ |
| **`--bg` job** | ✅ `--all` lists it; `state.json` has `state/detail/tempo/inFlight/tokens/fan` | ✅ reply → respawn → **queue-to-disk** if dead | ◐ `stop_job` / `delete_job`, `"worker may still be running"` | ✅ **`timeline.jsonl`** — the best AUDIT artifact CC ships. Used **3 times, 26 days ago.** |
| **Cross-account (4 config dirs)** | ❌ structural — 4 disjoint stores, 4 invocations | ❌ | ❌ | ❌ |

**Where it stops, stated as the four sentences our own plane must answer:**
1. *SEE* stops at `CHILD_SESSION` and at the config-dir boundary — 6/16 invisible, 4 views never unioned.
2. *INTERRUPT* stops at the age of a state: the surface shows `busy`, never `busy for 50.9 hours`.
3. *STOP* stops at "worker may still be running", and reaches nothing that lacks a pid file or a name.
4. *AUDIT* stops at the pane: `timeline.jsonl` is real and good, and only `--bg` jobs get one.

---

## 4. What I could NOT measure, and why

| Not measured | Why | The probe that would settle it |
|---|---|---|
| That `CLAUDE_CODE_FORCE_SESSION_PERSISTENCE=1` **actually** produces a registry row | The gate needs `PN()` (isInteractive) to be true, so a headless `claude -p` cannot exercise it; a faithful test needs a real PTY + auth, i.e. launching a live session. Evidence here is (a) the branch read out of the binary and (b) a 16/16 correlation — **strong, but it is INFERRED, not RUN.** | `CLAUDE_CONFIG_DIR=<copy> CLAUDE_CODE_CHILD_SESSION=1 CLAUDE_CODE_FORCE_SESSION_PERSISTENCE=1 script -q /dev/null claude` in a throwaway pane, then `ls <copy>/sessions`; positive control = same launch **without** the FORCE var must produce **no** file |
| The fleet view rendering at 30–50 live entries | Requires driving a TUI at that scale; would have to be done against a real fleet. Fold logic read from `ofi()` is code-truth, not a screenshot. | open the view on a box with ≥30 registered sessions at a known `LINES`, screenshot; compare `doneFoldHidden` telemetry |
| The native view showing a **workflow** child (`fan[].kind==="workflow"`) | The code path exists (`Mum()`), but all 3 jobs on this box carry only `todo` fans. **EXISTS ≠ OBSERVED.** | run one `--bg` session that spawns a Dynamic Workflow, then read its `state.json` `fan` |
| Whether 2.1.229+ `ListAgents` closes any of this | We run 2.1.220; the tool is absent from this session's surface and I did not install a newer binary (would mutate the toolchain) | install 2.1.235 into a throwaway prefix, `ToolSearch` for `ListAgents`, run it |
| Whether `fleet_view_stop_session` actually kills | Would require stopping a live session — barred by the read-only rule | on a disposable session: stop from the view, then `process.kill(pid,0)` in a loop for 10 s |
| Cost of `claude agents --json` at 50 rows | Only 2–3 rows per dir existed. 0.36 s is dominated by Bun cold start, not row count, so it should be ~flat — **INFERRED** | populate a copied config dir with 50 synthetic `<pid>.json` files (pointing at live pids) and re-time |
| Whether the daemon header form (`needs you`) is ever reachable here | `isDaemonWorkerRegistryEnabled` sits in the same gate bundle as `isAgentsFleetEnabled`/`fleetGateRejected`; I read the export list but did not resolve `ONe`'s body, so I cannot confirm or refute the landed "returns hardcoded false" claim | resolve `ONe` at its definition offset and read the gate call |

---

## 5. The design constraint this axis imposes

**Do not build a session lister. Build the three things Anthropic's lister structurally cannot be.**

1. **Adopt `sessions/<pid>.json` as the substrate, and pay the one-line entry fee.**
   It is already PID-keyed, procStart-disambiguated, self-GC'ing, mode-0700, and read in 0.36 s with no
   TTY. Our pane-keyed accounting is blind to 63% of live writers; this store is blind to 37% *and the
   blindness has a switch*. Export `CLAUDE_CODE_FORCE_SESSION_PERSISTENCE=1` from every launcher and
   fire path, and our fired sessions become first-class in Anthropic's own view for free. **Constraint:
   any unit we mint that cannot appear in this store must be justified, not defaulted to.**

2. **Our plane owns exactly the four things the native one cannot own.** Everything else is
   duplication we will have to keep in sync with a minified binary:
   - **Union across the 4 config dirs.** Structural in CC (`path.join(fn(),"sessions")`); trivial for us.
     Mind the `.claude-next/sessions` symlink — dedupe on `(pid, procStart)`, never on filename.
   - **Age, not just state.** Emit `statusUpdatedAt` age beside every status. The native JSON drops it,
     and the write is edge-triggered, so a 50.9 h `busy` is the *normal* failure and it renders
     identically to a healthy one. **A status without an age is not SEE.**
   - **The paneless classes** — teammate, unnamed subagent, Workflow agent. `yB()!=null` means these can
     *never* enter the native registry, by design. This is where our own ledger earns its existence, and
     the Workflow agent is the priority: it is the only class scoring ❌ on all four axes.
   - **A STOP that reports whether it worked.** Native stop's own vocabulary is `kill_unconfirmed` /
     `"worker may still be running"`. Ours must return a verdict — killed / refused / unreachable — and
     never a silent success. (Prior art in this repo: *make the actuator the arbiter*.)

3. **Copy `timeline.jsonl`, and copy it for pane sessions too.** It is the strongest AUDIT artifact CC
   ships — append-only `{at,state,detail,text}` per transition — and it exists **only** for `--bg` jobs,
   of which this box has 3, all 26 days old. Every unit we want to audit needs one, and it must be
   written by the unit, not reconstructed from a transcript afterwards.

4. **Design against 2.1.232, not 2.1.220.** *"non-teammate agent spawns in interactive sessions now run
   in the background by default"* plus *"removed the 200-subagent-per-session spawn cap"* means the
   paneless, unregistered, unstoppable population is about to grow **by default, without anyone asking
   for it**. A plane that only enumerates panes is already obsolete at the version after ours.

5. **Two levers to keep in the design's back pocket, both measured here.** `disableAgentView` /
   `CLAUDE_CODE_DISABLE_AGENT_VIEW` turns off `claude agents`, `--bg`, `/background` and the on-demand
   daemon in one setting — a real kill-switch if the native surface ever fights ours. And
   `messagingSocketPath` is the key that would light up CC's own shipped peer-control transport
   (`sendControlToUdsSocket`) — today dark because `VAs(){return}` is a stub and nothing writes the
   field. Worth re-checking on every upgrade: if a future build populates it, a supported cross-session
   STOP arrives for free.

---

### Reproduction one-liners

```bash
# fleet read, all 4 accounts, deduped
for d in ~/.claude ~/.claude-secondary ~/.claude-tertiary ~/.claude-quaternary; do
  CLAUDE_CONFIG_DIR=$d ~/.claude-220/node_modules/@anthropic-ai/claude-code/bin/claude.exe agents --json
done

# who is live but invisible
comm -13 <(ls ~/.claude{,-secondary,-tertiary,-quaternary}/sessions/*.json | xargs -n1 basename | cut -d. -f1 | sort) \
         <(ps -eo pid=,comm= | awk '$2 ~ /claude-220\/node_modules\/\.bin\/claude$/ {print $1}' | sort)

# why each is invisible
ps eww -p <pid> -o command= | tr ' ' '\n' | grep -E '^CLAUDE_CODE_(CHILD_SESSION|FORCE_SESSION_PERSISTENCE)='

# read any claim in this doc out of the binary (offsets are byte offsets into claude.exe)
python3 -c 'import mmap;f=open("'"$HOME"'/.claude-220/node_modules/@anthropic-ai/claude-code/bin/claude.exe","rb");m=mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ);print(m[227953000:227956500].decode("utf8","replace"))'
```

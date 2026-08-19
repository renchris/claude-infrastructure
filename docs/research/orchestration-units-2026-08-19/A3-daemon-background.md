# A3 — The daemon + background-session architecture ("left arrow")

**Date:** 2026-08-19 · **Binary:** `~/.claude-220/.../bin/claude.exe`, Mach-O arm64, 256,908,272 B,
`VERSION:"2.1.220"`, `GIT_SHA:"4073f59596e272f39393db4f96abc5f4b10eff21"`, `BUILD_TIME:"2026-07-24T22:17:45Z"`
**Method:** binary strings + live `--bg` probe (fired, measured, torn down — §5) + read of the daemon's own log.
**Prior art this EXTENDS, does not redo:** `docs/research/agent-view-coverage-2026-07-31.md` (the view's
`CLAUDE_CONFIG_DIR` scoping + the registration gate). That doc owns *who can SEE a session*; this one owns
*what a backgrounded session COSTS*.

---

## 1. VERDICT (≤5 lines)

> **Backgrounding frees the PANE and nothing else. It is not a lighter execution mode — it is the same
> full interactive REPL with the terminal replaced by a `bg-pty-host` process, and it costs MORE, not less.**
> Measured: one background job = **5 processes / 611.7 MB physical footprint / 54 threads**, vs a foreground
> session at **1 process / 329.6 MB / 19 threads** — ~1.9× the memory and ~2× the threads for the first job.
> There is **no worker-count cap** anywhere in the code; the only admission gate is macOS **VM pressure ≥ CRITICAL**,
> and the `nice 5` the bg processes carry **does not demote them** (PRI stays 31, same band as foreground).
> The one genuine win is *after* the fact: an idle worker is **retired** (process exits, conversation survives on
> disk) after 1 h — or 60 s under memory pressure — and can be `--resume`d. That elasticity is real and we have none.

**Operator's hypothesis, adjudicated:** *"backgrounding escapes the ~15-slot ceiling"* — **FALSE for a working
session, TRUE only for an idle one.** The ceiling is memory + runnable threads (per `scaling-bottlenecks-2026-08-09`),
and a live background worker pays both, plus a pty-host tax. What CC has that we don't is an *evictor*.

---

## 2. Numbers, with the command that produced each

### 2.1 What the daemon is

| Fact | Value | Command / evidence | Label |
|---|---|---|---|
| Service install | **disabled in 2.1.220** | `claude.exe daemon --help` → *"Service install is disabled in this version — the daemon runs on demand and exits when the last client disconnects."* | MEASURED |
| Origin | `transient` | `claude.exe daemon status` → `origin: transient — started on-demand by 'claude --bg' (pid 79885)` | MEASURED |
| Cold-start policy | default `"transient"` | settings schema: `daemonColdStart: E.enum(["transient","ask"]).optional().describe("When no background service is running: 'transient' spawns one for this login session; 'ask' offers to install it persistently")`; gate `function CIg(){return Ke("tengu_quiet_harbor",!1)?"ask":"transient"}` | MEASURED (strings) |
| Install gate | OFF | `function kst(){return Ke("tengu_amber_anchor",!1)}` → `bgSupervisorNoun()` returns `"background service"`, not `"daemon"` | MEASURED (strings) |
| Worker registry gate | **hardcoded false** | `isDaemonWorkerRegistryEnabled: ONe`, `function ONe(){return!1}` | MEASURED (strings) |
| Idle-exit rule | **5 s after last client** | `daemon.log`: `[supervisor] idle 5s with no clients — exiting` / `shutting down (cause=idle_exit, uptime=305s, leases=0, live_workers=0)` — observed **3 times** (Jul-26 uptime 181,585 s; Aug-19 11:40 uptime 305 s; Aug-19 11:58 after my probe) | MEASURED |
| Scope | **one daemon per `CLAUDE_CONFIG_DIR`** | `~/.claude-secondary/daemon/roster.json` `{"proto":1,"supervisorPid":59451,…}` vs `~/.claude-next/daemon/roster.json` `supervisorPid:59119` — separate files, separate pids | MEASURED |

**Daemon state layout** (strings; live dir `/tmp/cc-daemon-501/0503d474/`):
`control.sock` · `spare/<uuid>.pty.sock` · `spare/<uuid>.claim.sock` · `pty-pids/<pid>.pid` · plus, under the
config dir: `daemon/roster.json`, `daemon/control.key`, `daemon/dispatch/`, `daemon/dispatch/rejected/`,
`daemon/auth/<x>.json`, `jobs/<short>/state.json`, `jobs/<short>/timeline.jsonl`, `jobs/pins.json`, `jobs/.order`.
`/tmp/cc-daemon-501/` is **empty** when no daemon runs — the whole runtime dir is torn down on idle-exit.

### 2.2 `--bg-pty-host 200 50` — what the numbers are

```
bad argv: --bg-pty-host <sock> <cols> <rows> -- <file> [args...]
```
…and the spawn site builds it as `[…,"--bg-pty-host", r.ptySock, String(r.cols), String(r.rows), "--", e, …]`.

⇒ **`200 50` is COLS × ROWS — a fixed 200×50 headless terminal. It is NOT a pool size.** (MEASURED, strings.)
Confirmed live: `claude bg-pty-host --bg-pty-host /tmp/cc-daemon-501/0503d474/spare/739499b9.pty.sock 200 50 -- …`
and `claude logs 4925e5d0` replays a **full Claude Code TUI welcome box drawn to column 186** (§5).

### 2.3 The measurement: one background job, live (probe `4925e5d0`)

`/usr/bin/vmmap --summary <pid> | grep 'Physical footprint:'` — **not RSS**, per method rule 2.

| pid | ppid | role | **footprint** | RSS | RSS/fp | threads | NI | PRI | stat |
|---|---|---|---|---|---|---|---|---|---|
| 80000 | 1 | `claude.exe daemon run --origin transient` | **114.0 M** | 305 M | 2.68× | 12 | 0 | 31 | `Ss` |
| 80092 | 80000 | `claude bg-pty-host … spare/739499b9.pty.sock 200 50` | **84.9 M** | 255 M | 3.00× | 7 | 5 | 31 | `SNs` |
| 80093 | 80000 | `claude.exe --bg-pty-host …` (2nd host) | **85.3 M** | 257 M | 3.01× | 7 | 5 | 31 | `SNs` |
| 80232 | 80092 | `claude bg-spare --bg-spare …claim.sock` (**idle** prewarm) | **98.6 M** | 277 M | 2.81× | 9 | 5 | 31 | `SN` |
| 80527 | 80093 | `claude.exe --session-id 4925e5d0-…` (**the actual work**) | **228.9 M** | 475 M | 2.07× | 19 | 5 | 31 | `RN` |
| | | **TOTAL for ONE bg job** | **611.7 M** | 1,569 M | | **54** | | | |

Foreground comparison, same instrument, same minute:

| pid | role | **footprint** | RSS | threads | NI | PRI |
|---|---|---|---|---|---|---|
| 95587 | interactive session (`.bin/claude`, worktree `drain/recycle-11`) | **329.6 M** | 573 M | 19 | 0 | 31 |
| 99124 | interactive session (this one, many agents) | **371.6 M** | 762 M | 30 | 0 | 31 |
| 8435 | a subagent (`claude.exe --agent-id A9-…`) | **306.7 M** | 522 M | — | 0 | 31 |

Commands: `/usr/bin/vmmap --summary <pid>` · `/bin/ps -o pid,ppid,nice,pri,stat,command= -p …` ·
`/bin/ps -M -p <pid> | tail -n +2 | wc -l`.

**Three answers the operator asked for, separately:**

| Axis | Is a backgrounded session cheaper? | Evidence |
|---|---|---|
| **Screen real estate** | **YES — total.** Zero panes; `claude --bg` returns to the shell immediately (`backgrounded · 4925e5d0`). | MEASURED |
| **Memory** | **NO — it is worse.** 611.7 M for the first job (297.5 M of that is daemon + one pty host + the idle spare, standing) vs 329.6 M for a foreground session. Marginal 2nd job ≈ 85 M (pty host) + ~229 M (worker) ≈ **314 M**, still ≈ a foreground session, plus the amortised 297.5 M already spent. | MEASURED |
| **Load (runnable threads)** | **NO.** 54 threads vs 19. `NI=5` but **`PRI=31` — identical to foreground.** On Darwin `nice` alone does not move the band (only `taskpolicy -c background` reaches PRI=4). The worker was observed in state `RN` = **runnable**, i.e. in the load-average numerator. | MEASURED |

⚠️ **Confound, stated honestly:** the 228.9 M worker was 10 s old with a near-empty context; 95587 had hours of
context. The *architectural* claim (backgrounding adds a pty host + shares a daemon, and removes nothing) is solid;
the *per-worker* 228.9 M is a floor, not a like-for-like. A matched-context comparison was not possible read-only.

### 2.4 Cap? Pool size? — answered from code AND from the daemon's own log

| Question | Answer | Evidence | Label |
|---|---|---|---|
| Max background workers | **NONE.** No count cap exists anywhere in the bg scheduler. | Sweep loop iterates `for(let te of j.values())` with no size test; roster is an open map `j.workers[q]=z.rosterEntry()` | MEASURED (strings) |
| Spare pool size | **exactly 1** | `async function SXo(…){ … if(kXe\|\|uRr\|\|_Xo)return; …}` — `kXe` is a single object, not an array: if a spare exists *or* one is booting, return. Log confirms refill-one-on-claim: `bg spare spawned host pid=94935` → `bg claimed-spare 6dc23ecb` → `bg spare spawned host pid=94940` | MEASURED |
| Boot concurrency | **3** | `Ke("tengu_bg_prewarm_burst_concurrency",3)`, delay `Ke("tengu_bg_prewarm_burst_delay_ms",15000)`, per-sweep respawns `Ke("tengu_bg_prewarm_per_sweep",3)` with inner cap `ee=12` | MEASURED |
| Sweep period | **60 s** | `dNn=60000` | MEASURED |
| **The real admission gate** | **macOS VM pressure ≥ CRITICAL** | see below | MEASURED |
| Concurrent jobs actually observed | 4 (`6dc23ecb`,`5e4eab69`,`1ed2634a`,`f9b53b8b`) over a 2.1-day daemon run | `daemon.log` 2026-07-24 → 07-26 | MEASURED |

**The admission gate, verbatim** — and it is *not* what its own flag name says:

```js
function JKs(){
  let e = Ke("tengu_bg_low_mem_mb",1024)*1024*1024;
  if (e<=0) return {lowMem:!1, level:void 0};
  if (Lt()!=="macos") return {lowMem: Ahp.freemem()<e, level:void 0};   // Linux/Win: free RAM
  let t = f8y();
  return {lowMem: t!==void 0 && t>=d8y, level:t};                        // macOS: VM PRESSURE
}
function iYe(){ return JKs().lowMem }
var d8y = 4;
p8y = Buffer.from("kern.memorystatus_vm_pressure_level\x00");   // read via bun:ffi sysctlbyname
```

⇒ **On macOS `tengu_bg_low_mem_mb` (1024) is dead except as an on/off switch.** The live gate is
`sysctlbyname("kern.memorystatus_vm_pressure_level") >= 4` — i.e. **CRITICAL**, not WARN (=2), not NORMAL (=1).
So CC will happily admit background sessions until the kernel is already in critical pressure. Given
`docs/research/scaling-bottlenecks-2026-08-09` ranks memory as our #1 wall, **this gate fires far too late to
protect us**, and it is the *only* thing standing between `--bg` and an unbounded fleet.

**What the gate does when it DOES fire — this is the interesting half (elasticity we lack):**

```js
let K = iYe(), Y = K?UEl:fST, re = K?UEl:Rhp();   // UEl=60000 (60 s)  fST=3600000 (1 h)  Rhp()=480 min
… retireIfSettled(Y, oe, re) …
if (K && se===0 && iYe()) { … "bg: low memory persists after shedding non-pinned — retiring pinned settled workers as a last resort"; M("tengu_bg_retire_pinned_low_mem",{}) … }
```

and the retire predicate refuses only for these reasons:

```js
async retireIfSettled(e,t,r=e){
  if(this.isTransitioning) return {retired:!1,reason:"in-progress"};
  if(this.record.outcome)  return {retired:!1,reason:"no-state"};
  if(this.attachers.size>0)return {retired:!1,reason:"attached"};     // someone is LOOKING at it
  if(wDe(this.dispatch))   return {retired:!1,reason:"host-managed"};
  if(t?.has(this.dispatch.short)) return {retired:!1,reason:"pinned"};
  if(this.adoptedAt && Date.now()-this.adoptedAt<Ghp) return {retired:!1,reason:"recent-adopt"};
  if(this.lastInputAt && Date.now()-this.lastInputAt<e) return {retired:!1,reason:"recent-input"};
  … transitionTo({kind:"retiring",reason:"grace"}); this.shutdownWorker(); M("tengu_bg_retired",{…})
```

**The elasticity ladder, in numbers:** idle **1 h** → retire · idle **60 s** *under critical pressure* → retire ·
bridged/attached grace **480 min** (`tengu_bg_retire_grace_bridged_min`) → collapses to **60 s** under pressure ·
still under pressure after shedding everything unpinned → **retire pinned workers too**.

**Retire ≠ lose.** The conversation survives as `jobs/<short>/state.json` with everything needed to restart it:

```json
{"state":"done","linkScanPath":"/Users/chrisren/.claude-secondary/projects/…/1ed2634a-….jsonl",
 "linkScanOffset":327333,"respawnFlags":["--agent","claude","--permission-mode","auto"],
 "providerEnv":{"CLAUDE_CONFIG_DIR":"/Users/chrisren/.claude-secondary"},
 "sessionId":"1ed2634a-…","resumeSessionId":"1ed2634a-…","daemonShort":"1ed2634a","cliVersion":"2.1.215"}
```

⇒ **This is the one true ceiling-breaker in the whole feature: N conversations, K live processes, K ≪ N, with
K driven down automatically by memory pressure.** The operator's 3 "completed" jobs are 3.5 weeks old, hold zero
processes, and are still fully resumable.

### 2.5 The operator's screenshot, decoded line-for-line

The header string is rendered by exactly this JSX (MEASURED, strings):

```js
`${vCt.blocked} awaiting input`, `${vCt.active} working`, `${vCt.completed+aQ.length} completed`
…
"Your conversation moved to the background — enter opens it · esc returns to it · ctrl+c twice quits"
```

and the alternate form (fleet-wide) is
`${needsCount} needs you` / `${workingCount} working` / `${liveCount-workingCount} idle` / `nothing running`.
Note **`liveCount` is separate from `completed`** — the view itself distinguishes *has a process* from *doesn't*.

`claude agents --json --all` (run read-only, `CLAUDE_CONFIG_DIR=~/.claude-secondary`) returns exactly the
screenshot's contents:

```json
[{"id":"6dc23ecb","kind":"background","name":"investigate-session-closures","state":"done"},
 {"id":"5e4eab69","kind":"background","name":"resume danny studio 60 handoff","state":"done"},
 {"id":"1ed2634a","kind":"background","name":"opus 5 upgrade handoff","state":"done"},
 {"pid":95587,"kind":"interactive","status":"busy","cwd":"…/.worktrees/drain/recycle-11"},
 {"pid":99124,"kind":"interactive","status":"waiting","waitingFor":"permission prompt"}]
```

**All three "completed" jobs are `state:"done"` with NO pid.** The "1 awaiting input" is an *interactive* pane.
So the screenshot shows **zero live background sessions** — the operator has never actually run one concurrently.

### 2.6 TMUX — separate CC's mechanism from ours

| Question | Answer | Evidence | Label |
|---|---|---|---|
| Does CC's backgrounding use tmux? | **NO.** It uses its own `bg-pty-host`. No CC process is a child of any tmux. | `ps -eo pid,ppid,command \| awk '$2==24649\|\|$2==8626'` → only `expect` + `zsh`, no `claude` | MEASURED |
| Does 2.1.220 ship tmux integration? | **YES, but for WORKTREES and TEAMMATES, not backgrounding.** | `--tmux` help: *"Create a tmux session for the worktree (requires --worktree). Uses iTerm2 native panes when available; use --tmux=classic for traditional tmux."* Plus `Error: tmux is not installed. Install tmux with: brew install tmux` | MEASURED |
| Is tmux live on this box? | **YES — 5 sessions, all OURS.** | `tmux list-sessions` → `1`, `dev` (attached), `lr-resume-855b332e`, `lr-resume-8843d236`, `lr-resume-8ad3a9d2`. The `lr-*` are our own `account-relogin`/`limit-recover` skill. | MEASURED |
| 🚨 Correction to the brief's machine facts | The brief says *"pgrep tmux returned 1 process, 0 'tmux: server'"*. There are **2** tmux processes (24649 ppid=1 = the server, 8626 = a client), and the server IS live and serving 5 sessions. **`pgrep -c` does not exist on macOS BSD pgrep** — it exits rc=2 with a usage error, so any `pgrep -c … \|\| echo 0` reads **0 for every input**. A null from a blind instrument. | `pgrep -c tmux` → `usage: pgrep [-Lfilnoqvx] …` `rc=2` | MEASURED |

### 2.7 The teammate backend registry — found on this axis, belongs to A1/A2

Not my axis, but it is the single most load-bearing string I hit and the wave needs it:

```
teammateMode: E.enum(["tmux","iterm2","in-process","auto"]).describe("How spawned teammates execute (tmux, iterm2, in-process, auto)")
[BackendRegistry] Selected: iterm2 (native iTerm2 with it2 CLI)
[BackendRegistry] Selected: tmux (running inside tmux session)
[BackendRegistry] Selected: tmux (fallback in iTerm2, it2 setup recommended)
[BackendRegistry] Marking in-process fallback as active
[BackendRegistry] isInProcessEnabled: true (non-interactive session)
[BackendRegistry] isInProcessEnabled: true (fallback after pane backend unavailable)
[BackendRegistry] isInProcessEnabled: <b> (mode=<m>, insideTmux=<t>, inITerm2=<i>)
```

⇒ **A teammate does not necessarily take a pane — `in-process` is a first-class backend and is auto-selected for
non-interactive sessions.** But note the live counter-evidence on *this* box: 8 `claude.exe --agent-id A<N>-…`
processes exist as **separate OS processes with no pane**, so "in-process" plausibly means *no pane backend*, not
*same OS process*. **INFERRED — hand to A1/A2 to settle.** Corroborating: `agent-view-coverage-2026-07-31.md` §6
records that `--agent-id` processes are excluded from CC's session registry **by design** — *"they are not sessions"*.
That is an **accounting** verdict, not a **resource** verdict; they still cost 306.7 M footprint each (§2.3).

---

## 3. DOES OUR INFRASTRUCTURE KNOW ABOUT IT? — measured, with a positive control

`grep -rIl --exclude-dir={.git,node_modules,.worktrees} -F "<term>" .` in `~/Development/claude-infrastructure`:

| Term | Files | Meaning |
|---|---|---|
| `bg-pty-host` | **0** | — |
| `cc-daemon` | **0** | — |
| `roster.json` | **0** | — |
| `--bg` | **0** | we never launch a background session |
| `AGENT_VIEW` / `disableAgentView` | **0** / **0** | — |
| `claude agents` | 6 | `bin/cc-queue`, `tests/cc-queue.bats`, `docs/research/agent-view-coverage-2026-07-31.md`, `docs/plans/TERMINAL_AGNOSTIC_L3_L4.md`, `docs/plans/CLOUD_OBSERVABILITY.md`, `scripts/boot-resume.sh` |
| **positive control** `ITERM_SESSION_ID` | **153** | instrument works |
| **positive control** `handoff-fire` | **516** | instrument works |

**Two parallel registries exist and neither knows about the other:**

| | CC's | Ours |
|---|---|---|
| Path | `<CLAUDE_CONFIG_DIR>/sessions/<PID>.json` | `~/.claude/cc-registry/<PANE>.json` |
| Key | **PID** | **PANE** |
| Rows | 3 (`~/.claude`, symlinked from `~/.claude-next`) + 4 (`~/.claude-secondary`) | **19** |
| Liveness | **7 registered / 7 alive** (self-GC'd) | 19 rows, pane-keyed, staleness not checked here |
| Sample row | `{"pid":69257,"sessionId":"020aafc9-…","cwd":"…/wt-pool-2","procStart":"Wed Aug 19 11:35:54 2026","version":"2.1.220","kind":"interactive","status":"shell","statusUpdatedAt":…,"bridgeSessionId":"session_01M6qu…"}` | pane-keyed |

CC's registry carries `status` (`busy`/`waiting`/`shell`) and `waitingFor:"permission prompt"` **for free** —
which is a large part of what our beacon/`cc-inbox-guard`/supervisor machinery exists to reconstruct.

### 🚨 The gap, demonstrated LIVE by the probe (not argued)

When my background session ran, **our own hooks fired inside it** and armed a watcher that nothing can ever reach:

```
81316  81314  04:33  /bin/bash /Users/chrisren/.claude/hooks/../bin/cc-await-ping 4925e5d0-ee40-4fb7-abd8-0d038c483c16 --timeout 14340 --interval 15
/Users/chrisren/.claude/cc-beats/4925e5d0-ee40-4fb7-abd8-0d038c483c16.json
```

Read that carefully: a **4-hour** `cc-await-ping` armed on a **session-UUID that has no pane**, plus a heartbeat file
in `cc-beats/`. So:

| Rail | Behaviour on a paneless session | Verdict |
|---|---|---|
| Hooks | **fire normally** — `claude logs` shows `running 12 hooks` and our Stop block (`OPERATOR ▸ 13 runnable now, 153 need your call`) rendered *inside* the bg worker | works |
| `cc-beats` | **written** (session-UUID keyed) | works by luck |
| `cc-await-ping` / mailbox wake | **armed on a UUID with no pane** — the wake path is `it2`/kitty pane addressing, so it can never be woken; it just burns 4 h and exits | **BROKEN — silent** |
| `cc-registry` / `cc-panes` / `cc-where` / `cc-discover` | pane-keyed ⇒ **cannot see it at all** | **BLIND** |
| `handoff-fire` capacity gate (`CC_FIRE_MAX_LOAD_PER_CORE`) | keyed on load average, so it *does* feel bg workers' threads — but it cannot **count** them or attribute them | partial |
| `cc-reaper` / `cc-teardown` | pane-keyed ⇒ **cannot reap a bg worker**; conversely CC's own retire logic would kill one out from under us | **BLIND** |
| Landing a bg session's work | nothing in our repo reads `jobs/<short>/state.json` | **BLIND** |

**If we ever adopt `--bg`, our fleet accounting silently under-counts by exactly the number of background
sessions, and every wake/reap/land rail is inert for them.** The `cc-await-ping` orphan above is not hypothetical —
I produced it in one command, and it survived `claude stop` (see §4).

---

## 4. What I tried that did NOT work / could not be measured

1. **The daemon was already dead when I started.** `/tmp/cc-daemon-501/` was an *empty* dir (mtime 04:40:42), and
   the brief's quartet (pids 59451/…) had exited 3 min earlier. All §2.3 numbers therefore come from **my own**
   probe daemon (pid 80000), not from the brief's observation. The brief's RSS figures (317/265/258/411 MB) are
   consistent with mine (305/255/257/475 MB) — same architecture, different instance.
2. **No matched-context memory comparison.** The bg worker was 10 s old; the foreground sessions had hours of
   context. Fixing this needs two sessions driven to the same token count — out of scope read-only.
3. **`grep -o '.\{0,700\}TOKEN.\{0,700\}'` fails** — BSD `grep` caps interval repetition at 255
   (`grep: invalid repetition count(s)`). Every context extraction here went through a Python `str.find` window instead.
4. **`pgrep -c` does not exist on macOS** (rc=2, usage error). Any `pgrep -c X || echo 0` idiom reports 0 always.
   This is what made the brief's tmux fact wrong. (§2.6)
5. **`claude stop <id>` did not immediately reap my hook's `cc-await-ping`** — the watcher survived SIGTERM for
   >4 min and needed a `kill -9`. This corroborates existing backlog task **#127** (*"cc-await-ping dies with exit
   144 — the armed wake path silently disarms"*) from a new direction: it also fails to **die** on demand.
6. **Could not observe a multi-worker daemon.** Only one bg job was ever alive at once during my window; the
   4-concurrent figure is from the July log, not from live measurement.
7. **Numeric defaults inside compiled paths are unreadable.** The Bun binary keeps the feature-flag *names* and
   the *default literals* in the readable JS shim, but the sweep's machine code is not readable — so anything
   below the `Ke("name",default)` layer is unverified.

**Everything I spawned, and its teardown:** one `claude --bg 'Reply with the single word PROBE. Do not use any
tools.'` in the scratchpad dir → job `4925e5d0`, daemon pid 80000, 4 child processes. Torn down with
`claude stop 4925e5d0`, `rm -rf ~/.claude-secondary/jobs/4925e5d0`, `rm -f ~/.claude/cc-beats/4925e5d0-*.json`,
`kill -9 81316`. Verified clean: `claude agents --json --all` returns the operator's original 3 jobs and nothing
else; `claude daemon status` → `not running`; `ps | grep 4925e5d0` → empty. **No live-fleet process was touched.**

---

## 5. Open questions for the verifier

1. **Is `in-process` teammateMode a same-OS-process execution mode, or just "no pane backend"?** §2.7 —
   the strings say one thing, the 8 live `--agent-id` processes say another. This is the wave's crux and I only
   have half of it. Settle by setting `teammateMode:"in-process"` and counting `claude.exe` processes before/after.
2. **Does `CLAUDE_CODE_FORCE_SESSION_PERSISTENCE=1` actually make our split-pane sessions register?**
   `agent-view-coverage-2026-07-31.md` §6 reads it from the binary but flags it **not runtime-verified**. If true,
   our 19-row pane registry could be replaced by (or reconciled against) CC's self-GC'ing PID registry, which
   already carries `status` + `waitingFor` for free. One launcher env var, big payoff.
3. **What is `kern.memorystatus_vm_pressure_level` on this box at ~15 sessions?** If it is still 1 (NORMAL) at
   the point where we are actually wedged, then CC's *only* admission gate is provably useless for us, and the
   right move is to reuse its **evictor** (retire-on-idle) rather than its **gate**. Measure:
   `sysctl kern.memorystatus_vm_pressure_level` under load. I could not — the box was at ~71% free.
4. **Does a retired worker's `--resume` restore full fidelity** (todos, MCP, hooks state), or just the transcript?
   `state.json` carries `resumeSessionId` + `respawnFlags` + `linkScanOffset` but I did not exercise a resume.
5. **Is the 1-deep spare pool a per-daemon or per-config-dir singleton, and does it survive with 0 jobs?**
   Log shows refill-on-claim; I never observed 2 spares. If it is 1 per daemon and we run 4 daemons (one per
   account), the standing prewarm tax is 4 × ~183 M (pty host + spare) even with zero background work.
6. **`tengu_bg_low_mem_mb` on Linux vs macOS diverge completely** (free-RAM vs VM-pressure). Anyone porting a
   conclusion from Anthropic's docs or from a Linux box will get the wrong gate. Worth pinning as a corpus fact.

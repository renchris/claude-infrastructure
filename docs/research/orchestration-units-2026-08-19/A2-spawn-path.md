# A2 — Binary archaeology of the agent spawn path (2.1.220), and how it changed

Axis: when did Claude Code move subagents out of process, and what exactly does each spawn?
Method: static read of the `bin/claude.exe` bundle (Bun SEA, not `cli.js` — see §3 correction) at byte
offsets, cross-checked against the LIVE process table and Anthropic's own CHANGELOG.

---

## 1. Verdict (≤5 lines)

1. **There are THREE spawn units, not one, and only ONE of them costs a pane/process.** A **teammate**
   (`Agent({name})`) is a full separate `claude.exe --agent-id …` OS process, launched by *typing a shell
   command into a terminal pane*. A **plain research subagent** (`Agent`/Task with no name) and a **Dynamic
   Workflow `agent()`** are both **in-process** — zero panes, zero processes.
2. **The operator's hypothesis is HALF right, and the half that is right is the half our own CLAUDE.md
   mandates.** "Every subagent takes a pane slot" is TRUE of teammates and has been true since agent teams
   shipped (2.1.32); it was NEVER true of plain subagents or workflows.
3. **Workflows run 50-200 agents because they are ONE process with a semaphore.** The workflow `agent()`
   primitive is wrapped in a concurrency limiter of `min(16, max(2, os.cpus().length − 2))` = **8 on this
   box**, with a cumulative cap of **1000 calls per run**. "200 agents" is throughput through an 8-wide
   gate, not 200 concurrent anything.
4. **Out-of-process teammates predate every bundle we hold (≥2.1.113); the daemon + bg-pty-host + Dynamic
   Workflows all arrived in the 2.1.114→2.1.156 window** (changelog: daemon ~2.1.140, workflows 2.1.154).
5. **The newest levers are the interesting ones**: `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS` (default **20**,
   new in 2.1.217, absent from 2.1.215) and `CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY` (default **10**) — the
   latter is the *real* per-turn fan-out ceiling. 2.1.224 **removed** the 200/session cap entirely.

---

## 2. The numbers table

### 2a. What each unit actually is

| Unit | How it is spawned | OS cost | Concurrency bound (this box) | Evidence |
|---|---|---|---|---|
| **Teammate** `Agent({name})` | shell command typed into a terminal pane | **1 full `claude.exe` process** + its own MCP servers + its own hooks | none in CC; our `KMAX=8`/pane budget is ours | `$W_` at byte 234638563 + live `ps` |
| **Teammate, tmux backend** (`use_splitpane:false`) | `tmux new-window … -- cat`, then command | same | same | `UW_` at 234643xxx |
| **Teammate, in-process fallback** | `ivd()` — no pane at all | **0 processes** | shares session | `ivd` at 234645xxx |
| **Plain subagent** (`Agent`/Task, no name) | in-process agent loop, `type:"local_agent"` | **0 processes, 0 panes** | 20 concurrent / 200 cumulative / depth 3 | my own `$PPID` (below) |
| **Dynamic Workflow** | `vm.runInContext()` in the SAME process | **0 processes, 0 panes** | **8 concurrent**, 1000 cumulative | `uTd` at 234439475 |

### 2b. The teammate command line, verbatim from the bundle

`bin/claude.exe` byte **234638563** (function `$W_`, the iTerm2/pane backend). Extracted with:

```
dd if=…/bin/claude.exe bs=1 skip=$((234638563-3400)) count=6000 | tr -c '\11\12\15\40-\176' '.'
```

```js
let A = ULs(),                                    // the claude binary + prefix args
    I = [ `--agent-id ${$d([m])}`,
          `--agent-name ${$d([f])}`,
          `--team-name ${$d([d])}`,
          `--agent-color ${$d([g])}`,
          `--parent-session-id ${$d([kt()])}`,
          l ? "--plan-mode-required" : "",
          s ? `--agent-type ${$d([s])}` : "" ].filter(Boolean).join(" "),
    D = avd({planModeRequired:l, permissionMode:u.toolPermissionContext.mode,
             effortValue:u.effortValue, skipModel:!!c});
if (c) D = D ? `${D} --model ${$d([c])}` : `--model ${$d([c])}`;
let x = D ? ` ${D}` : "", O = qLs(),
    H = `cd ${$d([p])} && env ${O} ${$d(A)} ${I}${x}`;
…
await T.backend.sendCommandToPane(b, H, !v);      // ← literally typed into the pane
```

`avd()` (byte 234635110) contributes every remaining flag:

| Flag | Condition |
|---|---|
| `--dangerously-skip-permissions` | lead mode is `bypassPermissions` |
| `--permission-mode acceptEdits` \| `--permission-mode auto` | lead mode is that |
| `--model <m>` | always unless `skipModel` (falls back to `vw()`) |
| `--effort <e>` | `typeof effortValue === "string" && mXn()` |
| `--settings <path>` | `OVt() ?? Att()` |
| `--plugin-dir <d>` (repeatable) | each `a_e()` |
| `--plugin-dir-no-mcp <d>` (repeatable) | each `l_e()` |
| `--plugin-url <u>` (repeatable) | each `cMe()` |
| `--chrome` / `--no-chrome` | `ktt()` true/false |

**LIVE CONFIRMATION** — `ps -ww -o command= -p 17602`:

```
/Users/chrisren/.claude-220/node_modules/@anthropic-ai/claude-code/bin/claude.exe \
  --agent-id A10-hostile-reviewer@session-84bde2e9 --agent-name A10-hostile-reviewer \
  --team-name session-84bde2e9 --agent-color green \
  --parent-session-id 84bde2e9-bd00-4f1e-af05-1763ee55def6 --agent-type deep-research \
  --permission-mode auto --effort high \
  --settings /private/var/folders/…/cc-mcp-decision-off--…-wt-pool-8.json --model opus
```

Every field predicted by the code is present. MEASURED.

**Answer to "does the child get its own X?"** (the load-bearing part for the ceiling):

| Surface | Child gets its own? | Evidence |
|---|---|---|
| MCP server set | **YES** — full startup, no `--mcp-config`/`--strict-mcp-config` is passed, so it discovers its own | `ps -Ao pid,ppid,command \| awk '$2==17602'` → `node …/ms-365-mcp-server` (47 MB), a direct child. MEASURED |
| Hooks | **YES** | same command → `/bin/bash …/hooks/mailbox-wake-arm.sh`, a direct child. MEASURED |
| Permission mode | YES — passed explicitly (`--permission-mode auto`) | argv above |
| Model + effort | YES — passed explicitly (`--model opus --effort high`) | argv above |
| Settings file | YES — passed explicitly (`--settings <path>`) | argv above |
| Statusline | INFERRED yes — it is a full interactive CLI startup with no suppressing flag; not directly observed |

Env prefix `qLs()` (byte 234631667): always `CLAUDECODE=1 CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`, then an
**allowlist** `LW_` (Bedrock/Vertex/Foundry/Mantle/AWS/GCP vars, `CLAUDE_CODE_SUBAGENT_MODEL`,
`ANTHROPIC_BASE_URL`, `CLAUDE_CONFIG_DIR`, `CLAUDE_CODE_REMOTE*`, proxy vars, telemetry opt-outs), plus
`CLAUDE_SECURESTORAGE_CONFIG_DIR`. It **deletes** `CLAUDE_CODE_HOST_CREDS_FILE`. The binary itself comes from
`ULs()`, overridable by **`CLAUDE_CODE_TEAMMATE_COMMAND`** (byte 230485238: `ADu="CLAUDE_CODE_TEAMMATE_COMMAND"`).

### 2c. The dispatcher — three backends, and which one you get

Byte 234647xxx, function `qW_`:

```js
if (Lrn()) return ivd(e,t);                       // in-process
try { await Prn() } catch (o) {
  if (KMt() !== "auto") throw …;                  // teammateMode pinned → hard fail
  … "falling back to in-process" …; return ivd(e,t)
}
if (e.use_splitpane !== !1) return $W_(e,t);      // pane backend
return UW_(e,t);                                  // tmux new-window backend
```

`Lrn()` (byte 232759168) — **isInProcessEnabled**:

```js
if (_n()) return true;                            // NON-INTERACTIVE session ⇒ ALWAYS in-process
let t = gP_();                                    // settings teammateMode
if (t === "in-process") r = true;
else if (t === "tmux" || t === "iterm2") r = false;
else { if (fallbackActive) return true;
       r = !isInsideTmux() && !isInITerm2(); }     // neither ⇒ in-process
```

`wpe()` = isInITerm2 (byte 230485839): `TERM_PROGRAM === "iTerm.app" || !!ITERM_SESSION_ID || terminal === "iTerm.app"`.
**This box runs kitty, but our repo exports `ITERM_SESSION_ID` into every pane**, so `wpe()` is true and
teammates take the pane backend. Unset it (or set `teammateMode: "in-process"`) and teammates would stop
costing processes entirely — see §5 open question 1.

`KMt()` default when no snapshot: `nrn = "in-process"`.

### 2d. Dynamic Workflows — one process, one VM, one semaphore

| Fact | Value | Command / byte |
|---|---|---|
| Execution substrate | `require("vm")` → `createContext(…, {codeGeneration:{strings:false,wasm:false}})` → `runInContext` | byte 234437900 (`lTd`), 234439475 (`uTd`) |
| Globals injected | `agent`, `parallel`, `pipeline`, `workflow`, `args`, `log`, `phase`, `console`, `budget`, `setTimeout`, `clearTimeout` | byte 234438825 |
| Local-agent concurrency limiter | `B = CB(Qq_, K)` where `Qq_ = Xq_(os.cpus().length)` and `Xq_(e) = Math.min(16, Math.max(2, e-2))` | bytes 234412551, 234411112 |
| …value on this box | **8** (`node -p "Math.min(16,Math.max(2,require('os').cpus().length-2))"` → `8`; `os.cpus().length` → `10`) | MEASURED |
| Limiter implementation | `CB(e,t)` = counting semaphore, queue on overflow (byte 229153268) | MEASURED |
| Remote-agent limiter | `j = CB(Zq_=50, re)` — but `agent({isolation:'remote'})` **throws** `"not available in this build"` in 2.1.220 | byte 234429972 |
| Cumulative `agent()` cap per run | **1000** (`QSd=1000`); error: *"Workflow agent() call cap reached (1000)"* | bytes 234411886, 234432125 |
| `parallel()` internals | `Promise.allSettled(items.map(...))` — **no limiter of its own**; every item still passes through `B` | byte 234430131 |
| Advisory size guideline | "aim for fewer than 15 agents" (medium), settable via `workflowSizeGuideline` / `CLAUDE_CODE_WORKFLOW_SIZE_WARNING_AGENTS` | CHANGELOG 2.1.219 |

**This is the direct answer to the operator's paradox.** A workflow that "runs 200 agents" issues 200
`agent()` calls that queue behind an 8-wide semaphore inside a single `claude.exe`. Concurrency 8;
throughput 200. Method rule 6, satisfied by construction.

### 2e. Plain subagents — self-evidencing proof they are in-process

I am a plain research subagent in this 13-agent wave. My Bash tool's parent chain:

```
$ echo "my pid=$$ ppid=$PPID"; walk ancestry with ps -o pid,ppid,rss,command
my pid=55362 ppid=99124
99124 99091 735200 /Users/chrisren/.claude-220/node_modules/.bin/claude --permission-mode auto --model claude-opus-5 --effort high
99091 83977   1040 bash /Users/chrisren/.claude/bin/cc-close-attrib …
83977   587   5504 /bin/zsh -l
  587     1 253408 /Applications/kitty.app/Contents/MacOS/kitty
```

My tool calls are children of the **ordinary session process (99124)**. There is no `--agent-id` process
for me, no pane, no extra kitty window. MEASURED, and it is the strongest single datapoint on this axis
because the instrument is the subject.

Caps that DO bind plain subagents (all read out of the bundle at byte 230703413 / 230685691):

```js
function wHu(){ return Z.CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS ?? Et_ }   // Et_ = 20
function XYr(){ return Z.CLAUDE_CODE_MAX_SUBAGENTS_PER_SESSION ?? vt_ }  // vt_ = 200
function bee(){ let e=Z.CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH; … }        // aHu = 3, gate tengu_hazel_trellis
function xN_(){ let e=Bd(process.env.CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY); return e>0?e:10 }
```

**`CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY` (default 10) is the tighter of the two** for a single message: a
turn cannot execute more than 10 tool calls concurrently, so a single message cannot start more than 10
subagents at once regardless of the 20-cap. The 20-cap is also **soft** — bypassed by feature flag
`tengu_amber_kestrel` and by `EK(mainLoopModel, effortValue, ultracode)`.

### 2f. VERSION DIFF — when did each mechanism arrive?

Command (whole script at `<scratch>/vdiff.sh`; each column is `/usr/bin/grep -ac -- '<tok>' bin/claude.exe`):

```
CTRL = grep -ac 'claude-opus'   ← positive control, proves the grep can find a string that IS present
```

| bundle dir | VERSION | MB | CTRL | `--agent-id` | `bg-pty-host` | `daemon run` | `in_process_teammate` | `createTeammatePaneInSwarmView` | `workflow_agent` | `MAX_CONCURRENT_SUBAGENTS` |
|---|---|---|---|---|---|---|---|---|---|---|
| `~/.claude-versions/2.1.113` | 2.1.113 | 195 | 158 | 13 | **0** | **0** | 73 | 9 | **0** | **0** |
| `~/.claude-versions/2.1.114` | 2.1.114 | 195 | 158 | 13 | **0** | **0** | 73 | 9 | **0** | **0** |
| `~/.claude-156` | 2.1.156 | 205 | 129 | 11 | 8 | 10 | 57 | 6 | 17 | **0** |
| `~/.claude-161` | 2.1.161 | 207 | 128 | 11 | 8 | 10 | 61 | 6 | 19 | **0** |
| `~/.claude-170` | 2.1.170 | 211 | 122 | 14 | 8 | 10 | 63 | 6 | 19 | **0** |
| `~/.claude-versions/2.1.183` | 2.1.183 | 205 | 136 | 14 | 8 | 10 | 71 | 6 | 19 | **0** |
| `~/.claude-183` | **2.1.215** ⚠ | 235 | 134 | 14 | 9 | 13 | 74 | 6 | 23 | **0** |
| `~/.claude-219` | 2.1.219 | 245 | 134 | 14 | 9 | 13 | 74 | 6 | 23 | 5 |
| `~/.claude-220` | 2.1.220 | 245 | 135 | 14 | 9 | 13 | 74 | 6 | 23 | 5 |

⚠ **Correction to the brief: `~/.claude-183` contains 2.1.215, not 2.1.183.** The real 2.1.183 is at
`~/.claude-versions/2.1.183`. (`node -p "require('<dir>/…/package.json').version"`.)

**Positive controls.** Every negative cell sits in a row whose CTRL column is 122-158, i.e. the same
`grep -ac` on the same file finds a string known to be present. Additionally `2.1.113` returns
`createTeammatePaneInSwarmView`=9 and `local_agent`=75 — so the teammate machinery and the in-process
subagent type are both findable there; the zeros for `bg-pty-host` / `daemon run` / `workflow_agent` are
real absences, not a blind instrument.

**Dating, cross-checked against Anthropic's CHANGELOG** (`~/.claude/cache/changelog.md`, 498 KB, mtime
2026-08-11 — QUOTED-FROM-DOC):

| Mechanism | First appears | Quote |
|---|---|---|
| Agent teams (pane-backed from birth) | **2.1.32** | *"Added research preview agent teams feature for multi-agent collaboration … requires CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1"*; 2.1.33 *"Fixed agent teammate sessions in tmux"*; 2.1.77 *"iTerm2 auto mode not detecting iTerm2 for native split-pane teammates"* |
| Background daemon / `claude --bg` | **~2.1.140** | first changelog mention 2.1.140; binary-absent at 2.1.114, present at 2.1.156 ✅ consistent |
| Dynamic Workflows | **2.1.154** | *"Introducing dynamic workflows: … it orchestrates work across tens to hundreds of agents in the background"* ← this sentence is the source of the operator's "50-200" |
| 200 subagents/session cap | **2.1.212** | *"Added a per-session cap on subagent spawns (default 200, override with CLAUDE_CODE_MAX_SUBAGENTS_PER_SESSION) … /clear resets the budget"* |
| 20 concurrent subagents cap | **2.1.217** | *"Added a cap on concurrently-running subagents (default 20, override with CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS) so one message can't fan out unbounded background agents"* ✅ matches the binary diff exactly (absent 2.1.215, present 2.1.219) |
| 200/session cap **REMOVED** | **2.1.224** | *"Removed the 200-subagent-per-session spawn cap; long-running sessions no longer refuse new agents (concurrency and depth limits still apply)"* |

**So: subagents were never moved out of process — they were never IN a pane.** What moved is the opposite
direction: 2.1.154 added an *entirely new* in-process unit (workflows) that can outrun the pane-based one
by two orders of magnitude, and 2.1.212/217 retro-fitted caps because in-process fan-out had become
unbounded.

### 2g. Is there a pool? (Q3)

**For teammates: NO.** Every `Agent({name})` call runs `createTeammatePaneInSwarmView` → new pane → new
shell → cold `claude.exe`. There is no lookup of an idle agent anywhere on that path. Observationally: of
the three teammate PIDs alive at the start of this investigation (8435, 17602, 28505), **two had exited
15 minutes later** (`ps -M -p 8435` → 0 threads) — one process per call, dies when the teammate stops.

**For DAEMON-backed background jobs: YES, a pool of exactly ONE.** Byte 241488319:

```js
async function SXo(e,t,r,n){ …
  if (kXe || uRr || _Xo) return;                 // kXe is a SINGLE slot
  if (iYe()) { Ne("job_spare_ensure","low_mem"); return }
  … let c = await Fle([...MCn,"--agent",l,...NCn(r)], o, "spare", s);
  … kXe = {jobId:i, sessionId:o, cwd:s, ready:false, defaults:r}
```

and the claim side, byte 238558587: `static claim(e,t){ let r = new _me(e, t.spawnPty, t.getAuthSnapshot, "spare", …) }`
versus `static spawn(...)` with `via:"cold"`. This is the `spare/` subdir the brief saw in
`/tmp/cc-daemon-501/<id>/`. It warms **one** worker so that the next `claude --bg` / routine / remote
trigger starts hot. It has nothing to do with teammates or subagents.

The same code region also carries a genuine **memory-aware admission gate** — the first one I have found
inside Claude Code itself (byte 238530998):

```js
function JKs(){ let e = Ke("tengu_bg_low_mem_mb",1024)*1024*1024;
  if (e<=0) return {lowMem:false};
  if (platform!=="macos") return {lowMem: os.freemem() < e};
  let t = f8y(); return {lowMem: t!==undefined && t>=d8y, level:t} }   // d8y = 4
```

`f8y()` dlopens `libSystem` via `bun:ffi` and `sysctlbyname("kern.memorystatus_vm_pressure_level")`.
`d8y=4` = **CRITICAL**. Live now: `sysctl kern.memorystatus_vm_pressure_level` → `1` (NORMAL);
`memory_pressure -Q` → *"System-wide memory free percentage: 71%"*. So this gate is real but fires only at
the jetsam edge — it is not a working admission control for our ceiling.
Sibling mechanism, byte 235581923: `process.on("memoryPressure", …)` **reaps background shells**, disabled
by `CLAUDE_CODE_DISABLE_BG_SHELL_PRESSURE_REAP`.

### 2h. Cost of a teammate vs a session (footprint, not summed RSS)

`/usr/bin/footprint -p <pid>` + `ps -M -p <pid> | wc -l`:

| pid | role | threads | RSS (KB) | **phys_footprint** |
|---|---|---|---|---|
| 17602 | teammate `--agent-id A10-hostile-reviewer` | 18 | 472 096 | **280 MB** |
| 99124 | ordinary session (my parent) | 30 | 833 664 | **360 MB** |
| 53709 | ordinary session | 28 | 454 080 | **363 MB** |

A teammate is ~0.77× a session by footprint and ~0.6× by threads — **it is a slot, not a rounding error**.
Note RSS/footprint = 1.69× for 17602 and 2.31× for 99124: summing RSS would have overstated by ~2×, exactly
the trap method rule 2 names. (Plus each teammate's own MCP children — one measured at 47 MB.)

### 2i. Resource knobs the bundle reads (Q4)

`/usr/bin/grep -ao 'CLAUDE_CODE_[A-Z0-9_]*' bin/claude.exe | sort -u | wc -l` → **435 distinct**
(full list at `<scratch>/env-cc.txt`). The ones that are levers on *this* ceiling:

| Env var | Default (read from bundle) | Why it matters | byte |
|---|---|---|---|
| **`CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY`** | **10** | hard cap on concurrent tool calls per turn ⇒ the real per-message fan-out ceiling | 233195473 |
| **`CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS`** | **20** | concurrent in-process subagents; new in 2.1.217; SOFT (flag + effort bypass) | 230703356 |
| `CLAUDE_CODE_MAX_SUBAGENTS_PER_SESSION` | 200 | cumulative, `/clear` resets; **removed upstream in 2.1.224** | 230703413 |
| `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` | 3 (flag `tengu_hazel_trellis`) | nesting; after 2.1.224 this is the ONLY runaway bound left | 230685691 |
| **`CLAUDE_CODE_TEAMMATE_COMMAND`** | unset ⇒ `oR({pinToCurrentBinary:true})` | replaces the teammate launch command entirely — the hook point for admission control on teammate spawn | 230485238 |
| `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` | must be `1` | teams off ⇒ no teammate processes at all | 226143671 |
| `CLAUDE_CODE_WORKFLOW_SIZE_WARNING_AGENTS` / `_TOKENS` | flag `tengu_ochre_gantry` | advisory only (warns, does not block) | 242844162 |
| `CLAUDE_CODE_DISABLE_BG_SHELL_PRESSURE_REAP` | unset ⇒ reaping ON | disables the `memoryPressure` background-shell reaper | 235581923 |
| `CLAUDE_CODE_PLAN_V2_AGENT_COUNT` / `_EXPLORE_AGENT_COUNT` | clamped 1..10; **3** on `max_20x`, else 1 | plan-mode fan-out | 238004254 |
| `CLAUDE_CODE_SUBAGENT_MODEL` | — | forwarded to teammates in the env allowlist | 234631667 |
| `CLAUDE_CODE_MAX_TURNS`, `_MAX_RETRIES`, `_MAX_OUTPUT_TOKENS`, `_MAX_CONTEXT_TOKENS`, `_MAX_WEB_SEARCHES_PER_SESSION` (200) | — | secondary | env-cc.txt |
| `CLAUDE_CODE_DAEMON_COLD_START`, `CLAUDE_CODE_WORKER_EPOCH` | — | daemon spare/worker lifecycle | env-cc.txt |
| settings key `teammateMode` | `"in-process"` when no snapshot | `iterm2` \| `tmux` \| `in-process` — **the single biggest lever**: `in-process` makes teammates cost zero processes | 232656170 |

`grep -aoE '\bMAX_[A-Z0-9_]{3,}' | sort -u` → 82 distinct, but they are overwhelmingly SDK/vendor
constants (`MAX_STRUCTURED_OUTPUT_RETRIES`, `MCP_REMOTE_SERVER_CONNECTION_BATCH_SIZE`, …), not concurrency
levers. Full list at `<scratch>/env-max.txt`.

---

## 3. What did NOT work / could not be measured

1. **`cli.js` does not exist in 2.1.220 — correction to the brief.** The package ships exactly one
   artifact: `bin/claude.exe`, a **256 908 272-byte Mach-O arm64 Bun single-executable**
   (`file` → `Mach-O 64-bit executable arm64`). All nine installs on disk are the same shape. Every quote
   above is a byte-offset extraction from that binary, not a source read. Method used throughout:
   `dd if=<bin> bs=1 skip=$((OFF-N)) count=$((N+M)) | tr -c '\11\12\15\40-\176' '.'`.
2. **Cannot date the birth of out-of-process teammates from local artifacts.** `--agent-id` is present in
   the oldest bundle we hold (2.1.113). The CHANGELOG puts agent teams at 2.1.32 with tmux/iTerm2 pane
   fixes at 2.1.33/2.1.77, which is doc evidence that they were pane-backed from the start — but no
   pre-2.1.113 binary exists on this box to confirm by grep. `~/.npm/_cacache` has claude-code index
   entries; I did not try to reconstruct old tarballs from it (would be the way to close this).
3. **`tr` aborted with "Illegal byte sequence" at offset 173998528** until I dropped `tr -d '\000'` and
   used a single `LC_ALL=C tr -c` pass. Any window dump that looks empty in an earlier attempt is that,
   not an absence.
4. **`grep -c` on a binary counts LINES, not occurrences.** The version-diff table is an existence test
   only; its magnitudes are not comparable across versions (minified line boundaries shift).
5. **The daemon and bg-pty-host processes named in the brief were GONE by the time I looked**
   (`/tmp/cc-daemon-501/` is empty; `ps | grep -E 'bg-pty-host|daemon run'` → nothing). So the warm-spare
   mechanism is described from code, not caught in the act. The `spare/` directory the brief observed is
   the exact artifact of `SXo`/`claim` above.
6. **Statusline-per-teammate is INFERRED, not measured** — a statusline command runs periodically and I did
   not catch one under a teammate pid. MCP servers and hooks under a teammate WERE caught.
7. **No live probe was spawned.** Read-only throughout; nothing killed, stopped, or torn down. The only
   thing I created is scratch files under the session scratchpad.
8. **`agent({isolation:'remote'})` is dead code in 2.1.220** — `throw Error("agent({isolation:'remote'}) is
   not available in this build")` — so the 50-wide remote limiter (`Zq_=50`) is unreachable and cannot be
   used to push work off-box today.

---

## 4. Open questions for the verifier

1. **Would `teammateMode: "in-process"` (or unsetting `ITERM_SESSION_ID` before spawn) actually eliminate
   teammate processes on this box, and at what cost?** The code says yes unconditionally. But our whole
   pane-visibility stack (`cc-panes`, `cc-where`, `handoff-fire`, `cc-pane-runner`, the swarm view) is
   built on teammates *being* panes. This is a real fork, not a free win — someone should price it.
2. **Is `CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY=10` the binding constraint on our N=12 default research
   fan-out?** Our `research-subagents` skill defaults to N=12 in one message. If the per-turn tool
   concurrency is 10, the 11th and 12th queue. That is invisible and would look like "slow agents".
   Verify by timing a 12-wide fan-out against a 10-wide one.
3. **Does the 8-wide workflow semaphore make workflows *worse* than subagents on a 10-core box?**
   `Xq_(ncpu) = min(16, max(2, ncpu-2))` is sized as if `agent()` were CPU-bound, but an `agent()` call is
   an HTTPS request that spends ~all its time in network wait. 8 may be leaving throughput on the table for
   the one unit that costs us zero processes. There is no env override for it — only `os.cpus().length`,
   which nothing but the hardware sets.
4. **2.1.224 removed the 200/session cap** (changelog, and our own `MANIFEST.jsonl` 2.1.224 entry already
   flags it). If we ever advance past 2.1.223, depth-3 becomes the only runaway bound on a box that fans
   out N=12 by default. Does our admission gate (`CC_FIRE_MAX_LOAD_PER_CORE`) see in-process subagents at
   all? It keys on load average, and 8-20 in-process agents are mostly network-blocked — i.e. **invisible
   to a runnable-thread metric**. This looks like a genuine blind spot in our own gate.
5. **`kern.memorystatus_vm_pressure_level >= 4` is CRITICAL-only.** Claude Code's own low-mem gate
   therefore never fires before jetsam. If we want CC to self-throttle, `tengu_bg_low_mem_mb` is a Statsig
   flag we cannot set — but the same sysctl is trivially readable by `handoff-fire.sh`, and level 2 (WARN)
   would be an earlier, cheaper signal than load-per-core. Worth a second opinion on whether WARN is too
   noisy on a 64 GiB box.
6. **Unverified magnitude:** does a teammate's own MCP server set fully duplicate the lead's? I measured
   ONE MCP child (`ms-365-mcp-server`) under one teammate. If a teammate starts the full user-scope MCP
   set, the per-teammate cost is well above the 280 MB footprint measured for the CC process alone.

# D — Vendor pane backends in Claude Code 2.1.260

Subject: the three teammate backends (`in-process`, `tmux`, `iterm2`), every external command each
issues across a teammate's life, and what is left on screen when a teammate ends.

Method: byte offsets are into the **unstripped embedded JS source** inside
`~/.claude-260/node_modules/@anthropic-ai/claude-code/bin/claude.exe` (196,228,254 bytes). The bun
binary embeds each chunk's readable source at ~150M–192M; the `strings`-table copies of the same
literals sit at ~69M–79M and are NOT cited except where noted. Baseline
`~/.claude-220/.../claude.exe` (255,444,993 bytes) checked for drift. Every claim below is marked
**[E]** empirical (read out of the binary) or **[I]** inferred (about tmux/it2/iTerm2 behaviour the
binary does not itself contain).

Minified symbol → role map used throughout (all [E]):

| sym | role | offset |
|---|---|---|
| `ycr` | `TmuxBackend` class | 173462610 |
| `g` (chunk-ds7x76q4) | `ITermBackend` class | 181088566 |
| `N1t` | `respawnPaneWithCommand` (tmux) | 173462457 |
| `Ndt` | `detectPaneBackend` (BackendRegistry) | 170254612 |
| `Cqe` | `isInProcessEnabled` | 170258968 |
| `Aqe` | `getBackendByType` | 170258806 |
| `MPe` (chunk-teammate-mode) | `getTeammateModeFromSnapshot` | 167981054 |
| `Fdt` | `DEFAULT_TEAMMATE_MODE` | 167980160 |
| `Cyt` | `isPaneBackend` | 158275454 |
| `RV` | `updateTeamFile` (lock + read + mutate + write) | 158277799 |
| `Qmr` | `cleanupSessionTeams` | 158283440 |
| `zs` | teammate-side `handleShutdownApproval` | 172417930 |
| `Ugt` | `killInProcessTeammate` (task-registry kill) | 161931060 |
| `pe`/`ue`/`z` | spawn: split-pane / external-tmux-window / in-process | 173577300 / 173580900 / 173583900 |

Constants, all at **155645143–155645200** [E]:
`ms="team-lead"` · `pj="claude-swarm"` (tmux session) · `EQe="swarm-view"` (tmux window) ·
`fj="tmux"` (binary name) · `vme="cat"` (placeholder pane command) · `AQe()="claude-swarm-${pid}"`
(tmux `-L` socket for external mode) · env `CLAUDE_CODE_TEAMMATE_COMMAND`.

---

## 1. `teammateMode` — values, default, auto-detection

**Accepted values** [E] — `167802083`, commander option:

```js
new Y("--teammate-mode <mode>",'How to spawn teammates: "tmux", "iterm2", "in-process", or "auto"')
  .choices(["auto","tmux","iterm2","in-process"]).hideHelp()
```

Same four in the settings schema (`155098758`, `teammateMode:Y(Jor).optional().catch(void 0)
.describe("How spawned teammates execute (tmux, iterm2, in-process, auto)")`) and in the CLI parser
`kv()` at `167566746` (`H==="auto"||H==="tmux"||H==="iterm2"||H==="in-process"?H:void 0`).

**Default is `in-process`** [E] — `167980160`: `var Fdt="in-process"`. Unchanged in 2.1.220
(`231292800`: `var nrn="in-process"`). Resolution order (`$1t`, `167980806`): CLI override
(`--teammate-mode`) → `wo("teammateMode", Fdt)` settings chain → `"in-process"`. The value is
**snapshotted once at startup**; `MPe()` returns the snapshot and self-repairs by capturing if the
snapshot is null.

**The mode gates TWO independent decisions, and this is the part that is easy to get wrong.**

### 1a. `Cqe()` — "run in-process?" (`170258968`) [E]

```js
function Cqe(e=UV){
  if(ke()) return t("[BackendRegistry] isInProcessEnabled: true (non-interactive session)"),!0;
  let n=x(),a;                                   // x() = MPe()
  if(n==="in-process") a=!0;
  else if(n==="tmux"||n==="iterm2") a=!1;
  else { if(e.inProcessFallbackActive) return …,!0;
         let s=zSt(), i=nN(e); a=!s&&!i; }       // auto: neither tmux nor iTerm2 ⇒ in-process
  return t(`[BackendRegistry] isInProcessEnabled: ${a} (mode=${n}, insideTmux=${zSt()}, inITerm2=${nN(e)})`),a
}
```

`ke()` = non-interactive (`-p`/headless) ⇒ **always in-process, regardless of `teammateMode`**.

### 1b. `Ndt()` — "which pane backend?" (`170254612`) [E]

Ordered, first match wins, result cached in `cachedDetectionResult`:

| # | condition | selected | log line |
|---|---|---|---|
| 1 | `MPe()==="iterm2"` and `nN()` false | **throws** | `teammateMode is set to "iterm2" but this session is not running inside iTerm2. Launch Claude from iTerm2, or change teammateMode in settings.` (`170255500`) |
| 2 | `MPe()==="iterm2"` and `CNe()` false | **throws** | `teammateMode is set to "iterm2" but the it2 CLI is not reachable. Install it with \`pip install it2\` …` |
| 3 | `MPe()==="iterm2"`, both true | `iterm2` | `[BackendRegistry] Selected: iterm2 (explicit teammateMode)` |
| 4 | `insideTmux` | `tmux` | `Selected: tmux (running inside tmux session)` |
| 5 | `inITerm2` && !`preferTmuxOverIterm2` && it2 present | `iterm2` | `Selected: iterm2 (native iTerm2 with it2 CLI)` |
| 6 | `inITerm2` && tmux present | `tmux`, `isNative:false` | `Selected: tmux (fallback in iTerm2, it2 setup recommended)` |
| 7 | `inITerm2`, no it2, no tmux | **throws** | `iTerm2 detected but it2 CLI not installed. Install it2 with: pip install it2` |
| 8 | neither, tmux present | `tmux`, external mode | `Selected: tmux (external session mode)` |
| 9 | none | **throws** | per-OS "To use agent swarms, install tmux…" |

🚨 **There is no `MPe()==="tmux"` branch.** Explicit `tmux` only takes effect through `Cqe()`
(forces `a=!1`, i.e. *not* in-process) and then falls through rows 4–9 of the environment ladder. A
session with `teammateMode:"tmux"` inside iTerm2 with it2 installed and `preferTmuxOverIterm2`
unset **selects `iterm2`** (row 5). [E, by reading — no row in `Ndt` tests for `"tmux"`.]

### 1c. Environment probes (`158322889`–`158323400`) [E]

```js
var d=a.TMUX, T=a.TMUX_PANE;
function zSt(){return !!d}                 async function a6(){return zSt()}     // insideTmux
function z9t(){return T||null}             // $TMUX_PANE
function V9t(){if(!d)return null;return dt(d,",")||null}   // $TMUX socket path → `-S <sock>`
async function vre(){return (await Fe(fj,["-V"])).code===0}                      // tmux available
function nN(e=UV){ … let s=a.TERM_PROGRAM,i=!!a.ITERM_SESSION_ID,l=a.terminal==="iTerm.app",
                   n=s==="iTerm.app"||i||l; o.recordInITerm2(n); return n }      // inITerm2, CACHED
function oSn(e=UV){return e.terminalProbes.it2Command}
async function CNe(e=UV){ let o=a.SHELL||"/bin/zsh",
  s=await Fe(o,["-lc",`command -v ${c}`],{useCwd:!1,timeout:2000}),
  i=…stdout.split("\n").map(trim).filter(Boolean).at(-1)??"",
  n=i||c, r=await Fe(n,["session","list"]);
  if(i && r.code!==0 && (r.code===127||/ENOENT/i.test(r.error??""))) n=c,r=await Fe(n,["session","list"]);
  if(r.code!==0) return …,!1;
  e.terminalProbes.recordIt2Command(n); return !0 }
```

**Auto-detection by terminal** (mode `auto`, interactive) [E for the predicates, [I] for what each
terminal sets]:

| terminal | `$TMUX` | `nN()` | `Cqe()` | `Ndt()` selects |
|---|---|---|---|---|
| inside tmux (any host term) | set | — | false | **tmux** (row 4) |
| iTerm2, it2 installed + Python API on | unset | true | false | **iterm2** (row 5) |
| iTerm2, no it2, tmux installed | unset | true | false | **tmux**, `needsIt2Setup:true` → it2-install dialog (row 6) |
| kitty (stock) | unset | **false** — kitty sets `TERM_PROGRAM` to nothing iTerm-shaped and no `ITERM_SESSION_ID` | **true** | never called — **in-process** |
| plain Terminal.app | unset | false | **true** | never called — **in-process** |

**kitty only reaches a pane backend because the fleet forges `nN()`'s inputs.** `~/.zshrc`
synthesises `ITERM_SESSION_ID="w0t0p0:$KITTY_WINDOW_ID"` (documented in `bin/cc-pane-runner:34-37`
and `bin/it2-kitty:32-35`), which is sufficient: `nN()` is a *pure env check with no deeper probe*
(`158323100`). The fleet additionally pins `teammateMode:"iterm2"` in all three settings files
(`~/.claude/settings.json:66`, `~/.claude-quaternary/settings.json:1184`,
`~/.claude-next/settings.json:1156`), which takes row 3 and skips the environment ladder entirely.

---

## 2. Lifecycle table — every external command, per backend

`Fe(cmd,args)` / `Be(...)` are the spawn helpers. `d(e)=Fe(fj,[…socket,…e])` (tmux, current
server), `l(e,n)=Fe(fj,["-L",AQe(),...e],n)` (tmux, private `claude-swarm-<pid>` socket, external
mode), `d(e)=Fe(oSn(),e)` (it2 — **the cached resolved path from `CNe()`, not literally `it2`**,
`181088900`).

### 2a. In-process

| phase | external command | offset |
|---|---|---|
| spawn | **none.** `z()` writes the member row `{tmuxPaneId:"in-process",backendType:"in-process"}` then calls `spawnInProcessTeammate`/`startInProcessTeammate` inside the lead's own process, with its own `AbortController` registered in the lead's task registry | `173583900`–`173584500` |
| send | none — mailbox file write (`Ym`) + `retryWake?.emit()` | `172416500` |
| idle | `N5e(team,name,false)` → rewrites `config.json` member `isActive:false` from the teammate's Stop hook | `178137700` |
| shutdown | `zs()`: writes `shutdown_approved` to the lead's mailbox, then `W.abortController.abort()` — **no OS command** | `172418700` |
| kill (`TaskStop`) | `Ugt()` aborts; `paneTeardown` is `undefined` for `backendType:"in-process"` because `Cyt("in-process")===false` | `173583704`, `158275454` |
| lead exit | dies with the lead by construction (same process); `cleanupSessionTeams` skips it (`Cyt` filter) | `158283600` |

### 2b. tmux

Two sub-shapes. **Split-pane** (`pe()`, lead itself inside tmux, `use_splitpane!==false`) and
**external window** (`ue()`, `use_splitpane:false` → a detached `claude-swarm` session on a private
socket).

| phase | literal command (argv, in order) | offset |
|---|---|---|
| spawn — first teammate, leader present | `tmux [-S $TMUXSOCK] split-window -d -t <leaderPane> -h -l 70% -P -F '#{pane_id}' -- cat` | `173466100` |
| spawn — later teammates | `tmux … list-panes -t <win> -F '#{pane_id}'` then `split-window -d -t <midPane> {-v|-h} -P -F '#{pane_id}' -- cat` | `173466300` |
| spawn — external session | `tmux -L claude-swarm-<pid> has-session -t claude-swarm` → `new-session -d -s claude-swarm -n swarm-view -P -F '#{pane_id}' -- cat` (or `list-windows`/`new-window -t claude-swarm -n swarm-view …`) | `173464200`–`173465100` |
| spawn — external per-teammate window (`ue`) | `tmux new-window -t claude-swarm -n teammate-<slug> -P -F '#{pane_id}' -- cat` | `173580900` |
| decorate | `set-option -p -t <pane> window-style bg=default,fg=<c>` · `… pane-border-style fg=<c>` · `… pane-active-border-style fg=<c>` · `select-pane -t <pane> -T <name>` · `set-option -p -t <pane> pane-border-format '#[fg=<c>,bold] #{pane_title} #[default]'` · `set-option -w -t <win> pane-border-status top` | `173463500`–`173463900` |
| rebalance | leader mode: `select-layout -t <win> main-vertical` + `resize-pane -t <pane0> -x 30%` · external: `select-layout -t <win> tiled` | `173467300`, `173467600` |
| **send / launch** | `tmux [sock] set-option -p -t <pane> remain-on-exit failed` **then** `tmux [sock] respawn-pane -k -t <pane> -- <cmd>` (`N1t`) | `173462457` |
| idle | `config.json` `isActive` flip only — no tmux call | `178137700` |
| shutdown (teammate) | `zs()` writes `shutdown_approved{paneId,backendType}` then `setImmediate(()=>Rn(0,"other"))` — **the teammate exits its own process** | `172418700`, exit fn at `164076088` |
| shutdown (lead) | on reading `shutdown_approved`: `tmux [sock] kill-pane -t <paneId>` | `179218898` → `173463150` |
| kill (`TaskStop`) | `paneTeardown` → same `kill-pane`, bounded at 10 000 ms | `161931060`, `173583704` |
| spawn rollback | `D(()=>S.backend.killPane(A,!O))` / `D(()=>Fe(fj,["kill-pane","-t",A]))` — fires only if spawn fails **before** the commit callback `k()` | `173578801`, `173580413` |
| lead exit | `cleanupSessionTeams` → per member `kill-pane`, then `git worktree remove --force <path>`, then `rm -rf <teamDir>` | `158283440`–`158283700` |

**What happens to a tmux pane when its process exits** [E for the option set, [I] for tmux's
semantics]: the launcher sets `remain-on-exit failed` on the pane *before* `respawn-pane`. Under
tmux that means **exit 0 ⇒ the pane closes itself; non-zero ⇒ the pane stays as a dead pane** with
the last screen frozen. So a teammate that approves shutdown (`Rn(0,…)`, exit 0) removes its own
pane, and the lead's subsequent `kill-pane` is a no-op on an already-gone id. A teammate that
*crashes* leaves a dead pane that only `kill-pane` clears. There is **no dead-pane reaper**: grep
for `pane_dead` / `#{pane_dead}` returns 0 hits in the whole binary.

### 2c. iTerm2

The **complete** set of `it2` invocations in 2.1.260 — enumerated exhaustively by regex
`\["session"[^\]]{0,90}\]` over the whole binary, 17 matches of which 5 are it2 and the rest are
unrelated string arrays:

| offset | argv | when |
|---|---|---|
| `170253613` / `158323534` | `it2 session list` | **setup probe only** — `iln()` verify + `CNe()` availability gate |
| `181089212` | `it2 session split -v -s <leaderSessionId>` | first teammate, when `ITERM_SESSION_ID` contains a `:` |
| `181089309` | `it2 session split -v` | first teammate, no leader id parseable |
| `181089446` | `it2 session split -s <lastTeammateSessionId>` | every later teammate |
| `181089545` | `it2 session split` | later teammate, no recorded id |
| `181089691` | `it2 session list` | **only** on a split failure, to decide whether to prune |
| `181090473` | `it2 session send -s <id> $'\x15'` | first half of `sendCommandToPane` |
| `181090519` | `it2 session run -s <id> <cmd>` | second half of `sendCommandToPane` |
| `181090762` | `it2 session close -f -s <id>` | **`killPane` — the ONLY pane-close in the backend** |

Per-phase:

| phase | command | offset |
|---|---|---|
| spawn | `session split …` (above); new id parsed from stdout by `/Created new pane:\s*(.+)/` (`181088780`), pushed to `this.teammateSessionIds` | `181089100`–`181090000` |
| decorate | **none.** `setPaneBorderColor(){}`, `setPaneTitle(){}`, `enablePaneBorderStatus(){}` — three empty method bodies | `181090400` |
| send / launch | `session send -s <id> $'\x15'` then `session run -s <id> <cmd>`; `JEe(cmd)` refuses any control character first | `181090420`–`181090560` |
| idle | none — `config.json` `isActive` flip only | `178137700` |
| shutdown (teammate) | none — writes `shutdown_approved{paneId,backendType:"iterm2"}` then `Rn(0,"other")` | `172418700` |
| shutdown (lead) | `it2 session close -f -s <paneId>` from the InboxPoller | `179218898` |
| kill (`TaskStop`) | `paneTeardown` → `it2 session close -f -s <paneId>`, 10 s bound | `161931060` |
| spawn rollback | `killPane` → same close | `173578801` |
| lead exit | `cleanupSessionTeams` → per member `it2 session close -f -s <id>` | `158283640` |

**Dead-pane pruning is reactive only, never polled** [E, `181089600`–`181089800`]:

```js
let m=await d(r);
if(m.code!==0){
  if(i){                                     // i = the teammate session we targeted
    let l=await d(["session","list"]);
    if(l.code===0 && !l.stdout.includes(i)){
      t(`[ITermBackend] Split failed targeting dead session ${i}, pruning and retrying: ${m.stderr}`);
      let u=this.teammateSessionIds.indexOf(i); if(u!==-1) this.teammateSessionIds.splice(u,1);
      if(this.teammateSessionIds.length===0) this.firstPaneUsed=!1;
      continue;                              // retry the while(!0) loop
    }
  }
  throw new Dk(`Failed to create iTerm2 split pane: ${m.stderr}`)
}
```

There is no timer, no interval, no `session list` on any other path.

---

## 3. Every write to `teams/<team>/config.json`

All go through `RV` = `updateTeamFile` (`158277799`): `proper-lockfile` on `<path>.lock` (10
retries, 5–100 ms) in the legacy path, or a `storageV5` CAS loop with 5 attempts in `H`
(`158278400`). A mutator returning `false` means "no change, skip the write".

| # | writer | field(s) | trigger | offset |
|---|---|---|---|---|
| 1 | session-team init | creates the file: `{name,createdAt,leadAgentId,leadSessionId,members:[{agentId,name:"team-lead",agentType:"team-lead",joinedAt,tmuxPaneId:"leader",cwd,subscriptions:[],backendType:"in-process"}]}`, then `__n(teamName)` registers it for session cleanup | session startup with agent teams enabled | `180314560` |
| 2 | `W()` reserveTeammateIdentity | **push** `{agentId,name,color,joinedAt,tmuxPaneId:"",subscriptions:[],agentType,model,prompt,planModeRequired,cwd}` | first step of every spawn — **`tmuxPaneId` starts EMPTY** | `173576700` |
| 3 | `j()` | set `tmuxPaneId` + `backendType` on the just-added member | immediately after the pane exists (or `"in-process"`/`"in-process"` for 2a) | `173577100` |
| 4 | `h_n()` removeTeamMember | **splice** the member | spawn failed **before** the commit callback `k()` (the identity is rolled back; after `k()` the entry is deliberately kept — `[spawnTeammate] post-commit failure for …; entry kept (agent already running)`) | `158278254`, `173576926` |
| 5 | `N5e()` setMemberActive | `isActive = true` | the teammate's own `onQuery` turn start, `if(zr()){let Yn=ri(),Uo=kp(); if(Yn&&Uo) N5e(Yn,Uo,!0,io)}` | `158282094`, `179121781` |
| 6 | `N5e()` setMemberActive | `isActive = false` | the teammate's `Stop` hook (`teammate-idle-notification`) and `r6e` on turn failure | `178137901`, `178138557` |
| 7 | `XWt()`/`M5e()` setMemberMode | `mode` | permission-mode change propagated by the teammate | `158282004` |
| 8 | `ape()` removeTeammateFromTeamFile | filter out by `agentId` **or** `name` | lead's `yIo()`, on `shutdown_approved` — runs **after** the `killPane` | `158280346`, `179219067` |
| 9 | `L5e()` removeMemberByAgentId | splice, but **skips if `member.joinedAt >= onlyIfJoinedBefore`** (`Skipped stale removal of … (re-added after removal was initiated)`) | `Ugt()` = `TaskStop`/kill of a teammate | `158280983`, `161932141` |
| 10 | `RV` in `resumeInProcessTeammate` | bump `joinedAt`, else push a fresh row with `tmuxPaneId:"in-process",backendType:"in-process"` | resuming a stopped in-process teammate | `172400311` |
| 11 | `J()` in cleanup | not a field write — `rm -rf` of the whole team dir | lead exit | `158283561` |

🚨 **`isActive` is write-only inside the binary.** 242 occurrences of the token; filtering to those
within 300 chars of `members` yields exactly 2, both inside `N5e` itself (the setter's own
`s.isActive===n` short-circuit and the assignment). No consumer. [E] — it exists for external
readers, which is what makes fleet tooling that reads it legitimate but also unverified by the
product.

---

## 4. Lead exit — `cleanupSessionTeams` (`158283440`) [E]

```js
async function Qmr(e){return Sr("swarm_session_cleanup",async()=>{
  let r=i7t(); if(r.size===0)return;
  …await Promise.allSettled(n.map(a=>q(a,e)));   // q = pane kill
    await Promise.allSettled(n.map(a=>J(a,e)))   // J = worktrees + rm -rf teamdir
})}
async function q(e,r){ let n=await Tf(e,r); if(!n)return;
  let a=n.members.filter(m=>m.name!==ms && m.tmuxPaneId && m.backendType && Cyt(m.backendType));
  if(a.length===0)return;
  let [{ensureBackendsRegistered:o,getBackendByType:i},{isInsideTmux:s}]=await Promise.all([…]);
  await o(); let c=!await s();
  await Promise.allSettled(a.map(async m=>{ …
    let d=await i(m.backendType).killPane(m.tmuxPaneId,c);
    t(`cleanupSessionTeams: killPane ${m.name} (${m.backendType} ${m.tmuxPaneId}) → ${d}`) }))}
```

Registered as a **cleanup handler** at init (`167650870`):
`Tt(async()=>{let{cleanupSessionTeams:o}=await import("…");await o(r)})`, where
`Tt(e)=R().cleanup.register(e)` (`154178428`).

🚨 **The whole cleanup registry is raced against a 2-second timeout** (`164072500`) [E]:

```js
let C=(async()=>{try{await gke()}catch{}})();
await Promise.race([C,new Promise((D,N)=>{E=setTimeout(F=>F(new upr),Qge,N)})]);
```

with `Qge=2000` (`154178300`) and `upr` = `"Cleanup timeout"`. Each `it2 session close` is a fresh
Python-CLI process talking to iTerm2's Python API; N of them inside one 2 s budget is the failure
mode to expect at wide fan-out. The failure is **silent** — the race result is discarded by
`catch{}` and `Promise.allSettled`.

`cleanupSessionTeams` only reaches the drain on a **graceful** `shutdown()`. `forceExit`, SIGKILL,
a kernel panic, or a pane closed out from under the process all skip it entirely. [E — `shutdown()`
is the only caller of `gke()` in the exit path; `shutdownSync` delegates to the same `shutdown`.]

---

## 5. Answer: stock iTerm2 mode with the real `it2` CLI — what is left on screen

**A pane closes if, and only if, `ITermBackend.killPane` runs, and killPane runs on exactly four
occasions: a graceful `shutdown_approved` observed by the lead, a `TaskStop`/abort of the teammate's
task-registry entry, a spawn that failed before commit, and the lead's own graceful session exit
inside a 2-second cleanup budget.** On a graceful shutdown the sequence is: the teammate reads its
own `tmuxPaneId`/`backendType` out of `config.json`, writes `shutdown_approved{requestId,from,
paneId,backendType}` into the lead's mailbox, and calls `Rn(0,"other")` — **it kills its own
process, it does not touch its own pane** (`172418700`). The lead's InboxPoller then sees that frame
and issues `it2 session close -f -s <paneId>` (`179218898`), and only afterwards removes the member
from the team file. So in the happy path the pane does disappear, but **the lead is the one that
closes it, asynchronously, in a fire-and-forget IIFE whose failure is logged and otherwise ignored**
(`[InboxPoller] Failed to kill pane for <name>: …`). In every *other* ending — the teammate crashes,
is `^C`'d, hits a context wall, runs `/exit` itself, or the lead is SIGKILLed — **nothing closes the
pane**: unlike tmux, which the backend arms with `remain-on-exit failed` so a clean exit collapses
the pane by itself, iTerm2 panes are ordinary shell sessions that the binary never configures (all
three decorate methods are empty stubs) and never polls; `it2 session list` is consulted only when a
*subsequent split* fails, and the only remedy it applies is to forget the dead id from an in-memory
array so the next split retargets — it never closes anything. The residue is therefore a live
interactive shell sitting at a prompt in a split the operator has to close by hand, plus a member
row in `config.json` that survives until the lead's exit sweep (which will then fire
`it2 session close` at an id that no longer exists, log the non-zero result, and move on).

---

## 6. Adversarial pass

**Claim under test: "the iTerm2 backend never closes a pane on teammate death / on
`teammate_terminated` / on idle."**

The string that would have to exist is `["session","close"` (or `"session","kill"`, or a
`close`-shaped argv). Exhaustive regex over the binary for `\["session"[^\]]{0,90}\]` returns
**exactly one** `close` form, at `181090762`, inside `ITermBackend.killPane`. Therefore every close
is a `killPane` call, and the question reduces to enumerating `killPane` call sites. All 9
occurrences of the token `killPane`:

| offset | site | verdict |
|---|---|---|
| 181090734 | the definition | — |
| 173583719 | `te()` — `k=Cyt(c)?()=>h??=Aqe(c).killPane(T,!f):void 0`, stored as `paneTeardown`, also wired to `C.signal.addEventListener("abort",()=>{k()},{once:!0})` | kill / abort |
| 173578899 | spawn rollback `D(()=>S.backend.killPane(A,!O))` | pre-commit failure only |
| 179218886 | InboxPoller `shutdown_approved` branch | graceful shutdown |
| 158284243 / 158284292 | `cleanupSessionTeams` (call + log) | lead graceful exit |
| 173463153 | `TmuxBackend.killPane` definition | — |
| 70083479 / 75336566 | strings-table copies | — |

`teammate_terminated` is the *inbox notification the lead emits to itself* after the fact
(`179220526`, inside `yIo`) — it carries no pane operation and `yIo` contains no `killPane`. `yIo`
has exactly one real call site (the other two `yIo(` hits at `161456360`/`161457506` are a name
collision in URL-policy code). Idle (`idle_notification`) touches only `isActive`.

**Second gap checked: is there a `TeamDelete` cleanup path?** No. `TeamDelete` appears twice in
2.1.260 and one of them is `160219289`:
`var ypt=new Set(["Frame","FrameRead","TeamCreate","TeamDelete","SuggestBackgroundPR","AutofixPr"])`
— a set of *unsupported* tool names. There is no `TeamDelete` implementation, so no pane cleanup
hangs off it. The `agent-teams` skill's "classic `TeamCreate`/`TeamDelete` on 2.1.114" is correct as
history and dead on 2.1.260.

**Third gap checked: version drift 2.1.220 → 2.1.260.** The it2 argv set is byte-identical
(`231389044`–`231390477` in 220 vs `181089212`–`181090762` in 260: same nine forms, same flags, same
`-f -s` on close). `remain-on-exit` + `respawn-pane` present in both (`96768108`/`96768188` in 220).
`swarm_session_cleanup` and `cleanupSessionTeams` present in both. `DEFAULT_TEAMMATE_MODE` is
`"in-process"` in both. **No behavioural drift on this surface** — a finding worth recording
because it means measurements taken on 220 transfer.

---

## 7. Fleet facts — confirmed / corrected

`bin/cc-pane-runner:1-60` and `bin/it2-kitty:1-50` (worktree
`~/Development/.worktrees/wt-research-subagent-lifecycle-2026-09-19/`) are **confirmed correct
against 2.1.260** on every element they assert:

- `it2 session send -s <id> $'\x15'` then `it2 session run -s <id> <cmd>` — ✓ `181090473`/`181090519`
- `tmux respawn-pane -k -t <pane> -- <cmd>` — ✓ `173462457`
- first split `-v -s <leader>`, later splits bare `-s <prev>` — ✓ `181089212`/`181089446`
- leader id = `ITERM_SESSION_ID.slice(indexOf(":")+1)`, **null when there is no colon** — ✓ `181088850`
- new-pane id parsed by `/Created new pane:\s*(.+)/` then `.trim()` — ✓ `181088780`
- prune on split failure via `session list` + `stdout.includes(paneId)` — ✓ `181089691`
- `it2 session close -f -s <id>` — ✓ `181090762`
- `CNe()` in full: `$SHELL -lc "command -v it2"`, 2 s timeout, `.at(-1)`, runs `<resolved> session
  list` as the real gate, retries bare `it2` **only** on 127/ENOENT, caches the resolved path — ✓
  `158323265`–`158323700`. The header's warning that step 5's caching means "losing the PATH race
  silently bypasses the wrapper **on iTerm2 too**" is exactly right: `oSn()` returns the cached
  path and `d(e)=Fe(oSn(),e)` uses it for every later call.
- five subcommands — ✓, and the enumeration above proves the set is closed.

**Three additions the fleet headers do not carry** (worth folding in):

1. `cc-pane-runner`'s tmux comparison omits the *first* of the two tmux calls:
   `set-option -p -t <pane> remain-on-exit failed` precedes `respawn-pane -k`. That option is
   precisely why the tmux backend needs no reaper and the iTerm2 one leaves residue — it is the
   load-bearing half of the asymmetry the header is describing.
2. `ITermBackend.setPaneBorderColor` / `setPaneTitle` / `enablePaneBorderStatus` are **empty
   bodies** (`181090400`). A shim need not implement colour or title at all; the caller in `pe()`
   does invoke `enablePaneBorderStatus()` but only under `U&&O` (first teammate **and** insideTmux),
   so on iTerm2 it is unreachable anyway.
3. `killPane` is called with `(paneId, !insideTmux)` everywhere; `ITermBackend.killPane(e,s)`
   **ignores the second argument** entirely. Only `TmuxBackend` uses it (to pick the `-L
   claude-swarm-<pid>` socket).

**Fleet team file** `~/.claude-quaternary/teams/session-d02d8feb/config.json` matches shape #1
exactly: one member, `name:"team-lead"`, `tmuxPaneId:"leader"`, `backendType:"in-process"`, no
`isActive`. `isActive` is absent because it is only ever *added* by `N5e`, and the lead never runs
`N5e` on itself (`178137400`: `if(xe===He){… This agent is the team leader - skipping idle
notification hook; return}`).

---

## 8. Alternatives considered and ruled out

- **"`teammateMode:'tmux'` selects TmuxBackend directly."** Ruled out: `Ndt` has no `"tmux"` branch
  (`170254612`); the value only sets `Cqe()` false. Checked by reading the full function body, not
  by grep.
- **"the `it2` literal is what runs."** Ruled out: `d(e)=Fe(oSn(),e)` (`181088700`) where `oSn()` is
  the path cached by `CNe()`. A shim earlier on the login-shell PATH wins permanently.
- **"`remain-on-exit` is set on the iTerm2 side too."** Ruled out: 2 occurrences of the token in the
  whole binary, both in the tmux chunk (`173461745`, and its strings-table copy at `73241851`).
- **"a background poller reaps dead teammate panes."** Ruled out: `pane_dead` 0 hits; `session list`
  appears only twice outside the setup probe, both inside the split-retry.
- **"the 2.1.220 baseline behaves differently."** Ruled out by direct comparison, §6.

## 9. Uncertainties, named

- **[I] What `it2 session split` leaves running in the new pane.** The binary does not choose it;
  the real `it2` asks iTerm2 to split, which starts the profile's default command. The binary's own
  evidence that it is a *shell* is indirect but strong: `sendCommandToPane` TYPES the command
  (`session send` Ctrl-U + `session run` text+Enter), which is meaningless against anything but a
  prompt, and `cc-pane-runner:46-52` records the measured behaviour ("today's split yields an
  interactive shell that runs the command and returns to a prompt").
- **[I] tmux `remain-on-exit failed` semantics.** Read from tmux's documented option values
  (`on|off|failed`), not from this binary. The binary only proves the option is set.
- **[E, but bounded]** `isActive` has no reader *in this binary*. A reader spelled through a
  computed key (`m["is"+"Active"]`) would evade the scan; nothing suggests one exists.
- **Untested at runtime.** Everything here is static reading. In particular the 2-second cleanup
  budget's practical failure rate at N panes is a prediction, not a measurement — the brief's
  read-only boundary forbade firing a team to observe it.
- **Not investigated:** the `storageV5` CAS path for team-file writes (`H`, `158278400`) is
  described only by its retry shape; whether the fleet is on v5 or the lockfile path was not
  determined.

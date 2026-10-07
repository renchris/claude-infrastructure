# Gap G7: background Bash deadline in 2.1.293 (10 min or 30 min, who is covered, is BASH_DEFAULT_TIMEOUT_MS a lever)

Source: static read of the 2.1.293 binary
(`~/.claude-293/node_modules/@anthropic-ai/claude-code/bin/claude.exe`, Python mmap search, never
executed), the 2.1.284 binary for the before state, `pack/cc-changelog.md`, and the fleet repo.
Nothing here was measured at runtime.

## Answer

1. **Both figures are real; they apply to different session kinds.** The default background
   deadline is **10 minutes (600,000 ms) for a one-shot `claude -p`** and **30 minutes
   (1,800,000 ms) for every other unattended session** (a `-p` session fed by
   `--input-format stream-json`, or one started with `--sdk-url`). The changelog states only the
   30-minute figure; the 10-minute one-shot default is in the binary and in no changelog line of
   2.1.285 to 2.1.293.
2. **The default applies only when the Bash call gives no `timeout`.** A call with
   `run_in_background: true` and an explicit `timeout` gets that timeout as its deadline, up to a
   ceiling of 2 hours (7,200,000 ms). That holds in a one-shot `-p` too. So a 3300-second
   `cc-await-ping` watcher survives if the call passes `timeout >= 3300000`, and is cut at 600 s
   (one-shot) or 1800 s (streaming headless) if it passes none.
3. **"Not interactive" is a session-level flag**, set when argv has `-p`/`--print`, `--init-only`
   or `--sdk-url*`, or when stdout is not a TTY. Exempt even when that flag is set: sessions hosted
   by the desktop app (`claude-desktop`, `claude-desktop-3p`, `local-agent` entrypoints), sessions
   hosted by VS Code (`claude-vscode`), the server mode that calls `disableBackgroundDeadline()`,
   Monitor-tool tasks, and any session where the `tengu_cosmic_shore` flag is false. Interactive
   terminal panes, and subagents inside them, are exempt. Subagents inside a headless session are
   covered (the predicate does not look at the agent).
4. **`BASH_DEFAULT_TIMEOUT_MS` works, but only upward and with a side effect.** The one-shot
   default is `max(600000, BASH_DEFAULT_TIMEOUT_MS)` and the streaming default is
   `max(1800000, BASH_DEFAULT_TIMEOUT_MS)`, so setting it to 3,300,000 or more lifts both defaults
   past the watcher. It cannot lower the deadline. The same variable is also the default
   *foreground* Bash timeout (normally 120,000 ms) and raises the foreground maximum with it, so a
   hung foreground command would then block for that long. The per-call `timeout` is the narrower
   lever. `BASH_MAX_TIMEOUT_MS` raises the 2-hour ceiling only when set above 7,200,000.
5. **Launcher timeouts sized from "30 min" are wrong only for one-shot `-p` launches that
   background a command without a `timeout`.** The three fleet callers named in the brief are not
   in that class (see below).

## Evidence

### The deadline resolver (2.1.293, byte 191288733 onward)

```js
function WCn(){return uz()&&!ok().backgroundDeadlineDisabled}
function e7r(){return WCn()&&C("tengu_cosmic_shore",!0)}
var uoe=600000;
function OVt(){return JJ()?Math.max(uoe,cte()):xts()}
function wir(e){return e7r()?t7r(e):void 0}
function t7r(e){return Math.min(e??OVt(),Tae())}
```

- `uoe=600000`: 1 hit in 2.1.293 at byte 191288833, 0 hits in 2.1.284 (measured, mmap find).
- The tool description is built from the same function, so the model is told the live figure:
  `` `timeout` limits how long the command may run in the background before it is stopped (default ${OVt()} ms, max ${Tae()} ms) `` (same snippet, `GCn()` and `zCn()`).

### The constants (2.1.293, byte 190461160 onward)

```js
var a=120000,i=600000;
function cte(n=process.env){let e=n.BASH_DEFAULT_TIMEOUT_MS;if(e){let t=ud(e);if(!isNaN(t)&&t>0)return t}return a}
function gke(n=process.env){let e=n.BASH_MAX_TIMEOUT_MS;if(e){let t=ud(e);if(!isNaN(t)&&t>0)return Math.max(t,cte(n))}return Math.max(i,cte(n))}
var s=1800000;
function Tae(){return Math.min(Math.max(7200000,gke()),2147483647)}
function xts(n){return Math.max(s,cte(n))}
```

Read together: one-shot default = `max(600000, BASH_DEFAULT_TIMEOUT_MS or 120000)` = 600,000 ms
unset; other unattended default = `max(1800000, ...)` = 1,800,000 ms unset; ceiling =
`max(7200000, BASH_MAX_TIMEOUT_MS or max(600000, default))`. `cte()` is also the foreground
default and `gke()` (exposed as `WD()`, byte 192925752) the foreground maximum, which is the side
effect in answer 4.

### What "one-shot" means (bytes 184043950, 184044291, 209168120)

```js
function sEo({hasStreamingInput:e,sdkUrl:t}){return!e&&!t}
function JJ(){return n().host.launchOptions.singleShotPrintSession()}
// inside runHeadless(e, r /* prompt */, ...):
let Y=typeof r!=="string";oEo(Y),...,iEo(sEo({hasStreamingInput:Y,sdkUrl:b.sdkUrl}));
```

The prompt `r` comes from `Mi(e||"",H??"text")` (byte 201847665; `Mi` at 201745498), which returns
a stream only when `--input-format` is `stream-json` and otherwise builds a string from the
positional prompt and piped stdin. So `claude -p "text"` and `claude -p < file` are both one-shot
(10 min); `claude -p --input-format stream-json` and `--sdk-url` sessions are not (30 min).

### Which sessions count as not interactive (bytes 184042131, 184517902, 184518574, 185999012, 202119938)

```js
function Ee(){return!n().host.launchOptions.isInteractive()}
function uz(e=Ee()){let t=Ep()&&!n().claudecode;return e&&!t&&!Ev()}
function Ep(){return p()&&!n().childSession}          // p(): entrypoint in r
r=new Set(["claude-desktop","claude-desktop-3p","local-agent"])
function Ev(){let e=n();return e.entrypoint==="claude-vscode"&&!e.childSession&&!e.claudecode}
function t4e(e=process.argv.slice(2)){let n=hC("-p",e)||hC("--print",e),t=hC("--init-only",e),o=Slt((r)=>r.startsWith("--sdk-url"),e)!==-1;return n||t||o||!process.stdout.isTTY}
// startup: let w=n.kind==="non-interactive"||t4e(e); ... Gws(w)  ->  t.setInteractive(!e)
```

`claudecode` is `Boolean(a.CLAUDECOD…)` and `childSession` is
`Boolean(a.CLAUDE_CODE_CHILD_SESSION)` (byte 184518900), so a desktop- or VS Code-hosted session
that is itself a child or runs under a Claude Code parent loses the exemption. Note the last term
of `t4e`: a session without `-p` whose stdout is not a TTY is also non-interactive.

### Other exemptions

- Server mode: `M.disableBackgroundAgentLaunch(),M.disableRemoteAgentIsolation(),M.disableBackgroundDeadline()`
  at byte 227269654, in the function that builds the server named `"claude/tengu"`; its caller
  passes transport `"stdio"`. The entrypoint code maps `mcp serve` to entrypoint `mcp` (byte
  184519892), which makes `claude mcp serve` the likely owner; that link was not traced end to end.
- Monitor tasks: `let ke=w!=="monitor"?$Tn(he,s,q,h,w,b,M):void 0` (byte 196313582).
- Flag: `tengu_cosmic_shore`, default `true` in code; cached `true` in the four account configs
  that carry it (`grep` over `~/.claude*/.claude.json`: next, secondary, tertiary, quaternary).
- 2.1.284 has no deadline at all: 0 hits for `disableBackgroundDeadline`, `tengu_cosmic_shore`,
  `task_local_shell_background_deadline` (measured).

### How a per-call `timeout` reaches the deadline (bytes 196394512, 196396673, 196311384)

```js
let Ut=Te!==void 0?Math.min(Qe||WD(),Te,s?.maxTimeoutMs??1/0):Math.min(Qe||hV(),Rt?Tae():WD(),s?.maxTimeoutMs??1/0);
if(Qe&&Ut<Qe)h?.({key:"timeout_clamped",requestedMs:Qe,appliedMs:Ut});
...
let gr=jTn(Qe,Ut),so=g===void 0?await go(gr):g.adopt($n,gr,Ze);   // jTn(n,e)=n!==void 0&&n>0?e:void 0
// $Tn(...,b): q=wir(b), Y=q===void 0?void 0:setTimeout(H0r,q,w,q,G)
```

`Qe` is the call's `timeout`, `Rt` is true for `run_in_background`. With a timeout the deadline is
`min(timeout, Tae())`; without one it is `OVt()`. A foreground command that times out and is moved
to the background takes the other path (`ovn` -> `$Tn(e,r,s,g,void 0,w)`, byte 196316359) and
always gets the default. At the deadline `H0r` stops the task and logs
`LocalShellTask <id>: stopped at its <n>ms background deadline`.

### Changelog (`pack/cc-changelog.md`)

- Line 763 (2.1.285): "Changed background Bash and PowerShell commands to stop after a time limit
  (their `timeout` with `run_in_background`, default 30 min, max 2 h); Claude is notified when one
  is stopped".
- Line 461 (2.1.288): "Changed the background command time limit to apply only in unattended
  sessions (`-p`, Agent SDK, CI, cloud); terminal, desktop app and VS Code sessions have no limit".
- Line 81 (2.1.292): "Fixed one-shot `claude -p` and Agent SDK runs stopping a background command
  5 seconds after the final result, and one-shot `claude -p` runs dropping a scheduled wakeup; both
  are now waited for".
- A `grep -i` over lines 3-815 for "10 min", "ten min", "time limit", "background command" and
  "30 min" returns only those three lines plus two unrelated ones (273, 798). The 10-minute
  one-shot default is NOT STATED in the changelog.

### Fleet callers

- `scripts/handoff-fire.sh:13853-13856`: a login probe, `"$BIN" -p 'Reply with exactly: ok' ... --tools "" --max-turns 1`,
  under `perl -e "alarm $alarm_s"` (90 to 360 s). One-shot, but it has no tools, so it cannot start
  a background command. Not affected.
- `scripts/meter-experiment/run.sh:65` (`timeout -k 10 1200 "$BIN" -p --session-id ... < prompt.txt`)
  and `:72` (`timeout -k 10 300 "$BIN" -p --resume ... "Reply with exactly: OK"`). Both one-shot
  (stdin text is still a string prompt); both ask for a fixed reply and start no background
  command. Not affected in practice.
- The 3300 s arm is `hooks/session-continue.sh:863`:
  `cc-await-ping --timeout ${CC_WAKE_FLOOR_TIMEOUT_S:-3300} --interval 15`. In an interactive pane
  it is exempt. In `bin/cc-pane-headless` (a `claude -p --input-format stream-json` agent, comment
  at line 30) it is a streaming session, so the default is 1800 s, as the referee note said. It
  would be 600 s only inside a one-shot `-p`.
- `BASH_DEFAULT_TIMEOUT_MS` and `BASH_MAX_TIMEOUT_MS` appear in the repo only under
  `docs/research/` (measured, `grep -rn` over the worktree); no setting or launcher sets them.

## What remains unknown

- **No runtime confirmation.** Every figure above is read from code. Settling measurement: on
  2.1.293, run a one-shot `claude -p` that starts `sleep 900` with `run_in_background` and no
  `timeout`, and a second with `timeout: 3300000`; expect the first stopped near 600 s with the
  debug line `stopped at its 600000ms background deadline` and the second still running at 900 s.
  Repeat in a `--input-format stream-json` session and expect 1800 s.
- **Whether any fleet one-shot `-p` launch arms `cc-await-ping` or another long background
  command.** I read only the three callers the brief named plus the arm site. Settling measurement:
  list every `-p` launch without `--input-format stream-json` and check whether its prompt or hooks
  can background a command.
- **Whether the model passes `timeout` when it runs the arm command.** The hook prints the command
  text; the `timeout` argument is the model's choice. Settling measurement: read the Bash
  `tool_use` input for the arm call in a headless transcript.
- **Interaction with the 2.1.292 wait (line 81).** A one-shot `-p` now waits for a background
  command after its final result, so an armed watcher would presumably hold the process open until
  the 600 s deadline; that wait path was not read.
- **Which CLI mode owns `disableBackgroundDeadline()`**: likely `claude mcp serve`, not traced.
- **Whether a text-format `Mi()` can ever return a non-string** (which would flip a `-p` launch to
  the 30-minute class): only the head of the function was read.

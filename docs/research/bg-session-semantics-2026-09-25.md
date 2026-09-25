# Claude Code 2.1.280: background-session (bg) semantics, read from the binary

Source: `strings -n 8` of `~/.claude-280/.../bin/claude.exe` (Claude Code 2.1.280), with byte offsets into that extraction. Written 2026-09-25 by a read-only research subagent for the recover-pane-address fix (hooks/session-register.sh bg-fork arm; handoff-fire.sh hf_bg_hosted).
Read-only. No process was launched or signalled.

## Q1: Which env vars are stripped or rewritten for a bg session? Is there an explicit list?

**Verdict: yes, there is an explicit DENYLIST, `dNe`.** It includes `KITTY_WINDOW_ID`, `ITERM_SESSION_ID`, `TERM_PROGRAM`, `TMUX`/`TMUX_PANE` and `CLAUDE_CODE_SESSION_ID`. It does NOT include `KITTY_PID`, `KITTY_LISTEN_ON` or `TERM_SESSION_ID`, so those survive, which matches what you saw. A var on the list survives only if the dispatch passes it explicitly in `e.env`. After stripping, `SESSION_KIND=bg` and the other bg vars are set on top.

Evidence. The builder `Xe` (@24165657) copies `process.env` and then deletes:
```js
function Xe(e,r,s,o,n){let p={...process.env};...let h={...p,...e.env,CLAUDE_CODE_SESSION_KIND:"bg",CLAUDE_BG_BACKEND:"daemon",
 CLAUDE_BG_SOURCE:e.source,CLAUDE_JOB_DIR:r,CLAUDE_CODE_SESSION_NAME:Ks(...),CLAUDE_BG_RENDEZVOUS_SOCK:o,FORCE_COLOR:"3",
 COLORTERM:"truecolor",BROWSER:"true"}; ... if(process.env.CLAUDE_CONFIG_DIR)h.CLAUDE_CONFIG_DIR=process.env.CLAUDE_CONFIG_DIR;
 for(let g of dNe)if(!e.env?.[g])delete h[g];if(UZ(h),Qqe(h),!e.env?.CLAUDE_CODE_ENTRYPOINT)j8(h);
 ... for(let g of le)if(!e.env?.[g])delete h[g]; /* provider/auth vars */ ... if(s)delete h.CLAUDE_CODE_OAUTH_TOKEN;
```
The list itself (@23458645, excerpt):
```js
var dNe=["CLAUDE_CODE_SAFE_MODE",...,"CLAUDECODE","CLAUDE_CODE_SESSION_ID","CLAUDE_CODE_BRIDGE_SESSION_ID",
 "CLAUDE_CODE_CHILD_SESSION",...,"CLAUDE_BG_RV_AUTH","CLAUDE_BG_PTY_AUTH",...,"ANTHROPIC_MODEL","CLAUDE_CODE_PLUGIN_DIRS",
 "TERM_PROGRAM","TERM_PROGRAM_VERSION","__CFBundleIdentifier","KITTY_WINDOW_ID","WT_SESSION","KONSOLE_VERSION","VTE_VERSION",
 "ZED_TERM","ZELLIJ","TMUX","TMUX_PANE","CLAUDE_CODE_TMUX_SESSION",...,"STY",...,"LC_TERMINAL","SSH_CONNECTION","SSH_CLIENT",
 "SSH_TTY","COLORFGBG","CURSOR_TRACE_ID","GIT_ASKPASS",...,"TERMINAL_EMULATOR","ITERM_SESSION_ID","GNOME_TERMINAL_SERVICE",
 "XTERM_VERSION","ALACRITTY_LOG","TILIX_ID","TERMINATOR_UUID","ConEmuANSI","ConEmuPID","ConEmuTask","MSYSTEM",
 "CLAUDE_CODE_SSE_PORT","FORCE_CODE_TERMINAL"];
```
Other deletions:
- `UZ` and `Qqe` delete small internal sets (bridge-child, eval and dispatcher-tier vars).
- `j8` drops `CLAUDE_CODE_ENTRYPOINT` when it is vscode or desktop.
- `le`, `Ctn` and `K$` hold provider credentials and endpoints: `ANTHROPIC_API_KEY`, `*_BASE_URL`, `CLAUDE_CODE_USE_*` and similar.

A second, spare-claim builder (@~24160000) uses the same lists and sets `CLAUDE_CODE_SESSION_KIND:"bg"` too.
Consequence: a bg session cannot identify its kitty window or iTerm pane from the environment. Only `KITTY_PID` and `KITTY_LISTEN_ON` remain.

**Confidence: 95%.**

## Q2: How is backgrounding triggered?

**Verdict: two user actions, both handled by the same `BackgroundGesture` class. Nothing triggers it automatically.**
1. **The `/background` slash command (alias `/bg`)**: "Send this session to the background and free the terminal". It takes an optional `[prompt]`.
2. **← (left arrow) pressed on an empty composer.** That opens the agents view, which backgrounds the current session, sometimes after a "Press ← again" confirmation. If a tool is running, you get "Backgrounding after the current tool finishes…" (the defer-then-fork path).

`Ctrl+B` is `task:background`, which backgrounds a running tool or task. It does not background the session.

Evidence:
```js
name:"background",aliases:["bg"],description:"Send this session to the background and free the terminal",argumentHint:"[prompt]",immediate:(e)=>!e.trim()
// BackgroundGesture.onLeftArrow (@~38021000):
onLeftArrow=()=>{... if(we().trim()!==""){... ct("Cannot open agents — you have unsent text in the input. ...");return} ...
 ct("Backgrounding after the current tool finishes…");return} ...
// Hbe(): leftArrowOpensAgents -> {handler:h.onLeftArrow,confirmHint:"Press ← again to open agents"}
```
The code is gated off in these cases:
- persistence is disabled
- the session was started with `--project-config-root`
- there is queued input
- there is unsent draft text

The `/bg` handler, when the session is already bg: `if(At())return i("tengu_background_already_bg",{}),h(),f4(),null` (it just detaches).

**Confidence: 90%.**

## Q3: What does `/exit` do in a TUI viewing a bg session? What about Ctrl+C and closing the window?

**Verdict: (b), DETACH. The bg session keeps running under the daemon; `/exit` does not kill it.** Keystrokes typed in the viewer go to the bg worker. In the worker, `At()` (`SESSION_KIND==="bg"`) is true, so `/exit` and `requestExit` call `f4()`. That sends a `detach-request` over the rendezvous socket, or writes the `\x1B_cc-daemon-detach…` APC to stdout. The daemon forwards the APC to the attached client, and the client ends the attach with outcome `"detached"`.

The only way to end the worker from inside is **`/stop`**. It marks the job `stopped`, writes the detach APC with "Session stopped." and exits the worker.

Evidence:
```js
function bBt(){return At()?"Detach from this background session (it keeps running)":"Exit the CLI"}   // /exit description
function At(){return s9()==="bg"}
// non-interactive /exit (chunk-kxr5expm): if(At())return{type:"text",value:"Session keeps running. Use /stop to end it."}
requestExit=()=>{let{onDetachToCaller:h}=this.#n;if(h){h();return}if(At()){f4();return} ...     // REPL; wired as onExit:we.requestExit
function f4(h){if(!SJ())return;let v=i1r();if(FZ({type:"detach-request",msg:v,broadcast:h?.broadcast})){But();return}
 process.stdout.write(pK(v)),But()}
Hz="\x1B_cc-daemon-detach\x1B\\"   // pK(msg) = "\x1B_cc-detach-msg;"+msg+"\x1B\\"+Hz
// daemon side: else if(e.type==="detach-request"){let r=pK(e.msg),s=this.attachers.get(this.lastInputAttacher);
//   if(!e.broadcast&&s)s.deliver(r);else ... for(let o of this.attachers.values())o.deliver(r)}
// /stop: name:"stop",description:"Stop this background session; transcript and worktree are kept",isEnabled:At
//   kFt: Pa(o,{...t,state:"stopped",detail:"stopped from session"...}); if(SJ())process.stdout.write(pK("Session stopped."));
//   return ...er(0,"prompt_input_exit",...)
```
What the client does after detaching:
- For the `claude attach` CLI path, a clean APC detach relaunches the agent list: `if(xi(y,...))return ... zZ({args:["agents"],env:{CLAUDE_AGENTS_SELECT:s}})`.
- The in-TUI help reads "← returns to agent view, Ctrl+Z drops back to your shell. The session keeps running either way."

So I expect window 405 to fall back to the agents view, not to the shell. That is inferred from the attach path; I did not trace the in-process viewer. I put it at about 70%.

**Ctrl+C / Ctrl+D:** the composer's `onExit` is the same `requestExit`, and the double-press hint in bg reads `"Press <key> again to detach (session keeps running)"`. So it detaches too.

**Closing the window:** only the client (76287) gets SIGHUP. The worker's parents are pty-host 92118, then daemon 91697 (from `ps`). The daemon was spawned by 76287 with `--origin transient`. I did not determine whether a transient daemon exits when the process that spawned it dies while jobs are live, so that part is **UNKNOWN**. The daemon does have an idle-exit path (`tengu_daemon_idle_exit`), which suggests it stays alive while it holds jobs.

**Confidence: 85% for `/exit` = detach and the worker survives. About 70% that the client returns to the agents view. UNKNOWN for transient-daemon survival after its spawner dies.**

## Q4: Do SessionStart hooks run in the bg session? Do they get CLAUDE_ENV_FILE?

**Verdict: yes to both.** The bg worker is an ordinary interactive `claude --resume … --fork-session`, and nothing in the SessionStart path is gated on `SESSION_KIND`. `CLAUDE_ENV_FILE` is supplied to every SessionStart, Setup, CwdChanged and FileChanged command hook, and I found no bg exclusion. The session-env loader also reads `a.CLAUDE_ENV_FILE` if it is inherited.

Evidence:
```js
if(!pt&&(n==="SessionStart"||n==="Setup"||n==="CwdChanged"||n==="FileChanged")&&D!==void 0)Hn.CLAUDE_ENV_FILE=await Y5e(n,D);
async function Q5e(e){... let s=[],g=a.CLAUDE_ENV_FILE;if(g)try{... t(`Session environment loaded from CLAUDE_ENV_FILE: ${g} ...`)
// startup SessionStart is skipped when resuming: ...u.continue||u.resume?void 0:...bZ(Ze,{kind:"session-start",source:"startup",...})
```
So in the worker, SessionStart fires through the resume path and not the `"startup"` path.

**Confidence: 80% that the hooks run with CLAUDE_ENV_FILE. I did not observe a bg-specific skip. The `pt` guard was not resolved.**

## Q5: Is the parent session id available anywhere besides argv `--resume <path>`? What is SessionStart's `source` for a bg fork?

**Verdict: there is no parent-session env var and no parent field in the SessionStart hook input.** The inherited `CLAUDE_CODE_SESSION_ID` is actively **stripped** by `dNe`, as shown in Q1. The SessionStart input carries these fields:
- the common fields (`session_id`, which is the NEW id, `transcript_path`, `cwd`)
- `hook_event_name`, `source`, `agent_type`, `model`, `session_title`
- optional extras

Searches for `parent_session_id`, `forked_from`, `forkedFrom`, `resumed_from` and `CLAUDE_*PARENT*` found nothing.

The parent id does survive in three other places:
- **argv `--resume <old>.jsonl`**: the file name is the old session id.
- **the job record under `$CLAUDE_JOB_DIR`**: the dispatch schema has `launch:{mode:"resume",sessionId,transcriptPath,fork}`. `CLAUDE_JOB_DIR` is set in the worker's env.
- **the old transcript**: it ends with `continued-in` → `continuedInSessionId` (new id). That link points forward, not back.

Evidence:
```js
ve={...jl(_e,ne()),hook_event_name:"SessionStart",source:n,agent_type:g,model:h,session_title:s??Md(_e.id),...D}
// job dispatch schema (@18674221): launch:Mo("mode",[u({mode:R("prompt"),...}),u({mode:R("resume"),sessionId:o().transform(LE),transcriptPath:o()...optional(),fork:...
// argv builder: [...fork?["--session-id",e.launch.sessionId?,"--fork-session"]:[],"--resume",e.launch.transcriptPath??e.launch.sessionId,...]
```

**SessionStart `source` for a bg fork:** it is not `"startup"`, because that path is explicitly skipped for `--resume`. By elimination it is `"resume"`, the same as any `--resume --fork-session`. I found no fork-specific or `"bg"` source value. I could not grab the resume-path call site that passes the literal, so this is inferred.

**Confidence: 85% that there is no parent env var or hook field. 65% that `source` is `"resume"`.**

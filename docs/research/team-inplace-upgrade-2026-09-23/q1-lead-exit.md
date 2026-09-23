# Q1 — What a LEAD's exit does to its pane-backed teammates (Claude Code 2.1.280)

Read-only binary + disk read, 2026-09-22. Binary: `~/.claude-280/.../bin/claude.exe` (217,254,576 B).
Offsets are byte offsets into that file (JS source copy, the 2nd occurrence; the 1st is the bytecode
string table). Every string cited below is also present, same count, in 2.1.260 (table at the end).

## Verdict (5 lines)

1. A **graceful** lead shutdown kills every pane teammate. That covers `/exit` → "Exit and stop tasks",
   Ctrl-C/Ctrl-D exit, and a **SIGTERM, SIGINT or SIGHUP sent to the lead process, which skip the modal**.
   The kill comes from `cleanupSessionTeams`: `killPane` (`it2 session close -f`) on every tmux/iterm2
   member in `teams/<team>/config.json`, then `rm -rf` of the team dir and `git worktree remove` of
   each member's `worktreePath`.
2. The modal ("Background work is running") has 3 options. **None keeps teammates alive.** "Exit" runs
   the cleanup above. "Move to background and exit" hands the *conversation* to a daemon bg session and
   then calls the same `er(0)` shutdown, so the cleanup still runs (inferred from code; never run).
   "Stay" does not exit.
3. **No env var, setting or flag skips the modal or the team cleanup.** `CLAUDE_DISABLE_ADOPT`,
   `CLAUDE_CODE_DISABLE_AGENT_VIEW` and the `disableAgentView` setting only remove option 2.
   `CLAUDE_CODE_DISABLE_BG_EXIT_HANDOFF` only turns off the adopt.json handoff.
4. The teammate has **no lead-liveness check**. `--parent-session-id` is labelled "for analytics
   correlation" and goes only into telemetry and attribution. The teammate's orphan check watches its
   OWN tty. It dies only when its pane is closed (SIGHUP) or when it gets a structured shutdown.
5. **The teammate survives only if the lead dies without running its cleanup registry.** In practice
   that means SIGKILL (no handler), or a graceful exit whose team dir was moved aside first. On relaunch,
   `initializeSessionTeam` **rewrites config.json with the lead only** unless
   `CLAUDE_INTERNAL_ASSISTANT_TEAM_NAME=<team>` is set.

---

## 1. Code that runs on lead exit

### 1a. `/exit` and Ctrl-C/Ctrl-D open an interstitial when background items exist

- **`/exit` command** (offset **206035982**, `async function Ne(d,o)`): `if(At()) return d(),f4(),null`.
  So a session that is already a bg session detaches instead of exiting.
  Otherwise `s=o1r()` (the background items) and `t = p||s.length>0 ? (m)=>e(Hit,{…backgroundItems:s…})`.
  If items exist it renders `Hit`. If none, it goes straight to `WZ(...)` and shuts down.
- **Ctrl-C/Ctrl-D path** (`requestExit`, offset **197678428**): `D=r1r(tasks)`; `if(v||D.length>0)`
  it sets `exit:{kind:"interstitial",showWorktree:v,backgroundItems:D,…}`. Otherwise it calls
  `WZ(...)` directly.
- **Item sources** (offset **184407799**, chunk exporting `r1r,o1r`):
  `o1r()` maps P7e items with `g={agent:"subagent",workflow:"workflow",shell:"shell",monitor:"monitor",mcp:"MCP task"}`.
  The lesson's `subagent · <brief>` rows are these `kind:"agent"` items.
  `r1r(tasks)` labels each live task with `WRe[t.type]`.
- **Worktree sessions get a different modal.** In `Hit` (offset **197737310**), `if(v){ …e(JY,…) }`
  runs first. A lead inside a `claude -w` worktree therefore sees "Exiting worktree session" (Keep/Remove),
  not the background-work modal. Both block.

### 1b. The modal and its options (component `UY`, offset **197726524**)

The title is `"Background work is running"` and the subtitle is `"The following will stop when you exit:"`.
The options are built as `[Po,...Wo,Mo]`:

| option | value | handler in `UY` → `Hit` | effect |
|---|---|---|---|
| `Exit and stop tasks` (always present, pre-selected) | `exit` | `onExit` → `uo()` → `await Le?.()` (onBeforeExit), `Pe(goodbye)`, then `WZ(messages,…)` → `vdn` (`Q8(…,"process_exit")`) → **`er(0,"prompt_input_exit")`** (`WZ` at **183267024**) | full graceful shutdown (§1c) |
| `Move to background and exit` | `background` | only offered when `onBackground` is set, i.e. `LBn(msgs)` = `cb()&&!At()&&!$a()&&Uie()&&Ove(msgs,"")!==null` (offset **196432686**) | renders `asn`, which calls `isn({seed,…,exitsAfterward:!0,tasks…})` to spawn a daemon bg session carrying the conversation, prints `"<N> couldn't be moved and were stopped"`, then **`er(0,"prompt_input_exit",{suppressResumeHint:!0,…})`**. `isn` has no team/teammate code (0 hits for team, teammate, in_process or pUn in its body at **196431399**), so the same §1c cleanup follows. |
| `Stay` | `stay` | `onCancel` (cancelExit) | nothing exits |

Telemetry for the choice: `tengu_exit_background_work_prompt{item_count,chose_exit,chose_background}`.

### 1c. Every graceful path funnels into the same `shutdown()`, which drains the cleanup registry

- `er(e,n,r)` → `Wy().shutdown(...)` (offset **181298768**). `shutdown()` in `class a3r` (offset
  **181286964**) sets `shutdownInProgress`, calls `tJ()`, then runs
  `await Promise.race([xVe(), timeout kQ])` with **`kQ=2000`** ms. After that come the SessionEnd
  hooks, the analytics flush and `forceExit`.
- `bt(fn)` registers into `T().cleanup` and `xVe()` drains it (offset **170283000**:
  `var kQ=2000;function bt(e){return T().cleanup.register(e)}async function xVe(){await T().cleanup.drain()}`).
- **Signals call `shutdown()` directly, with no modal** (`install()` in `a3r`):
  - `SIGINT`: `this.shutdown(0)`, unless print-mode handlers are registered.
  - `SIGTERM`: `this.shutdown(143)`.
  - `SIGHUP`: `this.shutdown(129)`. With `CLAUDE_BG_BACKEND==="daemon"` it is ignored unless the
    process owns the controlling tty.
  - The orphan check (`armOrphanCheck`, every 30 s) calls `shutdown(129)` when the process's own
    stdin or stdout dies.
  - `SIGKILL` has no handler, so **nothing** runs.
- **The team cleanup is registered unconditionally at init** (offset **185926192**):
  `bt(async()=>{let{cleanupSessionTeams:r}=await import("/$bunfs/root/chunk-w4h1rxf6.js");await r(o)})`.
- **`cleanupSessionTeams` = `BRo`** (offset **177179050**; export map at **201542787**, where
  `BRo as cleanupSessionTeams` and `Tcr as registerTeamForSessionCleanup`):
  1. It reads `pUn()` = `sessionCreatedTeams`. The only producer is `Tcr(e)`, called by
     `initializeSessionTeam` (offset **199189707**).
  2. `me(team)` reads config.json and selects members with
     `c.name!=="team-lead" && c.tmuxPaneId && c.backendType && y9t(c.backendType)`, where
     `y9t = tmux || iterm2` (offset **177170696**). For each it calls
     `getBackendByType(type).killPane(tmuxPaneId, …)` and logs
     `cleanupSessionTeams: killPane <name> (<type> <pane>) → <bool>`.
  3. `de(team)`: `git worktree remove` for every member `worktreePath` (it falls back to `rm -rf`),
     then **`rm -rf teams/<team>/`**. That deletes config.json and `inboxes/`.
  4. `r.clear()`.
- **iTerm2 `killPane`** (offset **202091507**): `c(["session","close","-f","-s",paneId])`, i.e.
  PATH-resolved `it2`. On this Mac that is `~/.claude/bin/it2`. The wrapper converts `session close -f`
  into a python-API `async_close(force=True)` with a 20 s bound (wrapper lines 9-19, 193-242), and
  diverts to `it2-kitty` inside a verified kitty pane (lines 60-110). Closing the pane SIGHUPs the
  teammate's `claude.exe`, whose own handler then runs `shutdown(129)`.
- **The task-registry abort does NOT kill panes during shutdown.**
  - A pane teammate is registered in the lead as a task of `type:"in_process_teammate"`, with
    `paneTeardown = ()=>agt(type).killPane(paneId,…)` wired to `abortController.signal` "abort"
    (offset **201084443**, fn `ee`).
  - The AppStateProvider cleanup `bt(P)` → `gMt(tasks)` / `we(tasks)` (offset **184977596**) runs
    `if(Ff(r)) shell kill; else if(Po()){Bd(r.id);continue} else abort()`.
  - `Po()` is the "shutdown committed" flag. It is set by `tJ()` at the top of `shutdown()`
    (offset **174035336**: `function Po(){return e.committed}function tJ(){e.committed=!0}`).
  - So at shutdown, pane teammates are only deregistered. **The kill comes from `cleanupSessionTeams`
    alone**, via the team file.
- **Exit handoff** (`vt`/`Rt`, just before **184977596**) carries only shells, workflows and
  `local_agent`s into `adopt.json` "for the next wake of this session". It needs a bg job dir
  (`Fl()?XB()`), and `CLAUDE_CODE_DISABLE_BG_EXIT_HANDOFF` turns it off. **Teammates are not carried.**
- **Race caveat** (also agent-teams SKILL.md:445-448): the whole registry runs under the 2 s
  `Promise.race`. The drain keeps going while SessionEnd hooks run but is cut by `forceExit`. The
  P1 probe (lesson) still measured 0 surviving member processes at +30 s after option 1.

## 2. Env vars, settings and flags near the modal or cleanup

| name | where | effect on teammates |
|---|---|---|
| `CLAUDE_DISABLE_ADOPT` | `Uie(){return!a.CLAUDE_DISABLE_ADOPT}` (184407799) | removes option 2 only |
| `CLAUDE_CODE_DISABLE_AGENT_VIEW` / setting `disableAgentView` | `cb()` (177209199) | removes option 2 only |
| `CLAUDE_CODE_DISABLE_BG_EXIT_HANDOFF` | `g4n()`, `vt()` | disables the adopt.json handoff only |
| `CLAUDE_BG_BACKEND=daemon` | `a3r.install` | SIGHUP ignored unless the process owns the ctty; SIGTERM still shuts down |
| `CLAUDE_INTERNAL_ASSISTANT_TEAM_NAME` | `initializeSessionTeam` `p()` (199189036) | **relaunch lever, not an exit lever.** Sets `existingTeamName`; if that team's config exists it is **not overwritten** (§4). Deleted from env after the read. |

There is **no** env var, setting or flag that skips the modal, the `bt(cleanupSessionTeams)`
registration or the pane kill. The modal appears iff there are background items (or a worktree), so
suppressing it would mean having zero items. Even then, the direct path still calls `WZ` → `er`, and
the cleanup runs.

## 3. Does a teammate detect its lead's death?

**No.**
- `--parent-session-id <id>` is declared as `"Parent session ID for analytics correlation"` (offset
  **186393903**).
- At runtime it is stored via `setCliParentSessionId` and `setDynamicTeamContext({…parentSessionId})`
  (offset **186050979/186051415**). It is read back only by `EE()` (offset **172451264**), whose
  consumers are:
  - attribution `sR()`, which emits `parentSessionId` (172806051);
  - analytics `ne.parent_session_id=` (172813558);
  - subagent metadata `parentSessionId:EE()` (183851468 etc.).
- There is no liveness use. The source contains no identifier matching
  `lead*|leader*(Alive|Gone|Dead|Exited|Liveness|Pid|Heartbeat)` and no "orphan … teammate" string.
- The only self-exit triggers a pane teammate has are its own tty:
  - SIGHUP when the pane closes;
  - the orphan check on its own stdin/stdout;
  - SIGTERM;
  - a structured `shutdown_request` answered with approve.
- The teammate is spawned *inside an iTerm2/kitty pane* via `cd … && env … claude --agent-id …`
  (offset **201079662**). Its ppid is the pane's shell, not the lead.
- **If the lead is SIGKILLed, the teammate runs on indefinitely** and keeps polling
  `teams/<team>/inboxes/<name>.json`. If a graceful exit removed the team dir, the teammate keeps
  running with no inbox (`[TeammateInit] Team file not found` is logged only at init, offset 196573956).

## 4. What the lead does to `teams/<team>/config.json`

| event | config.json | inboxes/ | member worktrees | member panes/procs |
|---|---|---|---|---|
| graceful exit (option 1 or 2, Ctrl-C/D, SIGTERM/SIGINT/SIGHUP) | **dir deleted** (`de`: `rm -rf`) | **deleted** | **`git worktree remove`** of every member `worktreePath` | killed via `killPane` (tmux/iterm2 members only) |
| SIGKILL / hard crash before drain | untouched | untouched | untouched | **survive** |
| relaunch (`claude …`, `--resume` included, interactive, not `--agent-id`) | `initializeSessionTeam(void 0,…)` (offset **186049323**) builds team `session-<K()[:8]>`, and since `existingTeamName` is undefined and the env var is unset, **writes a fresh config holding only `team-lead`** (`if(!(i?await ph(e,n):null)){…TRn(e,{…members:[lead]})}`), then calls `Tcr(e)` to register it for cleanup | not touched by the write | — | not re-adopted: the lead's in-memory `teamContext.teammates` holds only the lead |

- There is **no `isActive=false` sweep** and no member-by-member removal on exit. The whole dir goes.
  (`setMemberActive`/`removeMemberByAgentId` exist, but only for per-teammate shutdown and idle.)
- `TeamDelete`/`TeamCreate` each appear once as bare strings. Their tool code paths do not exist in
  this runtime (consistent with SKILL.md:450-451).
- **Open point:** whether `K()` at that early init equals the `--resume` target sid or a fresh startup
  id was not settled statically. If it equals the target, the old team file is overwritten lead-only.
  If it is fresh, a new `session-<new8>` team is created and the old one is orphaned but intact.
  - Disk hint: 428/428 configs satisfy `name == "session-"+leadSessionId[:8]`, and 0 of the 46 with a
    transcript were created more than 30 min after the transcript began. So there is no evidence of a
    late re-init overwrite.
  - But ~380 lead-only team dirs have no transcript for their `leadSessionId`, which fits
    "fresh startup id, then switched by resume".
  - Either way the relaunched lead does NOT re-adopt the member. Passing
    `CLAUDE_INTERNAL_ASSISTANT_TEAM_NAME=session-<old8>` makes init read and keep the existing file
    (`i` non-null → `ph(e)` found → no write).

## 5. `/exit` typed into the TUI vs. process kill: what is left behind

| exit mode | modal? | teammate panes/procs | team dir | lead transcript | notes |
|---|---|---|---|---|---|
| `/exit` typed, members alive | **yes, blocks** until answered (lesson: unattended `/exit` leaves everything alive) | killed after option 1 or 2 | deleted | flushed; resume hint printed (option 2 suppresses it and prints the bg short id instead) | `/exit` with LF, not CR, only inserts a newline (lesson) |
| Ctrl-C/Ctrl-D exit | same interstitial (`requestExit`) | as above | deleted | flushed | |
| `kill -TERM/-INT/-HUP <lead pid>` | **no** | **killed** (cleanupSessionTeams) | **deleted**, member worktrees removed | flushed, SessionEnd hooks run | the *un*-attended graceful path the lesson did not cover |
| closing the lead's own pane | no (SIGHUP) | killed | deleted | flushed | |
| `kill -KILL <lead pid>` | no | **survive** | **intact** (config + inboxes) | whatever was already appended; no SessionEnd hooks, no final flush | the only stock path that keeps the teammate alive |

**Implication for in-place relaunch.** No vendor-supported option keeps teammates alive. The
candidates below are unmeasured levers, not recommendations; they are the only ones this read found:
- SIGKILL the lead. This loses the SessionEnd hooks and the final flush.
- Before a graceful exit, move `teams/<team>/` aside so that `ph()` returns null. `me` then kills
  nothing and `de` deletes an absent path. Restore the dir afterwards.

Then relaunch with `CLAUDE_INTERNAL_ASSISTANT_TEAM_NAME=<team>` so init keeps the member list. Whether
a relaunched lead can then address the surviving member (inbox poller, SendMessage routing) is a
separate question and was not examined here.

## Cross-version check (grep -c on the raw binary; each string occurs twice, bytecode + source)

`Move to background and exit` 2/2 · `Exit and stop tasks` 2/2 · `cleanupSessionTeams` 6/6 ·
`CLAUDE_DISABLE_ADOPT` 4/4 · `CLAUDE_CODE_DISABLE_BG_EXIT_HANDOFF` 4/4 · `CLAUDE_CODE_DISABLE_AGENT_VIEW` 6/6 ·
`Parent session ID for analytics correlation` 2/2 · `paneTeardown` 4/4 · `tengu_exit_background_work_prompt` 2/2
(2.1.260 / 2.1.280).

## On-disk facts used

- `backendType` census over all `~/.claude*/teams/*/config.json`: `in-process` 428 (the lead rows),
  `iterm2` 421, `tmux` 8. Pane teammates here are therefore `iterm2` and fall inside `y9t`, so
  `cleanupSessionTeams` does kill them.
- `docs/research/orchestration-units-2026-08-19.md:87`: `teammateMode:"iterm2"` on all 4 accounts,
  with `ITERM_SESSION_ID` exported so iTerm2 mode holds under kitty.
- Lesson `docs/lessons/a-lead-with-live-teammates-cannot-exit-unattended.md`: P1 on 2.1.260 found 0
  survivors after option 1, and option 2 unrun. This read predicts option 2 also kills members,
  because the same `er(0)` drain runs.

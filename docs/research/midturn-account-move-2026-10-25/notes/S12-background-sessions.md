# S12: Claude Code 2.1.293 background sessions (`--bg`, attach, respawn, agents)

Slot S12-background-sessions. Read-only study. Source is `/tmp/mtam/cc293-src.js` (52,710,919 bytes, CC 2.1.293, BUILD_TIME 2026-10-07T06:36:42Z, GIT_SHA 3abc54a9).
Offsets are byte offsets into that file. Minified names are only meaningful inside their own chunk.

## Method

- Wrote the grep helper `/tmp/mtam/S12/g.py`. It runs `python3 -I`, does `re.finditer` on the bytes, and prints windows around each hit. I ran it with `timeout 60` and searched for `already running`, `respawn`, `daemon.lock`, `control.sock`, `CLAUDE_CONFIG_DIR`, `getAuthSnapshot`, `isMidTurn`, `reply-on-resume` and `handoff`.
- The only binary invocations were `claude respawn --help` and `claude daemon --help` (output quoted below). I launched no session and no daemon.
- I ran `ls -ld` (metadata only) on the five config dirs and on `/tmp/cc-daemon-$(id -u)`, and opened no file contents there.
- Docs: WebFetch of https://code.claude.com/docs/en/agent-view (both halves) and two WebSearch queries (CHANGELOG mirrors).

## 1. Process model: which process hosts a background session

The chain is: a per-config-dir supervisor ("daemon"), then a detached `claude bg-pty-host` process for each session, then the worker `claude` process inside that PTY. The TUI is only a socket client.

- **Supervisor is per config dir.**
  - `we()` @1666641: `var we=bo(()=>(o()??u(R(),".claude")).normalize("NFC"),o)` where `o()` returns `process.env.CLAUDE_CONFIG_DIR`.
  - Daemon state dir @~7262672: `function c(){return i(we(),"daemon")}`.
  - Socket dir: `function Z(){return K("sha256").update(Q(we())).digest("hex").slice(0,8)}function Pke(){... return i(t,`cc-daemon-${e}`,Z())}` with `t="/tmp"`.
  - So sockets live at `/tmp/cc-daemon-<uid>/<sha256(resolve(configDir))[:8]>/`. This looks like the same hash shape as the keychain suffix. The docs say the same: "If you set `CLAUDE_CONFIG_DIR`, the supervisor uses that directory instead of `~/.claude` and runs as a separate instance with its own sessions."
- **Paths (from source):**
  - Control socket `DG()` @7267280 = `<sockdir>/control.sock`.
  - Per-session PTY socket `jE(short)` = `<sockdir>/pty/<short>.sock`.
  - Rendezvous socket `TKt` = `<sockdir>/rv/<short>.sock`. Spares live in `<sockdir>/spare/`.
  - `<configDir>/daemon/roster.json` (`MG()`), `<configDir>/daemon/pty-pids/<short>.pid`, `<configDir>/daemon/control.key` and `<configDir>/daemon/auth/<short>.json` (auth snapshot).
  - Lock `KI()` @15007950: `var b="daemon.lock";function KI(){return w(we(),b)}`, i.e. `<configDir>/daemon.lock`.
  - Jobs: `xdo(){return TS(we(),"jobs")}` @4438330, i.e. `<configDir>/jobs/<short>/state.json`.
- **Worker host:** `tCr()` @~16446700 spawns `[claude, "--bg-pty-host", ptySock, cols, rows, "--", worker argv]` with `detached:!0`, `argv0:"claude bg-pty-host"`, then `u.unref()`. Because the PTY host is detached, workers survive a supervisor restart. The supervisor "adopts" them from `roster.json` (`hoe.adopt` @16566487; the error text is "starting (adoption in progress)").
- **Daemon mode in 2.1.293:** `claude daemon --help` (measured) prints "Service install is disabled in this version — the daemon runs on demand and exits when the last client disconnects." The daemon is transient and exits when it is idle with no clients (`tengu_daemon_idle_exit` @16600378).
- **Measured now** (`ls -ld`): `~/.claude-{next,secondary,tertiary,quaternary}` each have their own `jobs/`, `daemon/` and `daemon.log`, so each account has run its own supervisor. `/tmp/cc-daemon-501/` is empty and no config dir has a `daemon.lock`, so no supervisor is running. `~/.claude-next/projects` and `~/.claude-next/sessions` are symlinks to `~/.claude/...`. The other three dirs have real directories.

## 2. What `attach`, `logs`, `agents` and "agent view" are

- **attach** @16143628: the client opens the control socket and writes `{proto, op:"attach", short, auth, cols, rows, attachId, caps}`. The daemon handler @15677170 (`case"attach"`) replies with decModes, tempo, state and stale/workerCliVersion, then streams the PTY ring buffer. The pane is a pure client. Detaching never stops the worker (docs: "Detaching never stops a background session").
- **agents / agent view** = `claude agents`, the fleet TUI that lists `<configDir>/jobs/*` plus daemon `list` and attaches inline. The subcommand list is at `qn()` @19696673: attach, logs, stop (alias kill), respawn [id] --all, and rm.
- **logs** prints the recent terminal output from the ring buffer.

## 3. "Already running" detection (exact mechanism)

`Cn()` @16345931 decides between continuing a session and starting a copy for `--bg --resume <uuid>`:

1. `Dt(uuid)` calls `e1e(uuid,{rejectUnreadable})` @16275823, which calls `listAllLiveSessions` (chunk-232z2cg3). That reads `H6()` = `A(we(),"sessions")` @3874703, i.e. `<configDir>/sessions/<pid>.json` (reader `F()` @9023684: `/^\d+\.json$/`, liveness by pid plus procStart). A holder of kind `bg` or `daemon-worker` gives reason "running". Any other live holder (an interactive TUI) gives "open-elsewhere".
2. Otherwise it reads `<configDir>/jobs/<uuid[:8]>/state.json`. If the sessionId differs or the row is exec, the reason is "handle-taken".
3. `ion(short)` sends the daemon `{op:"has"}`. It falls back to `daemon/roster.json` worker pid plus procStart. If the session is alive or present, the reason is "running".
4. If own flags were passed, the reason is "own-options".
5. Otherwise the result is `{kind:"continue"}`, which wakes the session under the same ID.

The note strings come from `In()` @16345931. For example, "note: session X is already running in the background, so this started a copy as Y" and "note: session X is open in another Claude Code process, so this started a copy as Y. The original conversation is unchanged."

**Consequence:** the liveness registry is per config dir. A live session under `~/.claude-secondary` cannot be seen by a `--bg --resume` run under `~/.claude-tertiary`. The exception is `.claude` and `.claude-next`, which share `sessions/` through a symlink (measured).

## 4. `respawn`: wait for idle, interrupt, or hand over?

There are three restart paths, and they behave differently.

| Path | Trigger | Mid-turn behaviour |
|---|---|---|
| `claude respawn <id>` / `--all` | CLI `aIs()` @16366024 calls `B5e(id,{force:!0})` | **Interrupts immediately.** With force it skips the "already running" refusal and calls `FSe()`, which sends daemon `op:"kill"`. That runs `hoe.kill("SIGTERM","killed")` @16477643, then `pty.kill(SIGTERM)` with a SIGKILL after 5 s. It waits up to 3 s for the old worker to be gone (`rRr`), then calls `g8(["--resume",R,...respawnFlags], ...)` @16308444. The session ID is the same and the transcript is not forked (`--resume`, not `--fork-session`). `respawn --all` filters to live jobs and forces each one. |
| Daemon upgrade sweep | `respawnIfIdleStale()` @16454148 | **Waits for idle.** It refuses when attached, when the last input was recent, when `tempo!=="idle"` ("busy"), or when `ye(h)` shows in-flight tasks or queued work ("inflight"). Then it moves to phase `upgrading` and calls `shutdownWorker()` (rv `{type:"shutdown"}`, SIGTERM after 5 s). The daemon's own binary self-restart is also deferred while workers are busy: "deferring the upgrade restart until idle (re-checked every poll, capped at Nm)" @16600378. |
| Crash/stall revival | worker exits unexpectedly, attempt>1, `doSpawn` @16479337 | **Resumes the interrupted turn.** It sets `CLAUDE_CODE_RESUME_INTERRUPTED_TURN=1` and `CLAUDE_CODE_RESUME_PROMPT` = "Continue from where you left off. Note: this session was automatically restarted after its process exited unexpectedly; the user has not sent a new message since the restart. Re-verify anything time-sensitive..." (@~16447400). It also sets `..._MAX_AGE_MS=3600000` for interactive lineage. Same ID, `--resume`. |

There is also an auth-rekey respawn, `rekeyForAuthMismatch` @16465690. It handles a socket-auth (PTY token) mismatch, not an OAuth account change. It defers while the worker is mid-turn: "worker is mid-turn ... deferring re-key respawn until safe". The comment reads "--resume preserves the session".

**What a forced respawn loses mid-turn:**
- The in-flight model stream is aborted (SIGTERM).
- A plain CLI respawn does not pass `replyOnResume`, so the resumed worker does not automatically re-issue the turn unless an initial or queued prompt exists. `tengu_resume_interrupted_turn` fires only for the `intent_replay` case.
- After a successful respawn, B5e rewrites state with `inFlight:{tasks:0,queued:0,kinds:[]}` (@~16315000).
- Per the docs, the "exit handoff" carries background shell commands, dynamic workflows and background subagents over to the next process. Running monitors and shell commands started by subagents stop. `CLAUDE_CODE_DISABLE_BG_EXIT_HANDOFF=1` disables the handoff.
- A foreground tool call that was executing is killed. Its transcript entry is left without a result, and the resumed session sees "Interrupted" or nothing. Docs on `/bg`: "Claude has no record that the command started, so Claude may run the command again."

## 5. `/background` (`/bg`, `←`) mid-turn: the only "live handover"

`UPs` / `Txe` / `OBn` / `kct` @32092284–32105506 work as follows:
- `A3(messages,"background_handoff",{responseStreaming})` flushes the transcript.
- It spawns a bg worker with `["--resume", <current session file>, "--fork-session", ...(isMidTurn?["--reply-on-resume"]:[]), "--permission-mode", ...]` and source `"repl"`.
- The new worker gets a new session ID (`providedSessionId` = a fresh `randomUUID()` when tasks carry over, otherwise generated in `g8`). `N_e()` then writes a "continued-in" link record into the old transcript.
- The foreground process exits.

The hidden help @19635209 describes the flag as: "--reply-on-resume: When resuming, immediately query if the loaded transcript ends in a user-role message (set by /background mid-turn so the fork continues the in-flight turn)."

Dialog text @~32092000:
- "N running — they will be stopped."
- "N tasks carry over to the background session."
- "running workflow subagents restart from the beginning".

So `/bg` mid-turn re-issues the in-flight request in a new process, but it **forks the transcript** (new ID). It also stays inside the same config dir/daemon.

## 6. Can a respawn/restart change `CLAUDE_CONFIG_DIR` or the account?

**No, by design.**
- Dispatch-time env capture `pHt()` @16378891 copies the allowlist `GWe` @9568834. That list includes `CLAUDE_CONFIG_DIR`, model and provider vars, AWS/GCP vars, `CLAUDE_SECURESTORAGE_CONFIG_DIR` and `CLAUDE_CODE_PROVIDER_MANAGED_BY_HOST`. The result is persisted into `jobs/<short>/state.json` as `providerEnv`, and `AYo` strips any non-allowlisted keys.
- Respawn reuses the **persisted** `f.providerEnv`, not the respawning shell's env (`let{CLAUDE_CODE_PROVIDER_MANAGED_BY_HOST:st,...Qe}=f.providerEnv??{}` @~16314500).
- The worker env builder `qe()` @16450273 is decisive:
  ```
  if(process.env.CLAUDE_CONFIG_DIR)o.CLAUDE_CONFIG_DIR=process.env.CLAUDE_CONFIG_DIR;
  else if(o.CLAUDE_CONFIG_DIR!==void 0&&(!mt(o.CLAUDE_CONFIG_DIR)||...includes("..")||!oQ(o.CLAUDE_CONFIG_DIR)))
    t(`bg spawn ${e.short}: dropped dispatch CLAUDE_CONFIG_DIR — not an absolute, dot-dot-free spelling of this daemon's config home`), delete o.CLAUDE_CONFIG_DIR;
  ```
  The worker's config dir is therefore always the supervisor's own. A dispatch or state.json value that differs is overwritten or dropped. `if(s)delete o.CLAUDE_CODE_OAUTH_TOKEN` also removes any env token whenever an auth snapshot is supplied.
- Credentials:
  - The supervisor's auth manager (@16522266) reads `getClaudeAIOAuthTokensAsync`, refreshes, and can push `token_update` or write a one-shot snapshot (`CLAUDE_BG_AUTH_SNAPSHOT_PATH`, consumed and deleted by the worker in `VNn()` @3843091).
  - In 2.1.293 the snapshot getter is wired only for `origin==="service"` (`getAuthSnapshot:n==="service"?()=>F.getAuthSnapshot():void 0` @16600378). Service install is disabled, so transient-daemon workers read their own config dir's stored credentials. I infer this from code; I did not run anything to confirm it.
  - Docs: "Background sessions get their credentials from the supervisor" and "The supervisor and its sessions authenticate with the same stored credentials as your interactive sessions."
- In-process relaunch `z8()` @16275823 (`process.execve` with `--resume K()`, `Object.assign(n,e.env)`) can take env overrides. But the /login restart path refuses in bg sessions: "a background session cannot restart itself (sign in from a session started directly with `claude`)" @37355206. z8 is a foreground-TUI primitive and not part of the bg architecture. It is out of S12 scope; flagged for whoever covers relaunch.

## 7. Docs and changelog cross-checks

- https://code.claude.com/docs/en/agent-view says:
  - each session is its own process under the supervisor;
  - "After an auto-update: the supervisor restarts itself onto the new version and moves idle sessions over ... Sessions that are working, waiting on you, or attached aren't interrupted";
  - `claude respawn <id>` means "Restart a session, running or stopped ... A session that has a saved conversation resumes it";
  - stall restart: "the session continues the interrupted response from where it left off";
  - `/bg`: "If Claude is responding when you run /bg, the response continues in the background session ... Backgrounding starts a fresh process that resumes from the saved conversation";
  - CLAUDE_CONFIG_DIR gives a separate supervisor instance.
- Version notes on the same page:
  - v2.1.257 `--resume <id> --bg` continues under its own ID or starts a copy with a `note:`;
  - v2.1.211 "a restarted ← or /background session doesn't resume an interrupted response older than about an hour";
  - v2.1.196 / v2.1.198 exit handoff of background shell commands, workflows and subagents;
  - v2.1.174 "the supervisor supplies a fresh credential snapshot to pre-warmed workers".
- CHANGELOG mirrors (newreleases.io v2.1.200) mention fixes for "background sessions silently stopping mid-turn after sleep/wake" and for "re-running a turn cancelled with Esc after a stall respawn". There is also a v2.1.150 bug where `respawn --all` was rejected (claudeissues.com #62448).

## Answer

The bg architecture has no sanctioned way to restart a session process under different credentials without forking the transcript.

- What it has is "restart this session process under the same supervisor, same config dir, same ID via `--resume`":
  - `claude respawn` interrupts immediately;
  - the upgrade sweep waits for idle;
  - crash revival auto-continues the interrupted turn.
- The supervisor is keyed to `CLAUDE_CONFIG_DIR`, and the worker env forcibly pins `CLAUDE_CONFIG_DIR` to the supervisor's home. Every restart therefore runs as the same account.
- The only mid-turn handover is `/background`, and it forks to a new session ID inside the same config dir.

A forced respawn in the middle of a turn loses:
- the in-flight API stream;
- any executing foreground tool call, which may be re-run;
- running monitors and subagent-owned shell commands.

Background shell commands, workflows and background subagents carry over. Workflow subagents restart from scratch on `/bg`, and in-flight counters are reset. Re-issuing the turn needs `--reply-on-resume` or the revival env, and plain `respawn` sets neither.

**Usable pieces for the design.** The pattern `kill worker -> --resume same uuid -> CLAUDE_CODE_RESUME_INTERRUPTED_TURN=1 + CLAUDE_CODE_RESUME_PROMPT` is the vendor's own "continue the interrupted turn in a new process" recipe. An external mover could copy it in a process it launches under the target config dir. That would be outside the bg supervisor, and it requires the transcript to be visible under the target dir; see the transcript/projects slots. Cross-config-dir "already running" detection does not exist, so the mover has to guarantee a single writer itself.

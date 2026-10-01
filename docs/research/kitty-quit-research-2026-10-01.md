# Quitting and relaunching kitty 610 without a dialog: research, 2026-10-01

Upstream source used: kitty tag v0.48.2, fetched to /tmp/kittysrc/ (`curl raw.githubusercontent.com/kovidgoyal/kitty/v0.48.2/...`).
The bundle's own Python is frozen (`/Applications/kitty.app/Contents/Resources/Python/lib/kitty-extensions/python-lib.bypy.frozen`), so
`inspect.getsource(kitty.boss.Boss.quit)` => `OSError: could not get source code`. `kitty --version` => `kitty 0.48.2`, so the tag matches.
Below, `cm.c` means /tmp/kittysrc/kitty_child-monitor.c, `boss.py` means kitty_boss.py, and `lu.c` means kitty_loop-utils.c.

## Answer first

1. **Use a signal, never `osascript quit` or ⌘Q.** SIGTERM, SIGHUP and SIGINT take one identical path. That path skips `Boss.quit()` and its
   confirmation code, so it never shows a dialog. But **expect SIGTERM alone not to finish the job on this kitty.** The signal goes through
   the same self-pipe and I/O-thread reader that handles SIGCHLD, and the 59 unreaped zombies show SIGCHLD is not being processed. Also,
   a clean exit joins the remote-control (talk) thread, and that thread has stopped calling accept(). So plan for **TERM, wait 10 s, KILL,
   then verify by pid**. SIGKILL is always delivered, and the kernel then hangs up every pty.
2. **`osascript ... quit` and ⌘Q both show the "Quit kitty?" dialog** with 32 Claude panes, because `confirm_os_window_close -1` counts
   every pane not at a shell prompt. `tell application "kitty"` is also ambiguous here: pid 610 and the sandbox 94453 share the bundle id
   `net.kovidgoyal.kitty`.
3. **Each Claude session gets SIGHUP when its pty closes.** At the 2026-09-30 15:25 shutdown, the SessionEnd hooks ran with
   `reason=other`. `session-deregister.sh` then moves the registry row to `~/.claude/autonomy/shutdown-tombstones/<sid>.json` and deletes
   the row. The transcript keeps every completed record; only the turn in flight is lost. `claude --resume <sid>` (same account config dir,
   same cwd) restores the conversation and an armed `/goal`.
4. **Relaunch with `open -n -a /Applications/kitty.app` and a scrubbed environment.** Do not use a bare `open -a kitty`: with 94453 running
   under the same bundle id, LaunchServices may just activate the sandbox. `-n` forces a new instance. kitty is single-instance only with
   `--single-instance`, and nothing in the config adds that. The new socket is `/tmp/kitty-<newpid>`. How long it takes to answer was
   **not measured** on this box, so poll with a bound (30 s).
5. **The script must detach itself from kitty 610's pty before it signals**, or the pty hangup kills the script before it can relaunch.
   This applies when it runs through Claude Code's `!` in a kitty 610 pane. Use the `start_new_session` pattern in
   `scripts/lib/detach.sh:27-35`.

## 1. Signals to kitty's main pid

- **Handlers are installed for SIGINT, SIGHUP, SIGTERM, SIGCHLD, SIGUSR1 and SIGUSR2** (`cm.c:121` `KITTY_HANDLED_SIGNALS`; installed by
  `init_loop_data` at `cm.c:175`). On macOS there is no signalfd, so the handler only writes the siginfo into a non-blocking self-pipe
  (`lu.c:14-29`, sigaction at `lu.c:51-52`).
- **That pipe is read only by the I/O thread** (`KittyChildMon`, `cm.c:1685` `read_signals(children_fds[1].fd, handle_signal, &ss)`).
  `handle_signal` maps **SIGINT, SIGTERM and SIGHUP alike** to `kill_signal` (`cm.c:1529-1533`). There is no difference between the three.
- **Next, the main thread sets an IMPERATIVE close** in `parse_input`
  (`cm.c:502-507`: `global_state.quit_request = IMPERATIVE_CLOSE_REQUESTED`). `process_pending_closes` then copies IMPERATIVE onto every
  OS window and calls `close_os_window` (`cm.c:1234-1235`, `:1254-1256`). It never calls `boss.quit()` or `confirm_os_window_close`, so
  **no dialog**. `macos_quit_when_last_window_closed no` (kitty.conf:967) does not hold the app open in the IMPERATIVE case
  (`cm.c:1260-1263`).
- **Each closed child gets `killpg(pgid, SIGHUP)`** and its pty fd is closed (`cm.c:1458-1472`, `hangup`/`cleanup_child`).
- **Exit then joins both helper threads:** `Boss.destroy` calls `shutdown_monitor`, which runs `pthread_join(io_thread)` and then
  `pthread_join(talk_thread)` (`boss.py:2659-2661`, `cm.c:459-469`). If either thread is wedged anywhere other than its poll(), the
  process never exits.
- **On a healthy kitty, timing is one main-loop tick** (`request_tick_callback()` at `cm.c:506`), which is sub-second. Not measured here.
- **Expected behavior on this wedged kitty 610, from the evidence:**
  - **SIGCHLD is not processed.** One processed SIGCHLD runs `waitpid(-1, WNOHANG)` in a loop and reaps every zombie (`cm.c:1579-1591`).
    Yet `ps -axo pid,ppid,stat | awk '$3~/Z/'` => **59 zombies with ppid 610**, and their start times run from `Wed 30 Sep 15:29:56` to
    `Thu 1 Oct 12:39:45`. Commit b6727f1d9 records the same: the window roots 64744, 18539 and 25646 became zombies "that kitty 610 never
    reaped". **SIGTERM travels through the same pipe and the same reader, so it may be ignored the same way.**
  - **The talk thread is not accepting.** `netstat -f unix -an | grep kitty-610` => about 128 sockets with Recv-Q 80 or 101 bytes and no
    accept. Its last log line was `2026-10-01 02:06:47 kitty[610:2297] write() to peer socket failed: Broken pipe` (`log show
    --predicate 'processID == 610 AND messageType == error'`; 556 such lines, all from thread 0x2297). So even if SIGTERM gets through,
    `pthread_join(talk_thread)` is likely to hang. The windows may close while the process stays alive.
  - **The threads are mostly idle.** `ps -M -p 610` twice, 20 s apart: thread 2 went from 4:39.43/1:40.77 to 4:39.46/1:40.78, and thread 3
    did not change. Which thread is which is not proven: `sample` is blocked by the hardened runtime (`codesign -dv` => `flags=0x10000(runtime)`)
    and was not run.
  - **Conclusion: give TERM a bounded chance (10 s), then SIGKILL.** SIGKILL cannot be caught. The kernel closes every pty master. XNU's
    master close drops carrier, which sends SIGHUP to each session leader; when the leader exits, the foreground group gets SIGHUP and
    reads/writes get EIO. That XNU behavior is from my reading of `tty_pty.c` and `ttymodem`, not tested here. The 59 zombies are then
    adopted and reaped by launchd.

## 2. osascript quit and ⌘Q show the dialog

- **The AppleEvent quit path is confirmable.** `applicationShouldTerminate` calls `application_close(0)` and returns `NSTerminateCancel`
  (glfw/cocoa_init.m:332-337). With flags=0 that sets `CONFIRMABLE_CLOSE_REQUESTED` (`kitty_glfw.c:924-934`), which leads to
  `call_boss(quit)` (`cm.c:1231-1232`). ⌘Q is the default `map cmd+q quit` (options/definition.py:4554) and runs the same `Boss.quit`.
- **`Boss.quit` needs confirmation:** `x = confirm_os_window_close[0]` = -1, so `num = num_active_windows` and
  `needs_confirmation = x != 0 and num >= 1` (`boss.py:2200-2204`). It then shows the `confirm(... 'Quit kitty?')` overlay and parks
  in `CLOSE_BEING_CONFIRMED` (`boss.py:2221-2224`).
- **Every Claude pane counts.** A window counts if `has_running_program` (`boss.py:1105`), and that is `not self.at_prompt`
  (window.py:912-913).
- **Docs** (options/definition.py:1906-1922): "A value of zero disables confirmation. This confirmation also applies to requests to quit
  the entire application ... with shell_integration enabled, using negative values means windows sitting at a shell prompt are not
  counted, only windows where some command is currently running."
- **The config has the value as stated:** kitty.conf:964 `confirm_os_window_close -1`, and its own comment (kitty.conf:946-951) says this
  is the backstop for `quit`.
- **osascript also returns before anything has quit** (NSTerminateCancel), and the dialog it causes needs a keystroke. Ruled out.
- **`kitty @ quit` / `close-os-window` is impossible:** the socket refuses connections (Recv-Q backlog above).

## 3. What the Claude sessions experience

- **Process tree.** Claude runs under bash/zsh, or under `expect` (which has its own inner pty). For example:
  `claude=86093 Ss+ parent=86090 [expect] grandparent=85643 [bash]` and `claude=69486 S+ parent=69331 [bash]`
  (`ps -o pgid=,tpgid=,stat=`). Either way the hangup reaches Claude: directly, or when expect sees EOF on its tty, exits and closes the
  inner master.
- **The registry has all 32 sessions:** `cc-registry rows kitty_pid=610: 45, with live pid: 32`, and there are 32 `claude` processes.
  Each row holds `account, cwd, kitty_pid, pid, session_id, ...` (`jq keys`).
- **SessionEnd hooks configured** (`jq '.hooks.SessionEnd' ~/.claude/settings.json`): session-end.sh (10 s), session-deregister.sh (5 s),
  session-index-end.sh, session-save-id.sh, harvest-skill-end.sh, live-session-registry.sh, `cc-permission-beacon.sh clear`.
- **They run on a signal death, measured.** `grep "2026-09-30 15:25" ~/.claude/logs/sessions.log` shows lines such as
  `[2026-09-30 15:25:27] Session ended sid=c8c2adc0-... reason=other`, a burst across the fleet within 4 s. That log line is written by
  hooks/session-end.sh:34. hooks/session-deregister.sh:66-71 records the same measurement for 19 roster sessions.
- **Not guaranteed for every session.** docs/research/husk-panes-2026-09-30.md:18 lists one death with "no SessionEnd".
- **What a `reason=other` end leaves** (hooks/session-deregister.sh:79-100), when the row's session_id matches (`:62-64`):
  - a tombstone at `~/.claude/autonomy/shutdown-tombstones/<sid>.json`, which is the row plus
    `{endedAt, endReason:"other", hostShutdown:false, branch}`;
  - the registry row is then deleted (`:100`).
  - If SessionEnd does not run, the row stays as a dead row. `cc-kitty-socket` and `cc-sessions` already tolerate that (`:9-10`).
- **No tombstone consumer runs on a kitty restart.** `scripts/boot-resume.sh` reads tombstones only once per boot (`:7-15`). A kitty
  restart is not a boot, so resuming is a separate step: the resume-sessions skill, or `bin/cc-resume-layout.sh --desktops --to
  unix:/tmp/kitty-<new>` fed `account<TAB>sid<TAB>worktree<TAB>branch` (`cc-resume-layout.sh:5-9`). **Snapshot before you kill**: remote
  control is dead, so `kitty @ ls` cannot provide one.
- **The transcript is intact apart from the in-flight turn.** "A pane close is a SIGHUP. Claude Code persists per completed record, so a
  streaming response or a running tool call at that instant is gone" (docs/research/kitty-title-band-2026-09-16/live-deploy.md:491).
  Scrollback and non-Claude pane processes (caffeinate, tee, MCP servers) are lost (same table, :492-493).
- **`/goal` survives a resume.** "`restoreGoalFromTranscript` scans the persisted transcript backwards for the last `goal_status`
  attachment and re-registers the hook (`tengu_goal_restored_on_resume`)" (docs/research/goal-condition-best-practice-2026-08-09.md:200).
  The current binary still has it: `strings claude.exe | grep -c tengu_goal_restored_on_resume` => `2`
  (`~/.claude-284/.../claude-code/bin/claude.exe`). Iterations reset to 0.
- **Lost on resume, needs repair:** registry/dispatch identity (live-deploy.md:494-495). Resumed panes need re-registration, and the
  launcher normally does that.

## 4. Relaunch

- **Both bundles have the same id.** `PlistBuddy CFBundleIdentifier` => `net.kovidgoyal.kitty` for `/Applications/kitty.app` and for
  `/Applications/kitty.app.staged`. `lsappinfo list` shows both registered (pid 610 at `/Applications/kitty.app`; the second ASN at
  `kitty.app.staged`).
- **Use `-n`.** `man open`: "-n Open a new instance of the application(s) even if one is already running." Without it, `open -a kitty`
  can hand the request to the running 94453 instead of launching. That is a LaunchServices bundle-id match; it is untested here, which
  is why `-n` is mandatory, not optional.
- **kitty itself is not single-instance by default.** The single-instance path runs only `if cli_opts.single_instance`
  (kitty_main.py:561). `~/.config/kitty/macos-launch-services-cmdline` does not exist (`cat` => No such file), so no flags are injected
  (launcher/main.c:534-555). `--instance-group` only matters together with `--single-instance`, and 94453's `--instance-group kdw4` cannot
  capture a plain launch.
- **Scrub the environment.** `man open`: "Opened applications inherit environment variables just as if you had launched the application
  directly". It was measured: the probe kitty "inherited `KITTY_PID` from the launching shell"
  (docs/research/kitty-pane-title-overlay-2026-09-14.md:1119-1122). Run as-is from a Claude pane, the new kitty and every pane in it would
  inherit `KITTY_LISTEN_ON=unix:/tmp/kitty-610`, `KITTY_WINDOW_ID`, `CLAUDE_CONFIG_DIR`, `CC_PANE_ID` and so on. So launch through
  `env -i` with a minimal set.
- **`--stderr` captures almost nothing.** An LS launch sets `KITTY_LAUNCHED_BY_LAUNCH_SERVICES=1` (Info.plist LSEnvironment), which calls
  `set_use_os_log(True)` (kitty_main.py:610-616). kitty logs then go to the unified log: read them with
  `log show --predicate 'process == "kitty"'`. kitty 610's own fd 2 is /dev/null (`lsof -a -p 610 -d 2`).
- **Socket.** `listen_on unix:/tmp/kitty-{kitty_pid}` (kitty.conf:147) gives `/tmp/kitty-<newpid>`; 94453 uses `/tmp/kdw4.sock`, so
  there is no collision. `bin/cc-kitty-socket:62-75` picks the oldest live `kitty-*` socket whose pid is a live kitty. A stale
  `/tmp/kitty-610` is skipped once 610 is dead, and kdw4.sock never matches the glob.
- **Time to answer: NOT MEASURED** (no prior measurement in docs/research for a cold start of the main config). Poll
  `kitten @ --to unix:/tmp/kitty-$NEW ls` with a 30 s bound.

## 5. Recommended sequence

Run it as `bash /tmp/kitty-610-restart.sh --confirm kitty-610`. What it cannot undo: it ends all 32 Claude sessions in kitty 610 (each
loses its in-flight turn and scrollback). They are then resumable from the snapshot.

```bash
#!/bin/bash
set -u
OLD=610; SANDBOX=94453
EXE=/Applications/kitty.app/Contents/MacOS/kitty
KITTEN=/Applications/kitty.app/Contents/MacOS/kitten
TS=$(date +%Y%m%dT%H%M%S); LOG="$HOME/Library/Logs/kitty-restart-$TS.log"
[ "${1:-}" = --confirm ] && [ "${2:-}" = "kitty-$OLD" ] || { echo "refused: pass --confirm kitty-$OLD"; exit 2; }

# 0. Detach from kitty 610's pty (own session, no controlling tty), or the hangup kills this script.
if [ -z "${KRS_DETACHED:-}" ]; then
  /usr/bin/python3 -c 'import os,subprocess,sys
log=open(sys.argv[1],"ab",0)
p=subprocess.Popen(sys.argv[2:],start_new_session=True,stdin=subprocess.DEVNULL,stdout=log,stderr=subprocess.STDOUT,env=dict(os.environ,KRS_DETACHED="1"))
print(p.pid)' "$LOG" /bin/bash "$0" "$@"
  echo "running detached; log: $LOG"; exit 0
fi

# 1. Identity gates: pid 610 must still be THIS kitty (no pid reuse); record the sandbox's identity.
[ "$(ps -p $OLD -o comm= 2>/dev/null)" = "$EXE" ] || { echo "ABORT: pid $OLD is not $EXE"; exit 3; }
SB_ID="$(ps -p $SANDBOX -o lstart=,comm= 2>/dev/null)"

# 2. Snapshot the 32 sessions (remote control is dead; registry + ps are the only sources).
SNAP="$HOME/.claude/autonomy/kitty-restart-$TS.tsv"
for f in "$HOME"/.claude/cc-registry/*.json; do
  jq -r --argjson k $OLD 'select(.kitty_pid==$k)|[.account,.session_id,.cwd,(.pid|tostring)]|@tsv' "$f" 2>/dev/null
done | while IFS=$'\t' read -r a s c p; do
  ps -p "$p" -o comm= >/dev/null 2>&1 || continue
  printf '%s\t%s\t%s\t%s\n' "$a" "$s" "$c" "$(git -C "$c" symbolic-ref -q --short HEAD 2>/dev/null)"
done > "$SNAP"; echo "snapshot: $(wc -l < "$SNAP") sessions -> $SNAP"

# 3. SIGTERM to the exact pid (never pkill/killall/osascript: those can reach 94453).
kill -TERM $OLD
for _ in $(seq 1 20); do ps -p $OLD >/dev/null 2>&1 || break; sleep 0.5; done
# 4. Escalate only if still alive.
if ps -p $OLD >/dev/null 2>&1; then
  echo "TERM did not end $OLD in 10 s; sending KILL"; kill -KILL $OLD
  for _ in $(seq 1 10); do ps -p $OLD >/dev/null 2>&1 || break; sleep 0.5; done
fi
ps -p $OLD >/dev/null 2>&1 && { echo "FAIL: $OLD still alive"; exit 4; }
[ "$(ps -p $SANDBOX -o lstart=,comm= 2>/dev/null)" = "$SB_ID" ] && echo "sandbox $SANDBOX unchanged" || echo "WARN: sandbox identity changed"

# 5. Give SessionEnd hooks time (they have 5-10 s timeouts): wait up to 20 s for the snapshot's claude pids to exit.
for _ in $(seq 1 40); do pgrep -x claude >/dev/null 2>&1 || break; sleep 0.5; done   # coarse; see note

# 6. Relaunch: a NEW instance of the exact bundle, scrubbed environment.
rm -f /tmp/kitty-$OLD
env -i HOME="$HOME" USER="$USER" LOGNAME="$USER" SHELL="${SHELL:-/bin/zsh}" LANG="${LANG:-en_US.UTF-8}" \
    PATH=/usr/bin:/bin:/usr/sbin:/sbin /usr/bin/open -n -a /Applications/kitty.app
NEW=""
for _ in $(seq 1 60); do
  NEW=$(pgrep -n -f '^/Applications/kitty\.app/Contents/MacOS/kitty' 2>/dev/null)
  [ -n "$NEW" ] && [ "$NEW" != "$SANDBOX" ] && "$KITTEN" @ --to "unix:/tmp/kitty-$NEW" ls >/dev/null 2>&1 && break
  NEW=""; sleep 0.5
done
[ -n "$NEW" ] || { echo "FAIL: new kitty socket did not answer within 30 s"; exit 5; }
echo "OK: new kitty pid $NEW, socket unix:/tmp/kitty-$NEW answers; resume from $SNAP"
```

Why each step is safe:

- **Steps 1 and 3, pid targeting.** Every signal names pid 610 exactly, after checking that its executable is the `/Applications/kitty.app`
  binary. 94453 runs `/Applications/kitty.app.staged/...` (`ps -o command -p 94453`), so neither the identity gate nor the `pgrep` anchor
  can match it. Nothing uses `killall kitty`, `pkill kitty` or `tell application "kitty"`, all of which resolve by name or bundle id and
  can reach 94453.
- **Step 3, TERM first.** If the self-pipe path works, kitty closes every window with no dialog and SIGHUPs each child group
  (`cm.c:502-507`, `:1458-1472`). TERM costs at most 10 s if it is ignored.
- **Step 4, KILL second.** Needed because the SIGCHLD backlog and the non-accepting talk thread predict either an ignored TERM or a hang
  in `shutdown_monitor`'s thread joins (`cm.c:464-468`). Children still get the pty hangup from the kernel, so SessionEnd runs the same
  way it did at the 15:25 shutdown.
- **Sessions' state files.** `reason=other` gives a tombstone plus a removed row (session-deregister.sh:79-100), and the transcript keeps
  every completed record. The snapshot TSV in step 2 is written before any signal, in the format `cc-resume-layout.sh` reads, so resume
  does not depend on the hooks having run.
- **Step 0.** Without detaching, a `!`-launched script shares the pty, dies at the hangup, and the relaunch never happens
  (scripts/lib/detach.sh:6-12 explains why nohup is not enough).
- **Step 6.** `-n` plus an exact path avoids activating 94453. `env -i` stops the new fleet from inheriting kitty-610 and account-specific
  variables.

Notes and limits:

- **Step 5's `pgrep -x claude` is coarse.** It also waits on claude processes outside kitty 610, so it simply uses its full 20 s bound
  there. Use the snapshot pids if exactness matters.
- **No step here was executed.** Nothing was signalled, quit or typed into. I ran one `kill -0 <pid>` liveness check over the registry
  pids: signal 0 delivers nothing and only tests existence. The script above uses `ps -p` instead.
- **Unverified:** the time to a ready socket; whether SIGTERM is actually ignored, which the script itself will reveal and log; and which
  `ps -M` thread is the I/O thread.

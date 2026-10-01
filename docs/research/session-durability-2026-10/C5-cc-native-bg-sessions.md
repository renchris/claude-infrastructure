# C5: Claude Code's own background sessions as the session layer

Research dossier, 2026-10-01, candidate C5. Read-only apart from this file. I made 0 of the 3 allowed
`kitten @` calls. The one contained experiment (allowed by the brief) used a throwaway session I
created myself (`9c4a2015`, Haiku, in `mktemp -d` dir `/tmp/sd-c5-pT3ezY`, account
`~/.claude-quaternary`). I attached to it only from private tmux servers (`-L sd-probe-c5`,
`-L sd-probe-c5b`), killed both servers, and then ran `claude stop` and `claude rm` on that id only.
I did not stop, attach, respawn or rm any other id. Every number below is labeled measured (with
its command) or estimated (with its method). UNMEASURED means not checked.

## Answer

**Claude Code's background sessions (`--bg` + `claude attach`) do survive (a) a terminal crash and
(b) a kitty restart. This run measured the parts that were open. It does not survive (c) a reboot
as processes: after a reboot the job records survive on disk, and a later attach or respawn
restarts each session from its transcript. That is the same loss C2's disk resume has.**

Recommendation: **do not migrate the fleet to C5 now. Pilot it, and first neutralize the hazard it
is already causing.** It is the cheapest survival layer to *run*, because it is vendor-maintained
and already on the box. It is the most expensive to *integrate*, because every pane-keyed tool in
this repo loses its address:

- Claude Code strips `KITTY_WINDOW_ID`.
- `/exit` only detaches.
- A recycle cannot reach a bg-hosted session (`scripts/handoff-fire.sh:4960`).

Why the pieces hold:

- **(a) and (b) are solid.** The worker hangs off its own `bg-pty-host` under a daemon that has no
  tty and its own session (measured), so a kitty death can only kill the `claude attach` clients.
  Killing the terminal that held the attach client left the session alive and attachable, with
  the conversation redrawn (measured, E5).
- **(c) is not a process-level win.** A reboot marks each job dead, and the daemon does not restart
  it on its own: `bg adopt: adopted=0 respawned=0 dead=1` after both of the last two reboots
  (measured, E3).
- **The retired lead's "hidden duplicate" (9aa483e9) was not auto-resume and not a spare acting on
  its own. Our own recycle created it.**
  - `handoff-fire.sh --recycle` typed `/exit`. Claude Code raised "Background work is running", and
    the recycle watcher answered `2` ("Move to background and exit").
  - Claude Code then forked lead `09c26b2b` into new session `9aa483e9` inside a pre-warmed spare.
    The fork carried the full 715K-token context.
  - It woke on its own task notification six minutes later and took about 10 tool-using turns.
    These included `cc-notify` to panes 41 and 4 and an append to the successor's brief file.
  - **It is a hazard.** Daemon logs show 18 slash-sourced bg sessions (exit dialog or
    `/background`) across 4 accounts from 2026-07-24 to 2026-10-01 (measured, E2).

## Evidence

### E1. Architecture and lifecycle (read-only `ps`, `lsof`, daemon files)

- **Process tree** (`ps -o pid,ppid,pgid,sess,tty,stat,command -p 9780,10027,10156,10130,10202`):
  - `9780 1 9780 ?? Ss claude.exe daemon run --origin transient --spawned-by {...pid:38588}`
  - `10027 9780 10027 ?? SNs claude bg-pty-host ... 1e4d8daa.pty.sock 200 50 -- claude.exe --bg-spare ...`
  - `10156 10027 10156 ttys068 SNs+ claude bg-spare ...`
  - So each session has its own pty host. That host holds the `/dev/ptmx` master
    (`lsof -p 10027` => `6u CHR /dev/ptmx`, `10u unix .../1e4d8daa.pty.sock`) and runs in its own
    process group. The worker sits on the pty slave `ttys068`. The daemon has no controlling tty.
  - In effect this is a built-in dtach with a screen model.
- **The daemon outlives its spawner.** `ps -o pid,ppid,lstart,command -p 38588` => header only, so
  the spawner (the old lead's claude in kitty pane 4) is gone. Daemon 9780 was still serving at
  `claude daemon status` => `uptime: 3212s`, `control.sock: reachable`.
- **Workers are niced.** `ps -o pid,nice,...` => pty hosts and workers run at `NI 5` and the daemon
  at `NI 0`. An interactive pane session (84365) runs at `NI 0`.
- **One daemon per config dir.** Each config dir has its own socket dir: `/tmp/cc-daemon-501/2be71cf3`
  (next), `6a49a3e4` (tertiary) and `136fa815` (quaternary), plus its own `daemon.log`, `daemon.lock`,
  `daemon/roster.json` and `jobs/<short>/state.json`. Measured with `ls ~/.claude-*/daemon*` and
  the `--- daemon start ---` lines. The vendor docs say the same: "If you set `CLAUDE_CONFIG_DIR`,
  the supervisor ... runs as a separate instance with its own sessions"
  (code.claude.com/docs/en/agent-view).
- **What counts as a "client".** The idle exit fires only when no live workers and no leases remain.
  - Every `idle_exit` line in four logs reads `leases=0, live_workers=0`, and each follows a
    `bg settled` or `bg retire`. Command:
    `grep -h 'shutting down' ~/.claude-*/daemon.log`.
  - My experiment's daemon `61988` exited 5 s after my only worker settled:
    `20:16:15.681Z bg settled 9c4a2015 (killed)` → `20:16:20.682Z idle 5s with no clients — exiting`.
  - So a live bg worker keeps its daemon up with no terminal at all. Spares do not count.
- **`--keep-workers`.** `claude daemon stop --help` => "stop  Shut down the supervisor and terminate
  background sessions ... --keep-workers leave detached sessions running". The docs add: "The new
  supervisor reconnects to the running sessions."
  - The binary's adopt path at daemon start does this. It logs
    `bg adopt: adopted=… respawned=… dead=…` and marks a missing pty host
    `"process gone while supervisor was down"` with `resumable:"auto-resume"` (strings of the
    2.1.284 `claude.exe`, `/tmp/sd-c5-strings.txt`).
  - **A plain `daemon stop` kills every worker.** Measured in the quaternary log:
    `2026-09-27T19:07:59Z shutting down (cause=shutdown_op ... live_workers=1)` →
    `bg settled bb4e00d0 (killed)`.
  - Daemon crash or SIGKILL with live workers: UNMEASURED. I did not signal a daemon. The code's
    adopt path and the separate process groups imply the workers survive.
- **Idle retire.** The supervisor stops idle, unattached workers.
  - Constants in the binary: `ar=3600000` (1 h) and `sr=28800000` (8 h). A session with a
    `bridgeSessionId` (remote control is on fleet-wide) gets 8 h. Measured log lines:
    `bg retire 03a7cd27: idle-prompt, idle 8h`.
  - `retireIfSettled` refuses `attached`, `pinned` (Ctrl+T, `jobs/pins.json`), `recent-input` and
    anything with in-flight tasks.
  - Under macOS memory pressure the grace drops to `Je=60000` (1 min). Monitoring-only sessions are
    shed, and then pinned ones "as a last resort" (`tengu_bg_retire_pinned_low_mem`).
  - Retire keeps the conversation. The next attach or reply restarts it.
- **Version-stale respawn.** `respawnIfIdleStale` restarts idle, *unattached* workers when the
  binary on disk changes (`tengu_bg_respawn_stale`). Attached workers are exempt
  (`reason:"attached"`).

### E2. The 9aa483e9 duplicate: mechanism and hazard (logs, roster, transcript)

- **Trigger.** The recycle watcher log
  `/var/folders/.../handoff-recycle-4-1790882230-Tqk19k.log` reads:
  `bgwork@15s: the /exit raised the background-work dialog; answered '2' (Move to background and exit) — the session exits and its tasks are NOT stopped`.
  That answer is deliberate repo behavior: `scripts/handoff-fire.sh:4280-4292` (`pane_bgwork_key`)
  and `:8531-8548` (the comment records that "Move to background and exit" hands the conversation to
  a background worker under a NEW session id).
- **Daemon side.** `~/.claude-next/daemon.log`:
  `19:17:33.407Z daemon start ... pid=9780 origin=transient` → `19:17:33.582Z bg claimed-spare 9aa483e9 (slash)`.
  - `daemon/roster.json` → `workers.9aa483e9.dispatch` =
    `{source:"slash", launch:{mode:"resume", sessionId:".../09c26b2b-...jsonl", fork:true}}`.
  - So it is a **fork of 09c26b2b** that was put into a pre-warmed `bg-spare`. Spares are idle,
    pre-warmed processes waiting on a `claim.sock`. They never resume anything by themselves.
  - The binary's dispatch telemetry names the sources: `source_shell` (`--bg`), `source_slash`
    (`/background` and the exit dialog), `source_fleet`, `source_spare` and `source_respawn`.
- **What the copy did** (transcript `~/.claude-next/projects/-Users-chrisren-Development-claude-infrastructure/9aa483e9-….jsonl`):
  - `SessionStart:fork` hooks ran at 19:17:37Z.
  - At 19:23:14Z a `<task-notification>` for task `bqat1mp3h` woke it. It then ran Bash,
    TaskCreate ×4, an append to `/tmp/recycle-72-successor.txt` (the successor's brief),
    `cc-notify 41` ×2 and `cc-notify 4`.
  - It then stood down at 19:26:18Z.
  - `jobs/9aa483e9/state.json` → `tokens: 761285`, `state: done`.
  - It is still alive as pid 10156 (`claude agents --json` => `"kind":"background","state":"done","status":"idle"`).
    It will retire after 8 h idle.
- **Why the tooling could not see it.**
  - The worker's argv is `claude bg-spare --bg-spare <claim.sock>`, with no `--fork-session` on it.
    So `hooks/session-register.sh:102-121` (`bg_fork_parent_sid`) gets no parent, and line 173 gets
    no pane.
  - `grep -l 9aa483e9 ~/.claude/cc-registry/*.json` => nothing.
- **Frequency.**
  `grep -h -E 'bg (claimed-spare|spawned) [0-9a-f]{8} \(slash\)' ~/.claude-*/daemon.log | wc -l` =>
  18, from 2026-07-24T18:41Z to 2026-10-01T19:59Z, across next, tertiary, quaternary and secondary.
  The log does not separate the exit dialog from a typed `/background`. Every one I traced (9aa483e9
  here, plus 43ef47fc and 59aeaf2b in `docs/research/recycle-bgwork-orphan-2026-09-29/README.md`)
  was a recycle's exit-dialog answer or a probe that replayed it.
- **Verdict: a hazard.**
  - The copy spends tokens on full context and acts on stale authority: it messaged peers and
    edited a successor's brief.
  - It is invisible to `cc-sessions` and the registry.
  - The repo's goal-clear (`handoff-fire.sh:8549`, `rcy_bgwork_goal_clear`) only stops goal-driven
    turns. Task notifications still wake the copy.

### E3. Reboot behavior (logs, boot time)

- `sysctl -n kern.boottime` => `Wed Sep 30 15:26:06 2026`. `last reboot` => also `Sep 16 16:28`.
- In `next` and `tertiary`: `2026-09-30T20:25:46Z shutting down (cause=signal ... live_workers=1)`,
  20 s before boot.
- Next daemon start (on demand, 10 h later): `bg adopt: adopted=0 respawned=0 dead=1`.
  `jobs/77aa4929/state.json` => `state: failed`.
- The same pattern holds on 2026-09-17: `adopt: adopted=0 respawned=0 dead=1`.
- So nothing restarts bg sessions after a reboot until a client asks. The docs say: "Within 48
  hours, the session shows as failed. Attach or reply to it and it restarts from where it left off.
  Past 48 hours ... stopped with `ended while the background service was off`." The daemon is also
  not a service: `claude daemon --help` => "Service install is disabled in this version — the
  daemon runs on demand".

### E4. The roster (`claude agents --json`)

- `claude agents --json` (next) => 6 rows: 5 `interactive` (from `~/.claude/sessions/<pid>.json`;
  `~/.claude-next/sessions` is a symlink to it) and 1 `background`.
  - Fields: `pid, id, cwd, kind, startedAt, sessionId, name, status, state`.
  - It needs no TTY. It only covers that config dir's sessions dir: tertiary has 16 and quaternary
    13 session files (`ls ~/.claude-*/sessions | grep -c json`). A fleet roster is therefore 3 calls
    (4 dirs, with ~/.claude and next shared), deduped.
- `claude agents --json --all` (quaternary) also lists finished jobs with
  `state: done|stopped|failed|killed` back to 2026-08-27. That is a disk roster that survives a
  reboot (`jobs/<short>/state.json`, which `rm` deletes).
- Whether `agents --json` starts the daemon: UNMEASURED (both runs found one already up). For a
  boot-time read, `~/.claude-*/jobs/*/state.json` is daemon-free.
- `respawn --all`: the docs define it as "Restart every running session". After a reboot nothing is
  running, so it most likely restarts nothing. Per-id `respawn <id>` ("running or stopped") or
  `attach <id>` is the restart path. Not run; UNMEASURED.

### E5. The contained experiment (exact commands; outputs abbreviated)

```
D=$(mktemp -d /tmp/sd-c5-XXXXXX)   # /tmp/sd-c5-pT3ezY
env -u KITTY_WINDOW_ID -u KITTY_LISTEN_ON -u KITTY_PID -u KITTY_PUBLIC_KEY -u ITERM_SESSION_ID -u CC_PANE_ID -u WINDOWID \
  CLAUDE_CONFIG_DIR=~/.claude-quaternary $B --bg --model claude-haiku-4-5-20251001 "reply OK and stop"
  => Starting background service… / backgrounded · 9c4a2015 / claude attach 9c4a2015 ...
daemon.log => 20:13:54.456Z daemon start pid=61988 ... bg claimed-spare 9c4a2015 (shell)
claude agents --json => {"id":"9c4a2015","kind":"background","status":"busy","state":"working",...}
tmux -L sd-probe-c5 -f /dev/null new-session -d -s a -x 160 -y 45 "env ... $B attach 9c4a2015; ..."
  capture => full TUI: banner, SessionStart hook output, "❯ reply OK and stop",
             "You've hit your weekly limit" (quaternary is weekly-exhausted; the lifecycle test is unaffected),
             footer "(4) 9c4a2015 sd-c5-pT3ezY · ⏸ manual mode on · ← for agents"
send-keys 'second line test' Enter => the worker took a turn (input path through attach works)
tmux -L sd-probe-c5 kill-server   # simulates the terminal dying: the attach client gets SIGHUP
  => attach client 98276 gone; claude agents --json => 9c4a2015 "status":"idle","state":"blocked";
     worker 62400, pty host 62156 and daemon 61988 alive
tmux -L sd-probe-c5b new-session ... -x 100 -y 30 "... attach 9c4a2015"
  => conversation fully redrawn at the new width, all 3 prompts visible; tmux history_size 0
claude stop 9c4a2015 => "stopped 9c4a2015"; agents --json --all => "state":"stopped"
claude rm 9c4a2015   => "removed 9c4a2015"; jobs/9c4a2015 gone; daemon idle-exit 5 s later
```

Cleanup: both tmux servers were killed and their socket files removed
(`ls /private/tmp/tmux-501 | grep -c sd-probe-c5` => 0). No process from the experiment remains.
The temp dir still holds the empty `.claude-plans/` and `.claude-tasks/` dirs that the
SessionStart hooks created there. I did not remove it, because `rm -r` is barred.

### E6. What attach does to the UI (measured with tmux `pipe-pane` on the attach client)

Raw client output, 18,319 bytes across one resize, one turn and another resize:

- **Kitty keyboard protocol:** `ESC[>5u` pushed and `ESC[<u` popped (5 each way). So Shift+Enter
  should reach the worker as a distinct key under kitty. End to end in kitty: UNMEASURED.
- **Other modes:** bracketed paste `?2004h` ×4, focus `?1004h` ×3, mouse `?1000h`/`?1006h` ×6,
  synchronized output `?2026h` ×18, alt screen 0.
- **Title (OSC 0/2): 0 sequences.** The pane title stayed `MacBookPro.localdomain`, while a control
  `printf '\033]2;SDC5-TITLE-CONTROL\007'` set its pane's title. So Claude's own retitling did not
  reach the terminal through attach in this run. The kitty title would have to come from
  `kitty @ launch --title` or `set-window-title`. That is a kitty-level title and keeps kitty's real
  title bars. Whether an AI-named session would emit a title later: UNMEASURED.
- **Scrollback:** the docs say "Attached sessions always render in fullscreen mode ... Your
  terminal's native scroll ... show[s] only the current viewport". Measured: `history_size 0` after
  re-attach. The fleet already runs `CLAUDE_CODE_NO_FLICKER=1` (`ps eww -p 10156`), so this is
  unchanged from today.
- **Keys:** `claude attach --help` => "← returns to agent view, Ctrl+Z drops back to your shell. The
  session keeps running either way." In a bg session, `/exit` = "Detach from this background session
  (it keeps running)" (binary string). Only `/stop` ends the worker
  (`docs/research/bg-session-semantics-2026-09-25.md` Q3).
- **Layout and drag:** kitty itself is unchanged, so real title bars, drag-to-reorder, the 2x2 and
  the one-row layout all stay. The pane's process is just `claude attach`. Mouse reporting inside
  the cell grid does not reach kitty's title-bar hit region (`kitty/mouse.c:1362`, cited in
  `~/.config/kitty/kitty.conf:384-385`). Live check in kitty: UNMEASURED.

### E7. Environment and identity (`ps eww`, repo code)

- **The daemon freezes the env of whichever process started it.**
  - Daemon 9780 holds `KITTY_WINDOW_ID=4`, `KITTY_LISTEN_ON=unix:/tmp/kitty-48854` and
    `TERM=xterm-kitty` (`ps eww -o command= -p 9780`).
  - Worker 10156 holds `KITTY_PID=48854`, `KITTY_LISTEN_ON=…`, `CC_RR_SID=09c26b2b-…` (the old
    lead's resume-runner id) and `CLAUDE_CODE_SESSION_KIND=bg`. It does **not** hold
    `KITTY_WINDOW_ID`.
  - The denylist `dNe` strips KITTY_WINDOW_ID, ITERM_SESSION_ID, TMUX and TERM_PROGRAM
    (bg-session-semantics Q1).
  - After a kitty restart, every worker of that account still points `KITTY_LISTEN_ON` at the dead
    kitty.
  - Whether the claim overlays the dispatching shell's env in-process: UNMEASURED. `ps eww` shows
    only the exec-time env.
- **Pane-keyed tooling for a bg session:**
  - `hooks/session-register.sh:173` gets no pane, and `:181-185` recovers one only for
    `--fork-session` argv. That is never the case for `--bg --resume <sid>` (same id) or for spares.
  - `handoff-fire.sh:4960-4970` (`hf_bg_hosted`) refuses `--recycle` for any pid under
    `--bg-pty-host`.
  - `bin/it2-kitty` and `get-text`/`send-text` still work on the *attach pane*, because it is a
    normal kitty window. Their pid, tty and "claude on tty" checks see the attach client, not the
    worker.
  - SessionEnd and shutdown tombstones (`hooks/session-deregister.sh`) fire only when the worker
    exits, not when a pane closes.
  - C4 adds that `teammateMode: iterm2` throws without the pane id (C4-hybrids.md:328).
- **Agent view is already disabled in the recovery path.**
  `scripts/limit-recover/lr-fire-resume.sh:1093` and `lr_recon/act.py:70` set
  `CLAUDE_CODE_DISABLE_AGENT_VIEW=1`. The docs also offer `CLAUDE_CODE_DISABLE_BG_EXIT_HANDOFF=1`
  (present in the 2.1.284 strings) to stop carrying exit work into a bg copy.

### E8. Versions (`--help` of each install)

| install | version | `--bg` | `attach` | `respawn` |
|---|---|---|---|---|
| ~/.claude-versions/2.1.114 (the pin) | 2.1.114 | no | no | no |
| ~/.claude-156/-170 | 2.1.156–2.1.170 | no | no | no |
| ~/.claude-183/-219/-220 | 2.1.215–2.1.220 | yes | no | no |
| ~/.claude-260/-280/-284 | 2.1.260–2.1.284 | yes | yes | yes |

Running fleet:
`ps -axo command | grep -E 'claude[-0-9]*/node_modules' | awk '{print $1}' | sort | uniq -c` =>
`33 /Users/chrisren/.claude-284/node_modules/.bin/claude`. So the live fleet is all 2.1.284, and the
2.1.114 pin cannot host C5. Note that `~/.claude-183` actually holds 2.1.215.

### E9. Permission classifier

- Measured: this session ran `claude agents --json`, `claude logs`, `claude stop 9c4a2015` and
  `claude rm 9c4a2015` with no denial. They were on a session it had created.
- `stop`/`kill`/`respawn` on a LIVE session the agent did not create: UNMEASURED, and forbidden to
  test. The brief's rule says the classifier denies killing or tearing down a live session. A
  `respawn` restarts the process, so expect the same treatment.
- `attach` needs a TTY and is an operator or pane action, not an agent action.
- The 9aa483e9 transcript shows the classifier denying a kitty `send-text`-style action as "[Remote
  Shell Writes]" at 19:13:40Z. Typing `/stop` into another session's attach pane would meet that
  rule too.

## Design within C5 (if piloted)

1. **One launcher, `cc-bg-launch`.**
   - It starts every session as `claude --bg [--resume <sid>]` under the account's config dir.
   - It runs with a scrubbed env (`env -u KITTY_* -u CC_RR_* -u WINDOWID ...`) and is the only
     thing that may start that account's daemon, so the daemon env is clean (E7).
   - It writes `~/.claude/bg-map/<short>.json` = `{sid, account, cwd, desk, slot}`. The map replaces
     the pane-keyed registry for bg sessions.
   - The three launch paths change: `bin/cc-pane-runner` (exec at `:102`), `bin/reso-resume-one`
     (`spawn ... --resume` at `:560`) and the `claude()` zsh function. Each calls this launcher,
     then `exec claude attach <short>` in the pane.
2. **Pane = viewer.**
   - Each kitty pane runs `cc-attach <short>`: `claude attach`, plus a loop that re-attaches after
     an accidental `←`/Ctrl+Z, and kitty `--title <name>` for the bar (E6).
   - Real title bars, drag, the 2x2 grid and the one-row layout are unchanged.
3. **Kitty restart or terminal crash: one command, `cc-reattach`.**
   - It reads bg-map plus `agents --json` for the 3 session dirs and rebuilds desks with
     `kitty @ launch ... cc-attach <short>`.
   - No claude process starts, so `capacity-admit.sh` and the /limit-recover nudge are not on this
     path at all. Failures 1 and 3 of 2026-10-01 drop out.
4. **Reboot.**
   - The same command, run by `scripts/boot-resume.sh`: for each map row whose job is `failed` or
     `stopped`, open the pane with `cc-attach <short>`. Attach restarts the session from its
     transcript (docs, E3), and the capacity gate staggers the restarts.
   - In-flight work is lost exactly as in C2. Past 48 h the state is "stopped"; whether attach
     still restarts it then is UNMEASURED.
5. **Recycle and self-close rebuilt.**
   - The successor is a new `--bg` job. The old one gets `/stop` typed into its own attach pane by
     the session itself (self-scope, not a peer kill). The pane re-execs `cc-attach <new>`.
   - Self-close = `/stop` + close the pane.
   - This replaces the `/exit` → shell-prompt contract that `hf_bg_hosted` now refuses.
6. **Pin attached work.** Keep panes attached, which exempts them from retire. During a kitty outage,
   memory-pressure retire (60 s grace) can stop idle unattached sessions. They keep their
   conversation.

**Do now, whatever is chosen (hazard fix, independent of C5):**

- After `handoff-fire` answers `2`, resolve the fork. Its roster row has
  `dispatch.launch.sessionId` ending in `<old-sid>.jsonl`, and `jobs/<short>/state.json` holds the
  state.
- Record the fork in the handoff ledger, and `claude stop <short>` it once its carried task settles
  (`inFlight.tasks == 0`).
- Whether the classifier allows that stop on a copy the recycle itself made: UNMEASURED.
- The alternative is `CLAUDE_CODE_DISABLE_BG_EXIT_HANDOFF=1`, but that stops the land the recycle
  is trying to keep alive.

## Events coverage

| event | C5 outcome | evidence |
|---|---|---|
| (a) terminal crash | Survives: worker, pty host and daemon untouched; in-flight turn, bg Bash, Monitors, subagents and workflows live on; re-attach redraws | measured (E5 kill-server, E1 process tree) |
| (b) kitty restart | Survives: same as (a); daemon is setsid, has no tty and outlived its spawner; one `cc-reattach` rebuilds the desks with no claude launches | measured except kitty SIGKILL itself (UNMEASURED; no signal path to the daemon) |
| (c) Mac reboot | Processes die; job records survive; daemon marks them dead/failed and does not restart them; attach or respawn per id resumes from transcript (same loss as C2) | measured (E3 logs), restart path from docs |

## Cost (estimated: from the files named above and their sizes)

- New: `cc-bg-launch` (~150 LOC), `cc-attach` (~60), `cc-reattach` (~250 including the desk
  layout, reusing `bin/cc-resume-layout.sh`), and the bg-map writer.
- Changed: `bin/cc-pane-runner`, `bin/reso-resume-one`, `~/.claude/lib/claude-launcher.zsh`,
  `hooks/session-register.sh` (map-based address), `scripts/boot-resume.sh`,
  `scripts/handoff-fire.sh` (recycle/self-close around `/stop`: the largest and riskiest part of a
  15k-line script), `hooks/session-deregister.sh`, plus bats tests.
- Total: about 10–12 files, ~1,200–1,800 LOC, 5–8 sessions plus a one-account pilot.
- The hazard fix alone: 1 file, ~80 LOC, 1 session.

## Risks

- **Vendor churn.** The bg semantics changed between 2.1.215, 2.1.260 and 2.1.284 (E8), and the repo
  has absorbed three bg-related incidents already. The fleet's resume and layout tooling would key
  on undocumented internals: `roster.json`, `jobs/*/state.json` and spares.
- **Identity loss.** `KITTY_WINDOW_ID` is stripped, so every pane-keyed hook and actuator needs the
  bg-map. If that is missed, sessions silently lose cc-notify, recycle and the registry, and husk
  sweeps misread the attach client.
- **Frozen daemon env** (E7). A worker can carry another session's `CC_RR_SID` and a dead kitty's
  `KITTY_LISTEN_ON`.
- **Single control point per account.** A plain `claude daemon stop` (no `--keep-workers`) kills
  every session of that account (E1, measured 2026-09-27).
- **Retire and memory-pressure shedding** stop unattached idle workers (60 s grace under pressure),
  including monitoring-only ones. Their Monitor watches then die.
- **Duplicate risk.** `--bg --resume <sid>` while an interactive copy is open "started a copy"
  (binary string), so migration is only safe at a restart boundary.
- **Title.** Claude's own title did not pass through attach (E6). Pane bars show only what kitty is
  told.
- **Agents cannot run the lifecycle verbs.** stop/respawn on others' live sessions is likely denied
  (E9), so recovery stays an operator-run command.
- **The existing hazard (E2) continues until fixed,** C5 or not.

## Open questions

1. Does a SIGKILL of the transient daemon leave workers attachable, so that the next client's
   daemon adopts them? Test on a private config dir that holds only a throwaway job.
2. In kitty, end to end: Shift+Enter, mouse selection and title-bar drag on a pane running
   `claude attach`.
3. After more than 48 h off, does `attach <id>` on a `stopped` job restart it? What does
   `respawn --all` do on a fresh boot?
4. Does the classifier allow `claude stop <fork>` by the recycle that created the fork?
5. Memory and CPU of ~32 workers on one daemon per account at nice 5 under 5–13 load per core.
   Nice 5 may help kitty's main thread (recycle-unreachable-2026-10-01.md).

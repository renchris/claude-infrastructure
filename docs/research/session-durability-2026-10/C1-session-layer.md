# C1: a session layer that outlives the terminal (tmux / kitty sessions / pty broker)

Research dossier for the 2026-10-01 session-durability workflow, candidate C1. This was read-only work.
Experiments ran only on private tmux servers (`-L sd-probe-c1`, `-L sd-probe-c1b`) with dummy processes,
and both servers were killed and their sockets removed afterwards. No `kitten @` call was made, and
`claude` was never launched.

## Answer

**Pick variant (a): tmux, with one private tmux server per Claude session, and kitty demoted to a
viewer that can be restarted.** Each kitty pane runs `tmux -L ccp-<id> attach`, with the status line
off, no prefix and no key bindings. Kitty keeps the OS windows, the 2x2 splits, the real title bars
and drag. Tmux keeps the pty, so the claude process no longer has kitty as an ancestor.

- **(a) Terminal crash** and **(b) kitty restart** become lossless. Measured here: SIGKILL of a
  tmux client, or closing the pty under it the way a kitty death does, leaves the pane process
  running. A fresh attach redraws the preserved screen. In-flight turns, background Bash, Monitor
  watches, cc-await-ping watchers, subagents, teammates and Workflow agents all survive, because
  the process never dies. Recovery is "start kitty, run `cc-reattach`". The attach starts no
  claude, so the capacity gate and the /limit-recover nudge (failures 1 and 3 of 2026-10-01) drop
  out of this path entirely.
- **(c) Mac reboot is not covered.** The tmux servers die with the box, so reboot still needs
  candidate C2's disk resume. C1 only changes where that resume launches (into a tmux host) and
  adds a persisted desk/slot manifest.

Variant (b), kitty's own sessions, is a layout replayer and not a session layer. It re-runs launch
commands, saving needs the same remote-control socket that jammed, and it survives nothing.
Variant (c), dtach/abduco, keeps processes alive with full escape-sequence fidelity. But it has no
screen model, so every composer-readback safety gate in handoff-fire.sh loses its reader. Neither
tool is installed.

**What C1 costs.** C1 is a migration, not a config change. 45 files read `KITTY_WINDOW_ID` and 49
call `kitty @`/`kitten @` (measured, `grep -rl` over bin scripts hooks lib). Pane identity must
move to a stable `CC_PANE_ID`, because a claude process inside tmux keeps a frozen kitty
environment forever. Shift+Enter needs one kitty `map` line. Scrollback moves into tmux.

**Conviction 55.** The survival mechanism is measured and solid. The risk is the size of the
identity migration, plus ergonomics that only the operator can judge.

## Evidence (each item: command ⇒ output)

### E1. The survival property (measured, private tmux 3.6a)
- Server parentage and priority: `ps -o pid,ppid,pri -p <tmux server>` ⇒ `3752 1 31`. The server
  daemonizes to launchd, so a kitty death cannot reach it.
- Killing the client: SIGKILL of the attach client ⇒ `clients after kill: (none)`, and every
  `pane_pid … dead=0` (5 of 5 panes alive).
- Kitty death, simulated by closing the pty master under the client: the client `exited
  status=256`; `pane pid 75993 alive: True`; a new attach ⇒ `reattach redraw contains marker: True`.
- A viewer that never reads: the client was attached but its tty was never read. The pane still
  finished writing 22 MB (`DONE-MARK` in `capture-pane` after 49 s, load ~165).
  Contrast, with no tmux: a writer on a bare pty whose master is never read blocked after
  **3 × 256 B** (`ps` state `Ss+`, 0.03 s CPU). So under tmux, Claude's output path can no longer be
  stalled by a deaf kitty. Whether today's kitty actually stops reading pane ptys when its main
  thread starves is UNMEASURED.

### E2. The control plane leaves kitty's PRI-4 band and kitty's fatal accept path
- `ps -axo pid,pri,comm` ⇒ the unfocused kitty 94453 is at **PRI 4**. The frontmost kitty 48854 is
  at 47. All 35 live claude processes are at **31** (`awk … | uniq -c` ⇒ `35 31`). The tmux server
  is at **31** (E1). Send-keys, capture-pane and kill go to the tmux server, which is a CLI daemon
  and not a GUI app, so App Nap and the background band do not apply. That last point is inferred
  from the PRI readings; App Nap itself is not proven.
- Kitty 0.48.2 `child-monitor.c:1821-1825` (local copy /tmp/kittysrc): any `accept()` error other
  than EINTR returns false, and `talk_loop` `goto end`s (`:2058`). The remote-control thread is
  gone for good.
- tmux 3.6a `server.c:381-389` (fetched from raw.githubusercontent.com/tmux/tmux/3.6a): EAGAIN,
  EINTR and ECONNABORTED are skipped. ENFILE and EMFILE back off 1 s. **Any other errno is
  `fatal("accept failed")`**, and that takes the whole server down with all its sessions. This is
  why the design uses one server per session: the blast radius is one session, not 32. Also,
  each socket then serves only its own session's traffic, so no fleet-wide 128-deep backlog
  (`server.c:138` `listen(fd, 128)`) can form.

### E3. Claude Code under tmux (binary 2.1.284 = `~/.claude-284/node_modules/@anthropic-ai/claude-code-darwin-arm64/claude`, the build all 35 live sessions run; `strings -n 8`)
- **TmuxBackend auto-select.** In `FYt()`, an explicit `teammateMode==="iterm2"` is checked
  **first**, and it throws `teammateMode is set to "iterm2" but this session is not running inside
  iTerm2` when the iTerm2 check `CV()` is false. Only after that does it check `insideTmux` (`Eln()
  { return !!TMUX }`) ⇒ `Selected: tmux (running inside tmux session)`. In `HCt()`, auto mode
  gives `isInProcessEnabled = !insideTmux && !inITerm2`, so in auto mode, having `$TMUX` set turns
  in-process teammates **off** and splits the tmux window instead.
- **This box pins `"teammateMode": "iterm2"`** at line 1305 of `settings.json` in all four config
  dirs (`grep -n teammateMode`). `CV()` passes only via `ITERM_SESSION_ID`, which `~/.zshrc:694`
  synthesizes **only when `cc-in-kitty` proves kitty is an ancestor**. Measured inside a private
  tmux pane: `cc-in-kitty --why` ⇒ `KITTY_WINDOW_ID=41/KITTY_PID=48854 are INHERITED, not ours …
  rc=1`. The same command outside tmux ⇒ `rc=0`. **So tmux as-is breaks teammate spawning with a
  thrown error.** The fix is for the host wrapper to export `ITERM_SESSION_ID=w0t0p0:<CC_PANE_ID>`
  and for the it2 shim to learn tmux. `--teammate-mode <mode>` is also a per-launch CLI flag (it
  is in the binary's help text), so nothing has to write settings.json. Auto/tmux mode is not an
  option: it would put teammates in tmux splits inside one kitty pane, with no kitty title bar.
- **Terminal identity.** The detector returns `TERM_PROGRAM` before it checks `TMUX` or
  `KITTY_WINDOW_ID`. Measured in a pane: `TERM=tmux-256color`, `TERM_PROGRAM=tmux`,
  `COLORTERM=truecolor`. The extended-keys allowlist `esr` contains `"tmux"`, and `MQe()` then
  emits `CSI<u` + `CSI>1u|>5u` + **`CSI>4;2m`** (modifyOtherKeys 2). `Mbt()` returns false when
  `TMUX` or `STY` is set. `kittyGraphics` is computed with `multiplexed: Boolean(TMUX)`, so images
  degrade, which is low stakes. `LT()` wraps OSCs in `\x1bPtmux;…\x1b\\` when the mux is tmux,
  which requires `allow-passthrough on`.
- **Rendering mode.** `"tui": "default"` (`~/.claude-next/settings.json:1297`) is the
  main-screen renderer, so Claude's history lives in **tmux's** scrollback, not kitty's.

### E4. Terminal fidelity through tmux (measured: a python pty client with `TERM=xterm-kitty` and kitty's terminfo, private server)
Settings were `status off; prefix None; set-titles on; set-titles-string '#{pane_title}';
extended-keys on; extended-keys-format csi-u; allow-passthrough on; set-clipboard on;
default-terminal tmux-256color; terminal-features xterm-kitty:RGB:extkeys:clipboard:title:sync:hyperlinks:usstyle:focus`.
- tmux's client-feature report for the kitty client ⇒ `bpaste,ccolour,clipboard,hyperlinks,cstyle,extkeys,focus,overline,RGB,strikethrough,sync,title,usstyle`.
- **OSC title, which the title band and kitty's tab/window titles depend on:** the pane emits OSC 2,
  and the client sends `\x1b]0;CC-TITLE-PROBE` / `\x1b]0;TITLE-AFTER-ATTACH` to kitty. The title
  also persists as `#{pane_title}` while detached and is replayed on attach.
- **OSC 52:** plain ⇒ `\x1b]52;c;aGVsbG8=` forwarded. Claude-style DCS-wrapped ⇒ forwarded.
  Both reach kitty only if a client is attached at that moment. Emitted while detached, they were
  dropped (count 0 in the first run).
- **Bracketed paste, mouse, sync:** `?2004h`, `?1000h` and `?1006h` were mirrored to the outer
  terminal. With tmux `mouse off`, an SGR click, a wheel event and a bracketed paste were delivered
  byte-exact to a pane app that had requested them. `?2026` synchronized output was used.
- **Keys:** with the pane app in modifyOtherKeys 2 (`#{pane_key_mode}` ⇒ `Ext 2`):
  `CSI 13;2u` in ⇒ `CSI 13;2u` out; `CSI 27;2;13~` ⇒ `CSI 13;2u`; ESC CR ⇒ `CSI 13;3u`; CR ⇒ `0d`.
  With an app in `VT10x`, `CSI 13;2u` collapses to `0d`.
- **Kitty never sends a distinct Shift+Enter to tmux.** tmux 3.6a sent neither `CSI>4;Nm` nor any
  kitty-keyboard push to the outer terminal (regex count 0 over the whole attach stream), and
  `man tmux | grep -ci kitty` ⇒ 0. Kitty 0.48.2 `screen.c:1845-1855` handles `CSI>4;…m` by only
  logging an error. Its legacy encoder (`key_encoding.c:125-127`, `:186-188`) sends Shift+Enter as
  bare `\r`. **So Shift+Enter would submit instead of inserting a newline** unless kitty maps it.
  The fix is one line in kitty.conf:
  `map --when-focus-on var:cc_host shift+enter send_text all \x1b[13;2u`. `--when-focus-on`
  exists in 0.48.2 (`options/utils.py:1352`), and the `cc_host` var is set by `launch --var`.
  tmux then forwards `CSI 13;2u` (measured above). The Claude-side newline was not tested with a
  live claude: UNMEASURED.
- **Environment trap:** a session made by `new-session` from a shell with `KITTY_WINDOW_ID=222`
  got **111**, the server's start-time global env. With `-e KITTY_WINDOW_ID=333` it got 333. Any
  per-pane identity must be passed with `-e`. Even then it freezes for the life of the process, so
  after a kitty restart every `KITTY_*` variable inside claude is stale.

### E5. Variant (b): kitty 0.48.2 session save/restore (source fetched from v0.48.2)
- `save_as_session` (`kitty/session.py:652-737`) has the options `--save-only`,
  `--use-foreground-process`, `--relocatable`, `--match` and `--base-dir`. It is invoked as a kitty
  action (key map or `kitten @ action`) and writes a `.kitty-session` file. `startup_session` and
  `--session` replay it at launch (`main.py:294-301`).
- `Window.as_launch_command` (`window.py:2342-2437`) serializes `launch --cwd … --env … --var …
  --title … <creation cmd>`. With `--use-foreground-process`, it adds the foreground cmdline as
  `cmd_at_shell_startup`. **It re-executes a command; it keeps nothing alive.** A bare `claude`
  replays as a new session. The roster's actual resume target is the transcript sid, which the
  repo's resume chain already holds.
- Saving needs either the remote-control socket or a keystroke, and the socket is exactly what
  wedged. It also bypasses capacity admission, the live-holder dedup
  (`boot-resume-launch.sh:257,292`) and account routing. **Verdict: no survival for (a), (b) or (c).
  At best it is a second, weaker copy of `cc-resume-layout.sh --desktops`.**

### E6. Variant (c): a per-session pty broker (dtach/abduco, or one we own)
- `command -v dtach abduco` ⇒ neither is installed (as the brief says); `/usr/bin/screen` exists.
  dtach-style brokers pass bytes through without emulating a terminal. The upside is that kitty
  keyboard protocol, titles, OSC 52 and images all reach kitty natively.
- The downsides are decisive here:
  1. There is **no screen model**. handoff-fire.sh's safety gates read the pane (`it2 session
     read` appears 7 times; examples are `hf_focus_gate` and `hf_exit_readback`,
     `handoff-fire.sh:3011`, `:3163`). With nothing to read, they fail closed, so recycles stop.
  2. On reattach the new kitty window starts blank and in legacy key mode. The modes Claude pushed
     at startup (kitty keyboard flags, bracketed paste, mouse) went to the old kitty, so
     Shift+Enter breaks until Claude re-asserts them. Claude has a mode-reassert table (`f=
     {bracketedPaste:0,…,focusEvents:4}`), but its trigger is UNMEASURED.
  3. Input injection exists only as `dtach -p` (stdin push). There is no way to enumerate, focus
     or capture panes.
- An owned broker that adds a screen model (pyte or similar) amounts to rewriting tmux.
  **Verdict: viable only as a fallback. Not recommended.**

### E7. Cost at 32 sessions (measured on this box under load 120-170 on 10 cores; `uptime` ⇒ `load averages: 168.61 …`)
- One shared server holding 32 sessions × 3000 lines × 150 wide glyphs (history-limit 2000):
  `ps -o rss` went from 4,080 KB to **144,304 KB**. That is a worst case, because non-ASCII cells
  are stored as extended cells.
- Per-session server with 1 pane and a full 2000-line history: **6,432 KB**. Attach client:
  **3,184 KB**. So about 9.6 MB × 32 ≈ **310 MB**, against **20,678 MB** for the 35 live claude
  processes (mean 591 MB). That is about 1.5%.
- CPU: relaying 22 MB of truecolor lines cost the tmux server **3.22 s** of CPU under load ~165,
  about 0.15 s/MB. Because tmux coalesces redraws, the client forwarded only **0.8 MB** to the outer
  terminal, so kitty parses less than it does today. A fleet estimate (method: assumed 20 KB/s per
  active session × 32 ≈ 0.64 MB/s, times 0.15 s/MB) is ≈ **10% of one core**. Claude's real output
  rate is UNMEASURED.

## Design (variant a)

1. **Host wrapper `bin/cc-tmux-host <pane-id> [--cwd D] [--env K=V…] [-- cmd…]`.** This is the
   single seam. If server `ccp-<id>` exists, it `exec`s `tmux -L ccp-<id> -f <repo>/config/cc-tmux.conf
   attach`. Otherwise it creates the session with `-e CC_PANE_ID=ccp-<id> -e
   ITERM_SESSION_ID=w0t0p0:ccp-<id> -e CLAUDE_CONFIG_DIR=…` and the command, then attaches. It
   uses its own config, **never ~/.tmux.conf**. That file binds `C-h/j/k/l` with no prefix
   (`bind -n C-j select-pane -D`), which would steal Claude's Ctrl-J newline, and it loads
   resurrect/continuum. Config: E4's settings plus `exit-empty on`, `remain-on-exit on` (so a
   recycle can `respawn-pane` in place, the TmuxBackend shape cited at `cc-pane-runner:20-23`),
   `history-limit 10000`, and `unbind -a` on the root and prefix tables. Desk and slot are stored
   as tmux user options (`@desk`, `@slot`, `@sid`, `@account`) and mirrored to
   `~/.claude/cc-hosts/<id>.json` for reboot.
2. **Viewer.** Every kitty pane runs `cc-tmux-host <id>` launched with `--var cc_host=<id>`, so
   kitty's title bars, drag, `cmd+d` splits, the move menu and fullscreen are unchanged. The title
   band reads kitty's window title, which tmux's `set-titles` keeps equal to Claude's OSC title.
3. **Identity.** `CC_PANE_ID=ccp-<id>` (the existing `CC_PANE_ID` seam, already in 10 bin files) is
   the durable key in cc-registry, handoffs and cc-notify. It survives kitty restarts.
   `KITTY_WINDOW_ID` becomes a derived and volatile fact: map a host to the kitty window that
   currently views it with `tmux list-clients -F '#{client_pid}'`, then walk the client's parent to
   a kitty window pid. Nothing inside claude may trust its own `KITTY_*` env again.
4. **Control plane.** Add a tmux arm to the it2 shim behind its 8 verbs (`split list send type run
   close focus|read tui-submit`, `bin/it2-kitty:1094-1489`): `send-keys -l`, `capture-pane -p`,
   `list-sessions`, `kill-server`, and `split` = new host + best-effort `kitty @ launch` viewer.
   Recycle, self-close and engagement checks then talk to the session's own tmux socket. Only
   *showing* a pane (launch viewer, fullscreen, move) still needs kitty's socket. When kitty is
   deaf, a fired session still starts and runs headless, and a viewer is attached later.
5. **`cc-reattach` (one command; zero once kitty's `startup_session` or a launchd watcher runs it
   on kitty start).** Enumerate `/tmp/tmux-501/ccp-*`, group by `@desk`, then open one OS window
   per desk with up to 4 `cc-tmux-host` viewers in the 2x2 (reusing cc-resume-layout's
   launch/rotate code). Fullscreen with `kitten @ action --match id:<w> toggle_fullscreen` (the
   plan's verified fix for failure 2). No capacity admission, because attach starts no claude, and
   no nudge.
6. **The 3 launch paths.**
   - (i) `cc-pane-runner`: it2-kitty `split` creates the host with `zsh -l -i -c 'exec
     cc-pane-runner'` inside it.
   - (ii) `reso-resume-one`: `cc-resume-layout.sh:257-264` changes `zsh -ic "$cmd; exec zsh -i"`
     to `cc-tmux-host <new-id> --cwd "$wt" -- zsh -ic "$cmd; exec zsh -i"`.
   - (iii) Hand-opened zsh: `claude()` in `lib/claude-launcher.zsh` re-execs through
     `cc-tmux-host new -- claude "$@"` when `$TMUX` is unset (opt-out with `CC_NO_HOST=1`). On
     exit, `exit-empty` ends the server and the pane returns to its prompt.
7. **Close semantics change.** Closing a kitty window now *detaches*. `kitty-confirm-close` must
   offer "detach (keeps running)" or "end session", and `cc-pane-close` ends by `tmux -L ccp-X
   kill-server` behind its existing four gates. Every headless census must count hosts. Today's
   dedup keys on live holders (`boot-resume-launch.sh:292`), which already sees a live
   tmux-hosted claude.

## Events coverage

| Event | What survives under C1 | Recovery | Lost |
|---|---|---|---|
| (a) kitty crash / SIGKILL | every claude process, its in-flight turn, background Bash, Monitors, cc-await-ping, subagents, teammates, Workflow agents, screen state (E1) | relaunch kitty, then `cc-reattach`: 1 command, or 0 if hooked to kitty start | only the viewers; the OSC 52 or bell emitted while detached is dropped (E4) |
| (b) deliberate kitty restart (deaf socket, zombies) | same as (a); a restart is now free, so a wedged socket costs seconds | same; no capacity gate, no nudge | nothing that matters |
| (c) Mac reboot | nothing in memory; tmux dies. Disk: transcripts, cc-registry, tombstones, the `cc-hosts/*.json` desk/slot manifest | C2's boot-resume, launching each `--resume` inside a `cc-tmux-host` | in-flight turn, background work, Monitors, teammates, workflows (needs C2's re-engage nudge) |
| tmux server fatal (new failure mode) | the other 31 sessions (one server each) | disk resume of that one session | that one session's in-flight state |

## Build cost (estimate: counted from the files named above plus typical sizes in this repo)
- New: `bin/cc-tmux-host` (~200 LOC), `config/cc-tmux.conf` (~40), `bin/cc-reattach` (~250,
  reusing cc-resume-layout functions), and bats suites (~400).
- Edited: `bin/it2-kitty` tmux arm (~400), `scripts/handoff-fire.sh` identity and kt call sites
  (30 `KITTY_WINDOW_ID` and 33 `kitty @` sites, mostly behind the shim), `hooks/session-register.sh`
  registry key, `bin/cc-pane-close`, `bin/kitty-confirm-close`, `bin/cc-resume-layout.sh`,
  `lib/claude-launcher.zsh`, `~/.zshrc` identity block, `kitty.conf` (1 line), `bin/cc-pane-runner`
  and `bin/reso-resume-one` comments/guards.
- Total ≈ 15-25 files and ≈ 1,500-2,500 LOC across 3 phases: host+viewer+reattach, control plane,
  identity migration. About 4-6 dispatched sessions over 2-3 days.

## Risks
1. **The identity migration is wide.** 45 files read `KITTY_WINDOW_ID`, and the env inside claude
   is frozen, so stale-id bugs (the it2-kitty:62-70 "recycled window id" class) multiply until
   every reader goes through `CC_PANE_ID`. Phase it, and keep kitty-only behavior as the default
   path until the shim passes.
2. **Teammate spawning throws** under tmux unless the host exports `ITERM_SESSION_ID` and the shim
   accepts `ccp-` ids (E3).
3. **Shift+Enter** depends on the kitty `map` (E4). If someone drops it, Shift+Enter silently
   submits the prompt.
4. **Scrollback ergonomics.** With `tui: default`, history lives in tmux. Kitty's wheel and search
   no longer see it. Either enable tmux `mouse on` (copy-mode scroll, OSC 52 copy) or move to
   Claude's fullscreen TUI. This is an operator call, and UNMEASURED with real Claude.
5. **Close now means detach**, so unseen headless sessions can accumulate and burn tokens. The
   census and close UI must show hosts.
6. **tmux `fatal("accept failed")`** on an unexpected errno (E2) kills a server. One server per
   session bounds that to a single session.
7. **Agent operations stay classifier-bound.** Ending a live session through tmux is still
   "killing a session", so the auto-mode classifier rules are unchanged.
8. **Reboot is untouched.** C1 without C2 leaves (c) exactly as bad as 2026-10-01.

## Open questions (not measured here)
- A real Claude 2.1.284 inside tmux: Shift+Enter via the map, Option+Enter, the `/` menus, image
  paste, OSC 8 links, and focus events. One throwaway session in a private host would settle these.
  This dossier did not launch claude, per the brief.
- Does Claude re-assert terminal modes after a reattach? tmux replays its own mode state, so it
  likely does not matter, but this is UNMEASURED.
- Does kitty's I/O thread stop reading ptys when the main thread sits at PRI 4? If it does, today's
  sessions also stall on output, and C1 fixes that too (E1 contrast).
- Kitty's `startup_session` as the zero-step trigger for `cc-reattach`, versus a launchd watcher on
  `/tmp/kitty-*` sockets.

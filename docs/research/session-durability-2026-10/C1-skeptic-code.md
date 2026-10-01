# C1 skeptic, code-and-evidence lens

This review tries to refute `C1-session-layer.md`. It was read-only apart from this file. Probes ran
on private tmux servers only (`-L sd-probe-skc`, `-skc2` to `-skc5`, with `sleep`/`sh`/`head` as the
dummy processes). All were killed and their socket files removed. I made no `kitten @` call and never
launched `claude`. I fetched tmux 3.6a and kitty v0.48.2 sources and a `strings` dump of the Claude
2.1.284 binary into `/tmp/sd-skc1/` as scratch files, then deleted them.

## Answer

**No fatal flaw. The core mechanism holds, and I replicated it independently.** A tmux pane survives
its client being SIGKILLed or having its pty closed, a fresh attach redraws the screen, and a viewer
that never reads cannot stall the pane. Every kitty and tmux source line the dossier cites checks
out. But the dossier overstates how complete the design is:

- The proposed config contradicts itself on session exit.
- The config as written gives no way to scroll back, and the wheel sends arrow keys into Claude.
- The migration surface is about 30% larger than counted.
- Under tmux, every claude runs in launchd's `Background` session, not the `Aqua` GUI session.
  Nobody has measured what that does to the 57 scripts that call `osascript`.
- The "blast radius is one session" argument ignores an errno (ENOMEM) on which tmux kills the
  server, and with it the session's own claude.

**Recommended conviction: 48** (dossier: 55).

## Verdicts on the key claims

| # | Claim | Verdict | Evidence (command => output) |
|---|---|---|---|
| 1 | The pane survives the client being SIGKILLed or its pty closing, and reattach redraws | **stands** | My python pty client against `-L sd-probe-skc`: closing the master => `client after master close waitpid: (35065, 256)`, `clients now: (none)`, `pane pid alive: True`, `reattach redraw contains marker: True`. SIGKILL of a second client => `clients: (none)`, `dead=0 pid=35061`. `ps` => server `14151 1 31 Ss` (ppid 1, PRI 31). Caveat: this simulates kitty's death. A real kitty SIGKILL with a kitty-spawned server was not run (forbidden), so that case is UNMEASURED. |
| 2 | A viewer that never reads cannot stall Claude's output | **stands** | tmux `tty.c:87-89` and `:224-236`: TTY_BLOCK drops output to a slow client (it does not block on it). Replicated: client attached and never read => `pane finished 10.8MB base64: True after 3.0s` (load 25-60). Whether kitty stalls today's ptys is still UNMEASURED, as the dossier itself says. |
| 3 | The control plane leaves kitty's PRI-4 band | **weakened** | The PRI readings are real. `ps` now => staged kitty 94453 at PRI 4, its `login`/`zsh` children at 31, main kitty 48854 at 54, `43 31` claude.exe. But claude is **already** at 31 under kitty, so C1 moves only the RPC endpoint. Several things stay on kitty's socket: the focus half of the recycle gate (`hf_focus_gate`, `handoff-fire.sh:3011`, `HELD:focused`), viewer launch for every split, fullscreen and move, and Claude's teammate availability probe. `yct()` in the binary runs `it2 session list`, which goes through it2-kitty to `kitten @ ls`. The dossier's config also omits `focus-events`, which would be the tmux-side substitute for the focus read. App Nap remains unproven. |
| 4 | tmux recovers from EMFILE and ECONNABORTED; any other errno is fatal; that is the reason for one server per session | **weakened** | The cites are exact: tmux `server.c:138` `listen(fd, 128)`; `:382` EAGAIN/EINTR/ECONNABORTED return; `:384-387` ENFILE/EMFILE back off; `:389` `fatal("accept failed")`. kitty `child-monitor.c:1821-1826` returns false on anything but EINTR, then `:2058` `goto end` and `:2082` `end:`. **But** `man 2 accept` on this Mac lists `[ENOMEM]`, which tmux treats as fatal. A tmux server's death hangs up its pane, so the claude dies with it, which is strictly worse than kitty, where only the RC thread died and every session lived. If the trigger is box-wide (memory pressure), every per-session server that is accepting at that moment dies together. The control plane now polls all 32 servers, so "one session" assumes failures are independent. Partly offsetting this: kitty's listen socket is blocking (`boss.py:230-241`, Python `s.listen()`), and launchd's soft `maxfiles` is `256` (`launchctl limit maxfiles`). That makes EMFILE or ECONNABORTED plausible kitty killers, and tmux survives exactly those. All of this is UNMEASURED: the kitty errno is unknown. |
| 5 | As configured, tmux breaks teammate spawning with a thrown error | **stands, and the fix is undercounted** | Binary: `FYt(){… if(jut()==="iterm2"){if(!CV(e))throw … 'not running inside iTerm2'` and `CV(){… s==="iTerm.app"\|\|!!a.ITERM_SESSION_ID\|\|…}`. `grep -n teammateMode` => `:1305` in all 4 `settings.json`. `~/.zshrc:694` is gated on `cc-in-kitty`. **Missed:** `bin/it2-wrapper:122-123` execs `it2-kitty` only when `cc-in-kitty` passes. Inside tmux that check fails by design (ancestry), so `it2` falls through to the **iTerm2** CLI path. `it2-wrapper`, `cc-in-kitty` and `it2-kitty`'s digits-only `valid_id` (`it2-kitty:62-70`) all have to change. Only it2-kitty is in the build list. |
| 6 | In auto mode, `$TMUX` selects TmuxBackend and turns off in-process teammates | **stands (moot here)** | Binary `HCt()`: `if(n==="tmux"\|\|n==="iterm2")a=!1;else{… a=!s&&!i}`. Teammate mode is pinned to `iterm2`, so in-process teammates are already off on this box. |
| 7 | kitty sends Shift+Enter to tmux as bare CR; one `map` fixes it | **stands, with a gap** | kitty `key_encoding.c:124-126` (Enter => `\x0d`, ESC prefix only for Alt), `:192` `SIMPLE("\r")`; `screen.c:1844-1854` only logs modifyOtherKeys. Replicated: `pane_key_mode: Ext 2`; input `\x1b[13;2u` => pane read `1b 5b 31 33 3b 32 75`; `outer stream has CSI>4: False`. **Gap:** `var:cc_host` is an existence match (`window.py:919-920` plus `compile_match_query` `:245-254`), set only by `launch --var`. Path (iii), hand-opened zsh, is never launched that way, so Shift+Enter would **submit** there. The fix is for the host to emit OSC 1337 `SetUserVar`, which kitty supports (`window.py:1352`). It is not in the design. |
| 8 | OSC title, OSC 52, bracketed paste, mouse and sync pass through | **stands for passthrough; the consequence is missed** | Attach stream (my capture) => starts `\x1b[?1049h` (tmux `tty.c:357` SMCUP), then `\x1b[?2004h`, then the title `\x1b]0;MacBookPro.localdomain\x07`, which is the hostname until Claude retitles. On the alternate screen with no mouse tracking, kitty turns the wheel into Up/Down **key presses** (`mouse.c:1560-1565` calls `fake_scroll`, `keys.c:315-329`). See missed risk 1. |
| 9 | The pane env is the server's start-time env unless passed with `-e` | **stands** | Replicated: server started with `FOO_SKC=111`; `new-session` from `FOO_SKC=222` => `s2: FOO=111`; with `-e FOO_SKC=333` => `s3: FOO=333`. |
| 10 | kitty 0.48.2 sessions replay layout and commands; they keep nothing alive | **stands** | `session.py:652` (options `:654/659/671/685`), `:722` `save_as_session`; `window.py:2342` `as_launch_command`; `main.py:294-301` `startup_session`. Not mentioned: a session file is a ready-made zero-socket **viewer** launcher for `cc-reattach` (`launch cc-tmux-host <id>` lines). |
| 11 | Memory and CPU cost is small | **weakened** | Re-measured: 1 pane, 150 columns, truecolor, `history_size=1961` => server **12,272 KB** RSS, 1.9x the dossier's 6,432 KB. The design sets `history-limit 10000`. ESTIMATED by linear scaling: about 55 MB per server, about 1.9 GB for 32 servers, not 310 MB. That is still about 9% of the measured 20.7 GB for claude, so not decisive. The fleet CPU figure is an estimate. Claude also changes its own output under `$TMUX`: binary `ae(){… if(a.TMUX&&u.level>2)return u.level=2` drops truecolor to 256 colors unless `CLAUDE_CODE_TMUX_TRUECOLOR` is set, and `eAn()` gates DECSTBM. Both are UNMEASURED. |

Smaller numeric drift (measured with `grep -rl` in both this worktree and the shared checkout on
`main`):

| Count | Dossier | Measured |
|---|---|---|
| files reading `KITTY_WINDOW_ID` | 45 | **43** |
| bin files using `CC_PANE_ID` | 10 | **14** |
| `kitty @`/`kitten @` lines in `handoff-fire.sh` | 33 | **26** |
| `session read` in `handoff-fire.sh` | 7 | **8** |
| files calling `kitty @`/`kitten @` | 49 | 49 (matches) |

None of these changes a conclusion.

## Design defects found in the dossier's own text

1. **`remain-on-exit on` contradicts §6(iii).** The design says (`C1-session-layer.md:183-184` with
   `:214-215`) "On exit, exit-empty ends the server and the pane returns to its prompt". Measured with
   both options on: after the command exits => `dead=1 status=0`, the session list still shows
   `a: 1 windows`, and `capture-pane` => `Pane is dead (status 0 …)`. The server does **not** exit,
   so a hand-opened pane is left showing a dead-pane banner instead of returning to its prompt.
2. **No scrollback path.** `unbind -a` on root and prefix, plus `prefix None` and `mouse off`, plus
   SMCUP on the outer kitty, means kitty's scrollback receives nothing and tmux copy-mode cannot be
   reached. Claude 2.1.284 itself warns in this state: `"tmux detected · scroll with PgUp/PgDn · or
   add 'set -g mouse on' to ~/.tmux.conf for wheel scroll"` (binary `Ivo()`). The dossier files this
   as "ergonomics, operator call". In fact it is a missing feature plus an input hazard (see missed
   risk 1).
3. **`kill-server` leaves the socket file.** Measured: after `kill-server`, all five
   `/tmp/tmux-501/sd-probe-skc*` sockets still existed and each answered `no server running`. So
   `cc-reattach`'s plan to "enumerate `/tmp/tmux-501/ccp-*`" will list dead hosts unless it probes
   each one with `has-session`.

## Fatal flaw

None found. Each defect above has a known, bounded fix. None contradicts the survival property that
C1 rests on.

## Missed risks

1. **The wheel becomes arrow keys into Claude.** kitty `mouse.c:1560-1565` calls `fake_scroll` on
   the alternate screen when the app has not enabled mouse tracking, and `keys.c:315-329` sends
   GLFW_FKEY_UP/DOWN. Under C1, kitty is on the alternate screen (tmux SMCUP, measured), so a scroll
   gesture would cycle the composer's prompt history or move the selection in a permission or
   select menu. Whether Claude's `tui: default` renderer enables mouse tracking is UNMEASURED. No
   `?1000h`/`?1002h`/`?1003h` literal appears in the binary's strings.
2. **Every claude moves out of the Aqua session.** tmux's `compat/daemon-darwin.c:72` re-homes the
   server with `bootstrap_look_up_per_user`. Measured in a private pane: `launchctl managername` =>
   `Background`, against `Aqua` outside tmux. `pbpaste` (rc 0) and the login keychain listing still
   work. But 57 non-test repo files call `osascript`, and the repo itself records that the GUI path
   "needs an Aqua session" (`scripts/limit-recover/lr-reset-poller.sh:27`). System Events,
   Accessibility, notifications and Keychain ACL prompts from inside a tmux-hosted session are all
   UNMEASURED. TCC "responsible process" attribution, once the spawning kitty is dead, is also
   UNMEASURED.
3. **The migration surface is undercounted.** 59 non-test files read some kitty identity signal
   (`KITTY_WINDOW_ID|KITTY_LISTEN_ON|KITTY_PID|foreground_processes|cc-in-kitty`), not 45.
   - 8 of them classify panes by kitty's `foreground_processes`, which under C1 will show a
     `tmux attach` client, never claude. One example is `lr_recon/observe.py:255` `_pane_state`,
     which then returns `unknown` for every pane.
   - 32 read `KITTY_LISTEN_ON`/`KITTY_PID`, which are frozen at a dead socket after a restart.
   - The build list also omits `bin/it2-wrapper` and `bin/cc-in-kitty`.
   - On this evidence, "1,500-2,500 LOC, 2-3 days" is optimistic (ESTIMATED: judgment from the file
     counts).
4. **A tmux fatal is a new way to kill a live claude** (claim 4). The safety story should say
   "disk-resume of that session", and a supervisor would have to detect it. Nothing in the design
   watches for a host whose server vanished.
5. **The recycle focus gate needs a viewer-side fact.** Under C1, `hf_focus_gate`'s `HELD:focused`
   needs either kitty's socket or tmux `focus-events on` and the `client_flags` focused flag. The
   proposed config has neither. When kitty is deaf, the gate either fails closed, so recycles stop,
   or reads stale focus.
6. **Things that look the same but are not.** The title shows the hostname until Claude retitles
   (measured `\x1b]0;MacBookPro.localdomain`). Colors drop to 256 (`ae()`). `cmd+d`'s
   `--cwd=current` (`kitty.conf:193`) now resolves to the `tmux attach` client's cwd.
7. **Mitigating fact the dossier could have cited.** The dedup really does see a live tmux-hosted
   claude. `lr_holder_count` relies on `kill -0` of the registry pid (`lr-lib.sh:280-301`), and
   `cc-reaper` never kills tmux or any subtree holding claude (`bin/cc-reaper:551`). So boot-resume
   would not double-launch a session that survived in tmux.

## Recommended conviction: 48

Survival for events (a) and (b) is real, replicated, and directly answers 2026-10-01. Without it,
failures 1 and 3 cannot recur on those events. Three things pull the number below the dossier's 55:

- The config as written has two defects: a contradiction on session exit, and no scrollback with a
  wheel-to-arrow-key hazard.
- The launchd `Background` session is an untested change of execution context for every session.
- The migration is about 30% wider than counted.

A one-session pilot with a real Claude would settle the Background-session and input questions
cheaply. It needs:

- `mouse on` plus the wheel binding;
- `focus-events on`;
- `SetUserVar cc_host`;
- a `pane-died` hook in place of `remain-on-exit`.

---

# Second pass (independent re-run, 2026-10-01 ~15:10-15:25 local)

This file already existed (committed in 55753e737), so this pass is appended instead of overwriting it.
Scope: read-only, apart from this append. Probes ran on private servers `-L sd-probe-skc1b` to `-skc1g`,
using `sleep`/`sh`/`python3` as dummy processes. All were killed, and their socket files and the
`/tmp/sd-skc1b/` scratch files (fetched sources, a binary `strings` dump) were deleted. I made no
`kitten @` call and did not launch `claude`.

## Answer (second pass)

**No fatal flaw, but conviction should go down to 45.** I replicated the survival property again.
Every source cite still checks out. Three things that both passes before this one missed carry more
weight than the config defects already listed:

1. **C1 removes the repo's chosen identity oracle.** Many gates use "kitty is my ancestor" as the
   evidence of which pane a session owns. Under C1 that evidence is gone. Every hosted session pins
   itself to the iTerm2 path, and the limit-recover reconciler can no longer bind a holder to a pane.
   None of this is in the build list.
2. **C1 compares tmux against dtach and kitty sessions, but never against the first-party session
   layer that is already running on this box.** That layer is Claude Code 2.1.284's `claude daemon`
   with `bg-pty-host` and `claude attach`.
3. **A finished host leaks forever.** The only garbage collector on the box is structurally blind to
   it.

## Verdicts (second pass, own measurements)

| # | Verdict | Evidence (command => output) |
|---|---|---|
| 1 survival | **stands** | `survive.py` on `-L sd-probe-skc1d`: after the pty master closed => `client waitpid (73782, 256)`, `clients after: (none)`, `pane pid 71095 alive: True pane_dead: 0`, `server ps: 71072 1 31 Ss`. Reattach => `has marker: True`. |
| 2 no viewer stall | **stands, and the kitty side is now sourced** | A bare pty writer whose master is never read => `bytes written before block: 1024 writer state: Ss` (ptyblock.py). tmux `tty.c:220-240` discards output to a slow client. kitty v0.48.2 `child-monitor.c:1667` polls POLLIN on a pane only when `vt_parser_has_space_for_input`, and parsing runs on the **main** thread (`parse_input` `:488`, called from the main loop at `:1406`). So a starved kitty main thread does stop the reads and blocks claude's writes. The dossier left this as an open question. A live stall is still UNMEASURED. |
| 3 PRI band | **weakened** | `ps` now => `94453 4` (the staged kdw4 kitty, not the main one), `48854 47`, `34` claude at `31`, tmux servers `31` with ppid 1. claude is already at 31, so only the RPC endpoint moves. tmux's PRI while the screen is locked is UNMEASURED. |
| 4 accept errors | **stands** (as source) | tmux 3.6a `server.c:138` `listen(fd, 128)` and `:381-389`, exact. kitty `child-monitor.c:1821-1826` and `:2058` `goto end`, exact. kitty's `perror` goes to stderr, which is /dev/null. I found no `RLIMIT_NOFILE`/`setrlimit` in boss.py, main.py, child-monitor.c, data-types.c, child.c, launcher/main.c or cocoa_init.m (grep => 0 hits), and `launchctl limit maxfiles` => soft `256`. So EMFILE is a plausible kitty killer, and tmux survives exactly that error. UNMEASURED. The first pass's ENOMEM and correlated-failure caveats still apply. |
| 5 teammate throw | **stands** | Binary (second definition of `FYt`): `if(jut()==="iterm2"){if(!CV(e))throw … 'not running inside iTerm2'…;if(!await yct(e))throw`. Exporting `ITERM_SESSION_ID` gets past `CV` only. `yct` then probes `it2`. In a private pane, `cc-in-kitty` => `plain-rc=1` and `INHERITED, not ours` (cik.sh), so the probe goes down the iTerm2 path. |
| 6 auto picks tmux | **stands (moot)** | Binary: `d=a.TMUX` beside `function Eln(){return!!d}`. `HCt`: `if(n==="tmux"\|\|n==="iterm2")a=!1;else{…a=!s&&!i}`. |
| 7 Shift+Enter | **stands** | `key_encoding.c:122` puts an ESC prefix only for ALT, `:125-126` Enter => `\x0d`, `:192` `SIMPLE("\r")`. `screen.c:1845-1854` only logs. `options/utils.py:1352` `when_focus_on`. The binary's `MQe` = `BVr`(`<u`) + `DWo`/`OWo`(`>1u`/`>5u`) + `MWo`(`>4;…`). A real claude newline is UNMEASURED. |
| 8 passthrough | **stands; the scroll consequence is contested** | Not re-measured. The binary probes `tmux show -Av mouse` and `show -gv focus-events` with a bare `tmux`, which reaches the per-session server through `$TMUX`. When mouse is off, it prints `tmux detected · scroll with PgUp/PgDn · or add 'set -g mouse on' … for wheel scroll`. But `kitty.conf:113-115` and `:207-209` record that Claude "grabs the mouse", and E4 shows tmux mirroring `?1000h/?1006h`. The first pass's "wheel becomes arrow keys" risk is therefore unproven in both directions. |
| 9 env trap | **stands** | Replicated: server born with `FOO_SKC=111`; `s2 ['FOO=111']`; with `-e` => `s3 ['FOO=333']`. |
| 10 kitty sessions | **stands** | `session.py:652-692` (options), `window.py:2342` `as_launch_command`, `:2406-2434` `cmd_at_shell_startup`, `main.py:294-301`. All exact. |
| 11 cost | **weakened** | Measured with history-limit 10000 and 12,000 lines of 150-column truecolor text => `history_size: 9059`, server RSS **38,064 KB**. An idle server was 3,664 KB. ESTIMATED as 38 MB x 32 ≈ 1.2 GB, not 310 MB. That is about 6% of claude's 20.7 GB, so it does not decide anything. |

Count drift (`grep -rl` over bin scripts hooks lib): 43 files read `KITTY_WINDOW_ID` (the dossier says
45). handoff-fire.sh has 30 `KITTY_WINDOW_ID` lines (matches the dossier) and 26 `kitty @` lines (the
dossier says 33). The launch line the dossier cites at `cc-resume-layout.sh:257-264` is at `:266`.

## Missed risks (new in this pass)

1. **The identity oracle is inverted.** handoff-fire.sh's own header reads "THE ENV VAR IS A CLAIM, THE
   PROCESS TREE IS THE EVIDENCE" (`:1995`). The gates:
   - `pane_ownership` (`:2072-2088`) tests whether the kitty window's launched pid is in the caller's
     ancestry. Under C1 it never is: claude's ancestors are the tmux server and then launchd.
   - `pin_term_verdict_for_watcher` (`:1939-1951`) maps `cc-in-kitty` rc 1 to `CC_TERM=iterm2`. The
     measured rc inside tmux is 1. So every hosted session's self-close and recycle take the iTerm2
     transport, or get REFUSED as `not-mine`.
   - lr_recon binds holders by walking the ppid chain to a kitty window root
     (`observe_rows.py:288-298`). `_identity_match` (`evidence.py:132-141`) then requires
     `kitty_pid`, `window_id` and `root_pid` to match. Limit recovery can no longer act in place.

   52 non-test files both walk ancestry (`ppid|ancestr`) and mention kitty. The dossier names none of
   `pane_ownership`, `lr_recon` or `it2-wrapper`. Consequence: phase 1 alone (host, viewer and
   reattach) breaks recycle and self-close for every hosted session. Phasing therefore delivers no
   partial value, and the estimate of 2-3 days / 1,500-2,500 LOC is low (ESTIMATED from the file
   count).
2. **The first-party alternative was never compared.** `ps` => `9780 ppid 1 … claude.exe daemon run
   --origin transient`, with children `10027`/`10130` `claude bg-pty-host`. The binary has:
   - `claude attach <id>`, `claude logs`, `claude stop`, and `detach (session keeps running)`;
   - `--bg` with `--resume <id>`;
   - `claude daemon install`, which installs the LaunchAgent `com.anthropic.claude-daemon`;
   - an auto-respawn nudge: "Continue from where you left off. Note: this session was automatically
     restarted after its process exited unexpectedly…";
   - `ringSnapshot`/`decModeSnapshot`, i.e. replay on reattach.

   The box already uses it: 16 `jobs/*/state.json` with `backend: daemon` across 4 config dirs (`ls -d ~/.claude*/jobs/*/state.json`). A
   caution comes with it: `~/.claude-next/daemon.log` => `bg retire 03a7cd27: idle-prompt, idle 8h`.
   C4 lists this as watch item H3. C1's claim that "variant (a) wins" was never tested against it.
3. **Finished hosts leak, invisibly.** `remain-on-exit on` keeps the server after the pane command
   exits (measured: `dead: 1 0`, and the session is still listed). Path (ii) also ends in
   `exec zsh -i`. `cc-reaper` never touches tmux (`:551`, `GARBAGE_WL` `:713`). Its `orphan-zsh` arm
   needs `parent==1` (`:918`, `:932`), but a pane's zsh is parented to the tmux server. Every ended
   session therefore leaves a server and a shell that nothing ever collects.
4. **Nothing in the design kills or detects a deaf kitty.** On 2026-10-01 kitty ignored SIGTERM and
   needed SIGKILL. C1's "relaunch kitty plus `cc-reattach`" has no detector and no kill step. Whether
   an agent may SIGKILL a kitty whose sessions would survive is a classifier question, UNMEASURED.
5. **A causal inference, UNMEASURED.** kitty reaps children in the I/O thread (`reap_children`, in
   `io_loop` on SIGCHLD). The 59 zombies therefore suggest that the I/O thread itself stalled. If so,
   every pane's reads stopped, and every claude was blocked writing. That would favor C1 more than the
   dossier argues.

**Recommended conviction (second pass): 45.** The mechanism is sound and replicated for (a) and (b). The
build is wider than counted, because it has to replace an identity oracle as well as an env variable.
The vendor's own detachable layer is unexamined, and it could make most of this build unnecessary.

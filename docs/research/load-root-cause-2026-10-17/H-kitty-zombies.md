# H-kitty-zombies: kitty zombies and terminal/browser CPU

Axis owner: worker for the 2026-10-17 load root-cause run. This was a read-only investigation. I killed nothing, signalled nothing, edited nothing except this file, and changed no settings. I made one `ps` table snapshot, one `top` sample, and ten `kitten @ ls` calls (one alone, then nine 0.5 s apart).

## Verdict (one paragraph)

The 221 zombies under kitty 44163 come from a known, upstream-fixed bug in kitty 0.48.2 (kovidgoyal/kitty#10436, fixed by f3fdc21850d7 on 2026-09-04 and shipped in v0.49.0). On macOS, closing the first window that used the graphics protocol sets the global signal write fd to -1. From then on, SIGCHLD, SIGUSR1, SIGTERM, SIGINT and SIGHUP are all dropped for the life of that kitty process. Window shells (`/usr/bin/login`) that exit are never `waitpid`-ed. **Zombies cost almost nothing in load.** They do not run, hold no fds or pages, and use 1.4% of `kern.maxproc`. The real cost is that this kitty cannot reload its config by signal or quit gracefully; only SIGKILL will stop it. The fix is already built and armed in this repo: the patched 0.48.2 bundle with the backported signal hunk at `/Applications/kitty.app.staged`, marker `~/.claude/autonomy/kitty-restart-pending` (2026-10-16 11:19). The swap is an operator step and takes effect at the next planned kitty restart or reboot. No userland workaround (setsid, double-fork, kitty config) can reap these: a window child must be kitty's direct child, and kitty no longer reaps anything. Hammerspoon (3.8% of one core on average) and WindowServer (7.9% of one core on average) are small. Hammerspoon has one change that keeps its output identical: drop the always-on 5 ms timer while nothing is pending. Together, this axis is about 1.3% of the machine's 10-core capacity and well under 0.1% of the load average.

## 1. Kitty zombies

### 1.1 Measurements

| What | Value | Command | M/E |
|---|---|---|---|
| kitty version | 0.48.2 | `/Applications/kitty.app/Contents/MacOS/kitty --version` | M |
| kitty 44163 age | started Thu 15 Oct 00:01:28, etime 02-02:37 (~50.6 h) | `ps -o pid,ppid,lstart,etime,stat,command -p 44163` | M |
| zombies, whole box | 226 | `ps -axo pid,ppid,stat,etime,comm \| awk '$3 ~ /Z/'` | M |
| zombies with ppid 44163 | 221 (other parents have 1 each: 88471, 51524, 37809, 1099, 1093) | same, grouped by ppid | M |
| live kitty children | 29 (13 zsh, 8 login, 6 bash, 2 kitten: `__atexit__`, `__watch_conf__`) | same, `$2==44163 && $3 !~ /Z/` | M |
| zombie identity (ucomm) | 206 `login` (uid 0), 6 zsh, 4 bash, 3 sleep, 1 Python, 1 kitty | `ps -axo pid,ppid,stat,lstart,ucomm,pgid,sess,tty,uid \| awk '$2==44163 && $3 ~ /Z/'` | M |
| zombie uid | 206 root, 15 uid 501 | same, column uid | M |
| first zombie | Thu 15 Oct 00:17:50, 16 min after kitty started | same, lstart | M |
| growth | 25 on 15 Oct, 192 on 16 Oct, 4 so far on 17 Oct. Bursty: 56 in 16 Oct 06h, 34 in 05h, 25 in 03h, 13 in 04h. Average about 4.4/h | same, bucketed by hour | M |
| previous kitty instances (repo record) | pid 610: 59 zombies at its 10-01 wedge. pid 48854: 187-189 on 10-04 | `bin/cc-kitty-reload:155-159`, `docs/research/concurrency-scale-2026-10-04/w1-audit-report.md:19`, `README.md:29` | M (prior run) |
| kitty panes now | 7 OS windows, 1 tab each, 27 windows, all in the active tab | one `kitten @ --to unix:/tmp/kitty-44163 ls` | M |
| process limits | kern.maxproc 16000, maxprocperuid 10666, num_tasks 16384. 1524 rows in the ps table | `sysctl kern.maxproc kern.maxprocperuid kern.num_tasks`, `wc -l` | M |
| kitty code signature | hardened runtime (`flags=0x10000(runtime)`), no get-task-allow | `codesign -dv`, `codesign -d --entitlements -` | M |

### 1.2 Mechanism: why kitty does not reap

- Reaping in kitty is entirely signal-driven. `reap_children()` loops `waitpid(-1, &status, WNOHANG)`, and its only call site is `if (ss.child_died) reap_children(...)` in `io_loop`, after `read_signals()` on the self-pipe. Source: kitty `child-monitor.c` (WebFetch of master; the v0.48.2 lines are cited in the issue below).
- Upstream issue **kovidgoyal/kitty#10436**, "Zombie (<defunct>) children accumulate on macOS: exited window shells are never reaped". It was filed on kitty 0.48.2, macOS 15.7.9, Apple Silicon, and matches this box exactly. It was closed COMPLETED on 2026-09-04 by commit **f3fdc21850d7a4d10966e9de6655ff53ede02314** ("Fix #10436"). Command: `gh issue view 10436 --repo kovidgoyal/kitty`, `gh api repos/kovidgoyal/kitty/commits/f3fdc218…`.
- The upstream changelog entry is verbatim: "macOS: Fix all signal handling being permanently disabled after the first window that used the graphics protocol is closed. This caused exited window shells to accumulate as zombie processes and also broke reloading the config with SIGUSR1 and quitting on SIGINT/SIGTERM/SIGHUP."
- The bug is in `kitty/loop-utils.c` `remove_signal_handlers()`. A loop that handles no signals unconditionally sets the global `signal_write_fd = -1`, and the main loop's handler then writes nowhere. It also had a `signal(ld->num_handled_signals, SIG_DFL)` typo. A second typo (`revents && POLLIN`) is in `child-monitor.c` io_loop. All three are fixed in f3fdc218.
- Fix availability: `gh api repos/kovidgoyal/kitty/compare/f3fdc218...v0.49.0` gives status `ahead`, ahead_by 98, behind_by 0. So v0.49.0, v0.49.1 and v0.49.2 (latest, 2026-10-01) all contain it. `brew info --cask kitty` shows `0.48.2 → 0.49.2` available.
- The onset fits the trigger. The first zombie appeared 16 min after kitty started. This fleet uses graphics-protocol overlays (`config/kitty.conf:655` launches `scripts/kitty-pane-title-overlay.py`), so the trigger fires early in every kitty's life. That the overlay is the specific trigger is ESTIMATED from the changelog wording; it was not instrumented.
- Which processes become zombies:
  - `login`: every kitty window's root on macOS. These 206 are closed panes from cc-pane-runner/it2-kitty (`bin/it2-kitty:1178` `launch --type=window`), cc-resume-layout (`bin/cc-resume-layout.sh:945-946,1182,1406`), cc-offload and cmd+w.
  - `sleep`: the 3 zombies match cc-relayout's `/bin/sleep 600` placeholder tabs/os-windows (`bin/cc-relayout:363,366`).
  - `zsh`/`bash`: windows launched with an explicit command.
  - `--type=background` children (kitty-confirm-close, kitty-pane-menu, kitty-fullscreen-guard, `config/kitty.conf:241-291,903-914`) left only 1 `Python` zombie, although cmd+w runs one on every close. That suggests they are reaped another way, most plausibly by CPython's `subprocess._cleanup()` on the next `Popen`. ESTIMATED; I did not verify this in kitty's frozen Python.
- The repo already knows the cause. Its record shows "signal path had stalled — 59 unreaped zombie children, i.e. SIGCHLD unhandled too — so every SIGUSR1 … was silently dropped" (`bin/cc-kitty-reload:155-159`), and that tool now reloads through `kitty @ load-config` first (`bin/cc-kitty-reload:162-166`). See also `docs/plans/kitty-deadlock-recovery-2026-10-01.md:94`: "Upstream fixed the signal half in v0.49.0".

### 1.3 Harm of the zombies (honest sizing)

- **CPU/load: zero.** A zombie is not runnable, so it never enters the run queue or the load average. Its mach task has already been torn down. It keeps only its proc struct and exit status, and holds no fds; the 10-04 audit measured "203 zombies (187 under kitty, no fds)" (`docs/research/concurrency-scale-2026-10-04/i-redteam-cpu.md:21`). That the task is gone and the slot holds no num_tasks entry is ESTIMATED from the XNU exit design.
- **Proc-table slots: 221 of 16000 (1.4%).** On the per-uid limit, 206 are root's `login` and root is exempt from maxprocperuid, so only 15 count against uid 501's 10666 (0.14%). MEASURED via uid column + sysctl.
- **ps / process walks: about 15% more rows (221 of 1524)** in every full-table scan by the fleet's ps-walkers. Each zombie row is cheap: no args or task info to fetch, about 648 bytes of kinfo_proc each, about 143 KB more per `KERN_PROC_ALL`. The extra size is ESTIMATED from sizeof(kinfo_proc); the impact is negligible.
- **The real harm is that the dead signal path breaks things.**
  - SIGUSR1 config reload is lost, including the `kitten __watch_conf__` auto-reload. cc-kitty-reload works around this.
  - SIGTERM, SIGINT and SIGHUP do nothing, so this kitty can only be SIGKILLed, and all 27 panes end abruptly.
  - The same 0.48.2 instance class carries the talk-thread accept() death that wedged kitty 610 on 10-01 and killed 31-32 sessions (`docs/research/concurrency-scale-2026-10-04/c-outcome-ledger.md:70`). That is a separate bug in the same build, also fixed by the staged bundle (`docs/patches/kitty-talk-thread-survives-v0.48.2.patch:1-20`).

### 1.4 Fix options

| Option | Verdict | Why |
|---|---|---|
| **Swap to the staged patched bundle at the next planned kitty restart** (`scripts/kitty-build-swap.sh:22-35`; bundle `/Applications/kitty.app.staged` dated Oct 16 11:19; marker `~/.claude/autonomy/kitty-restart-pending`) | **CHOSEN (P0, operator)** | It carries upstream's `loop-utils.c` hunk verbatim (`docs/patches/kitty-talk-thread-survives-v0.48.2.patch:15-18`), the talk-thread accept fix, and the fullscreen/backport patches (`scripts/kitty-build-swap.sh:7-20`). The operator already chose this build (decision 0a8ffe58562a, per `scripts/kitty-build-swap.sh:14`). The swap is renames only and takes effect at the next kitty start; `alarm-reboot-prep.sh` prints the marker at the next capacity-alarm reboot. So adoption already rides an existing event (reboot) and needs no extra downtime. |
| Stock cask 0.49.2 | Fallback | Fixes signals, but not the talk-thread death, which upstream had not fixed as of the 10-04 audit (`w1-audit-report.md:143`). Worth checking 0.49.x for the accept fix before choosing it. |
| `setsid` / double-fork / `--type=background` alternatives | REJECTED | A double fork still leaves the first child as kitty's unreaped zombie, because kitty reaps nothing. A window's root must be kitty's direct child, since it owns the pty. No launch shape avoids it. |
| kitty.conf change (e.g. `close_on_child_death yes`, `config/kitty.conf:1028`) | REJECTED | It changes when windows close, not whether children are reaped; `mark_child_for_removal` still needs SIGCHLD to arrive. |
| Avoiding the graphics protocol so the trigger never fires | REJECTED | It would remove the operator's ⌘⇧B overlay (`config/kitty.conf:655`). It is fragile (any `icat` or image in any pane re-arms the bug), and the fix already exists. |
| Attaching lldb to kitty to call `waitpid(-1)` | REJECTED | The kitty bundle uses the hardened runtime and has no get-task-allow (MEASURED, codesign), so attach fails with SIP on. It would also pause every pane. |
| Zombie-count alerting | REJECTED (also rejected by the repo) | It fires nonstop on any stock 0.48.2 (`w1-audit-report.md:175`). The useful detector after the swap is a timed `kitten @ ls` plus Recv-Q (`w1-audit-report.md:141`). After the swap, a non-zero zombie count under kitty becomes a valid regression check. |
| Upstream bug report | NOT NEEDED | #10436 is already fixed upstream. |

### 1.5 Event-driven framing

The fix needs no recurring process. The swap rides the next reboot the operator already makes, and the existing marker tells them about it. After the swap, reaping goes back to being event-driven inside kitty (SIGCHLD → waitpid), and nothing in claude-infrastructure needs to poll for zombies.

## 2. Hammerspoon (903 CPU-minutes over 16.5 days)

### 2.1 Measurements

- Average: Hammerspoon pid 1073, TIME 903:22 over etime 16-11:09:15 = 903.4 / 23709 min = **3.81% of one core**. MEASURED: `ps -axo pid,ppid,pcpu,pmem,rss,time,etime,comm`.
- Now: 7.2% pcpu (ps), and 4.0% with 79 idle wakeups in the 2 s `top -l 2 -s 2 -stats pid,command,cpu,idlew,power,threads` sample. MEASURED.

### 2.2 What runs (config at `/Users/chrisren/Development/hammerspoon-config`, loaded by `~/.hammerspoon/init.lua:39-43`)

- **screenshot: a permanent 5 ms timer (200 Hz).** `hsc/screenshot/init.lua:30` sets `pollS = 0.005` and `:32` sets `dirEvery = 2`. At `:385-398`, `hs.timer.new(cfg.pollS, …)` runs `settleTick()` on every tick and `state.w:tick()` (a directory `stat`) on every second tick, so the stat runs every 10 ms. `Watcher:tick` (`hsc/screenshot/watcher.lua:176-218`) also runs an unconditional listing every 1 s (2.4 ms each, `watcher.lua:24-29`). There is also a 60 s prune timer at `init.lua:400`. `settleTick()` (`init.lua:247-…`) only iterates `state.pending`, so when no screenshot is in flight, 100 of the 200 wakeups per second do nothing. The poll is a deliberate choice over FSEvents, after fseventsd livelocked on 2026-09-07/08 and a kqueue helper was benchmarked and rejected (`watcher.lua:3-11`). I do not reopen that decision.
- **dock:** `hs.pathwatcher` on `~/Library/Preferences` (`hsc/dock.lua:22,102-114`) filters for `com.apple.dock.plist`, with a 0.5 s debounce, plus an `hs.application.watcher` (`dock.lua:118-123`). Both are event-driven, so I find nothing material there. The pathwatcher adds one FSEvents client on a busy directory, which is small next to fseventsd's 125% (an fseventsd-axis concern, not this one).
- **smartpaste:** a keyDown `hs.eventtap` (`hsc/smartpaste.lua:31-47`) returns immediately unless the key is ⌘V. One Lua call per keystroke: negligible.

### 2.3 Fix (gives the same result)

H1 below runs the 5 ms tick only while `state.pending` is non-empty. The timer stays at 10 ms and stats the directory on every tick. When `onCandidate` opens a handle, a second 5 ms settle timer starts; it stops itself when `pending` drains. Detection stays at 10 ms (the C1-benchmarked interval, `init.lua:376-383`). Settle stays at 5 ms while a shot is pending, so screenshot latency is unchanged. Idle timer wakeups drop from 200/s to 100/s. ESTIMATED effect: Hammerspoon goes from about 3.8% to about 2% of one core, if per-wakeup Lua dispatch dominates, which is not measured. That saves about 0.2% of the 10-core machine. P2.

Rejected: lengthening the 10 ms detection poll, or arming only on the ⌘⇧3/4/5 hotkeys. Either one adds latency for shots taken by other routes, which would limit work.

## 3. WindowServer and kitty rendering

### 3.1 Measurements

- WindowServer pid 383: TIME 1883:06 over 16-11:10:18 = **7.94% of one core on average**. Now 12.8% (ps) and 4.9% (top sample, 38 idle wakeups / 2 s). MEASURED with the same commands as above. The lead's 57% figure was a peak I did not see.
- kitty 44163: TIME 46:28 over 2-02:37:46 = **1.53% of one core on average**; 4.6% now. MEASURED.
- **Title animation was checked and ruled out.** I sampled pane titles 9 times at 0.5 s intervals over 5.1 s with `kitten @ … ls` in a bounded python loop. 6 busy panes (titles prefixed ◐/◑) showed **0 glyph changes**. The busy glyph is a static state marker, not an animation, so kitty title-bar and NSWindow title redraws are not a WindowServer driver. MEASURED.
- kitty does not render hidden OS windows. In v0.48.2 `glfw.c:2568-2580`, `should_os_window_be_rendered()` requires `is_os_window_potentially_visible()`, which is false when the window is ICONIFIED, not VISIBLE, or OCCLUDED. MEASURED via `gh api repos/kovidgoyal/kitty/contents/kitty/glfw.c?ref=v0.48.2`. kitty also caps its render rate by `repaint_delay`: `config/kitty.conf:987` sets 16 ms (default 10), and `input_delay` is 5. So the 7 OS windows and 27 panes can only cost WindowServer when they are on screen and changing.
- The remaining in-pane source is the Claude Code TUI spinner/shimmer in busy sessions (`caffeinate` foreground marks the busy ones; 10 of 27 panes in the ls sample). Claude Code 2.1.291 has a "Reduce motion" config ("Added reduced motion mode to the config", `~/.claude/cache/changelog.md:6977`; later fixes at `:518` and `:4395`). It is not set in `~/.claude/settings.json` (grep for `motion` found nothing). Its share of WindowServer CPU is UNMEASURED.

### 3.2 Fix

H3 below enables reduce-motion, with a one-session A/B first. It removes continuous spinner and shimmer frames in busy panes while keeping the same text and status. It is a display preference, not a work limit. The current settings key name could not be confirmed from the changelog, so confirm it through `/config` first. Conviction is low because the effect is unmeasured.

Rejected: raising `repaint_delay` or `input_delay`, turning off `sync_to_monitor`, or hiding panes. Each one makes the terminal slower to respond or hides work, which violates the constraint, and kitty already skips occluded windows.

## 4. Dia renderers at 100-111% for 2.5 h

- Now: no Dia renderer burns. Pid 35519 shows 3.2% and is 2 min old. Every surviving renderer's TIME is ≤ 2:17, so none of them ran 150 CPU-minutes. The two burners have exited (tab closed or discarded). MEASURED: same `ps` snapshot.
- Sessions do drive Dia. `bin/cc-url-open` (kitty `open_url_with`, `config/kitty.conf:1085`) opens claude.ai and artifact links in the matching Dia Space, and `bin/cc-relogin:680-687` and `bin/dia-cdp-launch.sh:345` drive it too. So an agent-opened page, such as an animated artifact or a dev page reconnecting in a loop, is a plausible source. ESTIMATED.
- **Could not determine** which page burned, because the processes were gone before this run. That WindowServer's 57% peak was compositing that page is plausible, since both were observed in the same window, but UNMEASURED. Open question; recipe under H4.

## 5. Share of load (this axis)

- Zombies: 0% of CPU and run queue (they are not runnable). 1.4% of maxproc slots.
- Hammerspoon + WindowServer + kitty: 3.81 + 7.94 + 1.53 = **13.3% of one core on average**, i.e. **about 1.3% of 10-core capacity** and about 0.13 of a run-queue entry against a load of 84-520. MEASURED (ps TIME/etime).
- Conclusion: this axis does not drive the load of 400-500. Its value is reliability (the kitty swap) plus small streamlining wins.

## 6. Recommendations (ranked)

- **H0 (P0, operator): adopt the staged patched kitty at the next planned restart/reboot.** Run `bash ~/.claude/scripts/kitty-build-swap.sh swap --confirm /Applications/kitty.app` as the last step before reboot, then `verify --clear-marker` after login, exactly as the marker says. Fallback: cask 0.49.2.
  - Verify: after kitty starts, `ps -axo ppid,stat | awk -v k=$(pgrep -x kitty | head -1) '$1==k && $2 ~ /Z/' | wc -l` stays at 0 after closing panes. `kill -USR1 <kitty>` applies a config edit.
  - Risk: the restart ends all panes, so do it only at a reboot the operator is already making. Rollback: `scripts/kitty-build-swap.sh rollback`.
- **H1 (P2): Hammerspoon idle tick at 10 ms, 5 ms only while a shot is pending.** Files: `hammerspoon-config/hsc/screenshot/init.lua:30-32,385-398` and the `onCandidate`/`release` sites.
  - Verify: `top -l 30 -s 2 -stats pid,command,cpu,idlew` for Hammerspoon before and after. Then run the repo's bench (`hammerspoon-config/bench`) for the p50/p99 detection and settle latencies; they must match C1.
- **H3 (P2): Claude Code reduce-motion, A/B in one pane first.** Verify: kitty + WindowServer CPU via `top -l 30 -s 2` with 10 busy panes, setting off vs on.
- **H4 (P2, diagnostic only): when a Dia renderer next goes above 90% for 5 min or more, record its tab URL** (`osascript -e 'tell application "Dia" to get URL of every tab of every window'`), its pid and its etime. Then fix the page or the tool that opened it.

## 7. Sources

- https://github.com/kovidgoyal/kitty/issues/10436
- https://github.com/kovidgoyal/kitty/commit/f3fdc21850d7a4d10966e9de6655ff53ede02314
- https://raw.githubusercontent.com/kovidgoyal/kitty/master/kitty/child-monitor.c
- kitty v0.48.2 `kitty/glfw.c:2568-2580` (via gh api)
- kitty releases list (gh release list): v0.49.0 2026-09-21, v0.49.2 2026-10-01
- Related, other terminal: Ghostty #2273 (zombies from a login wrapper with killpg EPERM). This is a different mechanism; kitty's reaper uses waitpid(-1) and does not depend on killpg.

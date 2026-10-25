# RCA (final): the 2026-10-25 /dev wedge, kitty freeze and terminal lockup

- **Box:** MacBookPro18,2 (M1 Max, 10 cores, 64 GB). **macOS 15.8.1 (24H32)**, not 15.7.x (`zsh-sample.txt:13`, stall header). The previous boot (DBDBC472) ran from 10-21 14:06 to the manual restart at 13:13:47 on 10-25.
- **Times:** local CDT (UTC-5). Transcript and log rows in Z are converted.
- **Inputs:** `rca/RCA-draft.md` (15:06), the 8 lane notes in `rca/`, and three adversarial verdicts (kernel mechanism, order of events, workload). Appendix A records how each refuted claim was resolved. Appendix B lists the checks run for this final version.
- **Labels:**
  - **Confirmed** means observed directly, or read from source and matched to an observed stack.
  - **Likely** means several independent observations agree but one link is inferred.
  - **Speculative** means consistent with the evidence but untested.
- **Kernel-source caveat:** kernel source was read at `xnu-11417.140.69`, the newest *published* 15.x drop. The running kernel (`xnu-11417.140.69.712.69~1`) is an unpublished security build on that train, and no KDK exists for it. Here "Confirmed from source" means confirmed against the nearest published base and consistent with the stack shapes and offsets in both spindumps. The current macOS 26 tag, `xnu-12377.121.6`, has the same TIOCREVOKE, ptsopen and drainok code, so **no OS update removes this hazard**.

---

## 1. Summary

**Root cause (Likely, high confidence; every link observed or read from source, but not reproduced).** A kernel pty deadlock, built from our own fleet code, wedged `/dev`.

**How the deadlock formed:**
- A bash subshell (pid 96296) had inherited "ignore HUP/TERM/INT" from our held pane runner.
- It was blocked inside `open("/dev/ttys063")`, part of the painter's `stty size < "$TTYP"`.
- The master side of that pty had already been closed by a bats pty-test driver. The driver ran out of its 10 s budget and exited without killing its child.
- An open with no carrier sleeps in `ptsopen`'s carrier loop. That sleep holds the device's devsw lock and an iocount on the vnode.

**The trigger.** At **03:48:58** a teammate agent ran `kill -KILL 94459 68298`. That kills by pid, not by session or group, and 68298 was the session leader of ttys063.

**What the leader's exit did:**
- It revoked its controlling tty: `VL_TERMINATE` was set, then `vnode_drain` waited with no timeout for 96296's iocount.
- The TIOCREVOKE that the revoke sends wakes only readers. It does not wake carrier sleepers.
- ttys063 therefore stayed half-reclaimed for good.

**Effect on `/dev`:**
- Every `/dev` lookup of that node now slept on `vnode getiocount`.
- `devname_r` lstats `/dev` entries in readdir order, and every pty created after 03:03:31 sorts after ttys063. So every lookup of a newer tty walked into the wedged node: `ttyname`, `login`, zsh `init_io`, `ps` with a TT column, multi-pid `ps -p a,b` without `-x`, and `ls /dev`.
- The sleep can be interrupted. But callers that never receive a signal, and runtimes whose handlers use `SA_RESTART` (kitty; very likely claude.exe), stay blocked indefinitely.
- The wedge lasted 9.5 h and outlived the load: load1 fell from about 900 to about 20 while `/dev` stayed blocked.

**Why it took 9.5 h and a reboot:**
1. **Overload let a harmless fixture become the precondition (Confirmed; Likely necessary).**
   - The box ran at 65–100 load/core for about 12.8 h.
   - The held runner took **25 s** to start its painter, against the driver's 10 s budget.
   - Every governor did refuse at some point. Each was defeated by its own design:
     - the Agent gate released itself after 3 refusals;
     - 362 bats waivers in 26 h, because the refusal text prints the waiver line;
     - the verifier exports `CC_BATS_MAX_ROOTS=0`;
     - the load term is off by design.
2. **Detection was blind (Confirmed).**
   - The instruments built for this machine ran on the same `devname` path and went dark at the onset. capacity-alarm's tick was inside its own multi-pid `ps`, started 22 s before the kill, and never wrote another row; attrib, convoy and the heartbeat roster went dark too.
   - The consumers that noticed abstained quietly.
   - Pages had no human reader: no desk role since 09-09, 3,609 UNDELIVERED.
3. **kitty froze as a victim (Likely).**
   - kitty's `spawn()` calls `ttyname_r(slave)` on its main thread. The first spawn after the wedge froze the main thread between `openpty` and `fork`, leaving master fd 17 = 15,4 with 0 bytes and no child.
   - The remote-control peer table then filled to PEER_LIMIT 256.
   - kitty's SIGTERM handler is installed with SA_RESTART, so kitty "ignored" SIGTERM.
4. **A reboot was probably avoidable, but nothing we had could find the opener.**
   - A SIGKILL to 96296 would very likely have released the drain (PCATCH sleep; from source; not tested).
   - macOS `ps` shows no wait channel. `ps -o wchan` prints `-` even for an msleep sleeper (tested).
   - Once the leader is inside its revoke, its session members' `tdev` reads NODEV (`kern_exit.c:2321` before `:2336`; `kern_sysctl.c:1050-1055`).
   - So the opener can be found only through the process tree (ppid walk, getsid, pgid) or a stackshot.

**Still live at 15:55 today.**
- The blocking open is still at `bin/cc-pane-verdict:135`, and the inherited ignore is still at `bin/cc-pane-runner:292`. Both are unchanged on origin/main `77cd84ff2`.
- The test driver still kills by pid (`tests/cc-pane-runner-hold.bats:268-273`).
- capacity-alarm's multi-pid `ps` is still there (`scripts/capacity-alarm.sh:865`).
- The box is back in the overload regime: load 270–287 (27–29/core), 48% sys, 0% idle, 1,625 processes, 38 claude processes, 25 `cc-pane-runner` processes.
- The dispatcher fired at **27.16/core** on "headroom ADMIT".

**What changed from the draft:**
- **Walkers are interruptible.** "Forever" holds only for callers that get no signal or use SA_RESTART. The kill call's own `ps` was killed at 08:25:37.
- **capacity-alarm went dark in `read_argv0`.** Its multi-pid `ps -p` without `-x` (`:863-872`) hung, not the pty-gauge stat loop. `ps` 35442 is capacity-alarm's.
- **Kill-by-pgid is not a general remedy.**
  - Openers can sit in other process groups or other sessions.
  - Members' tdev is cleared during the revoke.
  - An `O_NONBLOCK` open, or any close of the wedged tty, can block THREAD_UNINT behind the opener's devsw lock.
- **The PEER_LIMIT onset is unknown.** It lies between 04:15:04 and 06:08:38. 06:11:40 was a log-retention edge.
- **Overload is promoted to cause #2.** "No concurrency ceiling would have prevented it" is withdrawn: a binding gate would very likely have prevented *this* incident, though not the class.
- **The clocks were re-anchored**, and the draft's ps-derived times stand. The verdict's 12–15 s correction is **rejected** (A-O5). The draft's 03:40-spindump-derived times were 15 s early: the opener blocked at 03:03:58, not 03:03:43.

---

## 2. Timeline (CDT)

**Clock anchors:**
- `hb.kitty-start` = 1792612498 = 10-21 14:54:58 (kernel start time). Adding kitty's etime of 3-22:16:35 dates the ps snapshot to **13:11:33**, which equals the file's birth time.
- Stall Time-Since-Fork minus ps etime is 228 s for 209 of 212 shared pids. That puts the stall reference at 13:15:21, its own Date/Time.
- The 03:40 spindump's fork ages are measured from **03:41:04**: the sampling start, which is Date/Time 03:40:49 plus "unresponsive for 15 seconds before sampling". From that reference kitty's fork age gives exactly 14:54:58.

| Time | Event | Source | Label |
|---|---|---|---|
| 10-21 14:01:55 | Shutdown stall on 15.7.9: the previous reboot, most likely the OS update | shutdown_stall_2026-10-21 | Likely |
| 10-21 14:06:27 | Boot DBDBC472 on 15.8.1 (24H32) | stall Time Since Boot 342,534 s | Confirmed |
| 10-21 14:54:58 | kitty 1881 starts (stock 0.48.2); unreaped zombies accumulate from 15:07 (297 by 13:11) | hb.kitty-start; ps | Confirmed |
| 10-21 16:03 → | capacity-alarm ALARM/WARN almost continuously; pages undelivered (no desk role since 09-09) | capacity-alarm.jsonl; autonomy-sweep.err.log | Confirmed |
| 10-22 ~04:00 → 11:30 | kitty-1881 deaf episode with no /dev wedge (EOF within 1 s, 258 peerless unix sockets, load 200–450); recovered by itself | kitty-deaf-episode-2026-10-22/REPORT.md:11-15; lr-recon has no tty= timeouts that day | Confirmed |
| 10-24 15:00 → 03:48 | Host 99–100% busy with 42–54% sys for about 12.8 h; sessions 29→50; coalition passes 700 at 15:58 | attrib.jsonl; capacity-alarm | Confirmed |
| 10-24 22:44–22:56 | `ps … args=` timeouts and "16 killed children not yet reaped"; cleared by itself | recon/events.jsonl | Confirmed (cause: Likely load-class proc-table contention, §4) |
| 10-25 00:00–01:00 | load1 about 950–1,024; 7–8 concurrent bats runs | load.jsonl; qos-census | Confirmed |
| 01:05 → 11:37 | postland-verify runs the full corpus of about 22.6k tests three times with `CC_BATS_MAX_ROOTS=0` exported | runner.log; postland-verify.sh:231 | Confirmed |
| 02:18 / 03:17 | Dispatcher fires at 62.3 and 88.6 load/core ("headroom ADMIT"; load term off by design) | dispatch-fires.log; capacity-admit.sh:158-169 | Confirmed |
| 02:20:20 | Last kalloc measurement: 1.588 GiB (8% of ceiling). Not measured afterwards | kalloc-zone-series.tsv | Confirmed |
| 02:34:27 | Agent gate admits lead 9ddc8ad3's teammate spawn (t1-runner) on `budget-expired`: "13 sessions mid-turn + 1 > active ceiling 8" | autonomy/idl.jsonl (07:34:27Z) | Confirmed |
| **03:02:08** | t1-runner (cc5a6d48) runs `bats -f 'A1t pty'`, pid 92243, waiver "slot holders 1-3h old, load ~650", `CC_BATS_MAX_ROOTS=0` (20 waivers in this hour across 7 cwds) | bats-waivers.jsonl | Confirmed |
| **03:03:31** | python driver `pty.fork()` → held runner bash 68298, session leader of `/dev/ttys063` | ps etime 10:08:02 | Confirmed |
| ~03:03:41 (or ~03:03:52) | Driver's 10 s wait ends ("never held", or "still held 10 s after release" at fork+21 s); `sys.exit` without killing the child closes the master; 68298 ignores SIGHUP | test source `f5704886b:tests/cc-pane-runner-hold.bats:239-283`; minor 63 unheld at 13:11 | Likely (exit message never captured) |
| **03:03:56** | Runner reaches its hold and starts painter 94459, **25 s after fork** | ps etime 10:07:37 | Confirmed |
| **03:03:58** | bash 96296 (`stty size < /dev/ttys063` subshell, sibling awk 96310) blocks in ptsopen's carrier wait | both spindumps; ps | Confirmed |
| 03:30–03:45 | Swap 1.8→6.3 GB, seg 37%, load 952–987, 45–50 sessions, coalition 964–1,071 | capacity-alarm | Confirmed |
| 03:37:17 | Last kitty *window* process starts (zsh 11504) | ps | Confirmed |
| 03:41:04–03:41:14 | Full-system spindump: kitty healthy, no devfs or revoke sleepers; 20 `ps` asleep in `__sysctl`/kern_proc (up to 89 s old); two priority-4 `ps` (27556, 29195) runnable but starved in user space for 57 min; 3,729 processes and 11,880 threads; kernel_task 85% in VM compressor/swap. These are load-class stalls, a separate class from the later wedge | Discord_…063329.hang; tools/hang0340-signatures.txt:37 | Confirmed |
| 03:41:00 / 03:41:31 → | lr-recon `ps args=` timeout; self-close calls run past 120 s (load-class stalls, before the trigger) | recon events; transcripts | Confirmed |
| 03:45:19 | Last capacity-alarm row | capacity-alarm.jsonl | Confirmed |
| 03:45:32 | Last good `hb.kitty-ls.json` (49 windows) | mtime | Confirmed |
| 03:47:21–23 | Last *logged* RC success (kitty-confirm-close wid 339) | kitty-pane-actions.jsonl | Confirmed |
| 03:47:43 | capacity-alarm tick starts (launchd `/bin/bash` 97955, PPID 1) | ps; com.claude.capacity-alarm.plist | Confirmed |
| 03:47:54 | Held-runner change committed (f5704886b; on main as f1cb86dd2) | git | Confirmed |
| 03:48:20 | That tick writes the last attrib row (busy 100%, sys 51%) | attrib.jsonl | Confirmed |
| 03:48:20–29 | t1-runner's `ps -axo` shows 68298 as `Ss+` with readable args: alive, not exiting | t1-runner tool result 08:48:29Z | Confirmed |
| 03:48:33–34 | Three kitty children in **pgid 1881** (not window children) start and become zombies | ps | Confirmed |
| 03:48:36 | capacity-alarm `read_argv0` pipeline `ps -o pid=,command= -p <list> \| cut \| awk` (35441/35442/35444/35447) starts; it never exits | ps; capacity-alarm.sh:863-872, :956 | Confirmed |
| **03:48:58** | **TRIGGER: `kill -KILL 94459 68298; /bin/sleep 1; ps -o pid,stat -p 68298,94459` (tool call issued). 68298's exit revokes ttys063; the drain waits on 96296 for good** | transcript; 13:15 stall | Confirmed act; Likely effect |
| ~03:49:00 | The kill call's own multi-pid `ps` (no `-x`) starts. It is the **earliest known devname sleeper**: it hits 120 s at 03:51:03 and is killed at 08:25:37 | transcript; adv_cmds ps.c:681-690 | Likely (stack not captured) |
| 03:49:31, 03:49:56, 03:52:16.9 | kitty main thread (0x3ce2) still logs | log-b-kitty | Confirmed |
| ~03:49:01 → 03:50:22 | lr-recon's first `ps pid=,tty=` try begins (two 40 s tries); first logged timeout at 03:50:22; 478 in a row to 13:15:04 | recon/events.jsonl | Confirmed |
| 03:50:20 | `ps` 88107 starts: the first sleeper whose stack was captured | stall; ps | Confirmed |
| 03:52:10–03:54:07 | User active in kitty (Focal 03:52:10 and 03:53:45, NonFocal 03:54:07) | runningboardd | Confirmed |
| 03:52:17–03:57:51 | kitty main thread stops; master fd 17 (15,4) is opened, carries 0 bytes and never gets a child. Fits `spawn()` → `ttyname_r` → lstat past ttys063 | ptmx-holders.txt:2; child.c:73 | Likely |
| 03:57:16 | Drainer logs "kitty unresponsive" (×1,247; never escalated) | pane-close-retry.log | Confirmed |
| 03:57:51 | First RC failure: `kitty @ get-text` read i/o timeout | bash-commands.log | Confirmed |
| 04:00:41 | Heartbeat census turns "carried"; roster frozen | census.log | Confirmed |
| 04:14:26–04:15:04 | RC sockets still "accepted … did not answer within 10s", so the peer table is not yet full | transcript 3d1dc252 | Confirmed |
| 04:18:59 | t1-runner diagnoses its own failure mode, "never held … startup under load ~700"; the arm holds once the wait is 30 s | /tmp/rca-tf/t1-runner.txt:348 | Confirmed |
| 04:15:04–06:08:38 | **PEER_LIMIT 256 reached** (exact time lost to log retention) | client logs | Confirmed bracket |
| 05:15 / 07:16 | Compressor-sentinel trips: 121 SIGSTOP and 14 SIGKILL overnight, never kitty or claude | sentinel log | Confirmed |
| 06:08:38 | First client-side `write: broken pipe` | transcript 9ddc8ad3 | Confirmed |
| 06:11:40.114 | Earliest *surviving* "Too many peers" line (14:02 extract). The 14:12 extract starts at 06:19:26, a 15:25 query at 07:10:59 | kitty-raw/log-1881-oct25.txt; log-b-kitty.txt | Confirmed (retention edge, not onset) |
| 06:59:51 | `tty` in a kitty login shell hangs | ps | Confirmed |
| 07:25 | Session 2b3becea measures `ps -o … -p a,b` hanging even with dead pids; one pid or `-x` returns at once | docs/lessons/multi-pid-ps-without-x-hangs.md | Confirmed |
| 08:25:37 | t1-runner's background tasks (including the 03:48:58 kill call's `ps`) are killed at teammate shutdown, so the walkers were killable | transcripts-fleet.md:143 | Confirmed |
| 08:41 → 13:09 | Heartbeat census "ok" but kitty-1881 roster `[]`; `cc-sessions --json` "failed or did not parse within 75s" | census.log; boot-resume.stderr.log | Confirmed (cause: Likely cc-sessions' multi-pid `ps`, fixed 67b84f5e1) |
| 09:00–10:00 | load1 falls to about 25–95; **the wedge persists** | qos-census | Confirmed |
| 09:30 → 13:15 | Exec churn 60–290/s; orphaned `jetsam-lane.sh` forks 4–5/s; lldb launched 9–23/min | unified log | Confirmed |
| 11:00:35 | Backlog files "kitty RC deaf since about 10:15", 6.5 h late | backlog ac9769f69e52 | Confirmed |
| 12:05:45 → 13:14:55 | `/goal` runaway in 2b3becea: about 640 polls of 8 × `kitten @ ls`; refusals 60–100/min | transcript; kitty log | Confirmed |
| 12:21:52 → 12:58:07 | 17 `login` processes (new Terminal/iTerm2 windows) asleep in ttyname → lstat | stall | Confirmed |
| 12:28:55 | Claude desktop helper opens pty 15,71; 0 bytes transferred | lsof | Confirmed |
| 13:02:26 | Compressor-sentinel TRIP page (17.03%, swap 7.95 GB) | pages | Confirmed |
| 13:05:43–46 | User's `zsh -fc 'echo ok'`: 1,715/1,715 samples in devname_r → lstat | zsh-sample.txt | Confirmed |
| 13:11:33 | ps-prereboot and `lsof /dev/ptmx` captured: 2,116 processes, 312 zombies, 65 uid-501 master fds; minors 62 and 63 unheld | files (birth time) | Confirmed |
| 13:13:47 | User requests Restart | loginwindow | Confirmed |
| 13:14:55–59.8 | kitty Force Quit: SIGTERM ignored (SA_RESTART handler), SIGKILL works. All masters close; three expect panes `exec` a fresh zsh whose `init_io` open enters the carrier wait; their window shells stick in `spec_close` behind the devsw lock (THREAD_UNINT) | Dock; launchd; stall :54332/:54474/:54564 | Confirmed / Likely |
| 13:15:21 | Shutdown-stall spindump: 68298 in vn_revoke (1 revoke frame, 1 drain leaf); 96296 in pty open; 40 getiocount leaves (23 `ps`, 17 `login`); 94459 in fixjobc → proc_parent | shutdown_stall_2026-10-25 | Confirmed |
| 13:16:52 | Boot 47645ED5 | kern.boottime | Confirmed |
| 13:21:21 / 13:31:06 | boot-resume abstains on an empty roster; worktree-gc removes 49 worktrees, including those of interrupted sessions | idl.jsonl:84574; worktree-gc-infra.log | Confirmed |
| 14:35 | `cc-sessions` and `convoy-gauge` get `-x` on multi-pid `ps` (67b84f5e1). capacity-alarm and handoff-fire do not | git | Confirmed |
| 15:55 | Load 27–29/core, 48% sys, 0% idle; dispatcher fires at 27.16/core; hazard lines unchanged on origin/main 77cd84ff2 | uptime; top; dispatch-fires.log; git show | Confirmed |

---

## 3. Ranked causes with evidence

| # | Cause | Confidence | Mechanism in one line |
|---|---|---|---|
| 1 | **A pty-lifecycle deadlock built from our own pieces:** (a) a test driver that closes the master and leaves a held runner alive; (b) a held runner whose children inherit SIG_IGN for HUP/TERM/INT; (c) a painter that block-opens the pane tty by path; (d) a session leader SIGKILLed by pid while a member sleeps in the open | **Likely** (high). Every link is observed or read from source; the 40 sleepers are tied to ttys063 by the single-reclaimer argument; not reproduced | A carrier-wait open holds the devsw lock and an iocount. The leader's exit revoke sets VL_TERMINATE and drains with no timeout. TIOCREVOKE does not wake carrier sleepers. Every lookup of the node sleeps on `vnode getiocount` |
| 2 | **Sustained overload kept in place by an admission stack built to release itself** | **Confirmed** that the governors were defeated; **Likely** that the overload was necessary for this instance | 25 s start-up against a 10 s fixed budget made the driver exit while the runner was still alive. The same load slowed every probe past its cadence |
| 3 | **Detection and paging blind to this class**, with the instruments themselves on the devname path | **Confirmed** | Producers hung on their first walk past the node. Consumers abstained locally. Nothing reached a human, and the onset was misdated by 6.5 h |
| 4 | **kitty puts its main thread on `/dev`** and has no RC back-pressure. It also has a second, load-only deafness mode | **Likely** (source Confirmed; stack unobserved) | The first spawn after the wedge slept in `ttyname_r`. RC peers accumulated to PEER_LIMIT 256 and every client got EOF or broken pipe |
| 5 | **Amplifiers after the wedge** | **Confirmed** | 31 never-exiting `ps` pipelines, RC retry storms (the `/goal` runaway), the jetsam-lane orphan and exec churn added load and noise. None is causal |
| 6 | **Recovery failure after the reboot** | **Confirmed** (the empty roster is Likely the same multi-pid `ps` hang) | boot-resume trusted an empty heartbeat roster; worktree-gc removed the worktrees of interrupted sessions |

### 3.1 Cause 1: the causal chain, link by link

1. **Design precondition (Confirmed).**
   - `bin/cc-pane-runner:292`: `_guarded() { trap '' INT QUIT TSTP TERM HUP; … }`. SIG_IGN survives fork and exec, so every child of a held runner ignores HUP.
   - The painter sizes the pane with `cols="$(stty size < "$TTYP" | awk …)"` (`bin/cc-pane-verdict:135`). That is a blocking `open(2)` of the slave, done by bash before it execs `stty`.
   - Both are unchanged on origin/main `77cd84ff2`.
2. **Test precondition under overload (Confirmed code; Likely timing).**
   - pid 92243 ran at 03:02:08 under a waiver.
   - `pty.fork()` at 03:03:31 made 68298 the session leader of ttys063.
   - The driver waited 10 s for `hold:fs`, then called `sys.exit` without killing the child (`f5704886b:tests/cc-pane-runner-hold.bats:239-283`).
   - The runner reached its hold, and started painter 94459, only at 03:03:56: 25 s after fork, at about 65–77 load/core.
   - Evidence that the master was closed before the open:
     - 96296 sleeps in the carrier loop, and only `ptcclose` clears `TS_CARR_ON` on a ptmx pty (`tty_dev.c` ptcclose).
     - Master minor 63 was unheld at 13:11:33. `ptmx-holders.txt` sees only uid-501 holders, but the carrier sleep already proves the close.
   - The teammate hit the same failure at 04:18:59 ("never held … startup under load ~700") and passed with a 30 s wait.
   - **Still unfixed at HEAD.** The driver now waits 30 s, but `fail()` still does `os.kill(pid, 9)`: pid only, no `killpg`, no `finally`. A python killed by a bats timeout still orphans the runner, and the real painter still runs against a real pty (`tests/cc-pane-runner-hold.bats:244-300`).
3. **Opener blocks (Confirmed).**
   - The chain is painter 94459 → subshell 95771 → **bash 96296**, with sibling awk 96310: the `$(stty size < … | awk)` shape.
   - From 03:03:58 it sleeps in `__open → spec_open → ptsopen → ttysleep(TSA_CARR_ON, TTIPRI|PCATCH)` (`tty_dev.c:295-302`). The stack is the same in both spindumps.
   - `spec_open` holds `devsw_lock(dev)` across `d_open` (`spec_vnops.c:400-401`). So the opener pins that minor's devsw lock and an iocount on the slave vnode.
   - Only a signal it does not ignore can wake it, and it ignores HUP/TERM/INT.
   - This was harmless until 03:48:58: at 03:41:04–14 nothing sat on the devfs or revoke paths.
4. **Trigger (Confirmed act; Likely effect).**
   - 68298 was `Ss+`, alive and not exiting, at 03:48:20–29.
   - At 03:48:58 the teammate ran `kill -KILL 94459 68298`. That is by pid, so 95771, 96296 and 96310 survived.
   - 68298's `proc_exit` ran the session-leader block in this order (`kern_exit.c:2312-2336`):
     1. SIGHUP to the foreground group;
     2. `session_clear_tty_locked` (`:2321`);
     3. `ttywait`;
     4. `VNOP_REVOKE(REVOKEALL)` → `vnode_reclaim_internal`, which sets VL_TERMINATE.
   - `TIOCREVOKE` wakes only `TSA_HUP_OR_INPUT` (`tty.c:1614-1622`, `tty.h:266-267`). The carrier sleeper is on a different channel.
   - `vnode_drain` then sleeps with no timeout and no PCATCH (`vfs_subr.c:6609-6626`; `kern.bootargs` is empty).
   - **Only one reclaimer exists.** `vn_revoke` returns ENOENT when VL_TERMINATE is already set, yet the 13:15 stall has exactly one revoke frame (68298's) and one drain leaf.
   - 94459 is in `fixjobc → proc_parent+0x1d0`, an uninterruptible wait for its exiting parent (`kern_proc.c:1304-1350`, `:2800`). That is why 95771 was never reparented.
5. **Global `/dev` stall (Confirmed path; Likely tie of each sleeper to ttys063).**
   - `devfs_dntovn` uses `vnode_getwithvid_drainok`, which lacks `VNODE_DRAINO` (`vfs_subr.c:6327-6330`). A lookup of the node therefore sleeps in `vnode_getiocount` on `"vnode getiocount"` while VL_TERMINATE is set (`vfs_subr.c:6762-6775`).
   - Libc `devname_r` lstats every entry in readdir order. devfs appends new entries at the tail (`devfs_tree.c:465-472`). So any lookup of a pty created after 03:03:31 crosses ttys063.
   - **The sleep is interruptible (PCATCH for ttys):**
     - a default-action signal kills the walker;
     - a handler without SA_RESTART gets EINTR after at most 8 `devfs_dntovn` retries, and `devname_r` skips the entry (`if (lstat(…)) continue;`) and finishes;
     - an SA_RESTART handler re-enters the syscall and blocks again;
     - a caller that gets no signal blocks indefinitely.
   - Sleepers observed:
     - 40 getiocount leaves at 13:15 (23 `ps`, 17 `login`), at 0 CPU;
     - the user's `zsh -fc` (1,715/1,715 samples);
     - the kill call's own `ps -o pid,stat -p 68298,94459`, from about 03:49:00. A multi-pid list without `-x` makes `ps` call `devname(e_tdev)` on every process that has a controlling tty (adv_cmds `ps.c:568-570`, `:681-690`, rdar 86332769);
     - capacity-alarm's `read_argv0` `ps` (35442, from 03:48:36);
     - lr-recon's `ps pid=,tty=`. It had 478 timeouts but no pile-up, because its own timer killed each one;
     - `tty` 93540 (06:59:51);
     - `cc-sessions`' bulk `ps` (twelve handoff-fire censuses wedged for more than 50 min).
   - **User symptoms explained:**

     | Symptom | Explanation |
     |---|---|
     | Terminal stuck at "login" | `login` → ttyname |
     | iTerm2 `zsh -f` blank; `zsh -fc` hung while `zsh --version` returned | zsh `init_io` → ttyname; `--version` never reaches it |
     | `bash --noprofile --norc` worked | bash never calls ttyname |
     | `sleep 3; ps` slow | TT column |
     | `ls /dev` hung | Apple fts uses `getattrlistbulk`; devfs has no bulk vnop, so VFS emulation runs `namei` on each entry (`vfs_attrlist.c:3976-4030`) |
     | `claude` printed nothing and ignored Ctrl-C | claude.exe imports `_ttyname_r`; an SA_RESTART restart fits both. The call site is unverified (Likely) |
6. **kitty main thread (Likely).**
   - The main thread logged at 03:49:31, 03:49:56 and 03:52:16.9, then never again (562 min; the previous longest gap was 421 min).
   - kitty held 47 masters but had 46 live window leaders. The extra master is **fd 17 = 15,4, 0 bytes, with no window process** (`ptmx-holders.txt:2`). That is a spawn that froze between `openpty` and `fork`.
   - `spawn()` calls `ttyname_r(slave)` on the main thread with the GIL held, before `fork()` (`kitty/child.c:73` @ v0.48.2). A newly created ttys004 node sorts after ttys063.
   - kitty "ignored" SIGTERM at 13:14:55: its handler is `SA_SIGINFO|SA_RESTART` (`loop-utils.c:51`), so the lstat restarts after the handler runs.
   - Who started the spawn is unknown. The user was active at 03:52–03:54, and fleet RC traffic was continuous.
   - **Alternative:** the 10-22 load-only deafness mode, under which the 03:52–03:57 stop is a coincidence. Against it: no recovery when load fell to about 20, and the 0-byte childless master.
7. **RC saturation (Confirmed outcome; onset bracketed).**
   - The talk thread keeps accepting connections, but only the main thread releases peers. `PEER_LIMIT 256` is hard-coded (`child-monitor.c:1785-1800`).
   - The limit was reached between 04:15:04 and 06:08:38. From 12:05, refusals ran at 60–100/min (the `/goal` runaway).
8. **Lockup and reboot (Confirmed), and the shutdown artifact (Likely).**
   - New terminals could not get past ttyname, kitty was frozen, and the user restarted.
   - kitty's SIGKILL closed every master. Three expect panes then `exec`'d a fresh zsh: 27387 at `init_io+228`, the open, already past ttyname at +208. Each entered the carrier wait.
   - Their window shells 81102, 55297 and 5802 blocked in `spec_close`, "blocked by turnstile waiting for zsh [27387]" (`bsd_stubs.c:349-381`, THREAD_UNINT).
   - This is not onset evidence. It shows the class again at about 2 load/core, and it shows that **a close (and a nonblocking open) of a tty that has a blocking opener is uninterruptible**.

### 3.2 Cause 2: overload, and governors that released themselves

- **Agent gate:** the t1-runner spawn was admitted on `budget-expired`, after 3 consecutive refusals, with "13 sessions mid-turn + 1 > active ceiling 8" (idl.jsonl 07:34:27Z).
- **cc-bats:**
  - 362 waivers between 10-24 12:00 and 10-25 14:00, 20 of them in the 03:00 hour.
  - The trigger run's waiver gave "load ~650" as its reason.
  - The refusal text itself prints the waiver incantation (`bin/cc-bats:748-749`).
  - postland-verify exports `CC_BATS_MAX_ROOTS=0` (`scripts/postland-verify.sh:231`).
- **Load term:** off by design. `load1` does not move with a resident spawn (`scripts/lib/capacity-admit.sh:158-169`, f944d6e3). The Agent path passes `CC_ADMIT_LOAD_TERM=off` (`hooks/agent-teams-enforce.sh:281`).
- **Dispatcher:** fired at 62.3 and 88.6 load/core on 10-25, and at 27.16/core today.
- **Effect on the fixture:** a 10 s start-up budget in a fixture that runs a signal-immune process on a real pty. At about 70/core, start-up took 25 s.
- **Counterfactual:** a binding gate at the §5 ceiling would very likely have prevented this instance. It would not prevent the class: link 8 reproduced it at about 2/core.

### 3.3 Cause 3: detection

- **Producers that went dark:** capacity-alarm, attrib, convoy, kalloc-slo, the cc-reaper sweep (after 06:35:39), and the heartbeat roster. Each hung on its first devname walk:
  - capacity-alarm: `read_argv0` at `:865`;
  - the pty gauge: `[ -e /dev/ttys### ]` at `:2019` would have hung next;
  - cc-sessions: multi-pid `ps`.
- **Consumers that noticed but did not escalate:** the drainer (×1,247 "kitty unresponsive"), lr-recon (478 timeouts), and the heartbeat, which kept a stale `kitty-ls`.
- **Paging:** capacity pages delete themselves on OK, there has been no desk reader since 09-09, and Pushover is not configured (`~/.config/lr-page/` is empty).

### 3.4 Causes 5 and 6

- **Amplifiers:** 31 never-exiting `ps` pipelines. Of the 35 found, 4 were caught mid-run (etime 0–10 s).
- **Other leaks:** 297 kitty zombies (#10436); 40+40 leaked zsh `zsystem flock`/fifo pairs; the `jetsam-lane.sh` orphan; three teammates that ignored shutdown_request at 07:00; a nohup'd TrueMemory gate; SevenRooms OS at 8.4 CPU-h and about 45k ports. None is causal.
- **Recovery:** boot-resume abstained at 13:21:21 (`source=heartbeat, no-open-sessions`). worktree-gc removed 49 worktrees at 13:31:06.

---

## 4. Ruled out

| Candidate | Why it is ruled out | Evidence |
|---|---|---|
| H1 PTY exhaustion | 64/511 at 03:45. At 13:11, 65 uid-501 master fds, highest minor 79 | capacity-alarm `ptys_used`; ptmx-holders.txt |
| H3 lookup cost scaling with the number of ptys | 3.5 µs per entry (2.4 ms at 511). The hang is a 0-CPU sleep. Readdir *order* matters; count does not | experiments.md |
| Original H2 (kitty stops reading → writers block → close-drains hold devfs locks) as the trigger | kitty was healthy at 03:41. No blocked tty writers at 03:41 or 13:15. Close drains are bounded at about 0.6 s | diag-reports; experiments |
| H2 drain variant (`ttywait` on an unread master) | Holds an iocount but never sets VL_TERMINATE, so it cannot poison lookups; only a revoke can | xnu source |
| A second reclaimer (revoke(2), a recycle, a probe) | One revoke frame and one drain leaf in the stall; `vn_revoke` returns ENOENT on an already-terminating vnode. `revoke-watch.py` (research-midturn-account-move, 02:31 to about 05:06) was gone by 13:11 | stall; vfs_subr.c |
| A pre-kill onset (ps 35442) | 35442 is capacity-alarm's multi-pid `ps`, started 22 s before the kill. 68298 was `Ss+` at 03:48:20–29, and a revoke needs the leader's exit | ps; capacity-alarm.sh:863-872; t1-runner |
| The three pane-zsh openers as an earlier wedge | Their masters were held by kitty until 13:14:59. Their leaders are stuck in fd close, *before* the revoke block | ps-prereboot; stall |
| kalloc zone exhaustion | No zalloc or zone-wait frames; the 40 walkers sit in msleep under getiocount. 8% of the map at 02:20 (stale after that, but irrelevant to these stacks) | stall; kalloc-zone-series.tsv |
| Compressor or VM stall as the mechanism | No vm_fault or page-wait frames. The wedge outlived the pressure (13:02 at 17%, load about 900 → about 20) | stall; compressor-sentinel |
| vnode-table exhaustion | "Vnodes Available: 88.62% (233214/263168)" | stall header |
| DEVFS_LOCK contention or pty churn | `devfs_dntovn` drops DEVFS_LOCK before the drainok get. Contention would show lck_mtx turnstile waits, not msleep | devfs_tree.c |
| CPU starvation as the mechanism | Sleepers used 0 CPU. The wedge persisted at load about 20 | stall; qos-census |
| Memory exhaustion, jetsam, kernel panic or watchdog | About 42–50 GiB available. Only per-process-limit kills. Restart was user-initiated | logs |
| kitty as the trigger; App Nap | Healthy at 03:41 and logging until 03:52:16.9. Frontmost, unclamped, user active. NSAppSleepDisabled is hygiene only | spindump; runningboardd |
| kitty fd exhaustion | Soft limit 2,560 | kitty-deaf-episode-2026-10-22 |
| WindowServer, the 12:05 `/goal` runaway, TrueMemory pythons, SevenRooms OS, the iOS simulator | Late or unrelated load; nothing couples them to the lstat/namei path | timeline |
| compressor-sentinel SIGSTOPs | Never signalled kitty or claude; freeze debt 0 | sentinel log |
| Onset at "about 10:15" | That was when one session first noticed | timeline |
| capacity-alarm's pty-gauge stat loop as why it went dark | The tick hung earlier, in `read_argv0` | ps tree 97955→35441→35442/35444/35447 |
| "No concurrency limit would have prevented it" | 25 s start-up against a 10 s budget; the same arm passed at 30 s | ps etime; t1-runner.txt:348 |
| An OS update as the fix | xnu-12377.121.6 has the same code | source |
| The order-of-events verdict's 12–15 s clock correction | Rejected; see A-O5 | hb.kitty-start; 228 s offset; file birth time |

---

## 5. Measured safe concurrency ceiling (basis included)

**Framing.**
- Session count does not bound the regime. The same 22–38 resident sessions produced anywhere from 2 to 30 load/core.
- The binding axis is sustained load per core. It is measured here by whether a 60 s launchd producer keeps its cadence, which is exactly the property that fixed test budgets and instruments need.
- `load1` is the measurement, not an admission input: a single resident spawn moves it by about 0. Enforcement must use a brownout on the sustained band, cadence misses or start-up latency (§7 R11).

**Cadence against load per core.**
- Data: `capacity-alarm.jsonl`, 10-21 19:06Z → 10-25 20:55Z, 3,186 intervals. The 03:45–13:16 dark window contributes nothing, so the worst band is optimistic.
- "Gaps > 180 s" is keyed to the load/core of the preceding row. "Rows/h" is keyed to the hour's median.

| load/core | intervals | gaps > 180 s | rows/h p50 (hours) | resident sessions p50 (range) |
|---|---|---|---|---|
| 0–2 | 445 | **0.2%** | 57 (8) | 22 (4–23) |
| 2–3 | 365 | **0.0%** | 44 (5) | 24 (17–25) |
| 3–5 | 629 | **0.3%** | 49.5 (16) | 26.5 (22–33) |
| 5–8 | 564 | 1.8% | 45 (14) | 26.8 (20–34) |
| 8–12 | 363 | 4.7% | 35 (14) | 30.5 (23–38) |
| 12–20 | 312 | **18.3%** | 24 (7) | 29 (17–35) |
| 20–40 | 356 | **45.2%** | 17 (17) | 37 (30–46) |
| > 40 | 152 | **55.9%** | 15 (8) | 37.5 (2–44.5) |

**Concurrent bats runs against load1** (qos-census, same window):

| runs | load1 p50 | load1 p90 |
|---|---|---|
| 1 | 36 | 271 |
| 2 | 75 | 265 |
| 3 | 115 | 323 |
| 4 | 129 | 388 |
| 5 | 201 | 485 |
| 6+ | 367 | 837 |

Fewer runs is *necessary* but not *sufficient*.

| Resource | Safe ceiling | Hard stop | Basis |
|---|---|---|---|
| **Sustained load/core (5-min)** | **≤ 5**: instruments on cadence (≤ 0.3% missed); 10 s budgets hold | Refuse new autonomous fires and resumes at **≥ 8** sustained; brown out (pause heavy toolchains, waivers void) at **≥ 12**; admit nothing autonomous at **≥ 20** | Cadence table. The trigger fixture failed at about 65–77/core. The dispatcher admitted at 62, 88 and 27/core |
| Concurrent heavy toolchains (bats corpora, Playwright, ffmpeg, full gates) | ≤ 2 (median 3.6–7.5/core) | 3 | qos-census table above; machine-lag-2026-08-06 :129-144 |
| Resident Claude sessions | ≤ 25 as a *planning* number: the ≤ 5/core hours had p50 22–27 | Not an admission term on its own | Cadence table; 10-24 13:00 had 22–23 sessions at 11.4/core |
| kitty coalition processes | ≤ 500 | 700 (first crossed 10-24 15:58, the start of the 12.8 h saturation) | capacity-alarm; panic-iterm2-coalition-2026-07-31 (death at 1,002) |
| Brownout predicate (vote) | n/a | 2 of 3: sessions ≥ 40, coalition ≥ 600, < 10 alarm rows in 15 min. True on 0–10% of normal-day rows, 56–60% of bad days, first fired 21:57Z on 10-24 (about 10.8 h before the collapse) | `solution/fleet-governor.md` §3 (Likely; fitted to this data) |
| System processes and threads | About 1,500 / about 6,000 (soft) | 3,000+ / 10k+ treated as saturated (03:41: 3,729 / 11,880) | 03:40 spindump; machine-lag-2026-08-06 |
| kalloc data.kalloc.1024 | ≤ 4 GiB | 6 GiB alarm; panic about 20 GiB | 15.8.1 still leaks about 1.1 KiB per `#!` exec (kalloc-longterm-2026-10-21/measure.md:35) |
| Compressor segments / swap | seg ≤ 25%; swap growth < 1 GB per 15 min | seg 45% warn / 70% alarm | This onset: seg 37%, swap +4.5 GB in 15 min |
| PTYs | Not binding (about 45–80 in use of 511) | Alarm at 400 | The binding constraint is pty *lifecycle* (R1–R5), not count |
| Fixed-budget fixtures | Must refuse to start above 8/core | n/a | 25 s observed against a 10 s budget |

**Now (15:55):** 27–29/core, 48% sys, 0% idle. That is the band where 45% of producer intervals are missed, and the dispatcher is still admitting fires. **No ceiling removes the class:** the 13:15 artifact happened at about 2/core.

---

## 6. Telemetry gaps (what would have made this a 5-minute diagnosis)

**The minimal set.** Items 1–4 alone would have produced, at about 03:50, a page that read:

> "tty canary stuck at /dev/ttys063; leader 68298 exiting since 03:48:58 (SIGKILL by pid from session cc5a6d48); session members 94459 (exiting), 95771, 96296 (user leaf `open`), 96310; kill 95771/96296/96310."

1. **A tty-path canary that names the node.**
   - Every 30–60 s, run a 5 s `ttyname` on a fresh pty in a disposable child, plus a per-entry bounded lstat walk of a readdir-only listing of `/dev`.
   - lr-recon measured this only by accident (478 timeouts) and abstained quietly.
2. **A devname-free process census on every canary failure.**
   - Use `ps -A -o pid=,ppid=,pgid=,stat=,etime=,tdev=,command=` plus `os.getsid()` for each pid.
   - `-A` skips the devname filter, and `tdev` prints major/minor raw (adv_cmds `print.c:591-608`; tested).
   - Two reasons it must not rely on tdev alone:
     - Members of a session whose leader is inside its revoke read NODEV (`kern_sysctl.c:1050-1055`).
     - `ps -o wchan` is blank on this macOS (tested on an msleep sleeper).
   - So the census must join on ppid, pgid and sid.
   - Our incident snapshots also lacked `stat`, `lstart` and `args`.
3. **An automatic stackshot.** A pre-authorized `spindump -notarget` (sudo; see HUMAN-ACTIONS) or tailspin. No spindump was taken between 03:41 and 13:15, and kitty's stack at the freeze was never captured.
4. **A kill audit.** Every `kill` should be logged with exec start and end times, the target pids, each target's pgid and sid, whether the target is a pty session leader, and its session members.
   - Today only the tool-call *issue* time (03:48:58) is known.
5. **Signal-disposition visibility.** The installed `/bin/ps` has no `sigignore`/`sigcatch` keywords (tested), so nothing showed which children inherited SIG_IGN for HUP.
   - Candidate (Speculative): read `kp_proc.p_sigignore` from `KERN_PROC_PID` via ctypes.
6. **Producer freshness.** capacity-alarm, attrib, convoy, kalloc-slo, cc-reaper and the heartbeat roster were silent for 9.5 h without a page.
7. **kitty RC liveness, with kitty error lines persisted in real time.**
   - The unified log kept the "Too many peers" lines for under about 8 h. Today the PEER_LIMIT onset cannot be recovered.
   - RC callers log only on completion, which left a 2.5 h gap with no failure rows.
8. **Paging that reaches a human:** an off-box channel when no desk is present, and history that is kept rather than self-deleted on OK.
9. **CPU attribution on a devname-free path.** attrib died with capacity-alarm, so H4 (the 43% sys peak) and H5 (claude at 15–32%) cannot be answered.
10. **Evidence preservation at incident start.** An early bounded `log collect` (root) or `log show` export of the kitty and kernel subsystems. Records retention-sensitive lines before they roll off.
11. **Heartbeat granularity.** The tick ran every 10–11 min under load (nominal 5). It logs no roster size, and it does not record *why* `cc-sessions` failed.
12. **Diagnostic-report lag.** The 03:40 hang report was written 2 h 52 m late, and no kitty hang report was ever produced.
13. **No exec parentage in compact unified-log lines.** The 12:05 burst poller, jetsam-lane.sh and the lldb launcher cannot be attributed from them.
14. **No KDK for 24H32.** Kernel frames are named from offsets.

---

## 7. Requirements for the long-term fix

**Pty lifecycle (removes the trigger class).**
- **R1. No fleet code opens a slave tty by path in blocking mode.**
  - Prefer no open at all: `TIOCGWINSZ` on an inherited fd, kitty-reported columns, or `$COLUMNS`.
  - An `O_NONBLOCK|O_NOCTTY` open is a last-resort fallback, run only in a disposable child that may be abandoned. The open (or the final close) can still block THREAD_UNINT on the devsw lock behind an existing carrier-wait opener.
  - Fix `bin/cc-pane-verdict:135` and audit every `stty … <` site, including expect's `stty rows … < $spawn_out(slave,name)` in `scripts/limit-recover/lr-fire-resume.sh:1873` and `bin/reso-resume-one:991`.
  - Lint `< "$TTY"`, `> /dev/ttys*` and `[ -c "$TTYP" ]` in bin/, scripts/ and hooks/.
- **R2. A process that ignores HUP/TERM/INT must not pass that disposition to children that touch the tty.**
  - `_guarded` (`bin/cc-pane-runner:292`) resets the traps in every child before exec, or the hold lives in a process that spawns no tty-touching child.
  - A held runner detects master loss (EIO or POLLHUP on its tty) and exits.
- **R3. Teardown kills the whole session tree, openers first, and never waits on reclaimers.**
  - Target set: the descendants by ppid walk, plus every pid with `getsid == leader`, plus every pgid in that set. Kill those, then the leader.
  - Use devname-free reads only.
  - Killing by pgid alone is not enough. At 13:15 the opener was zsh 27387 in pgid 27387 under leader 81102, and an opener can be in an unrelated session.
  - The exiting leader and children stuck in `proc_parent` are unkillable: log them and move on.
  - Applies to cc-reaper, cc-husk-sweep, `cc-restore --restart-kitty`, teammate "kill orphan" steps, and a `validate-bash.sh` guard against SIGKILLing a pty session leader by pid while it has live members.
- **R4. pty fixtures are hazardous and are treated as such.**
  - The driver kills the child's session and group in `try/finally`, in signal handlers and at exit.
  - The real painter never runs on a real pty; use a stub.
  - Start-up budgets refuse to run above 8/core, rather than stretching.
  - pty tests cannot be waived past the bats gate.
  - Run them off the shared live host where possible.
  - HEAD (`tests/cc-pane-runner-hold.bats:268-273`) still kills by pid only.
- **R5. kitty restart and kill do not recreate the deadlock.** Kill the old pane session trees (R3) before or with kitty, so `exec zsh` cannot re-open a tty whose master is gone.

**Detection and auto-remedy.**
- **R6. A tty-path watchdog independent of `/dev`.**
  - Canary and node-naming walk as in §6 items 1–2, run as abandonable children with one outstanding per type.
  - On a stuck node: census (§6 item 2), stackshot when pre-authorized, page carrying the cure command.
  - Remedy: SIGKILL the R3 target set of every exiting pty session leader.
  - An opener outside that tree needs a stackshot, or a user-level `sample` of candidates showing an `__open` leaf.
  - Auto-run only after the VM reproduction (Q1) passes, including the minor-reuse safety check.
- **R7. No instrument uses the devname path.** Ban all of these in instruments and hot paths:
  - `ps` TT/tty columns, e.g. `scripts/handoff-fire.sh:2151,2478,2496,2664,3186`, `hooks/accounts-board.sh:139`, `hooks/lead-crash-watchdog.sh:2275`, `scripts/headless-precondition-probe.sh:143`, `scripts/limit-recover/lr-upgrade.sh:2339`, `bin/dia-cdp-launch.sh:277`;
  - multi-pid `ps -p a,b` without `-x`/`-A`: `scripts/capacity-alarm.sh:865`, and `handoff-fire.sh:2496`, which also has a tty column;
  - `ps -t` (`scripts/handoff-selfclose-e2e.sh:108,127`), `tty`, `ttyname`, `[ -e /dev/ttys* ]` loops (`capacity-alarm.sh:2019`), `ls /dev` and fts over `/dev`, and lsof device-name resolution.
  - Enforce with a ship-gate lint.
  - Count ptys from a readdir-only listing (no stat), since XNU exports only `kern.tty.ptmx_max`. That this is safe during a wedge is Speculative; verify in the VM.
- **R8. Freshness watchdog on every producer**, paging after 3 missed intervals.
- **R9. Page delivery that reaches a human.** Off-box when no desk is present; history kept; no self-delete on OK.
- **R10. kitty-RC liveness rung.** Page on 2 consecutive failed bounded `kitty @ ls`, on any "Too many peers" line (captured in real time to our own log), or on a master that has had no child for N seconds.

**Admission and load.**
- **R11. Admission that holds under load.**
  - Brown out on a signal that moves with the work: the §5 sustained load/core bands, producer-cadence misses, and fork/exec start-up latency. Not a per-spawn `load1` delta.
  - Remove the 3-refusal self-release for autonomous callers.
  - Stop printing the waiver line to model callers; waivers need an operator-held token and are void in brownout.
  - Bound postland-verify's blanket `CC_BATS_MAX_ROOTS=0`.
  - Apply the same term to the dispatcher, handoff-fire and the ungated headless jobs.
- **R12. No `taskpolicy -b` on claude.exe** (an 84–89× tax confined to the E-cores).

**kitty.**
- **R13. Get kitty's main thread off `/dev`.**
  - Patch or propose `spawn()` using `ptsname_r(master)` (TIOCPTYGNAME) instead of `ttyname_r(slave)`.
  - Upgrade to ≥ 0.49 for #10436 (signals and zombies) and 0.50 for #10632 (RC back-pressure).
  - SA_RESTART means no catchable signal frees a blocked kitty; only SIGKILL does, and SIGKILL triggers R5.
- **R14. RC clients get hard timeouts, back-off and a circuit breaker.** Polling loops, including `/goal`-driven ones, stop on repeated failure.
- **R15. `NSAppSleepDisabled` YES** (hygiene only).

**Recovery and evidence.**
- **R16. boot-resume does not accept an empty roster when a shutdown tombstone burst exists.** worktree-gc holds interrupted sessions' worktrees for one boot. The crash path searches previous boot UUIDs.
- **R17. A no-reboot runbook for this wedge (Likely; validate in a VM).**
  1. Capture: devname-free census (§6 item 2), plus a stackshot if pre-authorized.
  2. Name the stuck node (canary).
  3. Find exiting session leaders (STAT `E`/`Z`, or `(bash)` with RSS 0), then their sessions (`getsid == leader`) and descendant trees. Do not rely on tdev: once the revoke has started, members read `??`.
  4. SIGKILL the R3 target set, excluding the reclaimer.
  5. Re-run the canary.
  6. If nothing was released, kitty-free reboot via Apple menu (it writes the stall stackshot).
- **R18. Hygiene.**
  - verify-cell cleanup kills its processes (the jetsam-lane orphan).
  - Fix the zsh `zsystem flock` and process-substitution leak.
  - nohup'd gates need a parent watchdog.
  - Teammates handle shutdown independently of their TUI.
  - Find the 43 per-session bash+sleep loops that reparent to launchd.
- **R19. Incident tools record absolute times** (`lstart`, exec start and end), and preserve retention-sensitive logs at first detection.

---

## 8. Open questions

1. **VM reproduction (gates R6 auto-remedy and R17).** Does SIGKILL of the carrier-wait opener release the drain on 24H32? The protocol:
   1. `pty.fork`;
   2. close the master;
   3. a SIG_IGN-HUP grandchild runs `stty size < slave`;
   4. SIGKILL the leader;
   5. time ttyname on a newer pty;
   6. SIGKILL the opener and re-time.

   The VM run must also test:
   - (a) a nonblocking open or close of the wedged tty blocks THREAD_UNINT behind the opener;
   - (b) after the opener's SIGKILL, ptsopen's `out_free` → `pty_free_ioctl(PF_OPEN_S)` frees minor 63's slot and devfs node while its vnode is mid-revoke (`tty_dev.c:312-321`). Can a reuse of minor 63 be hit by the late `VNOP_CLOSE(IO_REVOKE)`?
   - (c) the low-load start-up time of the A1t arm, to confirm load was necessary;
   - (d) whether a readdir-only `/dev` listing and `lsof -b` stay safe during the wedge.
2. **What exactly froze kitty's main thread, and who requested the spawn** (the user at 03:52–03:54, or fleet RC)? The `ttyname_r` sleep is inferred. `lsof` of kitty's slave fds and a main-thread stack were never taken.
3. **When did ps 35442 block, before or after the revoke?** Its 0.73 s CPU suggests many successful walks first. And when did the kill actually execute? Only its issue time is known.
4. **When was PEER_LIMIT reached** inside 04:15:04–06:08:38? Client logs in that window could show EOF versus timeout mode. The surviving extracts must be preserved.
5. **Where did the 43% sys go after the wedge, and what drove 37 of 45 claude processes to 15–32% CPU** (H4, H5)? H5 is unbounded: 37 had enough CPU time for 1 h or more at 15%, and three for the whole 9.4 h. Blocked TUI writes to unread ptys remain a candidate.
6. **Who owns the `ps|tr|grep` pipelines from 03:50:20 and the per-session bash+sleep loops**, who launched lldb 9–23 times a minute, and was the 12:05 burst poller the `/goal` session's tool shells?
7. **Was the 10-24 22:44 `ps` stall the load-class proc-table contention seen at 03:41?** There is no stackshot for it.
8. **Why did the pty-arm reruns at 04:19–04:26 stay held 30 s after release** while the non-pty arm passed? Probably they were victims of a tty-name lookup; untraced.
9. **Does the unpublished 15.8.1 xnu differ on these paths?** It cannot be ruled out by reading source; the VM test on 24H32 settles it.
10. **Root-held masters (for example sudo `use_pty`) are invisible to uid-501 `lsof`.** This is irrelevant to minor 63, but the census is incomplete in general.

---

## Appendix A. Refutation ledger

| ID | Refuted claim (verdict) | Disposition | Evidence / effect on this RCA |
|---|---|---|---|
| A-K1 | Walkers "sleep forever"; every new tty user "blocks for good" (kernel) | **Accepted** | `vfs_subr.c:6762-6775` (PCATCH for ttys, read again here); devfs retry ≤ 8; `devname_r` skips failed lstat; kitty `loop-utils.c:51` SA_RESTART; the kill call's `ps` was killed at 08:25:37. §3.1 link 5 rewritten; SA_RESTART explains kitty and claude ignoring signals |
| A-K2 | Open Q4: a second hang path for multi-pid `ps` (kernel) | **Accepted** (question closed) | adv_cmds `ps.c:568-570` (single-pid fast path only) and `:681-690` (devname filter when xkeep==0), read here. Earliest sleeper about 03:49:00. R7 bans the form; it also explains `cc-sessions` (67b84f5e1) and the empty roster |
| A-K3 | R1/R7: an O_NONBLOCK helper plus timeout and kill is enough (kernel) | **Accepted** | `spec_vnops.c:400` (open) and `:2813` (close) take `devsw_lock`; THREAD_UNINT turnstile seen at stall :54332. R1 rewritten (no open at all; abandonable children) |
| A-K4 | R17/R3: `kill -KILL -- -<pgid>` as the remedy (kernel) | **Accepted, extended** | 27387 (pgid 27387) and 81102 (pgid 81102). New: `session_clear_tty_locked` runs before `VNOP_REVOKE` (`kern_exit.c:2321` vs `:2336`) and clears `s_ttydev`, which is what kinfo reports as `e_tdev` (`kern_proc.c:2443-2455`, `kern_sysctl.c:1050-1055`, read here). So a tdev match cannot find 96296 in the global-wedge state either. `ps -o wchan` prints `-` (tested). R3, R6 and R17 now use the ppid/sid/pgid tree |
| A-K5 | "Confirmed from xnu-11417.140.69 … matches the stall's kernel" (kernel) | **Accepted** | Wording changed: nearest published base, consistent stack offsets. xnu-12377 has the same code, so an OS update is not a fix |
| A-K6 | Count ptys via a sysctl; `ptmx-holders.txt` is complete (kernel) | **Accepted** | `sysctl kern.tty` returns only `ptmx_max: 511` (run here); 65/65 rows are chrisren. The file is complete, but it is a uid-501 census only |
| A-O1 | PEER_LIMIT at 06:11:40.114; the unified-log lane's extract was "missing 92 lines" (order) | **Accepted** | Both extracts hold Df lines from 00:00:15, but their first E line moves with extraction time (06:11:40 at 14:02, 06:19:26 at 14:12). Onset bracketed 04:15:04–06:08:38 |
| A-O2 | capacity-alarm went dark at the `:2019` pty gauge (order) | **Accepted** | `read_argv0` at `:863-872` is exactly `ps -o pid=,command= -p "$1" \| cut -c1-200 \| awk`, called with a comma list at `:955-956`. The plist runs `/bin/bash` every 60 s, which gives 97955 with PPID 1. The workload verdict's "capacity-alarm has no such pipeline" is **rejected** |
| A-O3 | 35442 is an unattributed launchd job mid-scan of a TT column (order) | **Accepted, with corrected time** | It is capacity-alarm's multi-pid `ps`, started **03:48:36** (snapshot 13:11:33 − 9:22:57), not 03:48:21 |
| A-O4 | "No child after 03:48:34" supports a spawn freeze (order) | **Accepted** | Those children are pgid 1881, and the last window started at 03:37:17. Replaced by master fd 17 = 15,4 at 0t0 with no child (47 masters, 46 leaders) |
| A-O5 | ps snapshot at about 13:11:18 and stall reference at about 13:15:34, so all derived times are 12–15 s late (order) | **Rejected** | `hb.kitty-start` 1792612498 = 14:54:58 plus etime 3-22:16:35 gives 13:11:33, equal to the file birth time. Stall TSF − etime = 228 s for 209/212 pids gives 13:15:21, the stall's own Date/Time. The verdict took the 03:40 spindump's Date/Time (03:40:49, hang detection) as the TSF reference instead of the sampling start (03:41:04). Net effect: ps-derived times stand within about 3 s; 03:40-derived times move 15 s *later* (96296 at 03:03:58) |
| A-O6 | Open Q6: 10-22 had no peer-limit lines and was cleared by killing an opener (order) | **Accepted** (question closed) | 10-22 had no /dev wedge. 258 peerless unix sockets and EOF in under 1 s mean the peer table filled under load alone and recovered. kitty therefore has a second, load-only deafness mode (RC4) |
| A-W1 | Ceiling framing: "no concurrency limit would have prevented it" (workload) | **Accepted** | Fork 03:03:31 → painter 03:03:56 against a 10 s budget; at 30 s the arm held (04:18:59). §5 rewritten |
| A-W2 | RC4 "admission that never refused" (workload) | **Accepted** | idl.jsonl 07:34:27Z `budget-expired`; 362 waivers (20 in the 03:00 hour; pid 92243 "load ~650"); `cc-bats:748-749`; `postland-verify.sh:231`; `capacity-admit.sh:158-169`; `agent-teams-enforce.sh:281`. Promoted to cause #2 |
| A-W3 | qos-census "1–2 bats runs → load 8–16" (workload) | **Accepted** | Recomputed: 1 run p50 36 / p90 271; 2 runs p50 75 / p90 265 |
| A-W4 | Session ceiling "≤ 25, refuse at 30" (workload) | **Accepted** | Cadence table: 20–46 sessions occur at 20–40/core. Ceiling restated in load/core |
| A-W5 | H5 bounded to under about 1 h (workload) | **Accepted** | 37 of 45 claude had TIME for ≥ 1 h at 15%; H5 is unbounded |
| A-W6 | "35 never-exiting ps" (workload) | **Accepted** | 31; 4 were caught mid-run |
| A-W7 | Missing evidence: owner of 97955 (workload) | **Resolved** | capacity-alarm (A-O2) |
| A-W8 | "The overload is back now" (workload alternative) | **Confirmed** | 15:55: load 270–287, 48% sys, 0% idle, 1,625 processes, 38 claude, 25 cc-pane-runner; dispatcher fired at 27.16/core; hazards unchanged on origin/main 77cd84ff2 |

## Appendix B. Checks run for this final version (read-only)

- Clock anchoring: `hb.kitty-start`; `stat -f %SB` on ps-prereboot.txt and ptmx-holders.txt (13:11:33); stall-versus-ps offset computed over 212 pids; the Discord .hang header (Date/Time 03:40:49, End 03:41:14, sampled after 15 s unresponsive).
- Source reads:
  - adv_cmds `ps/ps.c`, `ps/print.c` and `ps/keyword.c` (main), in `/tmp/rca-final-dl/`;
  - xnu-11417.140.69 `bsd/kern/kern_proc.c` and `bsd/kern/kern_sysctl.c`, in `/tmp/rca-final-dl/`;
  - `vfs_subr.c`, `spec_vnops.c`, `devfs_tree.c` and `kern_exit.c`, in `/tmp/rca-synth-dl/`.
- Live tests:
  - `ps -o wchan` on a fifo-open sleeper prints `-`;
  - `ps -A -o tdev` prints `16/N` (290 processes) with no devname;
  - `sigignore`/`sigcatch` keywords are absent from `/bin/ps`;
  - `os.getsid()` works across sessions;
  - `sysctl kern.tty` returns only `ptmx_max`.
- Repo:
  - `scripts/capacity-alarm.sh:863-872, :955-956, :2019`;
  - `launchd/com.claude.capacity-alarm.plist`;
  - `bin/cc-pane-verdict:135` and `bin/cc-pane-runner:292`, on HEAD and on origin/main 77cd84ff2;
  - `tests/cc-pane-runner-hold.bats:244-300`;
  - `bin/cc-bats:744-751`, `scripts/postland-verify.sh:229-233`, `scripts/lib/capacity-admit.sh:155-172`, `hooks/agent-teams-enforce.sh:276-285`;
  - a census of devname-path call sites (§7 R7).
- Logs:
  - `~/.claude/state/bats-waivers.jsonl` (counts; pid 92243);
  - `~/.claude/autonomy/idl.jsonl` 07:34:27Z;
  - `capacity-alarm.jsonl` cadence-against-load (3,186 intervals);
  - qos-census runs-against-load;
  - `dispatch-fires.log` tail;
  - kitty log extracts (first E lines).

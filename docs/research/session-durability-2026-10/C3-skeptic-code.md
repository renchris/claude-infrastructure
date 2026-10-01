# C3 skeptic report: code and evidence lens

Read-only review of `C3-socket-robustness.md`, 2026-10-01. I made no `kitten @` calls, sent no signals, and launched
nothing except read-only commands and the system `python3`. Scratch files are `/tmp/sd-c3skc-*`. Times are UTC unless
marked CDT.

## Answer

**The core mechanism holds, and it holds more firmly than the dossier showed. Three of its supporting stories are
weaker than stated: when the thread died, why it died (EMFILE), and why signals broke. None of this is fatal. C3
remains a prevention complement with no session survival.** Recommended conviction: **48** (dossier: 62).

- **Stronger than claimed.** The 12:02 CDT sample the husk doc called "not kept" still exists:
  `/tmp/kitty610-sample.txt` (11:57:57 CDT, pid 610, parent `launchd [1]`). `grep -c KittyPeerMon` gives **0**, and
  `Thread_8856: KittyChildMon` is present. In the 2026-09-30 22:17:45 sample of pid 610, `Thread_8855: KittyPeerMon`
  is alive. 8855 = 0x2297, the talk thread's tid in the unified log. So the thread exit is now measured twice.
- **Weaker (1): the death window.** The cited evidence does not support the dossier's 07:08Z upper bound (claim 2).
- **Weaker (2): EMFILE.** The timeline does not fit the EMFILE accumulation story (claim 4).
- **Weaker (3): the signal bug.** The talk thread's exit is not needed to explain the signal clobber. A second
  trigger fired that night and is live today (claim 5).
- **Weaker (4): S1's premise.** The idea that "a live talk thread reads within ms" fails under the measured PRI 4
  clamp (claim 8).

## Verdicts per key claim

**1. The only non-shutdown exit is accept_peer() returning false; kitty 610 took it; v0.49.2 and master are
unchanged. STANDS.**
- `/tmp/kittysrc/kitty_child-monitor.c:1821-1826`: the `perror` line and `return false`.
- `:2058`: `goto end`.
- `:2082-2086`: `end:` frees the peers.
- `:1777`/`:1780`: `talk_thread_started` stays true, so nothing restarts the thread.
- The other returns (`:1834`, `:1840`, `:1844`) are all `true`.
- `diff -q` against a fresh curl of v0.48.2 gives CM-SAME.
- v0.49.2 and master, fetched with curl: `accept_peer` at 1995, `perror` at 1999, `goto end` at 2260.
- Thread exit is measured from the two retained `sample` files (see the Answer).

**2. Died between 07:06:47Z and 07:08Z; remote control dead for 11 h 23 min. WEAKENED.**
- **The lower bound is re-measured.** `log show ... processID == 610` gives 35,340 lines (rc 0). There are 179
  broken-pipe lines, all `kitty[610:2297]`; the last is at 02:06:47.037 CDT. The dossier said 35,356 and 180; the
  drift is log retention.
- **The 07:08Z upper bound is not evidence of death.** The subagent transcript
  (`~/.claude/projects/...09c26b2b.../subagents/agent-a22db32d3e0a10e9e.jsonl`) shows:
  - At 07:03:10-07:03:28Z, 8 of 8 probes answered: `kitty #1 rc=0 9.4s`, then 0.59-1.69 s. The thread was alive and
    one answer took 9.4 s.
  - At 07:07:00-07:09:36Z, every probe ended at 10.05-10.08 s with 0 bytes.
  - A live thread behind a deaf main thread gives exactly the same symptom. The dossier itself documents such
    episodes.
- **A defensible upper bound.** Main thread `15e6` logged `Requesting authorization` (a pane notification, parsed in
  `parse_input`) at 02:18:25.830 CDT. No broken-pipe line followed for the 15 abandoned 07:07-07:09Z probes. So the
  thread was dead by about **07:18Z**.
- **The window is 07:06:47-07:18:25Z.**
- **"11 h 23 min" is outage length, not detection time.** The diagnosis came at 11:58-12:02 CDT and the relaunch at
  13:29:45 CDT. That is 1 h 28 min after diagnosis.

**3. kitty keeps an abandoned client's fd until the main thread answers. STANDS.**
- `prune_peers` `:1968` requires `!num_of_unresponded_messages_sent_to_main_thread`.
- On hang-up, `read_from_peer` `:1927-1931` still queues a message.
- `queue_peer_message` `:1871` increments the count.
- The 179 `Broken pipe` lines from tid 2297 are the direct trace.
- Bursts re-counted: 01:54-01:57 CDT = 10+5+11+26 = 52.

**4. EMFILE is the only realistic errno (75%). WEAKENED; about 50%.**
- **The XNU reading is right.** `accept_nocancel` in `xnu-11417.140.69` (the running kernel, from `uname -v`) is
  byte-identical to main (`diff` of the extracted function is empty).
- **The cited lines check out:** `:519-536` (ECONNABORTED only when the listener is draining), `:619-632` (falloc
  failure drops the connection), `:663` (`(void) soacceptlock`).
- **No filter can inject an error.** `kmutil showloaded` lists no non-Apple kexts. The only network extension is
  Tailscale (a packet tunnel, not AF_UNIX).
- **The soft limit is 256.** kitty 610's parent is launchd (sample header), and `launchctl limit maxfiles` gives
  `256 unlimited`.
- **kitty never raises its fd limit.** GitHub code search for `RLIMIT_NOFILE repo:kovidgoyal/kitty` returns 0.
- **The listener is blocking.** `boss.py:233-237` uses a plain `socket.socket`, and kitty has no
  `setdefaulttimeout` (code search returns 0).
- **But the accumulation story conflicts with the timeline.** Each main-thread pass in `parse_input` (`:522-553`)
  answers every queued peer, and answered peers are then pruned.
  - The main thread answered at 07:03:28Z (probes) and at 07:04:30 and 07:06:47Z (broken pipes).
  - So roughly 180-190 new held peers had to build up after 07:06:47.
  - Under the dossier's own ≤07:08Z bound, that is about 180 connections in about 75 s.
  - Under my ≤07:18Z bound, it is at least 16 per minute.
  - Against that: `handoffs.jsonl` has **no rows between 07:00:32Z and 07:14:47Z**, the last kitty-610 pane spawn
    is at 07:00:05Z, and the dossier's census says 2-6 per minute.
  - The dossier's "20/min × 10-min deaf episode" does not fit the measured windows.
- **What remains.** EMFILE is still the only errno that XNU's source allows. Either a burst that nothing logged
  happened, or fds that are not peers ate the headroom (UNMEASURED), or there is an unread path. P1 still covers
  EMFILE from any source. The **peer-pile-up rationale for S2 is not demonstrated**.

**5. The dying talk thread disables signals (zombies, ignored SIGTERM); fixed upstream in v0.49.0. WEAKENED as an
explanation.**
- **The mechanism is right.**
  - `loop-utils.c:84` clears the write fd unconditionally.
  - The talk loop is created with 0 signals (`child-monitor.c:1778`) and freed at `:2083`.
  - The signal-owning loop is `io_loop_data` (`:175`).
  - `gh api .../commits/f3fdc21850` shows the guarded clear, and `compare f3fdc21850...v0.49.0` gives `ahead`.
- **The trigger is not shown.** kitty#10436's own trigger fired that night. Comparing `DiskCacheWrite` threads
  between the 22:17:45 CDT sample and the 11:57:57 CDT sample of pid 610: **14 of 21 exited**.
- A `DiskCacheWrite` thread exits only on dealloc (`disk-cache.c:468`, `:560-563`), and dealloc calls
  `free_loop_data` (`:573-575`), which does the same clobber.
- So the zombies and the ignored SIGTERM do not depend on the talk thread's death.
- Small correction: f3fdc21850 touches 4 files. The needed hunk is `loop-utils.c` +4/-2, not "2 lines".

**6. The staged build has no accept_peer fix. STANDS.**
- `grep '^diff' docs/patches/*.patch`: no patch touches `child-monitor.c` or `loop-utils.c`.
- `~/ktb` is clean at `1d1d947` and still has the unconditional clear at `loop-utils.c:84`.
- The staged `fast_data_types.so` is dated Sep 30 22:27.

**7. P1 (a global watcher that raises RLIMIT_NOFILE) is feasible. STANDS, with a gap closed.**
- `launch.py:516-542` runs `runpy.run_path` and then `on_load`, and catches exceptions at `:537-542`.
- `window.py:682-705` defines `GlobalWatchers`, and `:749/:751` call it when a window is created.
- **The dossier's `kitty +runpy` test proved a decrease, not a raise.** Agent shells already run at
  `ulimit -n` 1048576 (measured).
- I measured the raise from 256: `( ulimit -n 256; /usr/bin/python3 -c '...setrlimit(RLIMIT_NOFILE,(8192,h))' )`
  printed `before (256, inf)` then `after (8192, inf)`. `kern.maxfilesperproc` is 245760.
- Live adoption is still UNMEASURED.
- Precedent: `kitty.conf:588-603` records that in-process Python shims killed kitties on 2026-09-16.

**8. A dead thread can be detected cheaply without touching the socket. WEAKENED.**
- The cost re-measures fine: `netstat ... | awk '$NF=="/tmp/kitty-48854"' | wc -l` gives 1 row in 0.018 s.
- **The premise fails.** When kitty is backgrounded, the clamp covers the whole process:
  - `ps -M -p 94453` (staged kitty, not frontmost): all 7 threads at `4T`.
  - `ps -M -p 48854` (frontmost): main thread 47, the rest 31.
  - At 07:09Z, pid 610 showed `PRI 4, STAT R, %CPU 0.0`: runnable but starved (transcript).
- A live but starved talk thread leaves Recv-Q unread, so "Recv-Q > 0 for 30 s" can fire on a merely deaf kitty.
- The `sample`-shows-no-`KittyPeerMon` check must gate the page, not be optional.

**9. Steady-state traffic is low; retries are the danger. WEAKENED (minor).**
- The `pgrep 'kitten @|kitty @'` census cannot see raw AF_UNIX clients: the `python3 -c` probe in
  `handoff-fire.sh:1347-1365`, and `scripts/kitty-pane-title-overlay.py`.
- Cited bounds checked: `handoff-fire.sh:994`, `:1711-1724`; `it2-kitty:95`; `cc-resume-layout.sh:175` (unbounded).

**10. After death, an fd-based remote-control launch freezes the main thread. STANDS (from source; UNMEASURED
live).**
- The sequence is in `child-monitor.c:258-273`:
  - `self_pipe(fds,false)` creates a blocking pipe.
  - Its write end is parked in an injection queue that a dead loop never drains.
  - `wakeup_talk_loop` then writes to fd -1.
  - `simple_read_from_pipe` blocks forever.
- No "Failed to write to talk_loop wakeup fd" line appears in the 610 log (`grep -c` gives 0), so it never fired that
  day.
- The trigger set is wider than ⌘⇧B: every kitten with `allow_remote_control` (`boss.py:2367-2375`) and every
  `--allow-remote-control` launch (`:2900-2903`).

## Fatal flaw

None in the claims. The mechanism, the source citations and the absence of a fix in the staged build all check out.
The known limit stays: C3 gives **zero survival** for a crash, a kitty restart or a reboot. As an answer to the
question it must be paired with a session-layer or resume candidate.

## Missed risks

1. **The signal clobber is live today on kitty 48854 (0.48.2), whatever P1 does.**
   - Any graphics-using window closing will again stop reaping and make kitty ignore SIGTERM and SIGUSR1 (claim 5).
   - Only P2's backport or 0.49.x cures it. P1 and S1 do not.
   - Every restart path must assume SIGKILL.
2. **A dead talk thread can turn into a kitty crash.**
   - `end:` frees `talk_data.peers` (`:2085`) without resetting `num_peers`.
   - `send_response_to_peer` (`:2093-2107`) then walks the freed array and can `realloc`/`memcpy` into it when the
     main thread answers a message queued before death.
   - That is a heap use-after-free that can kill every session. P2 removes it; P1 removes it only if the errno is
     EMFILE.
3. **S1's value depends on a person.** The death came at about 02:07 CDT with the screen locked (frontmost app
   `loginwindow`, recycle-unreachable:12). Even after diagnosis, the relaunch took 1 h 28 min. "11 h to 1-2 min"
   assumes an awake operator and a restart that works first time; the real restart managed 8 of 32.
4. **P2 can busy-spin.**
   - An error raised before the dequeue (`mac_socket_check_accept`, `uipc_syscalls.c:487`) leaves the connection
     queued.
   - `poll` then returns at once, and the new `log_error` floods the log.
   - It needs a backoff on macOS too, not only on Linux.
5. **P1 without S2 turns deafness into instant PEER_LIMIT failures.**
   - Callers' retry sleeps, not the 10 s client timeout, then set the reconnect rate.
   - `it2-kitty:604-611` and the resolver are bounded, but unaudited loops elsewhere might not be.
6. **Abandoned commands still run late.** Queued `send-text` and `launch` messages run when the main thread wakes
   (`:536-551`), after the client has retried. That is a duplicate-typing hazard C3 does not address.
7. **Evidence is volatile.** `/tmp/kitty610-sample.txt` and the 22:17 samples are the only proof of thread exit and
   of the DiskCacheWrite churn. They should be copied into the repo before /tmp is cleaned.

## Recommended conviction: 48

| Remedy | Assessment |
|---|---|
| P2 (keep serving, plus the loop-utils backport) | The strongest item. Errno-independent; also cures missed risks 1 and 2. Depends on the operator adopting a patched build. |
| P1 | Cheap and now shown to raise the limit. Prevents the trigger only if it was EMFILE, which I put at about 50%. |
| S1 | Needs `sample` gating to avoid false positives under the PRI 4 clamp. Its benefit is bounded by operator availability. |
| S2 | Plausible, but the peer pile-up it targets is not demonstrated for this event. |

---

## Second pass (workflow rerun, 2026-10-01 15:10-15:25 CDT, same lens)

This file already held the first pass above, committed in 55753e737. Worker rules forbid overwriting, so this section
is appended. I made zero `kitten @` calls, sent no signals, and ran no experiments. Scratch files are in
`/tmp/sd-c3skc2/`.

### Answer

**I agree with the first pass on every verdict. Two new live measurements change the picture.**
1. **The signal clobber has already fired on today's kitty 48854, and its talk thread is still alive.** It has
   unreaped zombie children, and the count is growing. That kills P1's planned live-adoption path
   (`auto_reload_config` notifies kitty with SIGUSR1). It also means the SIGTERM step in the restart path is
   already dead weight.
2. **The broken-pipe trend just before the death argues against the EMFILE pile-up.** The main thread was
   draining held peers up to 02:06:47 CDT.

Recommended conviction: **45**.

### New evidence, per claim (claim numbers as in the first pass)

**Claim 1 (mechanism): STANDS.** Re-read:
- `/tmp/kittysrc/kitty_child-monitor.c:1821-1826` (accept error returns false), `:2058` (`goto end`),
  `:2082-2086` (`end:`).
- `free_peer` closes each peer fd (`:1850`), which fits 56 fds at 12:02 CDT.
- v0.49.2 and master: `/tmp/sd-c3-cm-0492.c` and `-master.c` both give `accept_peer` at 1995, `perror` at 1999,
  `goto end` at 2260 (grep).
- I found one more listener the thread accepts on: `talk_fd`, the single-instance socket (`:2020`). It is -1
  unless kitty runs with `--single-instance`. `ps` shows that 48854 runs with no arguments.

**Claim 2 (death window): WEAKENED; the first pass's 07:18Z upper bound holds.**
- `log show ... --start '2026-10-01 01:50' --end '02:40' --predicate 'processID == 610'` (rc 0, 629 lines):
  62 talk-thread lines; the last is `02:06:47.037 E kitty[610:2297] ... Broken pipe`.
- The main thread then handled input at 02:17:19, 02:18:25 (notification request) and 02:29:42 (window ordered
  front). No broken-pipe line followed any of them.

**Claim 3 (held fds): STANDS, and it is wider than stated.** `read_from_peer` (`:1927-1931`) queues a message
on EOF even when zero bytes were read. So the connect-then-close liveness probe (`handoff-fire.sh:1347-1365`) also
holds a peer until the main thread answers.

**Claim 4 (EMFILE): WEAKENED; about 45%.**
- **The XNU reading is right** (fresh `curl` of `xnu/main`):
  - `uipc_syscalls.c:519-541`: ECONNABORTED only for an empty queue on a listener with `SS_CANTRCVMORE` or
    `SS_DRAINING`.
  - `:543-549`: a pending `head->so_error`.
  - `uipc_usrreq.c:262`: `uipc_abort` sets `so_error` on the aborted child, not on the listener. The only other
    `unp_drop` caller is `:1115`, which serves datagram `unp_refs`.
  - `:619-633`: a `falloc` failure drops the connection.
  - So EMFILE remains the only errno the source permits.
- **Today's fd budget** (measured): `lsof -n -P -p 48854` gives 67 numeric fds: 37 CHR, 18 PIPE, 10 REG, 2 unix,
  highest fd 72. About 189 held peers would be needed to reach 256.
- **The precondition is not supported.** Broken-pipe lines per minute (CDT), each one an abandoned peer the main
  thread answered:
  - 01:54-01:57: 10, 5, 11, 26.
  - 02:02-02:06: 2, 3, 4, 1.
  - So the main thread was answering, and few abandoned peers were waiting, right up to 02:06:47.
  - EMFILE then needs about 190 new held connections after 02:06:47 and before death (at most 11.5 min).
  - Nothing logged supplies them: there are no `handoffs.jsonl` rows from 07:00:32Z to 07:14:47Z (first pass), and
    the 07:07-07:09Z probes number 15.
  - `log show` of the kernel for 02:00-02:20 CDT with `kitty|file table|maxfiles|too many` shows only AMFI and
    Safari lines.

**Claim 5 (signal clobber): mechanism STANDS; the attribution and the "0 zombies now" datum are REFUTED by a
live measurement.**
- `ps -A -o ppid=,stat= | awk '$1==48854 && $2 ~ /^Z/' | wc -l` gave 1 at 15:13:39, 4 at 15:19:32 and 5 at
  15:22:32 CDT, out of 40 children.
- pid 71018 (start 13:50:57; the 18:50:57Z split for pane 40, which has no registry entry) stayed Z across
  6 minutes of re-checks.
- `reap_children` reaps every child with `waitpid(-1, WNOHANG)` (`:1579-1590`). A zombie that persists means
  SIGCHLD went unprocessed.
- The talk thread is alive: `netstat` shows the listener row only, and RC splits worked at 19:11:34Z.
- So the clobber (`loop-utils.c:84`) fired on 48854 between the dossier's 0-zombie reading (about 14:05) and
  15:13, with no talk-thread death. Cause UNMEASURED; the first pass's DiskCacheWrite path fits.

**Claim 6 (staged build has no fix): STANDS.**
- The `diff` headers in `docs/patches/*.patch` cover 20 files; none is `child-monitor.c` or `loop-utils.c`.
- The staged `fast_data_types.so` is dated Sep 30 22:27.

**Claim 7 (P1 feasible): WEAKENED on adoption.**
- `auto_reload_config` (default 0.1, `kitty_options_definition.py:2928`) runs `kitten __watch_conf__ 48854 100`
  (pid 50324, `ps`).
- That kitten reloads by `unix.Kill(kitty_pid, unix.SIGUSR1)` (`tools/watch/api.go:223-224`, v0.48.2, `curl`).
- SIGUSR1 is a handled signal (`child-monitor.c:121`, `:1537`). `handle_signal` writes only while
  `signal_write_fd != -1` (`loop-utils.c:19`).
- Given claim 5, **editing kitty.conf will not reach today's kitty.** P1 needs one of:
  - a socket `kitten @ load-config` (`kitty.conf:23`), which the 2026-09-16 crash note (`kitty.conf:585-603`)
    makes the operator wary of;
  - the GUI reload;
  - the next start.
- Also, the watcher loads only when a window is created after the reload (`kitty_options_definition.py:2882-2883`,
  `window.py:690-701`, `:749/:751`).

**Claim 8 (cheap detection): WEAKENED (as in the first pass); one refinement.**
- Re-measured: 0.010 s, 1 row.
- `netstat -anv` has 23 columns. `options` = `00000002` (SO_ACCEPTCONN) marks the listener exactly, so S1 need not
  rely on position.
- Once 128 connections are queued, connects are refused at once (husk-panes-2026-09-30.md:88). A full backlog is a stronger
  signature of a dead thread than "Recv-Q > 0 twice".

**Claim 9 (low traffic): STANDS; two dossier facts corrected.**
- The dossier's own `/tmp/sd-c3-pgrep.txt` shows pid 37698 in 6 polls and pid 50966 in 12. Both are
  `kitten @ ... ls`.
  - At the dossier's 817 polls in 120 s (about 0.147 s each), those calls lived about 0.9-1.8 s, not "about 0.1 s".
  - The third pid, 52028, is the sampler's own `zsh -c`.
- `reso-keepalive` "running, pid 217" is stale: `ps -p 217` is empty, and `~/.reso/keepalive.log` ends at
  14:16:58 CDT.
- No hook or statusline calls RC per turn. I parsed the hook commands from settings.json: 4 hook files mention
  kitty, and the mention is a pattern or comment only. `statusline.sh:523` is a comment.

**Claim 10 (inject_peer freeze): STANDS from source.**
- `self_pipe(fds, false)` is a blocking pipe (`loop-utils.h:52-66`), read at `child-monitor.c:270-271`.
- The pane menu is not a trigger: `kitty.conf:217-218` launches it without `--allow-remote-control`.

### Fatal flaw

None in the claims. Scope is unchanged: C3 gives no session survival for (a), (b) or (c).

### Missed risks (new in this pass)

1. **Today's kitty already ignores SIGTERM, SIGHUP and SIGUSR1** (claim 5).
   - `kitty-restart-resume.py:253-261` SIGTERMs and then SIGKILLs after 10 s. Every restart is therefore a SIGKILL
     with no atexit, which leaves a stale `/tmp/kitty-<pid>` socket.
   - Zombies accumulate: 59 on 610 in 22 h, 5 on 48854 in under 2 h.
   - Only P2's loop-utils backport, or 0.49.x, cures this. That makes P2, not P1, the load-bearing item.
2. **P1's day-one claim depends on an RC call or a restart.** Neither the config edit nor "usable on day one"
   holds by itself.
3. **Someone was at the GUI 11 minutes after the death.** Kernel AMFI lines show `kitty-pane-menu-native` exec'd
   at 02:02:13 and 02:18:20 CDT. That binary is the right-click probe, which version `96d1f5219` pops before its
   `kitty @ ls`.
   - The menu then failed silently (`return 3`, stderr to nowhere).
   - So an S1 page at about 02:09 might have been seen. Who clicked is UNMEASURED.
   - This softens first-pass missed risk 3 but does not remove it.
4. **Normal `ls` latency is already 1-2 s at load 26** (claim 9). An S2 breaker that keys on latency, not
   timeouts, would trip in normal operation.

### Recommended conviction: 45

P2 with the backport is now shown necessary, by the live zombies. P1's live adoption path is measured broken. The
EMFILE precondition is contradicted by the pre-death broken-pipe trend. The detection items stay bounded by a human.

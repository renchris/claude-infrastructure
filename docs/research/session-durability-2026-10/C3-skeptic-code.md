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

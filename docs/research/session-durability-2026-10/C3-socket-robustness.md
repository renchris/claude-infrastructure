# C3: make kitty's control socket robust so the 2026-10-01 deadlock does not recur

Read-only research, 2026-10-01. Nothing was typed, closed, killed or launched. I made **no** `kitten @` calls
against the live socket. Times are UTC unless marked CDT (UTC-5).

## Answer

**The mechanism is confirmed from source and from kitty's own log. The errno is almost certainly EMFILE, and the
cheapest fix is a 6-line kitty watcher that raises kitty's soft fd limit, plus a small C patch at the next build.**

1. **Mechanism, confirmed.** In kitty 0.48.2, `talk_loop` has exactly one non-shutdown exit: `accept_peer()` returns
   false on any `accept()` error except EINTR, and the loop does `goto end` (`child-monitor.c:1821-1826, 2058, 2082`).
   The 12:02 CDT `sample` showed no `KittyPeerMon` thread, so that path ran. **v0.49.2 and master are unchanged**
   (`accept_peer` at `:1995-2001`, `goto end` at `:2260`).
2. **When it died: 07:06:47Z to 07:08Z (02:07 CDT), measured.** The talk thread (tid 0x2297) logged its last line at
   07:06:47Z (`log show ... processID == 610`). At 07:01Z `kitten @ ls` answered in 0.1 s. From 07:08Z every probe
   timed out (recycle-unreachable-2026-10-01.md:11). Nothing came from that thread for the 11 h 23 min until the
   18:29:45Z relaunch.
3. **Errno: EMFILE, conviction about 75%.** XNU's `accept()` on a healthy unix listener can fail only in `falloc`
   (EMFILE, ENFILE, ENOMEM; `uipc_syscalls.c:619-632`). A client that gives up while queued does **not** cause
   ECONNABORTED on macOS: `uipc_accept` returns 0 for a dead peer (`uipc_usrreq.c:269-291`), and `soacceptlock`'s
   result is discarded (`uipc_syscalls.c:663`). kitty never raises RLIMIT_NOFILE, and launchd's soft limit is 256.
   kitty also keeps every accepted peer's fd **until the main thread answers it** (`prune_peers`, `:1964-1968`), and
   the main thread was deaf (PRI 4, load 120+). So abandoned clients accumulate as open fds until accept hits EMFILE.
4. **A second bug made it look like a full deadlock.** On macOS the dying talk thread's `free_loop_data` sets the
   process-global `signal_write_fd = -1` (`loop-utils.c:82-84`). From then on SIGCHLD, SIGTERM, SIGHUP, SIGINT and
   SIGUSR1 are silently dropped. That explains the 59 zombies and the ignored SIGTERM. Upstream fixed this as
   kitty#10436 in commit `f3fdc21850`, shipped in **v0.49.0+**. Their trigger is different: closing a window that used
   the graphics protocol. So on 0.48.2, zombies alone do not prove the talk thread died.
5. **The staged patched build does NOT carry an accept_peer fix.** No file in `docs/patches/` touches `child-monitor.c`
   or `loop-utils.c` (`grep -n '^diff' docs/patches/*.patch`). `kitty.app.staged` was built 2026-09-30 22:27,
   about 14 h before the finding. This corrects the brief.

**Recommended design (prevent first, then detect):**

- **P1. In-process fd headroom (config only).** A global `watcher` in kitty.conf whose `on_load` calls
  `setrlimit(RLIMIT_NOFILE, 8192)` inside kitty. The fatal EMFILE then becomes kitty's own graceful
  `PEER_LIMIT=256` path (`add_peer` logs "Too many peers" and drops one client, `:1789-1806`).
- **P2. A 2-hunk C patch in the `~/ktb` build.** `accept_peer` logs the errno and keeps serving. Plus a backport of
  upstream `f3fdc21850` for the signal clobber.
- **P3. `NSAppSleepDisabled`.** Shortens the deaf episodes that fill the peer table.
- **S1. A zero-connection watchdog.** Detects a dead talk thread within about 60 s by reading `netstat` and `lsof`,
  never the socket.
- **S2. A client-side gate.** At most 4 concurrent `kitty @` calls, plus a circuit breaker that stops new
  connections while kitty is deaf or dead.

P1 to P3 prevent the event. S1 shortens it from 11 h to minutes if it happens anyway. S2 does both.

C3 does **not** make sessions survive a crash, a kitty restart or a reboot. It removes the cause of the forced kitty
restart on 2026-10-01. It is a complement to a session-layer candidate, not a substitute.

## 1. Root cause, with evidence

### 1.1 Source (kitty v0.48.2; local copies byte-identical to upstream, `diff -q` gives CM-SAME, LU-SAME, BOSS-SAME)

| Fact | Where |
|---|---|
| `accept()` error other than EINTR: `perror` to stderr (`/dev/null`), `return false` | `child-monitor.c:1821-1826` |
| `if (!accept_peer(...)) goto end;` is the only non-shutdown exit from `while (!shutting_down)` | `:2058`, `:2082` |
| `end:` runs `free_loop_data(&talk_data.loop_data)` and frees all peers; `talk_thread_started` stays true, so nothing restarts the thread | `:2082-2086`, `:1776-1781` |
| The peer limit of 256 is checked **after** `accept()` succeeds, and that path is non-fatal | `:1785`, `:1789-1806` |
| A peer is pruned only when `read.finished && !num_of_unresponded_messages_sent_to_main_thread && !write.used && !waiting_for_async_response` | `:1964-1968` |
| A client that hung up still sets `read.finished`, and the message stays queued for the main thread | `read_from_peer` `:1918-1930` |
| The main thread answers the queue in `parse_input`; until it does, the peer and its fd stay | `:520-552` |
| Listen backlog: Python `s.listen()` with no argument = min(SOMAXCONN, 128); `sysctl kern.ipc.somaxconn` gives 128 | `boss.py:230-237` |
| kitty never calls `setrlimit` | `grep -n rlimit` over launcher/main.c, data-types.c, child-monitor.c, boss.py, main.py, utils.py, launch.py, child.py, glfw.c, cocoa: 0 hits (not the full tree) |
| `launchctl limit maxfiles` gives `256 unlimited` (measured) | the GUI kitty inherits this soft limit |
| On macOS (no signalfd), `remove_signal_handlers` unconditionally sets the global `signal_write_fd = -1` | `loop-utils.c:12`, `:82-85`, `:99-109` |
| `inject_peer` wakes the talk loop, then does a **blocking** read for the peer id | `child-monitor.c:259`, `:269-271` |

**Consequence of the last row (from source, UNMEASURED live).** After the talk thread is dead, any
`--allow-remote-control` launch blocks kitty's main thread forever: `add_fd_based_remote_control` (boss.py:2854-2866)
calls `inject_peer`. ⌘⇧B is one such launch (`kitty.conf:631`). The GUI would freeze, not just remote control. The
watchdog (S1) should warn the operator off ⌘⇧B once the thread is dead.

### 1.2 XNU: which errno can `accept()` return here? (apple-oss-distributions/xnu main)

- `head->so_error = ECONNABORTED` is set only when the **listener** has `SS_CANTRCVMORE` or is draining
  (`uipc_syscalls.c:519-536`). Our listener was still listening with 128 queued at 12:02 CDT, so this is ruled out.
- A queued client that already closed is dequeued normally. `uipc_accept` "(our peer may have closed already!)"
  returns 0 (`uipc_usrreq.c:269-291`), and `soacceptlock`'s return value is discarded (`uipc_syscalls.c:663`). **So
  abandoned clients do not make `accept()` fail on macOS.** That refutes ECONNABORTED as the abandon path.
- `falloc` failure gives EMFILE, ENFILE or ENOMEM. XNU then **drops** that connection instead of re-queueing it
  (`uipc_syscalls.c:619-632`, "Probably ran out of file descriptors ... Drop the socket").
- ENOBUFS is listed only for `socreate`, not for `accept`. EBADF and ENOTSOCK would need the listen fd closed, but the
  listener row was still present at 12:02 CDT. MAC-policy EACCES is implausible for an unsandboxed app.
- ENFILE needs `kern.maxfiles` 491520 to be exhausted (measured with `sysctl`), which is implausible. ENOMEM is
  implausible with 25-31 GB reclaimable (handoffs.jsonl `admitted` rows at 06:16-07:43Z).

**So EMFILE is the only realistic errno (conviction about 75%; the remaining 25% is an unknown path I could not
read).** It needs about 190 accepted peers held at once: 256 minus kitty's baseline fds. Baseline measured now on pid
48854 with 35 sessions: **66 numeric fds** (`lsof -p 48854 | awk '$4 ~ /^[0-9]+[urw]?$/' | wc -l`). kitty 610 had 56
at 12:02 CDT, after `end:` had freed every peer. Peers pile up only while the main thread is not answering, which is
exactly the measured deaf state (PRI 4, screen locked, load 120-250; recycle-unreachable-2026-10-01.md:11-12).

**What would distinguish the errnos next time:**
- EMFILE: `lsof` numeric fd count climbing toward 256 before death.
- ENOMEM: memory pressure at that moment.
- Any errno, directly: P2 routes it to `log_error`, which, unlike `perror`, reaches the unified log. Thread 0x2297's
  `log_error` lines are visible there.

### 1.3 Unified log for pid 610 (measured)

Command: `log show --style compact --start '2026-09-30 15:29:00' --end '2026-10-01 13:30:00' --predicate
'processID == 610'` gave 35,356 lines, rc 0.

- **180 lines from the talk thread, all `write() to peer socket failed with error: Broken pipe`.** Each one is a client
  that had already timed out and left when the main thread finally answered. This is direct evidence that abandoned
  peers are held until answered.
- Bursts: 32 lines in 00:29 CDT, 52 in 01:54-01:57 CDT (06:54-06:57Z, the same minutes as the pane-19
  `recycle-held-unreachable` row at 06:55Z).
- **Last line: 2026-10-01 02:06:47 CDT (07:06:47Z).** No talk-thread line after that, for 11 h 23 min, although
  clients kept timing out (handoffs.jsonl `recycle-held-unreachable` at 09:17Z, 09:18Z, 10:33Z, 12:33Z, 15:34Z;
  `pane-close-retry.log` "kitty unresponsive" from 08:51:37Z). A slow but live thread would have logged more broken
  pipes whenever the main thread caught up.
- No "Too many peers" line, so PEER_LIMIT was never reached. That fits EMFILE (at about 190 peers) firing first.
- The `perror` line itself is absent, as expected: stderr is `/dev/null`.
- The main thread logged until 13:29:32 CDT (TextInputUI, AppKit), so the process was alive, not hung.

### 1.4 Newer kitty

- **v0.49.0, v0.49.1, v0.49.2 and master:** `accept_peer` has the same error path. The only diff is the signature and
  `get_peer_credentials` (`diff` of the extracted function bodies).
- **v0.49.0+ fix the signal clobber** (`loop-utils.c:89-93` in master: "Only clear the global write fd if it is owned
  by this loop"; kitty#10436, `f3fdc21850`, 2026-09-04).
- No upstream issue reports the talk-thread exit itself (`gh api search/issues q='repo:kovidgoyal/kitty "talk socket"'`
  returns only 2018-2019 items).
- `brew info --cask kitty` gives `0.48.2 → 0.49.1` available. Upgrading would cure zombies and SIGTERM, but not the
  thread death, and it would orphan the 0.48.2-based title-band and drag patches.

## 2. Census of our clients

**Measured steady state.** At 35 registered sessions, load 26, I polled 817 times over 120 s
(`pgrep -lf 'kitten @|kitty @'` every 0.05 s) and saw **2 distinct client processes**. A `kitten @ ls` lives about
0.1 s, so some calls were missed. My estimate is **2-6 connections/min at rest**. That is not a flood.

**Bursts and timeouts** (static read):

| Client | Bound | Retry and connection behaviour | Where |
|---|---|---|---|
| `kitten @` itself | 10 s response timeout, then abandons ("i/o timeout" at exactly 10 s) | — | recycle-unreachable:11 |
| handoff-fire `kt` / `hf_bounded` | 10 s (`HF_TIMEOUT_S`), split `launch` 45 s | a fire makes several calls: launch, send-text, ls verify | `handoff-fire.sh:994`, `:1020-1061`, `:1374`, `:1388` |
| pane→tty resolver `as_tty_classified` | 10 s per query | **5 queries, 0.3 s apart.** When kitty is deaf that is 5 abandoned peers per resolve; recycle and self-close add passes on top | `handoff-fire.sh:1711-1724` |
| `kitty_socket_accepting` probe | 2-3 s | connect then close with no command; still costs one main-thread round trip | `handoff-fire.sh:1347-1371` |
| `bin/it2-kitty` (it2 shim) | 15 s | send-text loop `continue`s on failure | `it2-kitty:95`, `:208`, `:610-611` |
| `reso-keepalive` (running, pid 217) | via it2-kitty | `session list` + `read` per pane every 240 s | `reso-keepalive:43-44` |
| `cc-kitty-wash` (StopFailure hook) | **only kitten's own 10 s**; `--no-response` for logos | ls ×2 + set-window-logo | `cc-kitty-wash:39`, `:65`, `:95`, `:118` |
| `cc-limited` | 2 s | 1 ls | `cc-limited:1131-1134` |
| `cc-where` | 15 s / 30 s | ls + focus | `cc-where:76`, `:116` |
| `cc-tui.sh` `cc_tui_rpc` | 10 s | — | `scripts/lib/cc-tui.sh:108-115` |
| `cc-resume-layout.sh` | **unbounded wrapper** (kitten's 10 s) | 1 launch per row, burst at resume | `cc-resume-layout.sh:175`, `:483`, `:494` |
| `boot-resume-launch.sh` | bounded | burst at resume | `boot-resume-launch.sh:167` |
| `cc-wedge-watch` | kitten's 10 s | one-shot per spawned pane, after a sleep | `cc-wedge-watch:152-213`, `:261` |
| `kitty-pane-menu`, title-band toggle | kitten's 10 s | operator-driven; ⌘⇧B uses fd-based RC (`inject_peer`) | `kitty-pane-menu:245`, `:274`; `kitty.conf:631` |

About 70 files reference the socket (`grep -rIcE 'kitty @|kitten @|it2-kitty|cc-kitty-socket'`). There is **no
machine-wide limiter**, and every bound only caps how long the client waits.

**Do clients hold or abandon connections? They abandon, and abandoning does not free the slot.**
- On timeout, the client process exits or is killed, and the kernel closes its end.
- If the connection was still queued, it keeps its backlog slot until accepted. The 12:02 capture showed 128 queued,
  each holding an unread 80-101 byte request.
- If it was already accepted, kitty keeps the fd until the main thread answers (`:1964-1968`). That produces the 180
  "Broken pipe" lines.
- Under deafness every retry adds another held fd, so retry loops are the accelerant.
- Estimate: 20 connections/min during a fire cluster × a 10-min deaf episode ≈ 200 held peers, which is past the
  roughly 190 EMFILE line. The 06:54-07:00Z window had a recycle plus 4 self-retire fires, goal-arms and a 52-line
  broken-pipe burst (handoffs.jsonl, pane-spawns.jsonl).

## 3. Remedies

| # | Remedy | Prevents or shortens | Cost | Conviction |
|---|---|---|---|---|
| P1 | Global kitty `watcher` raising RLIMIT_NOFILE to 8192 in-process | **Prevents** (if EMFILE) | 1 file of about 15 lines, 1 kitty.conf line, 1 bats | 75% |
| P2 | C patch: `accept_peer` keeps serving and logs errno; backport `f3fdc21850` | **Prevents** (any errno); restores SIGTERM and reaping | about 15 lines of patch, `make app` (16 s per build.md), restage | 85% that the thread survives; adoption is the operator's call |
| P3 | `defaults write net.kovidgoyal.kitty NSAppSleepDisabled -bool YES` | Shrinks deaf episodes, so fewer held peers | 1 command, next launch | 60% (recycle-unreachable:96) |
| S1 | Zero-connection watchdog plus dead flag | **Shortens**: 11 h to about 1-2 min | about 120 lines + plist + bats | 80% |
| S2 | Client gate: lockf semaphore (N=4) + circuit breaker in one shim | Prevents accumulation; ends the hang storm | about 150 lines + re-point about 6 seams + lint | 70% |
| X1 | Broker daemon owning one persistent connection | Prevents fd growth | about 300 lines of protocol work, new single point of failure, still inherits main-thread deafness | 40%; not recommended (S2 gives about 90% of its value) |
| X2 | One kitty instance per OS window | Shrinks blast radius to about 1/9 | High. Breaks cross-window moves (one process only), `cc-kitty-socket` oldest-socket discovery (`:57-75`), the drag patch (in-instance), `--desktops` layout | 35%; not recommended |
| X3 | Upgrade to cask 0.49.1 | Fixes signals only, not the thread | Loses the 0.48.2 patch line | — |

### P1 detail: the fd-headroom watcher

```python
# ~/.claude/scripts/kitty-fd-headroom-watcher.py  (kitty.conf: watcher ~/.claude/scripts/kitty-fd-headroom-watcher.py)
import resource
def on_load(boss, data):
    soft, hard = resource.getrlimit(resource.RLIMIT_NOFILE)
    want = 8192 if hard == resource.RLIM_INFINITY else min(8192, hard)
    if soft < want:
        resource.setrlimit(resource.RLIMIT_NOFILE, (want, hard))
        from kitty.utils import log_error; log_error(f'fd-headroom: RLIMIT_NOFILE {soft} -> {want}')
```

- **It runs inside kitty.** Global watchers come from `opts.watcher` (`window.py:680-705`) and are loaded with
  `runpy.run_path`, then `on_load(boss, {})` is called once (`launch.py:516-542`).
- The bundled interpreter has `resource` (`kitty-extensions/resource.so`). Measured:
  `kitty +runpy '...setrlimit(RLIMIT_NOFILE,(8192,h))'` printed `after (8192, 9223372036854775807)`. This ran the
  bundled Python only, with no GUI and no socket.
- With 8192 fds, about 256 peers plus 66 baseline fit easily, so overload hits PEER_LIMIT, which drops one client and
  keeps the thread alive.
- **Live adoption without a restart is plausible but UNMEASURED.** `auto_reload_config` runs as
  `kitten __watch_conf__ 48854 100 …kitty.conf` (pid 50324). A changed `watcher` spec makes `GlobalWatchers` reload on
  the next window creation. Test it in a sandbox kitty before relying on it.
- Verify with `log show --predicate 'process == "kitty"' | grep fd-headroom`.

### P2 detail: the C patch (add as `docs/patches/kitty-talk-thread-survives-v0.48.2.patch`, applied in `~/ktb`)

```diff
-        if (!shutting_down) perror("accept() on talk socket failed!");
-        return false;
+        if (shutting_down) return false;
+        int e = errno;
+        log_error("accept() on talk socket failed: %s (errno %d); still serving", strerror(e), e);
+        return !(e == EBADF || e == ENOTSOCK || e == EINVAL);   /* listener itself gone: stop as before */
```

Plus the 2-line `loop-utils.c` hunk from upstream `f3fdc21850`.

- No busy spin on persistent EMFILE: XNU drops the connection it failed to install (`uipc_syscalls.c:619-632`), so
  each failure consumes one queued connection and `poll` then blocks.
- Linux leaves it queued, so an upstream version should add a short backoff.
- **Filing upstream is an outbound step for the operator.** No existing issue covers it.

### S1 detail: the watchdog (launchd, StartInterval 60, never connects to the socket)

- **Dead-thread signature.** Rows in `netstat -anv -f unix` whose Addr is `/tmp/kitty-<pid>`, other than the listener,
  with **Recv-Q > 0 in two samples 30 s apart**.
  - A live talk thread reads requests within milliseconds even when the main thread is deaf, because it only polls and
    reads, so unread bytes mean nobody is accepting.
  - Measured cost: 9 ms (`time (netstat -anv -f unix | awk '$NF=="/tmp/kitty-48854"' | wc -l)` gives 1 row, the
    listener).
  - Confirm with `sample <pid> 1`: no `KittyPeerMon` thread.
- **Pre-EMFILE signature (if P1 is not in place).** kitty's numeric fd count over 180. Measured cost 89 ms
  (`lsof -p 48854 -a -d 0-1023`).
- **Do not use zombies as a signal on 0.48.2.** kitty#10436 produces them from a graphics-window close too. Measured
  now: 0 zombies among kitty 48854's 38 children.
- **Action on a dead thread:**
  - Write `~/.claude/state/kitty-rc-dead.<pid>`, which S2's breaker reads, so no new connections are made.
  - Page the operator once with the one restart command (the restart supervisor from this folder).
  - Warn against ⌘⇧B (the `inject_peer` freeze).
  - Note that SIGTERM will not work on 0.48.2 once the thread is dead; it needs SIGKILL.
- With S1 alone, the outage would have been about 2 min to detect plus however long a restart takes, instead of
  11 h 23 min.

### S2 detail: the client gate

- One shim `bin/kitty-rc` that takes the same arguments as `kitty @`. Many scripts already take a binary seam
  (`CC_KITTY_BIN`, `CC_TERM_KITTY`, `KITTY_BIN`, `CC_KEEPALIVE_KITTY_BIN`), so pointing those defaults at the shim
  covers most callers.
- Concurrency limit: `/usr/bin/lockf -t 0` on N=4 slot files (`flock` is not installed; `lockf` and `shlock` are).
- Circuit breaker: any call that times out writes `deaf-until = now+30s`; callers inside that window fail fast with rc
  124 and never connect. The dead flag from S1 makes it fail fast indefinitely.
- Turn the resolver's 5 retries into "retry only if not deaf".
- A lint fails new raw `kitty @` uses in production paths.

## 4. Events coverage

| Event | What C3 does | Coverage |
|---|---|---|
| (a) terminal crash | Removes one cause of forced kitty death: a dead talk thread that needed SIGKILL. P2 restores SIGTERM, so a planned quit runs kitty's normal signal path. Sessions still die with kitty. | **None for survival**; lowers the frequency |
| (b) kitty restart | Prevents the 2026-10-01-class forced restart (P1, P2, S2). S1 cuts detection from 11 h to minutes. Does nothing for the 8-of-32 resume shortfall (admission gate, fullscreen, nudge). | **Prevents this trigger**; no survival |
| (c) Mac reboot | Nothing; disk state is untouched | **None** |

## 5. Build cost (estimated, from file counts above)

- **P1:** 1 new file (15 lines), 1 kitty.conf line, 1 bats file; about 1 hour.
- **P2:** 1 patch file (about 15 lines), a rebuild in `~/ktb` (16 s per `kitty-title-band-2026-09-16/build.md:14`),
  and a restage through `scripts/kitty-build-swap.sh`; about 2 hours. Adoption rides the operator's planned swap or
  restart.
- **P3:** 1 operator command.
- **S1:** about 120 lines of shell, 1 plist, about 10 bats; about 1 session.
- **S2:** about 150 lines of shell, about 6 seam defaults, a lint over about 25 production files, about 15 bats;
  1-2 sessions.
- **Total:** about 3-4 agent sessions, about 450 lines, over 2-3 days. P1 and P3 are useful on day one.

## 6. Risks

- **The errno may not be EMFILE** (about 25%). P1 then does nothing for the trigger, and only P2 covers it. P2 waits
  on the operator adopting a patched build.
- **P1 live adoption is UNMEASURED.** If the global watcher does not load on a config reload, P1 waits for the next
  kitty start. The same file then also needs to be in the staged build's config.
- **A watcher bug runs inside kitty.** An exception in `on_load` is caught and logged (`launch.py:539-543`), so the
  blast radius is small, but it still runs on kitty's main thread.
- **PEER_LIMIT drops become visible as instant client failures under overload.** That is better than an 11 h outage,
  but callers must treat that rc as "deaf, retry later", which S2 does.
- **S2 can starve urgent calls (self-close `/exit`) behind slow ones.** Mitigation: a reserved priority slot.
- **Patch carrying.** A fourth local patch on 0.48.2 widens the gap to upstream 0.49.x. Rebasing all patches to
  0.49.2 later costs about 1 session.
- **The netstat signature depends on output format.** macOS `netstat` column drift would blind S1. Pin it with a
  calibration self-test against a private socket.
- **Deafness itself is not fixed by any of this, only made survivable.** Clients still wait up to 10 s while the main
  thread is at PRI 4.

## 7. Open questions

1. Which errno? Only P2's `log_error`, or an `lsof` fd series at the moment of death, can settle it.
2. Does a `watcher` added to kitty.conf load in a running kitty after `auto_reload_config`? Test in the kdw4 sandbox
   or a throwaway kitty. The operator or a permitted lane must do this; I am barred from launching kitty.
3. Is PRI 4 App Nap? Measured now: the staged kitty 94453, not frontmost, sits at PRI 4 while the operator is present;
   kitty 48854 is at PRI 47 (`ps -o pid,pri -p 48854,94453`). That points to a process-level background clamp for
   kitty instances that are not frontmost, but I have not proven that `NSAppSleepDisabled` lifts it.
4. Which RC commands set `waiting_for_async_response` and so hold peers indefinitely? Not checked (UNMEASURED).

## Deviations

- I wrote one throwaway sampler, `/tmp/sd-c3-sampler.sh`, with a shell heredoc. It is in /tmp, not the repo.
- I ran `kitty +runpy` once (bundled Python, no window, no socket).
- I made zero `kitten @` calls.
- /tmp/sd-c3-* scratch files remain.

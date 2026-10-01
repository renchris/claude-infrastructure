# C3 skeptic (operator-risk lens): socket robustness

Read-only review, 2026-10-01. I made zero `kitten @` / `kitty @` calls, signaled nothing, and launched nothing. I ran
no tmux experiment. Scratch files in /tmp were removed. Times are UTC unless marked CDT (UTC-5).

## Answer

**Verdict: C3's diagnosis mostly stands. As designed, its detect half (S1 plus S2) can make the next incident worse.
Recommended conviction: 45 (the dossier says 62).**

- **There is no fatal flaw in C3 as a complement.** P1 (the fd-headroom watcher) is cheap, and it is low-risk once its
  live reload is tested.
- **S1 plus S2 has a design defect that has to be fixed before it ships.** S1 can label a live but starved talk
  thread as "dead". It then writes an indefinite dead flag that S2 obeys, and it pages the operator to restart kitty.
  That turns a deaf episode that would have healed in 10 s to 12 min into an outage we caused ourselves. The restart
  it recommends is the procedure that brought back only 8 of 32 sessions today.
- **"P1 and P3 usable on day one" is half wrong.** P3 needs a kitty relaunch. P2 needs a build swap, which is also a
  relaunch. So 2 of the 3 prevention layers only arrive through the event that cost 24 sessions today, unless the
  resume chain (C2) is fixed first.
- **The death window and the EMFILE errno do not fit together as stated.** One of the two claims has to give, and
  P1's day-one value depends on the errno being EMFILE.

## The scenario where adopting C3 makes the next incident worse

1. It is night and the screen is locked. That is the condition that drops kitty to PRI 4 (recycle-unreachable:12:
   "frontmost app is `loginwindow`"). Load is 150-250.
2. The clamp covers the whole process, not just the main thread. **Measured:** `ps -M -p 94453` shows all 7 threads
   of the non-frontmost kitty at `4T`. So the talk thread starves along with the main thread.
3. Queued rows on `/tmp/kitty-<pid>` keep Recv-Q > 0 across two samples 30 s apart. S1 reads that as a dead thread.
   - The dossier's premise is "a live talk thread reads requests within milliseconds even when the main thread is
     deaf" (C3 §S1). That premise is UNMEASURED under the clamp.
   - The `sample` check that would tell starved from dead is listed only as a "Confirm with" line. It is not a gate
     on the action.
4. S1 writes `kitty-rc-dead.<pid>`. S2's breaker then fails every gated call **indefinitely**: recycle, handoff,
   self-close and pane close. S1 pages "restart kitty", and on 0.48.2 that has to be SIGKILL.
5. Without C3, the same episode heals when the main thread is scheduled again (deaf episodes of 10 s to 12+ min,
   recycle-unreachable:12). With C3, RC stays blocked until someone kills kitty. The kill ends every in-flight turn,
   background Bash, Monitor, subagent and Workflow, and the resume chain brings back 8 of 32
   (kitty-deadlock-recovery plan § "Restart result").

The same harm follows even when the thread really is dead, because the page comes too early:

- **The fleet is degraded, not dead, after the thread dies.** `git -C ~/Development/claude-infrastructure log --all
  --since=2026-10-01T07:08Z --until=2026-10-01T18:29Z | wc -l` gives **405 commits**. Per CDT hour: 02h 117, 03h 62,
  04h 47, 05h 26, 06h 25, 07h 61, then 1-25 per hour. A restart page at 02:10 CDT would trade the fleet's most
  productive hours for a mass kill.
- **The page reaches nobody.** `log show … processID == 610 AND eventMessage CONTAINS "CursorUIViewService"` puts
  the first kitty text input after 02:07 CDT at **10:30 CDT** (a proxy for the operator typing). The restart came at
  13:29 CDT. So the realistic gain on 2026-10-01 was at most about 3 h, not "11 h to 2 min".
- **The "one restart command" does not exist yet.** `kitty-restart-supervisor.py:26-28` hardcodes `LEAD_SID` and
  `OLD_KITTY = 610`, and `kitty-restart-resume.py:24` hardcodes `D = "/tmp/inboot-2026-10-01"`. They are one-offs.

## Verdict per key claim

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 1 | The talk thread's only non-shutdown exit is `accept_peer()` returning false; 610 took it; v0.49.2 and master are unchanged | **stands** | `/tmp/kittysrc/kitty_child-monitor.c:2058` is the only `goto end`. `curl …/master/kitty/child-monitor.c` gives `accept_peer` at :1995-2001 and `goto end` at :2260, the same error path. |
| 2 | The thread died between 07:06:47Z and 07:08Z; RC was dead for 11 h 23 min | **weakened** | See the first note below the table. |
| 3 | kitty holds an abandoned peer's fd until the main thread answers | **stands** | `prune_peers` at :1968. Every queued message gets a response at :541-550, which decrements the counter at `send_response_to_peer`. `grep -rIn 'wait-for-child-to-exit\|select-window' bin scripts hooks` finds no async RC users, so this is accumulation during deafness, not a leak. |
| 4 | EMFILE is the only realistic errno (about 75%) | **weakened** | I did not re-read the XNU source. The timing in the first note below says EMFILE implies a death later than claim 2 allows. Either claim 2 or this one has to give, and P1's prevention value rides on this one. |
| 5 | On macOS the dying thread disables all signal handling; fixed upstream in v0.49.0 | **stands** | `kitty_loop-utils.c:84` sets `signal_write_fd = -1` inside `#ifndef HAS_SIGNAL_FD`, and `free_loop_data` calls it at :108. |
| 6 | The staged build carries no `accept_peer` fix | **stands** | `grep -n '^diff' docs/patches/*.patch` lists no `child-monitor.c` or `loop-utils.c`. |
| 7 | P1 (raise the fd limit in-process with a global watcher) is feasible without a patched build | **stands, with costs** | See the second note below the table. |
| 8 | A dead talk thread can be detected without touching the socket | **weakened** | `ps -M -p 94453` puts every thread at PRI 4, so "Recv-Q > 0 for 30 s" also fits a starved but live thread. With P1 in place, a full peer table is handled by accept-then-`nuke_socket` (:1800-1801), which leaves no queued rows, so S1 cannot see that failure. |
| 9 | Steady-state client traffic is low; the danger is retries | **stands** | `it2-kitty:604-611`: a failed send-text sleeps and `continue`s to a fresh attempt. `reso-keepalive:54` types a fixed NUDGE through it2-kitty. |
| 10 | After the thread dies, ⌘⇧B (fd-based RC) freezes kitty's main thread | **stands (from source; UNMEASURED live)** | `inject_peer`: a blocking `self_pipe(fds,false)` at :259, then a blocking read at :271. `start_talk_thread` returns 0 at :1777 because `talk_thread_started` stays true, so nothing restarts the thread. |
| E1 | "S1 cuts detection from 11 h 23 min to about 1-2 min" | **weakened** | Detection is not the same as action. The first operator input was at 10:30 CDT and the restart at 13:29 CDT, so the realistic gain was at most about 3 h. The page's action is itself harmful (see the scenario above). |
| E2 | "P1 and P3 are usable on day one" | **refuted for P3** | C3's own table (§3, P3 "next launch") and recycle-unreachable:97 ("takes effect only at the next kitty launch"). P1's live adoption is UNMEASURED (C3 §7 Q2). |

**Note on claim 2.** `log show … 'processID == 610 AND threadIdentifier == 8855'` gives **142 lines** (141 Broken
pipe; the dossier says 180). The last line is **02:06:47.037 CDT**, which matches the dossier.

- The talk thread logged answer passes at 02:02, 02:03, 02:04:02, 02:04:30 and 02:06:47 CDT, with only 1-4 abandoned
  peers each. After each pass, the held peers drop to about 0.
- Only 1 handoff row and 0 pane-spawn rows fall in 07:01-07:13Z (grep of `handoffs.jsonl` and `pane-spawns.jsonl`).
- **So the roughly 190 held peers EMFILE needs could not exist by 07:08Z.** At the dossier's 2-6 connections/min, they
  take 30-95 min of total deafness.
- The 07:08Z bound comes from probes that cannot tell a deaf main thread from a dead talk thread.
- "RC dead" also does not mean "fleet dead": there were 405 commits in that window.

**Note on claim 7.** `on_load` runs once per path per process (`kitty_launch.py:534-538`), and only at the next
window creation (`kitty_window.py:749`). It has three costs:

- **Adoption is a live reload.** It needs a kitty.conf edit, and kitty.conf is a symlink into the shared checkout. A
  live reload has reverted operator runtime state before (`config/kitty.conf:758-760`, `:1173-1177`).
- **Config rollback cannot detach the watcher.** `kitty_window.py:697` is `self.ans = load_watch_modules(...) or
  self.ans`, so an empty watcher list keeps the old watchers.
- **The raised limit stays until a restart.**

## Missed risks (not in the dossier's risk list)

1. **S1 false positive leads to a lockout we cause ourselves.**
   - Cause: the clamp covers the whole process (measured above).
   - The dead flag is indefinite and S2 obeys it.
   - Fix before shipping: write the flag only after `sample <pid> 1` shows no `KittyPeerMon` thread; give the flag an
     expiry; never page a kill on netstat evidence alone.
2. **The restart page converts a degraded but productive fleet into a mass kill.**
   - Evidence: 405 commits during the dead window; today's restart chain brought back 8 of 32.
   - Fix: S1's page should say "RC is dead; sessions are still working; restart once C2's restore is proven". It
     should not prescribe an immediate restart.
3. **The page lands while the operator is away.**
   - The trigger condition, a locked screen with kitty at PRI 4, is the operator-absent state.
   - So most of S1's headline gain is illusory, unless an agent could act on the page. The auto-mode classifier
     forbids an agent from killing kitty, because that kills 32 live sessions.
4. **Adoption is gated on a restart.**
   - P2 (build swap) and P3 (next launch) both need a kitty restart, which costs 24 of 32 sessions today.
   - Sequencing has to be C2 (a working restore) first; C3's P2 and P3 only at a restart that is happening anyway.
   - P2's rollback (swapping back) is a second restart.
5. **P1 removes thread death's cap on stale-command replay.**
   - A live talk thread keeps reading and queueing launch and send-text requests through a long deaf episode, up to
     256 peers (PEER_LIMIT). The main thread runs them all late, after callers have already retried.
   - There is a measured precedent for duplicates: `handoff-fire.sh:1012-1014` ("the 0.8s retry created a SECOND
     one"; fire 4b0095d1ee73 "left two transcripts 12s apart").
   - Late or doubled `reso-keepalive` NUDGEs each start an extra turn, which burns quota.
   - S2's breaker should land before P1, or with it.
6. **P1 turns overload into fast failures.**
   - With P1, a full peer table refuses clients instantly instead of after 10 s, so retry loops spin faster
     (`it2-kitty:604-611`; `as_tty_classified` retries every 0.3 s).
   - A long-deaf main thread then looks healthy to S1 (point 8 above).
7. **S2 stays half-migrated for a long time.**
   - **Measured:** 49 production files under bin, scripts, hooks and lib contain `kitty @` or `kitten @`. 19 of them
     have uncommented raw calls and no binary seam, for example `cc-kitty-wash` (a StopFailure hook),
     `kitty-pane-menu`, `kitty-confirm-close`, `cc-where`, `cc-limited` and `limit-recover/lr-fleet.sh`.
   - Until all of them are migrated, the breaker's promise of "no new connections while dead" does not hold.
8. **P1's adoption path is a live config reload on the operator's terminal.**
   - A malformed line shows kitty's bad-config overlay (`boss.py` `show_bad_config_lines`).
   - Any runtime-only state that is not in the file is reverted, as has happened before (`config/kitty.conf:1173-1177`).
9. **Opportunity cost.** C3 spends 3-4 agent sessions and gives no session survival for any of the three events (C3
   §4). The operator's question is survival.

## Recommended conviction: 45

| Part | Recommendation |
|---|---|
| Mechanism | Keep. |
| P1 | Ship it, but only after one sandbox test of the live reload. |
| P2 and P3 | Defer to a restart that is happening anyway, after C2. |
| S2 breaker | Ship it before or with P1. |
| S1 | Rework it before shipping (gate on `sample`, expiring flag, advice instead of a restart page). |

The drop from 62 comes from four things:
- The death-time and EMFILE tension (claims 2 and 4).
- P3 is not day-one.
- S1's false-positive path and harmful action.
- Restart-gated adoption.

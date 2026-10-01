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

---

# Second operator-risk pass (independent re-run, 2026-10-01 15:10-15:25 CDT)

The workflow re-ran this skeptic step, and this path already held the first pass above (committed in 55753e737).
I appended this pass instead of overwriting it. Read-only: zero `kitten @` calls, nothing signaled, nothing launched,
and no tmux server started. The only scratch file is `/tmp/sd-c3r-log.txt`.

## Answer

**I agree with the first pass and go lower: recommended conviction 40 (the dossier says 62).** C3 is worth having as
a narrow complement: P1 after a sandbox test, and P2 at a restart that is happening anyway. But three of its headline
values fail the operator lens:

1. **"S1 cuts 11 h 23 min to 1-2 min" mislabels the gap.** Detection already took about 1 minute. The 11 h went to
   telling "dead" from "deaf", plus nobody being able to act. In addition, a netstat dead-socket detector that files
   a "restart kitty" need went live in handoff-fire at 15:15:34 CDT today, so S1 would be a second detector that can
   disagree with the first.
2. **S2's breaker, as specified, sits under a measured rc contract and breaks it.** Its rc 124 means "may have acted"
   for a call that certainly did not act. It will also be half-migrated for weeks: the code under it changes several
   times an hour.
3. **P1's prevention value depends on the errno being EMFILE, and the kitty log makes EMFILE less likely.** The new
   bound is below.

**No fatal flaw**, because C3 never claims survival. As an answer to the question (survive a crash, a restart or a
reboot), it delivers nothing for any of the three events (dossier §4).

## The scenario where C3 makes the next incident worse (adds to the first pass)

S1 fires under the same condition that shuts the resume gate.

1. The trigger condition is real and measured: screen locked, load 120-133 on 10 cores at 07:08-07:09Z
   (recycle-unreachable-2026-10-01.md:11-12), which is 12-13 per core.
2. S1 pages "restart kitty". Where does the page land?
   - Rung 1 of `bin/cc-desk-page` is `cc-notify --role desk`, which types into a pane over the dead socket.
   - Rung 2 is Notification Center only. `~/.config/lr-page/` does not exist (`ls` => No such file), so there is no
     Pushover. In `idl.jsonl`, 13 of 14 `cc-desk-page` rows went to `notification-center` and 1 to `none`.
   - kitty's own notifications are refused: `log show … processID == 610` at 02:18:26 CDT says "Notifications are not
     allowed for this application".
3. Suppose the operator acts. The restart lands at 12-13 load per core. `capacity-admit.sh:92` defaults to a ceiling
   of 2.0 per core, and the recovery plan (`kitty-deadlock-recovery-2026-10-01.md:38`) records the result: "round 1
   launched 10 and shed 22, and round 2 launched 0".
   - So a restart run at the moment S1 fires restores no more than today's 8 of 32 until load falls.
   - The admitted resumes then push load back up.
4. Without C3, RC stays dead but the sessions keep working (the first pass counted 405 commits in the dead window).
   With S1 and its "one restart command", a degraded fleet becomes a mostly dead one, at the worst hour.

**The "one restart command" is unsafe to reuse as-is.**
- `kitty-restart-supervisor.py:26-28` hardcodes `LEAD_SID` and `OLD_KITTY = 610`, and `:20` imports
  `/tmp/kitty-restart-resume.py`, which a reboot wipes.
- `:84` `if krr.alive(OLD_KITTY)`: after a reboot pid 610 is likely reissued to another process (pid 610 is free
  right now: `ps -p 610` returns nothing). The supervisor would then report "kitty was not restarted; fleet untouched"
  and open no recovery lead. This is the repo's own lesson "a stale pid is re-aimed, not defused"
  (`.claude/rules/agent-operating-lessons-situational.md:121`).

## Verdict per key claim (second pass)

| # | Claim | Verdict | Evidence (this pass) |
|---|---|---|---|
| 1 | Only non-shutdown exit is `accept_peer()` false; v0.49.2 and master unchanged | **stands** | `/tmp/kitty-src-0482/child-monitor.c:1821-1826`. The listener is a default blocking Python socket (`boss.py:230-237`, no `setblocking`), so EAGAIN is not a path. |
| 2 | Died 07:06:47Z-07:08Z; RC dead 11 h 23 min | **stands** (timing). I found a looser upper bound that is actually proven. | Main-thread tid is `15e6`: all 45 AppKit "order window front" lines in 01:50-02:20 CDT are on it (`/usr/bin/log show … processID == 610` => 617 lines). It ran Python at 02:18:25 CDT. `parse_input` runs every tick (`child-monitor.c:1406`) and answers every queued message (`:522-552`). So a live thread would have logged Broken pipe for the 9 probes that timed out at 07:08-07:09Z. There are none after 02:06:47 CDT. Therefore the thread was dead by about 07:08Z, and certainly by 07:18:25Z. |
| 3 | Abandoned peers hold fds until the main thread answers | **stands** | Same `:522-552`; the first pass found no async RC users. |
| 4 | Errno is EMFILE (about 75%) | **weakened** (more strongly than in the first pass) | Combine row 2 with the 07:06:47Z answer pass, which drains the message queue. EMFILE then needs about 190 new held peers inside roughly 1-11 min, which is at least 16/min and over 100/min if death was near 07:08Z. Measured rate at rest is 2-6/min; there was 1 handoff row and 0 pane-spawn rows in 07:01-07:13Z (first pass). No other "open files" error appears in those 617 lines (grep => 0), though stderr is /dev/null. If it is not EMFILE, P1 is a placebo that the operator would count as "deadlock prevented". |
| 5 | Dying thread disables signals; fixed in v0.49.0 | **stands** | First pass. |
| 6 | Staged build has no `accept_peer` fix | **stands, and adds a coupling** | `kitty-build-swap.sh:4-6, 11-23`: one bundle carries the title band, the upstream-defects patch and (under C3) P2. There is one yes/no, one swap "at a reboot the operator is already doing", and a rollback that is "the exact inverse". If the band disturbs the drag (the operator's top property), rolling it back removes P2 too. |
| 7 | P1 is feasible without a patched build | **stands, with a one-shot cost** | `kitty_launch.py:524-534` caches the module per path, or `False` if loading fails, before `on_load` runs. A buggy first version cannot be retried without a kitty restart or a new file name. `kitty_window.py:697` keeps the old watchers. Inheritance is low-risk: Claude raises its own limit (`ulimit -n` in this session => 1048576), so only plain zsh panes see the 8192. |
| 8 | A dead thread can be detected without touching the socket | **weakened** | Re-measured with `ps -M`: the non-frontmost staged kitty 94453 has all 7 threads at `4T`. The frontmost kitty 48854 has its main thread at 47T and the others at 31T. So a starved thread at PRI 4 is real. The netstat format still parses (12 ms). The same detector already shipped (see M1). |
| 9 | Steady traffic is low; retries are the danger | **stands** | `it2-kitty:609-611`: a failed send-text sleeps, then `continue`s. |
| 10 | ⌘⇧B freezes the main thread after the thread dies | **stands (source only)** | `kitty.conf:631` uses `--allow-remote-control`. |
| E1 | S1 cuts detection to 1-2 min | **refuted as stated** | An agent measured the deaf socket at 07:08-07:09Z, about 1 min after death (recycle-unreachable:11). `kitty-pane-menu:926-945` already alerts when kitty is unreachable (a3555936b). `pane-close-retry.log` has 47 "unresponsive/timeout" lines between 08:51Z and 18:29Z. What was missing: the dead-vs-deaf diagnosis (the `sample` at 12:02 CDT, `/tmp/kitty-sample-2026-10-01.txt`), restart tooling (the `/tmp` scripts have mtimes 13:01-13:18 CDT), and a resume chain that restores everything. |
| E2 | A "one restart command" exists for S1 to page | **refuted** | Hardcoded pid, SID and `/tmp` paths (see the scenario above). `kitty-restart-resume.py:227-240` also waits up to 4 h for in-flight landings before it signals. |

## Missed risks (new in this pass)

1. **M1. Two detectors, two thresholds, two restart prompts.**
   - Commit e66bf5760 went live at 15:15:34 CDT (`git reflog`: fast-forward). `handoff-fire.sh:1404-1430` reads
     `netstat` and calls a full queue (128, `CC_KITTY_WEDGED_QUEUE_N`) "STUCK".
   - `:12437` then files the cc-backlog need "restart kitty (control socket stuck: queue full)".
   - S1's trigger is any Recv-Q > 0 for 30 s. That is looser, and it is the one that can fire on a starved thread.
   - The operator would get disagreeing verdicts. C3 should reuse `hf_kitty_queue_depth` and its threshold rather than
     add a second detector.
2. **M2. S2's rc 124 is the wrong outcome code.**
   - In handoff-fire, 124 means "kitty may have CREATED the pane; never retry" (`handoff-fire.sh:14740-14746`).
   - The adopt-probe that resolves that ambiguity is tri-state, and "CANNOT TELL" needs `kitty @ ls` (`:14762`), which
     the open breaker also refuses.
   - So a fire that certainly sent nothing is handled as "maybe launched" and aborted, not retried.
   - With any other rc, `it2-kitty:609-611` retries a refusal that returns instantly, which makes a fast loop.
   - The repo has measured precedent for this contract going wrong: "one fire launched two sessions while reporting
     'Nothing was launched'" (`:14744`), and fire 4b0095d1ee73 (`:1034`).
   - Fix: S2 needs its own rc and marker ("breaker-open: not sent"), with callers updated before the breaker can trip.
3. **M3. A global 30 s breaker turns one slow but healthy call into a fleet-wide outage.**
   - Launches legitimately outlast 10-15 s under load. That is why `HF_SPLIT_TIMEOUT_S` is the inner bound plus 30 s
     (`:1038`).
   - A bound that was too tight already refused "69 of 297 fires" (`:1034`).
   - Fix: key the breaker per socket, and only on probe-class (`ls`) timeouts.
4. **M4. The shim is a second thing that can jam, and nothing watches it.**
   - A stale `deaf-until`, a slot left locked, or a parse bug would hold every recycle and self-close while kitty is
     healthy. That is the same symptom as 2026-10-01.
   - S1 watches kitty, not the shim, so the next diagnosis would start by suspecting kitty.
5. **M5. Half-migration under heavy churn.**
   - Measured: 46 production files make raw `kitty @`/`kitten @` calls (grep), and 36 reference a binary seam.
   - 54 commits touched `handoff-fire.sh` or `it2-kitty` in 7 days (`git log --since=2026-09-24`).
   - `handoff-fire.sh` grew by about 290 lines during this review (the 15:15 fast-forward). Every converge is live for
     about 32 sessions.
   - While migration is partial, the careful callers obey the breaker and the raw callers keep connecting. That is
     the opposite of what S2 is for.
6. **M6. The operator's own right-click menu.**
   - `kitty.conf:217-218` runs `bin/kitty-pane-menu`, which uses socket RC.
   - Outside S2, the menu bypasses the breaker. Inside S2, any agent's timeout disables it for 30 s, and an S1 dead flag
     (including a false positive) disables it indefinitely.
   - This is C3's only muscle-memory exposure, and the dossier does not scope it. C3 is otherwise clean on title bars,
     drag, fullscreen, scrollback and copy/paste, and that is to its credit.
7. **M7. P1/P2 widen a check-then-type race (derived from source; UNMEASURED live).**
   - `it2-kitty:788-789` and `:836-837` read the pane and refuse to type into a permission modal, then send the text.
   - A live talk thread with a deaf main thread can hold that send for minutes, so the check is stale when the
     keystrokes land.
   - `reso-keepalive:54`'s NUDGE ends in Enter.
   - Today, thread death caps how long a send can be held. With P1 or P2, only PEER_LIMIT (256) caps it.
8. **M8. P1's adoption path has a known hazard, and so does testing it.**
   - The adoption path is the shared `config/kitty.conf`. Edits reach the live terminal within about 100 ms of a
     converge (`config/kitty.conf:758-760`), and a reload once reverted the operator's zoom "every one to three
     minutes, all day" (`:1170-1177`).
   - The kdw4 sandbox reads its own `/tmp/kdw4/config/kitty.conf` (measured from the `__watch_conf__` args). But the
     watcher only loads when a window is created, so a test needs either a mutating RC call on the operator's sandbox
     or a GUI kitty launch, and the screen is shared with the operator.
9. **M9. Quota.** S1 asks for a restart, and a restart means a mass resume. That is about 32 cold-cache resumes plus a
   nudge turn each, roughly 3-6 M cache-write tokens (ESTIMATED: 32 sessions × 100-200 k context; UNMEASURED). C3
   has no pacing of its own.

## Recommended conviction: 40

| Part | Recommendation |
|---|---|
| Order | C2 (a restore that brings back 32 of 32 under a realistic ceiling) before any C3 piece that can prompt a restart. |
| P1 | Ship it as a drop-in with a new file name per attempt, after one sandbox test. Label it "only if EMFILE". |
| S1 | Diagnosis only. Reuse `hf_kitty_queue_depth`, gate on `sample` showing no `KittyPeerMon`, use an expiring flag, and never prescribe a restart while load per core is above the restore ceiling. |
| S2 | Defer until its rc contract is pinned in the handoff-fire and it2-kitty bats. It must be per socket, keyed on probe timeouts, and exclude the operator's menu. |
| P2, P3 | Only at a restart that is already happening. Offer P2 in a build without the title band, so the two decisions are separate. |

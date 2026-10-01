# C2 skeptic, operator-risk lens (2026-10-01)

Read-only review of `C2-restore-command.md`. Every number is labeled **measured** (with the command) or **estimated** (with the method). UNMEASURED means not checked.

## Answer first

**No finding refutes C2 as a whole. As written, though, it would make some incidents worse. Recommended conviction: 55, down from 70.**

- The dossier's evidence holds up. 9 of its 10 claims stand on re-measurement. Two are weakened: the 1-of-31 delivery count, and the restart time, which leaves out the land wait.
- The design adds new operator risk the dossier does not list. The worst one: the zero-command crash trigger cannot tell a crash from a deliberate quit. On this box `mode=resume` is already set, so landing C2 turns ⌘Q from a stop button into "everything comes back within 5 minutes, again and again".
- Four other new failure modes are concrete and cheap to fix, but each would hurt the first time:
  - `cc-reaper` kills the launchd restore after 600 s.
  - The 30-minute wait-and-retry widens a window in which a session can be launched twice.
  - Nothing stops two restore drivers from handling the same event.
  - The retire filter loses a session whose recycle was cut off mid-flight.

## Verdicts on the key claims

| # | Claim | Verdict | Evidence (re-measured here) |
|---|---|---|---|
| 1 | Round 1 refused the 11th session at 2.05/core, and the layout shed the tail | stands | idl.jsonl row 2026-10-01T18:33:53Z: `"load 20.49 on 10 cores = 2.05/core > ceiling 2.0/core (refusal 1 of budget 3)"`, caller cc-resume-layout. The budget-of-3 design (capacity-admit.sh:36-38) was bypassed by the shed-on-first-refusal at cc-resume-layout.sh:250-252. |
| 2 | "8 of 32" means 10 launched minus 2 that retired themselves | stands | `~/.claude/watchdog/teardown/16798199….json` mode=terminal ts 18:33:14Z; 40ebc527 ts 18:33:39Z (jq). |
| 3 | 5 sessions resurrected, 4 still alive | stands | pane-spawns.jsonl resume-layout rows: 16798199, 3a06361f, 40ebc527, 4433afc6 and d86e6bd4 were each launched twice (`grep -o sid=… \| uniq -c`). `ps -o etime= -p 71342,43478,50279,58151` shows all 4 alive at 41 to 44 min; registry rows 12, 13, 14 and 15. |
| 4 | Only 1 of 31 recovery prompts reached a transcript | **weakened** | By 14:22 a second prompt had landed. 13d7be20 has `queue-operation enqueue` "kitty was restarted at 13:29…" at **19:12:56Z, 23 min after the 13:50 send**. `~/.reso/keepalive.log` shows `14:12:56 nudged idle kitty:32` at that second: the keepalive's double Enter submitted the stale prompt left in the composer. The live hazard the dossier called UNMEASURED has now been observed once. |
| 5 | Fullscreen by window id gave rc 0 on 8 of 8 | stands (rc only) | finish.log has 8 `rc=0` lines. Only 4 were checked on screen (plan:39). Whether it acts on the matched window or the focused one is still open: kitty boss.py:1351-1356 uses `window_for_dispatch`. Behavior on a locked screen: UNMEASURED. |
| 6 | Tombstones caught 19 of 32 | stands | Census of roster sids with `endedAt >= 1790879360` returns 19. |
| 7 | Claude Code itself flagged 10 sessions with lost background shells; a naive rule flags 24 | stands, with a correction | 10 confirmed: grep over the post-18:30Z records of the 32 transcripts. The dossier says the notice "wakes the session". **Only 3 of the 10 wrote any assistant record after it.** 7 (68691067, 89bdedfa, 90b6aee4, f8b54aee, aee9bc26, dcbd2f8e, f4c84c9d) have the notice dequeued as a user record, transcripts last written 13:39 to 13:42, and are idle now (`✳` titles in 1 `kitten @ ls`, 14:22). This supports a nudge. It also shows that a user record in the transcript does not prove a turn ran, so C2's confirmation step (§2.7 step 4) must wait for an assistant record, not the nonce alone. |
| 8 | 3 keepalives and 5 pages for one event | stands, and is worse | keepalive.log shows 3 starts; 5 `undelivered-*.page` files. **Two keepalives are still running** (`ps`: pid 217, etime 31:30; pid 94882, etime 39:01) and still nudging pane 32 (14:12:56, 14:13:26). cc-reaper TERMed a third at age 717 s (`cc-reaper.log` 18:47:26Z). |
| 9 | At 6/core, 25 of 25 admitted, peak 3.28/core | stands | idl capacity-admit rows from 18:38:56Z to 18:47:08Z: 26 admitted, 0 refused, max `3.28/core (ceiling 6/core)`. |
| 10 | The `.start` bug is live | stands | `~/.claude/autonomy/reboot-2026-10-01.start` holds `1790878061` and then `1790878061 kalloc1024_gb=1.12`, which boot-resume.sh:298-299 rejects. |
| 11 | Planned restart takes about 10 min to the full fleet | **weakened** | The estimate leaves out the land wait, which today took **13 min 35 s** (run.log 13:15:47 armed, 13:29:22 kill; kitty-restart-resume.py:228-243 waits up to 4 h). The deaf fleet stays deadlocked throughout. Realistic total: about 25 min (estimated: measured wait plus the dossier's 10 min). |

## Fatal flaw (scoped)

**This is fatal to the zero-command crash trigger as specified, not to C2.**

The detector (§2.1, steps 3 and 4) fires when the main kitty K is gone, K started after boot, and no `events/K.done` exists. It does not require any evidence that K crashed: the `.ips` report is only one of three possible anchors.

A deliberate quit therefore passes the detector:
- ⌘Q on this fleet shows a "Quit kitty?" dialog (kitty-quit-research:15; kitty.conf:964 `confirm_os_window_close -1`), so a quit is a confirmed, deliberate act.
- `cat ~/.claude/autonomy/boot-resume/mode` returns `resume`, and `launchctl list` shows `com.claude.boot-resume` loaded.

So within 300 s of a deliberate quit, C2 would do all of this:
- run `open -n` on kitty;
- resume about 32 sessions;
- nudge about 12 of them to "Run /limit-recover now … continue the task".

Each relaunch is a new K with no `.done` marker, so quitting again repeats the cycle. Quitting kitty is the operator's natural stop button for a runaway fleet: quota burn, a bad deploy, an account cliff. It is also a step the operator already has pending: adopting the staged build (pid 94453) means quitting the main kitty. C2 would race that by reopening `/Applications/kitty.app`.

**Fix:**
- Require positive crash evidence: a `kitty-*.ips` newer than K's last heartbeat (cc-resume-classify.py:116-141 already finds it), or a jetsam record.
- Without that evidence, page only.
- Gate the crash trigger behind its own opt-in file.
- Document an off switch.

## Scenarios where adopting C2 makes the next incident worse (missed risks)

1. **cc-reaper kills the launchd-run restore mid-launch.**
   - Why it qualifies: the plist runs `/bin/bash …/boot-resume.sh` under launchd (`plutil -p` on the plist). cc-reaper TERMs any launchd-parented bash older than 600 s whose argv misses `GARBAGE_WL` (cc-reaper:917, :933). `boot-resume` is not on that list (cc-reaper:713).
   - It has happened to other launchd jobs: nightly-regression was TERMed 8 times (cc-reaper:904-910), public-publish at 919 s (cc-reaper:710-712), and today's boot-resume keepalive at 717 s.
   - C2 runs long enough to hit it: the crash and reboot restores run inside that job, and C2's own estimates (10 to 15 min, plus a start gate of up to 10 min and a 30 min deadline) pass 600 s.
   - The damage: when the job's bash dies, launchd reaps its process group (boot-resume.sh:550), so the layout dies mid-launch.
   - It is intermittent: sweeps are sparse (18:29Z and 18:45Z today), so some events escape. That is the hardest kind of failure to diagnose.
   - Fix: run the event restore from Python, as cc-restore does, or add `boot-resume` to `GARBAGE_WL`.
2. **Wait-and-retry widens a window for duplicate sessions.**
   - Ownership is checked once, for every row, before the first launch (boot-resume.sh:455-473).
   - Neither cc-resume-layout.sh nor reso-resume-one checks again for a live holder (`grep -n holder` finds 0 hits in both).
   - C2's retry loop stretches the gap between check and launch from about 7 min to as much as 30 min.
   - Today the lead stepped in mid-restore with a second driver (`inboot-finish.py`). An operator or agent running /resume-sessions in that window is blocked by the hand-path fence (boot-resume-launch.sh:257-292). The layout is not, so it later launches the same session a second time, giving two writers on one transcript.
   - Fix: call `lr_holder_count` for each row just before its launch.
3. **Two drivers can handle the same event.**
   - The only guard is `events/K.done`, which is written when the restore finishes, not when it starts.
   - A 300 s tick that lands in cc-restore's 26 s kill-and-relaunch, or during its roughly 10 min restore, sees K dead and starts a second restore of the same roster.
   - Fix: write an in-progress claim and take one global restore lock before sending SIGTERM.
4. **The retire filter turns resurrection into loss for a recycle that was cut off.**
   - The recycle marker is written before `/exit` (handoff-fire.sh:15405-15407).
   - Several aborts after the marker leave the session alive (:15408-15423).
   - The successor is typed into the pane later by a watcher through the terminal API (:2761, :8674).
   - If kitty dies between the marker and the relaunch, C2 drops the old sid, because it counts a recycle as retirement (§2.2). The successor never existed, so all that remains is a line in a page.
   - Successors do fail: handoffs.jsonl has 8 `recycle-dead` rows.
   - Fix: count a recycle as retirement only when the successor sid is in the roster, or has a transcript newer than the marker.
5. **The heartbeat can freeze.**
   - The rule "keep the previous file if the row count fell by more than 2" has no time limit. Closing a single 2x2 window drops 4 rows.
   - Measured upper bound: **350** five-minute windows with 3 or more session ends since 09-17, from 4217 ends in sessions.log. This counts non-roster sessions too.
   - A frozen roster makes the next crash restore bring back sessions the operator closed and miss newer ones. An operator's pane close is `reason=other` (session-deregister.sh:74), which the retire filter cannot see; 3773 of the 4217 ends are `other`.
   - Fix: let the freeze last one tick, or apply it only while K is dying.
6. **The deaf detector can misfire, and its opt-in bypasses the classifier.**
   - The threshold (a queue of 120 or more on two ticks) has never been tested against the recoverable slow-thread state. Stalls build the same queue (husk-panes:94), and deaf episodes run "more than 12 min" (recycle-unreachable:87), which is longer than two ticks. With auto-restart opted in, a false positive kills 32 healthy sessions.
   - The opt-in is a plain file that any agent can create. That turns a kill the classifier forbids an agent into a scheduled one.
   - Fix: confirm the thread is really dead (no `KittyPeerMon` thread in `sample`, or the oldest queued connection never changing), and make the opt-in operator-only.
7. **C2 would go live without the operator activating it, and half-built.**
   - The boot-resume contract (C10) is that the operator wires up and activates this machinery (activation snippet:3-7).
   - But `~/.claude` is a symlink farm over the checkout, so the first land of the detector arms crash auto-relaunch on the next tick, with no step by the operator.
   - The build is 3 sessions over about 2 days. If the detector lands before restore mode does, the next crash replays today's shed-the-tail failure.
   - Fix: put the new behavior behind a new opt-in file, and land the detector last.
8. **Text left in a composer gets submitted later.**
   - This was measured once today (row 4 of the table).
   - C2 keeps the keepalive (two Enters, reso-keepalive:231-233) for reboot mode and adds "send one more `\r`" when a nudge is unconfirmed.
   - An unconfirmed nudge has to be erased and verified empty, not left for the next Enter.
9. **An unattended crash happens at the worst time for kitty.**
   - When the screen is locked, kitty runs at PRI 4 (recycle-unreachable:12), so its remote control is at its slowest.
   - The restore makes about 100 bounded calls. Each client that times out is another chance to kill the new kitty's control thread (husk-panes:94). The result would be a half-restored fleet on a deaf kitty, and the fix for that is another kill.
   - `NSAppSleepDisabled` (recycle-unreachable:97) is a prerequisite that is missing from C2's change list.
10. **Quota and concurrency (estimated).**
    - Pre-kill context sizes run from 175k to 787k tokens, 7.0M in total (measured for 16 of 32 sessions, from `usage` on the last assistant record).
    - About 12 nudged first turns at R=8 each rewrite a cold cache: roughly 5M tokens (estimated as 12 × the median of 450k).
    - Each nudged session also pulls in the 68.6 KB `/limit-recover` command.
    - This would land while next2 is weekly-exhausted and next3 is at kmax-concurrency (handoffs.jsonl).
11. **No rehearsal is possible.**
    - cc-restore cannot be tested end to end without killing the fleet, so the next incident is its first full run.
    - Today's scripts surfaced 6 failure modes live.
    - The "live dry-run on a private kitty" in the build plan still moves the operator's Spaces and focus when it toggles fullscreen.

Low risk (measured): non-Claude panes. The process tree under kitty 48854 has 36 panes running claude, 1 bare `-zsh` and 2 `kitten`, so a restart loses almost nothing outside Claude.

## What C2 gets right (for balance)

- Kitty's title bars are untouched.
- The heartbeat makes no calls to the kitty socket (`cc-sessions` has none), so day-to-day running adds no socket load.
- The launched-once ledger and the event marker fix real bugs from today.
- The `.start` fix is needed whichever candidate wins.

## Recommended conviction

**55.**
- C2 is still the cheapest route to the reboot case, which only disk state survives.
- Its fixes for capacity, fullscreen, delivery and resurrection are measured and correct.
- But as specified it adds a stop-button inversion and four mid-restore failure modes that the dossier does not list.
- Each has a fix of a few lines (above). With those fixes in the change list, 65 to 70 would be fair.

## Probes and deviations

- **kitty socket:** 1 of the 3 allowed `timeout 10 kitten @ --to unix:/tmp/kitty-48854 ls` calls (rc 0, titles only).
- **Experiments:** no tmux experiment.
- **Writes:** none outside this file and the scratch files `/tmp/sd-c2skep-{ends.txt,ps.txt,kls.json,kls.err}`.
- **Deviation:** I checked 5 pids once with `kill -0`, a null signal that delivers nothing, before switching to `ps -o … -p`. No process was signaled, killed or typed into.

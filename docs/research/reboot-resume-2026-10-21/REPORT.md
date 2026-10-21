**How come we didn't resume ourselves?** All 26 eligible sessions did reopen, but the restore only sends a "carry on" prompt to sessions it can prove were cut off mid-work. 15 of 26 got only an inbox note, and a note cannot start a turn. Two of those still had work in hand and sat idle until you typed:
- **This lead (551eb39b)** had promised at 13:59 to "confirm 15.8.1, count sessions and run the leak test". The classifier read each transcript only up to the last heartbeat at 13:50 (`lost.json` anchor 1792608626, set at `boot-resume.sh:631`), so it never saw the promise. It also never checks a backlog row that the reboot itself unblocked (d4a65e8decc0).
- **The sevenrooms lead (9240c6a9)** had "W2 done" reports waiting in its old pane-31 mailbox. Its pane was renumbered to 2, and the next occupant of window 31 sealed that mail (`~/.claude/mailbox/31.sealed`).

The restore also ran slowly and invisibly. It waited 600 s for load to drop to 6 per core, which never happened (`load.log`), and the whole job runs at background priority (plist: `taskpolicy -c utility`, Nice 5, LowPriorityIO). It finished at 16:23, 88 minutes after it started at login. Its summary went to backlog row f172638a46a6 because no desk role exists, and the new kitty got no heartbeat until 16:29. The 47 minutes from boot to login were not a FileVault wait: macOS's post-update Template Migration ran 1534 s, then the Mac logged in automatically. The restart itself needed your clicks because kitty's "Quit kitty?" dialog and Dia both blocked it.

**Fixes, ranked.** Line numbers are from the live checkout under `~/.claude`, which I re-checked by grep. This worktree's copy of `scripts/boot-resume.sh` is different, so edit against current main. None of these touch settings.json, permissions, credentials or auth unless the entry says so.

**1. Classify at the real shutdown time, and recognise sessions that were closing themselves** (M)
- **Wrong:** `ANCHOR="$hb_start"` (`boot-resume.sh:631`) is passed as `--boot-epoch` (:1167), and `cc-resume-classify.py:204` stops reading at it. So the last 9.5 minutes before shutdown were never read.
- **Evidence:**
  - Records missed per session: 95d2333c 104, 5d19ef73 93, 2988e5df 55, b81018a2 24, 551eb39b 17.
  - Re-running at the shutdown time (1792609195) gives 3 INTERRUPTED / 9 WAKE-LOST / 14 AT-REST / 0 UNKNOWN, instead of 1/10/14/1.
  - 5d19ef73 had finished and was running `handoff-fire.sh self-close --terminal` when the power went. It was relaunched as an idle pane.
- **Change:**
  - `boot-resume.sh`: read until boot. Set the cut to the last burst of shutdown tombstones (endedAt 1792609195-199). Fall back to the newest pre-boot record, then `hb_start`. Rows admitted because they started after `hb_start` must also be classifiable.
  - `cc-resume-classify.py` `classify_full`: compute idle time from the last real turn. Skip queue-operation records, task-notifications inside the shutdown burst, and "Exit code 137/143" results.
  - New verdict RETIRED for a pending `handoff-fire.sh self-close` tool call. The retired check (`boot-resume.sh:741-835`) should also accept a lead-supervisor `kind:reap` record in `idl.jsonl`.
  - `handoff-fire.sh`: write a separate "terminal-intent" record when self-close starts, and remove it on every abort path.
- **Test:** `_selftest` cases: speech 5 minutes after the last tick decides the verdict; a record written only by the shutdown does not make a session look alive; a pending self-close gives RETIRED. Replay this boot's rows and expect 3/9/14/0, with 5d19ef73 RETIRED.

**2. Wake the session that owns the reboot, and any session the reboot unblocked** (M)
- **Wrong:** `WAKE_KINDS` (`cc-resume-classify.py:331`) has no promise or unblocked signal, and `rn_nudge_wanted` (`restore-note.sh:145`) prompts INTERRUPTED and WAKE-LOST only.
- **Evidence:** 551eb39b's promises are at transcript lines 551 and 595. Backlog row d4a65e8decc0 is blocked not-yet-true on "macOS 15.8.1 installed", and `sw_vers` now prints 15.8.1. The session had no turn until 20:34:24Z, when you typed. 9240c6a9 also had no turn until you typed at 15:54.
- **Change:**
  - `alarm-reboot-prep.sh`: write `$CLAUDE_CODE_SESSION_ID` as `owner` into `reboot-<date>.start` and the roster. `boot-resume` always prompts the owner.
  - `cc-backlog block`: add an `--until "<probe>"` field. It must not go in `--falsifier`, because a falsifier that passes closes the row (`docs/lessons/arming-and-mootness-cannot-share-one-falsifier.md`). At restore, run the probes on rows filed by each restored session; exit 0 adds a deciding item of kind `unblocked`.
  - Add a `promise` item kind, read from the last assistant text before the real cut (this depends on fix 1).
  - `rn_prompt_text` quotes the promise or the row. Do not widen prompts to every verdict (that was the 2026-08-24 defect).
- **Test:** owner sid is prompted; a row whose `--until` probe passes gives WAKE-LOST; a promise written before the prep `.start` does not fire.

**3. Carry each session's unread mail from its old pane number to its session at restore** (M)
- **Wrong:** mail is keyed by pane number, and the restore renumbers panes. `mailbox-drain.sh:351-410` never pulls the old pane's mailbox, and `mailbox-pending.sh:1009-1018` seals it.
- **Evidence:** `31.sealed` holds 7 lines, including "DONE — W2 landed fa03894". `8.sealed` holds 43e6eb4b's DONE report. 12 mailboxes were sealed at this restore.
- **Change:**
  - `boot-resume.sh`, before the layout: for each row, if pane P has lines past its acked mark from before the cut, call `mailbox_migrate P S` (`mailbox-pending.sh:717`) or write `P.forward`.
  - Classifier: a `mail` item kind in `WAKE_KINDS` (ignoring cc-await-ping and boot-resume senders), with the headline quoted in the prompt.
- **Test:** an unread HANDOFF-PING in the old mailbox gives WAKE-LOST, and the message reaches the resumed session. A mailbox holding only WAKE-PATH lines stays AT-REST.

**4. Remove the restore start gate** (S)
- **Wrong:** `restore_start_gate` (`boot-resume.sh:958-975`, called at :1252) waits for load to fall to 6 per core. That breaks the ruling that no gate waits for load.
- **Evidence:** 60 readings from 61.47 down to 6.99 per core, then the 600 s deadline. On 10-18 it did open, at 5.32, so it is not a fixed delay on every boot, but it is a load wait.
- **Change:** make it telemetry only: one `load.log` reading and no wait (or default `CC_RESTORE_START_LOAD=40`). Fix the matching text at :449-454 and in the page (around :1458).
- **Test:** a bats case with stubbed load 35 per core: no sleep, and the layout starts at once.

**5. Run the restore at normal priority** (S-M)
- **Wrong:** plist line 30 runs the job under `taskpolicy -c utility`, with LowPriorityIO and Nice 5. The restore therefore ranks below every claude process (priority 20 against 31).
- **Evidence:** the same glob takes 3.4 s at default priority and 24-46 s at the job's priority. Admission-to-launch grew from 4 s to 278 s, each prompt confirmation took 37-91 s, and the run took 88 minutes.
- **Change:**
  - `launchd/com.claude.boot-resume.plist`: drop the clamp, Nice and LowPriorityIO.
  - `boot-resume.sh`: re-run itself under `taskpolicy -c utility` only for the routine same-boot tick, before line 500. The census already lowers its own priority (`restore-heartbeat.sh:450`).
  - This needs the agent to be reloaded through `install.sh`. That is a launchd change, not an escalation surface.
- **Test:** after the reload, `ps -o pri,nice` during a restore shows priority 31 and nice 0. Re-time the glob at about 35 per core.

**6. Stop globbing every project directory to find a transcript** (S-M)
- **Wrong:** `_rn_transcript` (`restore-note.sh:177`) and `resume_marks` (`cc-resume-layout.sh:328-336`) glob about 73,000 directories on every call. `~/.claude-next/projects` is a symlink to `~/.claude/projects`, so that store is scanned twice. `resume_marks` only matters for the "maybe" re-check, and this boot had no such rows.
- **Change:** pass the transcript path through the row (account config dir plus cwd slug, as `_hb_transcript` in `restore-heartbeat.sh:213` does). Try that path first, cache it per session, skip roots whose real path was already scanned, and keep the glob only as a fallback.
- **Test:** one `rn_confirm` call under 1 s at load; a stub on `ls` shows no glob over `projects/*`.

**7. Make the confirm loop's deadline wall-clock, and stop re-confirming** (S)
- **Wrong:** `c_left` loses 5 per round however long the round takes (`boot-resume.sh:1331-1341`). The reporting loop (:1343-1362) then calls `rn_confirm` again for all 11 sessions.
- **Evidence:** the confirm phase ran from 15:35 to 16:10. If any prompt had failed to land, the 90 s budget could have stretched to hours (estimated).
- **Change:** `c_end=$(( $(date +%s) + CC_RESTORE_CONFIRM_S ))`, keep a set of confirmed sessions and skip them, and reuse each session's rc and counts in the reporting loop.
- **Test:** stub a slow `rn_confirm` (30 s). The phase must end within about 90 s plus one call, and each session is confirmed once.

**8. Deliver the restore summary early, to a session that exists, with true wording** (M)
- **Wrong:** the page is sent only after the confirm phase. It needs `cc-roles/desk`, which does not exist. The fallback row tells you "nothing was told… run /resume-sessions, cc-roles claim desk", which was false here: 26 sessions resumed and all 11 prompts confirmed.
- **Evidence:** the `idl.jsonl` record at 21:23:23Z has channel backlog-needs, reason no-desk-role. Undelivered pages exist for 5 events across the last 4 reboots.
- **Change:**
  - `boot-resume.sh`: send the page as soon as the layout returns, plus a follow-up after the confirm phase.
  - Recipient: the prep owner session (fix 2), else a live lead role, else the backlog.
  - The fallback text depends on the outcome, and `cc-backlog needs` runs in the background.
  - Run `cc-restore-rebind "$EVENT_DIR"` after the layout so roles named by pane number are re-resolved (drain-lead still points at pane 7, which is now 43e6eb4b).
- **Test:** with no desk role, the page reaches the owner session within a minute of the layout; the backlog text never says "nothing was told" when resumed > 0.

**9. Take heartbeats while a restore is running** (M)
- **Wrong:** the heartbeat lives inside the same single-instance launchd job as the restore, so there is no tick while the restore runs. The only first-run tick (`boot-resume.sh:843`) happens before any session is up.
- **Evidence:** the 1881 heartbeat dir was created at 16:29:21, 94 minutes after kitty started. Even in normal running, ticks average 443 s apart (up to 1313 s) against a 300 s interval.
- **Change:**
  - Call `heartbeat` right after the layout returns and before each exit.
  - Better: a separate `com.claude.restore-heartbeat` agent. It must skip its tick on a new boot until `events/boot-<BOOT>/` exists, so the cc-sessions sweep cannot eat the detection fallback.
  - `hb_tick` (`restore-heartbeat.sh:472`): add every live kitty pid found in `ps.txt` (checked with `_hb_kitty_ident`) to the kitty list.
  - Record each tick's duration.
- **Test:** during a simulated 30-minute restore, `heartbeat/<uuid>/<kittypid>/` is refreshed at least every 5 minutes.

**10. Record why sessions were held, and tell the lead its team members were lost** (M)
- **Wrong:** the four members of team session-948e2ac1 (b76212c7, bd1dfaa5, c7cc1565, 6ea12efd) were held with exit 7 (`boot-resume-launch.sh:364`). The probe's stderr is thrown away (`boot-resume.sh:1141`), and the lead's lost items have no teammate item.
- **Change:** append session, rc and reason to `$EVENT_DIR/held.log` and name each held session in the page. Map each held member to its lead through the `--parent-session-id` argv captured in `hb.kitty-ls.json`; a team config's `leadSessionId` does not match after a resume. The lead's prompt then says to respawn the members.
- **Test:** replay this boot. `held.log` has 4 rows, and 95d2333c's lost items include a teammate item.

**11. Fix the classifier crash on an unreadable transcript** (S)
- **Wrong:** `cc-resume-classify.py:187` returns 3 values where every caller unpacks 4, so it raises ValueError. `boot-resume.sh:1180-1183` then marks every row UNKNOWN, and nobody is prompted.
- **Change:** `return "UNKNOWN", f"unreadable: {exc}", "", []`.
- **Test:** a selftest with a directory path or a chmod-000 transcript among good rows: one output row per input row, and exit 0.

**12. Fix the `rows.tsv` merge under pipefail** (S)
- **Wrong:** at `boot-resume.sh:1189-1191`, `cat` of the missing `rows.tsv` fails under pipefail, so `mv` never runs. All three restore events hold only `rows.tsv.tmp`.
- **Change:** `cat "$EVENT_DIR/rows.tsv" 2>/dev/null || true` inside the braces.
- **Test:** a bats case: after a first-round restore, `rows.tsv` exists.

**13. Make reboot prep phase-aware** (M)
- **Wrong:** prep's 13:25 run said NOT-READY because of a land that had already pushed and been verified (land.log release exit 0 at 17:37:11Z). That land was stuck in an unbounded stranded-sweep (`ship-land.sh:1732`; normally 59-62 s, this one ran over 62 minutes). `find_lands` (`alarm-reboot-prep.sh:121-126`) also counts the lander's own subshell as a second land. Exit 3 at :329-333 skips every operator step.
- **Change:**
  - `ship-land.sh`: write the land's phase into the in-flight marker, and bound the sweep.
  - `find_lands`: drop child pids. A post-push land is reported as "safe to reboot".
  - Always print the operator steps.
  - Prep sets `defaults write net.kovidgoyal.kitty NSAppSleepDisabled -bool YES` itself.
  - Add an mkdir lock, and refresh `now` after the wait on every path. Two concurrent runs left `.start` 30 minutes older than its roster.
- **Test:** a stub land with the post-release phase gives READY; a second concurrent prep run exits 2.

**14. Add a no-click restart step to prep** (S)
- **Wrong:** Software Update's restart was vetoed by Dia (13:54:55) and by kitty's quit dialog (13:55:14 until 13:59:53). `kitty.conf:1031` sets `confirm_os_window_close -1`.
- **Change:** an `alarm-reboot-prep.sh --arm-restart` step that takes a final heartbeat, runs `kitten @ load-config -o confirm_os_window_close=0` (kitty has no `@ quit`), and lists or offers to quit apps that can veto the restart. The restart classifier must still read that quit as a reboot cut.
- **Test:** after the step, the loginwindow log shows no userCanceledErr for kitty.

**15. Stop filing a false "failed land" when a post-push land is killed** (S)
- **Wrong:** `_land_sig_verdict` (`ship-land.sh:1490-1525`) records "killed" and creates `refs/land/failed/...` pointing at 13d332d09, which is the tip of `origin/main`.
- **Change:** when `LANDED_HEAD` is set, record verify=ok, sweep=killed, and skip the failure inbox, the ref and the banner.
- **Test:** sending SIGTERM during the post-release phase creates no failure ref, and land.log shows exit 0.

**16. Don't treat the resume notice as a new turn** (S)
- **Wrong:** the "didn't finish before the previous session ended" notice that Claude Code adds on resume counts as a user turn in `classify_full`. That makes a session that was waiting look mid-turn. It is latent: 43e6eb4b, 4da72f17 and 509e3aad were all saved by being stale.
- **Change:** skip user records with `<status>stopped</status>` and that summary text, in both the single-task and `__orphan_summary__` forms.
- **Test:** a twin case: a finished turn, then this notice 5 minutes before the cut, gives AT-REST.

**17. Speed up the layout** (S)
- **Wrong:** `STAGGER=12` (`cc-resume-layout.sh:174`, sleep at :991) adds about 5.2 minutes of pure sleep. Windows that hold prompted rows launch last, which cost about 90 s per prompted row. That is minor; the investigator's larger impact claim was refuted.
- **Change:** 1-2 s stagger under `--restore`. Optionally sort windows by how many prompted rows they hold, most first.
- **Test:** the gaps in `pane-spawns.jsonl` are about 2-4 s at low load.

**18. Measure the restore deadline from the first run, not from kernel boot** (S)
- **Wrong:** `restore_done` (`boot-resume.sh:957`) measures from boot time. This boot's deadline was 14:36:30, before the first run at 14:55. Any session shed by the capacity gate would have had no retry round. Latent: shed was 0 this time.
- **Change:** stamp `$EVENT_DIR/started` at the first run and measure from it.
- **Test:** with a boot 2 hours earlier and shed > 0, a retry round still runs.

**19. Make the cc-sessions census cheap** (M)
- **Wrong:** the census bound is capped at 75 s, and it measured 74 s at 40 per core. On 10-18 it took 4 min 25 s, for 2.6 s of CPU. `bin/cc-sessions:280-339` forks 7-9 processes per row.
- **Change:** one `jq -s` over the registry plus one `ps -o pid=,lstart= -p <all>`. Log each tick as ok or carried, with its duration, in `census.log`. In `hb_tick`, drop roster rows with no session id. In cc-sessions, fall back to the file's mtime when startedAt is null, so stale placeholder rows are reaped.
- **Test:** the census of 60 rows finishes in under 10 s at 35 per core.

**20. Observability** (S)
- **Wrong:** launchd stdout and stderr go to `/tmp`, which a reboot erases. `last-classify.txt` is overwritten each run. `last-layout.txt` is appended across boots with no timestamps.
- **Change:** send logs to `~/Library/Logs/claude/`. Write `$EVENT_DIR/layout.txt` and `run.stderr` per event. Prefix `note()` lines with `date +%T`.
- **Test:** the event dir contains a timestamped layout log.

**21. Fullscreen count and the stray startup window** (S)
- **Wrong:** an unknown fullscreen state is counted as success (`cc-resume-layout.sh:1056`), so all 8 windows were reported fullscreen without being checked. Kitty's own startup window (bare zsh) was left open as a ninth window.
- **Change:** add `fullscreen_unknown` to the verdict, retry the check once, and cross-check against com.apple.spaces. After a pass that placed windows, close pre-existing single-pane windows that hold only a login shell.
- **Test:** with the display probe stubbed to return nothing, the verdict shows `fullscreen_unknown=8`.

**22. Prune temp clutter before an OS-update restart** (M, the effect is estimated)
- **Wrong:** Template Migration took 1534 s. Its log is dominated by lines about `/private/var/dirs_cleaner` (26,234 of them about cc-socks sockets). `/private/tmp/cc-socks` holds 71 sockets, 35 of them for dead processes.
- **Change:** when an update is pending, prep removes sockets for dead pids and `/tmp/claude-501` trees of sessions not in the roster. `boot-resume` records templateMigrator's TotalDuration in the event dir.
- **Test:** compare that duration at the next update.

**23. Capture the kitty tree when panes open, not only on ticks** (M)
- **Wrong:** pane 476 opened 2 minutes after the last tree capture (13:51:30) and was restored from the fallback plan. `hb.displays.tsv` was 20 minutes old.
- **Change:** refresh `hb.kitty-ls.json` from `cc_log_pane_spawn` and on pane close, and give the display probe a bound that scales with load.

**Dropped or turned into operator decisions:**
- **Not defects:** the custody-holding leads woke as designed; the "launched list written late" item has no duplicate-launch risk; "always refuse lands while a reboot is pending" would idle every lander and was dropped.
- **FileVault authrestart:** this is the credential-gated (escalation) item. It is not needed for OS updates, where Software Update's own key stash logged in automatically. For plain reboots it is already filed as backlog row 0822e916af70.
- **Desktop order:** macOS's "rearrange Spaces by most recent use" setting (`mru-spaces`) is on, so it reorders Desktops itself. Turning it off is your call.

**Leak test:** still leaking on macOS 15.8.1 (build 24H32). Running a `#!` script by its path keeps about 1.1 elements (1 KiB) per exec in `data.kalloc.1024` (1.098 ± 0.104; fit through zero 1.120 ± 0.082), against about 0 for `/bin/bash leaf.sh` (0.007 ± 0.101). That is from 6 S/B pairs at 3000 execs each, at load 184-389. The test itself grew the zone by about 47 MiB, which stays until the next reboot. Data is in `/Users/chrisren/.cache/kalloc-158-ab/`.
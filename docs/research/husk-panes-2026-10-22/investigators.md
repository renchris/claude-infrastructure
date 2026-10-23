# pane85

## Timeline
- 07:36:41Z handoff-fire pid 72807, run by the lead in pane 16 (then session 1e7dc0e1), spawned pane 85 as a split of pane 16 with cwd "current" and marker HANDOFF-ENGAGE-72807-1792654598-29628. MEASURED: ~/.claude/logs/pane-spawns.jsonl:5537
- 07:37:03Z claude pid 54386 started under the cc-close-attrib wrapper (ppid 53818). It registered at 02:37:14 CDT with tty=ttys038 pane=85. The fired-peer stamp ~/.claude/cc-fired/85.json was written at 07:37:37Z and custody fire-b13-r23-K was opened at 07:37:38Z. MEASURED: close-records/54386-1792654623.json; lead-crash-watchdog.log:66699; 85.json; cc-custody list
- 07:41:28Z the lead in pane 16 recycled into session 666022fd (pid 65517, account quaternary, cwd ~/Development/agent-context-sync). MEASURED: lead-crash-watchdog.log:66701; ~/.claude/cc-registry/16.json
- 08:17:14Z lane K's last tool call (a foreground pytest --basetemp scratch-K/bt1 with a 600 s timeout) never got a tool_result. A background-task notification was queued at 08:38:50Z and never consumed. So the process was alive but wedged for about 55 minutes. MEASURED: transcript records 805-806. The 'wedged' reading is INFERRED.
- 09:12:33Z SessionEnd fired with reason=other (sessions.log:133883, local 04:12:33). At 09:12:40Z claude exited 143 on signal 15, and the wrapper itself caught the TERM (sig_reached_wrapper=TERM). MEASURED: close-records/54386-1792654623.json. Sender not found: no kill or pkill appears in the bash-commands log for 09:00-09:13Z, and there is no cc-reaper or teardown row then.
- 09:12:44Z cc-pane-runner wrote 'fleet launch line exited 143 · shell kept for resume'. MEASURED: pane-say.jsonl:707 (ts 1792660364)
- 09:13:07Z the death was classed CRASH/external-sigterm and the death page went to cc-desk-page, not to the custody holder in pane 16. MEASURED: claude-crashes.jsonl:6442; lead-crash-watchdog.log:66725
- 09:18:59Z the watchdog painted pane 85: KILLED, 'pane 16 holds custody · tell it', 'uncommitted work in r23-k' (dirty:10). This is the paint still on screen now. MEASURED: pane-say.jsonl:711-715; lead-crash-watchdog.log:66730
- 12:23:40Z, about 3 hours later, lead 666022fd found K dead and dated the death wrongly to 08:17 UTC. `kitty @ ls` returned EOF at load ~150. MEASURED: bash-commands.log:2007,2222
- 12:25:31Z the lead ran by hand: `cd r23-k && CLAUDE_CONFIG_DIR=~/.claude-next claude -p --resume 570d3917 ... > scratch-K/resume1.out` from its own Bash tool in pane 16. There was no wrapper and no env scrub. The watchdog registered pid 23549 with tty=none pane=16. MEASURED: bash-commands.log:2221; lead-crash-watchdog.log:66758
- 12:26-23:14Z the headless lane K committed, rebased and landed eb0938ee..9b8471d4 on agent-context-sync main. CI runs 39865991577 and 39865991687 were green. MEASURED: transcript records 2042-2098; bash-commands.log:2370ff
- 23:14:35Z K sent DONE to agent-context-sync-16. Between 23:14:54Z and 23:14:56Z the lead returned custody fire-b13-r23-K. MEASURED: transcript 2101; cc-custody list --cwd ~/Development/agent-context-sync shows a 'return' row at 23:14:56Z
- 23:15:43Z K ran `handoff-fire.sh self-close --terminal`. At 23:16:28Z the watcher was armed 'for 16' with KITTY_WINDOW_ID=16, and the pane probe found pane 16 reachable. MEASURED: transcript 2135-2136; /tmp/handoff-selfclose-16-1792710988.log
- 23:16:36Z 'close sid=16 kind=terminal'. This wrote closedAt into the stale 16.json, a stamp opened 2026-10-18 for a b13/r16-d lane whose worktree no longer exists. 85.json is still closedAt null. MEASURED: the selfclose log; ~/.claude/cc-fired/16.json; 85.json
- 23:16:46Z close-attrib.jsonl:1242 records site=self-close id_requested=16 owner=operator-or-unknown verdict=closed. kitty-fullscreen-guard returned safe-not-last for wid 16. MEASURED: kitty-pane-actions.jsonl:1177
- 23:16:38Z the lead's last record was an Edit adding the 'B13 round 23 landed' section to docs/plans/bring-back-ocr.md. Its pane was closed under it. The watchdog wrote at 18:17:16 CDT: 'RECYCLE cause=clean-exit ... pane closed'. MEASURED: 666022fd transcript tail; lead-crash-watchdog.log:66939-66940
- 23:17:00Z headless pid 23549 was classed CRASH suspected-oom-large-context with no close record, and the paint was skipped (tty=none). MEASURED: claude-crashes.jsonl:6478; lead-crash-watchdog.log:66935-66937
- Now (23:29Z): pane 85 is a bare zsh in ~/Development/agent-context-sync and pane 16 is gone. r23-k is clean at 9b8471d4, which is an ancestor of origin/main (0 commits ahead). `cc-husk-sweep --pane 85` (list mode) says 'MOVED→pane 16 ... close this pane with cc-pane-close'. The lead's checkout has 1 uncommitted file, docs/plans/bring-back-ocr.md (+37 lines). MEASURED: kitty @ ls; git -C r23-k status/log/merge-base; cc-husk-sweep; git -C ~/Development/agent-context-sync diff --stat

## What happened
The words on pane 85 and the session's last words describe two different lives of the same session. Life 1 was the interactive claude in pane 85. It stalled at 08:17Z and was killed by a SIGTERM at 09:12:40Z (sender not found). The watchdog painted the KILLED banner at 09:19Z, and nothing has updated it since. About 3 hours later the lead in pane 16 found the death. `kitty @ ls` returned EOF at the time, so the lead ran life 2 itself as a headless `claude -p --resume` from its own Bash tool. That child inherited the lead's KITTY_WINDOW_ID=16 and also registered with the watchdog as pane=16. Life 2 finished the lane: it landed 9b8471d4 with CI green, and the lead returned its custody. It then ran `handoff-fire.sh self-close --terminal`. Self-close took 'my pane' from the inherited KITTY_WINDOW_ID=16. The ancestry check passes because the lead's pane-16 shell is an ancestor of the headless child. Pane 16 also held an open, 4-day-old fired-peer stamp for a deleted worktree, so the stamp gate did not stop it. The watcher then closed pane 16, the LEAD's pane, which killed lead 666022fd in the middle of its round-23 write-up and very likely also killed the headless child (its process tree lived in that pane). Pane 85 itself was never touched by life 2, so it still shows the 09:19Z snapshot. Self-close does not send SIGTERM to claude: it records the close, then has a detached watcher close the pane by id. Here that pane id was the wrong one.

## Disposition: close
Pane 85: close it, either with `cc-pane-close 85` (what cc-husk-sweep recommends) or by hand. Do NOT run `cc-husk-sweep --resume` or the printed `claude --resume 570d3917` line. Nothing of lane K's is at risk:
- `git -C ~/Development/.worktrees/b13/r23-k status --short` is empty.
- HEAD is 9b8471d4, and `git merge-base --is-ancestor HEAD origin/main` succeeds (rev-list count 0; local ref, not fetched).

Optional cleanup:
- ~/.claude/cc-fired/85.json is still closedAt null.
- The r23-k worktree and branch b13/r23-k still exist; the lead's remove-worktrees step skipped them at 23:15:43Z with 'a process is inside'.

URGENT, separate from pane 85: lead 666022fd (account quaternary, cwd ~/Development/agent-context-sync) was killed mid-task at 23:16:36Z, and its pane 16 is gone. Work at risk:
- An uncommitted, unlanded edit to docs/plans/bring-back-ocr.md on main in ~/Development/agent-context-sync (+37 lines, measured with `git diff --stat`). This is the 'B13 round 23 landed' section.
- The lead's remaining steps, in its own words at transcript record 1661: remove round 23's worktrees (r23-k and r23-ra remain), write the round-23 section in the plan and land it, then start round 24.

To recover, resume it in a new kitty pane at ~/Development/agent-context-sync with the quaternary account (CLAUDE_CONFIG_DIR=~/.claude-quaternary, or the pinned quaternary launcher), using `--resume 666022fd-ed3e-4e72-b293-7caae899d585`. cc-husk-sweep cannot find it because no pane is left. Pane 85's shell happens to sit in that cwd, but launching the resume there is the operator's call.

## Message defects
- Title '⛔ KILLED 570d3917': stale. It describes the 09:12Z death of life 1. The session was later resumed elsewhere and ended by its own terminal self-close. There is no timestamp, and nothing says the session continued elsewhere.
- 'Resume this session with: claude --resume 570d3917-…' (Claude Code's own exit text) is wrong three ways. Wrong account: the transcript is in ~/.claude-next and the default store cannot see it. Wrong cwd: the shell is in agent-context-sync, but the session's project is b13/r23-k. Wrong action now: the lane is finished, so a resume re-opens completed work.
- '⚠ fleet launch line exited 143 · shell kept for resume' is jargon ('fleet launch line', a bare 143 with no 'SIGTERM'). 'Kept for resume' tells the operator to resume a session that has since finished.
- '✗ 570d3917 killed (external-sigterm) ▶ cc-husk-sweep --pane 85': 'external-sigterm' names no sender. The suggested command now returns 'MOVED→pane 16 … the session continues in the pane named', which is false because pane 16 is closed and the session has ended. Its fallback advice (close with cc-pane-close) is buried.
- '⚠ pane 16 holds custody of its work · tell it' is false now: custody fire-b13-r23-K was returned at 23:14:56Z and pane 16 no longer exists. Even when it was true it gave no way to act: it says neither how to tell pane 16 (cc-notify agent-context-sync-16?) nor that nothing had told it automatically.
- '⚠ uncommitted work in r23-k' is false now: r23-k is clean and 9b8471d4 is on origin/main. It was true at 09:19Z (dirty:10, this session's own WIP), but the row carries no as-of time.
- Detail row (pane-say.jsonl:715) 'last close verdict: -' is unexplained filler.
- The cc-husk-sweep row shows DEATH 'suspected-oom-large-context' for this sid. That was the headless continuation's misclassified end, not an OOM, and it contradicts the pane's own 'external-sigterm'.
- Self-close's own output '→ self-close armed for 16' did not flag that pane 16 is not this session's fired pane (85.json) or that the caller was headless (tty=none), so a close of the wrong pane went out without a warning.

# pane42

## Timeline
- 2026-10-21T21:58:46Z: originator pane 21 (cwd wt-cc-000146-45877) fires T2 through handoff-fire, account next2 (MEASURED, handoffs.jsonl row ts 21:59:24Z).
- 21:59:00Z: pane 42 is spawned as a new os-window with marker HANDOFF-ENGAGE-26967-1792619918-317 (MEASURED, pane-spawns.jsonl:5503). kitty was launched with --cwd=/Users/chrisren/Development/.worktrees/wt-cc-000146-45877 (MEASURED, `ps -ww -o command= -p 89945`). The command then cd's into rrp-t2-boot-resume.
- 21:59:09Z: claude pid 96671 starts (MEASURED, close-records/96671-1792619949.json). 21:59:13Z: the watchdog registers session=18f95342 pane=42 tty=ttys064 (MEASURED, lead-crash-watchdog.log, logged as '2026-10-21 16:59:13' local time). 21:59:25Z: custody 'open' row for fire-rrp-T2, target pane 42 (MEASURED, `cc-custody list --json`).
- 22:12:21-24Z: the operator's kitty-pane-menu moves pane 42, then the only pane of os-window 12, into the 'Reboot resume T3 prep and land — 2 panes' window. The guard returned safe-after-toggle (MEASURED, kitty-pane-actions.jsonl). That destination is os-window 10: pane 40 (T3) appears there at 05:25Z (INFERRED from the same log).
- 23:55:03Z: os-window 10 (platform 1443) holds 7 panes, and pane 46 is closed (MEASURED, kitty-pane-actions.jsonl kitty-confirm-close row panes=7). No pane moves in or out of os-window 10 are logged between 23:55Z and 04:28Z (MEASURED, same log).
- 2026-10-22T02:25Z-02:53Z: three land attempts fail (MEASURED, refs/land/failed/2026102{2T022506Z,2T024816Z,2T025338Z}-18f95342-…). It then lands af5eda439 and 160bd4cb3, and both are ancestors of origin/main (MEASURED, `git merge-base --is-ancestor`).
- 03:04:31Z: the session runs deploy-live, which reports 'at trunk tip af5eda439, nothing to deploy' (MEASURED, bash-commands rotated log line 176663 and /tmp/t2-deploy.log).
- 03:06:06Z: DONE ping goes to the originator. 03:06:19Z: custody 'return' row for fire-rrp-T2 (MEASURED, cc-custody list --json). 03:06:20Z: last assistant text says 'Ledger is ✅, the tree is clean, and the branch has 0 commits ahead of origin/main. Retiring this pane:' (MEASURED, transcript tail).
- 03:06:21Z: `handoff-fire.sh self-close --terminal` runs. Its pane-probe listing took 5 s to answer (rc=0), already slow (MEASURED, /tmp/handoff-selfclose-42-1792638399.log). 03:06:50Z: 'close sid=42 kind=terminal'. 03:06:57Z: Enter is typed into pane 42 (MEASURED, pane-keys.jsonl:913).
- 03:07:06Z: SessionEnd reason=prompt_input_exit (MEASURED, sessions.log). 03:07:09Z: claude exits with code 0 (MEASURED, close record).
- 03:07:18.365Z: cc-pane-runner calls kitty-fullscreen-guard --window 42 --mode refuse --scope pane. Verdict kitten-failed, rc 3, with no os_window_id or panes fields (MEASURED, kitty-pane-actions.jsonl). The runner keeps the shell and prints '⚠ last pane of a fullscreen window · close it by hand' (MEASURED, `kitty @ get-text --match id:42`).
- 03:07-03:09Z: handoff-fire's 'it2 session close' fails 4 of 4 attempts. 03:09:19Z: hf_alarm class=husk-pane is written, and its desk push returns 'refused-rc3' (MEASURED, /tmp/handoff-selfclose-42-1792638399.log and ~/.claude/handoff-alarms/alarm-20261022T030919Z-16910-31210.json).
- 03:07:41Z: the watchdog classifies the death as RECYCLE, cause clean-exit, exit_code 0, with 30 claude sessions running concurrently (MEASURED, claude-crashes.jsonl).
- 03:08:27Z: the watchdog's pane_verdict_text records 'ok: 18f95342 ended cleanly · closing in 20s', with detail 'reason: prompt_input_exit … work in rrp-t2-boot-resume: clean' (MEASURED, pane-say.jsonl ts 1792638507).
- 03:08:31Z: cc-pane-close refuses. 'kitty remote control is down and a kitty window is in native fullscreen (or unreadable)' (MEASURED, pane-close.jsonl:92). Its guard --any-fs reports refused-fs over fullscreen windows [769, 865, 859, 781, 1443, 847], and 1443 is os-window 10 itself (MEASURED, kitty-pane-actions.jsonl).
- 03:08:31Z: the watchdog swaps the countdown row for '⚠ 18f95342 ended, reason unknown ▶ cc-husk-sweep --pane 42' and writes the title '✅ closed 18f95342' (MEASURED, pane-say.jsonl ts 1792638511 and lead-crash-watchdog.log: 'pane verdict PAINTED on ttys064 (pane 42): 18f95342 ended cleanly · closing in 20s').
- 03:09:33Z: pane 50 also gets kitten-failed. 03:27:21Z: kitten calls succeed again (reso-resume-one, safe-not-last) (MEASURED, kitty-pane-actions.jsonl). Nothing retries pane 42 after that (MEASURED: no pane-close-queue row self-close-42.json, and no later pane-close.jsonl row for 42).
- 04:28:25Z: os-window 10 holds 6 panes, pane 42 among them (MEASURED, it2-kitty guard row wid 38, panes=6).
- 2026-10-22T23:27-23:29Z: sibling investigators' dry-runs give guard verdict safe-not-last, panes=3 (MEASURED, kitty-pane-actions.jsonl). My own `cc-pane-close --pane 42 --dry-run` prints 'WOULD CLOSE — session 18f95342, its orchestrator abandoned/returned its custody after it registered; via kitty remote control', rc 0 (MEASURED). `cc-husk-sweep --pane 42` (list mode) gives verdict COLLECTED: 'never resumed; close the pane' (MEASURED).

## What happened
Session 18f95342 finished its work: T2 landed as af5eda439 and 160bd4cb3, and its custody was returned at 03:06:19Z. It then retired itself on purpose with self-close and /exit, and claude exited 0 at 03:07:09Z. At that moment kitty's remote control was not answering. The 03:06 listing had already taken 5 s, the guard's kitten call failed at 03:07:18Z, handoff-fire's close failed 4/4 up to 03:09Z, and cc-pane-close's remote check failed at 03:08:31Z. Every closing path made one short attempt and then gave up:
- cc-pane-runner kept the shell because the guard returned kitten-failed.
- handoff-fire raised a husk-pane alarm whose desk push was refused.
- The watchdog's closer could not use remote control. Its signal fallback (SIGHUP to the shell) was correctly blocked because several kitty windows, os-window 10 among them, were in native fullscreen.

Remote control was back by 03:27Z, but nothing records a stuck close for a fired peer's self-close, so nothing retried it. The pane has sat open about 20 h, although cc-pane-close --dry-run now says WOULD CLOSE.

The "two writers" are really one writer. The watchdog's paint_pane_verdict picked the title "✅ closed" for a clean exit (RECYCLE). When the closer refused, it replaced the body row with a fixed "ended, reason unknown" string and left the title unchanged. The pane's cwd is the originator's worktree because handoff-fire launches the pane with --cwd set to the originator's cwd and cd's into the target only inside the child command. The kept shell inherited the launch cwd. rrp-t2-boot-resume has since been removed.

## Disposition: close
Step: run `~/.claude/bin/cc-pane-close --pane 42`. Its dry-run at about 23:30Z printed 'WOULD CLOSE … via kitty remote control', rc 0. It re-checks identity, that nothing is running, custody and the fullscreen guard before closing.

Work at risk: none.
- The latest checkpoint matches the landed commit on 4 of 5 paths. The 14-line difference in tests/boot-resume.bats is a later fix that is in af5eda439 (MEASURED, `git diff e285343f2 af5eda439`).
- `cc-custody list --json` has an open row at 21:59:25Z and a return row at 03:06:19Z for marker HANDOFF-ENGAGE-26967-1792619918-317.

Do NOT treat wt-cc-000146-45877 as this session's work. It belongs to the live originator (pane 21, branch cc-000146-45877, HEAD 2372399e7 committed 2026-10-22 18:15). `git status --short` there is empty. It shows up only because it is the shell's launch cwd.

Optional cleanup: ~/.claude/handoff-alarms/alarm-20261022T030919Z-16910-31210.json (husk-pane, its push was refused) becomes stale once the pane is closed. I closed nothing, because this run is read-only.

## Message defects
- 'Resume this session with: claude --resume 18f95342-…' (Claude Code's own exit text): wrong launcher, since the transcript lives in .claude-secondary and needs claude2. It also invites a resume of a session whose custody was returned, which cc-husk-sweep calls COLLECTED, 'never resumed'. No line on the pane says 'do not resume'.
- 'kitty-fullscreen-guard: refused (kitten-failed) kitty window 42 scope=pane mode=refuse: state=UNKNOWN types=None onscreen=None': jargon only someone who knows the internals can read, and the state fields are placeholders, not readings. It omits the one useful fact, which is why the kitty @ kitten call failed (timeout, rc and stderr, or a bad reply); bin/kitty-fullscreen-guard:754-755 drops it.
- '⚠ last pane of a fullscreen window · close it by hand': FALSE. Os-window 10 held about 6 panes at 03:07Z (panes=7 at 23:55Z, 6 at 04:28Z, no logged moves in between). The guard never decided 'last' because its kitten failed, so an unknown was printed as a known fact. The advice to close by hand is also unneeded: once remote control returned, cc-pane-close could close it with no human (dry-run WOULD CLOSE).
- Title '✅ closed 18f95342': says the pane closed while it is still open and the body warns. The watchdog sets the title before the closer's refusal and never changes it.
- '⚠ 18f95342 ended, reason unknown': FALSE. The end reason was recorded as prompt_input_exit, clean-exit, exit 0, and the watchdog's own detail row two lines earlier in pane-say.jsonl says so. The unknown part was the close; its real blocker (kitty remote control down while windows were fullscreen) was logged but not shown.
- '▶ cc-husk-sweep --pane 42': cannot close the pane. In its default mode it only lists, and its --resume mode would be wrong here. The listing's verdict says 'close the pane' but gives no command, so the operator needs a second lookup. The command that acts is `cc-pane-close --pane 42`.
- Prompt '➜ wt-cc-000146-45877 git:(cc-000146-45877) ✗': shows the originator's worktree and branch with a dirty marker, which reads as if this pane's own work is uncommitted elsewhere. This session's worktree (rrp-t2-boot-resume) was clean and has since been removed.

# pane101

## Timeline
- 2026-10-22T07:27:37-38Z: lead claude pid 64334 (session d093011f, cwd r23-ra) splits panes 80, 81 and 82 for teammates ra-stop, ra-open and ra-misc through it2-kitty. Evidence: pane-spawns.jsonl:5532-5534 (ancestry '…bash>64334:claude') and pane-say.jsonl:690-692 (parent-session-id d093011f).
- 08:11Z to 15:51Z: pane-spawns.jsonl has no rows at all (5541 → 5543). MEASURED.
- 08:32-08:50Z: the kte-w3 lead e881b713 has 9 teammate splits fail with 'kitty launch failed (rc=124)'. Evidence: ~/.claude/projects/-Users-chrisren-Development--worktrees-kte-w3/e881b713-….jsonl, lines 689-1218.
- 09:17:47Z to 14:06:15Z: every kitty-fullscreen-guard verdict is 'kitten-failed' rc=3 (kitty-pane-actions.jsonl:1118-1124), so kitty could not be read in this window.
- 09:25:46Z: the RA lead calls Agent name=ra-shut (transcript d093011f line 695). 09:26:15Z result: 'Failed to create iTerm2 split pane: it2-kitty: kitty launch failed (rc=124):' (line 697). Retries fail at 09:26:37, 09:26:53 and 09:27:18Z with 'rc=1: Error: EOF' (lines 725, 736, 745).
- 09:27:36Z: the lead writes 'Teammate panes won't open … firing the second-wave builder as its own session instead' (line 762). The handoff-fire attempts follow (lines 763-778).
- 09:31:32Z: `kitty @ ls` → 'Error: EOF' (line 785). 09:31:54Z: the lead says it will build the ra-shut items itself (line 793), and it checks that no session runs in r23-ra-shut (lines 794-803).
- 14:05-14:11Z (inferred as warn ts − 300s): kitty finally opens the 9 kte-w3 panes 92-100. Their runners warn 'no command arrived within 300s' at 14:10:07Z through 14:15:57Z (pane-say.jsonl:747-755).
- 15:00:00.17Z (10:00:00 CDT): kitty opens window 101 in os-window 4 running `zsh -l -i -c 'exec /bin/bash "$CC_PANE_RUNNER"'`. This is the arm path, not handoff-fire's env path. Evidence: `kitty @ ls` created_at=1792681200174280000, and `ps` lstart of login pid 44696 is 'Thu 22 Oct 10:00:00 2026'. The pane's 'Last login: … 09:10:56' line is the PREVIOUS login (pane 100, 14:10:56Z), not this pane's start.
- At 15:00Z the live layer ~/Development/claude-infrastructure is at 0c4a29f7d (reflog, 09:24:11 CDT). That cc-pane-runner exec'd a shell at the deadline: `[ "$(date +%s)" -ge "$_deadline" ] && _fallback "no command arrived within ${_wait}s"`.
- 15:05:00Z: pane-say.jsonl:756 records {pane:101, kind:warn, verdict:'no command arrived within 300s', fact:'pane is an ordinary shell'}. _fallback removes 101.armed and execs zsh -l -i. ~/.claude/run/kitty-pane-cmd/ now holds only 126.armed and 37.armed (MEASURED).
- 16:11:30 CDT (wait, corrected): da0f61ce6 was committed at 11:11:30 CDT and went live in ~/Development/claude-infrastructure at 11:23:51 CDT (16:23:51Z) via 9451c8336. Evidence: reflog; 67a27da86 and 81ef70b27 lack it, 9451c8336 has it (merge-base --is-ancestor).
- 15:56:42Z: kte-w3 lead e881b713 hand-closes ids 92-100 with `kitty @ close-window` (bash-commands.log:8631). Its transcript line 3762 says 'Exactly 9 windows (ids 92–100)', so pane 101, from a different lead, was missed.
- 21:45:29Z: the RA lead reports 'LANDED 11bf13c5, CI green' and retires at 21:46:01Z (transcript lines 2569, 2594). Pane 76 is closed by cc-pane-runner at 21:46:39Z (kitty-pane-actions.jsonl: wid 76, safe-not-last).
- 23:27:44Z: a sibling investigator's dry-run cc-pane-close logs pane 101 verdict 'refused': 'no session registration for this pane in the running kitty's lifetime, and no exit record saying its launch never started claude' (pane-close.jsonl:154).
- ~23:28Z, now: `kitty @ ls` shows pane 101 still open as a bare zsh with no children (`pgrep -P 44732` returns nothing).

## What happened
Pane 101 is the ra-shut teammate pane that lane RA's lead (session d093011f, claude pid 64334) asked for at 09:25:46Z. At about load 450, kitty's remote control stopped answering for hours. it2-kitty's `timeout` killed the `kitty @ launch` client after 15s and reported rc=124. Claude Code then told the lead the split had failed, so no one recorded the pane id and no command was ever delivered to it. The lead gave up on teammate panes, built ra-shut's items itself, landed everything (11bf13c5, CI green) and retired at 21:46Z. kitty had already received the launch request, though, and completed it about 5.5 hours late, at 15:00:00Z. The armed cc-pane-runner in the new pane waited its 300s for a command file that would never come. The code live at that time (0c4a29f7d) then turned the pane into an interactive login shell instead of closing it, and printed 'no command arrived within 300s · pane is an ordinary shell', which the 56-cell cap cut to '…ordinary…'. Nine sibling panes (92-100) from the kte-w3 lead's failed splits met the same fate an hour earlier. That lead closed them by hand at 15:56Z and shipped da0f61ce6. It only looked at its own nine, so pane 101 was left. The out-of-band closer also refuses pane 101, because the no-command path writes no exit record and no session ever registered there.

## Disposition: close
Steps for the operator (I changed nothing):
(1) Re-confirm pane 101's foreground is the bare zsh with no children. Measured just now: `pgrep -P 44732` returns nothing.
(2) Close kitty window 101 by hand: the pane menu or ctrl-d in it, or `kitty @ close-window --match id:101`. It is 1 of 3 panes in os-window 4, so it is not the last pane of the window and the fullscreen-crash concern does not apply.
cc-pane-close / cc-husk-sweep will NOT do it: they refuse it, as the 23:27:44Z dry-run shows in pane-close.jsonl:154.

No work is at risk:
- git -C ~/Development/.worktrees/b13/r23-ra status: clean.
- HEAD 11bf13c5 is an ancestor of origin/main; rev-list origin/main..HEAD = 0.
- Only branch b13/r23-ra remains (no r23-ra-shut).
- No custody or debt: the pane never ran a session, there is no 101.cmd, and 101.armed is already gone.
- A stale ~/.claude/run/pane-exit/101.launch from Oct 19 (an earlier kitty's pane 101) is harmless.

Other ownerless no-command shells still open: none. In `kitty @ ls` (~23:28Z) the only bare-zsh panes are 42, 85 and 101. Only 101 is an armed-no-command shell (CC_PANE_CMD_DIR set, CC_PANE_CMD unset). 42 and 85 are env-mode handoff-fire panes, investigated separately. Panes 92-100 were closed at 15:56:42Z.

## Message defects
- '⚠ no command arrived within 300s · pane is an ordinary…' is truncated. The full logged fact is 'pane is an ordinary shell' (pane-say.jsonl:756). lib/cc-say.sh caps every line at 56 cells ('never above 56', _cc_say_w). '⚠ no command arrived within 300s · pane is an ordinary shell' measures 60 cells (counted), so cc_say_cut drops the fact's last word to fit 55.
- Even untruncated the line cannot be acted on. It does not say what the pane was for (teammate ra-shut of lane RA's lead, pane 76 / session d093011f), that the spawner was told the split failed so nobody owns it, that nothing will close it, or what to do (close it; no work lives here). 'Ordinary shell' sounds intentional and safe to keep, but it is a husk.
- 'Last login: Thu Oct 22 09:10:56' is the PREVIOUS login, i.e. pane 100's at 14:10:56Z, not this pane's start (10:00:00 CDT). It mis-dated the event in the brief.
- The title stays the default 'chrisren@MacBookPro:~/…/r23-ra'. Unlike watchdog-handled panes there is no verdict title or ⛔/✅ marker, so the pane cannot be told apart from a human shell in the tab bar.
- The cc-pane-close refusal 'no session registration for this pane in the running kitty's lifetime, and no exit record saying its launch never started claude' (pane-close.jsonl:154) is jargon and a dead end. It refuses without saying that the pane is an armed no-command shell, that it is safe to close by hand, or how to do it.
- In the post-fix code path, a guard refusal on this pane would print 'last pane of a fullscreen window · close it by hand'. That is false when the guard verdict is kitten-failed (unreadable), not fullscreen-last; pane 42 shows the same mismatch.

# census

Census, measured with `kitty @ ls` at 18:25 CDT: 25 kitty panes in 7 OS windows. 22 run a live claude (18 titled ✳, 3 ◐, 1 ◑). The other 3 are husks: 85 "⛔ KILLED 570d3917", 42 "✅ closed 18f95342", and 101 with the default shell title. No pane is a plain operator shell. Run now, `cc-husk-sweep --list` returns the same 3 husks. `cc-pane-close --dry-run` answers WOULD CLOSE for 42 and 85 and REFUSED for 101. Nothing ever calls it.

Root causes, all in current code:
(1) Every close of a lead's pane is decided once, at the moment of death. The runner decides right away; the watchdog decides about 65 s later and makes a single cc-pane-close call. No periodic sweeper ever re-checks a husk after conditions change: kitty remote control comes back, custody is returned, the work lands, or the session is resumed elsewhere and finishes. pane-close-retry closes only teammate rows.
(2) One failure both creates husks and keeps them. When kitty remote control is deaf (pane-close-retry.log shows it deaf around 03Z and again 09-14Z on Oct 22):
- splits lose their answer (pane 101);
- close-window calls time out (pane 42);
- a lead resumes its dead peer headless instead of in its pane (pane 85);
- the fullscreen-guard kitten fails, and its rc 3 vetoes every close from inside the pane.
(3) A new defect. The headless 570d3917 ran `handoff-fire.sh self-close --terminal`. It had inherited KITTY_WINDOW_ID=16, and the self-identity gate uses the process tree, which reads "mine" for anything the lead started. So at 23:16:46Z it closed the LEAD's pane 16 (lead 666022fd exited 4 s later) and left its own husk 85 open.
(4) Messaging is wrong in three ways:
- fullscreen-guard rc 3 means both "last pane of a fullscreen window" and "kitty did not answer", and the runner prints "last pane of a fullscreen window" for both;
- the watchdog keeps the title "✅ closed" while swapping the body row to "ended, reason unknown", though the reason (prompt_input_exit) is known;
- the KILLED and custody rows are painted once and never repainted after custody is returned.

Prior fixes that hold:
- F-a close-from-inside (for clean exits when kitty answers);
- F-c teammate arm;
- assistant-only close reader;
- F-d sweeper identity, which resolved all 3 correctly;
- COLLECTED verdict;
- verdict painted into the pane.

Recurring:
- kitty remote-control deafness;
- self-close close-failure with no durable row;
- no repaint or close when custody is returned (the husk-triage gap);
- a close that still depends on kitty remote control, now through the fullscreen guard;
- self-close queue rows that never expire (23 rows, 14 from older kitty processes; the stale self-close-85.json from Oct 1 points at today's pane 85, logged 2,322 times).

Who sent the external SIGTERM to 570d3917 at 09:12:40Z is unknown: bash-commands.log only begins at 10:24Z. Read-only throughout. The only commands run against the fleet were `kitty @ ls`, `cc-husk-sweep --list` and `cc-pane-close --dry-run`. The dry run appends would-close/refused rows to pane-close.jsonl.

- **Census: 25 panes, 22 live claude, 3 husks (85, 42, 101), 0 operator-only shells** (census): MEASURED (`kitty @ ls` snapshot /tmp/kls-census.json, 18:25 CDT; foreground_processes checked per pane). 25 panes in 7 OS windows: os2 {2,3,4,5}, os4 {7,11,101}, os7 {20,13,12,59,70}, os8 {24,25,103,124}, os10 {42,47,91}, os17 {21,67,117}, os18 {71,85,128}. 22 have a claude process in the foreground (titles: 18 '✳', 3 '◐' [21,117,128], 1 '◑' [103]). Pane 128 is the session that started this investigation. 0 panes are a plain operator shell, 0 are 'other'. End-state titles: '⛔ KILLED' ×1, '✅ closed' ×1, default shell title in a worktree ×1.
HUSK 85 (os18): cwd ~/Development/agent-context-sync, title '⛔ KILLED 570d3917', /bin/zsh -l -i at the prompt.
- Pane created 07:36:41Z, about 15h48m ago.
- claude died 09:12:40Z (husk about 14h12m).
- Last pane-say: 2026-10-22T09:19:00Z, lead-crash-watchdog: 'cause: external-sigterm (exit 143, signal 15) · work … dirty:10 · not yours to resume: its originator (pane 16) holds custody'.
HUSK 42 (os10): cwd …/wt-cc-000146-45877, title '✅ closed 18f95342'.
- Created 2026-10-21 21:58:59Z, about 25h26m ago.
- claude exited 0 at 03:07:18Z (husk about 20h18m).
- Last pane-say: 03:08:31Z, watchdog: '18f95342 pane kept — kitty remote control is down and a kitty window is in native fullscreen (or unreadable)'.
HUSK 101 (os4): cwd …/b13/r23-ra, default title.
- Created 15:00:00Z (10:00 CDT). The 'Last login 09:10:56' on screen is the PREVIOUS login, not this pane's start.
- Last pane-say: 15:05:00Z, cc-pane-runner: 'no command arrived within 300s · pane is an ordinary shell'.
- Spawner: CC_SPAWN_ROOT=p64334 (claude pid 64334, close-record 64334-1792653733.json). No pane-spawns.jsonl row exists for it; spawn records have a gap from 08:11Z to 15:51Z.
`cc-husk-sweep --list` (MEASURED) gives: 101 UNKNOWN/unresolved · 42 COLLECTED ('close the pane') · 85 MOVED→pane 16, DEATH suspected-oom-large-context, CLOSE yes, WORK clean ('close this pane with cc-pane-close'). Evidence: kitty @ ls (created_at, foreground_processes, env: 101 has CC_PANE_CMD_DIR and no CC_PANE_CMD); pane-say.jsonl ts 1792660740 (85), 1792638511 (42), 1792681500 (101); close-records/54386-1792654623.json ended_at 09:12:40Z exit 143 sig_reached_wrapper TERM; cc-husk-sweep --list output
- **End-of-life state machine (current code): which component decides and how each path ends** (behavior): Each path below gives what happens, who decides, what is painted, and whether the pane ends CLOSED or KEPT. [NOBODY] marks a pane KEPT with nothing scheduled to ever close or resume it.

Runner panes (handoff-fire in env mode, CC teammates in file mode, lr-lib), via `_launch` → `_close_on_exit`, cc-pane-runner:504-512 and 213-234:
- P1. Clean exit 0 (/exit, self-close's /exit, approved teammate shutdown). `_close_pane` (:239-287) checks in order:
  - recycle pending → KEPT, and the relaunch is typed (by design);
  - kitty-fullscreen-guard --scope pane --mode refuse (:277) returns rc 0 → the runner exits → CLOSED;
  - the guard returns rc≠0 → KEPT with '⚠ last pane of a fullscreen window · close it by hand' (:278-279). The watchdog then picks the pane up (P1b).
- P1b. Watchdog RECYCLE:clean-exit (lead-crash-watchdog.sh:1932-1940) sets the title '✅ closed <sid8>'.
  - Dirty or unlanded cwd: no countdown → KEPT [NOBODY].
  - Clean cwd: `cc-pane-close --dry-run` is asked first (:1991-2002). If it agrees, the row is '✓ ended cleanly · closing in 20s' → `pane_verdict_close` (:2044-2059) → CLOSED. If it refuses, the row becomes '⚠ <sid8> ended, reason unknown ▶ cc-husk-sweep' → KEPT [NOBODY]. This is pane 42.
- P2. rc 75 (launch queued) → same gates as P1.
- P3. Non-zero exit before claude started, with a durable owed record → same gates as P1.
- P4. rc 143, SIGTERM from any sender → `_kept_line` '⚠ the fleet launch line exited 143 · shell kept for resume' (:296-301) → KEPT. classify_death maps 143 to external-sigterm (:901) unless a teardown marker, desk retirement, teammate, or recycle phrase is found. CRASH branch (:1941-1966): title '⛔ KILLED <sid8>', row '▶ cc-husk-sweep --pane N', plus a custody row and a dirty-work row. This branch NEVER calls the closer → KEPT [NOBODY]. This is pane 85. With custody already collected the title is '✅ collected', 'do not resume' → still KEPT [NOBODY].
- P5. Other non-zero exits (1, 137 OOM/force, 139 crash, error-exit) → KEPT; watchdog CRASH '⛔ KILLED' → KEPT [NOBODY].
- P6. SIGHUP (kitty or any pane close) → the pane is already closing → CLOSED. Watchdog: 'pane verdict NOT PAINTED — the pane closed'.
- P7. Limit or transplant move. pane_lr_facts (:1884-1903):
  - moved-live → '✅ moved … closing in 20s' → closer → CLOSED;
  - stranded → '✗ stranded' plus requests/<sid>.cc-lr.json → KEPT, owned by the lr poller (scheduled).
  - An lr launcher refusal (rc 3/9 with claude started) → KEPT [NOBODY].
- P8. Teammate retired. Exit 0 → P1. Watchdog RECYCLE:retired-teammate '✅ retired … closing in 20s' → CLOSED. pane-close-retry teammate rows retry durably. Exception: 'retired mid-task' → KEPT [NOBODY] (deliberate warning).
- P9. No command delivered to an armed file-mode pane.
  - Code live at 10:05 CDT (0c4a29f7d, cc-pane-runner:530): `_fallback` → KEPT [NOBODY]. This is pane 101.
  - Since da0f61ce6 (live 11:12 CDT): `_no_command` → `_close_pane` (:545-550) → CLOSED only if the fullscreen guard answers. Otherwise KEPT with the false text 'last pane of a fullscreen window', and still no exit record (see the gate finding).
- P10. Empty command, CC_PANE_CMD_DIR unset, or not kitty → `_fallback` → KEPT [NOBODY] (by design: 'a human's to read').
- P11. CC_PANE_CLOSE_ON_EXIT=0 → KEPT (kill switch).

Other paths:
- P12. self-close --terminal. The detached watcher closes the pane with `it2 session close`, up to 4 tries → CLOSED. If all 4 fail (rc 124 under deaf kitty), it prints '!! PANE CLOSE FAILED … is a HUSK', writes an hf_alarm class=husk-pane, and queues NO row. claude then exits, and P1/P1b apply → KEPT [NOBODY] (pane 42). If the pre-close probe gets no answer: abort before /exit and write a self-close queue row. The drainer pages once and notifies once and never closes (P12b, see the gate finding).
- P13. self-close run by a headless `claude -p` child inside the lead's process tree → closes the LEAD's pane (see the separate finding).
- P14. Operator claude in a plain `zsh -l` (cc-close-attrib wrapper). It closes from inside only with CC_CLOSE_PANE_ON_EXIT=1, which defaults to OFF (cc-close-attrib:649-651). Otherwise the watchdog's P1b decides.
- P15. cc-reaper / cc-teardown retire a LIVE idle session → teardown closes the pane → CLOSED. These tools never enumerate husks (their scope is live registered sessions, cc-reaper:44-60). Evidence: bin/cc-pane-runner:100-105,213-234,239-287,296-308,504-512,545-550; hooks/lead-crash-watchdog.sh:577-586,745-915 (901),1884-1966,1970-2012,2034-2059; bin/cc-close-attrib:628-681; git show 0c4a29f7d:bin/cc-pane-runner:530; live-checkout reflog: 0c4a29f7d live 09:24 CDT, 81ef70b27 (contains da0f61ce6) live 11:12 CDT
- **The only automatic closer for a lead's husk is one-shot; nothing re-checks husks once conditions change** (behavior): MEASURED: callers of cc-pane-close are (a) lead-crash-watchdog, once per death, about 45 s settle + 20 s grace, and only when the painted row has a countdown; (b) pane-close-retry, for TEAMMATE rows only. cc-husk-sweep only lists and resumes. cc-reaper, team-orphan-reaper, teammate-reap-alarm and autonomy-sweep do not close husks (grep finds no non-comment call to cc-pane-close or cc-husk-sweep in it2-kitty, cc-teardown or lr-lib). autonomy-sweep only counts 'husk-pane' alarms in a desk summary.
The closer's own facts changed after the one-shot decision on both husks:
- Pane 42: refused at 03:08:31Z because kitty remote control was deaf. It now answers, and os-window 10 holds 3 panes. Dry run today: 'WOULD CLOSE … custody abandoned/returned … via kitty remote control'.
- Pane 85: CRASH branch, so no close was ever attempted. Its session later finished headless: 'Good to close: yes' at 23:15:42Z, custody returned at 23:14:56Z, worktree clean. Dry run today: 'WOULD CLOSE … Good to close: yes'.
Right now both are closeable and nothing will close them. Long-term fix (INFERRED): a periodic husk reconciler (e.g. in the 10-min teammate-reap-alarm tick, or on every SessionEnd and custody return) that runs `cc-husk-sweep --json` and hands every row whose verdict is COLLECTED, MOVED or DONE, or that has a closer-agreeing dry run, to `cc-pane-close`, gated on kitty answering. It would also repaint the pane when its verdict changes. Evidence: cc-pane-close --pane 42 --pane 85 --pane 101 --dry-run (run 18:2x CDT): 42 WOULD CLOSE, 85 WOULD CLOSE, 101 REFUSED; pane-close.jsonl 2026-10-22T03:08:31Z pane 42 refused; lead-crash-watchdog.log:66730 (85 painted, no close call); custody jsonl return row 2026-10-22T23:14:56Z fire-b13-r23-K; scripts/pane-close-retry.sh:87-99,136-160
- **Headless resume + self-close closed the LEAD's pane 16 and left the peer's own husk 85 open** (behavior): MEASURED sequence:
- Lead 666022fd ran in pane 16, tty ttys031, pid 65517.
- At 12:25Z it resumed peer 570d3917 HEADLESS (`claude -p`, entrypoint sdk-cli). Its own prompt says why: 'kitty remote control is down on this Mac, so no pane can be opened'. Husk 85 already existed, but typing a resume into it would also have needed kitty.
- The child inherited KITTY_WINDOW_ID=16. The watchdog registered it as 'pane=16 tty=none' (lead-crash-watchdog.log:66758).
- At 23:15:43Z the child ran `handoff-fire.sh self-close --terminal`, which logged 'self-close armed for 16' (/tmp/handoff-selfclose-16-1792710988.log: 'sid=16 tty=/dev/ttys031 … closed pane 16 (attempt 1/4)').
- close-attrib.jsonl 23:16:46Z: id_requested 16, verdict closed. Lead pid 65517's close record shows ended_at 23:16:40Z, exit 0. The watchdog logged 666022fd as 'pane closed (ttys031 is gone)'. Window 16 is absent from today's census.
The child's real husk, pane 85, was never targeted.
Cause: verify_self_pane (scripts/handoff-fire.sh:2555-2570) accepts 'mine' from process-tree ancestry. A `claude -p` started by the lead's Bash tool IS a descendant of pane 16, so the gate passes. Nothing checks that the pane's registry row names the CALLER's session_id, and nothing treats CLAUDE_CODE_ENTRYPOINT=sdk-cli as 'no pane'. bin/cc-close-attrib:641-645 already guards this exact shape: a nested Bash-tool `claude -p` 'stands down, where a plain walk would have reached the OUTER session's login shell and closed its window'. handoff-fire has no such guard.
Side effects:
- The watchdog classified the headless run's normal end as CRASH suspected-oom-large-context. A `-p` run has no close record, so the >4 MB transcript-size heuristic fires (classify_death, lines 745-915).
- The sweeper now shows 85 as 'MOVED→pane 16' to a pane that no longer exists.
Fix (INFERRED): in self-close, refuse, or retarget to the session's own registered pane, when the registry row for the env pane names a different session_id, or when the caller is headless (sdk-cli). The headless resume path should also unset KITTY_WINDOW_ID and ITERM_SESSION_ID, as hf_bgjob_argv already does at handoff-fire.sh:~7690. Evidence: 570d3917 transcript (.claude-next/…b13-r23-k/570d3917….jsonl) line 824 (entrypoint sdk-cli, '[lead 16] … resumed you HEADLESS'), last tool call 23:15:43Z; /tmp/handoff-selfclose-16-1792710988.log; close-attrib.jsonl:1242; close-records/65517-1792654883.json; lead-crash-watchdog.log:66758,66935,66939-66940; scripts/handoff-fire.sh:2555-2580,14632-14645
- **Close gates that veto, and whether a veto leaves anything that retries** (behavior): For each gate: where it lives, what record a veto leaves, and whether anything retries.
- Recycle pending (cc-pane-runner:250, cc-close-attrib:664; lib/pane-recycle-pending.sh fails safe to KEEP). Record: the recycle lock under ~/.reso/limit-recover/locks, owned by handoff-fire's watcher. If the relaunch never comes and the holder dies, nothing re-runs the close → abandoned.
- Fullscreen guard, from inside the pane (cc-pane-runner:277-281). Record: one kitty-pane-actions.jsonl row plus a pane-say warn. No retrier → abandoned. rc 3 also covers 'kitten-failed' (kitty did not answer), so ANY kitty remote-control outage at exit time keeps the pane. That is pane 42 at 03:07:18Z (state=UNKNOWN, types=None).
- Fullscreen guard / remote control down, in cc-pane-close (:440, :454; any-fs refuses when remote control is down). Record: a refused row in pane-close.jsonl. Retried only for teammate rows (pane-close-retry). For leads → abandoned (pane 42).
- Dirty or unlanded worktree. The watchdog drops the countdown (:1935-1937) and cc-pane-close gate 4 (:431) refuses. No record that would trigger a retry once the work lands → abandoned.
- 'Nothing says it meant to end' (gate 3, :426). Refused row, cc-husk-sweep hint → manual triage.
- Open custody. Not a close veto in cc-pane-close (a return or abandon ENABLES a close, :421). It changes the banner to 'pane N holds custody · tell it'. The CRASH branch never closes anyway. A later return or abandon triggers neither a repaint nor a close → abandoned (pane 85: returned 23:14:56Z, banner still stale).
- No registration and no exit record (gate 1, :356). The no-command path writes no pane-exit record, so the 'never launched' arm can never fire → abandoned permanently (pane 101; refused again in today's dry run).
- CC_PANE_CLOSE_ON_EXIT=0, CC_PANE_VERDICT_CLOSE=off, CC_KITTY_FS_GUARD=off: kill switches, intentional. None was set in any pane's env (MEASURED from kitty @ ls env).
- Self-close probe got no answer. Record: a DURABLE row ~/.claude/state/pane-close-queue/self-close-<pane>.json. drain_self_close (pane-close-retry.sh:87-99) only pages once and cc-notifies once. It never closes, never removes the row, and skips the kitty-generation check that teammate rows get → rows live forever.
  - MEASURED: 23 self-close rows, 14 of them older than the running kitty (started 2026-10-21 14:54:58 CDT).
  - self-close-85.json (sid 705115e9, 2026-10-01) now names today's live husk 85 and has logged 'already paged — held for handoff-fire' 2,322 times.
- Self-close close failed after 4 tries (rc 124). NO queue row, only an hf_alarm (push=refused-rc3) → abandoned (pane 42).
- Teammate close failure. Durable row, drained every 10 min and on SessionEnd, with a SIGHUP fallback when kitty is deaf → the ONE path that actually retries. Evidence: bin/cc-pane-close:341-461; bin/cc-pane-runner:239-287; scripts/pane-close-retry.sh:87-160; ls ~/.claude/state/pane-close-queue (23 self-close-*, 1 recycle-*); grep -c 'pane=85' pane-close-retry.log entries; kitty-pane-actions.jsonl 2026-10-22T03:07:18.365Z wid 42 kitten-failed rc 3; /tmp/handoff-selfclose-42-1792638399.log ('PANE CLOSE FAILED after 4 attempts … hf_alarm class=husk-pane … push=refused-rc3'); ps -o lstart= -p 1881
- **One failure creates the husks and also keeps them: kitty remote control was deaf for hours on Oct 22** (behavior): MEASURED from pane-close-retry.log rows ('kitty unresponsive — N row(s) held' vs 'terminal answers'): deaf at 03:07Z and 03:44Z, answering 04-07Z, deaf 09:12Z → 14:06Z, answering again from 15:51Z. Coarse: only one probe per run.
- Pane 42: self-close's 4 close-window calls timed out (rc 124 at 03:07:40, 03:08:13, 03:08:45, 03:09:17Z, close-attrib.jsonl). The runner's fullscreen guard then failed (kitten-failed), and the watchdog's dry run refused ('remote control is down…') — all during the 03Z deaf window.
- Pane 85: the external SIGTERM at 09:12:40Z falls at the start of the 09-14Z window. Because of the outage the lead resumed the peer headless rather than in pane 85 (its prompt says so). That led to the wrong-pane self-close.
- Pane 101: created 15:00Z, before the 15:51Z recovery. It has no pane-spawns row and no command arrived. That fits da0f61ce6's own diagnosis ('the split's answer was lost … kitty finished the launch after it2-kitty had reported failure', cc-pane-runner:538-543) — INFERRED for this pane.
Forward-looking residual (INFERRED from code): with da0f61ce6 live, an orphaned armed pane created during an outage still goes through `_close_pane` → fullscreen guard → kitten-failed → KEPT with the text 'last pane of a fullscreen window · close it by hand'. The guard needs exactly the remote control whose outage orphaned the pane, and no row is queued to retry it. Prior research (husk-panes-2026-09-30 third round) found that kitty's KittyPeerMon thread exits on an accept() error, an upstream defect that is still not fixed. Evidence: pane-close-retry.log hourly tally (DEAF 2026-10-22T03, 09, 11, 12, 14; ANSWERS 04-07, 15+); close-attrib.jsonl 03:07:40-03:09:17Z unverified-rc124 ×4; kitty-pane-actions.jsonl gap 14:06Z→15:51Z; pane-spawns.jsonl gap 08:11Z→15:51Z; 570d3917 transcript line 824
- **Pane text is wrong or stale on all three husks** (messaging): (a) Pane 42 says '⚠ last pane of a fullscreen window · close it by hand'. The guard's actual verdict was kitten-failed / state=UNKNOWN, meaning kitty did not answer. Whether 42 was the last pane was never read. INFERRED that it was not: at 22:12Z the menu moved it into a window that already held 2 panes, and it now shares os10 with 47 and 91. Cause: cc-pane-runner:277-279 prints one text for every rc≠0 from the guard.
(b) Pane 42's title is '✅ closed 18f95342' while its row says '⚠ 18f95342 ended, reason unknown'. When the closer refuses, paint_pane_verdict rewrites the countdown row but never the title (lead-crash-watchdog.sh:1984-2005). 'reason unknown' is false: the same paint logged 'exited on its own (reason: prompt_input_exit) … work clean'. The real reason (kitty remote control down) goes only to the pane-say log.
(c) Pane 85 still says 'pane 16 holds custody of its work · tell it' and 'uncommitted work in r23-k'. Custody was returned at 23:14:56Z, the work landed (CI green, clean tree), and pane 16 no longer exists. The paint happens once, at death, and nothing repaints it. This was already flagged as a gap in husk-triage-2026-10-01 § Gaps item 2, and the fix it proposed (repaint on cc-custody return/abandon) was never built: grep finds no repaint or close hook in bin/cc-custody or lib/pane-custody.sh.
(d) Pane 85's '✗ killed (external-sigterm)' names no sender. classify_death maps every exit 143 to external-sigterm (:901). The sender could not be traced here because bash-commands.log starts at 10:24Z.
(e) Pane 101's '⚠ no command arrived within 300s · pane is an ordinary shell' gives no action and names no spawner, though the env carries CC_SPAWN_ROOT=p64334. cc-pane-close cannot ever close it.
(f) The headless run's normal end was logged as CRASH suspected-oom-large-context, and cc-husk-sweep's DEATH column for 85 now shows that. Evidence: pane-say.jsonl 1792638438 (runner fullscreen text), 1792638507/1792638511 (watchdog detail 'reason: prompt_input_exit' and 'ended, reason unknown'); kitty-pane-actions.jsonl 2026-10-21T22:12:21Z kitty-pane-menu 'Reboot resume T3 prep and land — 2 panes'; hooks/lead-crash-watchdog.sh:1933,1991-2005,901; custody return row 23:14:56Z; lead-crash-watchdog.log:66935
- **Prior research: what was fixed and what recurs today** (both): FIXED and holding (MEASURED today):
- husk-panes-09-30 RC2 / F-a: the runner closes from inside on rc 0, rc 75 and never-started-owed exits.
- RC6 / F-c: retired-teammate arm.
- RC7: assistant-only close reader.
- RC8 / F-d: the sweeper resolves all 3 husks to the right sid, launcher and cwd through the watchdog arm.
- husk-triage gap 3: the COLLECTED verdict exists (pane 42 is COLLECTED).
- desk-husk-09-08: the verdict is painted into the pane (85 and 42 got banners).
- lr-wake RC4 (partly): the closer is asked before 'closing in' is painted, and it has a never-launched arm.
- husk-mass-sigterm-10-21: kill-guard fix; the 04:13 death page was DELIVERED (lead-crash-watchdog.log:66725).

RECURS:
- husk-panes RC3 (kitty remote control deaf, KittyPeerMon dies): unfixed upstream; outage windows on Oct 22 at 03Z and 09-14Z.
- RC5 (self-close close-failure leaves nothing durable): only probe-no-answer queues a row; a close that fails after 4 tries does not (pane 42).
- F-a's goal of 'remove the dependency on kitty remote control for closing' was undone by the 10-15 fullscreen guard: kitten-failed → KEEP. The kitty-lastpane-move-10-19 finding (stock kitty, fsfix false, relax never fires) keeps it strict.
- husk-triage gap 2 (a killed lead whose work is later ruled done keeps its banner; nothing repaints or closes on a custody return): pane 85.
- husk-mass-sigterm 'Husk design' (KILLED panes intentionally kept, with no auto-resume and no auto-close afterwards): pane 85 stayed open even after its work landed.
- F-b queue: self-close rows never expire and outlive the kitty generation, so pane-id reuse aliases them (self-close-85.json from Oct 1).
- lr-wake RC4 'pane verdicts lie': the fullscreen and reason-unknown texts above.

NEW, not in any prior doc:
- self-close from a headless child closes the lead's pane;
- no periodic husk reconciler;
- the no-command path writes no exit record, so cc-pane-close can never close such a pane. Evidence: docs/research/husk-panes-2026-09-30.md:25-62,73-90; husk-triage-2026-10-01.md:30-60; husk-mass-sigterm-2026-10-21.md:6-14,59-95; desk-husk-2026-09-08.md:7-19; kitty-lastpane-move-2026-10-19/README.md:5-11,90-117; lr-wake-incident-2026-10-18/REPORT.md RC2/RC4; cc-husk-sweep --list output; cc-pane-close --dry-run output

# messages

I audited every message these components can paint into a pane at end of life, compared all three real screens against live facts, and traced each one back to code. Everything was read-only. The one side effect: my three `cc-pane-close --dry-run` runs each appended a log row to pane-close.jsonl. No pane, process or git state was touched.

**Why it happens.** Nothing owns the pane's final verdict. Up to four writers paint a dead pane at different moments from different facts:
- Claude Code's own exit text;
- cc-pane-runner, when the command returns (and it routes the guard's raw stderr into the pane at bin/cc-pane-runner:277);
- the guard's own refusal line, through that redirect;
- lead-crash-watchdog, 1-6 minutes later (body rows plus an OSC-2 title at :2005).

Nothing ever repaints, so each pane keeps whichever wording was true when its writer ran.

**Defects that make the wording wrong:**
- **Title not recomputed.** The title comes from the death class before the closer is asked (:1933). When the closer refuses, only the body row is swapped to 'reason unknown' (:1996), and both reasons were actually known.
- **Wrong fullscreen claim.** The runner says 'last pane of a fullscreen window' whenever the guard refuses. On pane 42 the guard had actually failed to read the window (kitten-failed).
- **Fixed width.** Rows are fitted to a hard-coded 56 cells (:1823), but the panes were about 38 columns wide when painted, so 'tell it' broke onto its own line.
- **Fragile rows and titles.** The watchdog writes behind zsh's prompt and sets the title once. A prompt redraw erased pane 42's ▶ row (inferred), and oh-my-zsh resets the title at each prompt.

**The pane-85 behaviour bug.** Lead 16 resumed session 570d3917 headless, and the headless run inherited KITTY_WINDOW_ID=16. Its self-close at 23:16:46Z then closed the lead's own pane 16 while the lead was mid-turn. The watchdog logged that lead's death as a clean exit and painted nothing. Pane 85, the pane that should have closed, kept a stale verdict. Every row on it is now false: the session finished with 'Good to close: yes', the worktree is clean, and pane 16 no longer exists. Its ▶ command, cc-husk-sweep, now wrongly reports 'MOVED→pane 16'.

**Pane 101.** It never ran claude and gets no title at all, only a row cut to 'pane is an ordinary…'. The no-command path never writes the pane-exit record, so cc-pane-close refuses it for good. Seven such panes (95-101) timed out today.

**What the three panes should be.** Measured with `cc-pane-close --dry-run`: 85 would close and 42 would close. 101 is refused by the closer, though nothing ever ran there, so it should be closed too. None of the three should be resumed.

**Against the existing design.** The code mostly follows g-message-design.md: the one-line renderer, the 56-cell budget, detail to the log. Three deviations: the guard output never moved to the log, the runner still repeats the watchdog's death line, and the fullscreen row dropped 'kept'. The design itself has the gaps: no single final writer, no repaint, no set of end-states, an assumed width, and a title kept even when the close is refused.

**Proposed fix.** One idempotent writer, `cc-pane-verdict`, recomputed on every relevant event. It uses six end-states (DONE, RESUME, OWNED ELSEWHERE, NOTHING RAN, KEPT ON PURPOSE, CAN'T TELL), each with fixed wording: one title, at most 2 rows, one re-validated command. It sets the title with `kitty @ set-window-title` so the shell cannot overwrite it, fits rows to the real width, and keeps internal terms off the screen. A structural option: the runner stays as a small verdict screen instead of handing the pane to a shell. Three behaviour fixes go with it:
- a session with no tty never self-closes by KITTY_WINDOW_ID;
- the no-command path writes the pane-exit record;
- a periodic close retry runs after kitty outages.

No files were written; everything is in the findings above.

- **No single final writer: up to four writers paint a dead pane at different times, and only one of them sets the title** (both): End-of-life output reaches a pane from four independent sources, and nothing reconciles them:
(1) Claude Code's own exit text.
(2) bin/cc-pane-runner, when the command returns. That is _kept_line at :296-308, the guard-refusal line at :277-279, and _fallback at :102.
(3) kitty-fullscreen-guard's stderr, which the runner redirects into the pane.
(4) hooks/lead-crash-watchdog.sh, about 1-6 minutes later. It writes the body rows plus an OSC-2 title straight to the tty (:2005).
Only the watchdog sets a title, so a pane the watchdog never handles keeps the shell's default title (pane 101). Each writer works from the facts it had at its own moment. The later rows sit under the earlier ones and contradict them: on pane 42 the runner says 'close it by hand' and the watchdog says 'ended, reason unknown ▶ cc-husk-sweep'. Nothing ever revises a row after it is painted. Evidence: MEASURED from ~/.claude/logs/pane-say.jsonl:
- Pane 42: runner row :641 at ts 1792638438 (03:07:18Z). Watchdog rows :642 at 03:08:27Z and :644 at 03:08:31Z.
- Pane 85: runner row :707 at ts 1792660364 (09:12:44Z). Watchdog rows :711-713 at 09:19:00Z.
MEASURED screens (`kitty @ get-text --extent all`):
- Pane 85 shows 'Resume this session with: claude --resume 570d3917…' / '⚠ fleet launch line exited 143 · shell kept for resume' / prompt / '✗ 570d3917 killed (external-sigterm)' / '▶ cc-husk-sweep --pane 85' / '⚠ pane 16 holds custody of its work · ' / 'tell it' / '⚠ uncommitted work in r23-k'.
- Pane 42 shows the CC resume line / the raw guard line / '⚠ last pane of a fullscreen window · close it by hand' / '⚠ 18f95342 ended, reason unknown'.
Only title writer at end of life: `grep '\033]2;'` finds hooks/lead-crash-watchdog.sh:2005 alone. The cc-resume-layout.sh set-window-title calls are not end-of-life.
- **The fullscreen guard's raw debug line leaks into the pane through the runner's `>&2`** (messaging): cc-pane-runner runs the guard with stdout redirected to stderr (`>&2`), and the pane's stderr is the terminal. The guard's refusal print at bin/kitty-fullscreen-guard:990-993 (`{TOOL}: refused ({verdict}) kitty window {wid} scope= mode=: state= types= onscreen=`) therefore lands on screen word for word. The runner then adds its own summary line under it. g-message-design §5.3 B says the guard output 'goes to the log', and this redirect was never moved. The fix is to redirect the guard to the log: `2>>log`, or `>/dev/null 2>&1`, since the guard already writes its JSON verdict row to kitty-pane-actions.jsonl. Evidence: - bin/cc-pane-runner:277 is `if ! cc_run "$_c" --window "$KITTY_WINDOW_ID" --mode refuse --scope pane --tool cc-pane-runner >&2; then`. The same line was live at the event time as line 267 of 07ad2628e^ (MEASURED via git show).
- bin/kitty-fullscreen-guard:991 holds the f-string.
- Pane 42 screen (MEASURED): 'kitty-fullscreen-guard: refused (kitten-failed) kitty window 42 scope=pane mode=refuse: state=UNKNOWN types=None onscreen=None'.
- docs/research/lr-wake-incident-2026-10-18/g-message-design.md:366-367 says 'Moves out: … the guard path go to the log'.
- **'last pane of a fullscreen window' is asserted when the guard actually could not read the window (kitten-failed), and pane 42's window had 3 panes** (both): The guard's rc 3 covers three cases: fullscreen, unreadable and not-found (runner comment :256-258). The runner always prints the fullscreen case to the operator, and keeps the 'or unreadable' wording only in its CC_SAY_DETAIL (:278). Pane 42's guard verdict was kitten-failed: kitty remote control did not answer, so the state was UNKNOWN. 'Close it by hand' is also an unsafe instruction for a pane that really is the last one of a fullscreen window: Ctrl-D in that pane is exactly the 2026-10-15 kitty crash trigger. The two cases also need different wording. Unreadable means 'kitty didn't answer; will retry'. Fullscreen-last means 'exit fullscreen first'. Evidence: - MEASURED kitty-pane-actions.jsonl:1063: 2026-10-22T03:07:18Z, wid 42, state UNKNOWN, verdict kitten-failed, rc 3, caller cc-pane-runner. The record has no os_window_id or panes field.
- MEASURED pane-close.jsonl:92 at 03:08:31Z: refused, 'kitty remote control is down…'.
- MEASURED `kitty @ ls` now: pane 42's tab holds windows [42,47,91]. That pane 42 was not the last pane at 03:07Z is INFERRED, because the tab membership at that time was not recorded.
- Code: bin/cc-pane-runner:277-279.
- Design: g-message-design.md:361-364 specified '⚠ last pane of a fullscreen window · kept · close it by hand'. The code drops 'kept'.
- **Pane 42's title '✅ closed' contradicts its body, and 'reason unknown' discards two reasons that were known** (messaging): The watchdog picks the title from the death class alone: RECYCLE → '✅ closed $s8' (:1933). It does this before asking the closer. When `cc-pane-close --dry-run` then refuses, the branch at :1991-2003 swaps the 'closing in 20s' row for '⚠ <sid8> ended, reason unknown ▶ cc-husk-sweep'. That branch never recomputes the title, so :2005 paints '✅ closed' over a pane that was kept.
'Reason unknown' is false on two counts:
- The session's end reason was known (prompt_input_exit, a clean /exit).
- The reason the pane was kept was known: kitty remote control was down.
Both go to the log only. The same substitution turned pane 72's 'sha retired by its lead' into 'dd3c29b5 ended, reason unknown'.
The word 'closed' in the title of a pane that is visibly open is self-contradictory. A ✅ glyph also tells the operator to ignore the pane, but the pane needs a close.
The code follows the design here: g-message-design §5.3 E table row 'closer refused | ⚠ e52f1f63 ended, reason unknown · ▶ cc-husk-sweep --pane 1' and 'The OSC-2 title stays'. The defect is in the design. Evidence: - Code: hooks/lead-crash-watchdog.sh:1933, :1991-2003 (the row swap at :1996), :2005.
- MEASURED pane-say.jsonl:643 detail: 'exited on its own (reason: prompt_input_exit) … work … clean'.
- MEASURED pane-say.jsonl:645 detail: 'the closer keeps this pane: kitty remote control is down and a kitty window is in native fullscreen (or unreadable)…'.
- MEASURED pane-say.jsonl records at ts 1792660740 for pane 72: 'sha retired by its lead · closing in 20s', then 'dd3c29b5 ended, reason unknown'.
- MEASURED `kitty @ ls` title for pane 42: '✅ closed 18f95342'.
- Design: g-message-design.md:420-433.
- **Pane 85's verdict was painted once at 09:19Z and is stale on every row; nothing repaints a pane** (both): Pane 85's verdict was painted at death and never updated. Later facts made each row false:
(a) 'KILLED ▶ cc-husk-sweep' was right at 09:12Z. Lead 16 then resumed 570d3917 headless (registered 07:25 CDT), and the session finished: 'Good to close: yes' at 23:15:42Z, lane landed, CI green.
(b) 'pane 16 holds custody of its work · tell it': pane 16 no longer exists (see the next finding).
(c) 'uncommitted work in r23-k': the worktree is now clean, with head 9b8471d4 at 17:09 CDT.
The headless run's own end could not repaint pane 85 for two reasons. The watchdog skips the paint when the registration has no tty (:1974). The paint also targets the registering session's tty, not the pane where the husk sits. No other code calls the repaint entrypoint, and custody discharge does not trigger one. Prior research already flagged 'nothing repaints' as open: husk-panes-2026-09-30.md:82 and husk-triage-2026-10-01.md:58-60.
The true state of pane 85 today is DONE: close it, do not resume. Its screen says KILLED, resume, work at risk, and tell someone. Evidence: - MEASURED transcript ~/.claude-next/projects/-Users-chrisren-Development--worktrees-b13-r23-k/570d3917-….jsonl, last records: 23:15:42Z '✅ Good to close: yes…', 23:15:43Z self-close tool_use.
- MEASURED `git -C ~/Development/.worktrees/b13/r23-k status --porcelain`: empty. Head is 9b8471d4, committed 2026-10-22 17:09:21 -0500.
- MEASURED `cc-pane-close --pane 85 --dry-run`: 'WOULD CLOSE — session 570d3917, its last close said Good to close: yes'.
- MEASURED lead-crash-watchdog.log:66758 'registered session=570d3917… tty=none pane=16' and :66936 'pane verdict SKIPPED — no tty was recorded'.
- MEASURED: `grep -rln -- --pane-verdict bin scripts hooks lib` matches only hooks/lead-crash-watchdog.sh.
- MEASURED: bin/cc-custody and lib/pane-custody.sh contain no repaint or cc-pane-close call.
- **ROOT CAUSE for pane 85 (behaviour): the headless resume's self-close closed the lead's pane 16 mid-turn instead of husk pane 85** (behavior): Lead 666022fd in pane 16 resumed 570d3917 headless. The child inherited KITTY_WINDOW_ID=16 and registered as pane=16 with tty=none. When the child finished, it ran `handoff-fire.sh self-close --terminal`. That resolved 'my pane' as 16 through self_pane_id (scripts/handoff-fire.sh:2387-2392) and closed pane 16 via it2-kitty at 23:16:46Z. The lead's transcript ends mid-turn: an Edit result at 23:16:38Z, then a queue-operation at 23:16:39Z.
The watchdog then classified the lead's death as RECYCLE/clean-exit and did not paint, because the pane was gone. So a live lead was killed silently and recorded as a clean exit, and husk pane 85, which the self-close should have closed, was left open.
I did not trace why the process-tree identity gate admitted pane 16. The headless child does live in pane 16's process tree, so the gate probably saw a true but irrelevant fact (INFERRED).
Fix direction: a session whose registration has tty=none must never self-close by KITTY_WINDOW_ID. Its close target is its original husk pane (here 85, recorded in the earlier registration and the custody row), or nothing. Evidence: - MEASURED /tmp/handoff-selfclose-16-1792710988.log: '→ armed: __selfclose … sid=16 tty=/dev/ttys031', 'KITTY_WINDOW_ID=16', '2026-10-22T23:16:36Z close sid=16 kind=terminal', '→ closed pane 16 (attempt 1/4)'.
- MEASURED close-attrib.jsonl:1242: {ts 2026-10-22T23:16:46Z, site self-close, id_requested 16, verdict closed}.
- MEASURED kitty-pane-actions.jsonl:1177: guard 'safe-not-last' for wid 16, caller it2-kitty, 23:16:46Z.
- MEASURED lead-crash-watchdog.log:66701 'registered session=666022fd… tty=ttys031 pane=16'; :66939 'death class=RECYCLE cause=clean-exit'; :66940 'NOT PAINTED — the pane closed'.
- MEASURED tail of ~/.claude-quaternary/projects/-Users-chrisren-Development-agent-context-sync/666022fd-….jsonl: last user record 23:16:38Z is an Edit tool_result on bring-back-ocr.md.
- **The painted ▶ command for pane 85 (cc-husk-sweep --pane 85) now gives a wrong answer: 'MOVED→pane 16, the session continues there'** (both): cc-husk-sweep's lineage arm 3 ('the same sid registered later in another pane') counts the headless registration (tty=none, pane=16) as a move. Its row therefore tells the operator that the session continues in pane 16, which is closed, while the session itself has ended. The DEATH column shows the headless run's 'suspected-oom-large-context', not the pane's own SIGTERM. The closing advice ('close this pane with cc-pane-close') is right only by coincidence.
Whatever a banner names as its ▶ command has to be correct when the operator reads the banner, not just when it was painted. Headless registrations (tty=none) should be excluded from pane lineage. Evidence: - MEASURED `~/.claude/bin/cc-husk-sweep --pane 85`: '85 570d3917 claude suspected-oom-large-context yes clean MOVED→pane 16 watchdog …', followed by 'RECYCLED/MOVED (panes 85): the session continues in the pane named — never resumed here…'.
- Code: bin/cc-husk-sweep:337-341.
- MEASURED `kitty @ ls`: no window 16 exists.
- **The runner repeats the watchdog's job for a session that ran, using a raw exit code, jargon, and a premature 'for resume'** (messaging): _kept_line's comment (:291) says that when claude ran and then died, 'the shell stays for the resume lead-crash-watchdog paints here'. Yet :300-301 still prints '⚠ fleet launch line exited 143 · shell kept for resume' whenever claude_started=true. That breaks design rule R1 ('one event, one line; every other stage stays silent'). It also shows the operator a raw exit status (143), internal jargon ('fleet launch line'), and a recommendation to resume before anything has judged whether resuming is right. Pane 85's work was later finished elsewhere, so the recommendation turned out wrong.
Fix: when claude_started=true, write only `_detail` and let the final verdict speak. Evidence: - Code: bin/cc-pane-runner:291 (comment) and :300-301. ${1#the } turns 'the fleet launch line' into 'fleet launch line'.
- MEASURED pane-say.jsonl:707 at 09:12:44Z: tool cc-pane-runner, pane 85, verdict 'fleet launch line exited 143', fact 'shell kept for resume'.
- Design R1: g-message-design.md:256.
- **Pane 101: no title, a row truncated to its useless half, no action, and nothing can close it later** (both): A pane that never ran claude gets only the runner's _fallback row. cc_say fits it to 56 cells by cutting the fact, which drops 'shell'. Neither half says what to do. Nothing sets a title: the runner never writes one, and the watchdog never runs because no session registered. The title on screen is the shell's own auto-title.
The close path is also dead. _no_command never writes the pane-exit record, which only _launch writes (:509-510). That leaves cc-pane-close's never-launched arm with no evidence, so it refuses, and cc-husk-sweep returns UNKNOWN with no advice.
Trunk commit da0f61ce6 (11:11 CDT, after this pane timed out at 10:05 CDT) now has _no_command call _close_pane. If the guard refuses, though, the operator gets two rows ('last pane of a fullscreen window · close it by hand', then 'no command arrived…'), and the closer still cannot help afterwards because there is still no exit record.
Scale: 7 such panes (95-101) timed out on 2026-10-22. Evidence: - MEASURED render with lib/cc-say.sh: `cc_say warn 'no command arrived within 300s' 'pane is an ordinary shell'` gives '⚠ no command arrived within 300s · pane is an ordinary…'. The fact room is 56-32-3=21 cells (cc-say.sh:227-228).
- Code: bin/cc-pane-runner:100-105, :545-550, :509-510.
- MEASURED `cc-pane-close --pane 101 --dry-run`: 'REFUSED — no session registration for this pane in the running kitty's lifetime, and no exit record saying its launch never started claude'.
- MEASURED `cc-husk-sweep --pane 101`: 'UNKNOWN unresolved'.
- MEASURED pane-say.jsonl: 'no command arrived within 300s' rows for panes 95, 96, 97, 98, 99, 100 and 101 between ts 1792678241 and 1792681500.
- MEASURED: pane-spawns.jsonl has no 2026-10-22 split record for pane 101, which fits a lost split answer.
- **Rows are fitted to a fixed 56 cells, but these panes were about 38 columns wide when painted, so they wrapped mid-phrase ('tell it' alone)** (messaging): The watchdog hard-codes CC_SAY_WIDTH=56 (:1823), because it writes to a tty by path and cannot see the pane's $COLUMNS. The runner's cc_say falls back to 56 because a non-interactive bash has no COLUMNS (cc-say.sh:62). The 45-cell custody row wrapped after 38 cells. In pane 42 the prompt hard-wrapped at 37 cells.
The panes are 76 columns now (MEASURED), but the wrapped rows stayed broken because those breaks are hard. Fix: read the real width at paint time with `stty size </dev/ttysNNN` or the columns field of `kitty @ ls`. Evidence: - Code: hooks/lead-crash-watchdog.sh:1823 and lib/cc-say.sh:60-66.
- MEASURED get-text: pane 85 shows '⚠ pane 16 holds custody of its work · ' / 'tell it' (38 cells, then the remainder). Pane 42 shows '➜ wt-cc-000146-45877 git:(cc-000146-4' / '5877) ✗'.
- MEASURED `cc_say_cells`: the custody row is 45 cells.
- MEASURED `kitty @ ls`: panes 85, 42 and 101 are each 76 cols today.
- **Painted rows and titles can be silently erased: the watchdog writes behind zsh's line editor, and oh-my-zsh resets the title at every prompt** (both): Pane 42 lacks the '  ▶ cc-husk-sweep --pane 42' row that the watchdog recorded painting. The zsh prompt now sits where that row should be.
INFERRED: a prompt redraw (on resize or SIGWINCH) overwrote the last painted row. The watchdog writes `\n<block>` to the tty while ZLE believes the cursor is still on its prompt line (:2005).
The verdict title is a single OSC-2 write. ~/.zshrc sources oh-my-zsh without DISABLE_AUTO_TITLE, so the next prompt's precmd sets its own title, and one Enter erases the verdict.
Fix: write the title with `kitty @ set-window-title` (an override the shell cannot replace), and repaint the block on demand rather than once. Evidence: - MEASURED pane-say.jsonl:644 records action 'cc-husk-sweep --pane 42'. MEASURED get-text for pane 42 shows '⚠ 18f95342 ended, reason unknown' followed directly by '➜ wt-cc-000146-45877 git:(cc-000146-45877) ✗', with no ▶ row.
- MEASURED ~/.zshrc:37 'source $ZSH/oh-my-zsh.sh'. No DISABLE_AUTO_TITLE line was found.
- MEASURED pane 101's title 'chrisren@MacBookPro:~/Development/.worktrees/b13/r23-ra' matches oh-my-zsh's %n@%m:%~ shape.
- Code: hooks/lead-crash-watchdog.sh:2005.
- **pane-say.jsonl records rows that were never shown, so it cannot be used to audit what the operator saw** (messaging): cc_say logs every time it renders (cc-say.sh:213). The watchdog renders rows into a variable through _pv_add, and some of those rows are replaced before painting (:1991-2003). The log therefore claims '18f95342 ended cleanly · closing in 20s' was shown on pane 42, and it never was. The log should record the final painted block (one 'painted' record per paint) and mark superseded renders. Evidence: - MEASURED pane-say.jsonl:642 at ts 1792638507: kind ok, verdict '18f95342 ended cleanly', fact 'closing in 20s'. :644 has the replacement. The screen shows only the replacement.
- Code: lib/cc-say.sh:213; hooks/lead-crash-watchdog.sh:1838-1841 and :1993-1997.
- **Census of end-of-life messages: none answers all four of (a) running?, (b) work at risk?, (c) resume/close/ignore?, (d) one command** (census): cc-pane-runner:
- _fallback (:102) '⚠ <cause> · pane is an ordinary shell'. Answers (a) only implicitly. No (c), no (d). Truncates at 56 cells.
- _kept_line (:301) '⚠ <verb> exited N · shell kept for resume'. Says resume without judging it. Raw rc. No (d).
- _kept_line (:305) '✗ launch failed (exit N) ▶ cc-husk-sweep --pane N'. Has (d), but the command only lists; it does not close.
- _close_pane (:247, :270) '⚠ pane kept, not closed · recycle check unavailable | fullscreen guard missing'. No (c), no (d).
- _close_pane (:279) '⚠ last pane of a fullscreen window · close it by hand'. False when the guard could not read the window (kitten-failed). No command.
- Guard stderr (:991) leaks raw.
lead-crash-watchdog.sh:
- :1894 '✗ stranded ▶ cc-lr recover'. Good.
- :1900 '✓ moved, runs in pane N · closing'. Good.
- :1913-1928 retired variants. Fine.
- :1937-1938 '✓ ended cleanly · closing in 20s', the promise.
- :1952 '✓ work collected by pane N · do not resume ▶ cc-husk-sweep'. The command does not close, although the verdict is 'close'.
- :1957 '✗ killed (<cause class>) ▶ cc-husk-sweep'. Shows a cause-class token. The ▶ only lists, and (c) is unanswered.
- :1959 '⚠ pane M holds custody of its work · tell it'. Jargon ('custody'), and 'tell it' sits in the FACT slot as a non-command naming a pane that may be dead.
- :1845 '⚠ uncommitted work in <dir>'. Answers (b).
- :1851 '⚠ <name> not resumable · tell its lead <sid8>'. Jargon.
- :1996 '⚠ ended, reason unknown ▶ cc-husk-sweep'. False when a reason is known.
- Titles: :1892-1954 '✗ stranded / ✅ moved / ✅ retired / ⚠ retired mid-task / ✅ closed / ✅ collected / ⛔ KILLED'. Never recomputed after the closer refuses.
bin/cc-close-attrib: only :523 '⏸ claude N waiting on keychain' and :619-622 '⟳ session ended · starting successor'. No end-of-life verdict.
cc-pane-close, cc-husk-sweep and it2-kitty write to their callers, not to panes.
Also on every Claude pane, and from Claude Code itself: 'Resume this session with: claude --resume <sid>'. It names the wrong launcher for non-default stores (pane 42 needs claude2), and no verdict says 'don't resume' even when that is the answer (42, 85). Evidence: - Line numbers are from `grep -n` on the current trunk files (bin/cc-pane-runner, hooks/lead-crash-watchdog.sh, bin/cc-close-attrib, bin/kitty-fullscreen-guard).
- MEASURED `cc-husk-sweep --pane 42`: LAUNCHER claude2, verdict COLLECTED. The screen shows 'claude --resume 18f95342…'.
- Design §5.3 E (g-message-design.md:431-432) said Claude's own resume line would 'move out'. That text is Claude Code's, so only a verdict that countermands it can neutralise it.
- **Every close decision is one-shot: when kitty remote control is briefly down, nothing ever retries** (behavior): The runner's _close_pane runs once, when the command exits. The watchdog's pane_verdict_close (:2044) runs once, after the grace period. Pane 42 failed both at 03:07-03:08Z because kitty remote control was not answering, and nothing came back afterwards. The closer would now close all three panes, or could be made to. Without a periodic retry (for example cc-husk-sweep, or a launchd tick, running `cc-pane-close` on DONE/COLLECTED/never-ran panes), every brief kitty outage leaves permanent husks that need a human. Prior incidents describe the same pattern (husk-panes-2026-09-30, lr-wake 2026-10-18 §2.4). Evidence: - MEASURED pane-close.jsonl:92 at 2026-10-22T03:08:31Z: pane 42 refused, remote control down.
- MEASURED pane-close.jsonl:153/155/158 at 23:27-23:29Z: pane 42 would-close. My own dry-runs also logged rows there, because dry-run calls log_row; I wrote nothing else.
- MEASURED `cc-pane-close --pane 85 --dry-run`: WOULD CLOSE.
- Code: bin/cc-pane-runner:239-287 and hooks/lead-crash-watchdog.sh:2044-2059. Both run once.
- **The code mostly follows g-message-design.md; the design itself lacks a final-verdict owner, repaint, real width and an end-state set** (census): Followed:
- the cc_say shape (glyph, verdict, fact, ▶);
- a 56-cell budget;
- detail going to pane-say.jsonl;
- 'reason unknown' for a closer refusal;
- the KILLED row's ▶ as triage;
- the closer's dry-run running before the paint (R6 at paint time).
Not followed:
- The guard output did not move to the log (B).
- The runner still prints for a session that ran (R1).
- 'kept' was dropped from the fullscreen row (B).
Gaps in the design:
(1) It covers rows, not the pane's final state. Title and body come from separate decisions, and design E keeps the old title over a refused close.
(2) R6 'truthful tense' is checked only at paint time, with no rule for when facts change later.
(3) R4 assumes 57 columns, but painters cannot see the width.
(4) There is no enumerated set of end-states, so each producer invents its own wording (KILLED, closed, collected, reason unknown, ordinary shell).
(5) It never says who owns a pane whose session never registered (pane 101).
The design's own verification (g-message-design.md:809-823) already rates the shared renderer at 65% as a root cause and says it 'is not the cause of the two most consequential false banners'. That held here: the renderer works, and the verdict ownership is what broke. Evidence: - Design: docs/research/lr-wake-incident-2026-10-18/g-message-design.md:252-296 (R1-R8), :346-367 (B), :416-433 (E), :809-823 (V3).
- Code: lib/cc-say.sh:1-53; hooks/lead-crash-watchdog.sh:1795-1801 (header says it follows §5.3 E); bin/cc-pane-runner:120-128, :277, :300-301.
- **PROPOSAL: a single-writer final-verdict contract with six end-states, each one title, at most 2 rows and one command** (both): OWNERSHIP:
- Exactly one function, `cc-pane-verdict --pane N`, may write to a dead pane's tty or title. It is idempotent and recomputes everything from live facts each time.
- The runner, guard, closer, custody, self-close and watchdog only write facts: an extended ~/.claude/run/pane-exit/<wid>.json with {rc, claude_started, sid, kept_reason}, plus their logs. Then they call cc-pane-verdict.
- Repaint triggers: the command returns (runner), death is classified (watchdog), the closer refuses, cc-custody return/abandon, the end of a headless resume of the pane's sid, and a periodic sweep that also retries the close.
- The paint clears the visible screen first (history stays in scrollback). It sets the title with `kitty @ set-window-title`, which oh-my-zsh cannot override, falling back to OSC-2. It fits rows to the tty's real width (`stty size`).
- Structural option: the runner does not `exec $SHELL` after claude. It stays as a tiny verdict screen that owns the tty: Enter runs the ▶ command, `s` opens a shell. This removes the zsh-redraw and auto-title problems at the root.
- Every state also requires: _no_command writes the exit record; self-close from a tty=none session never targets KITTY_WINDOW_ID; headless registrations are excluded from husk lineage.

STATES. Each is title / row 1 / row 2. Title and row 1 share the glyph and the verdict noun. The ▶ command is re-validated (closer --dry-run or sweep) at paint time.

S1 DONE (work saved, nothing to resume). The pane closes itself and is painted only if the close is blocked.
- Title: '✓ done <sid8> · close'
- Row 1: '✓ <sid8> finished · don't resume'
- Row 2: '▶ cc-pane-close --pane N'
- If the block is the fullscreen guard, row 1 becomes '✓ <sid8> finished · last pane of fullscreen'. The closer, when an operator invokes it, should use the guard's toggle mode so the same ▶ still works.
- Applies to pane 42 (COLLECTED) and pane 85 (Good to close: yes).

S2 RESUME (work at risk, nobody else owns it).
- Title: '⛔ resume <sid8>'
- Row 1: '✗ <sid8> stopped mid-task · unsaved work'
- Row 2: '▶ cc-husk-sweep --resume --pane N'

S3 OWNED ELSEWHERE (custody open, moved, teammate, or a headless resume running).
- Title: '⏸ <sid8> → pane M'
- Row 1: '⏸ pane M is finishing <sid8> · don't resume'
- Row 2: none. The pane closes when the owner discharges, which triggers a repaint into S1.
- If the owner is gone, the state is recomputed as S2 or S1.

S4 NOTHING RAN (no command, or a launch that never started claude).
- Title: '✗ nothing ran · close'
- Row 1: '✗ no session started here'
- Row 2: '▶ cc-pane-close --pane N'
- Applies to pane 101.

S5 KEPT ON PURPOSE (CC_PANE_CLOSE_ON_EXIT=0, or the operator typed a command since). No paint: the operator owns the pane.

S6 CAN'T TELL (facts unreadable).
- Title: '◆ check <sid8>'
- Row 1: '◆ can't tell if <sid8> finished'
- Row 2: '▶ cc-husk-sweep --pane N'

BANNED ON SCREEN (they go to the log):
- exit codes and signal names;
- cause classes (external-sigterm, suspected-oom…);
- guard or kitten output;
- 'husk', 'custody', 'fleet launch line', 'collected', 'kitten';
- 'reason unknown' whenever any reason is recorded;
- 'closed' in the title of an open pane;
- a FACT slot used as an instruction ('tell it');
- a resume suggestion before S2 has been established.

EVERY STATE ANSWERS (a)-(d):
- (a): nothing is running in any painted state, by construction.
- (b): the row 1 qualifier ('don't resume' or 'unsaved work').
- (c): the title word.
- (d): row 2. Evidence: This proposal is INFERRED: a design, not something I tested. It is grounded in these defects:
- hooks/lead-crash-watchdog.sh:1933/:2005: title not recomputed.
- :1974: headless sessions get no paint.
- :1823: fixed width.
- bin/cc-pane-runner:277, :301, :509-510, :545-550.
- bin/cc-husk-sweep:337-341.
- scripts/handoff-fire.sh:2387-2392.
- kitty-fullscreen-guard toggle mode: bin/kitty-fullscreen-guard:11-24, 40.
- MEASURED dry-run verdicts: 85 WOULD CLOSE, 42 WOULD CLOSE, 101 REFUSED.

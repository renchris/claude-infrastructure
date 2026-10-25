# Restore plan v2: kitty 1881 (03:45 tree, 13:15 cut) → live kitty 1742

Written 2026-10-25 at 14:45–14:55 CDT by a read-only subagent. Nothing was launched, closed, typed or edited. The only writes are this file and `restore-plan-v2.tsv` beside it. Live reads: `kitty @ --to unix:/tmp/kitty-1742 ls`, `get-text` on all 34 live panes, `ps -axo … -ww`, and `~/.claude/cc-registry/*.json`. Scratch is in `/tmp/restore-v2/`.

## Answer first

- **The recovery is not complete.** 40 of the 49 recorded panes held a live process at the cut: 37 interactive sessions and 3 teammates. **Only 10 of the 37 sessions are running now.** 7 run under their own sid. The other 3 (502bd860, a85a7863, 2b3becea) recycled themselves into successors in the same panes after they were resumed. **16 sessions that were alive at the cut were never put back.** They are all P3 rows, and P3 was outside the 10-row `resume-plan.tsv` from the start.
- **The "empty plain shells" are not failed resumes.** They are placeholders that the layout replay creates on purpose. There are 11 of them: live W2, W4, W11, W12, W14 and W16–W21. `cc-resume-layout.sh` reopens every recorded pane whose id is missing from the roster as a bare shell in its recorded cwd (`bin/cc-resume-layout.sh:112-114`, `:623-625`). The reconstructed roster was missing exactly 11 panes: 11, 12, 322, 339, 298, 330, 331, 332, 333, 337 and 338. Nine of them held no session at the cut. Pane 11 held **5f18dd60**, which was alive and was not resumed. Pane 12 held **509e3aad**, which now runs in a separate OS window (OS11 W22), because the roster had sent it to stale kitty-853 pane 22.
- **4 of the 10 resumed sessions loaded but have not taken a turn since**: 58ec5fef, 568f7c83, 509e3aad and 3f1c1301. Each has 0 assistant records after the reboot and is parked on a `cc-await-ping` watcher. That fits their AT-REST state. But it also means **568f7c83 has not respawned its 3 teammates** (340, 345, 346).
- **Why "Complete" was the wrong verdict.** The run's own last line says `verdict=degraded … placed_failed=1 … fullscreen_failed=1` (`resume-run.log`). The check "tree read back as recorded" compares the split shape only (`kt.diff`, `cc-resume-layout.sh:880-895`), not what is inside each pane. `launched=10` counts processes that were started. Nothing in the run asks whether each pane holds the session it should.
- **Load warning, read at 14:53: loadavg 300 / 246 / 158 on 10 cores**, with 174 runnable processes, mostly the B13 round-28 lane test suites and a Dia renderer. Earlier today `capacity-admit` refused a restore at 2.08 per core; the load is now about 30 per core. **Do not bulk-resume the 16 sessions until the load falls.**

## Counts

| action | panes | sessions |
|---|---|---|
| LIVE-NOW | 10 | 271/502bd860 (as 8ec047e6), 24/a85a7863 (as d1f4a6b2), 216/2b3becea (as 760f97e6), 263/501dda01, 117/f27965bc, 272/3d1dc252, 314/58ec5fef, 12/509e3aad, 297/3f1c1301, 301/568f7c83 |
| RESUME-AT-REST | 16 | 79076bcf, a981134f, b292a869, 43e6eb4b, 5f18dd60, 85c040d1, 87a4411d, 5cc74e8c, 1bede217, 794296f2, 15f652bd, 418d940f, dd833573, 92fc4fbe, aaf6ccd5, 0e2799a9 |
| RESUME-NUDGE | 0 | The only INTERRUPTED rows in sessions.md (502bd860, 501dda01, 2b3becea) are all LIVE-NOW |
| OMIT-FINISHED | 11 | every P3-close row: 2a707a01, c162b95c, 28a7b735, cf477fab, 7396b781, eeb8db4d, 562baac5, 15e47f69, ba56f290, 9ddc8ad3, ad0e870f |
| OMIT-TEAMMATE | 3 | 84d2ca45, 9c8dbf8c, 8cefc9c6 (lead 568f7c83) |
| OMIT-NO-SESSION | 9 | 322/e93017f9 and 339/ccf42eae (exited 03:46–03:47), plus 7 teammate panes whose teammate ended before the cut (298, 330–333, 337, 338) |
| **total** | **49** | 10 + 16 + 11 = 37 interactive sessions alive at the cut, matching sessions.md P1–P3-close |

TSV columns, no header, in recorded tree order: `os_window  pane  cwd  sid  account  action  reason`. The cwd is the session's launch cwd, which is where `claude --resume` must run (§2).

## 1. How to see every window without screenshots

- **One read-only command:** `python3 -I /Users/chrisren/incident-2026-10-25/panes.py --sock unix:/tmp/kitty-1742`. It prints every OS window and, for each pane, CLAUDE or SHELL, working/idle/PROMPT, the footer sid and the cwd. At 14:50 it reported `CLAUDE=23 SHELL=11` and named all 11 empty shells.
- **It has two defects:**
  - **Without `--sock` it breaks.** The default socket is `sorted(glob("/tmp/kitty-*"))[-1]`, which today resolves to `/tmp/kitty-pane-menu-native.compile.log`.
  - **Its header comment is false.** It says "bin/cc-panes is the landed tool", but no `cc-panes` exists in `claude-infrastructure/bin` or `~/.claude/bin`. A standing census, `scripts/pane-census.sh` (husk-fix W3), is being built right now by session 53474c70 in live W50.
- **Which signals are reliable:** the footer sid (`(n) #<win> <sid8> …` in get-text) and `~/.claude/cc-registry/<win>.json` (pid, sid, kitty_pid). Both matched for all 10 live rows.
- **Which signal is not:** kitty's `foreground_processes`. It shows only `expect` and `bash` for the 7 live panes that run under reso-resume-one (W6, W7, W8, W10, W13, W15, W22). Use a ps-descendant walk from each window's `pid` instead (`/tmp/restore-v2/live.py`).

## 2. A vs B reconciliation

| field | result | decision and evidence |
|---|---|---|
| sid per pane | **agree, 49/49** | taken. A gave 8-character prefixes for 8 panes; the full sids come from the transcript filenames |
| alive at cut | **agree, 49/49** (40 yes, 9 no) | taken. I traced ps-prereboot.txt myself: 40 claude processes descend from kitty 1881, 4 from Python 2953 and 1 from iTerm2 |
| session vs teammate | agree | teammate panes carry `--agent-id <name>@session-<lead>` in the 03:45 argv; transcript `agentName` matches |
| pane 347 | same at the cut | A: no sid at 03:45, aaf6ccd5 from 03:46:39. B: aaf6ccd5. Taken as aaf6ccd5 |
| **cwd** | **disagree in 20 panes** (5, 263, 323, 326, 67, 272, 216, 217, 274, 314, 318, 322, 329, 339, 343, 347, 297, 301, 307, 328) | **A taken.** B used kitty's window cwd, which is the cwd of the shell that spawned the pane. A used the process cwd. In each of the 49 transcripts, the first record's `cwd` encodes exactly to its project directory, and that value equals A's cwd in all 20 panes. Example: pane 297's 03:45 foreground pid 3378 has cwd `lkw-scope-floor` while the window cwd is `lead-idle-fix` |
| the brief's "known error" 3f1c1301 → 297 | **not an error** (A and B agree, and I checked the raw files) | Tombstone `3f1c1301….json` reads paneUUID 297, pid 3378, ended 13:15:07. The 03:45 pane 297 foreground includes pid 3378. Pane 298's foreground is `claude.exe --agent-id lkw-ledger@session-3f1c1301` (pid 57063), whose tombstone ends 06:18:06 |
| the roster's real errors (A) | **confirmed** | (1) `hb.roster.json` row 5f18dd60 has paneUUID 29 and kitty_pid 853, but the 03:45 pane 11 foreground is `reso-resume-one next4 … 5f18dd60`. (2) Row 509e3aad has paneUUID 22, but pane 12 runs `reso-resume-one next4 … voiceink 509e3aad`. (3) Row 87a4411d has pid 59711 on claude-next; that pid was tombstoned at 01:39:18, and `cc-registry/20.json` shows pid 87856 on claude-tertiary. Errors (1) and (2) produced live shells W2 and W4 and the separate OS11 window |

Accounts come from each transcript's config dir: `.claude` (= `.claude-next/projects`, a symlink) is next, `-secondary` next2, `-tertiary` next3, `-quaternary` next4. Every account matches sessions.md, apart from the roster's stale 87a4411d entry.

## 3. LIVE-NOW evidence (kitty 1742)

| recorded pane → live | footer sid | registry pid | state after the reboot |
|---|---|---|---|
| 271/502bd860 → OS3 W3 | 8ec047e6 | 60195 | Recycled at 14:42 ("this pane is recycling into a fresh lead"). The successor's first prompt names 502bd860. Idle after a turn |
| 24/a85a7863 → OS4 W5 | d1f4a6b2 (next3) | 18402 | Recycled at 14:25 ("A fresh session starts in the same pane, pane 5, on account next3") |
| 263/501dda01 → OS4 W6 | 501dda01 | 32936 | working: 190 records, spinner at 26 minutes |
| 117/f27965bc → OS5 W7 | f27965bc | 57206 | taking turns; Otto check at 14:52 |
| 272/3d1dc252 → OS5 W8 | 3d1dc252 | 81742 | working: 160 records; "final plan commit is still landing" |
| 216/2b3becea → OS6 W9 | 760f97e6 (next3) | 42535 | Recycled at 14:25; the successor's first prompt says "successor of lead 2b3becea" |
| 314/58ec5fef → OS6 W10 | 58ec5fef | 47862 | **no turn taken**; parked on cc-await-ping 10 |
| 297/3f1c1301 → OS9 W13 | 3f1c1301 | 69751 | **no turn taken**; its last words at 11:58: landed, "clear the goal yourself with /goal clear" |
| 301/568f7c83 → OS10 W15 | 568f7c83 | 18030 | **no turn taken**; its SessionStart said "A parked watcher is holding your LIVE /goal inert" (pid 19794); **teammates not respawned** |
| 12/509e3aad → OS11 W22 | 509e3aad | 37651 | **no turn taken**; parked on cc-await-ping 22 |

None of the 3 originals is still running. In live ps their sids appear only inside the window shells' launch argv and inside the successors' prompts.

## 4. RESUME-AT-REST (16): preconditions

- All 16 were alive at the cut (A and B agree). None of them is running anywhere now: none of the 30 non-live sids appears in any live argv, footer or cc-registry row, and the only claude processes outside kitty 1742 are the 4 headless ones under pid 882.
- 15 of the 16 launch cwds exist.
- **15f652bd** (next, wt-cc-212741-59630) is the exception. Its worktree is GONE, branch `cc-212741-59630` is deleted, and no file under `~/.claude/autonomy/worktree-tombstones/` names it. So reso-resume-one can neither restore nor recreate it. The directory has to exist (for example a detached worktree at that path) before `--resume` can find the transcript.
- **Look before typing** in three of them. b292a869 is mid-turn but 14 h stale. 5cc74e8c is UNKNOWN; its tail at 05:36 may be an unanswered tool call. aaf6ccd5's critic stage probably died.
- **794296f2 may be skippable.** In its own words, "This session has no open work". It is still a P3 row, so the operator decides.
- **Slot for 5f18dd60:** live W2 (OS2, personal) is its pane's placeholder.

## 5. Sessions alive at the cut with no recorded pane

- **None in kitty 1881.** All 40 claude processes in kitty 1881 at 13:11 descend from a window shell in the 03:45 tree.
- **iTerm2 claude, pid 30625** (bash 67513 ← iTermServer 19197). It had run 6:17 at 13:11, so it started at about 13:05, and it had used 0.03 s of CPU. No transcript in any config dir begins between 12:00 and 13:16. There is no sid, so nothing can be resumed.
- **4 headless `claude -p` processes** (15808, 20287, 80545, 82174) under Python pid 2953. This was the classifier pool, now replaced by 4 headless processes under pid 882. They have no pane by construction.

## 6. Operator follow-ups (outside the TSV actions)

1. **568f7c83 (W15) needs a turn**, by a nudge or its 4 h watcher, before its 3 OMIT-TEAMMATE panes come back.
2. **Three sessions are waiting only for `/goal clear`:** 3f1c1301 (W13, LIVE-NOW), cf477fab and 9ddc8ad3 (both OMIT-FINISHED).
3. **The 11 placeholder shells can be closed.** Two exceptions:
   - W2 is the natural slot for 5f18dd60.
   - W4 duplicates pane 12, whose session is now in W22.
4. **Never resume 502bd860, a85a7863 or 2b3becea.** Their successors now hold the lead role, and resuming an original would create two leads.
5. **20 orphaned `zsh -ic 'env' 'CC_ADMIT_DONE=1' … reso-resume-one …` processes** sit under PPID 1: 2 per resumed pane, no children, asleep for more than 30 minutes. They are probably forks from the interactive shell's startup. I have not verified the cause, and they are harmless at this count.

## 7. Adversarial pass: gaps found and closed

- **Could a P3 session already have been resumed elsewhere** (iTerm2, the desktop app, a new pane)? Checked: no live argv, registry row or footer carries any of the 30 non-live sids. The new post-reboot sessions are round-28 lanes, S6/S8/psfix lanes, husk-fix W2/W3 and the layout-fix lane c7887188. Their first prompts name only 502bd860, a85a7863, 501dda01 and 2b3becea, all of which are LIVE-NOW.
- **Are the 3 successors really successors?** Yes. Each original's last post-reboot assistant text announces the recycle, and each successor's first prompt names its predecessor.
- **Is "LIVE" just a footer?** No. For all 10, the ps chain runs window shell → (reso-resume-one/expect) → claude pid = registry pid.
- **Gaps that remain:**
  - I did not map W16–W21 one-to-one onto panes 330–333, 337 and 338. The TSV names the candidate shells for each pane.
  - I did not re-run the P1/P2/P3 classifier. Priorities and states come from sessions.md, as the brief requires.

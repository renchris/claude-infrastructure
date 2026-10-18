# Live remediation findings (lead session, 2026-10-18 13:09–13:30 CDT)

What the lead hit while repairing the live panes. These are MEASURED at the tool call; each one is
also a defect for the fix plan.

## What was done to the live state
- 18 husk panes closed (403 409 410 412 413 414 416 417 418 419 425 426 435 428 332 1 242 401), each
  only after checking that its whole process tree was login shells and its session was live elsewhere
  or had closed with `Good to close: yes`. Load average fell from ~120 to ~51.
- Pane 350 (f06b5e9b): the exit modal was answered "Stay". The index was read off the screen with
  `_pane_bgwork_index "Stay"` (hooks/lib/pane-modal.sh).
- Panes 430 and 23: composer junk cleared with `cc_tui_clear`, verified by read-back.
- Tabs: OS window 18 went from 18 tabs to 1 (433 | 434 | 454). Panes 344, 430 and 442 moved into OS
  window 25 beside 429, as 4 equal columns. Each move was guarded by
  `kitty-fullscreen-guard --scope pane --mode refuse`; layouts were set with
  `kitty-apply-layout.py` and read back with `kitty_tree.ls_tabs`.
- FBAR session 3e929a81 (pane 23) was relaunched on next3 in the same pane (details below).
- No work was lost. The sessions with no live pane (22a76c8a, b102f5af, 8db0e6f1, e739e5b5) had all
  handed off to successors (pane 433, a recycle, the Evolve render, pane 377). 509e3aad lives in
  pane 28; 2e9ed9f2 continues as fad30cb7 in pane 442.

## Defects found while doing it
1. **cc-pane-close cannot close a pane that never started Claude.** All 18 husks were REFUSED. 14
   had "no session registration for this pane", because a capacity-admit refusal means claude never
   ran, so lead-crash-watchdog never registered it. Pane 332 was refused as "a different window"
   (a recycle successor re-registered the tty). Panes 1 and 242 were refused because "nothing says
   session meant to end", even though 0d7c9a19's last text was `Good to close: yes` in its *next3*
   transcript and the closer read the 4 KB *next* copy. The sanctioned closer therefore covers none
   of the overnight husk classes. It needs:
   - a "never-launched" arm: a pane whose launch line exited non-zero before any SessionStart;
   - a reader that follows transcripts across account stores.
2. **cc-husk-sweep mislabels a recycled pane as RESUME.** Pane 332 read `2e9ed9f2 … dirty RESUME`,
   but the session had recycled into fad30cb7 (pane 442). `--resume` would have started a second
   copy (split-brain). The sweep must consult recycle and handoff lineage (HANDOFF-RECYCLE markers,
   pane-successor claims) before it says RESUME.
3. **Stale reconciler cohort keeps acting after the limit resets.** Cohort `next4-7d-1792314000`
   still held 3e929a81 PRE-MOVE/IN-FLIGHT at 13:20, 11 h after it formed, and next4's weekly limit
   had already reset (5% used). The cohort has no exit for "the source account is healthy again",
   so the session stayed stranded. Fix: a member whose source account is under its caps (or whose
   reset passed) goes NOT_NEEDED and the reconciler resumes it in place, no move.
4. **The husk-recovery rail types `/goal clear` and leaves it in the composer.** handoff-fire.sh
   `rcy_bgwork_goal_clear` (~l.11230–11250) pastes `/goal clear` via `it2_paste_submit_verified`. When
   the submit fails, nothing scrubs it. Pane 23 showed `❯ /goal clear` at 13:00 and again after the
   lead had cleared it once (13:18 → 13:20), so a rail re-typed it. Two problems:
   - **Clearing a paused goal on a limit-blocked session destroys operator intent.** The goal was
     "paused · usage limit reached".
   - **The failure path must scrub its own paste.** The code scrubs `/exit` but not `/goal clear`.
5. **A transplant with no relaunch strands the session behind the handed-off guard.** At 03:03 the
   next4→next3 transplant wrote the tombstone `…3e929a81.HANDOFF.json` (handed_off_to
   ~/.claude-tertiary) and renamed the next4 transcript to `.jsonl.handed-off`. The next3 successor
   never started (the tertiary copy stayed byte-identical: 4040651 bytes, mtime 02:56). The old next4
   process stayed in pane 23, and any prompt typed there is refused by the handed-off guard. Poller:
   REQUEST-EXHAUSTED after 3 dispatches at 13:02. Fix: a tombstoned session whose successor shows no
   new bytes after N minutes is a first-class STRANDED state, and the remedy is exit + resume of the
   target in the same pane, not a recycle.
   - **Remedy applied by hand:** `/exit` (no background work, so no modal), then
     `lr-fire-resume.sh next3 <cwd> <sid>`. capacity-admit ADMITted it and the session runs on next3
     in pane 23.
6. **lr-fire-resume prints "this pane is now an ordinary shell" even on a planned exit.** Pane 23
   printed it after the exit above, the same husk state as complaint (c). The banner is right only
   when nothing follows. A planned exit should stage the successor first.
7. **Raw close of a fullscreen OS window's last pane.** Pane 428 was the only pane of OS window 24,
   and the lead closed it with `kitten @ close-window`, not through the guard. kitty did not crash
   (OS window 24 is gone, the others are intact), but this is the 2026-10-15 crash trigger. Any
   husk-closer must ask `kitty-fullscreen-guard --scope os-window` first.
8. **Load.** 76 claude processes and load average 84–121 at 13:12. 16 dead ttys were among the 35
   logged-in users. Husks are cheap, but every refused rescue fire also spun up MCP configs, temp
   prompt files and a login shell.

## Second pass (14:00 CDT, after the synthesis)
- The drain LaunchAgent `com.reso.drain-to-next3` was paused with its own switch,
  `~/.reso/limit-recover/listeners/drain-to-next3.off` (drain-v2.sh:16). Its next4 branch fires
  "past its weekly reset", so after the reset it re-rotated healthy next4 sessions every ~10 min
  (rc=1 each). Undo: remove the file.
- Batch 20261018T180746Z-next-next3-6778 was aborted (`abort` file, lr-move-worker.sh:133).
- Pane 350's exit modal was up again and was answered "Stay" again (index read off the screen).
- `/tmp/lr-rescue`, `/tmp/resume-9f6593c5-retry.sh` and `/tmp/fire-lr-344-successor.txt` were
  moved to `/tmp/lrwake/archived/`.
- Pane 344 (2cc3a7fa) was told by cc-notify that the rescue is over.
- Batches 184542Z (pane 445's own proof run) and 185310Z were left to their owners.

# Why the 2026-10-15 recovery put sessions in different pane positions

Status: fixed on branch `resume-pane-layout` (2026-10-15). Operator report: after the 00:01:27 kitty
crash, sessions came back in the right windows and Desktops at best, but in different split
positions.

## Where position was lost

1. **The runbook never reached the replay.** The resume session loaded `skills/resume-sessions` and
   followed it. Phases 1-2 build 4-column rows (`lr-select.py`, SKILL.md:46-50) and pipe them to
   `cc-resume-layout.sh` with no `--restore` (SKILL.md:114-121), or prefer `--desktops`, a 2x2
   grouped by project (SKILL.md:127-131). Neither path reads the recorded tree. Neither SKILL.md nor
   REFERENCE.md mentioned `cc-restore`, `--restore`, the heartbeat or the tree. SKILL.md:130-131 also
   claimed `boot-resume.sh` uses plain `--desktops`; it passes `--desktops --restore` (boot-resume.sh:1250-1251).
2. **The run itself.** At 05:08:49Z it ran `cc-resume-layout.sh --per-window 4 --stagger 30`, the
   per-monitor default path: it groups by project (`bin/cc-resume-layout.sh` planner after the
   `--restore` branch). The capacity gate then refused at load 41, and the rest went through a
   hand-written driver (`/tmp/kcr/drive2.sh`) that built 2x2 windows by alternating vsplit/hsplit.
   The recorded arrangement was never consulted.
3. **The replay that existed was unreachable from those rows.** Under `--desktops --restore`, trees
   were found only through the rows' column 8 group `k<pid>w<n>` (`bin/cc-resume-layout.sh:367-388`
   before this fix). lr-select rows have 4 columns, so even a `--restore` run on them fell back to one
   row of panes per window (planner `rows no tree placed`).
4. **The right command was filed and not run.** The crash page (`scripts/boot-resume.sh` crash_page)
   filed backlog row `c076f54ba660` at 05:03:35Z carrying `cc-restore --after-crash --kitty-pid
   64211`. That path fills column 8 from `hb.kitty-ls.json` (boot-resume.sh tree_slots :873-890) and
   would have replayed every tab: `--dry-run --tree` on the snapshot rebuilds all 6 recorded windows.
5. **Even the replay could drift without saying so.** A split whose anchor launch timed out (a
   `maybe` row) opened beside the tab's last pane instead (the WHERE fallback, `a="$tlast"`), and no
   step read the built tree back. The planner's own check (`sig`) printed every leaf as `p`, so it
   caught a wrong shape but not a wrong pane in the right shape.

kitty itself was faithful: `launch --location=vsplit|hsplit --next-to X --bias P` makes
pair(one=X, two=new, bias=1-P/100) (kitty 0.48.2 `kitty/layout/splits.py:629-660`), which is
exactly what the planner assumes.

## What changed

- `bin/cc-resume-layout.sh --restore` finds recorded trees by session id as well: the newest
  `hb.kitty-ls.json` under the heartbeat root, or a crash event's copy of it, whose roster holds a
  row's sid. A tree from a kitty that is still running is skipped.
- Every replayed splits tab is read back (`scripts/lib/kitty_tree.py`, which compares shape, axis,
  bias and pane identity). On a difference, `scripts/kitty-apply-layout.py` sets the tree exactly
  through kitty's own `Splits.set_layout_state` on the panes already there, and a second read-back
  gives the verdict (`tree-verify … verdict=ok|fixed|mismatch|unknown`).
- `bin/cc-relayout` moves already-running panes back into their recorded window, tab and position
  (detach-window, then the kitten), without restarting them. It refuses when any involved window
  reads as fullscreen.
- `skills/resume-sessions` Phase 0: after a kitty crash or restart, `cc-restore --after-crash`, or
  `--desktops --restore` for other rows, or `cc-relayout` for sessions already resumed.

## Proof

- Offline: `tests/cc-resume-layout-tree-replay.bats` replays a minimized copy of this crash's
  `hb.kitty-ls.json` into a plan, and checks each window's plan against the snapshot's tree.
- Live: `python3 scripts/checks/restore-tree-live-verify.py` uses a throwaway kitty with its own
  config and a socket under `~/Development/.worktrees`. Measured 2026-10-15 at load ~55, with 2 OS
  windows, 3 tabs, mixed axes, biases 30/60/25, a shell pane and one clean exit left out:
  - restore: `mismatches=0`;
  - after scattering the panes across tabs and windows, `cc-relayout --apply`: `mismatches=0`,
    `restarted=0 of 9`.

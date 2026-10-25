---
status: in-progress
---
# Incident 2026-10-25 — terminal/devfs lockup: lead plan

Scope (frozen): 2026-10-25 terminal-lockup incident — (a) RCA with evidence in ~/incident-2026-10-25/RCA.md, (b) researched long-term fix implemented+landed in claude-infrastructure, (c) all interrupted Claude Code sessions resumed, (d) incident temp settings (iTerm2 cmd, Terminal.app shell, Shortcuts script+setting) undone, (e) crash/halt telemetry so the next lockup leaves high-signal evidence.
Scope (grown, operator 14:30): resumed sessions must come back as live sessions in their recorded panes, fullscreen Desktops in order, even/recorded widths — deterministic in scripts + skill; a pane-level census tool so state is checked, not screenshotted.

Working folder (untracked evidence): `~/incident-2026-10-25/` — CHANGELOG.md (every change + undo), HUMAN-ACTIONS.md, baseline.md, monitor.sh/.log, sessions.md, restore-plan-v2.{md,tsv}, panes.py, rca/*.md, solution/DESIGN.md.

## Phase 0 — Agent Team Orchestration

**Execution locus per wave:**

| Wave | Locus | Why |
|---|---|---|
| W1 RCA research | Workflow `wf_02575376-587` (10 lanes → synth → 3 refuters → final) | read-only fan-out |
| W2 fix design | Workflow `wf_ce44f989-ca5` → solution/DESIGN.md | read-only fan-out |
| W3 pane→session map | Workflow `wf_1ec8d534-06b` → restore-plan-v2 | read-only, two independent methods |
| W4 resume-layout determinism + restore of the remaining 15 + design lane E | **S** pane 23, sid c7887188, branch `resume-layout-determinism` | default |
| W5 design lanes A–D | **S** 4 sessions, branches `lockwatch-lane-{a,b,c,d}` — panes 72 (A, sid 4b4a3a7b), 73 (B, d41b1e89), 74 (C, 7d370dfb), 75 (D) | default |
| W6 lane F: root-cause code fix (cc-pane-runner SIG_IGN, cc-pane-verdict blocking open, pty test teardown) + kitty upstream issue + Apple Feedback draft | **S** pane 76, sid 914995eb, branch `lockwatch-lane-f` | default; added after the final RCA named our own code |
| lead | **L** this pane (kitty pane 1) | synthesis, custody, operator relay |

Lead context budget: recycle at the first idle seam ≥35%; everything needed is on disk (this file + the folder above). Succession: `handoff-fire.sh --recycle` in pane 1 (fired lanes notify pane 1, so the pane must stay).

## Status (2026-10-25 ~15:40 CDT)

- (d) DONE: iTerm2 profile back to login shell, Terminal.app `Shell` key deleted, Shortcuts scripting off (SecuredPreferences.plist), "New Shortcut 1" deleted by the operator; nice/SIGSTOP gone with the reboot. Receipts: CHANGELOG.md.
- (c) PARTIAL: 10 P1/P2 sessions resumed 14:17 (4 nudged: 502bd860, 501dda01, 2b3becea, 3d1dc252); SevenRooms 79076bcf resumed 15:25 at the operator's ask (app re-authenticated); Motion lead 568f7c83 told its teammates' state (motion-prod 8cefc9c6 interrupted 09:22). Remaining 15 RESUME-AT-REST rows → pane 23 after its fixed tool lands. OMIT: 11 finished, 3 teammates, 9 no-session.
- (a) RCA draft (rca/RCA-draft.md): Likely trigger = `kill -KILL 94459 68298` by pid at 03:48:58 in a bats pty test → session leader stuck in proc_exit→vn_revoke→drain, descendant stuck in pty open → /dev node vnode iocount never drops → every ttyname/devname lstat sleeps forever (zsh, login, ps). kitty deafness (RC last OK 03:47; main thread last log 03:52; 297 zombies) is a separate earlier chain. PTY exhaustion refuted (≤65/511). Final RCA.md pending (refuters running).
- (b)+(e): DESIGN.md lanes A–D fired; lane E → pane 23.

## Status update (2026-10-25 ~16:40 CDT)

- (a) FINAL RCA: `docs/research/incident-2026-10-25/RCA.md` (copy of ~/incident-2026-10-25/RCA.md, 16:13). Rank 1 (Likely): kernel pty deadlock from our own code — `bin/cc-pane-runner:292` SIG_IGN inherited by children + `bin/cc-pane-verdict:135` blocking `stty size < "$TTYP"` + an `A1t pty` test driver that exited without killing its child; trigger `kill -KILL 94459 68298` by pid at 03:48:58 → VNOP_REVOKE → vnode_drain with no timeout → every devfs lookup of ttys063 sleeps. Rank 2: 65–100/core overload for ~13 h held in place by self-releasing admission gates. Rank 3: detection blind (producers hung on the same devname path; pages unread). Rank 4: kitty main thread `ttyname_r` in spawn. Rank 5/6: amplifiers; failed recovery.
- Design: `docs/research/incident-2026-10-25/DESIGN.md` (with the 0082/0083 renumbering and the lane-A unpoison-target-set amendment).
- Plan commit landed `e6dfb51f7`.
- Decision filed: `888ad4830b80` (refuse autonomous launches above 50/core sustained? default observe-only; revisit 2026-11-01).

## Open items

1. ~~Collect W1 final RCA → copy RCA.md + DESIGN.md into `docs/research/incident-2026-10-25/`, commit, ship.~~ DONE (this commit).
2. Custody: pane 23 + lanes A–D (`cc-custody`); verify each landing by content (`git ls-tree origin/main -- <paths>`).
3. Pane 23 restores the 15 → verify with `bin/cc-panes` (SHELL=0, every plan row accounted).
4. Operator Phase-0 items from DESIGN.md §8 (H5 Pushover credential, H7 two `--confirm` migration lines, H6 one TCC click) → file with `cc-backlog needs` once lanes land the migrations.
5. Stop the temporary monitor (`pkill -f incident-2026-10-25/monitor.sh`) once lockprobe is live; log in CHANGELOG.md.
6. FINAL-REPORT.md in the incident folder.

## Learnings

- A restore that reports `launched=N` and "tree read back as recorded" proves layout, not content; verify every pane's occupant (census) before claiming done. `pgrep -x kitty` matches nothing on this kitty build — use `/tmp/kitty-<pid>` sockets.
- `capacity-admit` refuses resumes at load > 2.0/core, which never clears at the 15–40/core design point; `CC_ADMIT_LOAD_TERM=off` drops only that term, and the refusal budget (3) admits on the next try.

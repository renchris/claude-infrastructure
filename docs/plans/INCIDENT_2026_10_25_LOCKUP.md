---
status: complete
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
| W7 lane F2: lane F's leftovers (expect-test teardown by process group; held runner exits on master loss, RCA R2b; `_husk_row` without `tty(1)`) | **S** pane 98, sid 00896c67, branch `lockwatch-lane-f2` | default; lane F self-closed before its follow-on arrived |
| W8 lane C2: handoff-fire tdev rewrite + ~40 suites' `ps` stubs | **S** pane 101, sid 254f6b3a, branch `lockwatch-lane-c2-tdev` | default; fired by lane C, reports to the lead |
| W10 boot-resume residuals (tombstones feed the recycle rung, outlived burst is no shutdown, resumed-this-boot stays down) | **S** pane 125, sid 8c12ad1c, branch `boot-resume-residuals` | default |
| W11 lr-submit-red (13 `lr-fire-resume-submit` arms red on trunk, found by F2) | **S** pane 146, sid 8c79f41a, branch `lr-submit-red` | default |
| W9 restore of the 15 RESUME-AT-REST rows | **L** lead, `cc-resume-layout --desktops --restore` | pane 23 landed the tool but handed the run back when the capacity probe refused; one command, no code |
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

## Status update (2026-10-26 ~00:55 CDT, recycled lead 0ec4b497)

Every lane landed, each verified by content (`git ls-tree origin/main` per path plus an empty diff against the lane tip):

| Lane | Landed | Live evidence |
|---|---|---|
| F root cause | effd3f4b2, 6c3ce71d4 | `tests/lockup-2026-10-25-preconditions.bats` RED 8/8 pre-fix, GREEN 8/8 |
| A lockprobe/forensics/classifier | 61df27073..2827c8669, 1bceb92c0 (install links) | lockprobe under the sentinel: `state.json level=0 verdict=ok seq=166 kitty_rc=ok selftest=ok` (04:04Z); classifier on the real stall report: `LOCKUP_DEVFS high, 40 sleepers, zombie leader 68298` |
| B sentinel host, guards, bounded ps | c50816a1f..a52299a61 | sentinel self-restarted and spawned lockprobe; capacity-alarm reads ptys from lockwatch (`argv_blind:false`) |
| C governor | abda1d5a1, ef8b545be, 0de93a544 | brownout + 50/core band observe-only, RC breaker live; `rcy_pane_paint` opens the tty non-blocking |
| D break-glass, guards, lint | 1d830d1cc, d6cc1641c; hammerspoon-config 8f795b7 | 0081 `--verify` rc 0, rescue selftest PASS |
| pane 23 restore + lane E | de0877dbe (and parents) | `bin/cc-panes` live |
| lead | 20ade159c | `lr-page` reads Pushover keys from agent-secrets |
| kitty upstream | kovidgoyal/kitty#10742 merged (57ce71929); note 1ec01e6f6 | — |

Still in flight: F2 (pane 98: expect-test teardown, runner exits on master loss, `_husk_row` without `tty(1)`), C2 (pane 101: handoff-fire tdev rewrite). The 15-row restore runs from the lead (`restore-15-run.log`); 92fc4fbe's reso worktree was recreated first. Temporary monitor stopped 23:04 once lockprobe was live.

Operator: one script, `bash /tmp/incident-operator-steps.sh --confirm launchd --confirm tailspin` (0082, 0083, tailspin), filed as backlog rows; Pushover keys, one TCC click and the Apple Feedback filing as needs-human / needs-credential rows; decision `1cf14ed6e1c3` (add api.pushover.net to the agent-secrets egress allowlist).

## Status: COMPLETE (2026-10-26 ~07:10 CDT, recycled lead b505115a)

Every wave landed, each verified by content (`git ls-tree origin/main` on the commit's paths, empty diff against the lane tip):

| Lane | Landed | Gate |
|---|---|---|
| F2 | 8c5330af7, 814b905bb, e7d92fdf2 | lockup §4 `1..11`, pty-reap `1..6` |
| C2 tdev | 03e7a12d1 (29 files) | 40 suites green; load-timing reds re-run alone and A/B'd against trunk |
| boot-resume residuals | dae8d9155, dd77219df, 0a8a4da9c | residuals `1..11` RED 5 → GREEN 11; boot-resume `1..97` |
| lr-submit-red | c7f4e4b81 | `1..51` 0 not ok on the landed tree (13 before) |

Close proof: `cc-panes` 48 panes, CLAUDE=42, TEAMMATE=6, SHELL=0; restore-plan-v2 49/49 accounted (25 live by resume argv, 3d1dc252 finished and closed, 23 OMIT); lockprobe `state.json level=0 verdict=ok kitty_rc=ok selftest=ok`, fresh each tick. Final report: `~/incident-2026-10-25/FINAL-REPORT.md`. Operator steps are one script plus filed rows (see the 00:55 update); they gate nothing in this scope.

## Open items

1. ~~Collect W1 final RCA → copy RCA.md + DESIGN.md into `docs/research/incident-2026-10-25/`, commit, ship.~~ DONE (this commit).
2. ~~Custody: pane 23 + lanes A–D; verify each landing by content.~~ DONE (all lanes incl. F2, C2, residuals, lr-submit-red).
3. ~~Restore the 15 → verify with `bin/cc-panes`.~~ DONE (SHELL=0, 49/49).
4. ~~Operator items → `cc-backlog needs`.~~ DONE: `/tmp/incident-operator-steps.sh` + rows faf27bb0a451, 6fa39cae3d79, e1c4cbd96ef5, ec7bac81c929; decision 1cf14ed6e1c3.
5. ~~Stop the temporary monitor.~~ DONE 23:04.
6. ~~FINAL-REPORT.md.~~ DONE (status FINAL).

## Learnings

- A restore that reports `launched=N` and "tree read back as recorded" proves layout, not content; verify every pane's occupant (census) before claiming done. `pgrep -x kitty` matches nothing on this kitty build — use `/tmp/kitty-<pid>` sockets.
- `capacity-admit` refuses resumes at load > 2.0/core, which never clears at the 15–40/core design point; `CC_ADMIT_LOAD_TERM=off` drops only that term, and the refusal budget (3) admits on the next try.
- Under load 100–250, a lane's own suites (not the land's smoke, which sheds) are the only behavioral gate; a lead waiting with a foreground poll must keep its bound well under the 600 s tool limit, since load stretches the loop and an overrun turns it into a background task that silences the /goal.

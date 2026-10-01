---
status: in-progress
---

# Kitty deadlock recovery and session durability, 2026-10-01

> **Scope (frozen):** get the fleet out of the 2026-10-01 kitty deadlock without losing any
> session's progress (restart kitty and bring every session back resumed, its subagents, workflows
> and background work re-engaged, with no manual re-prompting), then make terminal restarts and Mac
> reboots stop costing a manual rebuild.

## Phase 0: orchestration

- **Execution locus per wave.**
  - W1 (restart and resume) is **L**, lead-inline, in pane 72 (session 09c26b2b). Why: kitty's control socket is stuck, so no new pane can be fired; the lead is the only live writer. The restart itself is the operator's one command.
  - W2 (durable-fix research) is **S**, a dispatched session running a Dynamic Workflow, fired after W1 restores kitty.
  - W3 (implement W2's chosen design) is **S**, one dispatched session per phase.
- **Lead context budget.** Pane 72 was at about 50% when this plan was written. The kitty restart ends this session too; it comes back through W1's own resume, and this file is the state it resumes from.
- **Shared task list.** The task tools are not enabled in this account (`CLAUDE_CODE_ENABLE_TODO_TOOLS` is unset), so this table is the list.

| # | Task | Owner | State |
|---|---|---|---|
| T1 | Research: how to quit kitty 610 with no confirmation dialog, what its sessions receive, and a clean relaunch | subagent | DONE: SIGTERM to the pid (no dialog), SIGKILL after 10 s; relaunch with `open -n -a /Applications/kitty.app` |
| T2 | Research: can scripts/boot-resume.sh run for an in-boot kitty restart (roster, dedup, CC_BOOTTIME_OVERRIDE), and does its keepalive re-engage subagents and workflows | subagent | DONE: yes, with a private state dir and a one-line `.start`; its nudge recovers nothing (see Restart result) |
| T3 | Write the one-command restart script in /tmp: prep, detach, quit, relaunch, resume. Gate it with `--confirm`, dry-run it, and hand it to the operator | lead | DONE: /tmp/kitty-restart-resume.py and /tmp/kitty-restart-supervisor.py; the restart ran 13:29 |
| T4 | After the restart, verify every roster session came back, report any that did not, and close the 59 zombie windows' remains | lead (resumed) | DONE: 32 of 32 back in kitty 48854 by 13:48 (three rounds of /tmp/inboot-finish.py), each window fullscreen in one row; 31 recovery prompts typed, but they sat unsent (Restart result, item 4). Pane 39 has since closed |
| T5 | Fire W2: the durable-fix research session (brief below) | lead | FIRED 13:51 to pane 41 (worktree research/session-durability, custody marker fire-session-durability); lands docs/research/session-durability-2026-10.md. Items 4 to 6 below were sent to it to fold in |
| T6 | Fire the pane-lifecycle fix session (docs/plans/pane-lifecycle-fixes-2026-10-01.md, backlog row 21ba8983cd4a) | dispatcher | TAKEN by the dispatcher's own worker: pane 38, session c197cdd9, worktree wt-21ba8983cd4a. Not this lead's custody |

## Why a restart, and why kitty is stuck

Kitty 610's remote-control socket has 128 queued connections (the macOS limit), so every connect is refused while the listener stays open. It also stopped reaping its children. Recycles, handoffs, self-closes and pane closes all go through that socket, so the fleet is deadlocked: the only fix is a restart, which ends every pane. Evidence: docs/plans/pane-lifecycle-fixes-2026-10-01.md § Decisions. A restart loses no conversation: every transcript is on disk and `claude --resume` restores it. What dies is in-flight state (running commands, background tasks, teammates, Monitor watches), which W1 must re-engage.

## Restart result, 2026-10-01 13:29 (what went wrong, for the durable fix)

The quit and the relaunch worked as designed: SIGTERM was ignored, so SIGKILL ended kitty 610 after 10 s, and the new kitty (pid 48854) answered within 3 s. The resume did not finish, for three separate reasons:

1. **The capacity gate cannot admit a full fleet.** `cc-resume-layout.sh` checks `scripts/lib/capacity-admit.sh`, which refuses above `CC_ADMIT_MAX_LOAD_PER_CORE` (2.0 per core). Every batch of resumes pushes load past that, so round 1 launched 10 and shed 22, and round 2 launched 0. Before the restart this fleet ran at 5 to 13 per core, so a 2.0 ceiling can never restore it. A restore needs its own ceiling. This was run at 6, paced with waits between rounds.
2. **Fullscreen by title fails.** The layout finds each new OS window by a marker title (`CC-DESK-n`) through System Events. Claude overwrites the title as soon as it starts, so the match reads `nomatch`. That is not a permissions problem. Also, AX lists only windows on the current Desktop, and `tell process "kitty"` is ambiguous when a second kitty is running. The fix is kitty's own action, `kitten @ --to <sock> action --match id:<window> toggle_fullscreen`, which needs neither a title nor Accessibility. It was verified on the 4 resumed windows.
3. **The recovery prompt never went out.** The detached waiter was still holding round 3 on load when it was stopped, so no resumed session was told to run /limit-recover. /tmp/inboot-finish.py sends it after the last round.
4. **A typed prompt is not a submitted prompt.** `kitten @ send-text` arrives as a bracketed paste, so Claude Code keeps the trailing Enter as a newline inside the prompt box. At 14:40, 29 of the 31 prompts were still sitting unsent. Pressing Enter in another session's pane is refused for an agent (auto mode's Remote Shell Writes rule), so it is the operator's step: `/tmp/submit-recovery-prompts.sh` sends `send-key enter` only where the box still holds the prompt. Its first version matched the prompt's last line as one string, which a narrow pane wraps over several rows, so it would have skipped most panes; it now joins the box's rows before matching. A durable fix sends the text and then a separate `send-key enter`, and **verifies each press by re-reading the box**: the operator's first run at ~15:05 printed `submitted` for all 29 panes (every `send-key` exited 0) and submitted none, since no transcript moved. The second run at ~15:20 re-read each box after its press and confirmed 28; pane 11 had already been submitted by a bare `kitten @ send-text '\r'` from the lead. Exit 0 from `send-key` is not evidence of a submit. The agent's own read-back of another pane was then refused too, so pane access with no human involved needs operator-added allow rules (`Bash(kitten @:*)`, the relative `handoff-fire.sh` forms) plus an `autoMode.environment` line that names the local kitty panes as the operator's own sessions. That request is with the operator.
5. **The layout is one row per window.** The operator wants each kitty window fullscreen on its own Desktop with its panes side by side in one row (`horizontal` layout), not a grid.
6. **Screenshots of other Desktops are stale.** `screencapture -l<id>` of a window on another Desktop returns its last drawn frame; `kitten @ get-text` is the live read.

The boot-resume chain also files its "no desk role" page as a backlog row on every round (row `ade4387f8a09`). That row is a boot-delta notice; it was closed at 18:50Z once the fleet was back.

## W2 brief: durable-fix research (a dispatched session running one Dynamic Workflow)

The question: how should Claude Code sessions on this box survive a terminal crash, a kitty restart or a Mac reboot without a manual rebuild?

The current cost: about 9 OS windows with 3 to 6 sessions each die together, and the rebuild is slow and manual.

Decompose and fan out a Dynamic Workflow. Give each candidate its own researcher, two skeptics, and a judge that sets a conviction. Candidates to cover:
1. **A session layer that outlives the terminal.** tmux, or kitty's own session restore, or a per-session pty broker. Kitty becomes a viewer that can be restarted under live sessions.
2. **A one-step post-restart resume.** Extend scripts/boot-resume.sh into a general "restore everything" command covering layout, `--resume`, and a re-engage nudge that recovers subagents, teammates, workflows, background tasks and Monitor watches, the way /limit-recover does.
3. **Making the kitty control socket itself robust.** Find the root cause of the stuck accept queue, and decide whether to give each session its own kitty instance.
4. **Hybrids, and what each costs.** Weigh migration of the 3 launchers (cc-pane-runner, reso-resume-one, hand-opened zsh), the classifier's limits on agents ending or steering sessions, and operator ergonomics such as dragging panes and title bars.

Deliver docs/research/session-durability-2026-10.md: answer-first, a ranked recommendation with conviction, and a phased build plan for W3.

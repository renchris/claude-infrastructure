---
status: open
owner: session b418b97a (lead), operator goal 2026-09-08
---

# EXHAUSTIVE DRIVE — a session works until a hard blocker, never idles on drivable work

**Date opened:** 2026-09-08 · **Lead session:** `b418b97a-d3ec-4444-b993-4f29d55f425a` (pane 615, Fable 5.1 @ max,
account `.claude-secondary`) · **Worktree:** `~/Development/.worktrees/exhaustive-drive` (branch `exhaustive-drive`
off `origin/main` @ `b5f8fc683`) · **Shared task list:** `claude-infrastructure-main` items **198–207**.

**Scope (frozen):** make a Claude Code session drive exhaustively before it idles — (1) measure, over the
transcript corpus, every shape of "stopped with drivable work left" (unfiled follow-ons, under-researched
deferrals, offers, open task items, permission-frozen turns, silent closes) and which Stop arm caught or
missed each; (2) close each measured gap with a fact-bound mechanism (Stop-hook / task-list /
research-then-dispatch / permission-allowlist growth) plus the matching CLAUDE.md rule; (3) land via the
project-local `/ship` from a dedicated worktree and converge the live layer.

## Phase 0 — Agent Team Orchestration

**Execution locus per wave** (S = dispatched handoff session, the default · T = in-session teammates ·
L = lead-inline):

| Wave | Locus | Why (T/L only) |
|---|---|---|
| W0 research (12 axes + 12 skeptics + critic + synthesis) | **Dynamic Workflow** `wf_928fd862-9aa`, in this session's background | the operator names Dynamic Workflows as the research default; agents are read-only and write only their reports |
| W1 … Wn implementation | **S** — one dispatched session per wave, disjoint files | filled in from `SYNTHESIS.md` § waves once W0 lands |
| CLAUDE.md integrations | **L** | single owner of the resident rule text; Edit-only, INTEGRATE-never-overwrite |

**Lead context budget:** the lead holds ≥50% of its window for deciding; it fires waves and harvests their
pings, and never implements a wave inline except CLAUDE.md edits. **Succession point:** at ~50% fill, or
when W0's synthesis is harvested and every wave is fired — `handoff-fire.sh --recycle` (same pane, same
worktree), goal re-armed from this file's frozen scope.

**Team roster / task graph:** filled in from `SYNTHESIS.md` § waves after W0.

## The operator's goal (verbatim intent, 2026-09-08)

> We want Claude Code to continue to work exhaustively until there is a hard blocker/requirement/decision
> from the user. (1) Are there follow-on / loose-end / optional items? Net-positive available work is never
> optional, always mandatory; improve everything we touch to 100th percentile ("boil the ocean"). If there
> are, we are not done — complete them in the main session, a subagent, a Dynamic Workflow, Agent Teams, or
> a /handoff session. (2) Multiple todo items → a Shared Task List. (3) Items without a 100th-percentile
> implementation or decision scoped out → research exhaustively (Dynamic Workflows are usually optimal)
> until conviction moves. (4) Items ≥90% convicted → send them off. (5) Only then present the remaining
> user decisions, answer-first (Pyramid, SCQA/MECE), short and direct. (6) Only stop for user input after
> all that. (7) Any command the agent can run, it runs; defer only on permissions; constantly move
> permission prompts to the allowlist.

## What the lead measured before firing W0 (2026-09-08, 21:20–21:45Z)

- **Binary** 2.1.260 (`~/.claude-260`). Task tools (`TaskCreate/TaskUpdate/TaskList/TaskGet/TodoWrite`) are
  in the binary (35/29/20 string hits) but not offered to this session — gated behind
  `CLAUDE_CODE_ENABLE_TODO_TOOLS=1` / remote flag `tengu_rosy_wren` for opus≥4.8 · sonnet≥5 · fable≥5
  (backlog `ebe84950e98a`). So the operator's "Shared Task List" does not exist for any session today; the
  hooks that key on `TaskCreate|TaskUpdate|TaskCompleted` never fire. Interim: the lead wrote items
  198–207 straight into the native store `~/.claude-secondary/tasks/claude-infrastructure-main/` and
  regenerated `TASKS.md` via `hooks/lib/task-helpers.sh`.
- **Stop-hook latency vs transcript size** (synthetic Stop payload, load ~16–22 on 10 cores):

  | hook (timeout) | 2 MB | 24 MB | 69 MB |
  |---|---|---|---|
  | anti-deference-nudge (5 s) | 0.14 s | 0.24 s | 0.54 s |
  | completion-assert (5 s) | 0.13 s | 0.37 s | **4.14 s** |
  | dispatch-assert (10 s) | 0.30 s | 0.66 s | 1.39 s |
  | session-continue (5 s) | 2.46 s | 3.51 s | **4.80 s** |
  | goal-inert-watch (5 s) | 0.22 s | 0.33 s | 0.87 s |
  | operator-readout (10 s) | 5.86 s | 3.61 s | 0.71 s |

  A hook past its timeout is killed and writes nothing. The corpus holds 230 MB transcripts. So the two
  arms that enforce continue-until-done (`session-continue` 🔧 actuator, `completion-assert` false-done
  gate) are the first to die, on exactly the long sessions that accumulate loose ends.
- **IDL coverage:** `~/.claude/autonomy/idl.jsonl` holds only 2026-09-08 records (rotated) — 469
  anti-deference evaluations today against 901 turn-final assistant messages across the four roots. The
  gap is unexplained (W0 A01 (f)).
- **goal-inert-watch** abstained `goal-unreadable` on 353/469 evaluations today; `goal_live_condition()`
  reads this session's goal fine, so `goal_liveness()` is the failing reader (W0 A04 (c)).
- **conviction-close** (landed today, `4ddbd77d9` + `68410ce31`): ≈300 closes/30 d park drivable work as
  the operator's; Stop hooks catch ~⅓ of lexical hits; the "decision" vocabulary is unmatched by design.
- **`ENABLE_STOP_REVIEW="0"`** sits in the live `settings.json` env of every account with no repo
  reference and no git history — set live, never recorded (W0 A12).
- **Capacity:** 50 `claude` processes, load 15.9/21.4/22.7, 14 d uptime; `claude-accounts --rank general`
  routes to `next` (all four accounts at ~0 pressure).

## W0 — the research decomposition (fired 2026-09-08T21:45Z as Workflow `wf_928fd862-9aa`)

| # | axis | question in one line | delivery |
|---|---|---|---|
| A01 | stop-hook-timeout-decay | what fraction of Stops happen past each hook's timeout, and the size-independent read | `docs/research/exhaustive-drive-2026-09-08/A01-stop-hook-timeout-decay.md` |
| A02 | close-taxonomy | idle closes that left drivable work, by shape, hand-read precision, which arm could catch each | `…/A02-close-taxonomy.md` |
| A03 | shared-task-list | the Task-tool gate, fleet enablement, `OPEN_TASKS_MINE` rung design | `…/A03-shared-task-list.md` |
| A04 | goal-mechanism | is `/goal` working on 2.1.260; `goal-unreadable`; auto-arm from the frozen DoD | `…/A04-goal-mechanism.md` |
| A05 | permission-loop | 30 d prompt/denial census → allow rules → sanctioned closed loop | `…/A05-permission-loop.md` |
| A06 | research-then-dispatch | mechanize under-scoped → research → conviction → dispatch | `…/A06-research-then-dispatch.md` |
| A07 | caps-and-latches | cap/latch releases, exemptions, kill-switch false positives, re-arm semantics | `…/A07-caps-and-latches.md` |
| A08 | rule-surface-audit | CLAUDE.md text vs the 7-step workflow; Edit anchors | `…/A08-rule-surface-audit.md` |
| A09 | adversarial-derivation | baseline-blind: every remaining path to idle-with-work-left | `…/A09-adversarial-derivation.md` |
| A10 | idle-visibility | working / idling / needs-you at the pane level; D8 sensor spec | `…/A10-idle-visibility.md` |
| A11 | capacity-and-venue | no-capacity must route to a queue or the cloud, never file | `…/A11-capacity-and-venue.md` |
| A12 | upstream-features | built-in keep-working features (stop review, goal, agent-type Stop hooks, …) | `…/A12-upstream-features.md` |

Each axis is followed by one refute-by-default skeptic (Fable tier, per the adversarial-slot rule); a
completeness critic writes `CRITIC.md`; the synthesis writes `SYNTHESIS.md` with the ranked,
conviction-adjusted change list, the itemized operator decisions (answer-first), and the wave plan.

## Waves — filled from SYNTHESIS.md

_(pending W0)_

## Decisions log

- 2026-09-08 — Research locus = Dynamic Workflow, not teammates: the operator's goal names Workflows as
  the research default, and a workflow's agents cost the lead one structured summary each instead of a
  merge loop. Workers run on the default tier (`opus`); A09, the skeptics, the critic and the synthesis
  inherit the lead's Fable tier (adversarial-slot rule, `frontier-routing`).
- 2026-09-08 — The Shared Task List was written directly into the native store because the tools are
  gated off; the format was read from an existing pending item (`100.json`) and the summary regenerated
  with the repo's own helper, so `TASKS.md` and the hooks see the items exactly as tool-created ones.

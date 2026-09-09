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

### Lead probes while W0 ran (2026-09-08, 22:05–22:20Z)

- **Headless `-p` sessions DO get the Workflow tool** (measured: `claude -p 'list your tools'` on
  `.claude-secondary` returned Agent, Bash, Edit, ListAgents, Read, ReportFindings, ScheduleWakeup, Skill,
  ToolSearch, **Workflow**, Write). A dispatched research lane can therefore fan out with Dynamic
  Workflows (A06's open question, answered). A model self-report is a weak instrument for *deferred*
  tools — the same probe with `CLAUDE_CODE_ENABLE_TODO_TOOLS=1` did not list `TaskCreate`, while A03's
  schema-level A/B did; trust the schema, not the answer.
- **All five config dirs register the identical 12-hook Stop chain** (`~/.claude`, `-next`, `-secondary`,
  `-tertiary`, `-quaternary`; none missing any of the seven enforcement hooks). Registration parity is
  NOT the 901-vs-469 coverage gap.
- **The coverage gap is per-session, and mostly the 2.1.220 survivors.** Today (14 h window): 66
  sessions produced 738 closes; 17 sessions with 127 closes wrote **zero** anti-deference records, and
  **104 of those 127 closes are on binary 2.1.220** (backlog `76c714390f4d` — 4 live `.claude-220`
  processes, 4–13 days old). Per account: primary 176 closes / 169 records, secondary 136 / 32,
  tertiary 200 / 127, quaternary 222 / 175. W0 A01 (f) owns the remainder.
- **Side-defect found by the probe itself:** a headless `-p` child launched from a pane inherits
  `KITTY_WINDOW_ID`/`ITERM_SESSION_ID`, so its SessionStart/SessionEnd hooks armed and then SIGTERM'd a
  watcher keyed on the PARENT pane (615) and paged the desk with `WAKE-PATH-DOWN`. Probes should run with
  `env -u KITTY_WINDOW_ID -u ITERM_SESSION_ID`; the hooks should refuse pane identity under `-p`.
- **Shared-store concurrency is safe, and the flag works end-to-end headless** (measured 22:12Z): two
  concurrent `claude -p` sessions with `CLAUDE_CODE_ENABLE_TODO_TOOLS=1` and the same
  `CLAUDE_CODE_TASK_LIST_ID` each created three tasks; the list ended with ids 1–6, six distinct
  subjects (A got 2,5,6; B got 1,3,4), nothing lost or overwritten. A03's open question is closed:
  the `<N>.json` allocator is atomic across processes. Backlog `ebe84950e98a`'s premise ("a --print
  probe is blind to this axis") is refuted twice over.
- **W0 at 9/12 — three verdicts that overturn the lead's own hypotheses (22:25Z):** (A01) Stop hooks ARE
  killed at scale — 4,839 timeouts in 30 d, `operator-readout` on 24.2% of 11,871 closes,
  `completion-assert` on 11.6% — but the kill rate is flat-to-declining in transcript size (zero above
  32 MB), so the tail-read fix the lead planned would have moved none of them; the binding cost is
  `scripts/wrap-ledger.sh` (14.3 s uncached in claude-infrastructure, 12.5–12.8 s in reso and
  sevenrooms, 3 s in a leaf worktree), and inside it `hooks/lib/dod-path.sh::dod_lineage_ancestors`
  re-reads `lineage.tsv` once per BFS level (5,352 read iterations over 445 rows, twice per call).
  (A04) `/goal` is not a drive lever: 434 of 641 goals in 30 d (67.7%) were armed and never evaluated
  once, unchanged across the binary bump; the median goal that reached `met` blocked zero stops; there
  is no CLI/env arm, so auto-arming from the DoD is impossible; the 375 `goal-unreadable` abstains are a
  labelling bug (grep-under-pipefail: 47 of 48 such sessions contain no `goal_status` at all).
  `session-continue` is the primary drive lever and CLAUDE.md should say so. (A09, adversarial) the
  largest idle channel is the permission freeze — 84.2 session-hours frozen in a 13.7 h window across
  22 sessions, 15 of which never reached a Stop, so every Stop-keyed arm is blind by construction; a
  detector exists (`cc-permission-beacon`) and no actuator; 0 of 339 allow rules can express a shell
  operator, and 21 of 22 frozen commands were ordinary compound scripts. Second: the mechanical 🔧 arm
  armed on 2 of 672 evaluations because `session-writes.sh` is blind to Bash-mediated edits, and 48% of
  today's repo-writing sessions wrote ONLY through Bash (the auto-mode instruction tells them to).
- **W0 mid-flight (6/12 axes journaled):** the six agree that ~83% of the idle-with-work leak is a
  shape no phrase matcher sees (clean ledger, a stated finding, a named fix, then a stop — A02:
  ~890 idle closes / 30 d leave drivable work, ~80% of that volume in dispatched/teammate sessions whose
  findings never reach a store); the conviction gate landed today is unreachable over 219/220 blocked
  rows because the `needs` door files rows already-blocked with no class (A06); the kill switch is fired
  by MACHINE-authored briefs 26/29 times (A08) and by `and stop <more words>` 50% of the time (A07);
  permission prompts hold ~6.3 sessions blocked at any moment and 43.7% of blocking commands are
  unreachable by any allow rule (A05); the Task-tool flag works through `settings.json` `env` and the
  `tasks/` store is already ONE directory for all five accounts (A03).

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

## Waves — filled from SYNTHESIS.md (2026-09-09T00:05Z; source of every rank: `docs/research/exhaustive-drive-2026-09-08/SYNTHESIS.md`)

**The synthesis verdict.** The wave aimed at the Stop, and the Stop is where ≤24% of sessions end: of
108 dead main-chain sessions today, 26 reached a clean Stop while 61 (56%) retired themselves inside a
`handoff-fire.sh self-close` / `--recycle` Bash call that checks a dirty tree and nothing else — the
terminal close of 56% of sessions is audited by nothing (CRITIC §0). Where drivable work is actually
left, by measured count: permission freezes (1,172 session-hours / 30 d; 99.3% eventually granted),
then the self-close path, then the un-drained findings of dispatched peers (A02), then the phrase
matchers' blind shape. Every rank below is conviction-adjusted by its skeptic.

**Execution locus per wave** (S = dispatched session via `handoff-fire.sh --prompt-file --worktree
--notify-back 625 --account auto --split-right --goal …`; briefs at `/tmp/fire-ed-*.txt`; each wave owns
disjoint files and lands its own commits via the project-local `/ship`):

| Wave | Locus | Ranks | Files | Depends on |
|---|---|---|---|---|
| W0 CLAUDE.md corrections | **S** (was L; moved off the lead to protect its context — no other wave touches CLAUDE.md) | 3 (A08 E1/E2/E3/E4/E5/E6/E8 + A04 R6 + A07 R6) | `CLAUDE.md`, then sync `~/.claude/CLAUDE.md` (real file) | — |
| W1a goal-state | S | 1 (A04 R1+R5) | `hooks/lib/goal-state.sh`, `hooks/goal-inert-watch.sh`, `scripts/idl-abstain-alarm.sh`, tests | — |
| W1b handoff-fire | S | 7 then 5 (A11 R3; CRITIC C-R1 annotate) | `scripts/handoff-fire.sh`, its bats | — |
| W1c Stop-hook instrumentation | S | 2, 10, 4, 8 (A07 R5/R4, A07-sk2 M2, A01-sk) | `hooks/session-continue.sh`, `hooks/completion-assert.sh`, `hooks/anti-deference-nudge.sh`, `scripts/wrap-ledger.sh` (`_bounded`), tests | — |
| W1d dispatch/backlog hygiene | S | 11, 12, 15 (A11-sk2, A12 R6) | `bin/cc-dispatch`, `bin/cc-backlog`, one backlog row | — |
| W1e beat identity | S | 9 (A10-sk1 R1) | `hooks/session-beat.sh`, `scripts/lib/spawn-presence.sh`, tests | — |
| W1f Shared Task List | S | 6 (A03 R1+R3, CRITIC C-R4) | `migrations/0022-*.sh` (c10), `hooks/task-created-attrib.sh`, tests, one `cc-backlog needs --run` | — |
| W1g permission escalation ladder | S | 13 (A05-sk, CRITIC C9) | `scripts/lead-supervisor.sh`, one `cc-backlog needs --run` | — |
| W2 measurements | S (read-only, one number each) + one writer | 14, B1, B2, B4, B5, B6, B17, B21 | `scripts/measure-terminations.py`, `scripts/idl-abstain-alarm.sh`, research dir | W1a, W1c |
| W3 | S, one per item | whichever of B1–B12 crosses 90 on W2's numbers | disjoint per item | W2 |

**Lead budget + succession:** the lead (Fable 5.1 @ max) was at ~57% after the transplant and the
synthesis harvest; it fires W0 + W1a–g, commits this plan, lands the docs branch, then
`handoff-fire.sh --recycle` in this pane; the successor collects the eight pings (custody rows), lands
nothing itself, fires W2 when W1a and W1c have landed, and holds ≥50% of its window.

### Operator decisions — filed as class-C packets (conviction · receipt = SYNTHESIS.md · two options each)

1. **Who answers a permission prompt while you are asleep?** Recommendation (60%): the decider in shadow
   for 7 days, then enforce only for the compound test-fixture class. Below 90 because auto-granting
   removes the human from the loop by design and hook-allow vs deny precedence is unmeasured on 2.1.260.
2. **Pushover credentials** so a prompt reaches a human (80%: provide them). A credential is yours.
3. **Ratify the C10 rescope split** — env/hook migrations land with a revert, permissions and shell
   profiles stay operator-run (70%: ratify). The consent boundary is yours to move.
4. **Research-subagent default count**, 10 vs 12 across four surfaces (75%: align CLAUDE.md to 10).
5. **Who owns an orphaned class-C packet** — 96% of the 29 open ones can never render ⛔ again (65%:
   re-attach by pane uuid, else project).
6. **Dynamic Workflows as the step-3 research default** — 1.7× the quota of a dispatched session,
   quality unmeasured (75%: keep the measured-cheaper venue until B20 measures quality).

### Findings the lead's own notes got wrong (CRITIC, kept for the record)

- "104 of 127 hook-less closes ran on 2.1.220" — not reproduced by the critic (2.1.220 produced 17
  closes / 16 rows today); the 14% closes-vs-evaluations deficit is real and unexplained (B21).
- "ENABLE_STOP_REVIEW is dead" — it is the security-guidance plugin's Stop-review gate (installed,
  not in `enabledPlugins`, so inert today and load-bearing the moment the plugin is enabled).
- "The Stop chain is identical in all five config dirs" — true for the Stop event only; whole hook
  sets measure 100/94/95/94 across accounts.
- The IDL has eight gz archives from 2026-08-29; the "13-hour IDL" premise was wrong and six axes
  inherited it.

## Session events

- 2026-09-08T23:09Z — account `next2` (`.claude-secondary`) hit its 5-hour session cap while W0's
  critic and synthesis agents were running; both died as `api_error[session]` (NULL slots
  `a87f663f54e8fe8f1`, `ad180a81f6eb8c9ef`). All 12 axis reports and 12 skeptics had completed. A
  `/limit-recover` driver (session `b8fcf245`) transplanted this lead to `.claude-tertiary` (`next3`),
  same uuid, Fable 5.1 @ max preserved, source tombstoned (`.jsonl.handed-off`), lock
  `~/.reso/limit-recover/locks/b418b97a-….lock`. Ingest verified 23:35Z; the run was resumed from the
  tertiary store so only the two NULL slots re-execute (iron rules 2–3: null is absence of execution,
  never "found nothing"). The transplant carried the lead's context at ~53% — the succession point is
  right after the synthesis is harvested and the waves are fired (`handoff-fire.sh --recycle`, same
  pane, same worktree).
- The transplanted transcript still carries the old session's `goal_status` arm marker, so every
  transcript-reading goal predicate (`goal-state.sh`) reports the `/goal` as LIVE while the binary's
  in-memory registry may not hold it — a transplant/resume makes "is a goal live?" unanswerable from
  the transcript alone (relevant to W0 A04's finding that `/goal` cannot be the drive lever).

## Decisions log

- 2026-09-08 — Research locus = Dynamic Workflow, not teammates: the operator's goal names Workflows as
  the research default, and a workflow's agents cost the lead one structured summary each instead of a
  merge loop. Workers run on the default tier (`opus`); A09, the skeptics, the critic and the synthesis
  inherit the lead's Fable tier (adversarial-slot rule, `frontier-routing`).
- 2026-09-08 — The Shared Task List was written directly into the native store because the tools are
  gated off; the format was read from an existing pending item (`100.json`) and the summary regenerated
  with the repo's own helper, so `TASKS.md` and the hooks see the items exactly as tool-created ones.

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

### Fires (2026-09-09T00:15–00:25Z, from the lead in pane 625 / `next3`)

| Wave | worktree branch | brief | back-channel |
|---|---|---|---|
| W1b | `ed-w1b-handoff-fire` | `/tmp/fire-ed-w1b.txt` | SKIPPED — pane `625` is not uuid-shaped (transplanted kitty pane, no `ITERM_SESSION_ID`); no custody row |
| W1a | `ed-w1a-goal-state` | `/tmp/fire-ed-w1a.txt` | SKIPPED (same) |
| W1c | `ed-w1c-stop-hooks` | `/tmp/fire-ed-w1c.txt` | SKIPPED (same) |
| W1f | `ed-w1f-shared-task-list` | `/tmp/fire-ed-w1f.txt` | SKIPPED (same) |
| W0 | `ed-w0-claude-md` | `/tmp/fire-ed-w0.txt` | SKIPPED (same) |
| W1d | `ed-w1d-dispatch-hygiene` | `/tmp/fire-ed-w1d.txt` | `--notify-back <sid>` (sid-form test) |
| W1e | `ed-w1e-beat-tz` | `/tmp/fire-ed-w1e.txt` | `--notify-back <sid>` |
| W1g | `ed-w1g-supervisor-restart` | `/tmp/fire-ed-w1g.txt` | `--notify-back <sid>` |

**Outcome of that first attempt: all eight ABORTED at handoff-fire's F3 back-channel gate** — a
transplanted session has no `ITERM_SESSION_ID`, so its pane is not uuid-shaped and is not in
`~/.claude/cc-registry/`; the sid form and the kitty id were both refused. Fix applied 00:55Z: register
the pane the way the launcher does (`ITERM_SESSION_ID=w0t0p0:625 CC_PANE_ID=625` +
`hooks/session-register.sh` with a SessionStart payload), then fire with that env and
`--notify-back 625`. **Second attempt (01:00–01:25Z, load 15→25 on 10 cores):**

| Wave | pane | account | goal | state |
|---|---|---|---|---|
| W1b handoff-fire | 634 | next3 | ARMED+VERIFIED | engaged, working |
| W1a goal-state | 635 | next3 | ARMED+VERIFIED | engaged, working |
| W1d dispatch-hygiene | 636 | next | (unrecorded) | engaged, working |
| W1e beat-tz | 637 | next4 | NOT armed (arming paste abstained — backlog `2ee30f87c370`) | engaged, working |
| W1g supervisor-restart | 638 | next4 | NOT armed (same) | engaged, working |
| W1f shared-task-list | ~640 | next2 | NOT armed (composer unreadable 30 s) | engaged, working |
| W1c stop-hooks | 639 | next | none (stripped by the FIRE FAILED verdict) | **engaged LATE, working** — the fire verdict read "never engaged" because the brief paste submitted after the 305 s window; at 01:43Z its transcript (`24f08168`) was 1.56 MB and growing with 8 dirty files, and by 02:20Z it had 4 commits in its own land queue. The verdict was about the DISPATCHER's window, not the peer (memory `dispatcher-verdict-is-not-the-fired-sessions-state`); no custody row, no goal — harvested from trunk |
| W0 claude-md | 641 | next | none (same) | **engaged LATE, working** (same shape: transcript `1d7c5baa` 1.36 MB at 01:42Z) → **LANDED** `2c882c549` at 01:53Z, "docs(claude-md): nine resident-rule corrections from the exhaustive-drive audit" |

Custody rows exist for the six engaged fires (`--notify-back 625`). Three of six engaged sessions run
WITHOUT a Stop-hook goal — the goal-arm abstention rows are real and load-correlated; their briefs
carry the DoD so they work, and their closes are harvested from trunk like any other. **Harvest rule
for the successor:** the first five have no back-channel, so their
completion is read from trunk, not from mail — `git log origin/main --since=2026-09-09T00:00Z
--grep='goal-state\|handoff-fire\|completion-assert\|0022\|CLAUDE.md'` and `git worktree list | grep
ed-w` (a removed worktree = the session self-closed). A defect in its own right: a transplanted or
resumed session loses its pane identity, so `--notify-back` needs the SID form — record whether the
sid-form fires (W1d/e/g) actually deliver.

### Harvest (successor lead — session `093e40f3`, pane 643, `.claude-secondary`, from 01:40Z)

**Labor split with the origin pane** (625 cannot retire — it is an ORIGIN session — and stays live):
625 harvests the W1a–W1g pings (content-verify + `cc-custody return` + task list); **643 owns** the docs
land, this plan (sole editor), the W2 briefs + fires, W3, `deploy-live` convergence, and the operator
close. Recorded here because a successor reading only the disk would otherwise re-harvest what 625 owns.

| Wave | landed (content-verified `git ls-tree origin/main`) | at |
|---|---|---|
| docs branch (plan · LEAD-NOTES · 12 axes + skeptics · SYNTHESIS + CRITIC · fire record) | `1f0bb2e84` `bbb3547ec` `b94ecb90e` `024ab8be4` `7cbef6a07` — 32 paths | 02:19Z (the predecessor's detached `ship-land` never died: 47 min, most of it queued on the land-lock behind W1e; a second `ship-land` from the same worktree was correctly REFUSED by the in-flight guard) |
| W1a goal-state | `6ebb17d7c` `1de88352c` `40d4317fe` | 01:22Z; custody returned 01:34Z; pane 635 self-closed |
| W1f shared-task-list | `55896d1e7` — migration is **0023**, not the plan's 0022 (0022 was taken between the synthesis and the fire) | 01:39Z |
| W1e beat-tz | `86a21bb57` `eb3f5a2c8` | 01:46Z |
| W0 claude-md | `2c882c549` | 01:53Z |
| W1b handoff-fire · W1c stop-hooks (4 commits) · W1d dispatch-hygiene · W1g supervisor-restart | in their land queues at 02:20Z (load **112** on 10 cores — seven `ship-land`s contending for one lock; each waits 15–45 min) | — |

**W2 fires (from pane 643, `--notify-back 643`; briefs `/tmp/fire-ed-w2-{14,b1,b2,b4,b5,b6,b17,b21}.txt`,
goals `/tmp/fire-ed-w2-goals.tsv`, driver `/tmp/fire-ed-w2.sh [id …]`).** W1 was complete on trunk at
03:01Z (W1b `295c1da82` `889102f7e` · W1c `a910384b7` `61059cbc9` `6d5b9b892` `223369d30` — rank 8 verified
by content at `wrap-ledger.sh:740` · W1g `23d5994da` · W1d `32b64cfef` `026e653e3`), every W1 pane retired,
and 625 had returned every custody row, so the W1c half of the gate was open; slice 1 went at load 24–34.

| W2 item | pane | fired | dispatcher verdict | peer state (transcript size · mtime · worktree) |
|---|---|---|---|---|
| 14 termination census (writer) | 673 (`next`) | 03:19Z, window 391 s + one INC-4 resend | **FIRE FAILED — never engaged** (rc 1: no custody row, no goal, "retire that pane first") | **working** — 1.38 MB at 03:29Z; `scripts/measure-terminations.py` created, `idl-abstain-alarm.sh` modified |
| B17 jq-fatal record | 675 (`next`) | 03:28Z, same window | same verdict | **working** — 1.14 MB at 03:35Z |
| B21 closes-vs-evaluations | — | 03:35Z | **capacity gate rc 9**: 9 sessions mid-turn + 1 > active ceiling 8 (rank 7's gate, as designed; "refusal 1 of 1 — the next fire past the budget ADMITS and pages") | not fired — re-queued at the head of slice 2 |

**Four of four "never engaged" verdicts today were false** (W1c, W0, W2-14, B17: each pane ingested
the brief 2–6 min after its window and worked). The verdict is a statement about the dispatcher's
window, and its consequence — `engage_rc_consequence 1:custody → no row` — leaves a live worker
with no custody debt and no goal while its printed remedy invites a colliding re-fire. The file's
own comment names the asymmetry the row contradicts. **Filed as wave W1h** (brief
`/tmp/fire-ed-w1h.txt`, worktree `ed-w1h-late-engage`, goal row in the same tsv): 1:custody → open
the row (late provenance), the never-engaged message prints the transcript-mtime + worktree-dirt
check instead of "retire first", the goal half and the window untouched, red-proofed in the
existing capacity/custody bats. Slice 2 (`b21 w1h b1 b2 b4 b5 b6`) runs as one self-pacing job:
before each fire it waits on the gate's own instrument (`cc_sp_active` ≤ 7, polled every 60 s, 1 h
cap per item, measured 12 mid-turn at 03:40Z) and stops on the first rc 9 — a second consecutive
refusal is the paged admission, which is not a state to march into. Log `/tmp/fire-ed-w2-slice2.log`.

**Slice 2 (03:49–04:00Z):** B21 → pane 677 (`next4`, goal ARMED+VERIFIED); B1 → pane 678 (`next3`, goal
paste abstained, brief ingested); W1h refused on a path of my own making (the driver reads
`/tmp/fire-ed-w2-<id>.txt`, the brief sat at `/tmp/fire-ed-w1h.txt` — re-staged); B2 refused rc 9 with
the headroom read at 7 one second earlier — the sample-then-act race the actuator memory warns of. A
margin-5 driver then fired nothing in an hour at load 108–119 (the fleet holds 9–16 mid-turn against
the ceiling of 8), so the remainder runs as ONE driver at margin 6 (`w1h b2 b4 b5 b6 w3b17 w3b1`, 3 h
per item, halts on the first rc 9; log `/tmp/fire-ed-w2-slice4.log`).

### W2 returns (six of eight by 08:30Z — each content-verified on origin/main)

| Item | landed | the number | verdict → W3 |
|---|---|---|---|
| B17 jq-fatal record | `1550268e6` | ONE fatal record across live IDL + 8 archives: a 6,679 B `backlog-health` record from `scripts/autonomy-sweep.sh:1400` (72 emissions / 11 d, 100 % > 4,096 B, producer live) spliced at byte 4,096 by a concurrent `waiting-recycle` append — an **interleaved concurrent append** (> 4 KiB ⇒ ≥ 2 `write()`s on the shared O_APPEND fd), none of the brief's five classes; every `jq` census that redirects stderr silently drops **12.33 %** of the store (jq rc 5) | **CROSSES 90 (96)** → `W3-B17`: strip the 5,763 B constant `note:` (record → 845 B), a size assertion in the writer, tolerant readers in every census. Brief `/tmp/fire-ed-w2-w3b17.txt` |
| 14 termination census | `ea2b0c0aa` (`scripts/measure-terminations.py` + the denominator line in `idl-abstain-alarm.sh`) | 123 dead main-chain sessions / 24 h: **self-close 42.3 %** · Stop 29.3 % · killed 13.0 % · drain-recycle 7.3 % · recycle 6.5 % · api-error 0.8 % · frozen 0.8 %; Stop-chain coverage **32.5 %**, not CRITIC §0's 24 % (4 sessions/day end on a Stop-hook BLOCK the end_turn ladder filed as no-Stop); freezing is a **mid-life overlay on 26 %** of sessions, terminal for 0.8 % — a close-side freeze remedy would aim at 3 % of its phenomenon. Instrument defect fixed on the reader side first: a strict `lstart` compare pinned TZ but not LOCALE and read every live session as dead (134/0 vs 115/19) | **CROSSES 90 (94)**; the instrument IS the deliverable. Re-aims W3 at the self-close path (B1) and confirms the permission question is the operator's (decision 1) |
| B21 closes vs evaluations | `d5d924341` + `e73f71f8a` (`scripts/measure-close-vs-idl.py`) | unexplained deficit **0.0 %** for five of six Stop hooks on every binary version over 1,854 closes / 3 d; the two residuals (dispatch-assert 1.8 %, session-continue 41.1 % on 2.1.260) fully attributed | **C5 RESOLVED (96)** — no W3 item; the critic's "14 % deficit" is closed. Custody row returned by the lead (the pane retired without pinging 643) |
| B1 self-close refusal | `739a18337` (`scripts/measure-selfclose-rung.py`) | over 54 self-closes / 28 h (44 resolvable, 10 unresolvable): a refusal on **📦 fires 0/44**, on **REMAINDER≠0 fires 0/44**, on **⛔ fires 3/44 and all three were legitimate** (fired peers whose deliverable was the filed packet); reading the RUNG instead gives 5/44 = 11.4 % and the opposite verdict | **📦 + REMAINDER arms CROSS 90 (93); the ⛔ arm is REFUTED (90)** → `W3-B1`: refuse `self-close --terminal` on the stamp's UNLANDED / REMAINDER **fields**, never on RUNG, annotate-only for ⛔, FILED_MINE-only 🔧, `--recycle`, absent stamp. Brief `/tmp/fire-ed-w2-w3b1.txt` |
| B6 permission prefixes | `bccf99f0f` | **0** prefixes recur across ≥3 **distinct** approval sets. The 22 `settings.local.json` files are not 22 populations: 14 carry an empty `allow` and 3 are byte-identical copies of one 95-entry set, so 302 raw entries collapse to **111 distinct across 6 sets** (63.2 % are copy duplicates). Every candidate that reached "≥3 files" — `claude-accounts` (8), `awk`, `curl`, `rm`, `pnpm design:gate`, covering 20/64 = 31.2 % of exact approvals — reached it via the copy trio. Residual that IS real and is NOT a permissions finding: **27 of 64 exact Bash approvals (42.2 %) are read-only by construction** (`sysctl` ×5, `vm_stat`, `mdls`, the `claude-accounts` read flags ×8, the `git -C … status/log` reads) — the admission gate prompting on a read, already covered by decision packet `1df4081249d2` | **REFUTED (94)** — no W3 item, no settings diff, no operator read. Two classifier defects fixed before the count: dedupe by allow-set fingerprint, and `Bash(git *)` ends in `" *"` not `":*"` so a prefix-form classifier scores 10 wildcards as literals |
| B4 harvest latency | `2a196c1e2` (`scripts/measure-harvest-latency.py`, selftest 7/7) | permanent loss **38.3 %** (74/193) on the most generous reading, **78.8 %** once same-second self-commits are excluded. The median latency of **0.07 d** is itself the finding: 78 of 119 apparent harvests land inside 0.5 d — the closing session's own trailing commit, not a later reader — so only **41/193 = 21.2 %** reach a later reader. Hand-read precision **7/20 = 35 %**, and every matcher error is a false POSITIVE harvest | **CROSSES 90 (95)** → a peer-findings drain producer is worth building. No error direction rescues REFUTED. Does NOT license "recovers 78.8 %": the rate says the CHANNEL is lossy, it does not price the cargo. Adverse exclusion named: 302 of 820 transcripts had no turn-final close at all (died mid-turn) — the population most likely to lose findings |

Both W2 panes that carried a goal or a custody row (677, 678) retired clean; 673 and 675 (no rows, per
the never-engaged strip W1h fixes) also retired. **Standing, not this programme's:** `deploy-live`
refuses to advance (no GREEN stamp in the newest 200 trunk commits; green 419–435 commits behind live
HEAD, 131 h old) — filed already as `f36bc0986c43` / `5511ea906e2e`; the live layer still moved to
`23b631901` (8 behind) through another actuator, inside the 25-commit budget. Also observed by B17:
`cc-blockers` labels the autonomy sweep STALLED on a 530 h log-age proxy while its own IDL rows show
163 runs in 14 h (memory `liveness-proxy-cannot-be-output-age`).

**W1h returned (05:52Z, pane 685, `next4`, goal ARMED+VERIFIED):** `fb0b6866e` — `engage_rc_consequence`
row 1 now opens the custody row with the existing `unproven-rc1` provenance (the goal half and the
window untouched; `fire-engagement.bats` 52/52). The rc→consequence table after the change: 0 open+arm ·
**1 open+skip** · 2 skip+skip · 4 open+arm · 5 open+arm · 7 open+arm (loud). Its ping arrived; its custody
row discharged on its self-close.

**The record land (`1cc4f1b10`, 06:5xZ) conflicted THREE times in a row on
`.claude/rules/agent-operating-lessons.md`** — siblings append to that file's end ~3×/h and
`ship-land`'s in-lock re-fetch lands inside the window every time (the same-hunk append class § Concurrent
Sessions names). Resolved positionally: every sibling line kept, mine moved to the TOP of the list (line 5,
where nobody appends), and the fourth run landed clean. Rule for the next appender: put a rules line at
the top, not the end.

**Capacity state at 07:00Z — MEASURED no-capacity, not a stall of mine.** Every W2 pane had retired, load
was 20 (the 2.0/core rule, met), and the fire gate still refused: `cc_sp_active` = **11** mid-turn against
the active ceiling of 8 (the fleet's chronic 9–16 band, other programmes' waves), and
`claude-accounts --rank general` routes nowhere (`concurrency-unmeasured`, its DATA_UNAVAILABLE exit).
Both halves of the house's `no-capacity` definition hold. The documented per-fire lever
(`CC_FIRE_ACTIVE_CEILING=14`) was **refused by the auto-mode classifier** as an override of a safety gate
— respected, not worked around; the paged-admission path (second consecutive refusal) was not used either,
since six pages for six fires would spend the relief valve as a routine. The driver therefore waits on the
gate's OWN threshold (`cc_sp_active` ≤ 7, polled every 60 s, 6 h per item) for `b2 b4 b5 b6 w3b17 w3b1`
(log `/tmp/fire-ed-w2-slice5.log`) and fires the moment the fleet drains — the remaining three W2
measurements, the permission census, and both W3 implementations.

**Locus change, 07:20–08:30Z (successor lead, pane 643) — the capacity block was half stale.** At
re-measure `claude-accounts --rank general` DID route (`acct=next`, four accounts scored), so only the
machine admission gate still refused; the house's `no-capacity` class needs BOTH halves, so these rows
were no longer FILED-eligible. The gate governs **subagent spawns too** — of three fired at once, B5
admitted and B6/B4 were refused with `13 sessions mid-turn + 1 > active ceiling 8` — and its refusal text
names the remedy this wave then took: *"Run this work SERIALLY on the lead if it cannot wait."* So the
locus split by what each item actually needs: **W3-B17, W3-B1 and B2 stay dispatched** (implementation +
bats red-proof + land, and B2 is a benchmark that wants a quiet box), **B5 runs as an in-session
subagent**, and **B6 and B4 were driven inline on the lead**. The paged-admission path was not used and
`CC_FIRE_ACTIVE_CEILING` was not retried — the classifier's earlier refusal of that lever stands.

**Live layer:** `deploy-live.sh` run detached at 01:51Z from the shared checkout (live HEAD `f2b1cdff4`,
which already carries W1a). It reported the `lead-supervisor` daemon on STALE bytes (W1g's exact
defect) and entered its degradation search — no GREEN stamp in the newest 200 trunk commits, newest
green at depth 407 and already an ancestor of live HEAD; `ship-land` says the post-land verifier is
alive but every recent verdict is non-green (129 h since the last green). Verdict pending in
`/tmp/deploy-live-ed.log`; a refusal is filed as `cc-backlog needs`, never laundered into ✅.

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
- 2026-09-09T01:40Z — succession: lead `b418b97a` (pane 625) fired `fire-ed-recycle` → session
  `093e40f3` in pane 643, same worktree, `.claude-secondary`, Fable 5.1. The origin pane could not
  retire into it (an ORIGIN session may not self-close into a successor), so the two split the labor
  by file (§ Harvest). Two things the successor found that the fire record got wrong: (1) the
  "detached land was SIGTERM'd" reading was false — the `setsid nohup` run was alive at ppid 1 the
  whole time, merely queued; `ps … | grep ship-land` had missed it and `pgrep -f` matched the
  successor's own Bash wrapper (memory `pgrep-f-matches-agent-briefs`) — the in-flight guard's
  refusal was the reliable reading; (2) both "never engaged" waves were working (§ Fires). Lesson
  for the fire path: an engagement verdict measured inside a 305 s window under load 25 is a verdict
  about the window; before any re-fire, read the peer's transcript mtime and its worktree's dirt.

## Decisions log

- 2026-09-08 — Research locus = Dynamic Workflow, not teammates: the operator's goal names Workflows as
  the research default, and a workflow's agents cost the lead one structured summary each instead of a
  merge loop. Workers run on the default tier (`opus`); A09, the skeptics, the critic and the synthesis
  inherit the lead's Fable tier (adversarial-slot rule, `frontier-routing`).
- 2026-09-08 — The Shared Task List was written directly into the native store because the tools are
  gated off; the format was read from an existing pending item (`100.json`) and the summary regenerated
  with the repo's own helper, so `TASKS.md` and the hooks see the items exactly as tool-created ones.

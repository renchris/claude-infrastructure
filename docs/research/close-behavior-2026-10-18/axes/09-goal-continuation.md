# Axis 09: continuation mechanics (/goal, `session-continue.sh set`, handoff-fire, Stop block)

Scope (this slot): how a session can be made to keep going after it finishes research, instead of
stopping. What is the cheapest reliable mechanism that turns "research done, and recommendations
above 90% exist" into the next action (drive inline, fire a session, or file with a named
impossibility) rather than a close? Read-only. The only file written is this one.

## 0. Answer

The only channel that produces a next turn without a human is a Stop hook returning
`decision:"block"` (its `reason` comes back as the next turn). `additionalContext` also forces a
turn; `systemMessage` never reaches the model (CLAUDE.global.md:509-516). Every existing user of
that channel keys on git or ledger facts, or on a sentinel the agent arms itself. **Nothing turns
"this session landed a research doc whose implementation sections nobody has driven" into a fact a
Stop hook can read.** At the incident close the ledger said ✅, and every hook either stayed
silent or was capped.

- `/goal` cannot be armed from inside a session. No CLI exists, and the `ProposeGoal` tool is
  gated off upstream.
- The lever the agent can arm itself (`session-continue.sh set`) is limited by rule to 🔧 and
  must be cleared on ✅. In practice it is used for landing and waiting steps (§2).

**Proposed design (80%): an "enact floor".** Compute the fact at land time and read it at Stop in
O(1). It goes inside hooks that are already registered (`session-continue.sh`, and as a second leg
`completion-assert.sh`), so settings.json does not change. When the floor fires, its block reason
names the three exits. The FIRE exit is a single `handoff-fire.sh --goal` command, the same
command the operator's pushback eventually produced. Arming a goal through a fire is already
reliable: 102 of 104 `--goal` arms were `set` in 14 days.

## 1. /goal: how it is set, what the evaluator sees, and whether a session can arm its own

| Fact | Evidence | Conv. |
|---|---|---|
| `/goal <cond>` registers a session-scoped `type:"prompt"` Stop hook inside the CC binary | hooks/lib/goal-state.sh:59-60; goal-inert-watch.sh:6 | 95% |
| The evaluator is a tool-less LLM judging **transcript evidence only**, fail-closed ("insufficient evidence in transcript"), on a transcript truncated to about 50% of its window with the most recent part kept. Proof must be printed, and printed recently | docs/research/goal-condition-best-practice-2026-08-09.md:124-131, :151 | 90% |
| Evaluation is **deferred** while any background task is non-terminal (workflows, agents, bash). Check-ins come at 30, 60 and 120 min. The goal dies at the context wall but is inherited across `--recycle` and `--resume` | hooks/goal-inert-watch.sh:6-37 | 90% |
| **A session cannot arm its own goal.** `/goal` is composer input, and the model has no keystroke channel into its own composer (docs/research/silver-platter-enforcement-2026-09-12/goldset-raw.json:8, 776). `ProposeGoal`, "the tool that lets the model arm its own goal", sits behind `tengu_propose_goal`, default false, with no local override (docs/research/exhaustive-drive-2026-09-08/A12-upstream-features.md:38-41). Measured today: the key is absent in all 6 `~/.claude*/.claude.json` caches (`jq '.cachedGrowthBookFeatures.tengu_propose_goal // "absent"'`). It is watched by scripts/propose-goal-flag-watch.sh (backlog `2a65b9bf722d`) | as cited | 95% |
| The only working arm paths are `handoff-fire.sh --goal COND` (message 2 is a verified paste into the *fired* pane, scripts/handoff-fire.sh:17-37, `arm_goal` :9720) and `--recycle`, which inherits or re-arms the goal on the successor (`inherit_recycle_goal` :9703). `--recycle --goal` arms a goal on **this pane**, but only by giving up the context | scripts/handoff-fire.sh as cited | 90% |
| Arming is reliable: `goal-arm` rows in the last 14 days were 102 `set`, 1 `unverified` and 1 `abstained` (measured: `jq 'select(.ts>="2026-10-04" and .class=="goal-arm")|.verdict' ~/.claude/logs/handoffs.jsonl`) | measured | 90% |
| The incident session had **no goal**: `goal-inert-watch` logged `no-goal:absent` at 14:27:47Z, the close Stop (`~/.claude/autonomy/idl.jsonl`, sid 5759497b) | measured | 95% |

Verdict: /goal is the right *carrier* for large follow-on (the fired successor gets a Stop blocker
that holds until "every ≥90% wave landed" is proven). It cannot be the *trigger*, because the
session that discovered the work cannot arm it on itself without recycling away its context.

## 2. `session-continue.sh set`: the continuation the agent arms itself

Mechanism: `set` writes a sentinel and resets the counter (hooks/session-continue.sh:141-158). On
an armed Stop the hook emits `{decision:"block",reason:…}` with the step (:1529-1537). With no
sentinel, the floors run in this order: mechanical 🔧 (own dirty files), ship floor (📦/🚀), wake
floor (:1291-1328). At most one floor emits per Stop.

**How often it is used (measured)**

- `~/.claude/logs/session-continue.log`, last 14 days, real uuid sids only: `armed cli-set` 272,
  `fired continue` 344, `armed mechanical-dirty` 109, `fired ship-floor` 252, `fired wake-floor`
  828. That is 104 distinct sids arming `set` out of 713 sids with any record.
- Transcript census (`/tmp/a09_sc_census.py` over 1,568 transcripts in `~/.claude*/projects/*/`
  modified in the last 14 days): **272 Bash `session-continue.sh set` calls in 103 sessions**. This
  agrees with the log.
- **What gets armed** (268 step texts): 219 mention ship/land/commit/push/merge, and 175 are
  await/when/once steps. Only about 4 are research-to-implementation continuations, for example
  `247fdf36 "await research REPORT.md, then spawn 3 implementation teammates"` and
  `9cc0a58e "wait for research workflow w9e3ny3vx, then integrate root causes … and implement"`.
  So the lever works for research-to-implementation when the agent arms it before the research
  lands. Agents rarely do.
- The incident session **never ran `set`**. Its only call was `~/.claude/hooks/session-continue.sh
  clear` at transcript record 531 (13:27:54Z), after the mechanical arm fired on its uncommitted
  doc (`python3 /tmp/a09_tx.py <transcript>`).

**Why the rule steers away from it.** CLAUDE.rules.slim.10-session-close.md:218 says: *"On 🔧, and
only on 🔧, arm the continuation … Clear it … as soon as the state becomes ✅ / 📦 / ⛔ / 📤, on a
read-only turn"* (the same text is at CLAUDE.global.md:1124-1128). Once a research doc lands, the
ledger reads ✅. The rule then literally tells the agent to clear and stop. Undriven implementation
waves never make the ledger 🔧, because:

- The DoD remainder counts only unchecked `- [ ]` boxes in the DoD store
  (scripts/wrap-ledger.sh:871, :926-931).
- dod-persist.sh captures only `Scope (frozen|grown):` lines (hooks/dod-persist.sh:9-15, :106).
- Measured: **0 unchecked items across all 78 files in `~/.claude/autonomy/dod/`**
  (`grep -hcE '^[[:space:]]*[-*][[:space:]]+\[[[:space:]]\]' … | awk sum`). The "frozen-DoD
  remainder 0" clause of ✅ is therefore true by default.

## 3. handoff-fire.sh as the path for large follow-on (six waves)

The cheapest route is already proven, by the remediation itself (transcript 5759497b):

- 20:03:18Z: the operator pushes back. 20:05:13Z: `handoff-fire.sh --prompt-file
  /tmp/fire-startup-hooks-impl.txt --worktree startup-hooks-impl --account auto --split-right
  --follow --notify-back --goal 'Every docs/research/startup-hooks-2026-10-18/README.md section 5
  wave except Wave 6 is landed on origin/main with its bats tests green, and each Wave 6 item is
  filed for the operator — proven by printing …'` (record 723).
- The first attempt was refused by the capacity gate ("12 sessions mid-turn + 1 > active ceiling
  8"). The second, at 20:05:37Z, was admitted ("budget spent … ADMITTED", record 729).
- Cost: about 2 minutes and one prompt file. The goal ends at the agent's reach (Wave 6 is
  filed, not applied), which follows .claude/rules/agent-operating-lessons.md:53 ("a /goal
  conjunct needing an operator-only act … never clears").

What a research session needs in order to fire:

1. A brief file: the README path plus the §N pointer.
2. A pointer-style goal of at most 794 characters with no leading `/` and no `$`
   (handoff-fire.sh:27; goal-condition-best-practice §4.4).
3. `--worktree <slug> --account auto --notify-back`.
4. Capacity. The gate refuses once and then admits; 140 `refused` against 397 `admitted` rows in
   14 days (measured: `jq 'select(.ts>="2026-10-04")|.class' handoffs.jsonl | uniq -c`).

CLAUDE.global.md:128 already makes **S** (a dispatched handoff session) the default execution
locus for every implementation wave. The FILED rule names `handoff-fire.sh` as the drive path for
anything that lacks a named impossibility (CLAUDE.rules.slim.10-session-close.md:185). The verb
exists and the rule points at it. Nothing triggers it.

## 4. Stop-hook block semantics, and what each hook did at the incident

- `decision:"block"` plus `reason` blocks the stop, and the reason comes back as "Stop hook
  feedback:\n<reason>", which becomes the next turn (session-continue.sh:1529, :1418-1421).
  `additionalContext` also forces a turn and counts toward `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` (8).
  `systemMessage` does not reach the model (CLAUDE.global.md:509-516). The harness cap resets once
  a tool has run, so it catches only a text-only wedge (CLAUDE.global.md:1130-1135).
- What the hooks did at the incident close (IDL, sid 5759497b):
  - 14:19:10Z: `session-continue abstained ship-floor-budget` (rung 📦, 2/2).
  - 14:27:47Z: `goal-inert-watch no-goal:absent` and `anti-deference-nudge no-tell`.
  - **14:27:50Z: `completion-assert abstained capped:3>=3, suppressed_arm:"handoff", rung:"✅"`.**
  - session-continue left no row, because rung ✅ is one of its unlogged silent states
    (session-continue.sh:78-82).
  - The assert budget had been spent by three landedness convictions at 13:18:34, 13:19:02 and
    13:19:40Z (transcript records 307, 330, 378).
- Even uncapped, the suppressed arm (D1) would have demanded the wrong thing. It matched "needs
  your hand" (the 70% settings.json item) and demands `cc-backlog needs …`
  (completion-assert.sh:1650). **No arm demands drive or fire for agent-drivable follow-on.** This
  is the same starvation completion-assert.sh:1559-1580 already fixed for the shape, verdict and
  act classes by giving each its own budget.
- The "should we investigate?" turns (06:03 to 06:08Z) were read-only. Every hook abstained:
  `completion-assert no-close-tell`, `anti-deference-nudge no-tell`. **session-continue was
  cancelled by its 5 s timeout at 06:04:21Z and 06:08:19Z** (transcript `hook_cancelled …
  session-continue.sh … timedOut:true`).
- Actuator reliability across the fleet, 14 days (measured by grep over 1,568 transcripts):
  `hook_cancelled` for session-continue.sh 2,418, for completion-assert.sh 1,564, against 12,082
  `stop_hook_summary` records. Estimated: **about 20% of Stops lose session-continue to its
  timeout** (ratio of those counts; whether summaries map one-to-one to Stops is not verified).
  Any new floor must cost O(1) at Stop.

## 5. Root causes on this axis

1. **No producer for the fact "landed research names undriven implementation"** (95%). Every
   continuation trigger reads git, gate, custody or mail, or an agent-armed sentinel. The ledger
   was ✅ (completion-assert IDL 14:27:50Z). The DoD remainder is always 0 (0 of 78 files hold a
   box). Memory `a-plan-is-not-a-queue.md` records the same gap: "nothing scans plan documents for
   unfinished waves".
2. **The agent-armed lever is limited by rule to 🔧 and cleared on ✅** (80%).
   CLAUDE.rules.slim.10-session-close.md:218. In use it is about 98% landing and waiting steps (§2).
3. **A goal cannot be armed from inside a session** (95% on the fact, 60% as a cause). There is no
   CLI, `ProposeGoal` is off, and the only self-arm (`--recycle --goal`) costs the context.
4. **The only matching close-time arm was capped, and it targets operator steps** (90%).
   `capped:3>=3 suppressed_arm:handoff` at 14:27:50Z. D1's demand is `cc-backlog needs`.
5. **The actuator times out on about 20% of Stops (estimated)** (75% as a contributor). It was
   cancelled on both "should we investigate" turns of the incident session.

## 6. Proposed design: the enact floor (80%)

**Producer, at land time.** `scripts/ship-land.sh` runs in the session and knows
`CLAUDE_CODE_SESSION_ID` (ship-land.sh:668, :778). Commits carry no session trailer (measured
"0 of the last 500", ship-land.sh:147-150), so land time is the only point where the fact can be
attributed. After a content-verified land it scans the landed range for added or modified
`docs/research/**/{README,REPORT,SYNTHESIS,DESIGN}.md` and `docs/plans/*.md` whose headings match
`^#{2,3} .*(Implementation waves|Wave [0-9]|Next steps|Fix candidates|Recommendations)`. For each
match it appends `<ts>\t<path>\t<blob sha>\t<n sections>` to
`~/.claude/state/followon/<sid>.tsv`. A new `hooks/lib/followon-marker.sh` shares the reader and
writer.

**Consumer, at Stop.** A fourth floor in `hooks/session-continue.sh`, placed after the ship floor
and before the wake floor. It reuses `SC_LED_CACHE`, so no second ledger run. It blocks when all of
these hold:

- The rung is ✅ or 👤. 📦 and 🚀 stay the ship floor's job.
- The marker file exists (a builtin `-f`, so silent sessions pay nothing).
- The marker is not discharged. Discharge means any of: a `~/.claude/logs/handoffs.jsonl` row with
  `firing_sid == sid` newer than the marker (517 KB, one `grep -F`); a cc-backlog row with
  `session == sid` newer than the marker; or an own commit after the marker touching non-doc
  paths (inline implementation started).
- No kill-switch, no active research program (`research-program.sh is-active`), no teardown, and
  not an assignee.

Budget: once per blob sha, at most 2 per session. `session-continue.sh clear` spends it, as with
the mechanical arm's `.mech` (:1114-1144). That makes a deliberate stated park terminal.

The block reason, one paragraph:

> 📋 ENACT FLOOR: `<path>` (landed `<sha>`) has `<n>` implementation sections, and this session
> has driven none of them (no fire, no filed row). Research that is not enacted is not done. Do
> one of the following now. Drive it here or with teammates. Fire it:
> `~/.claude/scripts/handoff-fire.sh --prompt-file <brief> --worktree <slug> --account auto
> --notify-back --goal '<every ≥90% item in §N landed with bats green, proven by …>'`. Or file each
> item you cannot drive with a named impossibility (`cc-backlog add --why-not-now
> needs-human|not-yet-true|no-capacity|needs-credential …`). If this is a deliberate park, run
> `session-continue.sh clear` and say so in the close.

**Second leg, at the close.** In `hooks/completion-assert.sh`, an undischarged marker counts as
a ledger contradiction against a done-claim ("`<path>` lists `<n>` undriven implementation
sections"). It draws on its **own cap class** (`followon`, COMPLETION_FOLLOWON_MAX=2), so
landedness convictions can no longer starve it. This is the exact fix the file already applies
to shape, verdict and act.

**Guards against an always-firing alarm.**

- It is silent without a marker, and a marker exists only after this session lands a doc with
  drivable headings.
- Population on origin/main, this repo, 14 days (measured: `git log origin/main --since=2026-10-04
  --diff-filter=AM` over docs/research and docs/plans, then a heading grep): 24 of 292 touched
  docs matched, in about 9 study directories or plans. Estimated: at most about 0.6 marker-bearing
  lands per day before discharge, and most of them are discharged by a fire or a row.
- It never blocks ⛔: a session with an open class-C packet has rung ⛔, which fails the ✅/👤
  condition. A fired peer whose lead holds custody is the lead's harvest.

**Residuals.**

- A doc landed by a fired research peer leaves its marker under the peer's sid, while the lead
  owns enactment. Proposed: `cc-custody return` copies the peer's undischarged markers to the
  lead's sid.
- Inline discharge on the first non-doc commit is coarse. The successor's `--goal` or a re-armed
  `set` carries the rest.
- Read-only "should we …?" turns land nothing, so they get no marker. That pattern still depends
  on the rule ("a read-only turn that names drivable work is not E0", rule :100) plus the
  timeout-free fast path.

**Operator-only steps: none.** Both hooks are already registered as Stop hooks with t=5
(measured: `jq '.hooks.Stop[]…' ~/.claude/settings.json`). A *standalone* new Stop hook would need
a settings.json registration, which is operator-only, and this design avoids it on purpose.
Turning on `ProposeGoal` is upstream (a GrowthBook flag), not an operator step.

## 7. Supporting changes (budget-neutral)

- **Rule (60%).** Line 218: change "On 🔧, and only on 🔧" to "Whenever drivable work remains (🔧,
  or a ✅ whose own research names drivable follow-on)". Then change "Clear it … ✅" to "Clear it
  when nothing drivable remains". Freeze-DoD paragraph (:27): add "A research-only scope bounds
  what is researched, not whether its ≥90% findings are enacted." Matching cut: the
  research-program exemption is restated at :87, :100 and :192 on top of its own paragraph at
  :75-81. Collapse those three relays into a single "(§ Follow-On Gate exemption)" pointer each.
  Estimated saving is about 100 words against about 45 added (word count by hand).
- **Skill (65%), not resident.** `skills/research-subagents/SKILL.md` has no enactment step (grep
  for implement, fire and enact finds none at the terminal stage). Add a terminal "Enact" step:
  the synthesis ends with a per-item table (DRIVE / FIRE command / FILE id plus impossibility
  class) and fires `handoff-fire.sh --goal` for multi-wave follow-on before the close.
- **Template (55%).** A helper, `scripts/enact-fire.sh <doc> <§N>`, that writes the prompt file
  and a pointer goal of at most 794 characters. The floor's reason could then carry one exact
  command instead of a template.

## 8. Measurements (all re-runnable, all read-only)

- `awk '$1>="[2026-10-04"' ~/.claude/logs/session-continue.log | grep -E 'sid=[0-9a-f]{8}-' …
  | uniq -c`: cli-set 272, continue 344, ship-floor 252, wake-floor 828, mechanical-dirty 109.
- `/tmp/a09_sc_census.py` (1,568 transcripts, last 14 days): 272 set calls in 103 sessions. Step
  classes: 219 ship/land, 175 await, about 4 research-to-implement.
- `/tmp/a09_followon.py`: 321 line-1 "Good to close: yes" verdicts. Follow-on clause: none 151,
  prose 66, ids 53, no clause 51. Of the prose clauses, about 36 name work, and most of those are
  operator decisions or the lead's. Read by hand: about 1 to 3 are agent-drivable work left
  undriven (5759497b, a46e28ad). So a text-only follow-on check would be imprecise, which is why
  the design keys on the doc fact.
- Grep for `hook_cancelled` in transcripts (14 days): session-continue 2,418, completion-assert
  1,564, `stop_hook_summary` 12,082.
- `~/.claude/logs/handoffs.jsonl` (14 days): goal-arm set 102 / unverified 1 / abstained 1;
  admitted 397, refused 140.
- `~/.claude/autonomy/dod/*.md`: 78 files, 0 unchecked boxes.
- `.cachedGrowthBookFeatures.tengu_propose_goal`: absent in all 6 config caches.

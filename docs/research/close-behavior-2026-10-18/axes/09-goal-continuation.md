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

## Skeptic verdicts

Every check below was re-run read-only on 2026-10-18 from this worktree. "Measured" names the
command; line numbers are this worktree's (the deployed `~/.claude/rules/10-session-close.md` is
byte-identical to `CLAUDE.rules.slim.10-session-close.md`; `diff` printed nothing).

### Root causes

**RC1. No producer for "landed research names undriven implementation" — CONFIRMED, 90%.**
- `scripts/wrap-ledger.sh:871` and `:926-931`: REMAINDER counts only `- [ ]` lines.
- `hooks/dod-persist.sh:101-104`: "readers grep the `Scope (frozen|grown):` lines (… REMAINDER
  counts `- [ ]` boxes only)".
- A grep of `hooks/`, `scripts/*.sh` and `bin/` for `Implementation waves|unfinished wave|followon`
  finds no producer.
- Memory `a-plan-is-not-a-queue.md:3,:13` says what the axis quotes.
- Nuance (measured, `grep -hcE` over `~/.claude/autonomy/dod/*.md`): 78 files, 0 unchecked boxes,
  but **38 checked** boxes. So "always zero" describes today's state, not a rule of the design. The
  remainder can go non-zero; nothing feeds research follow-on into it.

**RC2. The 🔧-only lever rule is the cause — WEAKENED, 55%.**
- The text is real, at `:217` (not `:218`).
- The "those MUST stop" wording is in `CLAUDE.global.md:1124-1128`, and that file is **not
  resident**. It is 117,894 chars (`wc -c`). The resident `~/.claude/CLAUDE.md` is the 28.8K
  slim copy.
- The resident rules already order the drive the agent skipped:
  - `:86`: "an open plan item is open work, so drive it or answer `Good to close: no`"
  - `:99`: a read-only turn naming drivable work is not E0
  - `:184`: "'Out of scope' … are reasons, not impossibilities: drive it (here, or by firing a
    session with handoff-fire.sh)"
  - `:191`: offering is a defect
- `:217` governs the actuator (the sentinel), not whether work continues: "Within a turn, keep
  working rather than stopping on 🔧". The agent broke four resident drive rules. The sentinel
  line contributes; it is not the mechanism.
- The census reproduces (`grep -ciE` on `/tmp/a09_steps.tsv`: 219 ship/land, 175 await).
- "Never armed `set`" holds: no `armed cli-set` IDL row for 5759497b.
- "Its only call was clear" holds for the transcript only. `session-continue.log` has **5**
  cli-clears for this sid (10:33:27, 12:16:17, 12:49:59, 13:17:30, 13:27:55Z). The first four are
  recovery-run clears (session-continue.sh:164, lr-ingest-verify clause D), not the agent's.

**RC3. A session cannot arm a goal on itself — WEAKENED, 60%.**
- The fact that no path is built is confirmed. Measured with
  `jq '.cachedGrowthBookFeatures.tengu_propose_goal'`: absent in 7 files (6 config dirs plus
  `~/.claude.json`). `.claude-next4` holds 0 cached features, so its "absent" tells us nothing.
- "No keystroke channel into its own composer" is contradicted by this very session.
  `handoffs.jsonl` 2026-10-18T20:10:54Z `recycle-bgwork-selfcall`, target_pane 398, prev_sid
  5759497b: "Esc then /exit re-submitted". A detached watcher typed into the session's own composer.
- `arm_goal() { # $1=it2-bin $2=pane $3=condition` (handoff-fire.sh:9726) is pane-generic.
- So a context-preserving self-arm (a detached watcher that runs `arm_goal` on its own pane once
  the session is idle) is unbuilt, not impossible.
- The goldset quote (`goldset-raw.json:8`) is a label rationale about `/deploy` in another repo.
  It is weak evidence.
- As a cause it is weak: `handoff-fire --goal` to a peer was available all along, and it is what
  the remediation used.

**RC4. The close-time check was capped, and D1 targets the wrong object — CONFIRMED, 85%.**
- IDL rows checked: 13:18:34, 13:19:02 and 13:19:40Z are `class:assert count 1/2/3 max 3`.
  14:27:50Z is `capped:3>=3 suppressed_arm:handoff rung:✅ facts:""`.
- The D1 text at `:1650` and the per-class split at `:1561-1615` are confirmed.
- The cap was not causal for the waves. Uncapped, D1 would have demanded
  `cc-backlog needs --class needs-human` for the 70% settings.json item. The close itself says:
  "The one change that needs your hand is raising the dispatcher's timeout …".

**RC5. Actuator timeouts (~20% of Stops) — WEAKENED as a cause, 35%; CONFIRMED as a design
constraint.**
- Re-measured with a structured grep of
  `"attachment":{"type":"hook_cancelled","hookName":"Stop…"command":"…(session-continue|completion-assert).sh"`
  across 1,570 transcripts (14 days): **2,434** for session-continue and **1,575** for
  completion-assert, against **12,120** `stop_hook_summary`. Ratio 20%.
- The incident cancels at 06:04:21Z and 06:08:19Z are confirmed.
- Those were read-only turns. There was no sentinel, no 📦/🚀 work of the session's own and no own
  dirty file, so no session-continue arm could fire. Uncancelled, it would have stayed silent. The
  timeout is a constraint any new floor must respect; it did not cause this incident.

### Fix candidates

**F1. Enact floor (ship-land producer, session-continue consumer) — WEAKENED, 55%.**

The right shape: it would have caught the incident.
- The README has `## 5. Implementation waves` and 8 headings that match the regex.
- The land.log row at 14:27:18Z carries sid 5759497b. The rung was ✅ at the 14:27:47Z Stop.
- The cwd is not inside a research program (`research-program.sh is-active` rc=1).
- ⛔ silence is real (wrap-ledger.sh:24, :2500-2506).

As specified, it has six defects:

1. **Discharge-by-fire cannot be built as written.**
   - `handoffs.jsonl` `firing_sid` is a PANE: "FIRING_SID is a PANE" (handoff-fire.sh:17315-17318).
   - Measured: 262 digit values and 0 uuids. `admitted` rows are null in 265 of 265. There are
     **0** rows with `firing_sid` 5759497b, although that session fired at 20:05-20:09Z; its rows
     carry `"398"`.
   - The file also rotates (handoff-fire.sh:8176; the earliest row now is 2026-10-16T16:02:31Z).
   - Key discharge on `scripts/lib/fired-peers.sh` `firedBySid` (or cc-custody) instead.
2. **Pre-spent park budget.**
   - `clear` writes the `.mech` budget unconditionally for the session (session-continue.sh:263).
   - A per-session budget "as with `.mech`" would have been spent by the five clears that came
     before the marker: four recovery clears, plus the agent's 13:27:55Z clear of the A4-tokens
     mechanical arm. The README landed only at 14:27:18Z.
   - **A literal mirror of `.mech` would have missed its own incident.** Only a clear issued after
     the newest marker may park it.
3. **One filed row discharges every wave.** "Any cc-backlog row with session==sid" lets the
   incident's one operator item (Wave 6, settings.json), which is exactly what D1 asks the agent to
   file, silence all six drivable waves. Discharge must be per section, or require a fire or a
   drive.
4. **It fires on the sessions that are enacting.**
   - Measured: `git log origin/main --since=2026-10-04 --diff-filter=AM` gives 292 docs. 23 match
     the headings (not 24), and **only 4** pass the producer's filename filter.
   - **30 commits** touched those 4 docs in 14 days (about 2.1 a day, not 0.6). At least 13 are
     progress records by implementers, for example b48bed1a8 "Wave 4c landed + converged" and
     5d025053b "O3 applied". 29 of the 30 have 0 non-doc paths.
   - Blob-sha markers combined with "a non-doc commit *after* the marker" therefore block the wave
     leads who are doing the work.
   - Amend: discharge if this sid landed any non-doc path in the session. The incident's
     55f4d910b and 1e7461db7 are docs-only, so the incident is still caught.
5. **Narrow coverage.** The regex misses `## 5. Fixes, ranked`, `## Ranked fixes`,
   `## 7. Implementation brief`, `## Build now`, `## Waves` (three plans),
   `### Tier 1: agent-landable` and lowercase `Ranked recommendations`. Only 4 of about 57 candidate
   README/REPORT/DESIGN/plan docs match.
6. **No fired-peer exemption.** The guards name assignees but not fired peers. A fired research
   peer would be told to fire the implementation itself, duplicating its lead. D6 already exempts
   fired peers through `hooks/lib/origin-identity.sh`.

Tests: `tests/session-continue-forks.bats:96`, `:149` require idle-Stop output identical to
origin/main's and at most 35 external calls on a memo hit. That is compatible only if the no-marker
path is a builtin `-f` with no fork. They do not contradict the fix.

**F2. completion-assert `followon` cap class — WEAKENED, 50%.**
- It is implementable beside `act` at `:1608-1615`. It must be its own flag; folding it into
  `contra=1` would draw from `assert` and starve again.
- The double-block guard (`:1169-1190`) zeroes `contra` whenever session-continue's `.blocked`
  marker exists. So it is redundant whenever F1 fires. Its unique value is Stops where
  session-continue was cancelled (20%) or its budget is spent.
- After a deliberate `clear` park, the marker is still "undischarged" under the stated rules, so
  this leg blocks the park's close (up to 2 times). That violates the stated-park constraint
  unless `clear` after the marker also discharges it.

**F3. Budget-neutral rule edit — WEAKENED, 35%.**
- The matching cut is **contradicted by the test suite**:
  - `tests/research-program-exemption-rules.bats:35-37` greps `relaying the certificate` on the
    close-question and E0 lines and `is not an offer` on the Offering line.
  - It is deliberate: ":21 … a pointer must live WITH its rule".
- Cut size measured with `wc -w`: 25 + 31 + 33 = 89 words, so the saving is about 77, not about 100.
- Editing `CLAUDE.global.md` costs nothing and changes nothing, because the file is not resident.
- The resident rules already demand the drive (RC2), so one more sentence is a weak lever.
- The cited lines are off by one: `:217`, `:26`, `:86`, `:99` and `:191`.

**F4. Enact step in research-subagents plus `enact-fire.sh` — WEAKENED, 30%.**
- The insertion point misses the incident path.
- The operator typed `ultracode research …` (06:04:35Z). The session loaded `workflow-authoring`
  (a command-message at 06:04:36Z) and made 2 `Workflow` calls. Its only Skill call was `handoff`
  (`jq` tool-use census of the transcript).
- `workflow-authoring` is not in this repo (`~/.claude/skills/workflow-authoring` is absent).
- The helper is harmless and optional.

### Measurements

- **session-continue.log (CONFIRMED).** Re-run: cli-set 272, continue 345, ship-floor 257,
  wake-floor 838, mechanical-dirty 110; 104 of 719 sids. The drift is log growth.
- **Transcript census (CONFIRMED).** 272 calls / 103 sessions and 219/175 reproduce. Research to
  implementation is about 5-7 by my grep, against the axis's ~4.
- **Incident transcript (WEAKENED).** "One clear" holds for the transcript only; the log has 5.
- **IDL rows (CONFIRMED).**
- **hook_cancelled (CONFIRMED).** 2,434 / 1,575 / 12,120.
- **handoffs.jsonl "14 days" (WEAKENED).** The file rotates and now holds about 2 days. Today's
  counts are goal-arm set 85 / unverified 1 / abstained 1, admitted 265, refused 101. The ratio
  holds; the window label does not.
- **DoD store (CONFIRMED).** 0 unchecked, with 38 checked.
- **tengu flag (CONFIRMED).** One cache is empty.
- **Follow-on census (CONFIRMED).** From `/tmp/a09_followon.out`.
- **Doc population (WEAKENED).** The unit should be lands, not docs: 23 match, 4 pass the
  producer filter, and 30 commits touched those 4.

### What the axis missed

1. The `firing_sid` field is a pane id.
2. Recovery-run and unrelated clears spend floor budgets.
3. D1's own demand discharges the marker.
4. Implementers' plan-progress commits fire the floor.
5. There is no fired-peer exemption.
6. A self-goal through a detached `arm_goal` on the session's own pane is feasible.
7. The incident's research path was `workflow-authoring` → Workflow, which no repo skill reaches.
8. Rollout lag: "sessions run their OWN worktree copy of ship-land.sh ⇒ a fix reaches only newer
   ones" (`.claude/rules/agent-operating-lessons-situational.md:105`).
9. The floor's FILE exit uses `--why-not-now needs-human` with no `--conviction N --receipt R`,
   which rule `:184` requires. Followed literally, that row is refused or lands as UNCONVICTED 🔧.
10. The second "should we" reply said "Investigating the load now." and stopped with no tool call:
    a narrated action that no Stop arm checks.

# Control-arm rubric — fixed before the run

Decision packet `2c7259995a6b` asks whether a session still under 90% sure after research should
escalate to the frontier model (Fable 5.1) automatically or only by deliberate choice. The operator
approved this rule on 2026-10-20: send the original trial's brief to a fresh Opus 5.5 session and
count how many of the trial's nine findings it also reaches. **6 or more of 9 ⇒ keep the choice
deliberate for good. 5 or fewer ⇒ open a class-C decision to switch to automatic after migration
0029.**

This file is committed before the control run starts. It is not edited after the run's output exists.

## The original trial (arm A, already run)

| field | value | receipt |
|---|---|---|
| session | `8569adf1-7cd0-4f42-bdd0-bc30fff3258f` (account dir `~/.claude-quaternary`) | transcript `…/-Users-chrisren-Development--worktrees-nonlimit-resume-fable/8569adf1….jsonl` |
| model / effort | `claude-fable-5-1` / `xhigh` (77 of 77 assistant records) | `jq` over the transcript |
| permission mode | `auto` | `permission-mode` records |
| base commit | `8788dea27` (branch `handoff/nonlimit-resume-fable`; landed as `987a02e62`) | the brief: "expect 8788dea27" |
| window | first prompt 2026-09-09T17:43:30Z → commit `67fdf0670` 2026-09-09T18:07:44Z | git log |
| tools | 45 Bash, 1 ToolSearch; no subagents | `jq` over the transcript |
| brief | 7,630-byte `[locate] Step 0 …` prompt, saved verbatim as `original-brief.txt` beside this file | the transcript's first `queue-operation enqueue` |
| findings | `docs/plans/NONLIMIT_RESUME_LADDER.md` § W1.4, items 1–9 | landed in `67fdf0670` |

## The control (arm B, to be run)

Same brief and same base commit, run in a fresh headless `claude -p` session on `claude-opus-5-5` at
`xhigh`, on the default tier, in a new worktree at `8788dea27`. These are the only differences, and
each is needed for the run to be valid:

1. **Headless and read-only.** The deliverable section is printed as the final answer instead of
   being appended to the plan and committed. The back-channel and self-retire blocks are dropped,
   since a `claude -p` process has no pane. Edit and Write are disallowed.
2. **An evidence fence dated to the original run.** Today is 2026-10-21, and the disk now holds the
   trial's own findings: the landed plan, the post-W2 `lr-audit.py` behind the `~/.claude` symlinks,
   and later transcripts and memory files. The control is told to treat the time as 2026-09-09T17:43Z,
   to read repo code only from its own worktree, and to use only transcript records timestamped
   before 2026-09-09T18:07Z. A post-run audit of its transcript lists every path it read and flags
   any read outside the fence (§ Contamination below).
3. **Model label.** The brief calls the pass "Fable 5.1" and "the frontier tier". That wording is
   kept verbatim, so the brief stays the same; the model that runs is the init line's `model`, which
   is recorded.

## Scoring rules

- Each item is scored **REACHED** or **NOT REACHED** against the criterion below. `k` is the number
  REACHED. The verdict uses `k` alone.
- **REACHED** means the control's output names the same root cause or mechanism, as a claim it
  commits to (asserted, or adopted as a design premise). Naming the same file, symptom or topic is
  not enough. A question raised and then left open does not count. A claim the output contradicts
  elsewhere does not count.
- The claim may appear anywhere in the output, not only in its "What Opus 5 could not see" section.
- Different words and different receipts are fine. Exact numbers need not match: a different but
  correct measurement of the same mechanism counts.
- **PARTIAL** may be recorded as a note to show how close an item came, but it scores 0.
- Each score carries a quote from the control's output (or "no passage" for NOT REACHED, with the
  nearest passage, if any, quoted to show why it falls short).
- The scoring is done by a fresh-context judge that sees this rubric and the control's output, and
  never sees arm A's text beyond the criteria below. The lead re-checks every quote against the raw
  output and reports any disagreement with the judge rather than overriding it silently.

## The nine findings and what counts as reached

**F1 — It measured deaths and never looked at wakes.**
REACHED: the output states that interrupted sessions get re-engaged anyway, by the operator's typed
prompt and/or by a harness-originated wake, and puts the recovery audit on that re-engagement (the
next prompt or wake carries the audit). The point is that the wake is the design target.
NOT REACHED: a design that only detects the death (a census, a detector, a trigger on the error
record) and leaves what the next prompt carries unexamined.

**F2 — The error record's timestamp is not the death's time.**
REACHED: the output states that connectivity was lost long before the api-error record was written:
the client retries for an extended period (tens of minutes) while the process stays alive and the
transcript is silent, so disk silence or time since last activity cannot separate dead from alive.
This must be applied to unit liveness, for example showing that a time-window RUNNING rule (the
teammate `active < 5 min` window) misreads live units during an outage.
NOT REACHED: restating the brief's premise that "a stamp is not a liveness proxy" without the
retry-ladder mechanism or its consequence for the time window.

**F3 — The stall is a symptom, not a third cause.**
REACHED: the output rejects (or sharply qualifies) "stall is a third class" by identifying the
workflow stall as a symptom that can be the same network outage seen through a shorter timeout (the
stream watchdog), so the cause must be decided by evidence independent of the stall itself, such as
other sessions' or the fleet's activity in the same window, or a connectivity probe.
NOT REACHED: accepting stall as its own cause class, or giving a re-fire policy (re-fire once, back
off) without the symptom-versus-cause reframe and an independent discriminator.

**F4 — Stop hooks do not run on an api-error turn end.**
REACHED: the output states, as a measured fact or as a clearly identified hazard, that Stop hooks
(and with them goal, continue and re-arm logic) do not fire when a turn ends in an API error, so
recovery cannot be armed at the death by a Stop hook.
NOT REACHED: proposing a Stop hook for recovery, or not addressing whether Stop runs on that turn.

**F5 — The harness's own re-engagement path is the substrate.**
REACHED: the output identifies a harness-originated, keystroke-free wake (a `<task-notification>`
delivered to an idle session, or a hook-synthesized turn such as an asyncRewake exit 2) as the
mechanism that replaces the operator's typed paragraph, and puts the audit on it.
NOT REACHED: automation that types into the pane (send-keys, `it2 session send`), or "automatic"
with no named wake mechanism.

**F6 — `turn_duration` separates in-flight from idle.**
REACHED: the output names the transcript's `system` / `turn_duration` record (or another named
on-disk record that it shows is present at both normal and api-error turn ends) as the structural
turn-end marker that separates a turn still running (mid-retry) from an idle session.
NOT REACHED: a generic "check whether the turn finished" with no named record, or a marker that is
absent on api-error turns (for example `stop_hook_summary`).

**F7 — The retry files were never opened.**
REACHED: the output reads the stalled workflow's per-attempt files or journal and states that the
harness re-issued the same journal key several times (six attempts in the incident), that the
watchdog's kill is written to the slot as a user interrupt (`[Request interrupted by user]`), and
that the audit therefore misattributes the attempts to the user or TaskStop and/or under-counts them.
Two of these three parts are required: repeated attempts under one key, plus either the
misattribution or the under-count.
NOT REACHED: talking about the "6 × 180 s" stall from the brief without opening the attempt records.

**F8 — "No partial results" is not universal.**
REACHED: the output states that re-running a unit from scratch is safe only for read-only or
idempotent units and is a doubling or damage hazard for side-effecting ones (teammates that commit,
slots that write), so the recovery verdict or action must depend on the unit's class.
NOT REACHED: a uniform re-run rule for every unit type.

**F9 — The ask is an agency problem, not a trigger problem.**
REACHED: the output explicitly reframes the operator's ask: the problem is not detecting a death but
that a human is acting as the runtime, doing by hand (typing the paragraph into each pane) what the
system's own wake should do. It commits to a design where the system owns that act.
NOT REACHED: "make the trigger automatic" or "detect more death classes" without the reframe.

## Contamination

Arm B is invalid on an item if its transcript shows it read, before stating that item, any of:
the landed `NONLIMIT_RESUME_LADDER.md` with § W1 (any path other than its own worktree's copy),
`docs/research/api-error-rewake-proof-2026-09.md` or any post-2026-09-09 research doc on recovery,
a `scripts/limit-recover/` file outside its own worktree (the `~/.claude` symlinks resolve to the
post-W2 checkout), or a transcript record timestamped after 2026-09-09T18:07Z. An invalid item is
reported as such and scored NOT REACHED, and the report gives `k` with and without those items.

## Verdict

- `k ≥ 6`: the trial's findings are mostly reachable by a fresh default-model session with the same
  brief, so the effect is the fresh context, not the model tier. The decision stays "deliberate"; the
  report is the record.
- `k ≤ 5`: the frontier pass found things a fresh default session does not. Open a class-C decision:
  "switch frontier escalation to automatic after migration 0029", with conviction and the report as
  receipt.

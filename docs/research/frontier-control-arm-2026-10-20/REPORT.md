# Frontier control arm — result

**Score: k = 6 of 9.** A fresh Opus 5.5 session, given the same brief on the same base commit,
reached 6 of the nine findings from the 2026-09-09 Fable 5.1 trial.

**Verdict under the approved rule (6 or more ⇒ most):** keep frontier escalation a deliberate
choice. Decision `2c7259995a6b` stays "deliberate", and this report is its record. No new decision
is opened.

The rubric was fixed and landed before the run produced anything: `RUBRIC.md`, commit `f571a85f4`,
landed as `de863b3fe` at 2026-10-21T06:24Z. The control started at 06:20:28Z and its first scored
output appeared at 07:01:11Z.

## The two arms

| | Arm A (original trial) | Arm B (this control) |
|---|---|---|
| model / effort | `claude-fable-5-1` / xhigh | `claude-opus-5-5` / xhigh (init line and all 327 assistant records) |
| tier | frontier | default quota only; Fable never used |
| base commit | `8788dea27` | `8788dea27` (fresh detached worktree) |
| brief | `original-brief.txt` (7,630 B) | `control-prompt.txt`: the same brief plus a time fence and read-only delivery (RUBRIC.md § The control) |
| harness | 2.1.260-era, interactive pane, auto mode | 2.1.293, headless `claude -p`, auto mode, Edit/Write disallowed |
| wall time / turns | ~24 min, 46 tool calls | 40.7 min, 109 turns, 148 tool calls |
| subagents | none | 3 attempted; 2 refused by the machine capacity gate, 1 ran (fleet correlation) |
| output | `NONLIMIT_RESUME_LADDER.md` § W1 (`67fdf0670`) | `control-output.md` (34 KB, the final answer verbatim) |

Full arm-B transcript: `~/.claude-next/projects/-Users-chrisren-Development--worktrees-fca-control-base/1e1bcf42-de8b-4515-ac4e-5e1ff067a24a.jsonl`
(plus one subagent file under its `subagents/`).

## Scores, finding by finding

Scored by a fresh-context judge that saw only the rubric and arm B's output (`judge-scores.md`
has the full reasoning). The lead checked all 29 of the judge's quotes against the raw output: all
29 are verbatim once markdown bold and bullets are stripped.

| # | Arm A finding | B | Decisive quote from arm B |
|---|---|---|---|
| F1 | Measured deaths, never wakes | **REACHED** | "The missing piece is the moment of re-entry, not detection. … The fix is to run the disk audit in a hook and put its verdict table into the wake message." |
| F2 | Error timestamp ≠ death time (retry ladder, live process; 300 s window misreads live units) | NOT | Reaches the timestamp half ("The death record marks the end of the silence, not its start") but attributes the gap to machine sleep, says "Retries do not run while the machine sleeps", and never applies it to live units during an outage |
| F3 | Stall is a symptom, not a third cause | **REACHED** | "A stall is a third channel for the same causes, not a third cause." Control: "did any other session write real output during the stall's silent window?" |
| F4 | Stop hooks don't run on an api-error turn end | **REACHED** | From the 2.1.260 binary: "Fires instead of Stop when an API error … ended the turn"; the design arms its watcher earlier and probes whether it survives |
| F5 | Harness's own wake is the substrate | **REACHED** | asyncRewake exit 2 carries the audit; "No keystrokes: never type into live panes" |
| F6 | `turn_duration` separates in-flight from idle | NOT | Uses `stop_reason:"end_turn"` for healthy-idle vs interrupted; names no marker that separates a mid-retry turn from idle |
| F7 | Retry files never opened | **REACHED** | "Attempts 2–6 each restart … write 7 records and zero assistant output … and end in [Request interrupted by user]"; the audit yields "INTERRUPTED, 'TaskStop / user'" |
| F8 | "No partial results" not universal | NOT | ORPHANED units re-run uniformly; only a span-limited "re-read the remote" guard for ambiguous writes |
| F9 | Agency, not trigger | **REACHED** | "The framing assumed a non-quota interruption is a new kind of death that needs a new detector." "The automation has to be the reconciliation, not the re-prompt." |

**Lead's re-check (reported, not overriding).** I agree with F1, F3, F5, F7 (clear) and F6 (clear
miss). Three items are close calls:
- **F9** is the weakest REACHED. Arm B makes the reframe from detection to re-entry and gives the
  act to the system, but it never says outright that the operator is acting as the runtime.
- **F2** is the strongest NOT. Arm B has the timestamp-lag half, but it disputes the mechanism:
  sleep rather than a live retry ladder.
- **F4** rests on a quoted binary string rather than a prose claim. I agree it counts, because the
  design adopts it as a premise.

Under the stricter reading of F9, k is 5; under a looser reading of F2, it is 7. The score sits on
the threshold, and the pre-registered judge's 6 is the result.

## Contamination audit

The 2026-10-21 disk holds the trial's own findings, so arm B ran under a fence dated
2026-09-09T18:07Z. Checked against every tool call in the main stream and its subagent:

- **Repo code and docs:** read only from its own worktree at `8788dea27`. That commit has no § W1
  and no `turn_duration` in `scripts/` or `hooks/`. No read of the main checkout, other worktrees,
  or the `~/.claude` script symlinks.
- **Memory:** it opened 3 topic files, last modified 08-05, 08-10 and 09-06, all inside the fence.
  It listed the modification times of 9 more without reading them.
- **Post-cutoff data that reached it:** memory-file modification times, one api-error record from
  2026-10-06 (read for its JSON shape), and failed reads of newer harness binaries. None of these
  concerns any of the nine mechanisms.
- **Always-loaded context** (today's global CLAUDE.md, rules, MEMORY.md index, the worktree's
  project rules): no mention of `turn_duration`, asyncRewake, api-error turn ends, `[Request
  interrupted by user]`, or the operator as runtime (grep, 0 hits).

No item is invalidated, so k is 6 with and without the contamination rule.

## What it implies

1. **Most of the trial's value came from fresh context and a written brief, not the model tier.**
   That was the open question since 09-17. The answer is "mostly", by the narrowest margin the rule
   allows.
2. **The arms have different blind spots, not one stronger arm.** Arm B missed three of arm A's
   findings (`turn_duration`, the live retry ladder, unit-class re-run safety). It also found things
   arm A did not:
   - the `StopFailure` hook event and its closed `error` matcher set in the 2.1.260 binary;
   - an inferred machine-sleep explanation for the 09-09 silence;
   - DNS lag after wake tainting `ship-land`'s fetch;
   - one session held by two processes;
   - an existing but unregistered `stop-failure-marker.sh`.

   That fits the standing rule exactly: escalate for a *named* blind spot, deliberately, not by
   default.
3. **One factual disagreement is open and is not adjudicated here.** Arm A reads 09-09 as a
   network outage with live processes retrying; arm B infers machine sleep (dark-wake bursts about
   every 17 min, no real records 14:38:39–17:22:51Z). Arm B marks this INFERRED. It affects the
   recovery design (D4/D5 in arm B), not this verdict.
4. **Limits.** One run per arm, scored by one judge. Arm B ran 6 weeks later on a newer harness
   (2.1.293), under a fence arm A never had, and on a box at capacity that refused two of its three
   subagents. The 6-of-9 margin is zero, so a repeat run could land at 5.

## Disposition

Per the approved rule, nothing more is needed: the decision stays "deliberate" and this report is
its record. The 10-20 judge's alternative, a side-by-side Opus 5.5 run alongside the next deliberate
Fable ladder fire, remains a cheap way to grow the sample if the question is ever reopened.

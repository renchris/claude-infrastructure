# Limit-recover without the memory bottleneck — W0 research (2026-10-06)

Plan: `docs/plans/LIMIT_RECOVER_ZERO_MEMORY.md`. Method: one Dynamic Workflow, 16 read-only slots over Q1-Q8 (one of them a hostile reviewer), one synthesis slot, two skeptics (measurement lens, safety lens on a different model). Every slot wrote a file under `slots/`; the full 21-row change table and the 18 preserved disagreements between slots are in `slots/synthesis-draft.md`. This file is the lead's reading of them.

Tags used below are the slots' own: MEASURED (a command was run), READ (source or record text), INFERRED, EST.

**Sample size, stated once:** the move lane has exactly one multi-session batch on record, `~/.reso/limit-recover/move/20261006T060534Z-next3-next2-64630` (7 idle sessions, next3 to next2, width 4). Every move-lane timing below is n=7 from that batch.

## The binding constraint

**Memory is not what limits limit-recover to a few sessions at a time. Fixed numbers are.**

| Lane | What bounds it | Where | Did it bind in the records |
|---|---|---|---|
| Move (idle sessions, no model turn) | slot width, a literal 4, held for the whole relaunch and proof (mean 169.7 s) | `lr-move-worker.sh:50`, `lr-move-lib.sh:179` ("default 4 until a canary measures a safe width") | yes: 3 of 7 sessions waited 166.8-167.3 s for a slot, 29% of all worker-seconds (`slots/q1d`, `slots/q5a`) |
| Recover, one session (`--one`) | cap of 2 live recoveries, then a 900 s wait | `lr-fleet.sh:1380-1384` | yes: 38 of 353 runs since 2026-10-01 queued on it; time to rank p50 102 s queued against 3 s not queued (`slots/q1a`) |
| Recover pool | cap of 2 workers | `lr-fleet.sh:1361-1365` | no run on record since the pool landed |
| All lanes | a request waits for the launchd poller; a kick sent while a tick is running is dropped | `lr-reset-poller.sh:207-233`, plist `StartInterval` 600 | yes: 89 s of this batch's 523 s; 629-820 s on 7 of 30 switch and upgrade requests (`slots/q1c`) |
| Move and recover | the memory read: reclaimable memory over 4 GB and compressor segments under 90% | `lr-move-worker.sh:128-135`, `lr-move-batch.sh:151-155`, `lr-lib.sh:410-440` | **no: 8 of 8 admits in the batch, in under 1 s each; 0 refusals in 55 recover-lane probes; headroom 31-35 GB against the 4 GB floor, segments 4.1-4.6% against 90%** (`slots/q1b`, `slots/q1a`, `slots/q4`) |

None of the three caps takes a memory input, and no comment, commit or ruling gives memory as its reason (`slots/x-hostile-reviewer` table 1). Their recorded reasons are: the terminal's single control socket and overlapping TUI boots (move width), routing races and first-turn bursts on the target account (the caps of 2), and runaway fan-out from a poller tick.

Where the belief plausibly came from: on 2026-10-04 the compressor-segments term refused 13 times at 48-66% under a ceiling that was then 50%, parking nine sessions. The ceiling for swaps has been 90% since commit `85fb15804` the same day, and limit-recover callers show 0 refusals in 22 probes since 2026-10-05 (`slots/q4`).

## What one rotation costs in memory

| Component | Cost | Receipt |
|---|---|---|
| Recovery machinery, peak | 45-58 MB for under 1 s (about 105 MB on the largest transcript on the box, 241 MB) | `slots/q2a`, `/usr/bin/time -l` |
| Machinery left resident per rotated session | 14.7 MB (launcher shell and `expect`) | `slots/q2a`, n=11 |
| Transcript copy | 0 data bytes: an APFS clone, 1.2 MB and 0.02 s whatever the size | `slots/q3b`, 7 of 7 moves |
| The relaunched Claude Code process, typical transcript (up to 5 MB; 14 of 15 live sessions) | 177-197 MB real memory steady, 201-254 MB peak, stable in 3-5 s | `slots/q2b`, throwaway sessions, no prompt sent |
| Same, largest real transcript (230 MB) | 465 MB steady, 652 MB peak | `slots/q2b` |
| Net change on the machine | about zero: the old process exits before the new one starts | `slots/q2c`, source read and one traced move |

Ten typical relaunches at once peak near 2.5 GB, about 4% of 64 GB. `ps` RSS overstates these processes 1.7-3.5 times (it counts reclaimable pages); no current gate reads RSS.

So there is no per-rotation memory cost worth removing. The before and after for memory is the same number, and the plan's W1 item "remove or shrink the measured memory cost" is closed as nothing to remove.

## Answers Q1-Q8

| Q | Answer | Receipt |
|---|---|---|
| Q1 what bounds concurrency | Fixed caps (move width 4, recover 2 and 2), a serial admit lock on the recover lane (p50 13.2 s held), the poller's tick, and per-session wall time. The serial drainer is off the rotation path since 2026-10-04 (0 starts). Memory terms bound nothing in the records. | `slots/q1a`, `q1b`, `q1c`, `q1d` |
| Q2 where the memory goes | Almost all of it is the relaunched client (about 0.2 GB), which replaces a process that was already there. Machinery is 45-58 MB for under a second. | `slots/q2a`, `q2b`, `q2c` |
| Q3 is a second process needed | A successor process is needed, never a concurrent one. The account is fixed by the config directory at launch; the only documented in-process change is an interactive `/login`, which cannot be driven without typing into a pane. No lazy-resume flag exists. A shared transcript store is refused by the tooling and would save at most 5 s of 176 s. | `slots/q3a`, `q3b` |
| Q4 does the capacity gate measure the right thing | Mostly not memory: of 323 refusals to limit-recover callers in 18.3 days, 309 were load or active-session terms at segments under 15% and headroom over 23 GB. The 4 GB headroom floor refused 0 times in 2,604 rows. The move lane's two-term read costs nothing and stays. | `slots/q4` |
| Q5 wall time by step | Per session: median 176 s, p90 375 s. Of 1,751 worker-seconds: slot wait 29%, the typed relaunch waiting for the pane's shell 22%, a stall at the head of `lr-handoff` 16% (first wave only, cause not found), the watcher's proof 13%. Fixed clocks total 23.7 s per move. The batch took 523 s: 89 s poller hop, 4 s admit, 387 s workers, 44 s close. | `slots/q5a`, `q5b` |
| Q6 the two-command surface | Both halves exist under names that hide them (`recover --limited --account A` acts; `plan --from A --to B` lists). Missing: a fleet-wide form, busy sessions (printed and dropped), one verdict channel. Defects found: the batch roll-up is wrong in production, `move --sid <prefix>` has no ambiguity refusal, and `--until-idle` may restart a session that hit its limit while waiting (read from source, not reproduced). | `slots/q6` |
| Q7 target spread | The move lane sends all N to one target with no term for N. The recover lane asks per session and charges a 15-minute placeholder. The router's count-aware batch placement exists and only the idle reconciler calls it. In the record, 7 of 7 went to next2, which went from 1 to 13 panes. Concentrating on the soonest-resetting account is the router's design and the operator's 2026-10-04 ruling. | `slots/q7` |
| Q8 what tests pin | Caps are pinned as environment values, never as defaults, except the `--one` cap of 2. The move lane's memory read has no test at all (the fixture switches it off). The suites run under bash 5 while launchd runs `/bin/bash` 3.2, which is how the roll-up defect stayed green. Five replay controls are specified. | `slots/q8` |

## Defects the record exposed

1. **The batch summary is wrong on every batch.** `lr-move-batch.sh:80-83` puts a `case a|b)` inside `$( )`; `/bin/bash` 3.2 ends the substitution at the pattern's `)`. The recorded batch's `batch.log` holds the syntax error, `summary.json` says `"verdicts":"none"` and the one mail read "done: no rows" for 7 MOVED sessions. The same construct is at `bin/cc-lr:1370-1373` (MEASURED, `slots/q8` §5).
2. **A queue timeout reads as a memory refusal.** The slot-wait timeout says `capacity: no swap slot freed`, the same prefix as the memory refusal (`lr-move-worker.sh:124`, `:133`).
3. **A request written during a poller tick waits for the next one.** launchd does not start a second instance of a running job, so the kick is lost (`slots/q1c` §4).
4. **The skill text says recovery is "sequenced, one session at a time".** The pool has existed since 2026-09-21 (`commands/limit-recover.md:597`, `lr-fleet.sh:22`).

## Ranked changes, with the lead's conviction

Conviction is the probability that the change is correct and safe to land as stated. Changes above 90 are built in W1. The rest are not built; each names what would raise it.

| # | Change | Conviction | Basis |
|---|---|---|---|
| 1 | Fix the roll-up parse failure at both sites; a control replays the recorded batch through the runner under `/bin/bash` | 96 | reproduced in isolation by three slots; the record is the pre-fix output |
| 2 | Do no work on per-rotation memory or a shared store; keep the move lane's memory read as it is | 93 | the measurements above |
| 3 | Correct the stale "one at a time" text | 92 | source read |
| 4 | Make the memory read testable: a control with the recorded readings pinned (admits) and a 95% reading (refuses, nothing touched); pin the default width | 90 | today 0 tests go red if the read is deleted |
| 5 | Refuse an ambiguous `--sid` prefix on `move` and `plan`, as `switch --sid` already does | 91 | source read at three sites |
| 6 | Give the slot-wait timeout its own reason, and state the caps in force in the command's output | 91 | one reader of the prefix, a test |
| 7 | Close the lost kick while the poller stays the only starter: kick the move lane again when a tick ends, and have `cc-lr` re-send the plain kickstart while its request is unclaimed | 92 tick end, 90 client | the claim is a hard link, so a repeat cannot drive a batch twice |
| 8 | One verb for the surface: `cc-lr rotate --list` (writes nothing) and `cc-lr rotate (--all \| --account A)`, composed from the existing recover and move paths so every refusal stays where it is, with one verdict line per session | 91 with fixture tests | `slots/q6` §3; no new actuator |
| 9 | Close the until-idle hole (re-check for a limit error before a waiting row is promoted) so busy sessions can be waited on | 92 if it reproduces on the fixture | read from source only so far |
| 10 | Raise the move width above 4, or adapt it (widen after clean waves, halve on a slow boot) | 60 | nothing has run above 4; the one batch at 4 coincided with load 150 on 10 CPUs and 2 of 7 boot alarms. Needs a second real batch |
| 11 | Raise the recover caps from 2 | 55 | first-turn behavior above 6 simultaneous starts per account is unmeasured; an operator ruling of 2026-09-30 keeps 2 |
| 12 | Add the move runner and workers to the process reaper's whitelist | 70 | the rule's shape says a launchd-parented bash older than 600 s is killed, yet the log shows 0 such kills of recovery drivers that lived up to 2,028 s; not understood |
| 13 | Spread a batch over several targets through the router's batch placement | 55 | it gives 0 seats when the working-session count is unread (35.8% of sweeps); and it changes a routing ruling |
| 14 | Shorten the proof waits, or release the slot earlier | 35-60 | 52% of the batch's worker-seconds cannot be attributed to a step yet |

**What this means for the ask.** The memory bottleneck does not exist, so there is nothing to remove there. What does bound a rotation is the fixed widths, and the evidence does not support raising them blind: the only batch at width 4 is also the only evidence about load and boot failures at that width. W1 therefore removes the bounds that are safe to remove now (the lost 89 s, the false "no rows" summary, the misleading capacity label, the missing fleet-wide list and rotate commands) and leaves the widths where they are, printed in the output with their reason. Raising them is a decision that needs one more real batch, which this work is not allowed to run.

## What was not measured

- Any move batch but one; any width other than 4; any recover pool run since 2026-09-21.
- The cause of the 68-70 s stall before the bundle in the first wave, and of the 71-134 s between the typed relaunch and the launcher on two panes.
- Whether per-session time grows with width; the terminal's control socket above 4 concurrent streams.
- That `launchctl kickstart` on a running job is a no-op (inferred from 7 of 7 timings).
- Mutation runs behind "0 tests go red".
- Left behind by the measurements: `/tmp/lr-zm-throwaway-1/` (raw receipts) and one project entry for that path in `~/.claude-secondary/.claude.json` (`slots/q2b` §6).

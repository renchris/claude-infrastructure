# Limit-recover without the memory bottleneck — W0 research (2026-10-06)

Plan: `docs/plans/LIMIT_RECOVER_ZERO_MEMORY.md`. Method: one Dynamic Workflow, 16 read-only slots over Q1-Q8 (one of them a hostile reviewer), one synthesis slot, two skeptics (measurement lens, safety lens on a different model). Every slot wrote a file under `slots/`; the full 21-row change table and the 18 preserved disagreements between slots are in `slots/synthesis-draft.md`. This file is the lead's reading of them.

Tags used below are the slots' own: MEASURED (a command was run), READ (source or record text), INFERRED, EST.

**Sample size, stated once:** the move lane has exactly one multi-session batch on record, `~/.reso/limit-recover/move/20261006T060534Z-next3-next2-64630` (7 idle sessions, next3 to next2, width 4). Every move-lane timing below is n=7 from that batch.

## The binding constraint

**Memory is not what limits limit-recover to a few sessions at a time. Fixed numbers are.**

| Lane | What bounds it | Where | Did it bind in the records |
|---|---|---|---|
| Move (idle sessions, no model turn) | slot width, a literal 4, held for the whole relaunch and proof (mean 169.7 s) | `lr-move-worker.sh:50`, `lr-move-lib.sh:179` ("default 4 until a canary measures a safe width") | yes: 3 of 7 sessions waited 166.8-167.3 s for a slot, 29% of all worker-seconds (`slots/q1d`, `slots/q5a`) |
| Recover, one session (`--one`) | cap of 2 live recoveries, then a 900 s wait | `lr-fleet.sh:1380-1384` | yes: 38 runs since 2026-10-01 logged the cap wait, 17 of the 38 that ended RECOVERED among them; time to rank p50 102 s queued against 3 s not queued (`slots/q1a`, `slots/skeptic-measurement`) |
| Recover, target supply | no account the router will rank | `lr-fleet.sh:760-837` | yes, more often than the cap: 47 `parked: no routable target` rows over 12 sessions since 2026-10-01 (`slots/skeptic-measurement`) |
| Recover pool | cap of 2 workers | `lr-fleet.sh:1361-1365` | no run on record since the pool landed |
| All lanes | a request waits for the launchd poller; a kick sent while a tick is running is dropped | `lr-reset-poller.sh:207-233`, plist `StartInterval` 600 | yes: 89 s of this batch's 523 s; 629-820 s on 7 of 30 switch and upgrade requests (`slots/q1c`) |
| Move and recover | the memory read: reclaimable memory over 4 GB and compressor segments under 90% | `lr-move-worker.sh:128-135`, `lr-move-batch.sh:151-155`, `lr-lib.sh:410-440` | **no: 8 of 8 admits in the batch, in under 1 s each; 0 refusals in 55 recover-lane probes; headroom 31-35 GB against the 4 GB floor, segments 4.1-4.6% against 90%** (`slots/q1b`, `slots/q1a`, `slots/q4`) |

None of the three caps takes a memory input, and no comment, commit or ruling gives memory as its reason (`slots/x-hostile-reviewer` table 1). Their recorded reasons are: the terminal's single control socket and overlapping TUI boots (move width), routing races and first-turn bursts on the target account (the caps of 2), and runaway fan-out from a poller tick.

Where the belief plausibly came from: the compressor-segments term refused 13 times (12 on 2026-10-04, 1 on 2026-10-02) at 54-66% under a ceiling that was then 50%, parking nine sessions. The ceiling for swaps has been 90% since commit `85fb15804` on 2026-10-04. Over 14,375 samples from 2026-09-19 to 2026-10-06 the box never read segments at or above 90% (max 72.1%) and never under 4 GB of headroom (min 8.56 GB) (`slots/q4`, `slots/skeptic-measurement`). A timed-out wait for a move slot also said `capacity:`, the memory refusal's own prefix.

**What the skeptics corrected.** Both skeptics confirmed that memory is not the bound, and both weakened "the width alone is the bound":

- The slot wait is confounded. Of each 167 s wait, 68 s is a stall shared by all four first-wave sessions whose cause is not known; the same code took 105-110 s four wide and 16 s three wide.
- Boot time grew about three times inside the one batch as load rose: typed relaunch to engaged was about 59 s for the first four, 89 s for the fifth and about 170 s for the last two, at load 119-150 on 10 CPUs. The lane reads no load term. Behind the width sits CPU and boot time, and the record shows it getting worse, not better.
- The memory evidence for the batch is two box readings, not eight independent ones, and the "22 probes since 2026-10-05" all fall inside 18 minutes on 2026-10-06.
- The headroom term did refuse 3 times, on 2026-09-29, at 9.1-9.8 GB against a 4 GB floor plus a 6 GB operator reserve. The bare 4 GB floor refused 0 times.
- An empty `--sid` matched every session fleet-wide on `move` and `plan`, a wider hole than the prefix case the slots reported.
- No suite ran the move worker under `/bin/bash`, the interpreter launchd gives it.

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
| 9 | Close the until-idle hole (re-check for a limit error before a waiting row is promoted) so busy sessions can be waited on | 93 | reproduced on the fixture in W1: before the fix the row was restarted with no prompt and reported MOVED |
| 10 | Raise the move width above 4, or adapt it (widen after clean waves, halve on a slow boot) | 45 (both skeptics moved it down from 60) | nothing has run above 4; the one batch at 4 coincided with load 150 on 10 CPUs, 2 of 7 boot alarms and boot time tripling. Needs a second real batch with per-stage timestamps |
| 11 | Raise the recover caps from 2 | 45 (moved down from 55) | first-turn behavior above 6 simultaneous starts per account is unmeasured; the throughput estimate rests on 18 surviving runs; an operator ruling of 2026-09-30 keeps 2 |
| 12 | Add the move runner and workers to the process reaper's whitelist | 70 | the rule's shape says a launchd-parented bash older than 600 s is killed, yet the log shows 0 such kills of recovery drivers that lived up to 2,028 s; not understood |
| 13 | Spread a batch over several targets through the router's batch placement | 55 | it gives 0 seats when the working-session count is unread (35.8% of sweeps); and it changes a routing ruling |
| 14 | Shorten the proof waits, or release the slot earlier | 35-60 | 52% of the batch's worker-seconds cannot be attributed to a step yet |

**What this means for the ask.** The memory bottleneck does not exist, so there is nothing to remove there. What does bound a rotation is the fixed widths, and the evidence does not support raising them blind: the only batch at width 4 is also the only evidence about load and boot failures at that width. W1 therefore removes the bounds that are safe to remove now (the lost 89 s, the false "no rows" summary, the misleading capacity label, the missing fleet-wide list and rotate commands) and leaves the widths where they are, printed in the output with their reason. Raising them is a decision that needs one more real batch, which this work is not allowed to run.

## W1 result: before and after

Built in commit `c91d7210b`: rows 1, 4, 5, 6, 7, 8 and 9 of the table above, plus the stale text (row 3). Rows 10 to 14 were not built.

| Quantity | Before | After | How the after figure was obtained |
|---|---|---|---|
| Memory per rotation, relaunched client | 177-197 MB steady, 201-254 MB peak (typical transcript); net about zero on the machine | the same: no change touches the relaunch | measured before on throwaway sessions (`slots/q2b`); nothing in W1 alters it |
| Memory per rotation, machinery | 45-58 MB peak for under 1 s | the same plus two transcript-tail reads: 12.3 MB peak, 0.10 s for both | `/usr/bin/time -l` on the two reads over a 1.7 MB transcript, this worktree |
| Batch wall time, the recorded 7-session batch, request to summary | 523 s (89 s waiting for the poller, 4 s admit, 387 s workers, 44 s close) | about 453 s: the 89 s wait becomes about 19 s | computed from the record, not run: the tick in flight when the request arrived logged its last line at 06:05:53Z, 19 s after the request, and the fixed poller starts the batch as that tick ends. A real rotation was outside this work's limits |
| The batch's own report | `"verdicts":"none"`, mail "done: no rows", for 7 MOVED | `MOVED=7` in the summary and the mail | replay of the record's on-disk shape through the runner under `/bin/bash` (`tests/lr-move-concurrency.bats` case 14; red on the commit before) |
| `cc-lr move` exit code after a fully moved batch | 1 (watcher records and the claimed request were counted as failures) | 0 | `tests/lr-move-plan.bats` case 17; red on the commit before |
| A session that hit its limit while waiting for idle | restarted with no prompt and reported MOVED | NOTMOVED `became-limited`, nothing touched | `tests/lr-move-worker.bats` case 15; red on the commit before |
| Commands to see and rotate everything | one `recover --limited --account A` per account, busy sessions dropped, verdicts in two places | `cc-lr rotate --list`, then `cc-lr rotate --all` | `tests/cc-lr-front.bats`, 8 rotate cases |
| Concurrency widths | move 4, recover 2, unstated | move 4, recover 2, printed with their reasons in every `rotate`, `plan` and `move` output | unchanged on purpose; see rows 10 and 11 |

Suites run on the final tree, each with its plan line and 0 failures: lr-move-worker 1..20, lr-move-plan 1..18, lr-move-concurrency 1..17, lr-move-verdict 1..16, cc-lr-front 1..80, cc-lr-request 1..18, lr-doc-banned-transport 1..3, lr-switch-driver 1..39, lr-switch-bg-attach 1..32, lr-stale-markers 1..17, lr-upgrade 1..54, lr-fleet 1..138, lr-recon-fence-callsites-fleet 1..7, and the twelve poller suites (lr-reset-poller 1..38, -overlap 1..9, -requests 1..44, -bash32 1..2, -consolidate 1..10, -engagement 1..17, -inplace 1..38, -reroute 1..11, -resume-sweep 1..4, lr-poller-bg-not-teammate 1..8, lr-autorecover-drill 1..5, lr-recon-fence-callsites-poller 1..22). Control: the same new test files run against commit `c6f7dd483` fail exactly the cases marked RED.

## What was not measured

- Any move batch but one; any width other than 4; any recover pool run since 2026-09-21.
- The cause of the 68-70 s stall before the bundle in the first wave, and of the 71-134 s between the typed relaunch and the launcher on two panes.
- Whether per-session time grows with width; the terminal's control socket above 4 concurrent streams.
- That `launchctl kickstart` on a running job is a no-op (inferred from 7 of 7 timings).
- Mutation runs behind "0 tests go red".
- Left behind by the measurements: `/tmp/lr-zm-throwaway-1/` (raw receipts) and one project entry for that path in `~/.claude-secondary/.claude.json` (`slots/q2b` §6).

---
status: complete
---
# Limit-recover without the memory bottleneck — plan

Scope (frozen): moving every session that needs a different account is two quick commands, one that lists them (by account or fleet-wide) and one that rotates all of them in place to the right account, and the rotation is not throttled to one or two at a time by memory: the per-session memory cost of a rotation is measured, its cause is removed or cut to near zero, and whatever concurrency limit remains is set by a measured constraint and stated in the command's output.

Predecessors (read, do not restate): `docs/plans/LIMIT_RECOVER_100P.md`, `docs/plans/LIMIT_RECOVER_FLEET_V2.md`, `docs/plans/LIMIT_RECOVER_FLEET_V2_ARCHITECTURE.md`, `docs/plans/VOLUNTARY_ACCOUNT_SWITCH.md`, `docs/plans/MACHINE_CAPACITY_V2.md`.

## Phase 0 — orchestration — DONE

- **Execution locus per wave:** W0 research = **S** (the dispatched session runs it as a Dynamic Workflow, read-only slots on `agentType: 'workflow-lean'`). W1 implementation = **S** (same dispatched session leads; Agent Teams if the change splits across `bin/cc-lr`, the move lane and the recover lane with separate owners).
- **Lead context budget:** research returns as schema'd slot results and one synthesis at `docs/research/limit-recover-zero-memory-2026-10-06/README.md`; the lead keeps at least 50% for deciding and recycles after the synthesis is committed if it is past 50%.
- **Gate:** the bats suites that cover the files the change touches (find them with `grep -l` over `tests/` for the script names; assert the `1..N` plan line), bare `shellcheck` on changed shell files, `python3 -m py_compile` on changed Python, then the project `/ship` and the degraded-tier converge.
- **Hard constraints:** the safety refusals stay (teammate, ambiguous ref, not-limited, duplicate, mid-turn, a real draft in the composer, one actuator per session); a faster rotation that types into a busy or wrong pane is a regression. Nothing is typed into a live pane from inside a session; actuation stays with the poller and its drainer. Research and tests never move, exit or type into a real live session: measure on fixture panes and throwaway sessions, and from logs of past runs. No settings or allowlist edits.

## What the operator sees today (2026-10-06, the reason this plan exists) — DONE

- Operator's understanding: recovery runs one to a few sessions at a time because of memory, and that is the bottleneck. This is a hypothesis until W0 measures it.
- Measured this session, next3 at weekly 100%: `cc-lr recover --limited --account next3` listed and queued in one command. The batch of 7 idle sessions (`20261006T060534Z-next3-next2-64630`) was queued at 06:05:34Z and its "done" mail arrived at 06:14:18Z, about 9 minutes for 7 moves.
- The limited VoiceInk session (`4ad354fc`) was HELD twice for background shells before a third attempt submitted; pane 8 was mid-turn, then limited, then held by another actuator.
- Code facts read, not yet measured: the recover pool defaults to `LR_RECOVER_MAX_CONCURRENT` 2 and the single-session lane to `LR_ONE_MAX_CONCURRENT` 2 (`scripts/limit-recover/lr-fleet.sh`, near lines 1362 and 1381); the header comment there records serial recoveries of 115 to 658 s each; the move worker reads a kernel-safety term (swap segments under a 90% ceiling, headroom over a floor) before acting (`scripts/limit-recover/lr-move-worker.sh:129`, `lr-move-batch.sh:12`); upgrades and switches share one serial drainer (`bin/cc-lr`, near lines 735 and 1946).

## W0 — research (Dynamic Workflow, before any edit) — DONE

| # | Question | Where to read |
|---|---|---|
| Q1 | What actually bounds concurrency today, per lane (recover, move, switch, upgrade): a memory gate, a fixed cap, a lock, the serial drainer, or per-session wall time? Which bound was the binding one in recent runs? | `scripts/limit-recover/lr-fleet.sh`, `lr-move-batch.sh`, `lr-move-worker.sh`, `lr-upgrade.sh`, `lr-reset-poller.sh`, `bin/cc-lr`; `~/.reso/limit-recover/` run and move records; `~/.claude/land.log` is not relevant |
| Q2 | Where does the memory of one rotation go: the recovery machinery itself (audit, transplant copy, expect layer, watchers) or the relaunched `claude --resume` process loading a large transcript? Peak and steady RSS for each, on throwaway sessions of small and large transcript size | `lr-audit.py`, `lr-transplant.sh`, `lr-fire-resume.sh`; `ps`/`footprint` on fixture runs |
| Q3 | Does a rotation need a second process at all? Compare relaunch-with-resume against the alternatives: swapping the credential under a live process, a cold relaunch that loads lazily, a move that copies nothing because stores are shared or linked. What does Claude Code permit on the current version? | the binary's behavior on a throwaway session, the vendor docs, `docs/plans/VOLUNTARY_ACCOUNT_SWITCH.md` |
| Q4 | Is the capacity gate measuring the right thing? What did it refuse or delay in the last 30 days of recoveries, and how often was the refusal followed by real memory pressure versus none | `MACHINE_CAPACITY_V2.md`, the capacity probe's logs, the admission ledger |
| Q5 | Wall time of one rotation, split by step (probe, transplant, exit, shell wait, relaunch, engagement proof). Which steps are waits on a clock rather than on an event? | per-run `events.jsonl`, `results.tsv`, `lr-fleet.sh` proof waits |
| Q6 | The two-command surface: what do `cc-lr find --limited`, `cc-limited --json`, `cc-lr recover --limited`, `cc-lr switch --from A --all-idle` and `cc-lr move --from A --to B` each cover, where do they overlap, and what is missing for "list everything that needs rotating" and "rotate all of it to the right accounts" as one command each, including sessions that are busy now | `bin/cc-lr`, `bin/cc-limited`, the skill text `commands/limit-recover.md` |
| Q7 | Target choice at fleet scale: when N sessions leave one account, how are they spread over the others so the move does not push a second account to its wall | `bin/claude-accounts` rank and recovery floors, `lr-fleet.sh` admit section |
| Q8 | What do the existing suites pin, and which controls must replay real past runs so the change is proven against the pre-fix behavior | `tests/lr-*.bats`, `tests/cc-lr*.bats`, `tests/handoff-recycle-*.bats` |

Deliverable: `docs/research/limit-recover-zero-memory-2026-10-06/README.md` with the measured answer per row, the binding constraint named, and ranked changes with a conviction number each.

## W1 — implementation (shape depends on W0; expected, not decided) — DONE

- Remove or shrink the measured memory cost per rotation, then raise or remove the concurrency caps to what the remaining measured constraint allows.
- One list command and one rotate command that cover limited, idle-on-a-capped-account and busy-now sessions, with per-session verdicts and target spread.
- Controls that replay real past runs, and a before and after measurement of memory per rotation and wall time for a batch.

## Status — DONE

- 2026-10-06: plan created from the operator's ask and this session's next3 recovery; nothing implemented. Research not started.
- 2026-10-06, W0 done (`b485687a0`, `c6f7dd483`): 16 research slots, a synthesis and two skeptics; receipts in `docs/research/limit-recover-zero-memory-2026-10-06/`. **The hypothesis is refuted: memory does not bound a rotation.** 8 of 8 memory reads admitted in the one recorded batch; a relaunch costs about 0.2 GB that replaces a process already there. The bounds are fixed counts (move width 4, recover 2 and 2), a poller kick lost while a tick runs (89 s of that batch's 523 s), and per-session wall time whose two largest parts have no known cause yet.
- 2026-10-06, W1 done (`c91d7210b`): `cc-lr rotate --list` and `cc-lr rotate (--all | --account A)`; the batch roll-up fixed under the launchd shell (it had mailed "no rows" for 7 MOVED); the poller looks at move requests again as each tick ends, and `cc-lr` re-sends its kick; a slot-wait timeout no longer says `capacity:`; a session that became limited while waiting is held, not restarted without a prompt; `plan`/`move --sid` refuse an empty or ambiguous prefix; the bounds in force are printed with their reasons. Controls replay batch `20261006T060534Z-next3-next2-64630`. Before and after: README § W1 result.
- **W1 scope changed by the measurement, and why:** "remove or shrink the measured memory cost per rotation" has nothing to remove (same number before and after). "Raise or remove the concurrency caps to what the remaining measured constraint allows" was NOT done: the only batch at width 4 is also the only evidence at that width, and it shows load 150 on 10 CPUs, 2 of 7 slow boots and boot time tripling inside the batch. Both skeptics put a wider default at 45% conviction. The widths stay at 4 and 2 and are stated in the output.
- **Open, each needing a real rotation this work was not allowed to run:** a trial of the next real batch at `--slots 6` with per-stage timestamps (decision filed, see the close); the cause of the 68-70 s stall at the head of `lr-handoff` and of the 71-134 s between the typed relaunch and the launcher; whether the process reaper would end a batch older than 600 s (the rule's shape says yes, its log shows 0 such kills). Not built and left as is: spreading one batch over several targets (the router's 2026-10-04 ruling concentrates on the soonest-resetting account).
- 2026-10-06, plan closed (cc-backlog `ed9e2ce7dfdb`, cloud session): every section's work is on trunk (mirror shas `cf41e6aa`, `a05b5f95`, `7368bd1d`, `0cc89c51`; desk shas as cited above) and the frozen scope is met — memory was measured and is not a per-rotation cost to remove, and the widths in force are set by the measured load evidence and printed with their reasons. Rows 10-14 of the research's ranked table are outside this plan: each needs a real rotation this plan forbids running. Verdict: `docs/research/limit-recover-zero-memory-close-2026-10-06.md`.

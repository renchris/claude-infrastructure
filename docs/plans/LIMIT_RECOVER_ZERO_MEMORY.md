---
status: open
---
# Limit-recover without the memory bottleneck — plan

Scope (frozen): moving every session that needs a different account is two quick commands, one that lists them (by account or fleet-wide) and one that rotates all of them in place to the right account, and the rotation is not throttled to one or two at a time by memory: the per-session memory cost of a rotation is measured, its cause is removed or cut to near zero, and whatever concurrency limit remains is set by a measured constraint and stated in the command's output.

Predecessors (read, do not restate): `docs/plans/LIMIT_RECOVER_100P.md`, `docs/plans/LIMIT_RECOVER_FLEET_V2.md`, `docs/plans/LIMIT_RECOVER_FLEET_V2_ARCHITECTURE.md`, `docs/plans/VOLUNTARY_ACCOUNT_SWITCH.md`, `docs/plans/MACHINE_CAPACITY_V2.md`.

## Phase 0 — orchestration

- **Execution locus per wave:** W0 research = **S** (the dispatched session runs it as a Dynamic Workflow, read-only slots on `agentType: 'workflow-lean'`). W1 implementation = **S** (same dispatched session leads; Agent Teams if the change splits across `bin/cc-lr`, the move lane and the recover lane with separate owners).
- **Lead context budget:** research returns as schema'd slot results and one synthesis at `docs/research/limit-recover-zero-memory-2026-10-06/README.md`; the lead keeps at least 50% for deciding and recycles after the synthesis is committed if it is past 50%.
- **Gate:** the bats suites that cover the files the change touches (find them with `grep -l` over `tests/` for the script names; assert the `1..N` plan line), bare `shellcheck` on changed shell files, `python3 -m py_compile` on changed Python, then the project `/ship` and the degraded-tier converge.
- **Hard constraints:** the safety refusals stay (teammate, ambiguous ref, not-limited, duplicate, mid-turn, a real draft in the composer, one actuator per session); a faster rotation that types into a busy or wrong pane is a regression. Nothing is typed into a live pane from inside a session; actuation stays with the poller and its drainer. Research and tests never move, exit or type into a real live session: measure on fixture panes and throwaway sessions, and from logs of past runs. No settings or allowlist edits.

## What the operator sees today (2026-10-06, the reason this plan exists)

- Operator's understanding: recovery runs one to a few sessions at a time because of memory, and that is the bottleneck. This is a hypothesis until W0 measures it.
- Measured this session, next3 at weekly 100%: `cc-lr recover --limited --account next3` listed and queued in one command. The batch of 7 idle sessions (`20261006T060534Z-next3-next2-64630`) was queued at 06:05:34Z and its "done" mail arrived at 06:14:18Z, about 9 minutes for 7 moves.
- The limited VoiceInk session (`4ad354fc`) was HELD twice for background shells before a third attempt submitted; pane 8 was mid-turn, then limited, then held by another actuator.
- Code facts read, not yet measured: the recover pool defaults to `LR_RECOVER_MAX_CONCURRENT` 2 and the single-session lane to `LR_ONE_MAX_CONCURRENT` 2 (`scripts/limit-recover/lr-fleet.sh`, near lines 1362 and 1381); the header comment there records serial recoveries of 115 to 658 s each; the move worker reads a kernel-safety term (swap segments under a 90% ceiling, headroom over a floor) before acting (`scripts/limit-recover/lr-move-worker.sh:129`, `lr-move-batch.sh:12`); upgrades and switches share one serial drainer (`bin/cc-lr`, near lines 735 and 1946).

## W0 — research (Dynamic Workflow, before any edit)

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

## W1 — implementation (shape depends on W0; expected, not decided)

- Remove or shrink the measured memory cost per rotation, then raise or remove the concurrency caps to what the remaining measured constraint allows.
- One list command and one rotate command that cover limited, idle-on-a-capped-account and busy-now sessions, with per-session verdicts and target spread.
- Controls that replay real past runs, and a before and after measurement of memory per rotation and wall time for a batch.

## Status

- 2026-10-06: plan created from the operator's ask and this session's next3 recovery; nothing implemented. Research not started.

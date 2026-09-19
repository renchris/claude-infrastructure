# The land gate exempts itself from the bats admission ceiling — never hand-roll a wait for a slot

**2026-09-19 · bin/cc-bats · scripts/ship-land.sh:2209 · scripts/land-lock.sh**

## The rule

`cc-bats` refuses a run when `CC_BATS_MAX_ROOTS` (2) concurrent execution roots AND load/core ≥ 2.0
both hold. **The land gate is exempt from that ceiling and always has been** — so a session that
waits for a bats slot before `/ship` is waiting on a gate that does not apply to it.

```
# scripts/ship-land.sh:2209
CC_GATE_MAX_LOAD=0 CC_BATS_MAX_ROOTS=0 ${homeenv[@]+"${homeenv[@]}"} bats "$@" </dev/null
```

Concurrency is bounded instead by `scripts/land-lock.sh`, a machine-wide mutex keyed on
`--git-common-dir` (deliberately not `--show-toplevel`), so at most ONE land gate per repo runs
across every worktree on the box. The bound is the lock, not the ceiling. Recorded rationale, in
the file: *"a land gate that does not run is not a safer land, it is no land."*

`postland-verify.sh` takes the same exemption for the same reason.

## Therefore

**The human-free workflow already exists and needs nothing built:** commit → `bash
scripts/ship-land.sh` → read its verdict. It runs on a fully saturated box without an admission
refusal. Polling `~/.claude/state/bats-roots.d` or the load average before shipping is wasted work,
and an `until`-loop that does it is the defect, not a missing capability.

## Two facts that make the design safe, and one that makes the gate's refusal honest

- A refusal exits **75 (EX_TEMPFAIL)**, never 0, so it cannot be laundered into a pass. Before the
  land-gate exemption existed this produced 1,045 rows of `phase=land-gate signal='exit 75 /
  notok=0' outcome=cut-not-red` — 56% of all flake rows.
- **`cc-bats` is deliberately shedding, not waiting** (R1: *"nothing here waits, sleeps, queues,
  retries or polls in a loop"*), because a previous `gate_admit` failed *because it slept*. So
  "make the gate wait for a slot" is a fix that was already tried and reverted. Any queueing must
  live in the caller, and for the land path no queueing is needed at all.
- Pass `CC_BATS_WAIVER_REASON` when you do set `CC_BATS_MAX_ROOTS=0` yourself; waivers are recorded
  machine-wide and an `UNSTATED` reason is worth nothing to whoever reads the log later.

## What the ceiling actually binds

Only ad-hoc interactive suite runs — the cheap case. And its load term convicts bats for load it
did not create: a 2-second suite is shed because another repo's typecheck pinned the CPU. Before
proposing to raise `CC_BATS_MAX_ROOTS`, measure real idle (`top -l 2 -n 0`), not the load average
alone — on the day this was written the box was genuinely saturated at **1.15% idle on 10 cores**,
so raising the cap would have added contention, not capacity.

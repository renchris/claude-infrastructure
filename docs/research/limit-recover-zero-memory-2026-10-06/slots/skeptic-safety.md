# Skeptic, safety lens — 2026-10-06

Scope: ranks 1-8 (≥85%), the headline, what the slots missed. MEASURED = I ran it; READ = file:line.

## Headline: survives, with one refinement

- 8 of 8 `lr-move-*` kernel reads admit; 22 of 22 limit-recover probes since 2026-10-05 admit (MEASURED: `jq` over `~/.claude/autonomy/idl.jsonl`).
- Slot waits 166.8 / 167.2 / 167.3 s; first wave-2 slot 0.455 s after wave 1's first proof (MEASURED: 7 `*.events.jsonl`).
- Missed by every slot: per-boot time grew 3x inside the batch. Typed-relaunch → engaged was ~59 s for all four wave-1 boots (load1 23-43), 89 s for pane 14, ~170 s for panes 15/16, which the watcher flagged `INDETERMINATE:boot` at 71 s and 120 s (load1 119-150). MEASURED: `$TMPDIR/handoff-recycle-<pane>-*.log` "after Ns" lines and file mtimes 01:09:52-54 / 01:11:45 / 01:13:15 local (UTC-5), n=7. The lane reads no load term (READ `lr-move-worker.sh:132`); the reconciler's design says boots "failed at load 40+" (READ `lr_recon/admit.py:258`). The bound is the width literal; behind it, CPU/boot time, which the record shows growing.

## Refuted or corrected

| Claim | Why | Receipt |
|---|---|---|
| Rank 1 is a change to make | Already in the working tree, uncommitted, by another session (7 tracked files modified, mtime 02:08 local). HEAD, `main` and the deployed target (`~/.claude/scripts/limit-recover/` → main checkout) still carry the bare pattern: production fails every batch today. `bash -n` under 3.2 returns 0 on the HEAD file: runtime-only, no lint gate catches it; the uncommitted test 14 runs the runner under `/bin/bash`. The `cc-lr:1371` site never ran under 3.2 (`env bash`, invoked from sessions); its HEAD defect was the exclusion list (`*.watcher.json`, `request.claimed.json` read as FAILED → rc 1 after a fully moved batch). | MEASURED `git status`; `git grep LEADING-PAREN HEAD/main` = 0; `/bin/bash -n` rc 0; 3.2.57 micro-repro |
| Rank 5: "prefix matches more than one" | `--sid ""` matches every live session fleet-wide and `move` plans them all onto `--to`: no emptiness check, `case "$sid" in ""*)` on interactive and bg rows, no `--from` ⇒ no account filter. `switch --sid ""` is refused (`nsub=0`). The uncommitted `cl_move_sid_unique` closes both by counting rows. | READ `bin/cc-lr:1244,1269`; `lr-upgrade.sh:2488,922-923,1002` |
| Rank 4 "0 tests red" | RC2 (worker.bats 17-18, ledger pinned to tmp), RC5 (concurrency.bats 14-15) and the exclusion case (plan.bats 17) exist uncommitted. Still missing: no suite runs the worker, `lr-handoff.sh` or `handoff-fire.sh` under `/bin/bash`; the poller's PATH is `/usr/bin:/bin:/usr/sbin:/sbin`, so `"$HF"` (`env bash`) is 3.2 too. Two static passes (case-in-`$( )` scanner, bash-4 grep) found 0 further sites. | MEASURED `launchctl print`; READ `lr-handoff.sh:1890`, `lr-move-worker.bats:37` |
| Rank 8 "no-op kickstart is inferred" | 0 `TICK-SKIP` in 1,850 `TICK start` lines while requests arrived mid-tick: launchd never started a second instance. Tail call (EXIT trap) and 15 s re-kick are in the working tree; deployed poller and cc-lr lack both. | MEASURED `grep -c` on `poller.log`; READ worktree `lr-reset-poller.sh:233-246` |
| "Width 4 is the bound", "bounded together" | The reconciler's mirror scans `slot-1..6` (START=6); the move lane scans 1..4. Joint bound is max(4, 6) once the reconciler leaves observe mode (now observe: `recon/mode` absent; agent running). | READ `admit.py:260-271,316`, `lr-move-lib.sh:177-188` |
| Rank 7 message | New reason text ends "widen this batch: cc-lr move --slots <W>": a NOTMOVED recommending the unmeasured ramp (rank 15 at 60). Name the flag; do not recommend it. | READ worktree `lr-move-worker.sh:142` |

Ranks 2, 3, 6 hold. No test pins the skill prose (only the banned table is asserted). Watcher readers are `^`-anchored or substring (READ `handoff-fire.sh:1905,1938-1940`, `lr-fleet.sh:1015`, `lr-move-worker.sh:154`; 0 `$`-anchored); `pane_cc_state` is `ps -t`-based, so a launcher stamp line is harmless. Exit and engagement times are already readable from the watcher logs.

## Convictions moved

- Rank 15: 60 → 45. Boot time tripled within one 7-session batch as load rose; a 6-wide wave puts 6 boots into that window with no load read.
- Rank 5: 90 → 92. Wider hole than stated; the count-based refusal closes it; plan.bats 16 pins it.
- Rank 8 tail call: 85 → 88 (the 0/1,850 receipt; hard-link claim at `:286-290`).
- Rank 4: 90 → 88 until one case runs the worker chain under `/bin/bash`.
- Rank 7: 87 → 85 (message content).
- Rank 2: 92 → 90. The term is swap-derived (READ `capacity-admit.sh:281-295`); the one 65.02% refusal came 6.7 h after the 90% commit (`85fb15804`, 2026-10-04) and is untraced.

## Missing

- A worker / lr-handoff / handoff-fire run under 3.2 in any suite.
- Cause of the 68 s head stall (bundles 06:08:16Z vs actuate 06:07:08Z) and `one-20261006T060704Z` reaching rank at 06:08:22Z; the head calls the router only for `--target auto` (`lr-handoff.sh:706`).
- CPU attribution for load1 150 (`capacity-alarm.jsonl` `top_procs` are by RSS).
- A commit of the working-tree changes; my receipts separate HEAD from the diff.

Deviation: the checkout was not unmodified on arrival; I edited none of those files. Scratch only in `/tmp/lr-skeptic/`.

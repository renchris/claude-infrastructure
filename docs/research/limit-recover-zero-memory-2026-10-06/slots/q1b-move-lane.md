# q1b — what bounds concurrency in the move lane, and which bounds are memory-derived

Date 2026-10-06. Scope: `scripts/limit-recover/lr-move-batch.sh` (256 lines), `lr-move-worker.sh` (183), `lr-move-lib.sh` (232), plus the two things they call for the kernel read (`lr-lib.sh:410-440`, `scripts/lib/capacity-admit.sh`). The deployed copies under `~/.claude/scripts/` are byte-identical to this checkout for all five files (MEASURED: `diff -q` x5, all SAME), so what was read is what ran.

Tags: MEASURED = I ran it; READ = source or record; INFERRED = derived.

## Verdict

- **Memory does not bind the move lane.** One mechanism is memory-derived (the kernel-safety read, two call sites). It admitted 8 of 8 times on record, with 29 GB and 85.5 points of margin.
- **What binds is the slot semaphore: a static width of 4, held for 111-207 s per session.** Width is a literal, not computed from memory or anything else. In the one batch on record it made 3 of 7 sessions wait 167 s each.
- **At width 4 and the measured hold, a rotation of more than about 16 sessions will leave its tail NOTMOVED** on the 600 s slot-wait bound (INFERRED, queue arithmetic on n=7). That refusal is labelled `capacity:`, the same prefix as a memory refusal.
- Evidence base is thin: the move lane has exactly **one** batch on record (7 sessions, `move/20261006T060534Z-next3-next2-64630`).

## 1. Every concurrency bound in the lane

| # | Mechanism | Where | Scope | Bound | Memory-derived? |
|---|---|---|---|---|---|
| 1 | Launchd poller tick starts the batch (`lrp_move_kick`) | `lr-reset-poller.sh:273-301` | global, one poller | a request waits for the next tick start; kickstart without `-k` is a no-op mid-tick | no |
| 2 | `move-admit.lock` (mkdir + pid/lstart) | `lr-move-batch.sh:112-124`, released `:182` | global, across batches | one batch in the admit section; a waiter gives up after `LR_MOVE_ADMIT_WAIT_S` 90 s and refuses its **whole** batch | no |
| 3 | Kernel-safety read at admit | `lr-move-batch.sh:151-155` | once per batch | refusal = every driven row NOTMOVED, exit 2 | **yes** |
| 4 | Per-session claim `runs/by-sid/<sid>.active` | `lr-move-batch.sh:163`, `lr-lib.sh:657-700` | per sid | one actuator per session; a live holder = that row NOTMOVED `claim-held` | no |
| 5 | Fence / launch lock `locks/<sid>.launch` | `lr-move-worker.sh:88-92`, `lr-recon-fence.sh:361-425` | per sid | reconciler or a live launch-lock holder wins; row NOTMOVED | no |
| 6 | Idle wait on the shared census (`wait:*` rows only) | `lr-move-worker.sh:99-117`; census `lr-move-batch.sh:224-229` | per sid, one census per batch per 20 s | row waits up to `until_idle_s` for two `move` snapshots | no |
| 7 | **Swap-slot semaphore** `locks/swap-slots/slot-<i>` | `lr-move-lib.sh:180-215`, taken `lr-move-worker.sh:122`, released `:168` | **global**: all batches, and the reconciler's `BootSlots` (`lr_recon/admit.py:255-281`) | at most WIDTH moves between slot-take and first MOVED read; waiter polls every 2 s, gives up at `LR_MOVE_SLOT_WAIT_S` 600 s | **no** (static 4; see §2) |
| 8 | Kernel-safety read at slot acquire | `lr-move-worker.sh:128-135` | per session, while holding a slot | refusal = that row NOTMOVED, exit 3 | **yes** |
| 9 | Prove loop | `lr-move-worker.sh:158-178` | per session | 2 s poll, 300 s bound; slot freed at first MOVED read, verdict final after the same pid is read twice 5 s apart | no |
| 10 | Batch watch deadline | `lr-move-batch.sh:206` | per batch | `until_idle_s + 600 + 300 + 300` s; after it the runner stops watching, workers keep going | no |
| 11 | Kill switch `LR_MOVE_LANE=off` | `lr-move-batch.sh:107`, `lr-move-worker.sh:73` | global | everything NOTMOVED | no |

Nothing else in the three files limits fan-out: there is no `MAX_CONCURRENT`, no worker pool, no rate gap between spawns (READ: full read of all three files).

## 2. Key question 1 — how WIDTH is computed

It is not computed. It is the first of three static sources (READ):

| Source | Receipt | Reaches the worker when |
|---|---|---|
| `plan.json .slots` | `lr-move-worker.sh:50`; written by `bin/cc-lr:1248`, `:1314-1316` | the operator passes `cc-lr move --slots W`; validated only as a whole number (`bin/cc-lr:1268`), no upper cap |
| env `LR_MOVE_SLOTS` | `lr-move-worker.sh:50` | it is set in the **launchd poller's** environment. The worker is spawned poller -> batch -> worker, so a value exported in the operator's shell never arrives (INFERRED from the spawn chain) |
| literal `4` | `lr-move-worker.sh:50`; sanitiser `lr-move-lib.sh:183-185` (non-numeric -> 4, below 1 -> 1) | otherwise |

- `lr-move-batch.sh` never reads or sets the width (MEASURED: `grep -c -E 'WIDTH|slots' lr-move-batch.sh` = 0).
- No input is a memory, CPU, load or session-count reading.
- Stated rationale for 4 (READ, `lr-move-lib.sh:168-179`, `design-safety.md:293-305`, `:611-618`): the largest TUI-boot overlap ever observed is 4 (n=49 boots: 45 solo, 1 two-way, 2 three-way, 1 four-way; `capacity.verify.md:35`), and kitty RPC above 4 concurrent streams is unmeasured. Memory appears only as the third of three unknowns: transient at most W x 0.33 GB, i.e. 1.3 GB at W=4 and 5 GB at W=15.
- The design's adaptive width (AIMD from `swap-slots/durations.jsonl`: +2 after W clean releases, halve on a slow boot, floor 2, cap 12; `design-safety.md:298-301`) **is not built**: no file in the lane writes `durations.jsonl` (MEASURED: `grep -c -i -E 'durations\.jsonl|AIMD'` over the three files = 0). The code comment still says "default 4 until a canary measures a safe width" (`lr-move-lib.sh:179`).
- The semaphore has no queue order: each waiter retries `mkdir` every 2 s, so a late arrival can take a slot ahead of an earlier one (READ `lr-move-lib.sh:188-206`).
- Workers with different widths share one directory, each scanning `slot-1..slot-W`; the effective global bound is the largest width among live callers (INFERRED). The reconciler's limit starts at 6 on the same store, but it is off today (`recon.on` absent, MEASURED `ls`; `fence.log` says `reason=recon-off`).

## 3. Key question 2 — what the kernel-safety read measures

Both call sites run `lr_capacity_probe_corrected` with `CC_ADMIT_ACTIVE_TERM=off CC_ADMIT_LOAD_TERM=off CC_ADMIT_RESERVE_TERM=off`, which leaves two terms (READ; confirmed by the ledger rows' `"terms":"headroom,segments"`).

| Term | Inputs | Formula | Refuses when | Receipt |
|---|---|---|---|---|
| headroom | `vm_stat`: Pages free + speculative + inactive + purgeable, page size from the `vm_stat` header | pages x page size / 2^30 GB | below 4 GB (`CC_ADMIT_MIN_HEADROOM_GB`) | `capacity-admit.sh:212-225`, `:163`, `:1330`, `:1350` |
| segments | `sysctl vm.compressor_segment_limit`, `vm.compressor_segment_buffer_size`, `vm.swapusage` (used); `vm_stat` "Pages occupied by compressor" | 100 x (int(compressor pages / (buffer / page size)) + int(swap used bytes / buffer)) / limit | above 90 % (`LR_SEGMENT_PCT`, default 90; the gate's own default is 50) | `capacity-admit.sh:281-314`, `:1374-1393`; `lr-lib.sh:435-437` |

On refusal (READ):
- At admit: `refuse` writes `admit.json {admitted:false}`, every driven row gets NOTMOVED `batch refused: capacity: ...`, one summary mail, exit 2. No claim was taken yet (the read at `:151` precedes the claim loop at `:158`).
- At the worker: `finish NOTMOVED "capacity: ..."`, slot and claim released, exit 3. The session is untouched (this is before `/exit`).
- It is a **single sample with no retry**. The design said a failing term waits in the slot queue up to 600 s (`design-safety.md:238`) and scaled the floor as 4 GB + 0.35 GB x slots held (`:341`); the code does neither (flat 4 GB, terminal on first refusal).
- A probe charges no refusal budget and pages nobody (`capacity-admit.sh:1603-1607`); it appends one ledger row.
- Fail-open: capacity library unreachable -> "proceeding UNGATED", rc 0 (`lr-lib.sh:412-413`); an unreadable input is noted blind and admits (`capacity-admit.sh:1387-1389`).
- **No test exercises either refusal path**: the fixture exports `LR_MOVE_KERNEL_CHECK=off` (`tests/helpers/lr-move-fixture.sh:29`) and nothing turns it back on (MEASURED: `grep -rn LR_MOVE_KERNEL_CHECK tests scripts bin commands` = 3 hits, the fixture and the two call sites).

Measured values:

| When | Reclaimable (floor 4 GB) | Segments (ceiling 90 %) | Verdict | Receipt |
|---|---|---|---|---|
| batch admit, 06:07:04Z | 33.16 GB | 4.50 % | admit | `~/.claude/autonomy/idl.jsonl`, caller `lr-move-batch` (READ) |
| 4 workers, 06:07:07-08Z | 32.98-33.04 GB | 4.50 % | admit x4 | same, caller `lr-move-worker` |
| 3 workers, 06:09:55Z | 34.75 GB | 4.33 % | admit x3 | same |
| now | 21.78 GB | 4.08 % (66,500 of 1,629,609) | would admit | MEASURED: `vm_stat` (free 6102, speculative 3171, inactive 1417237, purgeable 601, compressor 126368, page 16384) and `sysctl -n vm.compressor_segment_limit vm.compressor_segment_buffer_size vm.swapusage` (1629609, 65536, used 2181.75M) |

- Move lane total: 8 probes, 8 admits, 0 refusals (MEASURED: `grep` + `jq` over the current `idl.jsonl`, which starts 2026-10-03T20:47:51Z).
- Where the "memory" belief plausibly comes from: the same ledger holds 12 `segments` refusals for `lr-handoff` (9) and `lr-fire-resume` (3), all on 2026-10-04 under the old 50 % ceiling, plus 8 `reserve-active` refusals the same day. On 2026-10-06 the `lr-*` callers show 0 refusals in 22 probes (MEASURED, same query).

## 4. Key question 3 — serial per batch versus per session

| Stage | Serial or parallel | Measured on the one batch (N=7) |
|---|---|---|
| request waits for a poller tick | serial, global | 89 s: request 06:05:34Z, a tick had started 06:05:16Z, next tick 06:07:03Z started the batch (`poller.log`) |
| admit section under the lock: router read (once, `--fresh` once on a miss), kernel read, N claims in a loop, one preseed per distinct cwd | serial per batch, and global across batches | under 4 s together with the fan-out: batch start 06:07:03Z, `admit.json` 06:07:04Z, first worker spawned 06:07:06.4Z |
| fan-out: one `detach` + claim re-stamp per row, in a loop | serial per batch, outside the lock | 1.83 s for 7 workers (spawn events 826.421 -> 828.251) |
| watch: one loop, 2 s poll; one `--switch-census` per 20 s while any `.waiting` file exists | serial per batch | no `wait:*` rows in this batch |
| W0 claim confirm, W1 fence, W2 idle wait, W3 slot + kernel read, W5 actuate, W6 prove, W8 result | parallel per session, except the slot | W0+W1 (spawned -> fenced) took 0.2-0.7 s per worker |
| close: fresh router read, then the prompt guard once per moved session in a loop, summary, one mail | serial per batch | 44 s (last result 06:13:33Z, `router.err` 06:14:03Z, `summary.json` 06:14:17Z) |

Where the 523 s (06:05:34Z -> 06:14:17Z) went: 89 s poller tick + 4 s admit and fan-out + 168 s wave 1 (4 sessions) + 218 s wave 2 (3 sessions) + 44 s close.

Per-session stage times from `<sid>.events.jsonl` (MEASURED, n=7):

| Wave | n | Slot wait | Slot hold (slot -> first MOVED read) | Actuator (`lr-handoff`) | Actuator return -> first MOVED read |
|---|---|---|---|---|---|
| 1 | 4 | 0.5-0.7 s | 166.5-168.1 s | 105.2-110.0 s | 56.8-61.4 s |
| 2 | 3 | 166.8-167.3 s | 110.8, 200.1, 207.5 s | 16.0-16.5 s | 94.6, 184.1, 190.9 s |

- Mean slot hold 169.7 s (n=7). Lane throughput at width 4 is therefore about 1.4 sessions per minute (INFERRED: 4 / 169.7 s).
- The slot is released only on a full MOVED verdict, P1-P7 (`lr-move-worker.sh:164-168`, `lr-move-lib.sh:148-153`). The design said "first P1+P5 read" (`design-safety.md:241`, `:290`). In all 7 sessions the first MOVED read came 1-8 s after the resume debt was marked `proven`, and that came 27-75 s (median 36 s) after the relaunched `claude` process had started (MEASURED: registry `lstart`, `resume-debt/meta/<sid>.json` event epochs and mtimes, `proof-first` events). So 27-75 s of each hold is spent after the new process already exists.
- Tail prediction (INFERRED): a waiter's 600 s clock starts when it begins waiting. With 4 servers and a 169.7 s mean hold, sessions 1-16 get a slot within 600 s and session 17 onward ends NOTMOVED `capacity: no swap slot freed in 600s (width 4)` (`lr-move-worker.sh:124`). The registry holds 30 rows now (MEASURED: `ls ~/.claude/cc-registry/*.json | wc -l`; some may be stale).
- That message shares the `capacity:` prefix with the memory refusal at `lr-move-worker.sh:133`, and `tests/lr-move-worker.bats:106` pins the prefix for the no-free-slot case. A queue timeout therefore reads as a capacity (memory) refusal.

## 5. Key question 4 — workers: up front or lazy, and what a waiter holds

- **Up front.** The fan-out loop starts one detached `lr-move-worker.sh` per claimed row immediately after admission (`lr-move-batch.sh:187-202`); all 7 were running within 1.83 s (MEASURED).
- A worker waiting for a slot holds:

| Held | While waiting for a slot? | Receipt |
|---|---|---|
| its per-session claim | yes, from admit to `finish` | `lr-move-batch.sh:163`, `:197`; `lr-move-worker.sh:64` |
| the launch lock | only when the fence verdict is "lapsed"; in this batch `lock=none` for every row | `lr-recon-fence.sh:391-395`; `<sid>.fence.log` |
| a swap slot | **no**: acquire is try-only, retried every 2 s | `lr-move-worker.sh:122-126` |
| a `.waiting` marker | only `wait:*` rows, and it is removed before the slot wait | `lr-move-worker.sh:101`, `:116` |
| one bash process | yes | plain `/bin/bash` RSS is 1,440 kB (MEASURED: `/bin/bash -c 'ps -o rss= -p $$'`); a worker with about 3,500 sourced lines is estimated at 3-5 MB (not measured, no worker was live) |
| the session itself | still alive in its pane, untouched | `lr-move-lib.sh:171-174` |

- Estimated cost of 40 waiters: under 200 MB (40 x 5 MB, estimate) against 21.78 GB reclaimable. Each waiter's poll costs roughly 30 short process spawns per 2 s when all four slots are held (INFERRED from counting the `mkdir`, `cat`, `ps`, `tr`, `sed` calls in `lr_swap_slot_acquire` and `lr_pidlock_live`); that is CPU, not memory.

## 6. Alternatives considered

- **"The kernel read is the bottleneck."** Rejected: 0 refusals in 8, and its cost is inside the 0.07-0.86 s between the `slot` and `actuate` events.
- **"The admit lock serialises the lane."** Rejected for a single batch: held under 4 s for N=7. It can matter only when several batches queue and a router `--fresh` read (about 30 s at close in this batch, from mtimes) runs inside it; the third waiter could then hit the 90 s refusal (INFERRED, not observed).
- **"Width 4 is memory-sized."** Rejected: the literal's documented basis is observed boot overlap and unmeasured kitty RPC; the memory transient at W=15 is 5 GB by the design's own figure, against 21.78-34.75 GB reclaimable.
- **"Raising the width is free."** Not supported either. Wave 1 (4-way) spent 105-110 s in the actuator and wave 2 (3-way) 16 s. That is confounded with first-wave cold start and with 7 workers starting at once, but it is the only data point and it points the wrong way.

## 7. Uncertainties

- One batch, 7 sessions, all idle `move` rows, reconciler off. No `wait:*` row, no refusal and no width other than 4 has ever run in this lane.
- The cause of the 105-110 s versus 16 s actuator gap is not attributed; it lives in `lr-handoff.sh` (another slot's ground). Bundle timestamps show 68 s before the bundle existed in wave 1 and 1 s in wave 2.
- Two wave-2 sessions took 154 s from the `/exit` attempt to the new process (background-work dialog answered at 06:10:28Z and 06:10:40Z); that is recycle mechanics, not the lane.
- The 0.33 GB per-swap transient is the design record's figure (READ), not re-measured here.
- When P1 (the registry row) lands relative to process start was not measured, so the 27-75 s saving from an earlier slot release is an upper bound.
- Worker RSS is an estimate.

## 8. Incidental defect seen in the receipts (outside the objective)

`summary()` fails to parse on `/bin/bash` 3.2.57: `batch.log` shows `syntax error near unexpected token 'newline'` at the `case ... in plan.json|admit.json|...)` inside `$( ... )` (`lr-move-batch.sh:80-83`), so `summary.json` and the requester's mail said `verdicts: none` / "no rows" for a batch that was 7 of 7 MOVED. Reproduced in isolation (MEASURED): the same construct errors on this bash, and the leading-paren form `(plan.json|admit.json)` parses and returns the right value. The repo's own rule file names this class (`.claude/rules/agent-operating-lessons-situational.md:172`).

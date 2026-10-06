# q1d — which bound was binding, from the records of past runs

Date 2026-10-06. Read-only over `~/.reso/limit-recover/`, `~/.claude/autonomy/capacity-admit|capacity-fire`,
`~/.claude/logs/handoffs.jsonl`. Analysis script: `/tmp/lr_q1d_analyze.py` (prints sections A-F; re-runnable, writes nothing).
Tags: MEASURED = I ran the command; READ = source or record text; INFERRED = derived.

## Answer

Memory was not the binding bound in any record I could find for the move lane, and was binding in 2 of roughly 490 recover/switch
records. In the one multi-session move batch on disk (7 sessions), sessions that were not being moved were waiting on, in order of
seconds on the critical path: (1) the relaunched `claude` booting and being proven alive while the swap slot was still held
(60 s wave 1, 95-191 s wave 2), (2) the fixed slot width 4, which made 3 sessions wait 167 s each, (3) an 89 s wait for the launchd
poller tick to claim the batch request, (4) a 68 s stall at the start of `lr-handoff` in wave 1 only, cause not identified.
All 8 capacity logs are 0 bytes. In the recover lane the recorded waits are the `--one` lane cap of 2 (38 runs), the
active-session ceiling 8 (10 lines, a count of mid-turn sessions, not memory), account quota (292 WAIT, 81 parked rows), and
non-capacity failures (176 FAILED rows, 117 of them one transplant lock-mismatch refusal).

## 1. Inventory (MEASURED, `python3 /tmp/lr_q1d_analyze.py`, `ls`)

| Store | Count | Multi-session with real actuation |
|---|---|---|
| `move/` batch dirs | 1 (`20261006T060534Z-next3-next2-64630`); `move/requests/` empty | 1 (7 workers) |
| `fleet/` timestamped multi runs | 9 (2026-09-10 .. 09-20), 12-48 rows each | 0 of 9: rows are dry-run / skipped / parked; one run has 1 RECOVERED (`20260914T153119Z`, 22 rows, 343 s) |
| `fleet/manual-*` | 1 | 0 rows; 1 FAILED event (active ceiling) |
| `fleet/one-*` | 480, of which 284 actuated (recycle/spawn/nudge row) | single-session each; overlap computed below |
| `runs/` | only `by-sid/` claim files (71 entries) | n/a |
| `fleet-drive-ledger.jsonl` | 471 bytes, last written 2026-09-10 | stale, not used |

So "recent multi-session batches" is a sample of n=1 move batch plus cohorts of overlapping `one-*` runs. Every claim below about
the move lane rests on that single batch.

## 2. The 7-session batch `20261006T060534Z-next3-next2-64630`: timeline (all UTC)

Sources: `<sid>.events.jsonl` (ms), `<sid>/bundle-*/events.jsonl` (s), `~/.claude/logs/handoffs.jsonl` rows for this batch,
`poller.log`, `plan.json`, `summary.json`, `batch.log`. Event decode: `lr-move-worker.sh:120-171`.

Plan: 9 rows, 7 `move`, 2 held before any work (`hold:mid-turn` pane 8 sid 4e9949e0 idle 593 s; `hold:being-recovered` pane 11
sid 4ad354fc). Result: 7 of 7 MOVED, `conjuncts 1111111`.

```
06:05:34  plan.json written (request)                          |
06:07:03  poller TICK start; MOVE-BATCH started pid 73895      | 89 s: request waits for the launchd tick
06:07:04  admit.json ("router: ranked")                        |   (previous tick started 06:05:16, 18 s before the request)
06:07:06-08  7 workers spawned, claimed, fenced (< 2 s each)

          WAVE 1: panes 2,3,4,12 (slots 1-4)                   WAVE 2: panes 14,15,16
06:07:07  slot taken (wait 0.5-0.7 s); kernel read passes      slot-wait "width 4" begins
06:07:08  actuate (lr-handoff starts)                          .
   ...    68 s with no record: lr-handoff before bundle mkdir  .   waiting for a slot
06:08:16  bundle dir created (lr-handoff.sh:969)               .   (167 s each, 504 session-seconds = 29 %
06:08:18-28  placed, precheck (10 s), "gate-exempt: swap"      .    of the batch's 1751 worker-seconds)
06:08:29  transplant ok                                        .
06:08:37  recycle-intent; 06:08:40 watcher armed; /exit        .
06:08:55  actuated rc 0                                        .
06:09:16-25  launcher runs in pane (shell prompt after 12-13 s).
06:09:18-30  READY                                             .
06:09:51-53  recycle-engaged ("alive 15s past boot")           .
06:09:55.1  proof-first -> slot released                       06:09:55.5-.6 slot taken (0.4 s after release)
06:10:02  result MOVED (wall 176 s each)                       06:09:56 bundle (1 s, not 68 s); 06:10:02 precheck done
                                                               06:10:11 actuated rc 0 (16 s in lr-handoff)
                                                               06:10:30 pane 14 launcher runs; READY 06:10:34
                                                               06:10:28/40 panes 15,16: background-work dialog answered
                                                               06:11:43 pane 14 engaged; proof 06:11:46; MOVED 06:11:53
                                                               06:12:38 panes 15,16 launcher finally runs (2 m 31 s after
                                                                        watcher armed; watcher logged INDETERMINATE:boot at 120 s)
                                                               06:13:12 panes 15,16 engaged; proof 06:13:15 / 06:13:23
06:13:33  last result MOVED (pane 15, wall 386 s)
06:14:17  batch.log "done: no rows"; summary wall_s 434
```

Per-session seconds (MEASURED, script section A):

| sid | pane | slot wait | slot -> actuated | actuated -> proof-first | proof -> result | total |
|---|---|---|---|---|---|---|
| 7f5deb68 | 2 | 0.5 | 108.6 | 59.4 | 7.6 | 176.4 |
| 1c0f7f90 | 3 | 0.6 | 110.7 | 56.8 | 7.7 | 176.3 |
| 893204d3 | 4 | 0.7 | 105.6 | 61.4 | 7.6 | 176.2 |
| 840ca76c | 12 | 0.6 | 109.8 | 56.8 | 7.7 | 175.7 |
| 4d059264 | 14 | 167.3 | 16.2 | 94.6 | 7.6 | 286.5 |
| deaa242a | 15 | 167.2 | 16.6 | 190.9 | 10.0 | 385.2 |
| 404651b1 | 16 | 166.8 | 16.1 | 184.1 | 7.5 | 375.0 |

- Shape: neither serial nor 2-wide. Two waves, 4 then 3. Peak slot-held = 4, peak in `lr-handoff` = 4, peak workers alive = 7. MEASURED.
- Where 1751 worker-seconds went: boot/proof wait 704 s (40 %), slot wait 504 s (29 %), inside `lr-handoff` 484 s (28 %, of which
  about 272 s is the wave-1 68 s stall x4), stability re-read 56 s (3 %). MEASURED (sums of the table).
- Request to last MOVED = 479 s; to batch done = 523 s (the "about 9 minutes"). Critical path: 89 s tick wait + 3 s spawn +
  169 s wave 1 + 208 s wave 2 + 10 s final stability read; then 44 s more until `batch.log` says done. MEASURED.
- The slot is held from `slot` to the first MOVED verdict (`lr-move-worker.sh:168`), so it covers the whole relaunch boot. Wave 2
  started 0.4 s after wave 1's first proof, which shows the slot width was the only thing wave 2 was waiting on. MEASURED.
- With width >= 7 and nothing else changed, the last result would have landed about 167 s earlier (479 -> about 312 s). INFERRED.

What filled the gaps, by evidence strength:

| Gap | Seconds | Cause | Tag |
|---|---|---|---|
| Request -> batch start | 89 | request is claimed only on a poller tick (`poller.log` 06:07:03 `MOVE-BATCH started`) | READ |
| Wave 2 slot wait | 167 x 3 | `slot-wait "width 4"`, default `LR_MOVE_SLOTS:-4` (`lr-move-worker.sh:50`, `lr-move-lib.sh:179` "default 4 until a canary measures a safe width") | READ + MEASURED |
| Wave 1, actuate -> bundle mkdir | 68 x 4 | not identified. Wave 2 did the same step in 1 s. Concurrent `lr-fleet --one 4ad354fc` started 06:07:04 and wrote `rank.timing` only at 06:08:22, so something machine-wide or shared delayed all five until about 06:08:16; `poller.log` shows `LOCK-REAP rc=124` (a timeout) at 06:07:41 in the same window | INFERRED (cause unknown) |
| /exit -> launcher running | 36-45 (wave 1), 23 (pane 14), 151 (panes 15,16) | panes 15,16 raised the background-work dialog (`recycle-bgwork-stopped-watcher` rows); the typed relaunch did not start for about 2.5 min | READ; why the typed command sat is not identified |
| Launcher READY -> engaged | 33 (wave 1), 69 (pane 14), 33 (15,16) | engagement-by-process needs `--resume` "alive 15s past boot", plus boot | READ |
| proof-first -> result | 7.5-10 | `LR_MOVE_STABLE_S:-5` second read + 2 s poll | READ |

Defect seen in the record (READ `batch.log`, MEASURED `bash -n`): `lr-move-batch.sh: command substitution: line 84: syntax error
near unexpected token 'newline'` followed by `done: no rows`; `summary.json` says `"verdicts":"none"` although 7 verdict files say
MOVED. The repo file is byte-identical to the installed one (`cmp`), `bash -n` passes, but `/bin/bash` is 3.2.57 and
`lr-move-batch.sh:80-83` puts a `case ... pattern) ... ;;` inside `$(...)`, which bash 3.2 mis-parses at run time.

## 3. Capacity logs and memory refusals, over all records

| Evidence | Count | Tag |
|---|---|---|
| `*capacity.log` under `move/` | 8 files (7 per-session + 1 batch), 8 of 8 are 0 bytes | MEASURED `find ... -name '*capacity*' -size 0` |
| Move kernel-safety read (`lr-move-worker.sh:128-134`) refusals | 0 of 7 | MEASURED |
| `~/.claude/autonomy/capacity-fire/{active,headroom,load,segments}.refusals` | all 4 are 0 bytes (mtime 2026-10-06 01:26 local) | MEASURED `ls -la` |
| `~/.claude/autonomy/capacity-admit/*.refusals` | 136 files, 7 non-empty, sum 9 refusals; 5 are `lr-fire-resume.*` (2026-09-19, 09-22 x2, 10-01 x2) | MEASURED |
| Distinct `capacity-admit: REFUSING` lines in 2858 scanned record files | 5: 3 active ceiling, 1 expired admission token, 1 compressor segments | MEASURED script section E |
| `capacity not admitted yet` (probe would refuse) in fleet logs | 6 runs (09-30 x1, 10-01 x4, 10-02 x1); 9 lines: 8 active ceiling, 1 compressor segments | MEASURED `grep` |

Memory-term refusals found, total 2 (READ):

- `fleet/one-20261002T043358Z-fe370fb2/detached.log`: `compressor segments 54.27% of limit (884350 of 1629609) > ceiling 50%` (a
  probe; waited 20 s).
- `switch/d425afab-bg-20261004T225159Z/events.jsonl` 2026-10-04T22:53:31Z: `compressor segments 65.02% of limit (1059623 of
  1629609) > ceiling 50% (refusal 1 of 3 ...)`, then 25 s later `ADMIT (budget expired after 3 consecutive refusals)` at 65.35 %.

Both are the 50 % recover/switch ceiling. The move lane reads the same term at 90 % (`LR_SEGMENT_PCT=90`,
`lr-move-worker.sh:147`) and neither value would have refused there. No `headroom` (free-memory floor) refusal exists anywhere
in the records. The most common "capacity" refusal is `N sessions mid-turn + ... > active ceiling 8`, which counts busy sessions.

## 4. Reason strings with counts

Move batch (n=7 workers, 9 plan rows): NOTMOVED 0. Held at plan time 2: `hold:mid-turn` "busy now; --until-idle S waits for it"
(1), `hold:being-recovered` "already being recovered by this command" (1). Capacity 0, slot timeout 0. READ `plan.json`.

Recover lane, `fleet/*/results.tsv` (489 files, 757 rows; MEASURED script sections C, D):

| Class | Rows | Quoted reason |
|---|---|---|
| FAILED | 176 | 138 x `lr-handoff rc=2`, 33 x rc=6; underlying: 117 x `lr-transplant: REFUSED (lock-mismatch) — the lock names PATH as the owner, not PATH`, 15 x `REFUSED (stub-beside-retired)`, 36 mentions `REFUSED:not-limited` |
| cwd gone | 130 | `CWD-GONE — ... no longer exists; a resume cannot be spawned there` |
| not owed | 112 | `TEAMMATE` (101), `TRANSPLANTED→nextN` (11) |
| dry-run | 85 | |
| no target / quota | 81 | `no routable target: router: ... weekly-exhausted; ... kmax-concurrency; ... recovery-weekly-thin`, `claude-accounts: --max-wait expired mid-sweep` (14), `next is still at its limit; nothing typed` (9) |
| RECOVERED | 68 | 54 recycle-in-place, 8 spawn, 6 nudge |
| PARTIAL | 17 | `transplanted but the relaunch did not verify — source is a tombstoned husk` |
| HELD (background shells / composer / busy) | 24 | `HELD:bg-work` 9, `HELD:unknown` 6, `HELD:draft` 4, `HELD:unreachable` 2, `HELD:pane` 1, `HELD:composer-unreadable` 1, `HELD:busy` 1; all "held before anything moved (lr-handoff rc 6) — the session is untouched" |
| parked for capacity | 7 | bare `capacity`, all 2026-09-10 .. 09-19, none in the 17 days since; `lr-fleet.sh:553` notes this row was written with an empty reason after 120 s |
| parked for slot | 0 | `the --one lane is at its concurrency cap` row never written; but see waits below |
| held by another actuator | 4 in `results/*.json` | `busy: another run holds .../runs/by-sid/SID.active`; plus poller `RUN-CLAIM-HELD` 13, `REQUEST-IN-FLIGHT` 9 |

Waits that did not end in a park (MEASURED `grep -l`):

- `lr-fleet: the --one lane is at its cap (2 live recoveries); waiting up to 900s for a slot`: 38 runs (10-01: 19, 10-02: 3,
  10-04: 15, 10-06: 1). The 10-01 cohort launched 10 `one-*` runs in 4 s (20:21:17-21Z) and they finished after 223-824 s.
- Actuated `one-*` runs: wall p50 21 s, p90 427 s (n=284); RECOVERED only: p50 74 s, p90 674 s, max 2028 s (n=67).

Poller (`poller.log`, 1846 ticks, tick interval p50 637 s, p90 875 s; MEASURED): `WAIT ... still capped, retry next tick` 292;
`HOOK-HELD ... autorecover.on is absent` 838; `CAP ... total-ceiling (N) reached; deferred to next tick` 48; `CONSOLIDATED 24 ready
→ 0 winner(s) (max 1/worktree, 4 total)`; `UPGRADE-DEFER` 6. Ticks that dispatched a recovery: 40, of which 28 dispatched 1,
5 dispatched 2, 7 dispatched 3-5.

## 5. Alternatives considered

- "Memory forced the width down": rejected for the move lane on this record (0 of 7 kernel reads refused, 0-byte logs); the width
  4 is a static default, not a measured response.
- "Work is serial": rejected; peak 4 concurrent handoffs.
- "The 68 s stall is memory pressure (swap thrash)": not excluded. No memory sample exists for 06:07-06:08; the kernel read
  passed at 06:07:07 and again at 06:09:55 under a 90 % ceiling, which bounds segments but says nothing about latency.
- "Slot wait is the largest term": only second; boot/proof wait is larger (704 s vs 504 s) and sits inside the slot hold.

## 6. Uncertainties

- n=1 move batch. Widths above 4 have never run; nothing here measures memory at width 7.
- Cause of the wave-1 68 s stall and of the 151 s typed-relaunch delay on panes 15,16 is not identified.
- The recover-lane overlap figure (peak 10) counts processes alive, including those queued on the lane cap of 2.
- Handoff and watcher logs carry no timestamps; phase times come from bundle `events.jsonl`, file mtimes and `handoffs.jsonl`.
- `capacity-admit/*.refusals` are counters without reasons; 4 of the 9 counted refusals (`boot-resume-launch` 3,
  `cc-resume-layout` 1) belong to other tools and were not decoded.

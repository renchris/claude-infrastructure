# G — `cc-lr move`: intent expiry, admit-lock contention, claim collisions (2026-10-17/18)

Scope: the 17 batch dirs `~/.reso/limit-recover/move/2026101[78]T*`, `poller.log`, and the lane sources at
worktree HEAD 2b9d938de. The deployed copies under `~/.claude/scripts/limit-recover/` and `~/.claude/bin/cc-lr`
resolve to the main checkout (c33e5c0b2), and `diff -q` shows no difference from this worktree for
lr-move-batch.sh, lr-intent.sh, lr-lib.sh, lr-move-worker.sh, lr-handoff.sh, lr-move-lib.sh, lr-reset-poller.sh or cc-lr.
The TTL line (`bin/cc-lr:1484`) and the admit-budget line (`lr-move-batch.sh:136`) have not changed since d46327fd2
(2026-10-04), so the cited code is the code every batch here ran. The system was live while I read it, and
rows marked "running" are as of a snapshot taken about 02:13-02:21Z on 2026-10-18.
Helpers: `/tmp/lri-g/extract.py` and `/tmp/lri-g/tables.py`, both read-only.
Measured = read from files with `stat -f %Fm`, `jq`, `grep poller.log` or `ps -o etime`. Estimated = inferred, with the method stated.

## 0. Numbers first

| class | count (measured) | net effect |
|---|---|---|
| Intent refused as expired | **7 rows**, 3 batches: 6 at `lr-handoff.sh:649` (`REFUSED:intent-invalid`, 48 s / 88 s / 902-904 s late) and 1 at the precheck `handoff-fire.sh:12924`, which is reported as `REFUSED:not-limited` | 0 moved. Every one held a claim and a swap slot first |
| Rows whose intent had **already expired when the poller started the batch** | **10 driven rows** in 4 batches (84451, 31080, 1739, 69593). The margin at start was −624 s to −3340 s | All of them are doomed by construction. They still took 8 claims and started 8 workers (measured from workers.tsv) |
| Batches refused at admission ("another batch held the admit section for 90s") | **2 of 5** parallel single-sid batches (69995, 69998) | Their 90-iteration budget ran **599-600 s of wall time**, not 90 s |
| Two batches inside the admit section at once | **1 event** (31080 and 1739, 01:51:45-01:52:12Z) | Got there through the "dead process" steal at `lr-move-batch.sh:132-133` while every holder was alive |
| Claim-held NOTMOVED rows | **10** (31080: 1, 69593: 1, 22836: 7, 23285: 1) | **8 of 10** were rows with a *valid* intent, lost to a holder whose intent had expired before its own batch started. **10 of 10 holders** were workers with an intent that had expired before start |
| Collision chains settled net-zero | **5** (4 holders refused intent-invalid, 1 holder ended still-busy) | **3** more holder workers (pids 38260, 42086, 99147) were still alive at about 02:17Z, 26-27 min old (measured with `ps -o etime`). They cover 5 claim-held rows and can only end NOTMOVED |
| Request → `MOVE-BATCH started` | median 348 s, range 5-5124 s, over 17 batches | 5 batches waited 1650-5124 s behind one poller tick that ran 00:23:59 → 01:50:07Z (86 min) |

## 1. Intent TTL

### 1.1 The check and what it compares

- **Writer.** `bin/cc-lr:1470` sets `now=$(date +%s)` when the plan is written. Then `bin/cc-lr:1484` sets
  `expires_epoch = now + until_idle_s + 900`. The clock therefore starts when the operator *types the command*, not when the lane starts work.
- **Validator.** `scripts/limit-recover/lr-intent.sh:62-67` reads `exp = .expires_epoch` and `now = date +%s`.
  `[ "$exp" -le "$now" ]` produces `expired: the intent expired $((now-exp))s ago; re-run cc-lr move`.
- **Callers.** There are only two, and both run *after* the claim, the slot and the kernel read are held:
  1. `lr-handoff.sh:636-657`, which calls `lr_intent_check` at `:649`. A failure gives `REFUSED:intent-invalid`, rc 6 (`:653-655`).
     The worker starts it at W5 (`lr-move-worker.sh:160-172`), i.e. after W0 claim `:81-87`, W2 wait `:102-120`
     and W3 slot `:139-146`.
  2. `handoff-fire.sh:12920-12928`, the `--probe-recycle-preconditions` limit gate, which `lr-handoff.sh:1397-1406` passes `--operator-intent` to.
     When this check fails, the refusal is labelled `REFUSED:not-limited`. The expiry shows only in the precheck line.
- **Not checked.** `lr-move-batch.sh:180` tests only `[ ! -f "$BDIR/intent/$sid.json" ]` (existence) before
  `lr_claim_take` at `:181`. The worker never reads the intent before W5. An intent that has already expired therefore gets the
  admit section, a claim, a preseed, a worker, a full idle wait and a swap slot before anything notices.

### 1.2 Every expiry occurrence in scope (measured: `grep "expired" */*.handoff.log`, result JSONs)

| batch | sid | until | intent expires | actuate (events) | reported | where | why the clock ran out |
|---|---|---|---|---|---|---|---|
| 20261017T073813Z…26358 | 76033be2 | 0 | 07:53:13 | 07:54:00 | expired 48 s ago → `REFUSED:intent-invalid` | lr-handoff.sh:649 | request→start 348 s, then slot-wait 07:44:51→07:53:56 (545 s) behind the 4 slot holders, whose handoffs ran 9-22 min (3 `HELD:unreachable`, 1 STRANDED). It got slot 30c3a88d freed at 07:53:55 |
| 20261017T073813Z…26358 | 1bf14662 | 0 | 07:53:13 | 07:54:37 | expired 88 s ago → `REFUSED:intent-invalid` | lr-handoff.sh:649 | same pattern; slot-wait 07:44:55→07:54:15 (560 s); got the slot f7351f3b freed at 07:54:14 |
| 20261018T002357Z…40187 | e739e5b5 | 0 | 00:38:57 | 00:26:57 (valid by 720 s) | precheck `expired 1106s ago` → verdict **`REFUSED:not-limited`** | handoff-fire.sh:12924 | lr-handoff ran 1910 s (actuate 00:26:57 → actuated 00:58:47). Its precheck read the intent at about 00:57:23, 30 min after the first check passed |
| 20261018T005330Z…69593 | 246a91b5 | 1800 | 01:38:30 | 01:53:25 | expired 902 s ago | lr-handoff.sh:649 | **expired 701 s before the poller started the batch** (01:50:11) |
| 20261018T005330Z…69593 | 8db0e6f1 | 1800 | 01:38:30 | 01:53:30 | expired 904 s ago | lr-handoff.sh:649 | same |
| 20261018T005330Z…69593 | e3dedc17 | 1800 | 01:38:30 | 01:53:29 | expired 904 s ago | lr-handoff.sh:649 | same |
| 20261018T005330Z…69593 | 2e9ed9f2 | 1800 | 01:38:30 | 01:53:29 | expired 904 s ago | lr-handoff.sh:649 | same |

For context, outside the brief's glob: the 2026-10-11 batches 163706Z and 163727Z have 8 more handoff logs that mention expiry
(measured with `grep -l expired 20261011T*/*.handoff.log`, 273-398 s late).

The 69593 workers refused 4-8 s after actuate (01:53:33-35) but did not write a result until 01:55:05-13. That is
measured from events.jsonl `actuated` → `result`. So four doomed workers held **all 4 swap slots** for 107-116 s. During that time
22836's three valid move rows (43e6eb4b, e739e5b5, 7b50757e) sat in slot-wait 01:53:53 → 01:55:07-16, and 23285's
1bf14662 sat in slot-wait 01:54:43 → 01:55:16.

### 1.3 Every intent: expiry against batch start and against actuate

Measured with `/tmp/lri-g/tables.py`. "exp-start" is expires_epoch minus the poller's `MOVE-BATCH started` time; a negative value means the intent was dead
before the batch existed. "act-exp" greater than 0 means the row actuated after expiry. "act-admit" is actuate minus the admit.json ts.

| batch | sid | pane | disp | until | req | expires | poller start | exp-start s | admit | actuate | act-exp s | act-admit s | verdict |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| …073813Z…26358 | f7351f3b | 1 | move | 0 | 07:38:13 | 07:53:13 | 07:44:01 | 552 | 07:44:31 | 07:44:57 | -496 | 26 | NOTMOVED HELD:unreachable |
| …073813Z…26358 | ab512c88 | 3 | move | 0 | 07:38:13 | 07:53:13 | 07:44:01 | 552 | 07:44:31 | 07:45:00 | -493 | 29 | NOTMOVED HELD:unreachable |
| …073813Z…26358 | 9f6593c5 | 7 | move | 0 | 07:38:13 | 07:53:13 | 07:44:01 | 552 | 07:44:31 | 07:45:01 | -492 | 30 | STRANDED |
| …073813Z…26358 | 76033be2 | 19 | move | 0 | 07:38:13 | 07:53:13 | 07:44:01 | 552 | 07:44:31 | 07:54:00 | **47** | 569 | NOTMOVED intent-invalid |
| …073813Z…26358 | 30c3a88d | 27 | move | 0 | 07:38:13 | 07:53:13 | 07:44:01 | 552 | 07:44:31 | 07:45:03 | -490 | 32 | NOTMOVED HELD:unreachable |
| …073813Z…26358 | 1bf14662 | 33 | move | 0 | 07:38:13 | 07:53:13 | 07:44:01 | 552 | 07:44:31 | 07:54:37 | **84** | 606 | NOTMOVED intent-invalid |
| …235745Z…69993 | 6db28068 | 342 | wait:bg-job | 3600 | 23:57:45 | 01:12:45 | 23:57:54 | 4491 | 23:59:32 | - | - | - | NOTMOVED still-busy |
| …235745Z…69995 | 756b68c8 | 340 | wait:subagents | 3600 | 23:57:45 | 01:12:45 | 23:57:55 | 4490 | 00:07:54 (refused) | - | - | - | NOTMOVED batch refused (admit) |
| …235745Z…69998 | 7b50757e | 47 | move | 0 | 23:57:45 | 00:12:45 | 23:57:56 | 889 | 00:07:56 (refused) | - | - | - | NOTMOVED batch refused (admit) |
| …235745Z…70005 | 509e3aad | 28 | wait:bg-job | 3600 | 23:57:45 | 01:12:45 | 23:58:04 | 4481 | 00:08:08 | - | - | - | NOTMOVED still-busy |
| …235746Z…69994 | 4736324c | 21 | wait:bg-job | 3600 | 23:57:46 | 01:12:46 | 23:58:12 | 4474 | 00:05:28 | - | - | - | NOTMOVED still-busy |
| …000816Z…49288 | 43e6eb4b | 8 | move | 0 | 00:08:16 | 00:23:16 | 00:17:12 | 364 | 00:17:18 | 00:17:36 | -340 | 18 | NOTMOVED HELD:unreachable |
| …000922Z…71757 | 7b50757e | 47 | move | 3600 | 00:09:22 | 01:24:22 | 00:17:13 | 4029 | 00:17:25 | 00:17:36 | -4006 | 11 | NOTMOVED HELD:unreachable |
| …002357Z…40187 | e739e5b5 | 20 | move | 0 | 00:23:57 | 00:38:57 | 00:24:20 | 877 | 00:25:29 | 00:26:57 | -720 | 88 | NOTMOVED REFUSED:not-limited (precheck intent expired, §1.2) |
| …002443Z…84451 | 756b68c8 | 340 | wait:subagents | 3600 | 00:24:43 | 01:39:43 | 01:50:07 | **-624** | 01:50:24 | - | - | - | running (doomed) |
| …003928Z…31080 | 381200c5 | 25 | move | 0 | 00:39:28 | 00:54:28 | 01:50:08 | **-3340** | 01:52:10 | - | - | - | NOTMOVED claim-held |
| …004329Z…1739 | ab512c88 | 3 | wait:bg-job | 900 | 00:43:29 | 01:13:29 | 01:50:10 | **-2201** | 01:52:10 | - | - | - | NOTMOVED still-busy:unread |
| …005330Z…69593 | 246a91b5 | 1 | move | 1800 | 00:53:30 | 01:38:30 | 01:50:11 | **-701** | 01:50:50 | 01:53:25 | 895 | 155 | NOTMOVED intent-invalid |
| …005330Z…69593 | 04b3cbc3 | 10 | wait:bg-job | 1800 | 00:53:30 | 01:38:30 | 01:50:11 | **-701** | 01:50:50 | - | - | - | running (doomed) |
| …005330Z…69593 | 8db0e6f1 | 24 | move | 1800 | 00:53:30 | 01:38:30 | 01:50:11 | **-701** | 01:50:50 | 01:53:30 | 900 | 160 | NOTMOVED intent-invalid |
| …005330Z…69593 | 381200c5 | 25 | wait:mid-turn | 1800 | 00:53:30 | 01:38:30 | 01:50:11 | **-701** | 01:50:50 | - | - | - | running (doomed) |
| …005330Z…69593 | e3dedc17 | 201 | move | 1800 | 00:53:30 | 01:38:30 | 01:50:11 | **-701** | 01:50:50 | 01:53:29 | 899 | 159 | NOTMOVED intent-invalid |
| …005330Z…69593 | 2e9ed9f2 | 332 | move | 1800 | 00:53:30 | 01:38:30 | 01:50:11 | **-701** | 01:50:50 | 01:53:29 | 899 | 159 | NOTMOVED intent-invalid |
| …005330Z…69593 | 756b68c8 | 340 | wait:subagents | 1800 | 00:53:30 | 01:38:30 | 01:50:11 | **-701** | 01:50:50 | - | - | - | NOTMOVED claim-held |
| …012244Z…22836 | 246a91b5 | 1 | move | 8134 | 01:22:44 | 03:53:18 | 01:50:14 | 7384 | 01:52:47 | - | - | - | NOTMOVED claim-held |
| …012244Z…22836 | 43e6eb4b | 8 | move | 8134 | 01:22:44 | 03:53:18 | 01:50:14 | 7384 | 01:52:47 | 01:55:24 | -7074 | 157 | NOTMOVED HELD:load |
| …012244Z…22836 | 04b3cbc3 | 10 | wait:bg-job | 8134 | 01:22:44 | 03:53:18 | 01:50:14 | 7384 | 01:52:47 | - | - | - | NOTMOVED claim-held |
| …012244Z…22836 | e739e5b5 | 20 | move | 8134 | 01:22:44 | 03:53:18 | 01:50:14 | 7384 | 01:52:47 | 01:55:21 | -7077 | 154 | STRANDED |
| …012244Z…22836 | 4736324c | 21 | wait:bg-job | 8134 | 01:22:44 | 03:53:18 | 01:50:14 | 7384 | 01:52:47 | - | - | - | running |
| …012244Z…22836 | 8db0e6f1 | 24 | move | 8134 | 01:22:44 | 03:53:18 | 01:50:14 | 7384 | 01:52:47 | - | - | - | NOTMOVED claim-held |
| …012244Z…22836 | 381200c5 | 25 | move | 8134 | 01:22:44 | 03:53:18 | 01:50:14 | 7384 | 01:52:47 | - | - | - | NOTMOVED claim-held |
| …012244Z…22836 | 509e3aad | 28 | wait:bg-job | 8134 | 01:22:44 | 03:53:18 | 01:50:14 | 7384 | 01:52:47 | - | - | - | running |
| …012244Z…22836 | 7b50757e | 47 | move | 8134 | 01:22:44 | 03:53:18 | 01:50:14 | 7384 | 01:52:47 | 01:55:20 | -7078 | 153 | NOTMOVED HELD:load |
| …012244Z…22836 | e3dedc17 | 201 | move | 8134 | 01:22:44 | 03:53:18 | 01:50:14 | 7384 | 01:52:47 | - | - | - | NOTMOVED claim-held |
| …012244Z…22836 | 2e9ed9f2 | 332 | move | 8134 | 01:22:44 | 03:53:18 | 01:50:14 | 7384 | 01:52:47 | - | - | - | NOTMOVED claim-held |
| …012244Z…22836 | 756b68c8 | 340 | wait:subagents | 8134 | 01:22:44 | 03:53:18 | 01:50:14 | 7384 | 01:52:47 | - | - | - | NOTMOVED claim-held |
| …012244Z…22836 | 6db28068 | 342 | wait:bg-job | 8134 | 01:22:44 | 03:53:18 | 01:50:14 | 7384 | 01:52:47 | - | - | - | running |
| …014908Z…23285 | ab512c88 | 3 | move | 8134 | 01:49:08 | 04:19:42 | 01:50:16 | 8966 | 01:53:49 | - | - | - | NOTMOVED claim-held |
| …014908Z…23285 | 76033be2 | 19 | move | 8134 | 01:49:08 | 04:19:42 | 01:50:16 | 8966 | 01:53:49 | - | - | - | NOTMOVED slot-wait 600 s |
| …014908Z…23285 | 30c3a88d | 27 | move | 8134 | 01:49:08 | 04:19:42 | 01:50:16 | 8966 | 01:53:49 | 01:59:58 | -8384 | 369 | NOTMOVED HELD:unknown |
| …014908Z…23285 | 1bf14662 | 33 | move | 8134 | 01:49:08 | 04:19:42 | 01:50:16 | 8966 | 01:53:49 | 01:55:31 | -8651 | 102 | NOTMOVED HELD:draft |
| …020022Z…2123 | 246a91b5 | 1 | move | 5400 | 02:00:22 | 03:45:22 | 02:11:38 | 5624 | 02:12:15 | 02:12:59 | -5543 | 44 | STRANDED (at 02:20Z) |
| …020022Z…2123 | 8db0e6f1 | 24 | move | 5400 | 02:00:22 | 03:45:22 | 02:11:38 | 5624 | 02:12:15 | 02:12:59 | -5543 | 44 | running |
| …020022Z…2123 | e3dedc17 | 201 | move | 5400 | 02:00:22 | 03:45:22 | 02:11:38 | 5624 | 02:12:15 | 02:13:02 | -5540 | 47 | running |
| …020022Z…2123 | 2e9ed9f2 | 332 | move | 5400 | 02:00:22 | 03:45:22 | 02:11:38 | 5624 | 02:12:15 | 02:19:15 | -5167 | 420 | running |
| …021322Z…22546 | 43e6eb4b | 8 | move | 4799 | 02:13:22 | 03:48:21 | 02:13:27 | 5694 | 02:13:47 | 02:15:08 | -5593 | 81 | running |
| …021322Z…22546 | 7b50757e | 47 | wait:composer-unknown | 4799 | 02:13:22 | 03:48:21 | 02:13:27 | 5694 | 02:13:47 | - | - | - | running |

**What the table says.**
- Across all 23 actuated rows, **act − admit has a maximum of 606 s** (26358's 1bf14662, almost all of it slot wait). act − req reached 3600 s.
  If the same `until + 900` budget were measured from admission, **the 6 refusals at `lr-handoff.sh:649` would all have passed**: the 69593
  rows at 155-160 s and the 26358 rows at 569-606 s, against 900 s. The seventh would not. e739e5b5's second check, at the precheck, came
  ≈1826 s after actuate (≈1914 s after admit), so an admit anchor alone does not cover a check made mid-handoff. See §4(a)(3).
- With `until=0` the budget is 900 s. It has to cover poller latency, measured at 5-5124 s (median 348 s), plus the admit section (6-604 s measured
  start→admit), plus slot wait, which is bounded at `LR_MOVE_SLOT_WAIT_S=600` (`lr-move-worker.sh:140`). 600 s of slot wait alone leaves 300 s
  for everything else, and the median poller latency already uses 348 s.
- **Where the large latency comes from (measured, `grep "TICK start\|MOVE-BATCH" poller.log`).** The poller kicks the lane at tick start
  (`lr-reset-poller.sh:358`) and at tick end (`:241-246`). The tick that began at 00:23:59 next kicked at 01:50:07, 86 min later.
  `cc-lr move` re-sends `kickstart` every 15 s (`bin/cc-lr:1513-1517`), but launchd drops a kickstart sent while a tick is running (`lr-reset-poller.sh:233-237`).
  Six requests (00:24:43 → 01:49:08) were started together at 01:50:07-16, **oldest first**, because
  `for q in "$root"/requests/*.json` (`:337`) expands in sorted order and batch ids begin with the request time.
  Load that evening was 515 → 438 on 10 cores (commit 560cf51f7).

## 2. Admit section

### 2.1 Per-batch admit table

Steps are bracketed by mtimes, measured with `stat -f %Fm`:
- `capacity.log` is 0 bytes for every batch, so its mtime marks the **start** of the capacity probe, which is the end of the router read.
- `admit.json` marks the end of the probe.
- The last `<sid>.claim.log` marks the end of the claims.
- `preseed.log` marks the end of the preseed, which is about when `unlock` runs (`lr-move-batch.sh:200`).
- `router.err` is rewritten by the CLOSE re-read (`:259`), so its mtime is admit-time only for batches still running. In those it sits 0.04-0.39 s before `capacity.log`.
- "lock taken" for a waiter is estimated as the previous holder's preseed end.

| batch (rows) | req → poller start | poller start | lock taken | router read | capacity | claims (n) | preseed (cwds) | lock held | start → admit | outcome |
|---|---|---|---|---|---|---|---|---|---|---|
| 073813Z…26358 (6) | 348 s | 07:44:01 | ≈07:44:01 | ≤30.0 s (incl. init) | 0.3 s | 0.35 s (6) | 2.6 s (5) | ≈33 s | 30 s | admitted |
| 235745Z…69993 (1) | 9 s | 23:57:54 | ≈23:57:54 (first) | **≤97.3 s** (incl. init) | 0.9 s | 0.01 s | **21.5 s** (1) | ≈120 s | 98 s | admitted |
| 235746Z…69994 (1) | 26 s | 23:58:12 | ≈23:59:54 (est.) | **≈323 s, two reads** (rc 3, then `--fresh` ranked) | 11.5 s | 0.9 s | 18.3 s (1) | ≈354 s | 436 s | admitted |
| 235745Z…70005 (1) | 19 s | 23:58:04 | ≈00:05:48 (est.) | **≈132 s** | 9.8 s | 0.24 s | 23.1 s (1) | ≈165 s | 604 s | admitted |
| 235745Z…69995 (1) | 10 s | 23:57:55 | never | - | - | - | - | - | 599 s | **refused 00:07:54** |
| 235745Z…69998 (1) | 11 s | 23:57:56 | never | - | - | - | - | - | 600 s | **refused 00:07:56** |
| 000816Z…49288 (1) | 536 s | 00:17:12 | ≈00:17:12 | ≤5.9 s | 0.3 s | 0.1 s | 1.2 s (1) | ≈7.6 s | 6 s | admitted |
| 000922Z…71757 (1) | 471 s | 00:17:13 | ≈00:17:19.6 | ≈5.0 s | 0.5 s | 0.03 s | 1.0 s (1) | ≈6.6 s | 12 s | admitted |
| 002357Z…40187 (1) | 23 s | 00:24:20 | ≈00:24:20 | ≤66 s (incl. init) | 3.4 s | 0.09 s | 3.9 s (1) | ≈73 s | 69 s | admitted |
| 002443Z…84451 (1) | 5124 s | 01:50:07 | ≈01:50:07 | ≤16.7 s | 0.8 s | 0.07 s | 1.7 s (1) | ≈19 s | 17 s | admitted |
| 005330Z…69593 (7) | 3401 s | 01:50:11 | ≈01:50:26.3 | ≈21.8 s | 3.1 s | **14.3 s (7)** | **29.9 s (3)** | ≈70 s | 39 s | admitted |
| 003928Z…31080 (1) | 4240 s | 01:50:08 | ≈01:51:36-45 | ≈25-34 s | 1.0 s | 0.8 s (held) | none | to ≈01:52:12 | 122 s | admitted **concurrently with 1739** |
| 004329Z…1739 (1) | 4001 s | 01:50:10 | **01:51:45 "dead process; taking it"** | ≈25 s | 1.0 s | 0.12 s | 21.1 s (1) | to ≈01:52:32 | 120 s | admitted **concurrently with 31080** |
| 012244Z…22836 (13) | 1650 s | 01:50:14 | ≈01:52:32.3 | ≈13.5 s | 1.3 s | 10.9 s (13) | 16.2 s (5) | ≈42 s | 153 s | admitted |
| 014908Z…23285 (4) | 68 s | 01:50:16 | ≈01:53:14.6 | ≈33 s | 2.5 s | 0.7 s (4) | 11.5 s (2) | ≈48 s | 213 s | admitted |
| 020022Z…2123 (4) | 676 s | 02:11:38 | ≈02:11:38 | ≤35.5 s | 1.8 s | 1.5 s (4) | 7.5 s (2) | ≈46 s | 37 s | admitted |
| 021322Z…22546 (2) | 5 s | 02:13:27 | ≈02:13:27 | ≤19.2 s | 0.6 s | 1.0 s (2) | 6.9 s (2) | ≈28 s | 20 s | admitted |

**The slow steps**, in order:
1. **The router read** (`lr-move-batch.sh:145-160`, `claude-accounts --rank general`): 5-132 s for one read, about 323 s when
   the first read fails and the `--fresh` retry at `:160` runs. The design comment at `:7` describes the section as "seconds long", but the 23:57 group measured 97-354 s.
2. **Preseed**: 18-30 s per batch in the loaded windows, even when every cwd logged "trust + upsell gates already set"
   (`:190-199`, one `lr-preseed-env.sh` per distinct cwd).
3. **Claims**: about 2 s per row under load (69593: 14.3 s for 7), sequential at `:177-189`.
4. **Capacity probe**: 0.3-11.5 s (`:168-172`).

Side finding, which is also the evidence that 69994 made two router reads: its admit.json says
`"target_auth":"ok","reason":"router: the router could not answer (rc 3)"`. `ROUTE_WHY` is cleared only once (`:144`), and
`route_read` returns 0 without resetting it (`:151`), so the first read's failure text survives a successful `--fresh` retry into `admit_json` (`:174`).

### 2.2 Why 5 parallel single-sid batches made 2 refuse (23:57:45Z, all requested by pane 344)

- **The section is serial and every batch pays for its own router read.** The lock was busy from about 23:57:54 to 00:08:33 (≈639 s) for
  three one-row batches: 69993 ≈120 s, then 69994 ≈354 s with two router reads, then 70005 ≈165 s. The estimate comes from the mtimes in 2.1.
- **The budget counts loop iterations, not seconds.** `lr-move-batch.sh:130-138` is
  `until mkdir; … t=$((t+1)); [ "$t" -lt 90 ] || refuse "…for 90s"; sleep 1; done`. Each iteration also forks `mkdir`, and
  `lr_pidlock_live` forks `cat`, `tr|sed` and `ps|tr|sed` (`lr-lib.sh:796-806`). 69995 refused 599 s after it started and 69998 after 600 s
  (measured, poller start → admit.json ts). That is **about 6.6 s per iteration**, so "90s" in the refusal text was 600 s of wall time.
- **Release order is a race, not a queue.** When 69993 released (≈23:59:54) and when 69994 released (≈00:05:48), the next
  holder was whichever waiter's 1-6 s poll reached `mkdir` first. 69994 won the first race and 70005 the second. 69995 and 69998 lost both
  and ran out at 00:07:54 and 00:07:56, while 70005 was still inside (until ≈00:08:33).
- **Outcome.** The two refused rows were re-requested as separate batches: 7b50757e as 71757 at 00:09:22, 756b68c8 as 84451 at 00:24:43.
  84451 then sat behind the 86-min tick until its intent had expired (§1.3, −624 s).

### 2.3 The double admission (01:51:45-01:52:12Z)

- 1739's batch.log has `01:51:45Z … move-admit lock held by a dead process; taking it`. That message comes from the steal arm at
  `lr-move-batch.sh:132-133`. At that moment every batch runner was alive: each wrote files afterwards, for example 69593's
  workers.tsv at 01:52:07 and 31080's admit.json at 01:52:11.
- 31080 and 1739 then both ran the capacity probe (capacity.log 01:52:10.053 and 01:52:10.088) and both wrote admit.json at 01:52:11.062.
- **Mechanism (estimated, from the code).**
  - `:132` reads the pid file **twice at two different moments**: inside `lr_pidlock_live`, then again in `$(cat "$ALOCK/pid")`.
    A reader that sees no pid during the holder's `unlock` (`:140`: `rm -f pid lstart; rmdir`) and then sees the *next* holder's freshly
    written pid passes the "evidence" test and steals.
  - `:133` then deletes whatever lock is there now, without a rename-and-verify. Compare `lr_claim_take` at `lr-lib.sh:866-873`
    and `lr_swap_slot_acquire` at `lr-move-lib.sh:198`, which both rename before deleting.
  - 23285's batch.log shows the same window being hit: `lr-lib.sh: line 802: …/move-admit.lock/lstart: No such file or directory`.
    In that case the pid had been read and lstart was already gone; it took the benign path.

## 3. Claim collisions

The claim holder for a pid comes from `workers.tsv` (pid ↔ batch ↔ sid) and the live `runs/by-sid/<sid>.active/holder`. That file names
`"by":"lr-move-worker (<batch>)"`; the batch runner restamps it at `lr-move-batch.sh:220` (`lr_claim_restamp`, `lr-lib.sh:883-887`).
Every claim-held row came from `lr_claim_take` returning `held-live` (`lr-lib.sh:846-847`). The batch writes `result NOTMOVED "claim-held: …"` at `lr-move-batch.sh:185`.

| loser batch (intent valid?) | sid | holder pid → batch | holder's intent at its batch start | holder's final verdict | chain |
|---|---|---|---|---|---|
| 22836 (valid to 03:53:18) | 246a91b5 | 38052 → 69593 | expired −701 s | NOTMOVED intent-invalid, 902 s (01:55:13) | **net zero** |
| 22836 (valid) | 8db0e6f1 | 38577 → 69593 | expired −701 s | NOTMOVED intent-invalid, 904 s (01:55:05) | **net zero** |
| 22836 (valid) | e3dedc17 | 45363 → 69593 | expired −701 s | NOTMOVED intent-invalid, 904 s (01:55:13) | **net zero** |
| 22836 (valid) | 2e9ed9f2 | 45965 → 69593 | expired −701 s | NOTMOVED intent-invalid, 904 s (01:55:05) | **net zero** |
| 22836 (valid) | 04b3cbc3 | 38260 → 69593 (wait row) | expired −701 s | running, 26 min old at about 02:17Z. Ends still-busy at about 02:21:55 (T0+1800) or intent-invalid | doomed |
| 22836 (valid) | 381200c5 | 42086 → 69593 (wait row) | expired −701 s | running. Ends at about 02:22:06 or intent-invalid | doomed |
| 22836 (valid) | 756b68c8 | 99147 → 84451 (wait row) | expired −624 s | running, 27 min old. Wait deadline about 02:50:30 (T0+3600) | doomed |
| 23285 (valid to 04:19:42) | ab512c88 | 61594 → 1739 (wait row) | expired −2201 s | NOTMOVED still-busy:unread after 900 s (02:07:41) | **net zero** |
| 69593 (itself expired) | 756b68c8 | 99147 → 84451 | expired −624 s | (as above) | moot: both sides doomed |
| 31080 (itself expired, −3340 s) | 381200c5 | 42086 → 69593 | expired −701 s | (as above) | moot: both sides doomed |

**Counts (measured):** 10 claim-held rows. 8 had valid intents. All 10 holders were workers whose intent had expired before their batch
started. 5 chains are net zero. 3 holder workers covering 5 rows were still alive at about 02:17Z. Not a collision: 69593's 8db0e6f1 claim
log reads `stolen-dead-holder pid=74528`, a dead foreign holder that was taken over correctly.

**How it happened.** 22836 (01:22:44) was an account-wide re-run of `--from next4`. When it was planned no claims were held: the earlier
batches' workers had finished by 01:14, and 69593 had not yet started. So its plan had 13 movable rows. The poller then started all six queued
batches within 9 s, oldest first (`lr-reset-poller.sh:337`), and the admit lock let them in roughly in that order. Every overlap was therefore
resolved in favour of the **stalest** intent, which by then had expired.

**Re-run cost.** The operator re-requested the 4 net-zero move rows as batch 2123 at 02:00:22. The poller started it at 02:11:38 and the rows
actuated at 02:12:59-02:19:15, **50-57 min after 22836's request** for the same rows.

**The doomed holders also block plans.** At plan time the hold check (`bin/cc-lr:1237-1246`) reads them as `hold:in-flight`:
2123 holds 04b3cbc3 (pid 38260) and 756b68c8 (pid 99147), and 22546 holds 756b68c8 (pid 99147), measured from plan.json. That makes 3 more
rows held behind workers that cannot move anything.

## 4. Recommendations

### (a) Intent TTL derivation

1. **Fail fast at admission.** At `lr-move-batch.sh:180`, replace the existence test with `lr_intent_check` from `lr-intent.sh:29`,
   using the row's own account and `$TO`, **before** `lr_claim_take` at `:181`. An expired row then becomes
   `NOTMOVED intent-expired-before-start (<N>s; queued <M>s)` with no claim, no preseed and no worker. On this data that alone means:
   - the 8 valid-intent rows lost to claim-held would have found no holder;
   - the other 2 claim-held rows (31080 and 69593's 756b68c8, both expired themselves) would have been reported as intent-expired;
   - none of the 8 doomed workers, the 3 plan-time `hold:in-flight` rows or the 4 doomed slot holds of 01:53:17-01:55:13 would have happened.
2. **Measure the act budget from admission, not from typing.**
   - Today the clock is `bin/cc-lr:1470` `now` + `:1484` `until_s + 900`. Keep `expires_epoch` as a **start-by** bound: how long a queued
     request still reflects the operator's will. It is checked at admit in (1).
   - Add an act-by bound anchored at admission. At `:174`/`:181`, lr-move-batch.sh writes `intent/<sid>.admitted` (0600) holding its admit epoch, in the
     0700 dir `bin/cc-lr:1471` created. That keeps the trust boundary `lr-intent.sh:13-17` relies on, because only the lane writes there.
   - `lr-intent.sh:62-67` would then compare `now` against `admitted + until_idle_s + LR_MOVE_SLOT_WAIT_S + margin` when that file
     exists. Measured: act − admit ≤ 606 s for all 23 actuated rows, against act − req of up to 3600 s.
3. **Refresh at claim and check in the worker.**
   - Read the intent at W0, right after `lr-move-worker.sh:88`, and alongside every `aborted` test (`:108`, `:142`, `:156`). An intent that
     expires mid-wait then releases the claim and the slot at once, instead of at W5.
   - Cap the W2 wait deadline (`:106`, `deadline=$((T0+UNTIL))`) at `act_by − LR_MOVE_SLOT_WAIT_S`, so a wait row cannot outlive its own intent.
   - For e739e5b5's case (the precheck at `handoff-fire.sh:12924` ran 30 min after the `lr-handoff.sh:649` check), the probe should either
     trust lr-handoff's admission or name the expiry. Today it reports `REFUSED:not-limited`, which hides the cause.

### (b) One batch for many named sids, in priority order

- **Today a batch can select by `--from A`, or by exactly one `--sid`/`--pane`.**
  - `bin/cc-lr:1400` overwrites `selv` on each `--sid`.
  - `cl_move_sid_unique` (`:1298-1307`, called at `:1437`/`:1444`) checks one value.
  - `cl_move_rows` (`:1176-1183`) passes one selector to `lr-upgrade.sh --switch-census`, which keeps a single `_sel`
    (`lr-upgrade.sh:3351-3352`) and filters on one prefix (`:1023-1024`, `:1095-1096`).
  - So N named sessions means N batches, N router reads and N waits on the global section. That is exactly the 23:57 group: 5 batches, 3 router reads totalling about 550 s, 2 refusals.
- **What `--sids a,b,c` (or repeatable `--sid`) needs:**
  1. In cc-lr, accumulate an ordered list and run `cl_move_sid_unique` once per prefix.
  2. Add `_sel="sids:a,b,c"` in lr-upgrade with a per-prefix `case` at `:1023-1024`/`:1095-1096`. The census still runs once.
  3. In `cl_move_rows`, sort its output rows by the list index, so `plan.json .rows` is in priority order.
  4. If mixed waits are wanted, carry `until_idle_s` per row. Today it is plan-level (`bin/cc-lr:1475`) and the worker reads only the plan value (`lr-move-worker.sh:49`).
- **Order is kept, and then lost.** The batch keeps plan order for claims (`lr-move-batch.sh:177-189`) and for worker spawn (`:205-225`).
  But `lr_swap_slot_acquire` (`lr-move-lib.sh:182-207`) is a free-for-all poll every 2 s, so priority is lost at W3. Keeping it needs a
  per-batch ticket: worker *i* tries for a slot only after every lower-index row of its batch has a slot or a result.
- The admit section stays one per batch: one router read, one capacity probe, a claim per row, a preseed per cwd. The data in 2.1 puts the per-row cost at about 2 s.
- The two admit-lock defects in §2.2-2.3 remain for any concurrent batches:
  - the budget at `:136` counts iterations; it should compare `$(date +%s)` against a deadline.
  - the steal at `:132-133` reads the pid twice and deletes in place; it should use the rename-and-verify pattern from `lr-lib.sh:866-873`.

### (c) Supersede, not collide

**What happens today:**
- A newer batch that meets a live claim records the row NOTMOVED (`lr-move-batch.sh:184-186`), whatever state the holder is in.
- Workers do have a per-batch stop: `cc-lr move --abort <batch>` (`bin/cc-lr:1417-1423`) writes `<batch>/abort`, and the worker checks it at
  `lr-move-worker.sh:108` (W2), `:142` (W3) and `:156`. The last of those is the final check before `ev actuate` (`:160`) and the lr-handoff
  start (`:163`). From `:163` on, the pane can be `/exit`ed: that is the point of no return.

**A safe protocol:**
1. **Identify the holder.** At `lr-move-batch.sh:184`, on `held-live`, read the holder's `by` from `runs/by-sid/<sid>.active/holder`
   (written by `lr_claim_stamp`, `lr-lib.sh:819-825`). Supersede only if:
   - `by` is `lr-move-worker (<B_old>)`, so the lane never supersedes lr-fleet, the reconciler or a drain;
   - `B_old` sorts before this batch. Batch ids carry the request time (`bin/cc-lr:1470`), so the newer intent wins and an older batch never displaces a newer one;
   - `<B_old>/<sid>.events.jsonl` has no `actuate` stage.
   If B_old's intent is already expired, the holder can never actuate (`lr-handoff.sh:649` refuses before planning), so it is always safe to supersede.
2. **Signal; never take the claim directly.**
   - Write `<B_old>/<sid>.superseded` naming the new batch.
   - Extend `aborted()` (`lr-move-worker.sh:97`) to `[ -e "$BDIR/abort" ] || [ -e "$BDIR/$SID.superseded" ]`, with its own reason:
     `NOTMOVED superseded by <batch>; nothing touched`.
   - The old worker releases its claim and slot in `finish()` (`:55-70`; release at `:65` and `:67`). The old worker stays the only thing that releases its claim.
3. **Do not wait inside the global section.**
   - Mark the row `pending-supersede` and spawn the new worker with a flag that makes W0 (`lr-move-worker.sh:81-87`) call `lr_claim_take`
     itself, bounded by a timeout, instead of waiting 15 s for a restamp.
   - Size the bound from the measured finish latency: rc 6 → result took 90-100 s under load (69593), so roughly 180 s.
   - On timeout: `NOTMOVED claim-held: <B_old> worker passed actuate`.
4. **Why this is safe.**
   - The claim is a `mkdir`, so at most one worker holds it.
   - The old worker gives it up only through `finish()`.
   - A marker written after the old worker's last check at `:156` is simply never seen. The old worker actuates under its claim, and the new
     worker times out as NOTMOVED.
   - So two actuators can never run on one session. The marker check needs no lock: losing the race costs a NOTMOVED, never a double move.

On this data, (a)(1) alone settles every chain in §3, because every holder was expired-at-start. (c) covers the case that remains: an older,
still-valid waiting worker being overtaken by a newer operator request.

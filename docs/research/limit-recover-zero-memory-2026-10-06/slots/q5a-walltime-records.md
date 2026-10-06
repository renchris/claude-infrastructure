# q5a — wall time of one rotation, split by step, from past-run records

Date 2026-10-06. Read-only. Script: `/tmp/lr_walltime.py` (python3, stdlib only); its full output: `/tmp/lr_walltime.out`.
Tags: MEASURED = computed by the script or a command I ran; READ = source or record text; INFERRED = my reading.

## 0. Answer

- The move lane has exactly ONE recorded batch (`ls ~/.reso/limit-recover/move` -> `20261006T060534Z-next3-next2-64630`, `requests`), 7 sessions, all MOVED. Every move-lane number below has n=7 from one batch. MEASURED.
- Per-session wall (worker spawned -> verdict): median 176 s, p90 375 s, max 385 s (n=7). MEASURED.
- No memory step costs time: the kernel-safety read (slot -> actuate) is 0.07-0.86 s (n=7) and all 7 `*.capacity.log` are 0 bytes (admitted, no refusal). MEASURED.
- Median rotation is dominated by an unexplained 69-70 s stall at the head of `lr-handoff.sh` (40% of 176 s), seen in the 4 first-wave sessions only. p90 rotation is dominated by the width-4 slot wait (167 s, 43% of 385 s), then by the typed relaunch line sitting unread by the pane's shell (133-134 s, 35%).
- Operator-visible batch time was 523 s (request 06:05:34 -> summary 06:14:17): 89 s waiting for the next launchd poller tick, 3 s admit/preseed/spawn, 387 s workers, 44 s post-batch. Effective parallelism inside the worker window: 3.2x (1243 s of slot->result work in 387 s), against a slot width of 4 and 7 sessions.
- Across the wider corpus (34 in-place recycles joined from 194 bundles, lanes mixed), the largest median step is "watcher detached -> launcher running in the pane" at 43 s (p90 81 s, max 166 s), i.e. /exit, claude exit, shell back, shell reads the typed line.

## 1. Sources and how each step is timed

| step | from -> to | source | resolution |
|---|---|---|---|
| claim | `spawned` -> `claimed` | `<sid>.events.jsonl` t_ms (lr-move-worker.sh:70,85) | ms |
| fence | `claimed` -> `fenced` | same (:93) | ms |
| idle wait | `fenced` -> `slot-wait` | same (:99-120); no `wait:*` row in this batch, so this is only the gap | ms |
| slot wait | `slot-wait` -> `slot` | same (:120-127), poll 2 s | ms |
| capacity read | `slot` -> `actuate` | same (:128-140) | ms |
| handoff head | `actuate` -> bundle `placed` event | events.jsonl + `<sid>/bundle-*/events.jsonl` (bundle TS is taken at lr-handoff.sh:968) | 1 s |
| precheck | `placed` -> handoff `admitted` | bundle events.jsonl | 1 s |
| transplant + arm | `admitted` -> `recycle-intent` row | `~/.claude/logs/handoffs.jsonl` | 1 s |
| detach | `recycle-intent` -> watcher `lstart` | `<sid>.watcher.json` | 1 s |
| exit (to shell probe) | watcher start -> "CONFIRMED at a shell prompt after Ns" | `$TMPDIR/handoff-recycle-<pane>-<epoch>-*.log` | 1 s |
| shell wait | shell probe + typed -> shell executes the line | `~/.zsh_history` extended timestamp of the `: hfv-<watcherpid>-...` line | 1 s |
| launcher prelude | shell ran line -> first `lr-fire-resume.sh` event | bundle events.jsonl | 1 s |
| relaunch | `relaunch-typed` (claude spawned) -> `READY` | bundle events.jsonl | 1 s |
| engagement proof (watcher) | `READY` -> `recycle-engaged` row | handoffs.jsonl | 1 s |
| engagement proof (worker) | `recycle-engaged` -> `proof-first` -> `result` | events.jsonl (lr-move-worker.sh:160-177) | ms |

`handoff.log` carries no per-line timestamps; only embedded epochs (recycle log name, `resume:<sid>:<epoch>`, bundle name) were usable. READ.

## 2. Batch 20261006T060534Z-next3-next2-64630 — full per-session step table (seconds)

MEASURED by `python3 /tmp/lr_walltime.py`. `dlg` = the /exit raised the background-work dialog, answered by the watcher at 15 s.

| sid | bg | claim | fence | idle wait | slot wait | capacity read | handoff head | precheck | transplant+arm | detach | exit->shell probe | probe->shell runs line | launcher prelude | spawn->READY | READY->engaged row | engaged->proof-first | proof hold | TOTAL | lr-handoff wall |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 7f5deb68 | - | 0.07 | 0.08 | 0.05 | 0.46 | 0.86 | 70 | 10 | 9 | 3 | 13 | 22 | 1 | 2 | 33 | 4 | 8 | 176 | 108 |
| 1c0f7f90 | - | 0.05 | 0.18 | 0.22 | 0.60 | 0.66 | 70 | 10 | 9 | 3 | 12 | 24 | 0 | 5 | 31 | 3 | 8 | 176 | 110 |
| 893204d3 | - | 0.29 | 0.42 | 0.24 | 0.67 | 0.33 | 69 | 10 | 9 | 3 | 12 | 33 | 0 | 5 | 23 | 2 | 8 | 176 | 105 |
| 840ca76c | - | 0.31 | 0.32 | 0.22 | 0.57 | 0.33 | 69 | 10 | 9 | 4 | 12 | 32 | 0 | 5 | 23 | 2 | 8 | 176 | 109 |
| 4d059264 | - | 0.28 | 0.36 | 0.14 | 167 | 0.07 | 1 | 5 | 3 | 2 | 9 | 13 | 1 | 4 | 69 | 3 | 8 | 287 | 16 |
| deaa242a | dlg | 0.18 | 0.26 | 0.04 | 167 | 0.08 | 1 | 5 | 3 | 2 | 16 | 133 | 2 | 5 | 28 | 11 | 10 | 385 | 17 |
| 404651b1 | dlg | 0.26 | 0.17 | 0.14 | 167 | 0.08 | 1 | 5 | 3 | 2 | 17 | 134 | 0 | 4 | 29 | 4 | 7 | 375 | 16 |

Absolute UTC marks (same run):

| sid | spawned | slot | actuate | bundle placed | admitted | recycle-intent | watcher | shell probe | shell ran line | fire-resume 1st | READY | engaged row | proof-first | result |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 7f5deb68 | 06:07:06 | 06:07:07 | 06:07:07 | 06:08:18 | 06:08:28 | 06:08:37 | 06:08:40 | 06:08:53 | 06:09:15 | 06:09:16 | 06:09:18 | 06:09:51 | 06:09:55 | 06:10:02 |
| 1c0f7f90 | 06:07:06 | 06:07:07 | 06:07:08 | 06:08:18 | 06:08:28 | 06:08:37 | 06:08:40 | 06:08:52 | 06:09:16 | 06:09:16 | 06:09:21 | 06:09:52 | 06:09:55 | 06:10:02 |
| 893204d3 | 06:07:06 | 06:07:08 | 06:07:08 | 06:08:18 | 06:08:28 | 06:08:37 | 06:08:40 | 06:08:52 | 06:09:25 | 06:09:25 | 06:09:30 | 06:09:53 | 06:09:55 | 06:10:02 |
| 840ca76c | 06:07:07 | 06:07:08 | 06:07:08 | 06:08:18 | 06:08:28 | 06:08:37 | 06:08:41 | 06:08:53 | 06:09:25 | 06:09:25 | 06:09:30 | 06:09:53 | 06:09:55 | 06:10:02 |
| 4d059264 | 06:07:07 | 06:09:55 | 06:09:55 | 06:09:57 | 06:10:02 | 06:10:05 | 06:10:07 | 06:10:16 | 06:10:29 | 06:10:30 | 06:10:34 | 06:11:43 | 06:11:46 | 06:11:53 |
| deaa242a | 06:07:07 | 06:09:55 | 06:09:55 | 06:09:57 | 06:10:02 | 06:10:05 | 06:10:07 | 06:10:23 | 06:12:36 | 06:12:38 | 06:12:44 | 06:13:12 | 06:13:23 | 06:13:33 |
| 404651b1 | 06:07:08 | 06:09:55 | 06:09:55 | 06:09:57 | 06:10:02 | 06:10:05 | 06:10:07 | 06:10:24 | 06:12:38 | 06:12:38 | 06:12:43 | 06:13:12 | 06:13:15 | 06:13:23 |

Reading the table:

- Two waves. Wave 1 = 4 sessions (slot width 4, `"detail":"width 4"` in every events.jsonl), wave 2 = 3 sessions that got a slot at 06:09:55.5-55.6, the instant wave 1's first proof released the slots (lr-move-worker.sh:168). MEASURED.
- All four wave-1 `proof-first` marks fall inside 116 ms (t_ms 1791266995057..5173) although their READY marks span 12 s (06:09:18..06:09:30). The proof is quantized by something shared, not by each session's own boot. MEASURED; cause not read.
- The same `lr-handoff.sh` code took 105-110 s in wave 1 and 16-17 s in wave 2 (`actuate` -> `actuated`). The difference is the handoff head (69-70 s vs 1 s), plus precheck 10 s vs 5 s and recycle gates `gates@4-6s ... detach@10-11s` vs `gates@1s ... detach@4s` (handoffs.jsonl `phases`). MEASURED.
- All four wave-1 bundles carry the same second in their name (`bundle-20261006T060816Z`, grep count 8 = 4 sessions x 2 mentions): four processes with transcripts of 1.7-3.6 MB left the head in the same second. That is the signature of a shared wait, not of per-session work. MEASURED the coincidence; cause INFERRED, unresolved.
- Wave 1 overlapped a launchd poller tick (`poller.log`: `06:07:03 TICK start`, `06:07:04 REQUEST 4ad354fc ... dispatching the in-place recovery DETACHED`, `06:07:26 RESUME-DEBT`, `06:07:41 LOCK-REAP rc=124`). Wave 2 (06:09:55) did not start on a tick boundary. INFERRED as the likeliest contention source; not proven.
- "probe -> shell runs line": the watcher logs `pane N CONFIRMED at a shell prompt after 9-17s — typing relaunch`, and zsh's own history timestamp for that typed line is 13-134 s later. `lr-fire-resume.sh` then emits its first event 0-2 s after zsh starts the line, so the launcher is not the slow part; the pane's shell was not yet reading input. The two `dlg` sessions (background-work dialog answered "Exit and stop tasks") are the 133-134 s cases; the watcher raised `INDETERMINATE:boot — no claude on /dev/ttys031, no relaunch.rc ... 71s after the relaunch was typed` for one and `120s` for the other. MEASURED the gap; what holds the tty between the probe and the shell's read is not in any record. READ the log lines.
- 4d059264's READY -> engaged row is 69 s against 23-33 s for the other six. The watcher's proof is "alive 15s past boot" (handoffs.jsonl detail), so 8-18 s of each is polling/boot detection and 15 s is a fixed wait. MEASURED the durations; the 69 s outlier is unexplained.

## 3. Per-step statistics

### 3a. Move lane (n = 7 sessions, 1 batch) — MEASURED

| step | n | median s | p90 s | max s | sum s |
|---|---|---|---|---|---|
| claim | 7 | 0.3 | 0.3 | 0.3 | 1 |
| fence | 7 | 0.3 | 0.4 | 0.4 | 2 |
| idle wait | 7 | 0.1 | 0.2 | 0.2 | 1 |
| slot wait | 7 | 0.7 | 167.2 | 167.3 | 504 |
| capacity read | 7 | 0.3 | 0.7 | 0.9 | 2 |
| handoff head (before bundle) | 7 | 69.2 | 69.8 | 70.1 | 282 |
| precheck | 7 | 10.0 | 10.0 | 10.0 | 55 |
| transplant + arm | 7 | 9.0 | 9.0 | 9.0 | 45 |
| detach | 7 | 3.0 | 3.0 | 4.0 | 19 |
| exit -> shell probe | 7 | 12.0 | 16.0 | 17.0 | 91 |
| shell probe -> shell runs line | 7 | 32.0 | 133.0 | 134.0 | 391 |
| launcher prelude | 7 | 0.0 | 1.0 | 2.0 | 4 |
| relaunch (spawn -> READY) | 7 | 5.0 | 5.0 | 5.0 | 30 |
| engagement proof, watcher (READY -> engaged row) | 7 | 29.0 | 33.0 | 69.0 | 236 |
| engagement proof, worker (engaged row -> proof-first) | 7 | 3.3 | 4.2 | 11.2 | 30 |
| proof hold (proof-first -> result) | 7 | 7.6 | 7.7 | 10.0 | 56 |
| TOTAL spawned -> result | 7 | 176.4 | 375.0 | 385.2 | 1751 |

Share of the 1751 session-seconds: slot wait 29%, shell wait 22%, handoff head 16%, watcher proof 13%, exit 5%, proof hold 3%, precheck 3%, transplant+arm 3%, everything else under 2% each. Claim + fence + idle + capacity read together: 6 s of 1751 (0.3%). MEASURED.

The medians above are of a bimodal sample (4 sessions near 70 s and 3 near 1 s for the handoff head; 4 near 0.6 s and 3 at 167 s for the slot wait). With n=7 from one batch they describe this batch, not a distribution.

### 3b. In-place recycles of every lane, `~/.claude/logs/handoffs.jsonl` — MEASURED

Ledger span 2026-10-03T08:18Z..2026-10-06T06:27Z; `recycle-engaged` rows n=49 (none under_test). `elapsed_s` and `phases` are the recycle's own fields.

| step | n | median s | p90 s | max s |
|---|---|---|---|---|
| recycle start -> watcher detached | 49 | 11 | 30 | 58 |
| of which gates | 49 | 1 | 6 | 22 |
| of which self-id -> intent | 49 | 3 | 15 | 40 |
| of which tty -> detach | 49 | 4 | 8 | 20 |
| detach -> engaged (exit, shell, relaunch, boot, proof) | 49 | 71 | 343 | 2191 |
| total, all | 49 | 82 | 346 | 2249 |
| total, engaged by a real assistant turn | 33 | 77 | 131 | 235 |
| total, no-prompt process proof (the 7 moves) | 7 | 83 | 189 | 189 |
| total, "answering within 180 s" oracle | 9 | 368 | 1985 | 2249 |
| detach -> prompt submitted (prompted recycles) | 17 | 55 | 101 | 196 |
| prompt submitted -> first assistant turn | 17 | 7 | 14 | 27 |

### 3c. Bundle `events.jsonl` joined to an engaged in-place recycle — MEASURED

194 bundles carry events.jsonl; 34 join to a `recycle-engaged` row (same sid, engaged within 900 s of the bundle timestamp). Lanes are mixed (recover pool, switch, move).

| step | n | median s | p90 s | max s |
|---|---|---|---|---|
| bundle ts -> handoff admitted (audit, precheck, focus probe) | 29 | 12 | 50 | 159 |
| admitted -> watcher detached (transplant, launcher build, recycle gates) | 29 | 5 | 22 | 140 |
| watcher detached -> launcher running in pane | 29 | 43 | 81 | 166 |
| watcher detached -> shell ran the typed line (zsh history) | 34 | 42 | 80 | 164 |
| launcher running -> claude spawned | 29 | 1 | 1 | 3 |
| claude spawned -> ready signal / composer painted | 29 | 5 | 7 | 10 |
| claude spawned -> engaged row, real assistant turn | 16 | 23 | 57 | 105 |
| claude spawned -> engaged row, no-prompt process proof | 7 | 33 | 36 | 73 |
| claude spawned -> engaged row, answering oracle | 6 | 286 | 308 | 414 |
| TOTAL bundle ts -> engaged row, all | 34 | 156 | 412 | 874 |
| TOTAL, no-prompt | 7 | 97 | 196 | 196 |
| TOTAL, real assistant turn | 20 | 116 | 412 | 874 |

The handoff head is before the bundle timestamp and so is invisible in this table; it is measurable only on the move lane, where the worker stamps `actuate`.

### 3d. Recover pool, `fleet/one-<start>-<sid>/results.tsv` — MEASURED

480 `one-*` dirs, 467 result rows. Duration = dir-name start -> results row timestamp (the row is written when the recycle is armed, not when it engages).

| mechanism / verdict | n | median s | p90 s | max s |
|---|---|---|---|---|
| recycle-in-place/FAILED | 173 | 7 | 127 | 824 |
| parked | 172 | 9 | 247 | 2394 |
| recycle-in-place/RECOVERED | 53 | 99 | 697 | 2028 |
| recycle-in-place/PARTIAL | 17 | 147 | 222 | 1202 |
| recycle-in-place/HELD:bg-work | 9 | 25 | 209 | 739 |
| parked/capped | 9 | 155 | 286 | 307 |
| spawn/RECOVERED | 8 | 53 | 230 | 499 |
| nudge-in-place/RECOVERED | 6 | 30 | 33 | 84 |
| start -> `recycle-engaged` row, recycle-in-place (joined) | 11 | 215 | 320 | 410 |

- 53 of 467 rows (11%) are RECOVERED by an in-place recycle; 173 (37%) are FAILED and 181 (39%) parked. The failure and park rates are outside this slot, but they mean most recover-pool wall time is not spent rotating.
- Overlap of `--one` windows (start -> results row) for the 281 recycle-mechanism rows: max 10 concurrent; time at 1x = 14,758 s, 2x = 1,838 s, 3x = 1,070 s, 4x = 702 s, 5x-10x = 1,158 s. So 76% of busy seconds had one run in flight. The windows include any slot queueing inside lr-fleet, so this bounds launches in flight, not sessions actuating. MEASURED; whether 1x reflects the cap or the demand is not in these records.

## 4. Which step dominates

| rotation | total | 1st | 2nd | 3rd |
|---|---|---|---|---|
| median session (7f5deb68) | 176 s | handoff head 70 s (40%) | watcher proof 33 s (19%) | shell wait 22 s (12%) |
| p90 = max session (deaa242a) | 385 s | slot wait 167 s (43%) | shell wait 133 s (35%) | watcher proof 28 s (7%) |
| fastest wave-2 session without its queue (4d059264, 287 - 167) | 120 s | watcher proof 69 s | shell wait 13 s | exit 9 s |

- Median: the pre-bundle head of `lr-handoff.sh`, a stall whose cause is not in the records. If it is absent (as in wave 2), the median rotation's largest step becomes the exit/shell-wait pair (25-45 s) and the watcher's proof (23-33 s). MEASURED.
- p90: the slot queue. It is a fixed width (`WIDTH` from `plan.json .slots`, else `LR_MOVE_SLOTS:-4`, lr-move-worker.sh:50), not a memory measurement; the slot is held until the first proof read (:168), so wave 2 waited for wave 1's whole rotation. READ + MEASURED.
- Corpus-wide (3c, n=29-34): exit + shell wait is the largest median step at 43 s of a 156 s median total.

## 5. Batch wall time versus sum of per-session times

MEASURED, one batch.

| quantity | value |
|---|---|
| request/plan written (`plan.json .ts`, `request.claimed.json`) | 06:05:34 |
| poller tick that started the batch (`poller.log: 06:07:03 MOVE-BATCH started pid 73895`; previous tick 06:05:16) | 06:07:03 (+89 s) |
| admit (`admit.json`), first worker spawned | 06:07:04, 06:07:06 |
| last per-session result | 06:13:33 |
| `summary.json` written, its own `wall_s` | 06:14:17, 434 s (counted from 06:07:03) |
| operator-visible total, request -> summary | 523 s (8.7 min) |
| worker window, first spawned -> last result | 387 s |
| sum of per-session spawned -> result | 1751 s -> 4.53x (queue time counted) |
| sum of per-session slot -> result (work only) | 1243 s -> 3.22x |
| sum of slot-held time (slot -> proof-first) | 1188 s -> 3.07 slots busy of 4 |

- Serial execution of the same per-session work would have been 1243 s; the batch did it in 387 s. Effective parallelism 3.2x for 7 sessions at width 4.
- Outside the workers: 89 s (17% of 523 s) queued for the next launchd tick, 44 s (8%) between the last result and the summary (the seven `*.guard.log` files are stamped 06:14:06..06:14:16; 06:13:33 -> 06:14:06 is unaccounted in the records).
- `batch.log` shows the batch runner's summary step failing under the deployment shell: `lr-move-batch.sh: command substitution: line 84: syntax error near unexpected token 'newline'` ... `case "${f##*/}" in plan.json|admit.json|summary.json|request*.json'`, and `summary.json` then says `"verdicts":"none"` and `done: no rows` although all 7 per-session files say MOVED. READ. The repo's own rule file names this class (`/bin/bash` 3.2 under launchd, `case` inside `$( )`).

## 6. Does this axis support "memory is the bottleneck"?

No, for the one batch that has step records.

- The memory read admitted all 7 in under 1 s each; the ledger rows either side of the batch read `reclaimable 34.29GB (floor 4GB) · compressor segments 4.16% of limit` (handoffs.jsonl 06:12:25) and `33.52GB ... 4.13%` (06:26:30). READ.
- 504 of 1751 session-seconds were the width-4 slot queue. That cap is static; nothing in the records shows memory setting it.
- `uptime` at the time of this analysis (2026-10-06 01:31 local): load averages 33.77 38.38 46.86 on 10 CPUs. MEASURED now, not at batch time. CPU contention is the candidate for the wave-1 stall and for the 5x slower recycle gates in wave 1; that is INFERRED and needs a timestamped run to confirm.

## 7. Alternatives considered

- "Wave 1 was slow because its transcripts are larger": rejected. Sizes 1.7-3.6 MB vs 0.5-1.6 MB (`confirm_len`), and all four left the head in the same second regardless of size.
- "The launcher (`lr-fire-resume.sh`) is slow before it spawns claude": rejected. zsh history shows the line started 0-2 s before the launcher's first event (n=7), and 3c gives 1 s median (n=29).
- "The 134 s gap is claude still exiting": not decided. The watcher saw no claude on the tty and judged the pane at a shell, yet the shell did not execute the typed line for 134 s. Records do not show what ran on the tty in between (shell hooks after exit, the dialog's "stop tasks" teardown, or a slow prompt under load).
- "The slot width is the only reason for 3.2x": partly. Removing the queue alone would have put wave 2's sessions at 120-218 s, but wave 1 shows 4 concurrent handoffs running 6x slower than 3, so wider is not guaranteed faster on this host.

## 8. Uncertainties

- n=1 batch, n=7 sessions for every move-lane step. No second batch exists to compare.
- Cause of the 69-70 s handoff head: unresolved. It lies in lr-handoff.sh lines 1-968 (before `TS=` at :968); nothing there logs a time.
- Cause of the shell-wait gap (13-134 s): unresolved, see section 7.
- The zsh-history join is by watcher pid. Six of the seven lines were confirmed by grep on the batch id; deaa242a's (06:12:36) matched by pid only and agrees with its launcher's first event at 06:12:38.
- Watcher `lstart`, bundle and ledger timestamps have 1 s resolution; steps under 3 s in those columns are +/-1 s.
- Section 3d durations end when the recycle is armed, not engaged; only 11 rows join to an engaged row.
- The 15 s "alive past boot" wait and the 5 s stable re-read (LR_MOVE_STABLE_S, lr-move-worker.sh:171) are fixed costs read from source and log text, not separately timed.

## 9. Changes this axis suggests (conviction = probability correct and safe as stated)

| change | conviction | basis |
|---|---|---|
| Add ms events to the move worker and watcher for: handoff start, bundle created, /exit sent, claude pid gone, shell executed the launcher's first line, claude pid up. Records today cannot place 282 s + 391 s of this batch. | 85% | sections 2, 8 |
| Start a move batch at request time instead of at the next launchd tick (89 s of 523 s here; tick spacing 107 s between 06:05:16 and 06:07:03). | 65% | section 5 |
| Fix the `case` inside `$( )` at lr-move-batch.sh:83-84 so the summary counts verdicts under /bin/bash 3.2. | 85% | batch.log, section 5 |
| Raise the move slot width above 4, or release the slot when the old process has exited instead of at first proof. Saves up to 167 s per queued session here. | 45% | section 4; risk: wave 1 (4 wide) ran its handoff 6x slower than wave 2 (3 wide), cause unknown |
| Find and remove what delays the shell reading the typed relaunch (median 32 s, max 134 s; 42 s median over n=34 corpus-wide). No concrete edit yet. | 55% | sections 2, 3c |
| Shorten the no-prompt process proof (15 s alive-past-boot plus 5 s stable re-read plus polling: 34-80 s per session here). | 35% | section 2; these waits exist to catch a relaunch that dies at boot |

## 10. Left behind

`/tmp/lr_walltime.py`, `/tmp/lr_walltime.out`, `/tmp/lr_walltime.err` (empty). Nothing else written; no session, pane, lr-* command or git state was touched.
